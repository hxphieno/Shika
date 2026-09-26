import Foundation

/// Input policy above the engine, independent of UIKit and textDocumentProxy.
@MainActor
final class SKInputSession {
    private let engine: SKInputEngine
    private var configuration: SKInputConfiguration
    private let insertText: (String) -> Void
    private let deleteText: () -> Void
    private let updateComposition: (String) -> Void
    private let candidateIsDisplayable: (String) -> Bool
    private let specialCandidates: SKSpecialCandidates
    private var specialCandidate: SKCandidate?
    private var nextCandidateIndex = 0
    private var preferVisibleCandidate = false
    private var revision = 0
    private var candidateLoadTask: Task<Void, Never>?
    private(set) var state = SKEngineState()
    var onUpdate: ((SKEngineState) -> Void)?

    init(engine: SKInputEngine, configuration: SKInputConfiguration, candidateIsDisplayable: @escaping (String) -> Bool = { _ in true }, insertText: @escaping (String) -> Void, deleteText: @escaping () -> Void, updateComposition: @escaping (String) -> Void = { _ in }, specialCandidates: SKSpecialCandidates = SKSpecialCandidates()) {
        self.engine = engine
        self.configuration = configuration
        self.insertText = insertText
        self.deleteText = deleteText
        self.updateComposition = updateComposition
        self.candidateIsDisplayable = candidateIsDisplayable
        self.specialCandidates = specialCandidates
    }

    func type(_ text: String) {
        switch configuration.inputPolicy.action(for: text, isComposing: !state.input.isEmpty) {
        case let .engineKey(key, insertIfUnhandled):
            if key == 32, preferVisibleCandidate {
                if let first = state.candidates.first { select(first) }
                else { apply(engine.commitLiteralFallback(rawInput: state.input)) }
                return
            }
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
        if candidate == specialCandidate {
            // Only whole, unconfirmed Chinese input can produce this choice.
            // Clear marked text and native composition without learning a word
            // the user did not select or dispatching a synthetic ID to Rime.
            apply(engine.clear())
            insertText(candidate.text)
            return
        }
        apply(engine.selectCandidate(at: candidate.index))
    }

    func loadMoreCandidates() {
        guard !state.input.isEmpty, !state.isLastPage, candidateLoadTask == nil else { return }
        appendCandidates(until: state.candidates.count + 40, revision: revision)
    }

    private func appendCandidates(until target: Int, revision expectedRevision: Int) {
        guard revision == expectedRevision else { return }
        var seen = Set(state.candidates.map(\.contentIdentity))
        // Bound synchronous work. A run of missing glyphs must not hide later
        // valid candidates or monopolize the input thread while scanning them.
        for _ in 0..<4 where !state.isLastPage && state.candidates.count < target {
            let page = engine.candidatePage(startingAt: nextCandidateIndex,
                limit: min(40, target - state.candidates.count))
            state.candidates += page.candidates.filter {
                candidateIsDisplayable($0.text) && seen.insert($0.contentIdentity).inserted
            }
            state.isLastPage = !page.hasMore || page.nextIndex <= nextCandidateIndex
            nextCandidateIndex = page.nextIndex
        }
        if !state.isLastPage, state.candidates.count < target {
            candidateLoadTask = Task { @MainActor [weak self] in
                await Task.yield()
                guard !Task.isCancelled, let self, revision == expectedRevision else { return }
                candidateLoadTask = nil
                appendCandidates(until: target, revision: expectedRevision)
            }
        }
        // Browsing never changes the marked text or the engine's selected page.
        publishCandidates()
    }

    private func publishCandidates() {
        if let specialCandidate { state.candidates.removeAll { $0 == specialCandidate } }
        specialCandidate = specialCandidates.suggestion(for: state, configuration: configuration,
                                                        isDisplayable: candidateIsDisplayable)
        if let specialCandidate {
            state.candidates.removeAll { $0.text == specialCandidate.text }
            state.candidates.insert(specialCandidate, at: min(2, state.candidates.count))
        }
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
        if preferVisibleCandidate {
            if let first = state.candidates.first { apply(engine.commitCandidate(at: first.index)) }
            else { apply(engine.commitLiteralFallback(rawInput: state.input)) }
            return
        }
        apply(engine.commit())
    }

    func switchConfiguration(to configuration: SKInputConfiguration) throws {
        commitPending()
        let result = try engine.selectConfiguration(configuration)
        self.configuration = configuration
        apply(result)
    }

    private func apply(_ result: SKEngineState) {
        candidateLoadTask?.cancel()
        candidateLoadTask = nil
        revision &+= 1
        if !result.committedText.isEmpty {
            insertText(result.committedText)
        }
        state = result
        specialCandidate = nil
        state.candidates = result.candidates.filter { candidateIsDisplayable($0.text) }
        preferVisibleCandidate = result.candidates.first.map { !candidateIsDisplayable($0.text) } ?? false
        // Commit is a one-shot output, never retained for subsequent UI updates.
        state.committedText = ""
        // Pagination follows native IDs, including hidden rows. Never renumber
        // survivors: the engine still needs its original ID for selection.
        nextCandidateIndex = (result.candidates.map(\.index).filter { $0 >= 0 }.max() ?? -1) + 1
        updateComposition(state.input.isEmpty ? "" : (state.preedit.isEmpty ? state.input : state.preedit))
        if state.candidates.count < result.candidates.count, !state.isLastPage {
            appendCandidates(until: result.candidates.count, revision: revision)
        } else { publishCandidates() }
    }
}
