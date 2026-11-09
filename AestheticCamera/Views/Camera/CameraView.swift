import SwiftUI
import CoreMotion

struct CameraView: View {
    @StateObject private var viewModel = CameraViewModel()
    @StateObject private var levelMotion = CameraLevelMotionManager()
    @State private var showGallery = false

    var body: some View {
        ZStack {
            // Camera preview
            CameraPreviewView(session: viewModel.cameraService.captureSession)
                .ignoresSafeArea()

            // Subject highlight overlay (only when hints enabled)
            if viewModel.showHints, let bounds = viewModel.subjectBounds {
                SubjectHighlightView(bounds: bounds)
                    .ignoresSafeArea()
            }

            AspectRatioFramingOverlay(
                aspectRatio: viewModel.selectedAspectRatio,
                gridType: viewModel.showGrid ? viewModel.gridType : .none
            )
                .ignoresSafeArea()

            if viewModel.showLevelIndicator {
                CameraLevelIndicator(levelAngle: levelMotion.levelAngle)
                    .ignoresSafeArea()
            }

            // Capture flash effect
            if viewModel.showCaptureFlash {
                Color.white
                    .ignoresSafeArea()
                    .opacity(0.8)
                    .animation(.easeOut(duration: 0.1), value: viewModel.showCaptureFlash)
            }

            // Scene capture overlay
            if viewModel.isSceneCaptureActive {
                sceneCaptureOverlay
            }

            // Smart pan overlay
            if viewModel.smartPanState != .idle {
                smartPanOverlay
            }

            // Hold Still overlay
            if viewModel.showHoldStillOverlay {
                holdStillOverlay
            }

            // UI Overlays
            VStack {
                // Top bar
                topBar

                Spacer()

                // Composition guidance overlay (only when hints enabled and not in scene capture)
                if viewModel.showHints && !viewModel.isSceneCaptureActive {
                    CompositionGuideView(
                        guide: viewModel.compositionGuide,
                        onLensTap: { lens in
                            viewModel.switchLens(to: lens)
                        }
                    )
                    .frame(height: 50)
                    .padding(.bottom, 8)

                    // Score indicator
                    ScoreIndicatorView(
                        score: viewModel.compositionScore,
                        showDetails: viewModel.showScoreDetails
                    )
                    .padding(.horizontal)
                    .padding(.bottom, 8)
                }

                // Bottom controls (hide during scene capture and smart pan)
                if !viewModel.isSceneCaptureActive && viewModel.smartPanState == .idle {
                    bottomControls
                }
            }
        }
        .onAppear {
            levelMotion.start()
            viewModel.startCamera()
        }
        .onDisappear {
            levelMotion.stop()
            viewModel.stopCamera()
        }
        .sheet(isPresented: $viewModel.showSettings) {
            SettingsView(viewModel: viewModel)
        }
        .alert("Error", isPresented: .init(
            get: { viewModel.errorMessage != nil },
            set: { if !$0 { viewModel.errorMessage = nil } }
        )) {
            Button("OK") { viewModel.errorMessage = nil }
        } message: {
            Text(viewModel.errorMessage ?? "Unknown error")
        }
        .fullScreenCover(isPresented: $viewModel.showCropPreview) {
            if let image = viewModel.imageForCrop,
               let suggestion = viewModel.cropSuggestion {
                CropPreviewView(
                    image: image,
                    cropSuggestion: suggestion,
                    onAccept: { croppedImage in
                        viewModel.acceptCrop(croppedImage)
                    },
                    onReject: {
                        viewModel.rejectCrop()
                    }
                )
            }
        }
        .fullScreenCover(isPresented: $viewModel.showSceneResult) {
            if let image = viewModel.sceneResultImage,
               let crop = viewModel.sceneResultCrop {
                SceneResultView(
                    originalImage: image,
                    cropSuggestion: crop,
                    selectionReason: viewModel.sceneResultReason,
                    onSave: { _ in
                        viewModel.saveSceneResult()
                    },
                    onDiscard: {
                        viewModel.discardSceneResult()
                    }
                )
            }
        }
        .fullScreenCover(isPresented: $showGallery) {
            GalleryView()
        }
    }

