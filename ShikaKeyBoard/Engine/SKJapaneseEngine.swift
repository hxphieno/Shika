import Foundation

/// Kana conversion and N-best word connection policy over the offline Mozc data.
@MainActor
final class SKJapaneseEngine: SKInputEngine {
    private let lexicon: SKJapaneseLexicon
    private let learningURL: URL
    private var learned: [String: [String: Int]]
    private var input = ""
    private var kana = ""
    private var pending = ""
    private var texts: [String] = []
    private var page = 0

    init(resources: URL, userDirectory: URL) throws {
        lexicon = try SKJapaneseLexicon(resources: resources)
        try FileManager.default.createDirectory(at: userDirectory, withIntermediateDirectories: true)
        learningURL = userDirectory.appendingPathComponent("japanese-learning.json")
        learned = (try? JSONDecoder().decode([String: [String: Int]].self, from: Data(contentsOf: learningURL))) ?? [:]
    }

    func replaceInput(_ text: String) -> SKEngineState {
        input = text; page = 0
        (kana, pending) = lexicon.reading(input)
        texts = pending.isEmpty ? lexicon.convert(kana) : []
        // Promotion applies only to a previously selected, still valid candidate.
        let scores = learned[kana] ?? [:]
        texts = texts.enumerated().sorted {
            let a = scores[$0.element] ?? 0, b = scores[$1.element] ?? 0
            return a == b ? $0.offset < $1.offset : a > b
        }.map(\.element)
        return snapshot()
    }

    func process(key: Int32) -> SKEngineState {
        if key == 0x20 { return commit() }
        if key == 0xff08 { return replaceInput(String(input.dropLast())) }
        guard let scalar = UnicodeScalar(UInt32(bitPattern: key)),
              (97...122).contains(key) || key == 39 || key == 45 else {
            var state = snapshot(); state.handled = false; return state
        }
        return replaceInput(input + String(scalar))
    }

    func selectCandidate(at index: Int) -> SKEngineState {
        guard texts.indices.contains(index) else { return snapshot() }
        let text = texts[index]
        var words = learned[kana] ?? [:]
        words[text] = min(10000, (words[text] ?? 0) + 1)
        learned[kana] = words
        // Bound the persistent learning file independently of corpus size.
        if learned.count > 1024, let evicted = learned.keys.sorted().first(where: { $0 != kana }) {
            learned.removeValue(forKey: evicted)
        }
        if let bytes = try? JSONEncoder().encode(learned) { try? bytes.write(to: learningURL, options: .atomic) }
        var state = clear(); state.committedText = text; return state
    }
    func commit() -> SKEngineState {
        if !texts.isEmpty { return selectCandidate(at: 0) }
        let text = kana + pending
        var state = clear(); state.committedText = text; return state
    }
    func clear() -> SKEngineState {
        input = ""; kana = ""; pending = ""; texts = []; page = 0
        return snapshot()
    }
    func candidatePage(startingAt index: Int, limit: Int) -> SKCandidatePage {
        let start = max(0, min(index, texts.count)), end = min(texts.count, start + max(0, min(limit, 64)))
        return SKCandidatePage(candidates: (start..<end).map {
            SKCandidate(index: $0, text: texts[$0], comment: "日文 · " + kana)
        }, nextIndex: end, hasMore: end < texts.count)
    }
    func changePage(backward: Bool) -> SKEngineState {
        page = max(0, min(max(0, (texts.count - 1) / 8), page + (backward ? -1 : 1)))
        return snapshot()
    }
    func selectConfiguration(_ configuration: SKInputConfiguration) throws -> SKEngineState {
        guard configuration.language == .japanese else { throw SKRimeEngine.EngineError.missingResources }
        return clear()
    }
    private func snapshot() -> SKEngineState {
        let items = candidatePage(startingAt: page * 8, limit: 8)
        return SKEngineState(input: input, preedit: kana + pending, candidates: items.candidates,
            page: page, isLastPage: !items.hasMore)
    }
}
