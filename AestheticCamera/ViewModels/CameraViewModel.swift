import SwiftUI
import AVFoundation
import Combine

/// Capture mode selection
enum CaptureMode: String, CaseIterable, Identifiable {
    case singleShot = "Single Shot"
    case sceneCapture = "Scene Capture"
    case smartPan = "Smart Pan"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .singleShot: return "camera"
        case .sceneCapture: return "pano"
        case .smartPan: return "viewfinder"
        }
    }

    var description: String {
        switch self {
        case .singleShot: return "Take a photo, get AI crop suggestion"
        case .sceneCapture: return "Pan camera, AI picks best shot"
        case .smartPan: return "Auto-detect subjects, capture 1x + 4x"
        }
    }
}

@MainActor
final class CameraViewModel: ObservableObject {
    // MARK: - Published Properties

    @Published var compositionScore: CompositionScore = .zero
    @Published var compositionGuide: CompositionGuide = .none
    @Published var subjectBounds: CGRect? = nil  // Detected subject bounding box (normalized 0-1)
    @Published var currentLens: CameraLens = .wide
    @Published var autoCaptureEnabled: Bool = false
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

    // Capture mode
    @Published var captureMode: CaptureMode = .singleShot

    // Crop suggestion state (v3 single shot)
    @Published var showCropPreview: Bool = false
    @Published var cropSuggestion: CropSuggestion?
    @Published var isRequestingCrop: Bool = false
    @Published var imageForCrop: UIImage?

    // Scene capture state (v4)
    @Published var isSceneCaptureActive: Bool = false
    @Published var sceneCapturedCount: Int = 0
    @Published var sceneGuideOffset: CGFloat = 0  // -1 to 1, for visual guide
    @Published var isProcessingScene: Bool = false
    @Published var showSceneResult: Bool = false
    @Published var sceneResultImage: UIImage?
    @Published var sceneResultCrop: CropSuggestion?
    @Published var sceneResultReason: String = ""

    // Smart pan state (v5)
    @Published var smartPanState: SmartPanState = .idle
    @Published var showHoldStillOverlay: Bool = false
    @Published var smartPanPairsCount: Int = 0
    @Published var isProcessingSmartPan: Bool = false

    // Auto-capture settings
    @Published var minimumScoreThreshold: Float = 0.70
    @Published var captureCooldown: TimeInterval = 2.0

    // Composition weights (for advanced settings)
    @Published var rotWeight: Float = 0.35
    @Published var goldenWeight: Float = 0.25
    @Published var linesWeight: Float = 0.20
    @Published var nimaWeight: Float = 0.20

    // Haptic settings
    @Published var hapticEnabled: Bool = true

    // Aspect ratio for crop suggestions (default 4:3 to match Apple Camera)
    @Published var selectedAspectRatio: AspectRatio = .fourThree

    // MARK: - Services

    let cameraService = CameraService()
    private let compositionEngine = CompositionEngine()
    private let compositionGuideAnalyzer = CompositionGuideAnalyzer()
    private let autoCaptureController = AutoCaptureController()
    private let motionAnalyzer = MotionAnalyzer()
    private let sceneCaptureController = SceneCaptureController()
    private let smartPanController = SmartPanController()

    // Scene capture photos storage
    private var pendingSceneCapture = false
    private var pendingSmartPanCapture = false

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
        sceneCaptureController.delegate = self
        smartPanController.delegate = self
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

    func toggleAutoCapture() {
        autoCaptureEnabled.toggle()
        autoCaptureController.setEnabled(autoCaptureEnabled)
    }

    func captureManually() {
        triggerCapture()
    }

    func updateSettings() {
        autoCaptureController.minimumScoreThreshold = minimumScoreThreshold
        autoCaptureController.cooldownDuration = captureCooldown
    }

    // MARK: - Crop Suggestion

    func requestCropSuggestion() {
        guard let image = lastCapturedImage else {
            errorMessage = "No image to analyze. Capture a photo first."
            return
        }

        imageForCrop = image
        isRequestingCrop = true

        Task {
            do {
                let suggestion = try await ClaudeAPIService.shared.suggestCrop(for: image, aspectRatio: selectedAspectRatio)
                await MainActor.run {
                    self.cropSuggestion = suggestion
                    self.isRequestingCrop = false
                    self.showCropPreview = true
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = error.localizedDescription
                    self.isRequestingCrop = false
                }
            }
        }
    }

