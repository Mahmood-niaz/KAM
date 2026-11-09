import SwiftUI

struct CompositionGuideView: View {
    let guide: CompositionGuide
    let onLensTap: (CameraLens) -> Void

    var body: some View {
        // Guidance text banner only
        HStack(spacing: 12) {
            // Quality indicator
            Circle()
                .fill(guideColor)
                .frame(width: 12, height: 12)

            Text(guide.guidanceText)
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(.white)

            // Lens suggestion button
            if let suggestedLens = guide.suggestedLens {
                Button(action: { onLensTap(suggestedLens) }) {
                    Text(suggestedLens.icon)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.black)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Color.yellow)
                        .cornerRadius(12)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color.black.opacity(0.6))
        .cornerRadius(20)
    }

    private var guideColor: Color {
        if guide.isExcellentComposition {
            return .green
        } else if guide.isGoodComposition {
            return .yellow
        } else {
            return .orange
        }
    }
}

#Preview {
    ZStack {
        Color.black

        CompositionGuideView(
            guide: CompositionGuide(
                horizontalHint: .moveRight,
                verticalHint: .moveUp,
                suggestedLens: .zoom2x,
                compositionQuality: 0.45,
                subjectPosition: CGPoint(x: 0.5, y: 0.5),
                idealPosition: CGPoint(x: 0.667, y: 0.333)
            ),
            onLensTap: { _ in }
        )
    }
}