    // MARK: - Scene Capture Overlay

    private var sceneCaptureOverlay: some View {
        VStack {
            // Visual guide at top
            if !viewModel.isProcessingScene {
                sceneGuideView
                    .padding(.top, 100)
            }

            Spacer()

            VStack(spacing: 20) {
                if viewModel.isProcessingScene {
                    // Processing state
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        .scaleEffect(1.5)
                    Text("Analyzing \(viewModel.sceneCapturedCount) photos...")
                        .font(.headline)
                        .foregroundColor(.white)
                } else {
                    // Photo count
                    Text("\(viewModel.sceneCapturedCount) photos captured")
                        .font(.headline)
                        .foregroundColor(.white)

                    Text("Pan and tap to capture different angles")
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.7))

                    // Capture button
                    Button {
                        viewModel.captureScenePhoto()
                    } label: {
                        ZStack {
                            Circle()
                                .stroke(Color.yellow, lineWidth: 4)
                                .frame(width: 70, height: 70)

                            Circle()
                                .fill(Color.yellow)
                                .frame(width: 58, height: 58)
                        }
                    }

                    // Action buttons
                    HStack(spacing: 16) {
                        Button {
                            viewModel.cancelSceneCapture()
                        } label: {
                            Text("Cancel")
                                .font(.subheadline.weight(.medium))
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(Color.white.opacity(0.2))
                                .clipShape(Capsule())
                        }

                        Button {
                            viewModel.finishSceneCapture()
                        } label: {
                            Text("Done")
                                .font(.subheadline.weight(.medium))
                                .foregroundColor(.black)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(viewModel.sceneCapturedCount >= 2 ? Color.yellow : Color.gray)
                                .clipShape(Capsule())
                        }
                        .disabled(viewModel.sceneCapturedCount < 2)
                    }
                    .padding(.horizontal)
                }
            }
            .padding(24)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .padding()
        }
    }

    // Visual pan guide
    private var sceneGuideView: some View {
        GeometryReader { geometry in
            let width = geometry.size.width - 80
            let centerX = geometry.size.width / 2
            let indicatorX = centerX + (viewModel.sceneGuideOffset * width / 2)

            ZStack {
                // Guide track
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.white.opacity(0.3))
                    .frame(width: width, height: 8)

                // Center marker
                Rectangle()
                    .fill(Color.white.opacity(0.5))
                    .frame(width: 2, height: 16)

                // Position indicator
                Circle()
                    .fill(Color.yellow)
                    .frame(width: 20, height: 20)
                    .shadow(color: .black.opacity(0.3), radius: 2, x: 0, y: 1)
                    .position(x: indicatorX, y: geometry.size.height / 2)
            }
            .frame(width: geometry.size.width, height: 30)
        }
        .frame(height: 30)
        .padding(.horizontal, 40)
    }

    // MARK: - Smart Pan Overlay

    private var smartPanOverlay: some View {
        VStack {
            Spacer()

            VStack(spacing: 20) {
                if viewModel.isProcessingSmartPan {
                    // Processing state
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        .scaleEffect(1.5)
                    Text("Analyzing \(viewModel.smartPanPairsCount) subject pairs...")
                        .font(.headline)
                        .foregroundColor(.white)
                } else {
                    // Status text
                    Text(viewModel.smartPanState.statusText)
                        .font(.headline)
                        .foregroundColor(.white)

                    // Pairs count
                    if viewModel.smartPanPairsCount > 0 {
                        Text("\(viewModel.smartPanPairsCount) subject\(viewModel.smartPanPairsCount == 1 ? "" : "s") captured")
                            .font(.subheadline)
                            .foregroundColor(.white.opacity(0.7))
                    }

                    // Action buttons
                    HStack(spacing: 16) {
                        Button {
                            viewModel.cancelSmartPan()
                        } label: {
                            Text("Cancel")
                                .font(.subheadline.weight(.medium))
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(Color.white.opacity(0.2))
                                .clipShape(Capsule())
                        }

                        Button {
                            viewModel.stopSmartPan()
                        } label: {
                            Text("Done")
                                .font(.subheadline.weight(.medium))
                                .foregroundColor(.black)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(viewModel.smartPanPairsCount >= 1 ? Color.cyan : Color.gray)
                                .clipShape(Capsule())
                        }
                        .disabled(viewModel.smartPanPairsCount < 1)
                    }
                    .padding(.horizontal)
                }
            }
            .padding(24)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .padding()
        }
    }

    // MARK: - Hold Still Overlay

    private var holdStillOverlay: some View {
        VStack {
            Spacer()

            HStack {
                Spacer()

                VStack(spacing: 8) {
                    Image(systemName: "hand.raised.fill")
                        .font(.system(size: 40))
                        .foregroundColor(.yellow)

                    Text("Hold Still")
                        .font(.headline.weight(.bold))
                        .foregroundColor(.white)
                }
                .padding(24)
                .background(Color.black.opacity(0.7))
                .clipShape(RoundedRectangle(cornerRadius: 16))

                Spacer()
            }

            Spacer()
        }
        .transition(.opacity)
        .animation(.easeInOut(duration: 0.2), value: viewModel.showHoldStillOverlay)
    }

    // MARK: - Top Bar

    private var topBar: some View {
        HStack {
            // Settings button
            Button {
                viewModel.showSettings = true
            } label: {
                Image(systemName: "gearshape.fill")
                    .font(.title2)
                    .foregroundColor(.white)
                    .padding(12)
                    .background(.ultraThinMaterial)
                    .clipShape(Circle())
            }

            Spacer()

            // Hints toggle
            Button {
                viewModel.showHints.toggle()
            } label: {
                Image(systemName: viewModel.showHints ? "lightbulb.fill" : "lightbulb")
                    .font(.title2)
                    .foregroundColor(viewModel.showHints ? .yellow : .white)
                    .padding(12)
                    .background(.ultraThinMaterial)
                    .clipShape(Circle())
            }

            // Grid toggle
            Button {
                viewModel.showGrid.toggle()
            } label: {
                Image(systemName: viewModel.showGrid ? "grid" : "grid.circle")
                    .font(.title2)
                    .foregroundColor(.white)
                    .padding(12)
                    .background(.ultraThinMaterial)
                    .clipShape(Circle())
            }
        }
        .padding()
    }

    // MARK: - Bottom Controls

    private var bottomControls: some View {
        VStack(spacing: 16) {
            // Lens picker
            LensPickerView(
                currentLens: viewModel.currentLens,
                onLensSelected: { lens in
                    viewModel.switchLens(to: lens)
                }
            )

            // Main control row - changes based on mode
            switch viewModel.captureMode {
            case .singleShot:
                singleShotControls
            case .sceneCapture:
                sceneCaptureControls
            case .smartPan:
                smartPanControls
            }

            // Capture count
            if viewModel.captureCount > 0 {
                Text("\(viewModel.captureCount) photo\(viewModel.captureCount == 1 ? "" : "s") captured")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.7))
            }
        }
        .padding(.bottom, 30)
    }

    // MARK: - Single Shot Controls (v3)

    private var singleShotControls: some View {
        HStack {
            // Gallery preview + AI crop button (left)
            VStack(spacing: 8) {
                Button {
                    showGallery = true
                } label: {
                    if let lastImage = viewModel.lastCapturedImage {
                        Image(uiImage: lastImage)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 50, height: 50)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(Color.white, lineWidth: 2)
                            )
                    } else {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.gray.opacity(0.3))
                            .frame(width: 50, height: 50)
                            .overlay(
                                Image(systemName: "photo")
                                    .foregroundColor(.white.opacity(0.5))
                            )
                    }
                }

                // AI Crop button (only shows when image exists)
                if viewModel.lastCapturedImage != nil {
                    Button {
                        viewModel.requestCropSuggestion()
                    } label: {
                        if viewModel.isRequestingCrop {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                .frame(width: 36, height: 36)
                        } else {
                            Image(systemName: "wand.and.stars")
                                .font(.system(size: 16))
                                .foregroundColor(.white)
                                .frame(width: 36, height: 36)
                                .background(Color.purple.opacity(0.8))
                                .clipShape(Circle())
                        }
                    }
                    .disabled(viewModel.isRequestingCrop)
                }
            }

            Spacer()

            // Manual capture button (center, large)
            Button {
                viewModel.captureManually()
            } label: {
                ZStack {
                    Circle()
                        .stroke(Color.white, lineWidth: 4)
                        .frame(width: 70, height: 70)

                    Circle()
                        .fill(Color.white)
                        .frame(width: 58, height: 58)
                }
            }

            Spacer()

            // Auto-capture toggle (right, smaller)
            Button {
                viewModel.toggleAutoCapture()
            } label: {
                ZStack {
                    Circle()
                        .stroke(viewModel.autoCaptureEnabled ? Color.green : Color.white.opacity(0.5), lineWidth: 2)
                        .frame(width: 50, height: 50)

                    Circle()
                        .fill(viewModel.autoCaptureEnabled ? Color.green.opacity(0.3) : Color.gray.opacity(0.3))
                        .frame(width: 44, height: 44)

                    Text("AUTO")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(viewModel.autoCaptureEnabled ? .green : .white.opacity(0.6))
                }
            }
        }
        .padding(.horizontal, 40)
    }

    // MARK: - Scene Capture Controls (v4)

    private var sceneCaptureControls: some View {
        VStack(spacing: 12) {
            // Start Scene Capture button
            Button {
                viewModel.startSceneCapture()
            } label: {
                HStack {
                    Image(systemName: "pano")
                        .font(.title2)
                    Text("Capture Scene")
                        .font(.headline)
                }
                .foregroundColor(.black)
                .padding(.horizontal, 30)
                .padding(.vertical, 16)
                .background(Color.yellow)
                .clipShape(Capsule())
            }

            Text("Pan left and right to capture 3 angles")
                .font(.caption)
                .foregroundColor(.white.opacity(0.7))
        }
    }

    // MARK: - Smart Pan Controls (v5)

    private var smartPanControls: some View {
        VStack(spacing: 12) {
            // Start Smart Pan button
            Button {
                viewModel.startSmartPan()
            } label: {
                HStack {
                    Image(systemName: "viewfinder")
                        .font(.title2)
                    Text("Start Smart Pan")
                        .font(.headline)
                }
                .foregroundColor(.black)
                .padding(.horizontal, 30)
                .padding(.vertical, 16)
                .background(Color.cyan)
                .clipShape(Capsule())
            }

            Text("Pan slowly - subjects auto-captured at 1x + 4x")
                .font(.caption)
                .foregroundColor(.white.opacity(0.7))
        }
    }
}

