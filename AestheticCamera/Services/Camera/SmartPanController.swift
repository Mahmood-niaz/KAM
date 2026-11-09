import Foundation
import CoreMotion
import UIKit
import CoreGraphics

/// Delegate protocol for SmartPanController events
protocol SmartPanControllerDelegate: AnyObject {
    func smartPanController(_ controller: SmartPanController, didChangeState state: SmartPanState)
    func smartPanController(_ controller: SmartPanController, didDetectSubject subject: DetectedSubject)
    func smartPanController(_ controller: SmartPanController, requestCaptureForSubject subject: DetectedSubject, lens: CameraLens)
    func smartPanController(_ controller: SmartPanController, requestSwitchToLens lens: CameraLens)
    func smartPanController(_ controller: SmartPanController, didCompletePair pair: PhotoPair)
    func smartPanController(_ controller: SmartPanController, didFinishWithPairs pairs: [PhotoPair])
    func smartPanControllerNeedsHapticFeedback(_ controller: SmartPanController)
}

/// Controller for smart panning mode with automatic subject detection and multi-lens capture
final class SmartPanController {
    weak var delegate: SmartPanControllerDelegate?

    // MARK: - State

    private(set) var state: SmartPanState = .idle {
        didSet {
            if state != oldValue {
                delegate?.smartPanController(self, didChangeState: state)
            }
        }
    }

    private(set) var detectedSubjects: [DetectedSubject] = []
    private(set) var capturedPairs: [PhotoPair] = []

    // MARK: - Motion

    private let motionManager = CMMotionManager()
    private var currentYaw: Double = 0
    private var lastSignificantYaw: Double = 0

    // MARK: - Subject Detection

    private var lastSaliencyCenter: CGPoint?
    private var lastSaliencyConfidence: Float = 0
    private var saliencyStableFrames: Int = 0

    // Thresholds
    private let yawDeduplicationTolerance: Double = 0.148  // ~8.5 degrees in radians
    private let saliencyConfidenceThreshold: Float = 0.4
    private let saliencyStabilityFramesRequired: Int = 5
    private let saliencyMovementThreshold: CGFloat = 0.08  // Max movement between frames

    // MARK: - Capture Sequence

    private var currentSubject: DetectedSubject?
    private var pendingWidePhoto: UIImage?
    private let lensSwitchDelay: TimeInterval = 0.4  // Time to wait for lens switch

    // MARK: - Public API

    func startSmartPan() {
        guard state == .idle else { return }

        detectedSubjects = []
        capturedPairs = []
        currentSubject = nil
        pendingWidePhoto = nil

        startMotionTracking()
        state = .panning
    }

    func stopSmartPan() {
        stopMotionTracking()

        if !capturedPairs.isEmpty {
            state = .processing
            delegate?.smartPanController(self, didFinishWithPairs: capturedPairs)
        }

        state = .idle
    }

    func cancelSmartPan() {
        stopMotionTracking()
        detectedSubjects = []
        capturedPairs = []
        currentSubject = nil
        pendingWidePhoto = nil
        state = .idle
    }

    /// Call this with each video frame's saliency result during panning
    func processSaliencyResult(center: CGPoint?, confidence: Float) {
        guard state == .panning else { return }

        // Check if we have a stable, confident saliency detection
        if let center = center, confidence >= saliencyConfidenceThreshold {
            if let lastCenter = lastSaliencyCenter {
                let movement = hypot(center.x - lastCenter.x, center.y - lastCenter.y)

                if movement < saliencyMovementThreshold {
                    // Stable detection
                    saliencyStableFrames += 1
                } else {
                    // Detection moved too much, reset
                    saliencyStableFrames = 0
                }
            }

            lastSaliencyCenter = center
            lastSaliencyConfidence = confidence

            // Check if stable enough to consider as subject
            if saliencyStableFrames >= saliencyStabilityFramesRequired {
                checkForNewSubject(at: center, confidence: confidence)
            }
        } else {
            // No valid detection
            saliencyStableFrames = 0
            lastSaliencyCenter = nil
            lastSaliencyConfidence = 0
        }
    }

