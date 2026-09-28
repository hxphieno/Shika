import Foundation

// The height test compiles the real controller and views without Engine/.
// Fixed candidates keep this geometry test independent of Rime deployment.
@MainActor
final class SKConversionEngine: SKInputEngine {
    private var state = SKEngineState()
    init(configuration: SKInputConfiguration) throws {}
    func process(key: Int32) -> SKEngineState {
        if let scalar = UnicodeScalar(UInt32(key)) { state.input += String(scalar) }
        state.preedit = state.input
        state.candidates = ["你坏", "尼康", "你好", "你会", "拟好", "泥青"].enumerated().map {
            SKCandidate(index: $0.offset, text: $0.element, comment: "")
        }
        return state
    }
    func selectCandidate(at index: Int) -> SKEngineState { commit() }
    func candidatePage(startingAt index: Int, limit: Int) -> SKCandidatePage {
        SKCandidatePage(candidates: Array(state.candidates.dropFirst(index).prefix(limit)), nextIndex: state.candidates.count, hasMore: false)
    }
    func changePage(backward: Bool) -> SKEngineState { state }
    func commit() -> SKEngineState {
        let text = state.candidates.first?.text ?? state.input
        state = SKEngineState()
        return SKEngineState(committedText: text)
    }
    func clear() -> SKEngineState { state = SKEngineState(); return state }
    func selectConfiguration(_ configuration: SKInputConfiguration) throws -> SKEngineState { clear() }
}
