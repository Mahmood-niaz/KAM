import AVFoundation
import UIKit

protocol CameraServiceDelegate: AnyObject {
    func cameraService(_ service: CameraService, didOutput pixelBuffer: CVPixelBuffer, timestamp: CMTime)
    func cameraService(_ service: CameraService, didCapturePhoto image: UIImage)
    func cameraServiceDidFail(_ service: CameraService, error: Error)
}

final class CameraService: NSObject {
    weak var delegate: CameraServiceDelegate?

    let captureSession = AVCaptureSession()
    private var videoDevice: AVCaptureDevice?
    private let videoOutput = AVCaptureVideoDataOutput()
    private let photoOutput = AVCapturePhotoOutput()

    // Track device orientation for photo capture
    private var currentOrientation: UIDeviceOrientation = .portrait

    private let sessionQueue = DispatchQueue(label: "com.aestheticcamera.session", qos: .userInitiated)
    private let videoQueue = DispatchQueue(label: "com.aestheticcamera.video", qos: .userInteractive)

    private(set) var isConfigured = false
    private(set) var currentLens: CameraLens = .wide

    // Actual zoom factors for each lens (determined from device)
    // For builtInTripleCamera, zoom factor 1.0 = ultra-wide, not wide!
    // These are the internal AVFoundation zoom factors, not user-facing values
    private var wideZoomFactor: CGFloat = 2.0        // 1x user-facing (physical lens)
    private var zoom2xFactor: CGFloat = 4.0          // 2x user-facing (digital crop of 1x)
    private var telephotoZoomFactor: CGFloat = 8.0   // 4x user-facing (physical telephoto lens)
    private var zoom8xFactor: CGFloat = 16.0         // 8x user-facing (digital crop of 4x)

    // MARK: - Setup

    func configure() {
        sessionQueue.async { [weak self] in
            self?.setupSession()
        }
    }

    /// Get the actual AVFoundation zoom factor for a given lens based on the current device
    func zoomFactor(for lens: CameraLens) -> CGFloat {
        switch lens {
        case .wide:
            return wideZoomFactor
        case .zoom2x:
            return zoom2xFactor
        case .telephoto:
            return telephotoZoomFactor
        case .zoom8x:
            return zoom8xFactor
        }
    }

    private func setupSession() {
        guard !isConfigured else { return }

        captureSession.beginConfiguration()
        captureSession.sessionPreset = .photo

        // Setup video device (triple camera preferred)
        guard setupVideoDevice() else {
            captureSession.commitConfiguration()
            return
        }

        // Setup video output for frame analysis
        setupVideoOutput()

        // Setup photo output for capture
        setupPhotoOutput()

        captureSession.commitConfiguration()
        isConfigured = true

        // Set initial zoom to 1x wide lens (not ultra-wide which is the default)
        if let device = videoDevice {
            do {
                try device.lockForConfiguration()
                device.videoZoomFactor = wideZoomFactor
                device.unlockForConfiguration()
                print("Initial zoom set to \(wideZoomFactor) (1x wide lens)")
            } catch {
                print("Failed to set initial zoom: \(error)")
            }
        }
    }