    func acceptCrop(_ croppedImage: UIImage) {
        lastCapturedImage = croppedImage
        showCropPreview = false
        cropSuggestion = nil
        imageForCrop = nil

        // Save cropped image to photo library
        PhotoLibraryService.shared.savePhoto(croppedImage) { [weak self] result in
            if case .failure(let error) = result {
                self?.errorMessage = "Failed to save cropped photo: \(error.localizedDescription)"
            }
        }
    }

    func rejectCrop() {
        showCropPreview = false
        cropSuggestion = nil
        imageForCrop = nil
    }

    // MARK: - Scene Capture (v4)

    func startSceneCapture() {
        guard !isSceneCaptureActive else { return }

        isSceneCaptureActive = true
        sceneCapturedCount = 0
        sceneGuideOffset = 0

        sceneCaptureController.startCapture()
    }

    func cancelSceneCapture() {
        sceneCaptureController.cancelCapture()
        isSceneCaptureActive = false
        sceneCapturedCount = 0
        sceneGuideOffset = 0
    }

    func captureScenePhoto() {
        guard isSceneCaptureActive else { return }
        sceneCaptureController.capturePhoto()
    }

    func finishSceneCapture() {
        guard isSceneCaptureActive, sceneCapturedCount >= 2 else { return }
        sceneCaptureController.finishCapture()
    }

    func saveSceneResult() {
        guard let image = sceneResultImage, let crop = sceneResultCrop else { return }

        // Apply crop and save
        if let croppedImage = applyCrop(to: image, with: crop) {
            PhotoLibraryService.shared.savePhoto(croppedImage) { [weak self] result in
                DispatchQueue.main.async {
                    switch result {
                    case .success:
                        self?.lastCapturedImage = croppedImage
                        self?.captureCount += 1
                    case .failure(let error):
                        self?.errorMessage = "Failed to save: \(error.localizedDescription)"
                    }
                }
            }
        }

        dismissSceneResult()
    }

    func discardSceneResult() {
        dismissSceneResult()
    }

    private func dismissSceneResult() {
        showSceneResult = false
        sceneResultImage = nil
        sceneResultCrop = nil
        sceneResultReason = ""
    }

    // MARK: - Smart Pan (v5)

    func startSmartPan() {
        guard smartPanState == .idle else { return }
        smartPanController.startSmartPan()
    }

    func stopSmartPan() {
        smartPanController.stopSmartPan()
    }

    func cancelSmartPan() {
        smartPanController.cancelSmartPan()
        smartPanState = .idle
        showHoldStillOverlay = false
        smartPanPairsCount = 0
    }

    func saveSmartPanResult() {
        // Similar to scene result - the result view will handle this
        dismissSceneResult()
    }

    private func processSmartPanPairs(_ pairs: [PhotoPair]) {
        isProcessingSmartPan = true

        // Collect all images: for each pair, we send both 1x and 4x
        var allImages: [UIImage] = []
        for pair in pairs {
            allImages.append(pair.widePhoto)
            allImages.append(pair.telephotoPhoto)
        }

        Task {
            do {
                let result = try await ClaudeAPIService.shared.analyzeSmartPanCaptures(
                    pairs: pairs,
                    aspectRatio: selectedAspectRatio
                )

                await MainActor.run {
                    self.isProcessingSmartPan = false
                    self.smartPanState = .idle

                    // Show result
                    self.sceneResultImage = result.selectedImage
                    self.sceneResultCrop = result.crop
                    self.sceneResultReason = result.reason
                    self.showSceneResult = true
                }
            } catch {
                await MainActor.run {
                    self.isProcessingSmartPan = false
                    self.smartPanState = .idle
                    self.errorMessage = error.localizedDescription
                }
            }
        }
    }

