import Foundation
import CoreVideo

actor CompositionEngine {
    private let saliencyAnalyzer = SaliencyAnalyzer()
    private let ruleOfThirdsAnalyzer = RuleOfThirdsAnalyzer()
    private let goldenRatioAnalyzer = GoldenRatioAnalyzer()
    private let leadingLinesAnalyzer = LeadingLinesAnalyzer()
    private let nimaScorer = NIMAScorer()

    private var lastAnalysisTime: CFAbsoluteTime = 0
    private let minimumAnalysisInterval: CFAbsoluteTime = 0.05 // 20 FPS max

    private(set) var lastSaliencyResult: SaliencyResult = .empty

    func analyze(pixelBuffer: CVPixelBuffer) async -> CompositionScore {
        // Throttle analysis to prevent overwhelming the system
        let now = CFAbsoluteTimeGetCurrent()
        guard now - lastAnalysisTime >= minimumAnalysisInterval else {
            // Return a default score if we're analyzing too fast
            return CompositionScore.zero
        }
        lastAnalysisTime = now

        // Run saliency analysis first (used by multiple analyzers)
        let saliencyResult = await saliencyAnalyzer.analyze(pixelBuffer: pixelBuffer)
        lastSaliencyResult = saliencyResult

        // Run composition analyzers concurrently
        async let ruleOfThirdsScore = ruleOfThirdsAnalyzer.analyze(saliencyResult: saliencyResult)
        async let goldenRatioScore = goldenRatioAnalyzer.analyze(saliencyResult: saliencyResult)
        async let leadingLinesScore = leadingLinesAnalyzer.analyze(pixelBuffer: pixelBuffer, saliencyResult: saliencyResult)
        async let aestheticScore = nimaScorer.score(pixelBuffer: pixelBuffer)

        return CompositionScore(
            ruleOfThirds: await ruleOfThirdsScore,
            goldenRatio: await goldenRatioScore,
            leadingLines: await leadingLinesScore,
            aestheticQuality: await aestheticScore
        )
    }
}
