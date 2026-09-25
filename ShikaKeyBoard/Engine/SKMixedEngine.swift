import Foundation

/// Owns mixed composition, selection and learning behind the existing UI contract.
/// Input offsets refer to raw letters; output length never determines consumption.
@MainActor
final class SKMixedEngine: SKInputEngine {
    private let decoder: SKMixedDecoder
    private let native: SKRimeSession
    private let learningURL: URL
    private var learned: [String: Int]
    private var input = ""
    private var locked: [SKMixedDecoder.Segment] = []
    private var context: SKMixedDecoder.Segment?
    private var candidates: [SKMixedDecoder.Path] = []
    private var page = 0
    private var chineseCache: [String: [SKCandidate]] = [:]
    private var lockedCount: Int { locked.reduce(0) { $0 + $1.raw.count } }
    private var prefix: String { locked.map(\.text).joined() }
    private var remaining: String { String(input.dropFirst(lockedCount)) }

    init(resources: URL, userDirectory: URL, beamWidth: Int = 16) throws {
        decoder = try SKMixedDecoder(resources: resources, beamWidth: beamWidth)
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
        return snapshot()
    }
    private func queryChinese(_ code: String) -> [SKCandidate] {
        if let cached = chineseCache[code] { return cached }
        let result = native.replaceInput(code)
        let items = (result["candidates"] as? [[String: Any]] ?? []).compactMap { item -> SKCandidate? in
            guard let text = item["text"] as? String else { return nil }
            return SKCandidate(index: 0, text: text, comment: item["comment"] as? String ?? "")
        }
        if chineseCache.count >= 256 { chineseCache.removeAll(keepingCapacity: true) }
        chineseCache[code] = items
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
        if let choice = candidates.first {
            let tail = String(remaining.dropFirst(choice.consumed))
            return finish(prefix + choice.text + tail, segments: tail.isEmpty ? locked + choice.segments : [])
        }
        return finish(prefix + remaining, segments: [])
    }
    private func finish(_ text: String, segments: [SKMixedDecoder.Segment]) -> SKEngineState {
        if !segments.isEmpty { remember(segments); context = segments.last }
        else { context = nil }
        input = ""; locked = []; candidates = []; page = 0
        _ = native.clearComposition()
        var state = snapshot(); state.committedText = text
        return state
    }
    func clear() -> SKEngineState {
        context = nil; input = ""; locked = []; candidates = []; page = 0
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
        return SKEngineState(input: input, preedit: prefix + remaining, candidates: items.candidates,
            page: page, isLastPage: !items.hasMore)
    }
}
