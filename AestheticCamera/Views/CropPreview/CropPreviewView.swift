import SwiftUI

struct CropPreviewView: View {
    let image: UIImage
    let cropSuggestion: CropSuggestion
    let onAccept: (UIImage) -> Void
    let onReject: () -> Void

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 20) {
                // Header
                Text("Suggested Crop")
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(.white)

                // Image with crop overlay
                GeometryReader { geometry in
                    let imageSize = calculateImageSize(in: geometry.size)

                    ZStack {
                        // Original image (dimmed)
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFit()
                            .frame(width: imageSize.width, height: imageSize.height)
                            .opacity(0.4)

                        // Crop area (bright)
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFit()
                            .frame(width: imageSize.width, height: imageSize.height)
                            .mask(
                                Rectangle()
                                    .frame(
                                        width: cropSuggestion.width * imageSize.width,
                                        height: cropSuggestion.height * imageSize.height
                                    )
                                    .offset(
                                        x: (cropSuggestion.x + cropSuggestion.width / 2 - 0.5) * imageSize.width,
                                        y: (cropSuggestion.y + cropSuggestion.height / 2 - 0.5) * imageSize.height
                                    )
                            )

                        // Crop frame border
                        Rectangle()
                            .stroke(Color.yellow, lineWidth: 2)
                            .frame(
                                width: cropSuggestion.width * imageSize.width,
                                height: cropSuggestion.height * imageSize.height
                            )
                            .offset(
                                x: (cropSuggestion.x + cropSuggestion.width / 2 - 0.5) * imageSize.width,
                                y: (cropSuggestion.y + cropSuggestion.height / 2 - 0.5) * imageSize.height
                            )
                    }
                    .frame(width: geometry.size.width, height: geometry.size.height)
                }
                .aspectRatio(image.size.width / image.size.height, contentMode: .fit)
                .padding(.horizontal)

                // Explanation
                Text(cropSuggestion.explanation)
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.8))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)

                // Buttons
                VStack(spacing: 12) {
                    // Primary action - Save Cropped
                    Button(action: {
                        if let croppedImage = applyCrop(to: image, with: cropSuggestion) {
                            onAccept(croppedImage)
                        } else {
                            onReject()
                        }
                    }) {
                        HStack {
                            Image(systemName: "crop")
                                .font(.system(size: 16, weight: .semibold))
                            Text("Save Cropped")
                                .font(.headline)
                        }
                        .foregroundColor(.black)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(Color.yellow)
                        .clipShape(Capsule())
                    }

                    HStack(spacing: 12) {
                        // Discard
                        Button(action: onReject) {
                            HStack {
                                Image(systemName: "xmark")
                                    .font(.system(size: 14, weight: .semibold))
                                Text("Discard")
                                    .font(.subheadline.weight(.medium))
                            }
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(Color.white.opacity(0.2))
                            .clipShape(Capsule())
                        }

                        // Save Original
                        Button(action: {
                            onAccept(image)
                        }) {
                            HStack {
                                Image(systemName: "photo")
                                    .font(.system(size: 14, weight: .semibold))
                                Text("Original")
                                    .font(.subheadline.weight(.medium))
                            }
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(Color.white.opacity(0.2))
                            .clipShape(Capsule())
                        }
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 40)
            }
        }
    }

    private func calculateImageSize(in containerSize: CGSize) -> CGSize {
        let imageAspect = image.size.width / image.size.height
        let containerAspect = containerSize.width / containerSize.height

        if imageAspect > containerAspect {
            // Image is wider
            let width = containerSize.width
            let height = width / imageAspect
            return CGSize(width: width, height: height)
        } else {
            // Image is taller
            let height = containerSize.height
            let width = height * imageAspect
            return CGSize(width: width, height: height)
        }
    }

    private func applyCrop(to image: UIImage, with suggestion: CropSuggestion) -> UIImage? {
        // First, normalize the image orientation (iPhone photos have rotation metadata)
        guard let normalizedImage = normalizeOrientation(image) else { return nil }

        let imageWidth = normalizedImage.size.width * normalizedImage.scale
        let imageHeight = normalizedImage.size.height * normalizedImage.scale

        let cropRect = CGRect(
            x: suggestion.x * imageWidth,
            y: suggestion.y * imageHeight,
            width: suggestion.width * imageWidth,
            height: suggestion.height * imageHeight
        )

        guard let cgImage = normalizedImage.cgImage,
              let croppedCGImage = cgImage.cropping(to: cropRect) else { return nil }

        return UIImage(cgImage: croppedCGImage, scale: normalizedImage.scale, orientation: .up)
    }

    private func normalizeOrientation(_ image: UIImage) -> UIImage? {
        guard image.imageOrientation != .up else { return image }

        // Use UIGraphicsImageRenderer for better quality (uses optimal color space and format)
        let format = UIGraphicsImageRendererFormat()
        format.scale = image.scale
        format.preferredRange = .extended  // Preserve wide color gamut

        let renderer = UIGraphicsImageRenderer(size: image.size, format: format)
        let normalizedImage = renderer.image { context in
            image.draw(in: CGRect(origin: .zero, size: image.size))
        }

        return normalizedImage
    }
}
