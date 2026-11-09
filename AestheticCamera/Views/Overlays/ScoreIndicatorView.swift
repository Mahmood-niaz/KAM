import SwiftUI

struct ScoreIndicatorView: View {
    let score: CompositionScore
    let showDetails: Bool

    var body: some View {
        VStack(spacing: 8) {
            // Main score bar
            mainScoreBar

            // Detailed breakdown (expandable)
            if showDetails {
                detailedScores
                    .transition(.opacity.combined(with: .scale))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: showDetails)
    }

    // MARK: - Main Score Bar

    private var mainScoreBar: some View {
        HStack(spacing: 12) {
            // Score indicator icon
            scoreIcon

            // Progress bar
            VStack(alignment: .leading, spacing: 4) {
                Text("Composition")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.7))

                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        // Background
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.white.opacity(0.2))
                            .frame(height: 8)

                        // Progress
                        RoundedRectangle(cornerRadius: 4)
                            .fill(scoreColor)
                            .frame(width: geometry.size.width * CGFloat(score.combined), height: 8)
                            .animation(.easeOut(duration: 0.2), value: score.combined)
                    }
                }
                .frame(height: 8)
            }
            .frame(maxWidth: 150)

            // Percentage text
            Text("\(Int(score.combined * 100))%")
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundColor(scoreColor)
                .frame(minWidth: 50, alignment: .trailing)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    // MARK: - Score Icon

    private var scoreIcon: some View {
        ZStack {
            Circle()
                .fill(scoreColor.opacity(0.2))
                .frame(width: 36, height: 36)

            Image(systemName: scoreIconName)
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(scoreColor)
        }
    }

    private var scoreIconName: String {
        switch score.combined {
        case 0.85...: return "checkmark.circle.fill"
        case 0.70...: return "circle.fill"
        case 0.50...: return "circle.bottomhalf.filled"
        default: return "circle"
        }
    }

    // MARK: - Detailed Scores

    private var detailedScores: some View {
        VStack(spacing: 8) {
            ScoreRow(label: "Rule of Thirds", value: score.ruleOfThirds, icon: "grid")
            ScoreRow(label: "Golden Ratio", value: score.goldenRatio, icon: "circle.grid.cross")
            ScoreRow(label: "Leading Lines", value: score.leadingLines, icon: "arrow.up.right")
            ScoreRow(label: "Aesthetic", value: score.aestheticQuality / 10, icon: "sparkles")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    // MARK: - Score Color

    private var scoreColor: Color {
        switch score.combined {
        case 0.85...: return .green
        case 0.70...: return .yellow
        case 0.50...: return .orange
        default: return .red
        }
    }
}

// MARK: - Score Row

struct ScoreRow: View {
    let label: String
    let value: Float
    let icon: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundColor(.white.opacity(0.6))
                .frame(width: 20)

            Text(label)
                .font(.caption)
                .foregroundColor(.white.opacity(0.8))

            Spacer()

            // Mini progress bar
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.white.opacity(0.2))
                        .frame(height: 4)

                    RoundedRectangle(cornerRadius: 2)
                        .fill(rowColor)
                        .frame(width: geometry.size.width * CGFloat(value), height: 4)
                }
            }
            .frame(width: 60, height: 4)

            Text("\(Int(value * 100))%")
                .font(.caption2)
                .foregroundColor(.white.opacity(0.7))
                .frame(width: 35, alignment: .trailing)
        }
    }

    private var rowColor: Color {
        switch value {
        case 0.7...: return .green
        case 0.5...: return .yellow
        default: return .orange
        }
    }
}

#Preview {
    ZStack {
        Color.black
        VStack {
            ScoreIndicatorView(
                score: CompositionScore(
                    ruleOfThirds: 0.75,
                    goldenRatio: 0.6,
                    leadingLines: 0.4,
                    aestheticQuality: 7.5
                ),
                showDetails: true
            )
        }
        .padding()
    }
}