    private func applyCrop(to image: UIImage, with suggestion: CropSuggestion) -> UIImage? {
        guard let normalizedImage = normalizeOrientation(image) else { return nil }

        let imageWidth = normalizedImage.size.width * normalizedImage.scale
        let imageHeight = normalizedImage.size.height * normalizedImage.scale

        let cropRect = CGRect(
            x: suggestion.x * imageWidth,
            y: suggestion.y * imageHeight,
            width: suggestion.width * imageWidth,
            height: suggestion.height * imageHeight
        )

        guard let cgImage = normalizedImage.cgImage,
              let croppedCGImage = cgImage.cropping(to: cropRect) else { return nil }

        return UIImage(cgImage: croppedCGImage, scale: normalizedImage.scale, orientation: .up)
    }

    private func normalizeOrientation(_ image: UIImage) -> UIImage? {
        guard image.imageOrientation != .up else { return image }

        // Use UIGraphicsImageRenderer for better quality (uses optimal color space and format)
        let format = UIGraphicsImageRendererFormat()
        format.scale = image.scale
        format.preferredRange = .extended  // Preserve wide color gamut

        let renderer = UIGraphicsImageRenderer(size: image.size, format: format)
        let normalizedImage = renderer.image { context in
            image.draw(in: CGRect(origin: .zero, size: image.size))
        }

        return normalizedImage
    }

    private func processScenePhotos(_ photos: [UIImage]) {
        isProcessingScene = true

        Task {
            do {
                let result = try await ClaudeAPIService.shared.analyzeScene(photos: photos, aspectRatio: selectedAspectRatio)

                await MainActor.run {
                    self.isProcessingScene = false
                    self.isSceneCaptureActive = false

                    // Show result
                    let selectedIndex = min(result.selectedPhotoIndex, photos.count - 1)
                    self.sceneResultImage = photos[selectedIndex]
                    self.sceneResultCrop = result.crop
                    self.sceneResultReason = result.reason
                    self.showSceneResult = true
                }
            } catch {
                await MainActor.run {
                    self.isProcessingScene = false
                    self.isSceneCaptureActive = false
                    self.errorMessage = error.localizedDescription
                }
            }
        }
    }

    // MARK: - Private Methods

    private func analyzeFrame(pixelBuffer: CVPixelBuffer, timestamp: CMTime) {
        // Cancel previous analysis if still running
        analysisTask?.cancel()

        analysisTask = Task { [weak self] in
            guard let self = self else { return }

            let rawScore = await compositionEngine.analyze(pixelBuffer: pixelBuffer)

            // Get saliency center for motion analysis and composition guidance
            let saliencyResult = await compositionEngine.lastSaliencyResult
            let panningState = motionAnalyzer.detectPanning(
                currentTimestamp: timestamp,
                saliencyCenter: saliencyResult.attentionCenter
            )

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

                // Feed saliency data to smart pan controller if active
                if self.smartPanState == .panning {
                    // Derive confidence from presence and size of salient objects
                    let confidence: Float = saliencyResult.salientObjects.isEmpty ? 0.0 : 0.7
                    self.smartPanController.processSaliencyResult(
                        center: saliencyResult.attentionCenter,
                        confidence: confidence
                    )
                }

                self.checkAutoCapture(score: rawScore, panningState: panningState)
            }
        }
    }

    private func updateSubjectBounds(from saliencyResult: SaliencyResult) {
        // Find largest salient object
        guard let largestObject = saliencyResult.salientObjects.max(by: {
            $0.boundingBox.width * $0.boundingBox.height <
            $1.boundingBox.width * $1.boundingBox.height
        }) else {
            // No objects detected - gradually fade out
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

        // Hints are different - track as pending
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

    private func checkAutoCapture(score: CompositionScore, panningState: PanningState) {
        guard autoCaptureEnabled else { return }

        // Don't capture while actively panning
        if panningState == .activePanning { return }

        let decision = autoCaptureController.shouldCapture(score: score)

        if decision.shouldCapture {
            triggerCapture()
        }
    }

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

        // Capture photo
        cameraService.capturePhoto()
        autoCaptureController.recordCapture()
    }

    private func handleCapturedPhoto(_ image: UIImage) {
        // Check if this is a scene capture photo
        if isSceneCaptureActive && pendingSceneCapture {
            pendingSceneCapture = false
            sceneCaptureController.photoWasCaptured(image)
            sceneCapturedCount = sceneCaptureController.photoCount
            return
        }

        // Check if this is a smart pan capture photo
        if pendingSmartPanCapture {
            pendingSmartPanCapture = false
            smartPanController.photoWasCaptured(image)
            return
        }

        // Regular single shot mode
        lastCapturedImage = image
        captureCount += 1

        // In single shot mode, don't auto-save - let user decide via crop preview
        // Only save if auto-capture is enabled (user wants hands-free operation)
        if autoCaptureEnabled {
            PhotoLibraryService.shared.savePhoto(image) { [weak self] result in
                switch result {
                case .success:
                    print("Photo saved successfully")
                case .failure(let error):
                    self?.errorMessage = "Failed to save photo: \(error.localizedDescription)"
                }
            }
        }
    }
}

