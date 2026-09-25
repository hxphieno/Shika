import Foundation

/// Rime session adapter. Input schemes supply their decoding and spelling configuration.
/// Precompiled resources avoid deployment and network access in the extension.
@MainActor
final class SKRimeEngine: SKInputEngine {
    private let session: SKRimeSession
    private let probe: SKRimeSession
    private let resources: URL
    private let correctionEnabled: Bool
    private var segmentationCandidates: SKPinyinSegmentationCandidates?
    private var correctionCandidates: SKCorrectionCandidates?
    private var displayed = SKEngineState()

    init(configuration: SKInputConfiguration, resourceURL: URL? = nil, userURL: URL? = nil, correctionEnabled: Bool = true) throws {
        let resources = resourceURL ?? Bundle.main.url(forResource: "RimeData", withExtension: "bundle")
        guard let resources else { throw EngineError.missingResources }
        let directory = try userURL ?? FileManager.default.url(for: .applicationSupportDirectory,
            in: .userDomainMask, appropriateFor: nil, create: true).appendingPathComponent("RimeUser", isDirectory: true)
        self.resources = resources
        self.correctionEnabled = correctionEnabled
        session = try SKRimeSession(sharedPath: resources.path, userPath: directory.path, schema: configuration.schemaID)
        probe = try SKRimeSession(sharedPath: resources.path, userPath: directory.path, schema: configuration.schemaID)
        segmentationCandidates = SKPinyinSegmentationCandidates(resources: resources, configuration: configuration)
        correctionCandidates = correctionEnabled ? SKCorrectionCandidates(resources: resources, configuration: configuration) : nil
    }

    func process(key: Int32) -> SKEngineState {
        if key == 32, let first = displayed.candidates.first, first.index < 0 {
            return selectCandidate(at: first.index)
        }
        return present(decode(session.processKey(key)))
    }
    func selectCandidate(at index: Int) -> SKEngineState {
        if let correction = segmentationCandidates?.selection(at: index) ?? correctionCandidates?.selection(at: index) {
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
    func candidatePage(startingAt index: Int, limit: Int) -> SKCandidatePage {
        let data = session.candidatePage(from: UInt(max(0, index)), limit: UInt(max(1, min(limit, 64))))
        return SKCandidatePage(candidates: decode(data).candidates,
            nextIndex: data["nextIndex"] as? Int ?? index,
            hasMore: data["hasMore"] as? Bool ?? false)
    }
    func changePage(backward: Bool) -> SKEngineState { present(decode(session.changePage(backward))) }
    func commit() -> SKEngineState {
        if let first = displayed.candidates.first, first.index < 0 { return selectCandidate(at: first.index) }
        return present(decode(session.commitComposition()))
    }
    func clear() -> SKEngineState { present(decode(session.clearComposition())) }
    func selectConfiguration(_ configuration: SKInputConfiguration) throws -> SKEngineState {
        let result = session.selectSchema(configuration.schemaID)
        if result["error"] != nil { throw EngineError.missingResources }
        _ = probe.selectSchema(configuration.schemaID)
        segmentationCandidates = SKPinyinSegmentationCandidates(resources: resources, configuration: configuration)
        correctionCandidates = correctionEnabled ? SKCorrectionCandidates(resources: resources, configuration: configuration) : nil
        return present(decode(result))
    }

    private func present(_ result: SKEngineState) -> SKEngineState {
        let segmented = segmentationCandidates?.present(result) { code in
            decode(probe.replaceInput(code))
        } ?? result
        let state = correctionCandidates?.present(segmented) { code in
            decode(probe.replaceInput(code))
        } ?? segmented
        displayed = state
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
