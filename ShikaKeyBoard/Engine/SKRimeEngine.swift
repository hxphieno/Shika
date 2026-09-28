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
    private var prefixCandidates: SKPinyinPrefixCandidates?
    private var correctionCandidates: SKCorrectionCandidates?
    private var syllableCandidates: SKSyllableCorrectionCandidates?
    private var syllableProbe: SKRimeSession?
    private var syllableCache: [String: SKEngineState] = [:]
    private var syllableCacheOrder: [String] = []
    private let userDirectory: URL
    private var learnedSpellings: SKLearnedSpellingIndex?
    private var spellingProfile: SKSpellingProfile
    private var displayed = SKEngineState()
    private var choices: [SKCandidate] = []
    private var nativeIndices: [Int: Int] = [:]
    private var nativeCursor = 0
    private var nativeHasMore = false

    init(configuration: SKInputConfiguration, resourceURL: URL? = nil, userURL: URL? = nil, correctionEnabled: Bool = true) throws {
        let resources = resourceURL ?? Bundle.main.url(forResource: "RimeData", withExtension: "bundle")
        guard let resources else { throw EngineError.missingResources }
        let directory = try userURL ?? FileManager.default.url(for: .applicationSupportDirectory,
            in: .userDomainMask, appropriateFor: nil, create: true).appendingPathComponent("RimeUser", isDirectory: true)
        self.resources = resources
        self.userDirectory = directory
        self.correctionEnabled = correctionEnabled
        spellingProfile = configuration.spelling
        session = try SKRimeSession(sharedPath: resources.path, userPath: directory.path, schema: configuration.schemaID)
        probe = try SKRimeSession(sharedPath: resources.path, userPath: directory.path, schema: configuration.schemaID)
        segmentationCandidates = SKPinyinSegmentationCandidates(resources: resources, configuration: configuration)
        prefixCandidates = SKPinyinPrefixCandidates(resources: resources, configuration: configuration)
        correctionCandidates = correctionEnabled ? SKCorrectionCandidates(resources: resources, configuration: configuration) : nil
        configureSyllableSearch(configuration)
    }

    func process(key: Int32) -> SKEngineState {
        if key == 32 || key == 0xff0d { invalidateSyllableCache() }
        if key == 32, let first = displayed.candidates.first {
            return selectCandidate(at: first.index)
        }
        return finish(decode(session.processKey(key)), code: displayed.input)
    }
    func selectCandidate(at index: Int) -> SKEngineState {
        invalidateSyllableCache()
        if let correction = prefixCandidates?.selection(at: index) ?? segmentationCandidates?.selection(at: index) ?? correctionCandidates?.selection(at: index) ?? syllableCandidates?.selection(at: index) {
            let original = displayed.input
            _ = session.replaceInput(correction.code)
            let selected = session.selectText(correction.text)
            if selected["matched"] as? Bool == true { return finish(decode(selected), code: correction.code) }
            // Preserve input if an unexpected dictionary/session change made a
            // previously displayed candidate unavailable.
            return present(decode(session.replaceInput(original)))
        }
        guard let nativeIndex = nativeIndices[index] else { return displayed }
        return finish(decode(session.selectCandidate(UInt(nativeIndex))), code: displayed.input)
    }
    func candidatePage(startingAt index: Int, limit: Int) -> SKCandidatePage {
        let requestedEnd = max(0, index) + max(0, min(limit, 64))
        // Quotas never reset when the expanded grid asks for another page.
        // Only further single characters may follow the initial grouped list.
        for _ in 0..<4 where choices.count < requestedEnd && nativeHasMore {
            let data = session.candidatePage(from: UInt(nativeCursor), limit: 256)
            let cursor = data["nextIndex"] as? Int ?? nativeCursor
            nativeHasMore = (data["hasMore"] as? Bool ?? false) && cursor > nativeCursor
            nativeCursor = cursor
            var seen = Set(choices.map(\.contentIdentity))
            for candidate in SKCandidateGrouping.decode(data) where candidate.text.count == 1 && seen.insert(candidate.contentIdentity).inserted {
                appendChoice(candidate)
            }
        }
        let start = min(max(0, index), choices.count), end = min(requestedEnd, choices.count)
        return SKCandidatePage(candidates: Array(choices[start..<end]), nextIndex: end,
            hasMore: end < choices.count || nativeHasMore)
    }
    func changePage(backward: Bool) -> SKEngineState {
        let target = max(0, displayed.page + (backward ? -1 : 1))
        let items = candidatePage(startingAt: target * 8, limit: 8)
        guard !items.candidates.isEmpty else { return displayed }
        displayed.page = target; displayed.candidates = items.candidates; displayed.isLastPage = !items.hasMore
        return displayed
    }
    func commit() -> SKEngineState {
        invalidateSyllableCache()
        if let first = displayed.candidates.first, first.index < 0 || nativeIndices[first.index] != 0 {
            return commitCandidate(at: first.index)
        }
        return finish(decode(session.commitComposition()), code: displayed.input)
    }
    func commitLiteralFallback(rawInput: String) -> SKEngineState {
        // express_editor's raw confirmation preserves segments already selected
        // inside Rime; clearing and inserting get_input() would lose that prefix.
        process(key: 0xff0d)
    }
    func commitCandidate(at index: Int) -> SKEngineState {
        let selected = selectCandidate(at: index)
        guard !selected.input.isEmpty else { return selected }
        // This exceptional flush starts with a filtered native first choice.
        // Do not auto-select another, unchecked candidate for the remaining tail.
        var flushed = commitLiteralFallback(rawInput: selected.input)
        flushed.committedText = selected.committedText + flushed.committedText
        return flushed
    }
    func clear() -> SKEngineState { present(decode(session.clearComposition())) }
    func selectConfiguration(_ configuration: SKInputConfiguration) throws -> SKEngineState {
        let result = session.selectSchema(configuration.schemaID)
        if result["error"] != nil { throw EngineError.missingResources }
        _ = probe.selectSchema(configuration.schemaID)
        segmentationCandidates = SKPinyinSegmentationCandidates(resources: resources, configuration: configuration)
        prefixCandidates = SKPinyinPrefixCandidates(resources: resources, configuration: configuration)
        correctionCandidates = correctionEnabled ? SKCorrectionCandidates(resources: resources, configuration: configuration) : nil
        configureSyllableSearch(configuration)
        return present(decode(result))
    }

    private func present(_ result: SKEngineState) -> SKEngineState {
        let segmented = segmentationCandidates?.present(result) { code in
            decode(probe.replaceInput(code))
        } ?? result
        let corrected = correctionCandidates?.present(segmented, learned: learnedSpellings?.suggestions(for: segmented.input) ?? []) { code in
            decode(probe.replaceInput(code))
        } ?? segmented
        let state = syllableCandidates?.present(corrected) { code in
            if let cached = syllableCache[code] { return cached }
            guard let syllableProbe else { return SKEngineState() }
            let value = decode(syllableProbe.replaceInput(code))
            if syllableCacheOrder.count == 32 { syllableCache.removeValue(forKey: syllableCacheOrder.removeFirst()) }
            syllableCacheOrder.append(code); syllableCache[code] = value
            return value
        } ?? corrected
        displayed = prefixCandidates?.present(state) { code in
            decode(probe.replaceInput(code))
        } ?? state
        let window = SKCandidateGrouping.nativeWindow(session)
        let grouped = SKCandidateGrouping.arrange(recommendations: displayed.candidates,
            words: displayed.candidates + window.items, text: { $0.text }, identity: { $0.contentIdentity })
        choices = []; nativeIndices = [:]
        nativeCursor = window.next; nativeHasMore = window.more
        for candidate in grouped { appendChoice(candidate) }
        displayed.page = 0
        displayed.candidates = Array(choices.prefix(8))
        displayed.isLastPage = choices.count <= 8 && !nativeHasMore
        let output = displayed
        displayed.committedText = ""
        return output
    }

    private func appendChoice(_ candidate: SKCandidate) {
        // Keep synthetic correction IDs intact. Positive presentation IDs map
        // back to Rime's original absolute indices, including prefix choices.
        let index = candidate.index < 0 ? candidate.index : choices.count
        if candidate.index >= 0 { nativeIndices[index] = candidate.index }
        choices.append(SKCandidate(index: index, text: candidate.text, comment: candidate.comment,
            consumedInputCount: candidate.consumedInputCount))
    }

    private func invalidateSyllableCache() {
        syllableCache.removeAll(keepingCapacity: true)
        syllableCacheOrder.removeAll(keepingCapacity: true)
    }

    private func finish(_ state: SKEngineState, code: String) -> SKEngineState {
        if let learnedSpellings, !state.committedText.isEmpty, state.input.isEmpty {
            if spellingProfile == .doublePinyin {
                learnedSpellings.record(code: code, text: state.committedText)
            } else if (4...48).contains(code.utf8.count) {
                // Full pinyin can also commit abbreviations or partial readings.
                // Record only a complete spelling verified by the native comment,
                // including phrases just learned through multiple selections.
                let exact = decode(probe.replaceInput(code)).candidates.contains {
                    $0.text == state.committedText && spellingProfile.isExact(comment: $0.comment, input: code, syllables: [:])
                }
                if exact { learnedSpellings.record(code: code.replacingOccurrences(of: "'", with: ""), text: state.committedText) }
            }
        }
        return present(state)
    }

    private func configureSyllableSearch(_ configuration: SKInputConfiguration) {
        invalidateSyllableCache()
        syllableProbe = nil; syllableCandidates = nil
        spellingProfile = configuration.spelling
        learnedSpellings = correctionEnabled ? SKLearnedSpellingIndex(userDirectory: userDirectory, profile: configuration.spelling) : nil
        guard correctionEnabled, configuration.spelling == .doublePinyin,
              FileManager.default.fileExists(atPath: resources.appendingPathComponent("build/shika_flypy_assist.schema.yaml").path),
              let helper = try? SKRimeSession(sharedPath: resources.path, userPath: userDirectory.path, schema: "shika_flypy_assist") else { return }
        syllableProbe = helper
        syllableCandidates = SKSyllableCorrectionCandidates(resources: resources, configuration: configuration)
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
