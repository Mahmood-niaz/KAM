import Vision
import CoreImage

struct SaliencyResult {
    let salientObjects: [VNRectangleObservation]
    let attentionCenter: CGPoint
    let heatmap: CVPixelBuffer?

    static let empty = SaliencyResult(salientObjects: [], attentionCenter: CGPoint(x: 0.5, y: 0.5), heatmap: nil)
}

final class SaliencyAnalyzer {
    private let attentionRequest = VNGenerateAttentionBasedSaliencyImageRequest()
    private let objectnessRequest = VNGenerateObjectnessBasedSaliencyImageRequest()

    func analyze(pixelBuffer: CVPixelBuffer) async -> SaliencyResult {
        return await withCheckedContinuation { continuation in
            let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, options: [:])

            do {
                try handler.perform([attentionRequest, objectnessRequest])

                var salientObjects: [VNRectangleObservation] = []
                var attentionCenter = CGPoint(x: 0.5, y: 0.5)
                var heatmap: CVPixelBuffer?

                // Extract attention-based results
                if let attentionObservation = attentionRequest.results?.first {
                    heatmap = attentionObservation.pixelBuffer

                    // Find attention center from heatmap
                    if let center = findAttentionCenter(from: attentionObservation) {
                        attentionCenter = center
                    }
                }

                // Extract objectness-based results (bounding boxes)
                if let objectnessObservation = objectnessRequest.results?.first,
                   let objects = objectnessObservation.salientObjects {
                    salientObjects = objects
                }

                let result = SaliencyResult(
                    salientObjects: salientObjects,
                    attentionCenter: attentionCenter,
                    heatmap: heatmap
                )

                continuation.resume(returning: result)
            } catch {
                print("Saliency analysis failed: \(error)")
                continuation.resume(returning: .empty)
            }
        }
    }

    private func findAttentionCenter(from observation: VNSaliencyImageObservation) -> CGPoint? {
        let pixelBuffer = observation.pixelBuffer

        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }

        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)

        guard let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer) else { return nil }

        let floatBuffer = baseAddress.assumingMemoryBound(to: Float.self)

        var weightedX: Float = 0
        var weightedY: Float = 0
        var totalWeight: Float = 0

        for y in 0..<height {
            for x in 0..<width {
                let index = y * width + x
                let weight = floatBuffer[index]

                if weight > 0.1 { // Threshold for significant saliency
                    weightedX += Float(x) * weight
                    weightedY += Float(y) * weight
                    totalWeight += weight
                }
            }
        }

        guard totalWeight > 0 else { return nil }

        // Normalize to 0-1 range
        let centerX = CGFloat(weightedX / totalWeight) / CGFloat(width)
        let centerY = CGFloat(weightedY / totalWeight) / CGFloat(height)

        return CGPoint(x: centerX, y: centerY)
    }
}
