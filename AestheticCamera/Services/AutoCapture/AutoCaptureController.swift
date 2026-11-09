import Foundation

final class AutoCaptureController {
    // Configuration
    var minimumScoreThreshold: Float = 0.70
    var excellentScoreThreshold: Float = 0.85
    var cooldownDuration: TimeInterval = 2.0
    var scoreStabilityWindow: Int = 5
    var stabilityThreshold: Float = 0.02

    // State
    private var lastCaptureTime: Date?
    private var recentScores: [Float] = []
    private(set) var isEnabled: Bool = true

    // MARK: - Public API

    func setEnabled(_ enabled: Bool) {
        isEnabled = enabled
        if !enabled {
            recentScores.removeAll()
        }
    }

    func shouldCapture(score: CompositionScore) -> CaptureDecision {
        guard isEnabled else {
            return .skip(reason: .disabled)
        }

        // Check cooldown
        if let lastCapture = lastCaptureTime,
           Date().timeIntervalSince(lastCapture) < cooldownDuration {
            return .skip(reason: .cooldown)
        }

        let combinedScore = score.combined

        // Track recent scores for stability detection
        recentScores.append(combinedScore)
        if recentScores.count > scoreStabilityWindow {
            recentScores.removeFirst()
        }

        // Need enough history for stability analysis
        guard recentScores.count >= scoreStabilityWindow else {
            return .skip(reason: .buildingHistory)
        }

        // Check if score is above minimum threshold
        guard combinedScore >= minimumScoreThreshold else {
            return .skip(reason: .belowThreshold)
        }

        // Calculate score stability (low variance = stable)
        let variance = calculateVariance(recentScores)
        let isStable = variance < stabilityThreshold

        // Detect local maximum (score was rising, now falling/stable)
        let isLocalMaximum = detectLocalMaximum()

        // Capture conditions:
        // 1. Excellent score and stable - capture immediately
        if combinedScore >= excellentScoreThreshold && isStable {
            return .capture(confidence: .high, score: combinedScore)
        }

        // 2. Good score at local maximum (user found best spot while panning)
        if combinedScore >= minimumScoreThreshold && isLocalMaximum && isStable {
            return .capture(confidence: .medium, score: combinedScore)
        }

        // 3. Not stable enough yet
        if !isStable {
            return .skip(reason: .unstable)
        }

        return .skip(reason: .waitingForBetterMoment)
    }

    func recordCapture() {
        lastCaptureTime = Date()
        recentScores.removeAll()
    }

    func reset() {
        recentScores.removeAll()
        lastCaptureTime = nil
    }

    // MARK: - Private Helpers

    private func detectLocalMaximum() -> Bool {
        guard recentScores.count >= 3 else { return false }

        let recent = Array(recentScores.suffix(5))
        guard recent.count >= 3 else { return false }

        // Find the maximum in the window
        guard let maxIndex = recent.indices.max(by: { recent[$0] < recent[$1] }) else {
            return false
        }

        // Local maximum is in the middle portion (not at the very end = still rising)
        let isAtLocalMax = maxIndex >= 1 && maxIndex < recent.count - 1

        // Or if the last few scores are decreasing from a peak
        let isDecreasing = recent.count >= 3 &&
            recent[recent.count - 1] <= recent[recent.count - 2] &&
            recent[recent.count - 2] <= recent[recent.count - 3]

        return isAtLocalMax || isDecreasing
    }

    private func calculateVariance(_ values: [Float]) -> Float {
        guard !values.isEmpty else { return 0 }

        let mean = values.reduce(0, +) / Float(values.count)
        let squaredDiffs = values.map { ($0 - mean) * ($0 - mean) }
        return squaredDiffs.reduce(0, +) / Float(values.count)
    }
}
