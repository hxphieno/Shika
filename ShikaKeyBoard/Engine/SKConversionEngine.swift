import Foundation

/// Mode routing only. Each engine owns composition and candidate IDs; mixed
/// policy never leaks into pure Chinese/Japanese or the keyboard UI.
@MainActor
final class SKConversionEngine: SKInputEngine {
    private let resources: URL
    private let userDirectory: URL
    private var engine: any SKInputEngine

    init(configuration: SKInputConfiguration, resourceURL: URL? = nil, userURL: URL? = nil) throws {
        guard let resources = resourceURL ?? Bundle.main.url(forResource: "RimeData", withExtension: "bundle") else {
            throw SKRimeEngine.EngineError.missingResources
        }
        self.resources = resources
        userDirectory = try userURL ?? FileManager.default.url(for: .applicationSupportDirectory,
            in: .userDomainMask, appropriateFor: nil, create: true).appendingPathComponent("RimeUser", isDirectory: true)
        engine = try Self.make(configuration, resources: resources, userDirectory: userDirectory)
    }
    private static func make(_ configuration: SKInputConfiguration, resources: URL, userDirectory: URL) throws -> any SKInputEngine {
        switch configuration.language {
        case .chinese: return try SKRimeEngine(configuration: configuration, resourceURL: resources, userURL: userDirectory)
        case .japanese: return try SKJapaneseEngine(resources: resources, userDirectory: userDirectory)
        case .mixed: return try SKMixedEngine(resources: resources, userDirectory: userDirectory)
        }
    }
    func process(key: Int32) -> SKEngineState { engine.process(key: key) }
    func selectCandidate(at index: Int) -> SKEngineState { engine.selectCandidate(at: index) }
    func candidatePage(startingAt index: Int, limit: Int) -> SKCandidatePage { engine.candidatePage(startingAt: index, limit: limit) }
    func changePage(backward: Bool) -> SKEngineState { engine.changePage(backward: backward) }
    func commit() -> SKEngineState { engine.commit() }
    func commitCandidate(at index: Int) -> SKEngineState { engine.commitCandidate(at: index) }
    func commitLiteralFallback(rawInput: String) -> SKEngineState { engine.commitLiteralFallback(rawInput: rawInput) }
    func clear() -> SKEngineState { engine.clear() }
    func selectConfiguration(_ configuration: SKInputConfiguration) throws -> SKEngineState {
        // Construct before replacing, so missing resources leave a usable engine.
        let next = try Self.make(configuration, resources: resources, userDirectory: userDirectory)
        engine = next
        return engine.clear()
    }
}
