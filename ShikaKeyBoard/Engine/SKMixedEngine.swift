import Foundation

/// Owns mixed composition, selection and learning behind the existing UI contract.
/// Input offsets refer to raw letters; output length never determines consumption.
@MainActor
final class SKMixedEngine: SKInputEngine {
    private let decoder: SKMixedDecoder
    private let native: SKRimeSession
    private let prefixCandidates: SKPinyinPrefixCandidates?
    private let learningURL: URL
    private var learned: [String: Int]
    private var input = ""
    private var locked: [SKMixedDecoder.Segment] = []
    private var context: SKMixedDecoder.Segment?
    private var candidates: [SKMixedDecoder.Path] = []
    private var page = 0
    private var chineseCache: [String: (candidates: [SKCandidate], preedit: String)] = [:]
    private var displayRemaining = ""
    private var lockedCount: Int { locked.reduce(0) { $0 + $1.raw.count } }
    private var prefix: String { locked.map(\.text).joined() }
    private var remaining: String { String(input.dropFirst(lockedCount)) }

    init(resources: URL, userDirectory: URL, beamWidth: Int = 16) throws {
        decoder = try SKMixedDecoder(resources: resources, beamWidth: beamWidth)
        prefixCandidates = SKPinyinPrefixCandidates(resources: resources, configuration: SKInputConfiguration(
            schemaID: "shika_pinyin", inputPolicy: .chineseRomanization, spelling: .fullPinyin))
        native = try SKRimeSession(sharedPath: resources.path, userPath: userDirectory.path, schema: "shika_pinyin")
        learningURL = userDirectory.appendingPathComponent("mixed-learning.json")
        learned = (try? JSONDecoder().decode([String: Int].self, from: Data(contentsOf: learningURL))) ?? [:]
        if learned.count > 4096 { learned = [:] }
    }
    private func wordKey(_ segment: SKMixedDecoder.Segment) -> String {
        "w:\(segment.language.rawValue):\(segment.raw):\(segment.text)"
    }
    private func pairKey(_ previous: SKMixedDecoder.Segment, _ next: SKMixedDecoder.Segment) -> String {
        "p:\(previous.language.rawValue):\(previous.text):\(next.language.rawValue):\(next.raw):\(next.text)"
    }
    private func bonus(_ previous: SKMixedDecoder.Segment?, _ next: SKMixedDecoder.Segment) -> Double {
        // Before the first learned selection both terms are necessarily zero.
        // Avoid constructing word/pair keys for every edge of the search graph.
        guard !learned.isEmpty else { return 0 }
        let word = learned[wordKey(next)] ?? 0
        let pair = previous.map { learned[pairKey($0, next)] ?? 0 } ?? 0
        return min(3, log1p(Double(word)) * 0.8 + log1p(Double(pair)))
    }
    private func remember(_ segments: [SKMixedDecoder.Segment]) {
        var previous = context
        for segment in segments {
            let key = wordKey(segment)
            learned[key] = min(1000, (learned[key] ?? 0) + 1)
            if let previous {
                let pair = pairKey(previous, segment)
                learned[pair] = min(1000, (learned[pair] ?? 0) + 1)
            }
            previous = segment
        }
        if learned.count > 2048 {
            let keep = learned.sorted { $0.value == $1.value ? $0.key < $1.key : $0.value > $1.value }.prefix(2048)
            learned = Dictionary(uniqueKeysWithValues: keep.map { ($0.key, $0.value) })
        }
        if let data = try? JSONEncoder().encode(learned) { try? data.write(to: learningURL, options: .atomic) }
    }
    private func refresh() -> SKEngineState {
        page = 0
        let chinese = queryChinese(remaining)
        candidates = decoder.decode(remaining, context: locked.last ?? context, native: chinese, chineseQuery: queryChinese, bonus: bonus)
        // Display boundaries only: offsets and commits always use the raw input.
        var parts = (candidates.first?.segments ?? []).map { segment in
            guard segment.language == .chinese else { return segment.raw }
            _ = queryChinese(segment.raw)
            let preedit = chineseCache[segment.raw]?.preedit ?? segment.raw
            return preedit.replacingOccurrences(of: " ", with: "") == segment.raw ? preedit : segment.raw
        }
        let tail = String(remaining.dropFirst(candidates.first?.consumed ?? 0))
        if !tail.isEmpty { parts.append(tail) }
        displayRemaining = parts.joined(separator: " ")
        return snapshot()
    }
    private func queryChinese(_ code: String) -> [SKCandidate] {
        if let cached = chineseCache[code] { return cached.candidates }
        let result = native.replaceInput(code)
        let window = SKCandidateGrouping.nativeWindow(native)
        func candidates(_ rows: [[String: Any]]) -> [SKCandidate] {
            rows.compactMap { item -> SKCandidate? in
                guard let text = item["text"] as? String else { return nil }
                return SKCandidate(index: item["index"] as? Int ?? 0, text: text, comment: item["comment"] as? String ?? "")
            }
        }
        let state = SKEngineState(input: code, preedit: result["preedit"] as? String ?? code,
            candidates: SKCandidateGrouping.arrange(recommendations: window.items,
                words: window.items, text: { $0.text }, identity: { $0.contentIdentity }))
        let items = prefixCandidates?.present(state) { completion in
            let queried = native.replaceInput(completion)
            return SKEngineState(candidates: candidates(queried["candidates"] as? [[String: Any]] ?? []))
        }.candidates ?? state.candidates
        if chineseCache.count >= 256 { chineseCache.removeAll(keepingCapacity: true) }
        chineseCache[code] = (items, result["preedit"] as? String ?? code)
        return items
    }
    func process(key: Int32) -> SKEngineState {
        if key == 0x20 {
            return candidates.isEmpty ? finish(prefix + remaining, segments: []) : selectCandidate(at: 0)
        }
        if key == 0xff0d { return finish(prefix + remaining, segments: []) }
        if key == 0xff08 {
            if input.count > lockedCount { input.removeLast() }
            else if !locked.isEmpty { locked.removeLast() }
            return refresh()
        }
        guard (97...122).contains(key) || key == 39 || key == 45,
              let scalar = UnicodeScalar(UInt32(bitPattern: key)) else {
            var state = snapshot(); state.handled = false; return state
        }
        input.append(Character(scalar))
        return refresh()
    }
    func selectCandidate(at index: Int) -> SKEngineState {
        guard candidates.indices.contains(index) else { return snapshot() }
        let choice = candidates[index]
        guard choice.consumed > 0, choice.consumed <= remaining.count else { return snapshot() }
        if choice.consumed == remaining.count {
            return finish(prefix + choice.text, segments: locked + choice.segments)
        }
        locked += choice.segments
        return refresh()
    }
    /// Punctuation/mode changes flush once; selecting a prefix must never drop
    /// the undecoded tail when the caller immediately switches engines.
    func commit() -> SKEngineState {
        commitCandidate(at: 0)
    }
    func commitCandidate(at index: Int) -> SKEngineState {
        if candidates.indices.contains(index) {
            let choice = candidates[index]
            let tail = String(remaining.dropFirst(choice.consumed))
            return finish(prefix + choice.text + tail, segments: tail.isEmpty ? locked + choice.segments : [])
        }
        return finish(prefix + remaining, segments: [])
    }
    func commitLiteralFallback(rawInput: String) -> SKEngineState {
        finish(prefix + remaining, segments: [])
    }
    private func finish(_ text: String, segments: [SKMixedDecoder.Segment]) -> SKEngineState {
        if !segments.isEmpty { remember(segments); context = segments.last }
        else { context = nil }
        input = ""; locked = []; candidates = []; page = 0
        displayRemaining = ""
        _ = native.clearComposition()
        var state = snapshot(); state.committedText = text
        return state
    }
    func clear() -> SKEngineState {
        context = nil; input = ""; locked = []; candidates = []; page = 0
        displayRemaining = ""
        decoder.resetCache(); chineseCache.removeAll(keepingCapacity: true); _ = native.clearComposition()
        return snapshot()
    }
    func candidatePage(startingAt index: Int, limit: Int) -> SKCandidatePage {
        let start = min(candidates.count, max(0, index))
        let end = min(candidates.count, start + min(64, max(0, limit)))
        return SKCandidatePage(candidates: (start..<end).map { i in
            let candidate = candidates[i]
            let language = candidate.languages.count > 1 ? "中日" : (candidate.last?.language == .japanese ? "日文" : "中文")
            return SKCandidate(index: i, text: candidate.text,
                comment: language + (candidate.segments.contains(where: \.corrected) ? " · 纠错" : ""),
                consumedInputCount: candidate.consumed)
        }, nextIndex: end, hasMore: end < candidates.count)
    }
    func changePage(backward: Bool) -> SKEngineState {
        page = max(0, min(max(0, (candidates.count - 1) / 8), page + (backward ? -1 : 1)))
        return snapshot()
    }
    func selectConfiguration(_ configuration: SKInputConfiguration) throws -> SKEngineState {
        guard configuration.language == .mixed else { throw SKRimeEngine.EngineError.missingResources }
        return clear()
    }
    private func snapshot() -> SKEngineState {
        let items = candidatePage(startingAt: page * 8, limit: 8)
        return SKEngineState(input: input, preedit: prefix + displayRemaining, candidates: items.candidates,
            page: page, isLastPage: !items.hasMore)
    }
}
