import Foundation

/// A read-only Rime syllable search supplements the fixed whole-word index.
/// Main-session spelling, learning and partial selections remain authoritative.
final class SKSyllableCorrectionCandidates {
    private let mapping: [String: String]
    private var selections: [Int: (code: String, text: String)] = [:]

    init?(resources: URL, configuration: SKInputConfiguration) {
        guard configuration.spelling == .doublePinyin,
              let data = try? Data(contentsOf: resources.appendingPathComponent("correction-syllables.json")),
              let mapping = try? JSONDecoder().decode([String: String].self, from: data) else { return nil }
        self.mapping = mapping
    }

    func selection(at index: Int) -> (code: String, text: String)? { selections[index] }

    func present(_ result: SKEngineState, query: (String) -> SKEngineState) -> SKEngineState {
        selections.removeAll(keepingCapacity: true)
        let raw = Array(result.input.utf8)
        guard result.page == 0, result.committedText.isEmpty, (4...32).contains(raw.count), raw.count % 2 == 0,
              raw.allSatisfy({ (97...122).contains($0) }),
              !result.preedit.unicodeScalars.contains(where: { $0.value > 127 }) else { return result }
        func code(_ comment: String) -> String? {
            let syllables = comment.split(whereSeparator: { $0 == " " || $0 == "'" })
            let values = syllables.compactMap { mapping[String($0)] }
            return !values.isEmpty && values.count == syllables.count ? values.joined() : nil
        }
        func complete(_ candidate: SKCandidate) -> Bool {
            candidate.index < 0 || code(candidate.comment) == result.input
        }
        var state = result
        var seen = Set(state.candidates.filter(complete).map(\.text))
        var extra: [SKCandidate] = []
        for candidate in query(result.input).candidates {
            guard let corrected = code(candidate.comment), corrected != result.input,
                  corrected.utf8.count == raw.count else { continue }
            let edits = zip(corrected.utf8, raw).filter { $0 != $1 }.count
            guard (1...2).contains(edits), seen.insert(candidate.text).inserted else { continue }
            let index = -200 - extra.count
            selections[index] = (corrected, candidate.text)
            extra.append(SKCandidate(index: index, text: candidate.text, comment: "纠错 · " + candidate.comment,
                consumedInputCount: raw.count))
            if extra.count == 3 { break }
        }
        // Keep the original first three and all exact homophones ahead of new
        // guesses. Replace only equivalent partial routes with complete repairs.
        var remaining: [SKCandidate] = []
        for candidate in extra {
            if let position = state.candidates.firstIndex(where: { $0.text == candidate.text && !complete($0) }) {
                state.candidates[position] = candidate
            } else { remaining.append(candidate) }
        }
        let exactEnd = state.candidates.lastIndex(where: complete).map { $0 + 1 } ?? 0
        state.candidates.insert(contentsOf: remaining, at: min(state.candidates.count, max(3, exactEnd)))
        return state
    }
}