private struct AspectRatioFramingOverlay: View {
    let aspectRatio: AspectRatio
    let gridType: GridType

    var body: some View {
        GeometryReader { geometry in
            let size = geometry.size
            let ratio = aspectRatio.portraitRatio
            let frameWidth = min(size.width, size.height * ratio)
            let frameHeight = frameWidth / ratio
            let frameRect = CGRect(
                x: (size.width - frameWidth) / 2,
                y: (size.height - frameHeight) / 2,
                width: frameWidth,
                height: frameHeight
            )

            ZStack {
                Path { path in
                    path.addRect(CGRect(origin: .zero, size: size))
                    path.addRect(frameRect)
                }
                .fill(Color.black.opacity(0.45), style: FillStyle(eoFill: true))

                CompositionOverlayView(gridType: gridType)
                    .frame(width: frameWidth, height: frameHeight)
                    .position(x: frameRect.midX, y: frameRect.midY)

                Rectangle()
                    .stroke(Color.white.opacity(0.9), lineWidth: 1.5)
                    .frame(width: frameWidth, height: frameHeight)
                    .position(x: frameRect.midX, y: frameRect.midY)
            }
            .frame(width: size.width, height: size.height)
        }
        .allowsHitTesting(false)
    }
}

// MARK: - Lens Picker

