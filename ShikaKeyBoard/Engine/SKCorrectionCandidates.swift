import Foundation

/// Candidate ranking and correction routes, independent of Rime's bridge API.
final class SKCorrectionCandidates {
    private let corrector: SKSpellingCorrector
    private let profile: SKSpellingProfile
    private var corrections: [Int: (code: String, text: String)] = [:]

    init?(resources: URL, configuration: SKInputConfiguration) {
        guard let corrector = SKSpellingCorrector(resources: resources, configuration: configuration) else { return nil }
        self.corrector = corrector
        profile = configuration.spelling
    }

    func selection(at index: Int) -> (code: String, text: String)? { corrections[index] }

    func present(_ result: SKEngineState, query: (String) -> SKEngineState) -> SKEngineState {
        corrections.removeAll(keepingCapacity: true)
        var state = result
        guard state.page == 0, !state.input.isEmpty,
              state.committedText.isEmpty,
              // A Hanzi prefix is a deliberate partial selection. Preserve the
              // native composition and its remaining segmentation unchanged.
              profile.allowsCorrection(preedit: state.preedit) else { return state }
        let exactFirst = state.candidates.first.map { corrector.isExact(comment: $0.comment, input: state.input) } ?? false
        var extra: [SKCandidate] = []
        var seen = Set(state.candidates.filter {
            corrector.isExact(comment: $0.comment, input: state.input)
        }.map(\.text))
        for suggestion in corrector.suggestions(for: state.input) {
            let queried = query(suggestion.code)
            guard let candidate = queried.candidates.first(where: { corrector.isExact(comment: $0.comment, input: suggestion.code) }),
                  seen.insert(candidate.text).inserted else { continue }
            let index = -1 - extra.count
            corrections[index] = (suggestion.code, candidate.text)
            extra.append(SKCandidate(index: index, text: candidate.text, comment: "纠错 · " + candidate.comment))
            if extra.count == 3 { break }
        }
        // A native partial candidate with the same text is not equivalent to a
        // full typo repair (e.g. 中国 for zhongguoo leaves an o). Prefer the
        // corrected route so selecting it consumes the complete mistyped code.
        let correctedTexts = Set(extra.map(\.text))
        state.candidates.removeAll { correctedTexts.contains($0.text) }
        if exactFirst {
            // Preserve all leading exact homophones, not just the first: a
            // correct second/third candidate must not be displaced by a typo.
            let exactCount = state.candidates.prefix(while: {
                corrector.isExact(comment: $0.comment, input: state.input)
            }).count
            state.candidates = Array(state.candidates.prefix(exactCount)) + extra + Array(state.candidates.dropFirst(exactCount))
        } else {
            state.candidates = extra + state.candidates
        }
        return state
    }

}
