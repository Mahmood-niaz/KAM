import CoreMedia
import Foundation

final class MotionAnalyzer {
    private var previousFrameTimestamp: CMTime?
    private var previousSaliencyCenter: CGPoint?
    private var velocityHistory: [CGFloat] = []
    private let historySize = 5

    // Velocity thresholds (normalized per second)
    private let fastPanningThreshold: CGFloat = 0.5
    private let slowPanningThreshold: CGFloat = 0.1

    func detectPanning(currentTimestamp: CMTime, saliencyCenter: CGPoint) -> PanningState {
        defer {
            previousFrameTimestamp = currentTimestamp
            previousSaliencyCenter = saliencyCenter
        }

        guard let prevTimestamp = previousFrameTimestamp,
              let prevCenter = previousSaliencyCenter else {
            return .unknown
        }

        let timeDelta = CMTimeGetSeconds(currentTimestamp - prevTimestamp)
        guard timeDelta > 0 else { return .unknown }

        // Calculate displacement of saliency center
        let displacement = hypot(
            saliencyCenter.x - prevCenter.x,
            saliencyCenter.y - prevCenter.y
        )

        // Velocity in normalized units per second
        let velocity = displacement / CGFloat(timeDelta)

        // Track velocity history for smoothing
        velocityHistory.append(velocity)
        if velocityHistory.count > historySize {
            velocityHistory.removeFirst()
        }

        // Use average velocity for more stable detection
        let avgVelocity = velocityHistory.reduce(0, +) / CGFloat(velocityHistory.count)

        if avgVelocity > fastPanningThreshold {
            return .activePanning
        } else if avgVelocity > slowPanningThreshold {
            return .slowPanning
        } else {
            return .stationary
        }
    }

    func reset() {
        previousFrameTimestamp = nil
        previousSaliencyCenter = nil
        velocityHistory.removeAll()
    }
}
