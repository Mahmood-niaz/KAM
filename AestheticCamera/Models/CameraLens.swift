import Foundation
import AVFoundation

enum CameraLens: String, CaseIterable, Identifiable {
    case ultrawide = "Ultrawide"        // 0.5x - physical ultra-wide lens
    case wide = "Wide"                  // 1x - physical lens
    case zoom2x = "2x"                  // 2x - digital crop of 1x wide
    case telephoto = "Telephoto"        // 4x - physical telephoto lens
    case zoom8x = "8x"                  // 8x - digital crop of 4x telephoto

    var id: String { rawValue }

    /// User-facing zoom multiplier (relative to 1x wide lens)
    var userZoom: CGFloat {
        switch self {
        case .ultrawide: return 0.5
        case .wide: return 1.0
        case .zoom2x: return 2.0
        case .telephoto: return 4.0
        case .zoom8x: return 8.0
        }
    }

    var icon: String {
        switch self {
        case .ultrawide: return "0.5"
        case .wide: return "1"
        case .zoom2x: return "2"
        case .telephoto: return "4"
        case .zoom8x: return "8"
        }
    }
}
