import Foundation
import Vision

final class RuleOfThirdsAnalyzer {
    // Rule of thirds intersection points (normalized 0-1)
    // Note: Vision coordinates have origin at bottom-left
    private let intersectionPoints: [CGPoint] = [
        CGPoint(x: 1.0/3.0, y: 1.0/3.0),
        CGPoint(x: 2.0/3.0, y: 1.0/3.0),
        CGPoint(x: 1.0/3.0, y: 2.0/3.0),
        CGPoint(x: 2.0/3.0, y: 2.0/3.0)
    ]

    // Rule of thirds lines (for subjects aligned along lines)
    private let verticalLines: [CGFloat] = [1.0/3.0, 2.0/3.0]
    private let horizontalLines: [CGFloat] = [1.0/3.0, 2.0/3.0]

    func analyze(saliencyResult: SaliencyResult) -> Float {
        // Use both salient objects and attention center
        var scores: [Float] = []

        // Score based on salient object positions
        for object in saliencyResult.salientObjects {
            let centroid = CGPoint(
                x: object.boundingBox.midX,
                y: object.boundingBox.midY
            )
            let score = scorePosition(centroid)
            scores.append(score)
        }

        // Also score the attention center
        let attentionScore = scorePosition(saliencyResult.attentionCenter)
        scores.append(attentionScore)

        // Return the best score (most aligned with rule of thirds)
        return scores.max() ?? 0.0
    }

    private func scorePosition(_ point: CGPoint) -> Float {
        // Calculate minimum distance to any intersection point
        let intersectionDistances = intersectionPoints.map { intersection in
            hypot(point.x - intersection.x, point.y - intersection.y)
        }
        let minIntersectionDistance = intersectionDistances.min() ?? 1.0

        // Calculate minimum distance to vertical lines
        let minVerticalDistance = verticalLines.map { abs(point.x - $0) }.min() ?? 1.0

        // Calculate minimum distance to horizontal lines
        let minHorizontalDistance = horizontalLines.map { abs(point.y - $0) }.min() ?? 1.0

        // Combined line distance (for subjects on lines but not intersections)
        let lineDistance = min(minVerticalDistance, minHorizontalDistance)

        // Score calculation:
        // - Perfect intersection alignment: score approaches 1.0
        // - Good line alignment: score around 0.6-0.8
        // - Center or corners: lower score

        // Maximum possible distance from intersection is ~0.47 (corner to nearest intersection)
        let intersectionScore = Float(1.0 - (minIntersectionDistance / 0.47))

        // Maximum line distance is 1/6 (0.167) for points between lines
        let lineScore = Float(1.0 - (lineDistance / 0.167)) * 0.7

        // Use the better of intersection or line alignment
        let rawScore = max(intersectionScore, lineScore)

        // Penalize dead center (boring composition)
        let centerDistance = hypot(point.x - 0.5, point.y - 0.5)
        let centerPenalty: Float = centerDistance < 0.1 ? 0.3 : 0.0

        return max(0, min(1, rawScore - centerPenalty))
    }
}
