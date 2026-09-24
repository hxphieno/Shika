import Foundation

/// Input policy above the engine, independent of UIKit and textDocumentProxy.
@MainActor
final class SKInputSession {
    private let engine: SKInputEngine
    private let insertText: (String) -> Void
    private let deleteText: () -> Void
    private(set) var state = SKEngineState()
    var onUpdate: ((SKEngineState) -> Void)?

    init(engine: SKInputEngine, insertText: @escaping (String) -> Void, deleteText: @escaping () -> Void) {
        self.engine = engine
        self.insertText = insertText
        self.deleteText = deleteText
    }

    func type(_ text: String) {
        if text == " " && !state.input.isEmpty {
            apply(engine.process(key: 0x20))
        } else if text.unicodeScalars.count == 1, let scalar = text.unicodeScalars.first,
                  (97...122).contains(scalar.value) || scalar.value == 39 {
            let next = engine.process(key: Int32(scalar.value))
            apply(next)
            if !next.handled { insertText(text) }
        } else {
            commitPending()
            insertText(text)
        }
    }

    func deleteBackward() {
        if state.input.isEmpty { deleteText() }
        else { apply(engine.process(key: 0xff08)) }
    }

    func select(_ candidate: SKCandidate) {
        guard state.candidates.contains(candidate) else { return }
        apply(engine.selectCandidate(at: candidate.index))
    }

    func changePage(backward: Bool) { apply(engine.changePage(backward: backward)) }
    func cancel() { apply(engine.clear()) }

    func commitRaw() {
        let raw = state.input
        apply(engine.clear())
        if !raw.isEmpty { insertText(raw) }
    }

    func commitPending() {
        guard !state.input.isEmpty else { return }
        apply(engine.commit())
    }

    func switchSchema(to schema: String) throws {
        commitPending()
        apply(try engine.selectSchema(schema))
    }

    private func apply(_ result: SKEngineState) {
        if !result.committedText.isEmpty { insertText(result.committedText) }
        state = result
        // Commit is a one-shot output, never retained for subsequent UI updates.
        state.committedText = ""
        onUpdate?(state)
    }
}
