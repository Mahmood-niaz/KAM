import Foundation

struct CompositionScore {
    let ruleOfThirds: Float      // 0-1
    let goldenRatio: Float       // 0-1
    let leadingLines: Float      // 0-1
    let aestheticQuality: Float  // 0-10 (NIMA scale)

    var combined: Float {
        // 100% aesthetic-based scoring using NIMA
        // NIMA typically returns 4-7 for most images, rarely above 7
        // Map practical range (3-8) to (10%-95%) for better UX
        let clampedNIMA = min(max(aestheticQuality, 3.0), 8.0)
        let normalizedNIMA = (clampedNIMA - 3.0) / 5.0  // Maps 3-8 to 0-1

        // Apply slight curve to make middle scores more spread out
        let adjustedScore = pow(normalizedNIMA, 0.85)

        return adjustedScore * 0.85 + 0.10  // Range: 10% to 95%
    }

    var isOptimal: Bool {
        combined >= 0.70
    }

    var isExcellent: Bool {
        combined >= 0.85
    }

    static let zero = CompositionScore(
        ruleOfThirds: 0,
        goldenRatio: 0,
        leadingLines: 0,
        aestheticQuality: 5
    )
}

extension CompositionScore: CustomStringConvertible {
    var description: String {
        String(format: "RoT: %.0f%% | Golden: %.0f%% | Lines: %.0f%% | NIMA: %.1f | Combined: %.0f%%",
               ruleOfThirds * 100,
               goldenRatio * 100,
               leadingLines * 100,
               aestheticQuality,
               combined * 100)
    }
}
