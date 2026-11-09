import Foundation
import CoreGraphics
import Vision

/// Analyzes saliency data and provides actionable composition guidance
final class CompositionGuideAnalyzer {

    // Rule of thirds intersection points (normalized 0-1)
    private let compositionPoints: [CGPoint] = [
        CGPoint(x: 1.0/3.0, y: 1.0/3.0),  // Top-left
        CGPoint(x: 2.0/3.0, y: 1.0/3.0),  // Top-right
        CGPoint(x: 1.0/3.0, y: 2.0/3.0),  // Bottom-left
        CGPoint(x: 2.0/3.0, y: 2.0/3.0)   // Bottom-right
    ]

    // Threshold for considering subject "on" a composition point
    private let alignmentThreshold: CGFloat = 0.12

    // Minimum subject size relative to frame for zoom-out suggestion
    private let minSubjectSize: CGFloat = 0.08

    // Maximum subject size relative to frame for zoom-in suggestion
    private let maxSubjectSize: CGFloat = 0.45

    /// Analyze saliency result and provide composition guidance
    func analyze(saliencyResult: SaliencyResult, currentLens: CameraLens) -> CompositionGuide {
        // Get subject position (attention center or largest salient object)
        let subjectPosition = getSubjectPosition(from: saliencyResult)
        let subjectSize = getSubjectSize(from: saliencyResult)

        // Find nearest ideal composition point
        let (nearestPoint, distance) = findNearestCompositionPoint(to: subjectPosition)

        // Calculate composition quality (inverse of distance, clamped)
        let maxDistance: CGFloat = 0.47 // Max possible distance from corner to nearest point
        let normalizedDistance = min(distance / maxDistance, 1.0)
        let compositionQuality = Float(1.0 - normalizedDistance)

        // Determine movement hints
        let horizontalHint = calculateHorizontalHint(
            subjectX: subjectPosition.x,
            idealX: nearestPoint.x,
            distance: distance
        )

        let verticalHint = calculateVerticalHint(
            subjectY: subjectPosition.y,
            idealY: nearestPoint.y,
            distance: distance
        )

        // Determine lens suggestion based on subject size
        let suggestedLens = calculateLensSuggestion(
            subjectSize: subjectSize,
            currentLens: currentLens
        )

        return CompositionGuide(
            horizontalHint: horizontalHint,
            verticalHint: verticalHint,
            suggestedLens: suggestedLens,
            compositionQuality: compositionQuality,
            subjectPosition: subjectPosition,
            idealPosition: nearestPoint
        )
    }

    // MARK: - Private Helpers

    private func getSubjectPosition(from saliencyResult: SaliencyResult) -> CGPoint {
        // Prefer the largest salient object's center
        if let largestObject = saliencyResult.salientObjects.max(by: {
            $0.boundingBox.width * $0.boundingBox.height <
            $1.boundingBox.width * $1.boundingBox.height
        }) {
            return CGPoint(
                x: largestObject.boundingBox.midX,
                y: largestObject.boundingBox.midY
            )
        }

        // Fall back to attention center
        return saliencyResult.attentionCenter
    }

    private func getSubjectSize(from saliencyResult: SaliencyResult) -> CGFloat {
        // Get size of largest salient object relative to frame
        if let largestObject = saliencyResult.salientObjects.max(by: {
            $0.boundingBox.width * $0.boundingBox.height <
            $1.boundingBox.width * $1.boundingBox.height
        }) {
            return largestObject.boundingBox.width * largestObject.boundingBox.height
        }

        // Default to medium size if no objects detected
        return 0.15
    }

    private func findNearestCompositionPoint(to point: CGPoint) -> (CGPoint, CGFloat) {
        var nearestPoint = compositionPoints[0]
        var minDistance = CGFloat.greatestFiniteMagnitude

        for compositionPoint in compositionPoints {
            let distance = hypot(point.x - compositionPoint.x, point.y - compositionPoint.y)
            if distance < minDistance {
                minDistance = distance
                nearestPoint = compositionPoint
            }
        }

        return (nearestPoint, minDistance)
    }

    private func calculateHorizontalHint(subjectX: CGFloat, idealX: CGFloat, distance: CGFloat) -> HorizontalHint {
        // If already close enough, no hint needed
        guard distance > alignmentThreshold else {
            return .centered
        }

        let horizontalDiff = idealX - subjectX

        // Only suggest movement if significantly off
        if horizontalDiff > 0.08 {
            return .moveRight  // Subject needs to move right in frame = camera moves left
        } else if horizontalDiff < -0.08 {
            return .moveLeft   // Subject needs to move left in frame = camera moves right
        }

        return .centered
    }

    private func calculateVerticalHint(subjectY: CGFloat, idealY: CGFloat, distance: CGFloat) -> VerticalHint {
        // If already close enough, no hint needed
        guard distance > alignmentThreshold else {
            return .centered
        }

        let verticalDiff = idealY - subjectY

        // Only suggest movement if significantly off
        // Note: Vision coordinates have Y=0 at bottom, but we want intuitive hints
        if verticalDiff > 0.08 {
            return .moveDown  // Subject needs to move down in frame
        } else if verticalDiff < -0.08 {
            return .moveUp    // Subject needs to move up in frame
        }

        return .centered
    }

    private func calculateLensSuggestion(subjectSize: CGFloat, currentLens: CameraLens) -> CameraLens? {
        // If subject is too small, suggest zooming in
        if subjectSize < minSubjectSize {
            switch currentLens {
            case .wide:
                return .zoom2x
            case .zoom2x:
                return .telephoto
            case .telephoto:
                return .zoom8x
            case .zoom8x:
                return nil // Already at max zoom
            }
        }

        // If subject is too large (cropped), suggest zooming out
        if subjectSize > maxSubjectSize {
            switch currentLens {
            case .wide:
                return nil // Already at widest
            case .zoom2x:
                return .wide
            case .telephoto:
                return .zoom2x
            case .zoom8x:
                return .telephoto
            }
        }

        // Subject size is good, no lens change needed
        return nil
    }
}
