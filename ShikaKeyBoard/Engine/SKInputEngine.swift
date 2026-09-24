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

    init(schema: String, resourceURL: URL? = nil, userURL: URL? = nil) throws {
        let resources = resourceURL ?? Bundle.main.url(forResource: "RimeData", withExtension: "bundle")
        guard let resources else { throw EngineError.missingResources }
        let directory = try userURL ?? FileManager.default.url(for: .applicationSupportDirectory,
            in: .userDomainMask, appropriateFor: nil, create: true).appendingPathComponent("RimeUser", isDirectory: true)
        session = try SKRimeSession(sharedPath: resources.path, userPath: directory.path, schema: schema)
    }

    func process(key: Int32) -> SKEngineState { decode(session.processKey(key)) }
    func selectCandidate(at index: Int) -> SKEngineState { decode(session.selectCandidate(UInt(index))) }
    func changePage(backward: Bool) -> SKEngineState { decode(session.changePage(backward)) }
    func commit() -> SKEngineState { decode(session.commitComposition()) }
    func clear() -> SKEngineState { decode(session.clearComposition()) }
    func selectSchema(_ schema: String) throws -> SKEngineState {
        let result = session.selectSchema(schema)
        if result["error"] != nil { throw EngineError.missingResources }
        return decode(result)
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
