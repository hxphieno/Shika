import Foundation

@MainActor private final class SpecialCandidateEngine: SKInputEngine {
    var input = ""
    var preeditOverride: String?
    var rows: [SKCandidate]
    var initialCount: Int
    var page = 0
    var selected: [Int] = []
    var requestedStarts: [Int] = []
    init(_ rows: [SKCandidate], initialCount: Int = 8) { self.rows = rows; self.initialCount = initialCount }
    func snapshot() -> SKEngineState {
        SKEngineState(input: input, preedit: preeditOverride ?? input,
                      candidates: input.isEmpty ? [] : Array(rows.prefix(initialCount)),
                      page: page, isLastPage: rows.count <= initialCount)
    }
    func process(key: Int32) -> SKEngineState {
        if key == 32 { return commit() }
        if key == 0xff0d { let raw = input; _ = clear(); return SKEngineState(committedText: raw) }
        if key == 0xff08 { input = String(input.dropLast()) }
        else { input += String(UnicodeScalar(UInt32(key))!) }
        return snapshot()
    }
    func selectCandidate(at index: Int) -> SKEngineState {
        selected.append(index)
        let text = rows.first { $0.index == index }?.text ?? "INVALID"
        _ = clear(); return SKEngineState(committedText: text)
    }
    func candidatePage(startingAt index: Int, limit: Int) -> SKCandidatePage {
        requestedStarts.append(index)
        let batch = Array(rows.filter { $0.index >= index }.prefix(limit))
        let next = (batch.last?.index ?? (index - 1)) + 1
        return SKCandidatePage(candidates: batch, nextIndex: next, hasMore: rows.contains { $0.index >= next })
    }
    func changePage(backward: Bool) -> SKEngineState { page = backward ? 0 : 1; return snapshot() }
    func commit() -> SKEngineState { selectCandidate(at: rows[0].index) }
    func clear() -> SKEngineState { input = ""; page = 0; return SKEngineState() }
    func selectConfiguration(_ configuration: SKInputConfiguration) throws -> SKEngineState { clear() }
}