    private func setupVideoDevice() -> Bool {
        // Try to get triple camera first (iPhone Pro models)
        let discoverySession = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInTripleCamera, .builtInDualCamera, .builtInWideAngleCamera],
            mediaType: .video,
            position: .back
        )

        guard let device = discoverySession.devices.first else {
            let error = NSError(domain: "CameraService", code: 1,
                               userInfo: [NSLocalizedDescriptionKey: "No camera device found"])
            DispatchQueue.main.async {
                self.delegate?.cameraServiceDidFail(self, error: error)
            }
            return false
        }

        videoDevice = device

        do {
            let input = try AVCaptureDeviceInput(device: device)
            if captureSession.canAddInput(input) {
                captureSession.addInput(input)
            } else {
                return false
            }
        } catch {
            DispatchQueue.main.async {
                self.delegate?.cameraServiceDidFail(self, error: error)
            }
            return false
        }

        // Detect actual zoom factors for this device
        configureZoomFactors(for: device)

        return true
    }

    private func configureZoomFactors(for device: AVCaptureDevice) {
        // For triple/dual camera, get the switch-over points
        // virtualDeviceSwitchOverVideoZoomFactors tells us where the physical lenses switch
        let switchOverFactors = device.virtualDeviceSwitchOverVideoZoomFactors

        print("Device: \(device.deviceType), switchOverFactors: \(switchOverFactors)")
        print("Min zoom: \(device.minAvailableVideoZoomFactor), Max zoom: \(device.maxAvailableVideoZoomFactor)")

        if device.deviceType == .builtInTripleCamera {
            // iPhone Pro triple camera: ultra-wide (0.5x) -> wide (1x) -> telephoto (4x)
            // For triple camera, zoom factor 1.0 = ultra-wide lens
            // The first switch-over is where wide (1x) lens activates
            // We start at 1x (wide), skipping ultra-wide

            if switchOverFactors.count >= 1 {
                // The wide lens (1x) activates at this zoom factor
                wideZoomFactor = CGFloat(truncating: switchOverFactors[0])  // typically 2.0

                // 2x = twice the wide zoom factor (digital crop of 1x wide)
                zoom2xFactor = wideZoomFactor * 2.0  // typically 4.0

                // 4x = four times the wide zoom factor (native telephoto)
                telephotoZoomFactor = wideZoomFactor * 4.0  // typically 8.0

                // 8x = eight times the wide zoom factor (digital crop of 4x telephoto)
                zoom8xFactor = min(wideZoomFactor * 8.0, device.maxAvailableVideoZoomFactor)  // typically 16.0
            }
        } else if device.deviceType == .builtInDualCamera {
            // Dual camera: wide (1x) -> telephoto
            // For dual camera, zoom factor 1.0 = wide lens
            wideZoomFactor = 1.0
            zoom2xFactor = 2.0
            telephotoZoomFactor = min(4.0, device.maxAvailableVideoZoomFactor)
            zoom8xFactor = min(8.0, device.maxAvailableVideoZoomFactor)
        } else {
            // Single wide-angle camera - digital zoom only
            wideZoomFactor = 1.0
            zoom2xFactor = 2.0
            telephotoZoomFactor = min(4.0, device.maxAvailableVideoZoomFactor)
            zoom8xFactor = min(8.0, device.maxAvailableVideoZoomFactor)
        }

        print("Configured zoom factors - 1x: \(wideZoomFactor), 2x: \(zoom2xFactor), 4x: \(telephotoZoomFactor), 8x: \(zoom8xFactor)")
    }

    private func setupVideoOutput() {
        videoOutput.setSampleBufferDelegate(self, queue: videoQueue)
        videoOutput.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ]
        videoOutput.alwaysDiscardsLateVideoFrames = true

        if captureSession.canAddOutput(videoOutput) {
            captureSession.addOutput(videoOutput)
        }

        // Set video orientation
        if let connection = videoOutput.connection(with: .video) {
            if connection.isVideoRotationAngleSupported(90) {
                connection.videoRotationAngle = 90
            }
        }
    }

    private func setupPhotoOutput() {
        photoOutput.maxPhotoQualityPrioritization = .quality

        if captureSession.canAddOutput(photoOutput) {
            captureSession.addOutput(photoOutput)
        }

        // Configure photo output connection to match video preview
        if let connection = photoOutput.connection(with: .video) {
            if connection.isVideoRotationAngleSupported(90) {
                connection.videoRotationAngle = 90
            }
        }
    }

    // MARK: - Session Control

    func startSession() {
        sessionQueue.async { [weak self] in
            guard let self = self else { return }
            if !self.captureSession.isRunning {
                self.captureSession.startRunning()
            }
        }

        // Start tracking device orientation
        DispatchQueue.main.async {
            UIDevice.current.beginGeneratingDeviceOrientationNotifications()
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(self.orientationChanged),
                name: UIDevice.orientationDidChangeNotification,
                object: nil
            )
            self.currentOrientation = UIDevice.current.orientation.isValidInterfaceOrientation
                ? UIDevice.current.orientation : .portrait
        }
    }

    @objc private func orientationChanged() {
        let orientation = UIDevice.current.orientation
        if orientation.isValidInterfaceOrientation {
            currentOrientation = orientation
        }
    }

    func stopSession() {
        sessionQueue.async { [weak self] in
            guard let self = self else { return }
            if self.captureSession.isRunning {
                self.captureSession.stopRunning()
            }
        }

        DispatchQueue.main.async {
            NotificationCenter.default.removeObserver(self)
            UIDevice.current.endGeneratingDeviceOrientationNotifications()
        }
    }

    // MARK: - Lens Control

    func switchLens(to lens: CameraLens) {
        guard let device = videoDevice else { return }

        sessionQueue.async { [weak self] in
            guard let self = self else { return }

            do {
                try device.lockForConfiguration()

                // Use device-specific zoom factor, not the generic one from CameraLens
                let deviceZoom = self.zoomFactor(for: lens)
                let targetZoom = min(max(deviceZoom, device.minAvailableVideoZoomFactor),
                                    device.maxAvailableVideoZoomFactor)

                print("Switching to \(lens.rawValue): deviceZoom=\(deviceZoom), targetZoom=\(targetZoom)")

                // Use ramp for smooth animated transition like native iOS camera
                // Rate is zoom factor change per second - higher = faster transition
                let zoomDelta = abs(targetZoom - device.videoZoomFactor)
                let rate: Float = max(Float(zoomDelta) * 3.0, 2.0)  // Adaptive rate, minimum 2.0
                device.ramp(toVideoZoomFactor: targetZoom, withRate: rate)

                device.unlockForConfiguration()

                self.currentLens = lens
            } catch {
                print("Failed to switch lens: \(error)")
            }
        }
    }

    /// Cancel any ongoing zoom animation
    func cancelZoomRamp() {
        guard let device = videoDevice else { return }

        sessionQueue.async {
            do {
                try device.lockForConfiguration()
                device.cancelVideoZoomRamp()
                device.unlockForConfiguration()
            } catch {
                print("Failed to cancel zoom ramp: \(error)")
            }
        }
    }

    // MARK: - Photo Capture

    func capturePhoto() {
        // Update photo output rotation to match device orientation BEFORE capture
        if let connection = photoOutput.connection(with: .video) {
            let rotationAngle = rotationAngleForCurrentOrientation()
            if connection.isVideoRotationAngleSupported(rotationAngle) {
                connection.videoRotationAngle = rotationAngle
            }
        }

        let settings = AVCapturePhotoSettings()
        // Use maximum quality for captures
        settings.photoQualityPrioritization = .quality

        photoOutput.capturePhoto(with: settings, delegate: self)
    }

    /// Get the correct rotation angle for the current device orientation
    private func rotationAngleForCurrentOrientation() -> CGFloat {
        switch currentOrientation {
        case .portrait:
            return 90
        case .portraitUpsideDown:
            return 270
        case .landscapeLeft:
            // Home button on right - camera is rotated 180 from natural landscape
            return 0
        case .landscapeRight:
            // Home button on left - camera matches natural landscape
            return 180
        default:
            return 90
        }
    }
}

