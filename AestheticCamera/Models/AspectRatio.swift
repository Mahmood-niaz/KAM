import Foundation

/// Supported aspect ratios for crop suggestions (matching Apple Camera)
enum AspectRatio: String, CaseIterable, Identifiable {
    case fourThree = "4:3"      // Default, standard photo
    case sixteenNine = "16:9"   // Cinematic, widescreen
    case oneOne = "1:1"         // Square, social media
    case threeTwo = "3:2"       // Classic 35mm film

    var id: String { rawValue }

    var displayName: String { rawValue }

    var next: AspectRatio {
        let all = AspectRatio.allCases
        return all[(all.firstIndex(of: self)! + 1) % all.count]
    }

    /// Returns the aspect ratio value (width / height) for landscape orientation
    var landscapeRatio: CGFloat {
        switch self {
        case .fourThree: return 4.0 / 3.0      // 1.333
        case .sixteenNine: return 16.0 / 9.0  // 1.778
        case .oneOne: return 1.0               // 1.0
        case .threeTwo: return 3.0 / 2.0      // 1.5
        }
    }

    /// Returns the aspect ratio value (width / height) for portrait orientation
    var portraitRatio: CGFloat {
        switch self {
        case .fourThree: return 3.0 / 4.0      // 0.75
        case .sixteenNine: return 9.0 / 16.0  // 0.5625
        case .oneOne: return 1.0               // 1.0
        case .threeTwo: return 2.0 / 3.0      // 0.667
        }
    }

    /// Portrait ratio string for Claude prompts (e.g., "3:4")
    var portraitRatioString: String {
        switch self {
        case .fourThree: return "3:4"
        case .sixteenNine: return "9:16"
        case .oneOne: return "1:1"
        case .threeTwo: return "2:3"
        }
    }

    /// Landscape ratio string for Claude prompts (e.g., "4:3")
    var landscapeRatioString: String {
        rawValue
    }

    /// Description for settings UI
    var description: String {
        switch self {
        case .fourThree: return "Standard photo"
        case .sixteenNine: return "Cinematic widescreen"
        case .oneOne: return "Square for social"
        case .threeTwo: return "Classic 35mm film"
        }
    }
}