@main struct SpecialCandidatesChecks {
    @MainActor static func main() async throws {
        let resources = URL(fileURLWithPath: CommandLine.arguments[1])
        let provider = SKSpecialCandidates(resourceURL: resources)
        let full = SKInputConfiguration(schemaID: "shika_pinyin", inputPolicy: .chineseRomanization, spelling: .fullPinyin)
        let double = SKInputConfiguration(schemaID: "shika_flypy", inputPolicy: .chineseRomanization, spelling: .doublePinyin)
        var count = 0
        func expect(_ value: Bool, _ message: String) {
            count += 1
            if !value { fatalError("FAIL: \(message)") }
            print("PASS: \(message)")
        }
        func row(_ index: Int, _ text: String, _ comment: String = "", consumed: Int? = nil) -> SKCandidate {
            SKCandidate(index: index, text: text, comment: comment, consumedInputCount: consumed)
        }
        func suggest(_ input: String, _ rows: [SKCandidate], configuration: SKInputConfiguration? = nil,
                     preedit: String? = nil, page: Int = 0, displayable: (String) -> Bool = { _ in true }) -> SKCandidate? {
            provider.suggestion(for: SKEngineState(input: input, preedit: preedit ?? input, candidates: rows, page: page),
                                configuration: configuration ?? full, isDisplayable: displayable)
        }
        let words = [row(0, "烟花", "yan hua"), row(1, "眼花", "yan hua"), row(2, "研华", "yan hua"), row(3, "烟", "yan")]
        expect(suggest("yanhua", words)?.text == "🎆", "full pinyin maps fireworks")
        expect(suggest("yjhx", words, configuration: double)?.text == "🎆", "double pinyin shares word mapping")
        expect(suggest("yan'hua", words)?.text == "🎆", "syllable separator supported")
        for (word, reading, output) in [("逗号", "dou hao", "，"), ("句号", "ju hao", "。"), ("爱心", "ai xin", "❤️"), ("省略号", "sheng lue hao", "……"), ("胜利", "sheng li", "✌️")] {
            expect(suggest(reading.replacingOccurrences(of: " ", with: ""), [row(0, word, reading)])?.text == output,
                   "maps \(word) preserving complete Unicode sequence")
        }
        expect(suggest("yanhuabiaoyan", words) == nil, "partial word cannot replace a longer input")
        expect(suggest("yh", words) == nil, "abbreviation does not trigger")
        expect(suggest("yanh", words) == nil, "completion does not trigger")
        expect(suggest("yanhua", [row(0, "烟花", "yan hua", consumed: 3)]) == nil, "partial consumption rejected")
        expect(suggest("yanhua", words, preedit: "今天yan hua") == nil, "confirmed prefix protected")
        expect(suggest("yanhua", words, page: 1) == nil, "later engine pages do not inject")
        expect(suggest("yanhua", words, displayable: { $0 != "🎆" }) == nil, "unsupported emoji hidden")
        expect(suggest("yanhua", (0..<5).map { row($0, "普通词") } + words) == nil, "only leading five candidates trigger")
        var mixed = full; mixed.language = .mixed
        var japanese = full; japanese.language = .japanese
        expect(suggest("yanhua", words, configuration: mixed) == nil, "mixed composition unchanged")
        expect(suggest("yanhua", words, configuration: japanese) == nil, "Japanese composition unchanged")

        var output = "", marked = "", updates: [String] = []
        let engine = SpecialCandidateEngine(words)
        let session = SKInputSession(engine: engine, configuration: full,
            insertText: { output += $0; updates.append("insert:\($0)") }, deleteText: {},
            updateComposition: { marked = $0; updates.append("mark:\($0)") }, specialCandidates: provider)
        func type(_ text: String, in session: SKInputSession) { for character in text { session.type(String(character)) } }
        type("yanhua", in: session)
        expect(session.state.candidates.map(\.text) == ["烟花", "眼花", "🎆", "研华", "烟"], "inserts third, preserves ordinary ordering")
        expect(session.state.candidates.filter { $0.index != SKSpecialCandidates.candidateIndex } == words, "native IDs and metadata unchanged")
        let special = session.state.candidates[2]
        updates = []; session.select(special)
        expect(output == "🎆" && marked.isEmpty && engine.input.isEmpty && session.state.candidates.isEmpty, "selecting emoji clears composition and inserts once")
        expect(updates == ["mark:", "insert:🎆"] && engine.selected.isEmpty, "clear precedes insertion without native selection or learning")
        session.select(special)
        expect(output == "🎆", "stale special candidate cannot commit twice")
        output = ""; type("yanhua", in: session); session.type(" ")
        expect(output == "烟花" && engine.selected.last == 0, "space still commits normal first word")
        output = ""; type("yanhua", in: session); session.select(session.state.candidates[3])
        expect(output == "研华" && engine.selected.last == 2, "shifted fourth candidate selects original native ID")
        output = ""; type("yanhua", in: session); session.type("，")
        expect(output == "烟花，", "punctuation still flushes ordinary word")
        output = ""; type("yanhua", in: session); session.type("\n")
        expect(output == "yanhua", "Return preserves existing raw-input semantics")
        type("yanhua", in: session); session.deleteBackward()
        expect(!session.state.candidates.contains { $0.index == SKSpecialCandidates.candidateIndex }, "deleting to incomplete spelling removes suggestion")
        session.cancel(); expect(session.state.candidates.isEmpty, "cancel clears special candidate")
        try session.switchConfiguration(to: double); type("yjhx", in: session)
        expect(session.state.candidates[2].text == "🎆", "switch to double pinyin works in session")
        session.cancel(); try session.switchConfiguration(to: mixed); type("yanhua", in: session)
        expect(session.state.candidates == words, "mode switch disables Chinese suggestions")

        let shortEngine = SpecialCandidateEngine(words, initialCount: 1)
        let short = SKInputSession(engine: shortEngine, configuration: full, insertText: { _ in }, deleteText: {}, specialCandidates: provider)
        type("yanhua", in: short)
        expect(short.state.candidates.map(\.text) == ["烟花", "🎆"], "one ordinary candidate appends without empty placeholder")
        short.loadMoreCandidates()
        expect(short.state.candidates.map(\.text) == ["烟花", "眼花", "🎆", "研华", "烟"], "expansion moves suggestion to third")
        expect(shortEngine.requestedStarts == [1], "pagination uses native cursor, not visible count")

        let duplicateRows = words + [row(4, "🎆"), row(5, "🎆", consumed: 6), row(6, "其他")]
        let duplicateEngine = SpecialCandidateEngine(duplicateRows, initialCount: 3)
        let duplicates = SKInputSession(engine: duplicateEngine, configuration: full, insertText: { _ in }, deleteText: {}, specialCandidates: provider)
        type("yanhua", in: duplicates); duplicates.loadMoreCandidates(); duplicates.loadMoreCandidates()
        expect(duplicates.state.candidates.filter { $0.text == "🎆" }.count == 1 && duplicates.state.candidates[2].text == "🎆", "paged duplicates removed across metadata variants")
        expect(duplicates.state.candidates.last?.text == "其他" && duplicates.state.isLastPage, "deduplication does not skip last native row")

        let hiddenRows = [row(0, "隐藏")] + words.enumerated().map { row($0.offset + 1, $0.element.text, $0.element.comment) }
        let hiddenEngine = SpecialCandidateEngine(hiddenRows, initialCount: 3)
        var hiddenOutput = ""
        let hidden = SKInputSession(engine: hiddenEngine, configuration: full, candidateIsDisplayable: { $0 != "隐藏" },
            insertText: { hiddenOutput += $0 }, deleteText: {}, specialCandidates: provider)
        type("yanhua", in: hidden)
        expect(hidden.state.candidates[2].text == "🎆" && hidden.state.candidates[0].index == 1, "third position calculated after glyph filtering and refill")
        hidden.type(" ")
        expect(hiddenOutput == "烟花" && hiddenEngine.selected == [1], "hidden first candidate fallback still selects visible word")

        let lateRows = (0..<200).map { row($0, "隐藏") } + words.enumerated().map { row($0.offset + 200, $0.element.text, $0.element.comment) }
        let lateEngine = SpecialCandidateEngine(lateRows, initialCount: 2)
        let late = SKInputSession(engine: lateEngine, configuration: full, candidateIsDisplayable: { $0 != "隐藏" },
            insertText: { _ in }, deleteText: {}, specialCandidates: provider)
        type("yanhua", in: late)
        for _ in 0..<1000 where late.state.candidates.isEmpty { await Task.yield() }
        expect(late.state.candidates.count >= 3 && late.state.candidates[2].text == "🎆", "async hidden-row refill adds third-place suggestion")
        late.cancel()
        for _ in 0..<20 { await Task.yield() }
        expect(late.state.input.isEmpty && late.state.candidates.isEmpty, "cancel prevents async suggestion resurrection")
        print("PASS: \(count) special-candidate checks")
    }
}
