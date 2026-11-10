import SwiftUI
import AVFoundation
import Combine

@MainActor
final class CameraViewModel: ObservableObject {
    // MARK: - Published Properties

    @Published var compositionScore: CompositionScore = .zero
    @Published var compositionGuide: CompositionGuide = .none
    @Published var subjectBounds: CGRect? = nil  // Detected subject bounding box (normalized 0-1)
    @Published var currentLens: CameraLens = .wide
    @Published var showGrid: Bool = true
    @Published var showLevelIndicator: Bool = true
    @Published var showHints: Bool = false  // Composition hints off by default
    @Published var gridType: GridType = .ruleOfThirds
    @Published var showCaptureFlash: Bool = false
    @Published var showSettings: Bool = false
    @Published var showScoreDetails: Bool = false
    @Published var lastCapturedImage: UIImage?
    @Published var captureCount: Int = 0
    @Published var errorMessage: String?

    // Capture options
    @Published var timerSeconds: Int = 0
    @Published var flashMode: AVCaptureDevice.FlashMode = .off
    @Published var burstEnabled: Bool = false
    @Published var isExposureLocked: Bool = false
    @Published var portraitEnabled: Bool = false
    @Published var countdown: Int?

    // Tap-to-focus state
    @Published var focusIndicatorPoint: CGPoint?
    @Published var exposureBias: Float = 0
    private var countdownTask: Task<Void, Never>?
    private var indicatorTask: Task<Void, Never>?

    // Composition weights (for advanced settings)
    @Published var rotWeight: Float = 0.35
    @Published var goldenWeight: Float = 0.25
    @Published var linesWeight: Float = 0.20
    @Published var nimaWeight: Float = 0.20

    // Haptic settings
    @Published var hapticEnabled: Bool = true

    // Aspect ratio for the framing overlay
    @Published var selectedAspectRatio: AspectRatio = .fourThree

    // MARK: - Services

    let cameraService = CameraService()
    private let compositionEngine = CompositionEngine()
    private let compositionGuideAnalyzer = CompositionGuideAnalyzer()

    // MARK: - Private Properties

    private var analysisTask: Task<Void, Never>?
    private let feedbackGenerator = UIImpactFeedbackGenerator(style: .medium)

    // Score smoothing (EMA)
    private var smoothedScore: CompositionScore = .zero
    private var smoothedGuideQuality: Float = 0.5
    private let smoothingFactor: Float = 0.06 // Lower = smoother, higher = more responsive

    // Guidance stability (prevent rapid hint changes)
    private var lastStableGuide: CompositionGuide = .none
    private var lastHintChangeTime: Date = .distantPast
    private let minimumHintInterval: TimeInterval = 2.0 // Seconds between hint changes
    private var pendingGuide: CompositionGuide?
    private var pendingGuideStartTime: Date?
    private let pendingConfirmationTime: TimeInterval = 0.8 // Seconds a new hint must persist before showing

    // Subject bounds smoothing
    private var smoothedBounds: CGRect?
    private let boundsSmoothingFactor: CGFloat = 0.15 // Lower = smoother
    private let minimumSubjectSize: CGFloat = 0.02 // Ignore tiny detections (2% of frame)

    // MARK: - Initialization

    init() {
        cameraService.delegate = self
        feedbackGenerator.prepare()
    }

    // MARK: - Public API

    func startCamera() {
        cameraService.configure()
        cameraService.startSession()
    }

    func stopCamera() {
        cameraService.stopSession()
        analysisTask?.cancel()
    }

    func switchLens(to lens: CameraLens) {
        currentLens = lens
        cameraService.switchLens(to: lens)
    }

    func captureManually() {
        guard countdownTask == nil else { return }
        guard timerSeconds > 0 else {
            triggerCapture()
            return
        }

        countdownTask = Task { [weak self] in
            guard let self else { return }
            for remaining in stride(from: self.timerSeconds, through: 1, by: -1) {
                self.countdown = remaining
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }
            self.countdown = nil
            self.countdownTask = nil
            self.triggerCapture()
        }
    }

    func cycleTimer() {
        timerSeconds = timerSeconds == 0 ? 3 : (timerSeconds == 3 ? 10 : 0)
    }

    func cycleFlash() {
        switch flashMode {
        case .off: flashMode = .auto
        case .auto: flashMode = .on
        default: flashMode = .off
        }
    }

