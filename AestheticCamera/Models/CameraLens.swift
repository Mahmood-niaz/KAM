import Foundation
import AVFoundation

enum CameraLens: String, CaseIterable, Identifiable {
    case wide = "Wide"                  // 1x - physical lens
    case zoom2x = "2x"                  // 2x - digital crop of 1x wide
    case telephoto = "Telephoto"        // 4x - physical telephoto lens
    case zoom8x = "8x"                  // 8x - digital crop of 4x telephoto

    var id: String { rawValue }

    /// User-facing zoom multiplier (relative to 1x wide lens)
    var userZoom: CGFloat {
        switch self {
        case .wide: return 1.0
        case .zoom2x: return 2.0
        case .telephoto: return 4.0
        case .zoom8x: return 8.0
        }
    }

    var icon: String {
        switch self {
        case .wide: return "1"
        case .zoom2x: return "2"
        case .telephoto: return "4"
        case .zoom8x: return "8"
        }
    }
}

enum CaptureDecision {
    case capture(confidence: CaptureConfidence, score: Float)
    case skip(reason: SkipReason)

    var shouldCapture: Bool {
        if case .capture = self { return true }
        return false
    }
}

enum CaptureConfidence {
    case high
    case medium
}

enum SkipReason {
    case disabled
    case cooldown
    case buildingHistory
    case belowThreshold
    case waitingForBetterMoment
    case unstable
}

enum PanningState {
    case activePanning
    case slowPanning
    case stationary
    case unknown
}
