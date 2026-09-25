import Foundation

/// Input policy above the engine, independent of UIKit and textDocumentProxy.
@MainActor
final class SKInputSession {
    private let engine: SKInputEngine
    private var configuration: SKInputConfiguration
    private let insertText: (String) -> Void
    private let deleteText: () -> Void
    private let updateComposition: (String) -> Void
    private var nextCandidateIndex = 0
    private(set) var state = SKEngineState()
    var onUpdate: ((SKEngineState) -> Void)?

    init(engine: SKInputEngine, configuration: SKInputConfiguration, insertText: @escaping (String) -> Void, deleteText: @escaping () -> Void, updateComposition: @escaping (String) -> Void = { _ in }) {
        self.engine = engine
        self.configuration = configuration
        self.insertText = insertText
        self.deleteText = deleteText
        self.updateComposition = updateComposition
    }

    func type(_ text: String) {
        switch configuration.inputPolicy.action(for: text, isComposing: !state.input.isEmpty) {
        case let .engineKey(key, insertIfUnhandled):
            let next = engine.process(key: key)
            apply(next)
            if insertIfUnhandled && !next.handled { insertText(text) }
        case .literal:
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

    func loadMoreCandidates() {
        guard !state.input.isEmpty, !state.isLastPage else { return }
        let page = engine.candidatePage(startingAt: nextCandidateIndex, limit: 40)
        var seen = Set(state.candidates.map(\.contentIdentity))
        state.candidates += page.candidates.filter { seen.insert($0.contentIdentity).inserted }
        state.isLastPage = !page.hasMore || page.nextIndex <= nextCandidateIndex
        nextCandidateIndex = page.nextIndex
        // Browsing never changes the marked text or the engine's selected page.
        onUpdate?(state)
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

    func switchConfiguration(to configuration: SKInputConfiguration) throws {
        commitPending()
        let result = try engine.selectConfiguration(configuration)
        self.configuration = configuration
        apply(result)
    }

    private func apply(_ result: SKEngineState) {
        if !result.committedText.isEmpty {
            insertText(result.committedText)
        }
        state = result
        // Commit is a one-shot output, never retained for subsequent UI updates.
        state.committedText = ""
        nextCandidateIndex = (state.candidates.map(\.index).filter { $0 >= 0 }.max() ?? -1) + 1
        updateComposition(state.input.isEmpty ? "" : (state.preedit.isEmpty ? state.input : state.preedit))
        onUpdate?(state)
    }
}
