import SwiftUI
import CoreMotion
import UIKit

struct CameraView: View {
    @StateObject private var viewModel = CameraViewModel()
    @StateObject private var levelMotion = CameraLevelMotionManager()
    @State private var iconAngle: Double = 0

    var body: some View {
        ZStack {
            // Camera preview
            CameraPreviewView(
                session: viewModel.cameraService.captureSession,
                onTap: { point, devicePoint in
                    viewModel.focus(atViewPoint: point, devicePoint: devicePoint)
                }
            )
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

            // Tap-to-focus indicator with exposure slider
            ZStack {
                if let point = viewModel.focusIndicatorPoint {
                    FocusIndicatorView(bias: Binding(
                        get: { viewModel.exposureBias },
                        set: { viewModel.setExposureBias($0) }
                    ))
                    .position(point)
                }

                // Countdown
                if let countdown = viewModel.countdown {
                    Text("\(countdown)")
                        .font(.system(size: 96, weight: .thin))
                        .foregroundColor(.white)
                        .rotationEffect(.degrees(iconAngle))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .ignoresSafeArea()

            // UI Overlays
            VStack {
                // Top bar
                topBar

                Spacer()

                // Composition guidance overlay (only when hints enabled)
                if viewModel.showHints {
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

                bottomControls
            }
        }
        .onAppear {
            UIDevice.current.beginGeneratingDeviceOrientationNotifications()
            updateIconAngle()
            levelMotion.start()
            viewModel.startCamera()
        }
        .onDisappear {
            UIDevice.current.endGeneratingDeviceOrientationNotifications()
            levelMotion.stop()
            viewModel.stopCamera()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIDevice.orientationDidChangeNotification)) { _ in
            updateIconAngle()
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
    }

    private func updateIconAngle() {
        let angle: Double
        switch UIDevice.current.orientation {
        case .landscapeLeft: angle = 90
        case .portrait, .landscapeRight, .portraitUpsideDown: angle = 0
        default: return
        }
        withAnimation(.easeInOut(duration: 0.3)) {
            iconAngle = angle
        }
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
                    .rotationEffect(.degrees(iconAngle))
                    .padding(12)
                    .background(.ultraThinMaterial)
                    .clipShape(Circle())
            }

            Spacer()

            // Grid toggle
            Button {
                let next = viewModel.gridType.next
                viewModel.gridType = next
                viewModel.showGrid = next != .none
            } label: {
                Image(systemName: viewModel.showGrid ? "grid" : "grid.circle")
                    .font(.title2)
                    .foregroundColor(.white)
                    .rotationEffect(.degrees(iconAngle))
                    .padding(12)
                    .background(.ultraThinMaterial)
                    .clipShape(Circle())
            }

            // Aspect ratio toggle
            Button {
                viewModel.selectedAspectRatio = viewModel.selectedAspectRatio.next
            } label: {
                Text(viewModel.selectedAspectRatio.displayName)
                    .font(.system(size: 14, weight: .semibold, design: .monospaced))
                    .foregroundColor(.white)
                    .rotationEffect(.degrees(iconAngle))
                    .frame(width: 52, height: 52)
                    .background(.ultraThinMaterial)
                    .clipShape(Circle())
            }
        }
        .padding()
    }

    // MARK: - Bottom Controls

    private var bottomControls: some View {
        VStack(spacing: 16) {
            shutterControls

            // Capture count
            if viewModel.captureCount > 0 {
                Text("\(viewModel.captureCount) photo\(viewModel.captureCount == 1 ? "" : "s") captured")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.7))
            }
        }
        .padding(.bottom, 30)
    }

    private var shutterControls: some View {
        GeometryReader { geometry in
            let sideWidth = (geometry.size.width - 70) / 2

            HStack(spacing: 0) {
                LensPickerView(
                    currentLens: viewModel.currentLens,
                    iconAngle: iconAngle,
                    onLensSelected: { lens in
                        viewModel.switchLens(to: lens)
                    }
                )
                .frame(width: sideWidth)
                .opacity(0.7)

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

                FeatureButtonBox(iconAngle: iconAngle, viewModel: viewModel)
                    .frame(width: sideWidth)
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
        .frame(height: 100)
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
                ZStack {
                    Rectangle().fill(.ultraThinMaterial)
                    Color.black.opacity(0.55)
                }
                .mask {
                    Path { path in
                        path.addRect(CGRect(origin: .zero, size: size))
                        path.addRect(frameRect)
                    }
                    .fill(style: FillStyle(eoFill: true))
                }

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
    let iconAngle: Double
    let onLensSelected: (CameraLens) -> Void

    private let lenses = CameraLens.allCases

    var body: some View {
        VStack(spacing: 8) {
            ForEach(0..<2, id: \.self) { row in
                HStack(spacing: 8) {
                    ForEach(0..<3, id: \.self) { column in
                        let index = row * 3 + column
                        if index < lenses.count {
                            lensButton(lenses[index])
                        } else {
                            Color.clear.frame(width: 36, height: 36)
                        }
                    }
                }
            }
        }
        .padding(10)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 18))
    }

    private func lensButton(_ lens: CameraLens) -> some View {
        Button {
            onLensSelected(lens)
        } label: {
            Text(lens.icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(currentLens == lens ? .black : .white)
                .rotationEffect(.degrees(iconAngle))
                .frame(width: 36, height: 36)
                .background(
                    Circle()
                        .fill(currentLens == lens ? Color.yellow : Color.white.opacity(0.2))
                )
        }
    }
}

// MARK: - Feature Box

struct FeatureButtonBox: View {
    let iconAngle: Double
    @ObservedObject var viewModel: CameraViewModel

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                featureButton(
                    isActive: viewModel.timerSeconds > 0,
                    action: { viewModel.cycleTimer() }
                ) {
                    if viewModel.timerSeconds > 0 {
                        Text("\(viewModel.timerSeconds)s")
                            .font(.system(size: 12, weight: .semibold))
                    } else {
                        Image(systemName: "timer")
                    }
                }

                featureButton(
                    isActive: viewModel.flashMode != .off,
                    action: { viewModel.cycleFlash() }
                ) {
                    Image(systemName: flashIcon)
                }
            }

            HStack(spacing: 8) {
                featureButton(
                    isActive: viewModel.burstEnabled,
                    action: { viewModel.toggleBurst() }
                ) {
                    Image(systemName: "square.stack.3d.down.right")
                }

                featureButton(
                    isActive: viewModel.isExposureLocked,
                    action: { viewModel.toggleExposureLock() }
                ) {
                    Image(systemName: viewModel.isExposureLocked ? "lock.fill" : "lock.open")
                }

                featureButton(
                    isActive: viewModel.portraitEnabled,
                    action: { viewModel.togglePortrait() }
                ) {
                    Image(systemName: "camera.aperture")
                }
            }
        }
        .padding(10)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 18))
    }

    private var flashIcon: String {
        switch viewModel.flashMode {
        case .on: return "bolt.fill"
        case .auto: return "bolt.badge.a.fill"
        default: return "bolt.slash.fill"
        }
    }

    private func featureButton<Label: View>(
        isActive: Bool,
        action: @escaping () -> Void,
        @ViewBuilder label: () -> Label
    ) -> some View {
        Button(action: action) {
            label()
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(isActive ? .black : .white)
                .rotationEffect(.degrees(iconAngle))
                .frame(width: 36, height: 36)
                .background(
                    Circle()
                        .fill(isActive ? Color.yellow : Color.white.opacity(0.2))
                )
        }
    }
}

// MARK: - Focus Indicator

private struct FocusIndicatorView: View {
    @Binding var bias: Float

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 4)
                .stroke(Color.yellow, lineWidth: 1.5)
                .frame(width: 76, height: 76)

            Slider(value: $bias, in: -2...2)
                .tint(.yellow)
                .frame(width: 110)
                .rotationEffect(.degrees(-90))
                .offset(x: 80)
        }
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

#Preview {
    CameraView()
}
