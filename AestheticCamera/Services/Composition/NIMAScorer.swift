import CoreImage

/// Estimates image quality based on basic image properties (brightness, sharpness, contrast)
final class NIMAScorer {
    private let context = CIContext()

    func score(pixelBuffer: CVPixelBuffer) async -> Float {
        // Estimate quality from basic image properties
        return estimateQuality(pixelBuffer: pixelBuffer)
    }

    private func estimateQuality(pixelBuffer: CVPixelBuffer) -> Float {
        // Simple quality estimation based on image properties
        // This is a placeholder until NIMA model is integrated

        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)

        // Calculate average brightness
        let brightness = calculateAverageBrightness(ciImage)

        // Estimate sharpness (edge strength)
        let sharpness = estimateSharpness(ciImage)

        // Estimate contrast
        let contrast = estimateContrast(pixelBuffer)

        // Combine into quality score (1-10 scale)
        // Good photos typically have:
        // - Moderate brightness (not too dark or bright)
        // - Good sharpness
        // - Reasonable contrast

        let brightnessScore = 1.0 - abs(brightness - 0.5) * 2 // Penalize extreme brightness
        let sharpnessScore = min(1.0, sharpness / 0.3)
        let contrastScore = min(1.0, contrast / 0.3)

        let qualityScore = (brightnessScore * 0.3 + sharpnessScore * 0.4 + contrastScore * 0.3)

        // Map to 1-10 scale (NIMA range)
        return Float(4.0 + qualityScore * 4.0) // Range: 4-8
    }

    private func calculateAverageBrightness(_ image: CIImage) -> Float {
        let extent = image.extent
        let filter = CIFilter.areaAverage()
        filter.inputImage = image
        filter.extent = extent

        guard let outputImage = filter.outputImage else { return 0.5 }

        var bitmap = [UInt8](repeating: 0, count: 4)
        context.render(outputImage,
                      toBitmap: &bitmap,
                      rowBytes: 4,
                      bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
                      format: .RGBA8,
                      colorSpace: CGColorSpaceCreateDeviceRGB())

        let r = Float(bitmap[0]) / 255.0
        let g = Float(bitmap[1]) / 255.0
        let b = Float(bitmap[2]) / 255.0

        return (r + g + b) / 3.0
    }

    private func estimateSharpness(_ image: CIImage) -> Float {
        // Use edge detection to estimate sharpness
        let edgeFilter = CIFilter.edges()
        edgeFilter.inputImage = image
        edgeFilter.intensity = 1.0

        guard let edges = edgeFilter.outputImage else { return 0.5 }

        // Calculate average edge intensity
        let avgFilter = CIFilter.areaAverage()
        avgFilter.inputImage = edges
        avgFilter.extent = edges.extent

        guard let avgOutput = avgFilter.outputImage else { return 0.5 }

        var bitmap = [UInt8](repeating: 0, count: 4)
        context.render(avgOutput,
                      toBitmap: &bitmap,
                      rowBytes: 4,
                      bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
                      format: .RGBA8,
                      colorSpace: CGColorSpaceCreateDeviceRGB())

        return Float(bitmap[0]) / 255.0
    }

    private func estimateContrast(_ pixelBuffer: CVPixelBuffer) -> Float {
        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }

        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)

        guard let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer) else {
            return 0.5
        }

        let buffer = baseAddress.assumingMemoryBound(to: UInt8.self)

        var minBrightness: Float = 1.0
        var maxBrightness: Float = 0.0

        // Sample pixels to estimate contrast
        let sampleStep = max(1, (width * height) / 1000)
        for i in stride(from: 0, to: width * height, by: sampleStep) {
            let row = i / width
            let col = i % width
            let offset = row * bytesPerRow + col * 4

            let b = Float(buffer[offset]) / 255.0
            let g = Float(buffer[offset + 1]) / 255.0
            let r = Float(buffer[offset + 2]) / 255.0

            let brightness = (r + g + b) / 3.0
            minBrightness = min(minBrightness, brightness)
            maxBrightness = max(maxBrightness, brightness)
        }

        return maxBrightness - minBrightness
    }
}
