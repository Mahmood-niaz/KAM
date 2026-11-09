import CoreImage
import CoreImage.CIFilterBuiltins
import Vision

final class LeadingLinesAnalyzer {
    private let context = CIContext()

    func analyze(pixelBuffer: CVPixelBuffer, saliencyResult: SaliencyResult) async -> Float {
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)

        // Apply edge detection
        guard let edges = detectEdges(ciImage) else {
            return 0.3 // Default neutral score
        }

        // Analyze edge patterns for leading lines
        let lineScore = analyzeEdgePatterns(edges, targetPoint: saliencyResult.attentionCenter)

        return lineScore
    }

    private func detectEdges(_ image: CIImage) -> CIImage? {
        // Use Sobel edge detection for line detection
        let edgeFilter = CIFilter.edges()
        edgeFilter.inputImage = image
        edgeFilter.intensity = 1.0

        return edgeFilter.outputImage
    }

    private func analyzeEdgePatterns(_ edges: CIImage, targetPoint: CGPoint) -> Float {
        // Simplified heuristic analysis for leading lines
        // In a full implementation, this would use Hough transform or ML

        // Sample edge intensity in different directions from center
        let imageSize = edges.extent.size
        let center = CGPoint(x: imageSize.width / 2, y: imageSize.height / 2)
        let target = CGPoint(x: targetPoint.x * imageSize.width,
                            y: targetPoint.y * imageSize.height)

        // Calculate direction from center to target
        let dx = target.x - center.x
        let dy = target.y - center.y
        let targetAngle = atan2(dy, dx)

        // Check for convergence patterns (lines pointing toward subject)
        var convergenceScore: Float = 0.0

        // Check corners for diagonal lines pointing inward
        let corners: [(CGPoint, CGFloat)] = [
            (CGPoint(x: 0, y: 0), .pi / 4),                    // Bottom-left to center
            (CGPoint(x: imageSize.width, y: 0), 3 * .pi / 4),  // Bottom-right to center
            (CGPoint(x: 0, y: imageSize.height), -.pi / 4),    // Top-left to center
            (CGPoint(x: imageSize.width, y: imageSize.height), -3 * .pi / 4) // Top-right to center
        ]

        // Simple scoring based on potential diagonal composition
        // Real implementation would analyze actual edge directions
        for (corner, expectedAngle) in corners {
            let angleToTarget = atan2(target.y - corner.y, target.x - corner.x)
            let angleDiff = abs(angleToTarget - expectedAngle)

            // If target is along a diagonal, score higher
            if angleDiff < .pi / 6 {
                convergenceScore += 0.25
            }
        }

        // Check for horizontal/vertical alignment (less dynamic but still compositional)
        let horizontalAlignment = 1.0 - Float(abs(target.y - center.y) / imageSize.height)
        let verticalAlignment = 1.0 - Float(abs(target.x - center.x) / imageSize.width)

        // Slight bonus for subjects not dead center
        let offCenterBonus: Float = (abs(targetPoint.x - 0.5) > 0.15 || abs(targetPoint.y - 0.5) > 0.15) ? 0.1 : 0.0

        // Combine scores
        let alignmentScore = max(horizontalAlignment, verticalAlignment) * 0.3
        let finalScore = convergenceScore + alignmentScore + offCenterBonus

        return max(0, min(1, finalScore))
    }
}
