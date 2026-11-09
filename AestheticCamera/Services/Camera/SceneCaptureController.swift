import Foundation
import CoreMotion
import UIKit

protocol SceneCaptureDelegate: AnyObject {
    func sceneCaptureDidCapture(_ controller: SceneCaptureController, photoNumber: Int)
    func sceneCaptureDidComplete(_ controller: SceneCaptureController, photos: [UIImage])
    func sceneCaptureDidCancel(_ controller: SceneCaptureController)
    func sceneCaptureDidUpdateGuide(_ controller: SceneCaptureController, offset: CGFloat)
}

final class SceneCaptureController {
    weak var delegate: SceneCaptureDelegate?

    private let motionManager = CMMotionManager()
    private var capturedPhotos: [UIImage] = []

    private(set) var isCapturing = false

    // Pan tracking
    private var startYaw: Double = 0
    private var currentYaw: Double = 0
    private var isFirstReading = true

    // Visual guide range (in radians, ~60 degrees total = 30 degrees each side)
    private let maxRotation: Double = 0.52  // ~30 degrees

    // MARK: - Public API

    func startCapture() {
        guard !isCapturing else { return }
        guard motionManager.isDeviceMotionAvailable else {
            print("Device motion not available")
            return
        }

        isCapturing = true
        capturedPhotos = []
        isFirstReading = true

        motionManager.deviceMotionUpdateInterval = 1.0 / 60.0
        motionManager.startDeviceMotionUpdates(using: .xArbitraryZVertical, to: .main) { [weak self] motion, error in
            guard let self = self, let motion = motion else { return }
            self.processMotion(motion)
        }
    }

    func stopCapture() {
        motionManager.stopDeviceMotionUpdates()
        isCapturing = false
    }

    func cancelCapture() {
        stopCapture()
        capturedPhotos = []
        delegate?.sceneCaptureDidCancel(self)
    }

    func capturePhoto() {
        // Called when user taps capture - delegate will handle the actual capture
        delegate?.sceneCaptureDidCapture(self, photoNumber: capturedPhotos.count + 1)
    }

    func photoWasCaptured(_ image: UIImage) {
        capturedPhotos.append(image)
    }

    func finishCapture() {
        guard capturedPhotos.count >= 2 else {
            // Need at least 2 photos
            return
        }
        stopCapture()
        delegate?.sceneCaptureDidComplete(self, photos: capturedPhotos)
    }

    var photoCount: Int {
        capturedPhotos.count
    }

    // MARK: - Private

    private func processMotion(_ motion: CMDeviceMotion) {
        let yaw = motion.attitude.yaw

        if isFirstReading {
            startYaw = yaw
            currentYaw = yaw
            isFirstReading = false
            delegate?.sceneCaptureDidUpdateGuide(self, offset: 0)
            return
        }

        currentYaw = yaw

        // Calculate offset from start (-1 to 1 range)
        var delta = currentYaw - startYaw

        // Handle wraparound at ±π
        if delta > .pi { delta -= 2 * .pi }
        if delta < -.pi { delta += 2 * .pi }

        // Normalize to -1 to 1 range
        let normalizedOffset = CGFloat(max(-1, min(1, delta / maxRotation)))

        delegate?.sceneCaptureDidUpdateGuide(self, offset: normalizedOffset)
    }
}
