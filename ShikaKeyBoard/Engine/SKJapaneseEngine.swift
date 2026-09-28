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
    private struct Choice {
        let text: String
        let reading: String
        let raw: String
        var identity: SKCandidate.ContentIdentity { .init(text: text, consumedInputCount: raw.count) }
    }
    private var choices: [Choice] = []
    private var locked: [Choice] = []
    private var lockedCount: Int { locked.reduce(0) { $0 + $1.raw.count } }
    private var prefix: String { locked.map(\.text).joined() }
    private var remaining: String { String(input.dropFirst(lockedCount)) }
    private var page = 0

    init(resources: URL, userDirectory: URL) throws {
        lexicon = try SKJapaneseLexicon(resources: resources)
        try FileManager.default.createDirectory(at: userDirectory, withIntermediateDirectories: true)
        learningURL = userDirectory.appendingPathComponent("japanese-learning.json")
        learned = (try? JSONDecoder().decode([String: [String: Int]].self, from: Data(contentsOf: learningURL))) ?? [:]
    }

    func replaceInput(_ text: String) -> SKEngineState {
        input = text; locked = []
        return refresh()
    }

    private func refresh() -> SKEngineState {
        page = 0
        let raw = remaining
        (kana, pending) = lexicon.reading(raw)
        var recommendations: [Choice], words: [Choice] = []
        if pending.isEmpty {
            recommendations = lexicon.convert(kana).map { Choice(text: $0, reading: kana, raw: raw) }
            words = lexicon.words(for: kana).sorted { $0.cost < $1.cost }.map {
                Choice(text: $0.text, reading: kana, raw: raw)
            }
        }
        else {
            recommendations = lexicon.completionWords(for: raw).map {
                Choice(text: $0.word.text, reading: $0.reading, raw: raw)
            }
            words = recommendations
        }
        // Prefixes must end on a real romanization boundary. Re-reading both
        // sides guards n/nn and doubled consonants; output length is not an offset.
        if raw.count > 1, !recommendations.isEmpty {
            for end in stride(from: min(raw.count - 1, 96), through: 1, by: -1) {
                let head = String(raw.prefix(end)), tail = String(raw.dropFirst(end))
                let a = lexicon.reading(head), b = lexicon.reading(tail)
                guard a.pending.isEmpty, !a.kana.isEmpty,
                      a.kana + b.kana == kana, b.pending == pending else { continue }
                words += lexicon.words(for: a.kana).sorted { $0.cost < $1.cost }.map {
                    Choice(text: $0.text, reading: a.kana, raw: head)
                }
            }
        }
        // Promotion applies only to a previously selected, still valid candidate.
        func ranked(_ items: [Choice]) -> [Choice] {
            items.enumerated().sorted {
                let a = learned[$0.element.reading]?[$0.element.text] ?? 0
                let b = learned[$1.element.reading]?[$1.element.text] ?? 0
                return a == b ? $0.offset < $1.offset : a > b
            }.map(\.element)
        }
        // A full dictionary choice outside the old N-best list can also be
        // learned after expansion. Let that selection compete at the top.
        let recommended = Set(recommendations.map(\.identity))
        recommendations += words.filter {
            $0.raw == raw && !recommended.contains($0.identity) && (learned[$0.reading]?[$0.text] ?? 0) > 0
        }
        recommendations = ranked(recommendations)
        choices = SKCandidateGrouping.arrange(recommendations: recommendations, words: ranked(words),
            text: { $0.text }, identity: { $0.identity })
        // Keep the reading easy to select, independently of learned word order.
        if pending.isEmpty && !kana.isEmpty {
            choices.removeAll { $0.text == kana && $0.raw == raw }
            choices.insert(Choice(text: kana, reading: kana, raw: raw), at: min(2, choices.count))
            let katakana = String(String.UnicodeScalarView(kana.unicodeScalars.map {
                (0x3041...0x3096).contains($0.value) ? UnicodeScalar($0.value + 0x60)! : $0
            }))
            if !choices.contains(where: { $0.text == katakana && $0.raw == raw }) {
                choices.append(Choice(text: katakana, reading: kana, raw: raw))
            }
        }
        return snapshot()
    }

    func process(key: Int32) -> SKEngineState {
        if key == 0x20 { return choices.isEmpty ? commit() : selectCandidate(at: 0) }
        if key == 0xff0d {
            // Like Chinese composition, Return confirms the original spelling.
            return finish(prefix + remaining, selected: [])
        }
        if key == 0xff08 {
            if input.count > lockedCount { input.removeLast() }
            else if !locked.isEmpty { locked.removeLast() }
            return refresh()
        }
        guard let scalar = UnicodeScalar(UInt32(bitPattern: key)),
              (97...122).contains(key) || key == 39 || key == 45 else {
            var state = snapshot(); state.handled = false; return state
        }
        input += String(scalar)
        return refresh()
    }

    func selectCandidate(at index: Int) -> SKEngineState {
        guard choices.indices.contains(index) else { return snapshot() }
        let choice = choices[index]
        if choice.raw.count < remaining.count {
            locked.append(choice)
            return refresh()
        }
        return finish(prefix + choice.text, selected: locked + [choice])
    }

    private func finish(_ text: String, selected: [Choice]) -> SKEngineState {
        for choice in selected {
            var words = learned[choice.reading] ?? [:]
            words[choice.text] = min(10000, (words[choice.text] ?? 0) + 1)
            learned[choice.reading] = words
        }
        // Bound the persistent learning file independently of corpus size.
        while learned.count > 1024, let evicted = learned.keys.sorted().first(where: { $0 != selected.last?.reading }) {
            learned.removeValue(forKey: evicted)
        }
        if !selected.isEmpty, let bytes = try? JSONEncoder().encode(learned) { try? bytes.write(to: learningURL, options: .atomic) }
        var state = clear(); state.committedText = text; return state
    }
    func commit() -> SKEngineState {
        commitCandidate(at: 0)
    }
    func commitCandidate(at index: Int) -> SKEngineState {
        guard choices.indices.contains(index) else { return finish(prefix + remaining, selected: []) }
        let choice = choices[index], tail = String(remaining.dropFirst(choices[index].raw.count))
        return finish(prefix + choice.text + tail, selected: tail.isEmpty ? locked + [choice] : [])
    }
    func commitLiteralFallback(rawInput: String) -> SKEngineState {
        finish(prefix + remaining, selected: [])
    }
    func clear() -> SKEngineState {
        input = ""; kana = ""; pending = ""; choices = []; locked = []; page = 0
        return snapshot()
    }
    func candidatePage(startingAt index: Int, limit: Int) -> SKCandidatePage {
        let start = max(0, min(index, choices.count)), end = min(choices.count, start + max(0, min(limit, 64)))
        return SKCandidatePage(candidates: (start..<end).map {
            SKCandidate(index: $0, text: choices[$0].text, comment: "日文 · " + choices[$0].reading,
                consumedInputCount: choices[$0].raw.count)
        }, nextIndex: end, hasMore: end < choices.count)
    }
    func changePage(backward: Bool) -> SKEngineState {
        page = max(0, min(max(0, (choices.count - 1) / 8), page + (backward ? -1 : 1)))
        return snapshot()
    }
    func selectConfiguration(_ configuration: SKInputConfiguration) throws -> SKEngineState {
        guard configuration.language == .japanese else { throw SKRimeEngine.EngineError.missingResources }
        return clear()
    }
    private func snapshot() -> SKEngineState {
        let items = candidatePage(startingAt: page * 8, limit: 8)
        return SKEngineState(input: input, preedit: prefix + remaining, candidates: items.candidates,
            page: page, isLastPage: !items.hasMore)
    }
}
