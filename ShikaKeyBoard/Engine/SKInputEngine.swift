import Foundation

struct SKCandidate: Equatable {
    let index: Int
    let text: String
    let comment: String
}

struct SKEngineState {
    var input = ""
    var preedit = ""
    var candidates: [SKCandidate] = []
    var committedText = ""
    var page = 0
    var isLastPage = true
    var handled = true
}

@MainActor
protocol SKInputEngine: AnyObject {
    func process(key: Int32) -> SKEngineState
    func selectCandidate(at index: Int) -> SKEngineState
    func changePage(backward: Bool) -> SKEngineState
    func commit() -> SKEngineState
    func clear() -> SKEngineState
    func selectSchema(_ schema: String) throws -> SKEngineState
}

/// Shared engine infrastructure. Schemes supply only their schema identifier.
/// Precompiled resources avoid deployment and network access in the extension.
@MainActor
final class SKRimeEngine: SKInputEngine {
    private let session: SKRimeSession
    private let probe: SKRimeSession
    private let resources: URL
    private let correctionEnabled: Bool
    private var corrector: SKSpellingCorrector?
    private var displayed = SKEngineState()
    private var corrections: [Int: (code: String, text: String)] = [:]

    init(schema: String, resourceURL: URL? = nil, userURL: URL? = nil, correctionEnabled: Bool = true) throws {
        let resources = resourceURL ?? Bundle.main.url(forResource: "RimeData", withExtension: "bundle")
        guard let resources else { throw EngineError.missingResources }
        let directory = try userURL ?? FileManager.default.url(for: .applicationSupportDirectory,
            in: .userDomainMask, appropriateFor: nil, create: true).appendingPathComponent("RimeUser", isDirectory: true)
        self.resources = resources
        self.correctionEnabled = correctionEnabled
        session = try SKRimeSession(sharedPath: resources.path, userPath: directory.path, schema: schema)
        probe = try SKRimeSession(sharedPath: resources.path, userPath: directory.path, schema: schema)
        corrector = correctionEnabled ? SKSpellingCorrector(resources: resources, schema: schema) : nil
    }

    func process(key: Int32) -> SKEngineState {
        if key == 32, let first = displayed.candidates.first, first.index < 0 {
            return selectCandidate(at: first.index)
        }
        return present(decode(session.processKey(key)))
    }
    func selectCandidate(at index: Int) -> SKEngineState {
        if let correction = corrections[index] {
            let original = displayed.input
            _ = session.replaceInput(correction.code)
            let selected = session.selectText(correction.text)
            if selected["matched"] as? Bool == true { return present(decode(selected)) }
            // Preserve input if an unexpected dictionary/session change made a
            // previously displayed candidate unavailable.
            return present(decode(session.replaceInput(original)))
        }
        guard index >= 0 else { return displayed }
        return present(decode(session.selectCandidate(UInt(index))))
    }
    func changePage(backward: Bool) -> SKEngineState { present(decode(session.changePage(backward))) }
    func commit() -> SKEngineState {
        if let first = displayed.candidates.first, first.index < 0 { return selectCandidate(at: first.index) }
        return present(decode(session.commitComposition()))
    }
    func clear() -> SKEngineState { present(decode(session.clearComposition())) }
    func selectSchema(_ schema: String) throws -> SKEngineState {
        let result = session.selectSchema(schema)
        if result["error"] != nil { throw EngineError.missingResources }
        _ = probe.selectSchema(schema)
        corrector = correctionEnabled ? SKSpellingCorrector(resources: resources, schema: schema) : nil
        return present(decode(result))
    }

    private func present(_ result: SKEngineState) -> SKEngineState {
        corrections.removeAll(keepingCapacity: true)
        var state = result
        defer { displayed = state }
        guard let corrector, state.page == 0, !state.input.isEmpty,
              state.committedText.isEmpty,
              // A Hanzi prefix is a deliberate partial selection. Preserve the
              // native composition and its remaining segmentation unchanged.
              !state.preedit.unicodeScalars.contains(where: { $0.value > 127 }) else { return state }
        let exactFirst = state.candidates.first.map { corrector.isExact(comment: $0.comment, input: state.input) } ?? false
        var extra: [SKCandidate] = []
        var seen = Set(state.candidates.filter {
            corrector.isExact(comment: $0.comment, input: state.input)
        }.map(\.text))
        for suggestion in corrector.suggestions(for: state.input) {
            let queried = decode(probe.replaceInput(suggestion.code))
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

    private func decode(_ data: [AnyHashable: Any]) -> SKEngineState {
        SKEngineState(input: data["input"] as? String ?? "",
            preedit: data["preedit"] as? String ?? "",
            candidates: (data["candidates"] as? [[String: Any]] ?? []).compactMap { item in
                guard let index = item["index"] as? Int, let text = item["text"] as? String else { return nil }
                return SKCandidate(index: index, text: text, comment: item["comment"] as? String ?? "")
            }, committedText: data["commit"] as? String ?? "", page: data["page"] as? Int ?? 0,
            isLastPage: data["lastPage"] as? Bool ?? true, handled: data["handled"] as? Bool ?? true)
    }

    enum EngineError: LocalizedError {
        case missingResources
        var errorDescription: String? { "离线词库加载失败，请重新安装或重试" }
    }
}
