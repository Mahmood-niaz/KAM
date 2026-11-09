import Foundation
import Vision

final class GoldenRatioAnalyzer {
    private let phi: CGFloat = 1.618033988749895
    private let phiInverse: CGFloat = 0.618033988749895

    // Golden ratio intersection points (phi positions)
    private let goldenPoints: [CGPoint] = [
        CGPoint(x: 0.382, y: 0.382),  // 1 - phi^-1
        CGPoint(x: 0.618, y: 0.382),  // phi^-1
        CGPoint(x: 0.382, y: 0.618),
        CGPoint(x: 0.618, y: 0.618)
    ]

    // Golden spiral approximate focal points (for different orientations)
    private let spiralFocalPoints: [CGPoint] = [
        CGPoint(x: 0.618, y: 0.382),  // Standard spiral
        CGPoint(x: 0.382, y: 0.382),  // Flipped horizontal
        CGPoint(x: 0.618, y: 0.618),  // Flipped vertical
        CGPoint(x: 0.382, y: 0.618)   // Flipped both
    ]

    func analyze(saliencyResult: SaliencyResult) -> Float {
        var scores: [Float] = []

        // Score salient objects against golden ratio points
        for object in saliencyResult.salientObjects {
            let centroid = CGPoint(
                x: object.boundingBox.midX,
                y: object.boundingBox.midY
            )
            let score = scorePosition(centroid)
            scores.append(score)
        }

        // Score attention center
        let attentionScore = scorePosition(saliencyResult.attentionCenter)
        scores.append(attentionScore)

        return scores.max() ?? 0.0
    }

    private func scorePosition(_ point: CGPoint) -> Float {
        // Score based on proximity to golden ratio points
        let goldenPointDistances = goldenPoints.map { goldenPoint in
            hypot(point.x - goldenPoint.x, point.y - goldenPoint.y)
        }
        let minGoldenDistance = goldenPointDistances.min() ?? 1.0

        // Score based on proximity to spiral focal points
        let spiralDistances = spiralFocalPoints.map { focalPoint in
            hypot(point.x - focalPoint.x, point.y - focalPoint.y)
        }
        let minSpiralDistance = spiralDistances.min() ?? 1.0

        // Golden point score (max distance ~0.5 from corner to nearest golden point)
        let goldenScore = Float(1.0 - (minGoldenDistance / 0.45))

        // Spiral focal point bonus (subjects in spiral focal area)
        let spiralBonus = Float(max(0, 1.0 - (minSpiralDistance / 0.25))) * 0.15

        // Check if subject fills frame according to golden ratio
        let frameScore = scoreFrameFill(point)

        let rawScore = max(goldenScore, frameScore) + spiralBonus

        return max(0, min(1, rawScore))
    }

    private func scoreFrameFill(_ point: CGPoint) -> Float {
        // Check if subject is positioned such that it divides frame by phi
        // e.g., subject at 0.382 from edge creates phi ratio

        let leftRatio = point.x
        let rightRatio = 1.0 - point.x
        let topRatio = point.y
        let bottomRatio = 1.0 - point.y

        let ratios = [leftRatio, rightRatio, topRatio, bottomRatio]

        // Check how close any ratio is to phi inverse (0.382 or 0.618)
        let phiDistances = ratios.flatMap { ratio -> [CGFloat] in
            [abs(ratio - 0.382), abs(ratio - 0.618)]
        }

        let minPhiDistance = phiDistances.min() ?? 1.0

        // Score based on proximity to phi ratio
        return Float(max(0, 1.0 - (minPhiDistance / 0.15))) * 0.6
    }
}
