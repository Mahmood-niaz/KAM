import SwiftUI

struct CompositionOverlayView: View {
    let gridType: GridType

    var body: some View {
        GeometryReader { geometry in
            switch gridType {
            case .ruleOfThirds:
                RuleOfThirdsGrid(size: geometry.size)
            case .goldenRatio:
                GoldenRatioGrid(size: geometry.size)
            case .goldenSpiral:
                GoldenSpiralGrid()
            case .diagonal:
                DiagonalGrid(size: geometry.size)
            case .none:
                EmptyView()
            }
        }
    }
}

// MARK: - Rule of Thirds Grid

struct RuleOfThirdsGrid: View {
    let size: CGSize

    private let lineColor = Color.white.opacity(0.8)

    var body: some View {
        Path { path in
            path.move(to: CGPoint(x: size.width / 3, y: 0))
            path.addLine(to: CGPoint(x: size.width / 3, y: size.height))

            path.move(to: CGPoint(x: 2 * size.width / 3, y: 0))
            path.addLine(to: CGPoint(x: 2 * size.width / 3, y: size.height))

            path.move(to: CGPoint(x: 0, y: size.height / 3))
            path.addLine(to: CGPoint(x: size.width, y: size.height / 3))

            path.move(to: CGPoint(x: 0, y: 2 * size.height / 3))
            path.addLine(to: CGPoint(x: size.width, y: 2 * size.height / 3))
        }
        .stroke(lineColor, lineWidth: 1)
    }
}

// MARK: - Golden Ratio Grid

struct GoldenRatioGrid: View {
    let size: CGSize

    private let lineColor = Color.white.opacity(0.8)
    private let goldenSection: CGFloat = 0.61803398875

    var body: some View {
        Path { path in
            path.move(to: CGPoint(x: size.width * (1 - goldenSection), y: 0))
            path.addLine(to: CGPoint(x: size.width * (1 - goldenSection), y: size.height))

            path.move(to: CGPoint(x: size.width * goldenSection, y: 0))
            path.addLine(to: CGPoint(x: size.width * goldenSection, y: size.height))

            path.move(to: CGPoint(x: 0, y: size.height * (1 - goldenSection)))
            path.addLine(to: CGPoint(x: size.width, y: size.height * (1 - goldenSection)))

            path.move(to: CGPoint(x: 0, y: size.height * goldenSection))
            path.addLine(to: CGPoint(x: size.width, y: size.height * goldenSection))
        }
        .stroke(lineColor, lineWidth: 1)
    }
}

// MARK: - Golden Spiral Grid

struct GoldenSpiralGrid: View {
    var body: some View {
        GoldenSpiralShape()
            .stroke(Color.yellow.opacity(0.85), style: StrokeStyle(lineWidth: 2, lineCap: .round))
            .shadow(color: .black.opacity(0.6), radius: 1)
    }
}

struct GoldenSpiralShape: Shape {
    private let phi: CGFloat = 1.61803398875

    func path(in rect: CGRect) -> Path {
        var path = Path()

        let maxAngle = 4 * CGFloat.pi
        let maxRadius = min(rect.width, rect.height) * 0.46
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let steps = 240

        for step in 0...steps {
            let angle = maxAngle * CGFloat(step) / CGFloat(steps)
            let radius = maxRadius * pow(phi, 2 * (angle - maxAngle) / (.pi / 2))
            let point = CGPoint(
                x: center.x + radius * cos(angle),
                y: center.y + radius * sin(angle)
            )

            if step == 0 {
                path.move(to: point)
            } else {
                path.addLine(to: point)
            }
        }

        return path
    }
}

// MARK: - Diagonal Grid

struct DiagonalGrid: View {
    let size: CGSize

    private let lineColor = Color.white.opacity(0.4)

    var body: some View {
        Path { path in
            // Main diagonals
            path.move(to: CGPoint(x: 0, y: 0))
            path.addLine(to: CGPoint(x: size.width, y: size.height))

            path.move(to: CGPoint(x: size.width, y: 0))
            path.addLine(to: CGPoint(x: 0, y: size.height))

            // Corner triangles (for baroque diagonal composition)
            path.move(to: CGPoint(x: 0, y: 0))
            path.addLine(to: CGPoint(x: size.width, y: size.height / 2))

            path.move(to: CGPoint(x: size.width, y: 0))
            path.addLine(to: CGPoint(x: 0, y: size.height / 2))

            path.move(to: CGPoint(x: 0, y: size.height))
            path.addLine(to: CGPoint(x: size.width, y: size.height / 2))

            path.move(to: CGPoint(x: size.width, y: size.height))
            path.addLine(to: CGPoint(x: 0, y: size.height / 2))
        }
        .stroke(lineColor, lineWidth: 1)
    }
}
