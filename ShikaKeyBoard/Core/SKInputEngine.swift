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
    func selectConfiguration(_ configuration: SKInputConfiguration) throws -> SKEngineState
}
