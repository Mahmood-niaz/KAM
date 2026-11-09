import Foundation
import CoreGraphics

/// Represents actionable composition guidance for the user
struct CompositionGuide {
    /// Horizontal movement suggestion
    let horizontalHint: HorizontalHint

    /// Vertical movement suggestion
    let verticalHint: VerticalHint

    /// Suggested lens for better framing
    let suggestedLens: CameraLens?

    /// How close the current composition is to ideal (0-1)
    let compositionQuality: Float

    /// The detected subject's current position (normalized 0-1)
    let subjectPosition: CGPoint

    /// The nearest ideal composition point
    let idealPosition: CGPoint

    /// Whether the composition is already good
    var isGoodComposition: Bool {
        compositionQuality >= 0.7
    }

    /// Whether the composition is excellent
    var isExcellentComposition: Bool {
        compositionQuality >= 0.85
    }

    /// Human-readable guidance text
    var guidanceText: String {
        if isExcellentComposition {
            return "Perfect! 📸"
        }

        if isGoodComposition {
            return "Good composition!"
        }

        var hints: [String] = []

        switch horizontalHint {
        case .moveLeft:
            hints.append("← Move left")
        case .moveRight:
            hints.append("Move right →")
        case .centered:
            break
        }

        switch verticalHint {
        case .moveUp:
            hints.append("↑ Move up")
        case .moveDown:
            hints.append("Move down ↓")
        case .centered:
            break
        }

        if let lens = suggestedLens {
            hints.append("Try \(lens.icon)")
        }

        return hints.isEmpty ? "Looking good" : hints.joined(separator: " • ")
    }

    static let none = CompositionGuide(
        horizontalHint: .centered,
        verticalHint: .centered,
        suggestedLens: nil,
        compositionQuality: 0.5,
        subjectPosition: CGPoint(x: 0.5, y: 0.5),
        idealPosition: CGPoint(x: 0.5, y: 0.5)
    )
}

enum HorizontalHint {
    case moveLeft
    case moveRight
    case centered
}

enum VerticalHint {
    case moveUp
    case moveDown
    case centered
}
