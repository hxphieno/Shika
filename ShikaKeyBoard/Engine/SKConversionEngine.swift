import Foundation

/// The common input-session boundary. Language-specific decoding stays below UI.
@MainActor
final class SKConversionEngine: SKInputEngine {
    private let resources: URL
    private let userDirectory: URL
    private var configuration: SKInputConfiguration
    private var chinese: SKRimeEngine?
    private var japanese: SKJapaneseEngine?
    private var native = SKEngineState()
    private var displayed = SKEngineState()
    private static let japaneseRoute = -1000

    init(configuration: SKInputConfiguration, resourceURL: URL? = nil, userURL: URL? = nil) throws {
        guard let resources = resourceURL ?? Bundle.main.url(forResource: "RimeData", withExtension: "bundle") else {
            throw SKRimeEngine.EngineError.missingResources
        }
        self.resources = resources
        userDirectory = try userURL ?? FileManager.default.url(for: .applicationSupportDirectory,
            in: .userDomainMask, appropriateFor: nil, create: true).appendingPathComponent("RimeUser", isDirectory: true)
        self.configuration = configuration
        try configure(configuration)
    }

    private func configure(_ next: SKInputConfiguration) throws {
        // Construct the destination before dropping the active decoder, so a
        // missing resource cannot leave the keyboard without its previous mode.
        var nextChinese = chinese, nextJapanese = japanese
        if next.language != .chinese && nextJapanese == nil {
            nextJapanese = try SKJapaneseEngine(resources: resources, userDirectory: userDirectory)
        }
        if next.language != .japanese {
            if let engine = nextChinese { _ = try engine.selectConfiguration(next) }
            else { nextChinese = try SKRimeEngine(configuration: next, resourceURL: resources, userURL: userDirectory) }
        }
        chinese = next.language == .japanese ? nil : nextChinese
        japanese = next.language == .chinese ? nil : nextJapanese
        configuration = next
        _ = clear()
    }

    func process(key: Int32) -> SKEngineState {
        if configuration.language == .japanese { return japanese!.process(key: key) }
        if key == 0x20, let first = displayed.candidates.first, first.index <= Self.japaneseRoute {
            return selectCandidate(at: first.index)
        }
        native = chinese!.process(key: key)
        return present(native)
    }
    func selectCandidate(at index: Int) -> SKEngineState {
        if configuration.language == .japanese { return japanese!.selectCandidate(at: index) }
        if configuration.language == .mixed, index <= Self.japaneseRoute,
           displayed.candidates.contains(where: { $0.index == index }) {
            let result = japanese!.selectCandidate(at: Self.japaneseRoute - index)
            _ = chinese?.clear(); native = SKEngineState(); displayed = result
            return result
        }
        native = chinese!.selectCandidate(at: index)
        return present(native)
    }
    func candidatePage(startingAt index: Int, limit: Int) -> SKCandidatePage {
        configuration.language == .japanese
            ? japanese!.candidatePage(startingAt: index, limit: limit)
            : chinese!.candidatePage(startingAt: index, limit: limit)
    }
    func changePage(backward: Bool) -> SKEngineState {
        if configuration.language == .japanese { return japanese!.changePage(backward: backward) }
        native = chinese!.changePage(backward: backward); return present(native)
    }
    func commit() -> SKEngineState {
        if configuration.language == .japanese { return japanese!.commit() }
        if let first = displayed.candidates.first, first.index <= Self.japaneseRoute {
            return selectCandidate(at: first.index)
        }
        native = chinese!.commit(); return present(native)
    }
    func clear() -> SKEngineState {
        _ = chinese?.clear(); _ = japanese?.clear()
        native = SKEngineState(); displayed = native; return native
    }
    func selectConfiguration(_ next: SKInputConfiguration) throws -> SKEngineState {
        try configure(next); return displayed
    }
    private func present(_ state: SKEngineState) -> SKEngineState {
        var state = state
        if configuration.language == .mixed, state.page == 0, state.committedText.isEmpty,
           state.input.count >= 3, !state.preedit.unicodeScalars.contains(where: { $0.value > 127 }) {
            _ = japanese!.replaceInput(state.input)
            let foreign = japanese!.candidatePage(startingAt: 0, limit: 64)
            var seen = Set(state.candidates.map(\.text))
            let additions = foreign.candidates.filter { seen.insert($0.text).inserted }.map {
                SKCandidate(index: Self.japaneseRoute - $0.index, text: $0.text, comment: $0.comment)
            }
            state.candidates.insert(contentsOf: additions.prefix(3), at: min(5, state.candidates.count))
            state.candidates.append(contentsOf: additions.dropFirst(3))
        } else { _ = japanese?.clear() }
        displayed = state
        return state
    }
}