struct LensPickerView: View {
    let currentLens: CameraLens
    let onLensSelected: (CameraLens) -> Void

    var body: some View {
        HStack(spacing: 12) {
            ForEach(CameraLens.allCases) { lens in
                Button {
                    onLensSelected(lens)
                } label: {
                    Text(lens.icon)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(currentLens == lens ? .black : .white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(
                            Capsule()
                                .fill(currentLens == lens ? Color.yellow : Color.white.opacity(0.2))
                        )
                }
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial)
        .clipShape(Capsule())
    }
}

// MARK: - Subject Highlight

struct SubjectHighlightView: View {
    let bounds: CGRect  // Vision coordinates (0-1, origin bottom-left)

    var body: some View {
        GeometryReader { geometry in
            // Convert Vision coordinates to SwiftUI (flip Y axis)
            let x = bounds.minX * geometry.size.width
            let y = (1 - bounds.maxY) * geometry.size.height  // Flip Y
            let width = bounds.width * geometry.size.width
            let height = bounds.height * geometry.size.height

            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.yellow.opacity(0.8), lineWidth: 2)
                .frame(width: width, height: height)
                .position(x: x + width / 2, y: y + height / 2)
        }
    }
}

@MainActor
private final class CameraLevelMotionManager: ObservableObject {
    @Published private(set) var levelAngle = 0.0

