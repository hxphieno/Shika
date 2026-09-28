import Foundation

/// Rime can rank a sequence of initials ahead of a longer syllable prefix
/// (zhon -> z'h'o'n instead of zhong). Probe legal completions explicitly.
final class SKPinyinPrefixCandidates {
    private let syllables: Set<String>
    private var selections: [Int: (code: String, text: String)] = [:]

    init?(resources: URL, configuration: SKInputConfiguration) {
        guard configuration.spelling == .fullPinyin,
              let data = try? Data(contentsOf: resources.appendingPathComponent("correction-syllables.json")),
              let mapping = try? JSONDecoder().decode([String: String].self, from: data) else { return nil }
        syllables = Set(mapping.keys).union(["nue", "lue"])
    }

    func selection(at index: Int) -> (code: String, text: String)? { selections[index] }

    func present(_ result: SKEngineState, query: (String) -> SKEngineState) -> SKEngineState {
        selections.removeAll(keepingCapacity: true)
        let raw = Array(result.input)
        guard result.page == 0, result.committedText.isEmpty, (2...48).contains(raw.count),
              raw.allSatisfy({ $0.isASCII && ($0.isLowercase || $0 == "'") }),
              !result.preedit.unicodeScalars.contains(where: { $0.value > 127 }) else { return result }
        var boundaries: Set<Int> = [0], completions = Set<String>()
        for start in raw.indices where boundaries.contains(start) {
            if raw[start] == "'" {
                if start > 0 { boundaries.insert(start + 1) }
                continue
            }
            let tail = String(raw[start...])
            // Single-letter initials already have a broad native candidate list.
            if (2...5).contains(tail.count), !tail.contains("'") {
                for syllable in syllables where syllable.count > tail.count && syllable.hasPrefix(tail) {
                    completions.insert(result.input + syllable.dropFirst(tail.count))
                }
            }
            for end in (start + 1)...min(raw.count, start + 6) {
                if syllables.contains(String(raw[start..<end])) { boundaries.insert(end) }
            }
        }
        var extra: [SKCandidate] = [], seen = Set<String>()
        for code in completions.sorted(by: { $0.count == $1.count ? $0 < $1 : $0.count < $1.count }).prefix(4) {
            guard let candidate = query(code).candidates.first(where: {
                SKSpellingProfile.fullPinyin.isExact(comment: $0.comment, input: code, syllables: [:])
            }), seen.insert(candidate.text).inserted else { continue }
            // A matching native completion already owns the right selection.
            if result.candidates.contains(where: {
                $0.text == candidate.text && ($0.comment == candidate.comment ||
                    SKSpellingProfile.fullPinyin.isExact(comment: $0.comment, input: result.input, syllables: [:]))
            }) { continue }
            let index = -300 - extra.count
            selections[index] = (code, candidate.text)
            extra.append(SKCandidate(index: index, text: candidate.text, comment: candidate.comment))
        }
        var state = result
        let texts = Set(extra.map(\.text))
        state.candidates.removeAll { texts.contains($0.text) }
        let exactCount = state.candidates.prefix(while: {
            SKSpellingProfile.fullPinyin.isExact(comment: $0.comment, input: result.input, syllables: [:])
        }).count
        state.candidates.insert(contentsOf: extra, at: exactCount)
        return state
    }
}