    /// Call when a photo has been captured
    func photoWasCaptured(_ image: UIImage) {
        switch state {
        case .capturingWide:
            pendingWidePhoto = image
            // Switch to telephoto
            state = .switchingToTelephoto
            delegate?.smartPanController(self, requestSwitchToLens: .telephoto)

            // After delay, capture telephoto
            DispatchQueue.main.asyncAfter(deadline: .now() + lensSwitchDelay) { [weak self] in
                self?.captureTelephotPhoto()
            }

        case .capturingTelephoto:
            guard let subject = currentSubject,
                  let widePhoto = pendingWidePhoto else {
                // Something went wrong, return to panning
                state = .switchingBackToWide
                returnToPanning()
                return
            }

            // Create the photo pair
            let pair = PhotoPair(subject: subject, widePhoto: widePhoto, telephotoPhoto: image)
            capturedPairs.append(pair)
            delegate?.smartPanController(self, didCompletePair: pair)

            // Clear pending state
            currentSubject = nil
            pendingWidePhoto = nil

            // Switch back to wide lens and resume panning
            state = .switchingBackToWide
            returnToPanning()

        default:
            break
        }
    }

    var pairCount: Int {
        capturedPairs.count
    }

    // MARK: - Private Methods

    private func startMotionTracking() {
        guard motionManager.isDeviceMotionAvailable else { return }

        motionManager.deviceMotionUpdateInterval = 1.0 / 60.0  // 60 Hz

        motionManager.startDeviceMotionUpdates(using: .xArbitraryZVertical, to: .main) { [weak self] motion, error in
            guard let self = self, let motion = motion else { return }

            self.currentYaw = motion.attitude.yaw
        }
    }

    private func stopMotionTracking() {
        if motionManager.isDeviceMotionActive {
            motionManager.stopDeviceMotionUpdates()
        }
    }

    private func checkForNewSubject(at center: CGPoint, confidence: Float) {
        // Check if this yaw region has already been captured
        let isDuplicate = detectedSubjects.contains { $0.isInSameRegion(yaw: currentYaw, tolerance: yawDeduplicationTolerance) }

        if !isDuplicate {
            // New subject detected!
            let subject = DetectedSubject(
                yawAngle: currentYaw,
                timestamp: Date(),
                saliencyCenter: center,
                confidence: confidence
            )

            detectedSubjects.append(subject)
            delegate?.smartPanController(self, didDetectSubject: subject)

            // Trigger capture sequence
            triggerCaptureSequence(for: subject)
        }

        // Reset stable frames after checking
        saliencyStableFrames = 0
    }

    private func triggerCaptureSequence(for subject: DetectedSubject) {
        currentSubject = subject
        state = .subjectDetected

        // Haptic feedback
        delegate?.smartPanControllerNeedsHapticFeedback(self)

        // Brief pause to let user stabilize, then capture
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            guard let self = self, self.state == .subjectDetected else { return }
            self.captureWidePhoto()
        }
    }

    private func captureWidePhoto() {
        guard let subject = currentSubject else { return }
        state = .capturingWide
        delegate?.smartPanController(self, requestCaptureForSubject: subject, lens: .wide)
    }

    private func captureTelephotPhoto() {
        guard let subject = currentSubject else { return }
        state = .capturingTelephoto
        delegate?.smartPanController(self, requestCaptureForSubject: subject, lens: .telephoto)
    }

    private func returnToPanning() {
        delegate?.smartPanController(self, requestSwitchToLens: .wide)

        DispatchQueue.main.asyncAfter(deadline: .now() + lensSwitchDelay) { [weak self] in
            guard let self = self else { return }
            if self.state == .switchingBackToWide {
                self.state = .panning
            }
        }
    }
}