// MARK: - SceneCaptureDelegate

extension CameraViewModel: SceneCaptureDelegate {
    nonisolated func sceneCaptureDidCapture(_ controller: SceneCaptureController, photoNumber: Int) {
        Task { @MainActor in
            // Mark that we're expecting a scene capture photo
            pendingSceneCapture = true

            // Haptic feedback
            if hapticEnabled {
                feedbackGenerator.impactOccurred()
            }

            // Visual feedback
            showCaptureFlash = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                self.showCaptureFlash = false
            }

            // Capture the photo
            cameraService.capturePhoto()
        }
    }

    nonisolated func sceneCaptureDidComplete(_ controller: SceneCaptureController, photos: [UIImage]) {
        Task { @MainActor in
            processScenePhotos(photos)
        }
    }

    nonisolated func sceneCaptureDidCancel(_ controller: SceneCaptureController) {
        Task { @MainActor in
            isSceneCaptureActive = false
            sceneCapturedCount = 0
            sceneGuideOffset = 0
        }
    }

    nonisolated func sceneCaptureDidUpdateGuide(_ controller: SceneCaptureController, offset: CGFloat) {
        Task { @MainActor in
            sceneGuideOffset = offset
        }
    }
}

// MARK: - SmartPanControllerDelegate

extension CameraViewModel: SmartPanControllerDelegate {
    nonisolated func smartPanController(_ controller: SmartPanController, didChangeState state: SmartPanState) {
        Task { @MainActor in
            self.smartPanState = state
            self.showHoldStillOverlay = state.shouldShowHoldStill
        }
    }

    nonisolated func smartPanController(_ controller: SmartPanController, didDetectSubject subject: DetectedSubject) {
        Task { @MainActor in
            // Subject detected - haptic will be triggered by the controller
        }
    }

    nonisolated func smartPanController(_ controller: SmartPanController, requestCaptureForSubject subject: DetectedSubject, lens: CameraLens) {
        Task { @MainActor in
            pendingSmartPanCapture = true

            // Visual feedback
            showCaptureFlash = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                self.showCaptureFlash = false
            }

            // Capture the photo
            cameraService.capturePhoto()
        }
    }

    nonisolated func smartPanController(_ controller: SmartPanController, requestSwitchToLens lens: CameraLens) {
        Task { @MainActor in
            currentLens = lens
            cameraService.switchLens(to: lens)
        }
    }

    nonisolated func smartPanController(_ controller: SmartPanController, didCompletePair pair: PhotoPair) {
        Task { @MainActor in
            smartPanPairsCount = controller.pairCount
        }
    }

    nonisolated func smartPanController(_ controller: SmartPanController, didFinishWithPairs pairs: [PhotoPair]) {
        Task { @MainActor in
            processSmartPanPairs(pairs)
        }
    }

    nonisolated func smartPanControllerNeedsHapticFeedback(_ controller: SmartPanController) {
        Task { @MainActor in
            if hapticEnabled {
                feedbackGenerator.impactOccurred()
            }
        }
    }
}

// MARK: - CameraServiceDelegate

extension CameraViewModel: CameraServiceDelegate {
    nonisolated func cameraService(_ service: CameraService, didOutput pixelBuffer: CVPixelBuffer, timestamp: CMTime) {
        Task { @MainActor in
            analyzeFrame(pixelBuffer: pixelBuffer, timestamp: timestamp)
        }
    }

    nonisolated func cameraService(_ service: CameraService, didCapturePhoto image: UIImage) {
        Task { @MainActor in
            handleCapturedPhoto(image)
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
}