// MARK: - AVCaptureVideoDataOutputSampleBufferDelegate

extension CameraService: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput,
                      didOutput sampleBuffer: CMSampleBuffer,
                      from connection: AVCaptureConnection) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let timestamp = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)

        delegate?.cameraService(self, didOutput: pixelBuffer, timestamp: timestamp)
    }

    func captureOutput(_ output: AVCaptureOutput,
                      didDrop sampleBuffer: CMSampleBuffer,
                      from connection: AVCaptureConnection) {
        // Frame dropped - this is expected under heavy load
    }
}

// MARK: - AVCapturePhotoCaptureDelegate

extension CameraService: AVCapturePhotoCaptureDelegate {
    func photoOutput(_ output: AVCapturePhotoOutput,
                    didFinishProcessingPhoto photo: AVCapturePhoto,
                    error: Error?) {
        if let error = error {
            DispatchQueue.main.async {
                self.delegate?.cameraServiceDidFail(self, error: error)
            }
            return
        }

        guard let imageData = photo.fileDataRepresentation(),
              let image = UIImage(data: imageData) else {
            return
        }

        // Apply correct orientation based on device orientation
        let orientedImage = self.applyOrientation(to: image)

        DispatchQueue.main.async {
            self.delegate?.cameraService(self, didCapturePhoto: orientedImage)
        }
    }

    private func applyOrientation(to image: UIImage) -> UIImage {
        // Since we set videoRotationAngle before capture, the image data
        // should already be correctly oriented. Return as-is.
        return image
    }
}
