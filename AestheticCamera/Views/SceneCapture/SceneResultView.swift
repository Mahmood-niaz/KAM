import SwiftUI

struct SceneResultView: View {
    let originalImage: UIImage
    let cropSuggestion: CropSuggestion
    let selectionReason: String
    let onSave: (UIImage) -> Void
    let onDiscard: () -> Void

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 20) {
                // Header
                Text("Best Shot Selected")
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(.white)

                // Selection reason
                Text(selectionReason)
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.8))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)

                // Image with crop overlay
                GeometryReader { geometry in
                    let imageSize = calculateImageSize(in: geometry.size)

                    ZStack {
                        // Original image (dimmed)
                        Image(uiImage: originalImage)
                            .resizable()
                            .scaledToFit()
                            .frame(width: imageSize.width, height: imageSize.height)
                            .opacity(0.4)

                        // Crop area (bright)
                        Image(uiImage: originalImage)
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
                .aspectRatio(originalImage.size.width / originalImage.size.height, contentMode: .fit)
                .padding(.horizontal)

                // Crop explanation
                Text(cropSuggestion.explanation)
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.7))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)

                // Buttons
                HStack(spacing: 16) {
                    // Discard
                    Button(action: onDiscard) {
                        HStack {
                            Image(systemName: "xmark")
                                .font(.system(size: 16, weight: .semibold))
                            Text("Discard")
                                .font(.headline)
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(Color.white.opacity(0.2))
                        .clipShape(Capsule())
                    }

                    // Save
                    Button(action: {
                        if let croppedImage = applyCrop(to: originalImage, with: cropSuggestion) {
                            onSave(croppedImage)
                        } else {
                            onDiscard()
                        }
                    }) {
                        HStack {
                            Image(systemName: "checkmark")
                                .font(.system(size: 16, weight: .semibold))
                            Text("Save")
                                .font(.headline)
                        }
                        .foregroundColor(.black)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(Color.yellow)
                        .clipShape(Capsule())
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 40)
            }
        }
    }

    private func calculateImageSize(in containerSize: CGSize) -> CGSize {
        let imageAspect = originalImage.size.width / originalImage.size.height
        let containerAspect = containerSize.width / containerSize.height

        if imageAspect > containerAspect {
            let width = containerSize.width
            let height = width / imageAspect
            return CGSize(width: width, height: height)
        } else {
            let height = containerSize.height
            let width = height * imageAspect
            return CGSize(width: width, height: height)
        }
    }

    private func applyCrop(to image: UIImage, with suggestion: CropSuggestion) -> UIImage? {
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

        UIGraphicsBeginImageContextWithOptions(image.size, false, image.scale)
        image.draw(in: CGRect(origin: .zero, size: image.size))
        let normalizedImage = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()

        return normalizedImage
    }
}
