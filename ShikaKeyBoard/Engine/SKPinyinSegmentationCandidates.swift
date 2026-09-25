import Foundation

/// Enumerates bounded, valid syllable paths which Rime's sentence pruning may
/// omit. Rime still performs all word lookup, sentence scoring and learning.
final class SKPinyinSegmentationCandidates {
    private let syllables: Set<String>
    private var selections: [Int: (code: String, text: String)] = [:]
    // Only immutable syllable paths are reused. Native words and learned rank
    // are queried afresh, including when deleting and retyping the same input.
    private var pathCache: [String: [String]] = [:]
    private var pathCacheOrder: [String] = []

    init?(resources: URL, configuration: SKInputConfiguration) {
        guard configuration.spelling == .fullPinyin,
              let data = try? Data(contentsOf: resources.appendingPathComponent("correction-syllables.json")),
              let mapping = try? JSONDecoder().decode([String: String].self, from: data) else { return nil }
        syllables = Set(mapping.keys).union(["nue", "lue"])
    }
    func selection(at index: Int) -> (code: String, text: String)? { selections[index] }

    func present(_ result: SKEngineState, query: (String) -> SKEngineState) -> SKEngineState {
        selections.removeAll(keepingCapacity: true)
        var state = result
        let raw = Array(state.input)
        guard state.page == 0, state.committedText.isEmpty, (3...32).contains(raw.count),
              raw.allSatisfy({ $0.isASCII && $0.isLowercase }),
              !state.preedit.unicodeScalars.contains(where: { $0.value > 127 }) else { return state }
        let paths = segmentationPaths(for: state.input, characters: raw)
        guard paths.count > 1 else { return state }
        func code(_ comment: String) -> String {
            comment.split(whereSeparator: { $0 == " " || $0 == "'" }).joined(separator: "'")
        }
        let existingPaths = Set(state.candidates.map { code($0.comment) })
        var seen = Set(state.candidates.map(\.text))
        var extra: [SKCandidate] = []
        for path in paths.filter({ !existingPaths.contains($0) }).prefix(1) {
            let queried = query(path)
            guard let candidate = queried.candidates.first(where: { code($0.comment) == path }),
                  seen.insert(candidate.text).inserted else { continue }
            let index = -100 - extra.count
            selections[index] = (path, candidate.text)
            extra.append(SKCandidate(index: index, text: candidate.text, comment: candidate.comment))
        }
        // Preserve the native first choice; show alternative full parses before
        // partial prefixes, without treating them as spelling corrections.
        let prefix = state.candidates.prefix(while: {
            $0.comment.replacingOccurrences(of: " ", with: "").replacingOccurrences(of: "'", with: "") == state.input
        }).count
        state.candidates.insert(contentsOf: extra, at: min(5, prefix))
        return state
    }

    private func segmentationPaths(for input: String, characters raw: [Character]) -> [String] {
        if let cached = pathCache[input] { return cached }
        // Dynamic programming bounds work even for highly ambiguous long input.
        var paths = Array(repeating: [[String]](), count: raw.count + 1)
        paths[raw.count] = [[]]
        for start in stride(from: raw.count - 1, through: 0, by: -1) {
            for end in (start + 1)...min(raw.count, start + 6) {
                let syllable = String(raw[start..<end])
                guard syllables.contains(syllable) else { continue }
                paths[start] += paths[end].map { [syllable] + $0 }
            }
            paths[start] = Array(paths[start].sorted {
                $0.count == $1.count ? $0.joined(separator: "'") < $1.joined(separator: "'") : $0.count < $1.count
            }.prefix(8))
        }
        let result = paths[0].map { $0.joined(separator: "'") }
        if pathCacheOrder.count == 32 { pathCache.removeValue(forKey: pathCacheOrder.removeFirst()) }
        pathCacheOrder.append(input); pathCache[input] = result
        return result
    }
}