    func toggleBurst() {
        burstEnabled.toggle()
    }

    func togglePortrait() {
        portraitEnabled.toggle()
    }

    func toggleExposureLock() {
        isExposureLocked.toggle()
        cameraService.setAutoLocked(isExposureLocked)
    }

    func focus(atViewPoint point: CGPoint, devicePoint: CGPoint) {
        if isExposureLocked {
            isExposureLocked = false
        }
        focusIndicatorPoint = point
        cameraService.focus(at: devicePoint)
        scheduleIndicatorHide()
    }

    func setExposureBias(_ value: Float) {
        exposureBias = value
        cameraService.setExposureBias(value)
        scheduleIndicatorHide()
    }

    private func scheduleIndicatorHide() {
        indicatorTask?.cancel()
        indicatorTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            guard !Task.isCancelled else { return }
            self?.focusIndicatorPoint = nil
        }
    }

    // MARK: - Private Methods

    private func triggerCapture() {
        // Haptic feedback
        if hapticEnabled {
            feedbackGenerator.impactOccurred()
        }

        // Visual feedback
        showCaptureFlash = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            self.showCaptureFlash = false
        }

        cameraService.capturePhoto(flashMode: flashMode, burstCount: burstEnabled ? 5 : 1, portrait: portraitEnabled)
    }

    private func handleCapturedPhoto(_ data: Data) {
        // Preview only; the saved file is the original encoded data
        if let preview = UIImage(data: data) {
            lastCapturedImage = preview
        }
        captureCount += 1

        PhotoLibraryService.shared.savePhoto(data) { [weak self] result in
            if case .failure(let error) = result {
                self?.errorMessage = "Failed to save photo: \(error.localizedDescription)"
            }
        }
    }

    private func analyzeFrame(pixelBuffer: CVPixelBuffer, timestamp: CMTime) {
        // Cancel previous analysis if still running
        analysisTask?.cancel()

        analysisTask = Task { [weak self] in
            guard let self = self else { return }

            let rawScore = await compositionEngine.analyze(pixelBuffer: pixelBuffer)

            // Get saliency center for composition guidance
            let saliencyResult = await compositionEngine.lastSaliencyResult

            // Calculate composition guidance
            let rawGuide = compositionGuideAnalyzer.analyze(
                saliencyResult: saliencyResult,
                currentLens: currentLens
            )

            await MainActor.run {
                // Apply exponential moving average smoothing
                self.smoothedScore = self.applySmoothing(newScore: rawScore)
                self.compositionScore = self.smoothedScore

                // Smooth the guide quality for stable display
                self.smoothedGuideQuality = self.smoothingFactor * rawGuide.compositionQuality +
                    (1.0 - self.smoothingFactor) * self.smoothedGuideQuality

                // Apply stability logic to hints (prevent rapid changes)
                let stableGuide = self.stabilizeGuide(rawGuide: rawGuide)

                // Update guide with smoothed quality and stable hints
                self.compositionGuide = CompositionGuide(
                    horizontalHint: stableGuide.horizontalHint,
                    verticalHint: stableGuide.verticalHint,
                    suggestedLens: stableGuide.suggestedLens,
                    compositionQuality: self.smoothedGuideQuality,
                    subjectPosition: rawGuide.subjectPosition,
                    idealPosition: rawGuide.idealPosition
                )

                // Update subject bounds from saliency (largest salient object)
                self.updateSubjectBounds(from: saliencyResult)
            }
        }
    }

    private func updateSubjectBounds(from saliencyResult: SaliencyResult) {
        // Find largest salient object
        guard let largestObject = saliencyResult.salientObjects.max(by: {
            $0.boundingBox.width * $0.boundingBox.height <
            $1.boundingBox.width * $1.boundingBox.height
        }) else {
            // No objects detected - clear bounds
            if smoothedBounds != nil {
                smoothedBounds = nil
                subjectBounds = nil
            }
            return
        }

        let newBounds = largestObject.boundingBox
        let objectSize = newBounds.width * newBounds.height

        // Filter out tiny detections (likely noise)
        guard objectSize >= minimumSubjectSize else {
            return // Keep previous bounds, don't update with noise
        }

        // Apply smoothing
        if let current = smoothedBounds {
            let alpha = boundsSmoothingFactor
            smoothedBounds = CGRect(
                x: alpha * newBounds.minX + (1 - alpha) * current.minX,
                y: alpha * newBounds.minY + (1 - alpha) * current.minY,
                width: alpha * newBounds.width + (1 - alpha) * current.width,
                height: alpha * newBounds.height + (1 - alpha) * current.height
            )
        } else {
            // First detection - use directly
            smoothedBounds = newBounds
        }

        subjectBounds = smoothedBounds
    }

    private func applySmoothing(newScore: CompositionScore) -> CompositionScore {
        let alpha = smoothingFactor
        let oneMinusAlpha = 1.0 - alpha

        return CompositionScore(
            ruleOfThirds: alpha * newScore.ruleOfThirds + oneMinusAlpha * smoothedScore.ruleOfThirds,
            goldenRatio: alpha * newScore.goldenRatio + oneMinusAlpha * smoothedScore.goldenRatio,
            leadingLines: alpha * newScore.leadingLines + oneMinusAlpha * smoothedScore.leadingLines,
            aestheticQuality: alpha * newScore.aestheticQuality + oneMinusAlpha * smoothedScore.aestheticQuality
        )
    }

    private func stabilizeGuide(rawGuide: CompositionGuide) -> CompositionGuide {
        let now = Date()

        // First hint should appear immediately (no delay on app start)
        let isFirstHint = lastHintChangeTime == .distantPast
        if isFirstHint {
            lastStableGuide = rawGuide
            lastHintChangeTime = now
            return lastStableGuide
        }

        // Check if the new guide hints differ from the stable guide
        let hintsChanged = rawGuide.horizontalHint != lastStableGuide.horizontalHint ||
                          rawGuide.verticalHint != lastStableGuide.verticalHint ||
                          rawGuide.suggestedLens != lastStableGuide.suggestedLens

        if !hintsChanged {
            // Hints match stable guide, reset pending
            pendingGuide = nil
            pendingGuideStartTime = nil
            return lastStableGuide
        }

        // Check if enough time has passed since last hint change
        let timeSinceLastChange = now.timeIntervalSince(lastHintChangeTime)
        let canChangeHint = timeSinceLastChange >= minimumHintInterval

        if !canChangeHint {
            // Too soon to change, keep current
            return lastStableGuide
        }

        // Check if this is a new pending hint or continuation
        let pendingMatches = pendingGuide?.horizontalHint == rawGuide.horizontalHint &&
                            pendingGuide?.verticalHint == rawGuide.verticalHint &&
                            pendingGuide?.suggestedLens == rawGuide.suggestedLens

        if pendingMatches, let startTime = pendingGuideStartTime {
            // Same pending hint - check if it's been consistent long enough
            if now.timeIntervalSince(startTime) >= pendingConfirmationTime {
                // Confirmed! Update stable guide
                lastStableGuide = rawGuide
                lastHintChangeTime = now
                pendingGuide = nil
                pendingGuideStartTime = nil
            }
        } else {
            // New pending hint - start tracking
            pendingGuide = rawGuide
            pendingGuideStartTime = now
        }

        return lastStableGuide
    }
}

// MARK: - CameraServiceDelegate

extension CameraViewModel: CameraServiceDelegate {
    nonisolated func cameraService(_ service: CameraService, didOutput pixelBuffer: CVPixelBuffer, timestamp: CMTime) {
        Task { @MainActor in
            analyzeFrame(pixelBuffer: pixelBuffer, timestamp: timestamp)
        }
    }

    nonisolated func cameraService(_ service: CameraService, didCapturePhoto data: Data) {
        Task { @MainActor in
            handleCapturedPhoto(data)
        }
    }

    nonisolated func cameraServiceDidFail(_ service: CameraService, error: Error) {
        Task { @MainActor in
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - Grid Type

enum GridType: String, CaseIterable, Identifiable {
    case ruleOfThirds = "Rule of Thirds"
    case goldenRatio = "Golden Ratio"
    case goldenSpiral = "Golden Spiral"
    case diagonal = "Diagonal"
    case none = "None"

    var id: String { rawValue }

    var next: GridType {
        let all = GridType.allCases
        return all[(all.firstIndex(of: self)! + 1) % all.count]
    }
}