    private let motionManager = CMMotionManager()
    private var filteredAngle: Double?
    private var lastMotionTimestamp: TimeInterval?

    func start() {
        guard motionManager.isDeviceMotionAvailable,
              !motionManager.isDeviceMotionActive else { return }

        motionManager.deviceMotionUpdateInterval = 1.0 / 60.0
        motionManager.startDeviceMotionUpdates(to: .main) { [weak self] motion, _ in
            guard let motion else { return }
            let gravity = motion.gravity
            guard hypot(gravity.x, gravity.y) > 0.15 else { return }
            let rawAngle = atan2(gravity.x, -gravity.y)
            let timestamp = motion.timestamp
            Task { @MainActor [weak self] in
                guard let self else { return }

                let angle: Double
                if let filteredAngle = self.filteredAngle,
                   let lastMotionTimestamp = self.lastMotionTimestamp {
                    let elapsed = max(timestamp - lastMotionTimestamp, 0)
                    let alpha = 1 - exp(-elapsed / 0.08)
                    let difference = atan2(
                        sin(rawAngle - filteredAngle),
                        cos(rawAngle - filteredAngle)
                    )
                    angle = filteredAngle + alpha * difference
                } else {
                    angle = rawAngle
                }

                self.filteredAngle = angle
                self.lastMotionTimestamp = timestamp
                self.levelAngle = angle
            }
        }
    }

    func stop() {
        motionManager.stopDeviceMotionUpdates()
        filteredAngle = nil
        lastMotionTimestamp = nil
        levelAngle = 0
    }
}

private struct CameraLevelIndicator: View {
    let levelAngle: Double

    private var isLevel: Bool {
        abs(levelAngle) < 0.5 * .pi / 180
    }

    var body: some View {
        GeometryReader { geometry in
            let color = isLevel ? Color.yellow.opacity(0.82) : Color.white.opacity(0.76)

            ZStack {
                HStack(spacing: 8) {
                    Capsule()
                        .fill(Color.white.opacity(0.28))
                        .frame(width: 42, height: 0.5)

                    Circle()
                        .fill(Color.white.opacity(0.28))
                        .frame(width: 3, height: 3)

                    Capsule()
                        .fill(Color.white.opacity(0.28))
                        .frame(width: 42, height: 0.5)
                }

                HStack(spacing: 7) {
                    Capsule()
                        .fill(color)
                        .frame(width: 34, height: 1)

                    ZStack {
                        Circle()
                            .stroke(color, lineWidth: 1)
                            .frame(width: 8, height: 8)

                        Rectangle()
                            .fill(color)
                            .frame(width: 1, height: 12)
                    }
                    .frame(width: 12, height: 14)

                    Capsule()
                        .fill(color)
                        .frame(width: 34, height: 1)
                }
                .rotationEffect(.radians(levelAngle))
            }
            .shadow(color: .black.opacity(0.55), radius: 1.5)
            .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
