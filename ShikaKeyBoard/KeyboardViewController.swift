import UIKit

/// Owns scheme selection and the iOS text connection; views only emit key events.
class KeyboardViewController: UIInputViewController, SKKeyboardEventHandler {
    private let candidateBar = CandidateBarView()
    private let textConnection = SKMarkedTextConnection()
    private let expandedCandidates = SKExpandedCandidatesView()
    private var candidatesExpanded = false
    private var inputSession: SKInputSession?
    private let chineseJapaneseView = SKChineseJapaneseKeyboardView()
    private let shuangpinView = SKShuangpinKeyboardView()
    private let numberView = SKNumberInputView()
    private let languageButton = SKInputSwitchButton()
    private let shuangpinLabel = UILabel()
    private var keyboardState = SKKeyboardState(scheme: SKInputScheme(rawValue:
        UserDefaults.standard.string(forKey: SKInputScheme.preferenceKey) ?? "") ?? .chineseJapanese,
        languageMode: SKChineseJapaneseMode(rawValue: UserDefaults.standard.string(forKey: SKChineseJapaneseMode.preferenceKey) ?? "") ?? .mixed)
    private var keyboardBottomConstraints: [NSLayoutConstraint] = []
    private var mainHeightConstraint: NSLayoutConstraint?

    override func viewDidLoad() {
        super.viewDidLoad()
        languageButton.translatesAutoresizingMaskIntoConstraints = false
        languageButton.heightAnchor.constraint(equalToConstant: SKConfig.defaultKeyHeight).isActive = true
        for marker in [languageButton, shuangpinLabel] as [UIView] {
            let width = marker.widthAnchor.constraint(equalToConstant: SKConfig.defaultKeyHeight)
            width.priority = .init(999) // Hidden arranged views must be able to collapse to zero.
            width.isActive = true
        }
        languageButton.onTap = { [weak self] in
            guard let self else { return }
            SKDeleteKeyInteraction.cancelActive()
            let next = keyboardState.languageMode.next
            do { try inputSession?.switchConfiguration(to: SKChineseJapaneseScheme.configuration(for: next)) }
            catch { candidateBar.showError(); return }
            keyboardState.languageMode = next
            UserDefaults.standard.set(keyboardState.languageMode.rawValue, forKey: SKChineseJapaneseMode.preferenceKey)
            renderLanguageMode()
        }
        renderLanguageMode()
        shuangpinLabel.accessibilityIdentifier = "mode.shuangpin"
        languageButton.accessibilityIdentifier = "mode.chineseJapanese"
        shuangpinLabel.text = "双拼"
        shuangpinLabel.font = .systemFont(ofSize: 16, weight: .medium)
        shuangpinLabel.textColor = SKConfig.keyTitleColor
        shuangpinLabel.textAlignment = .center
        shuangpinLabel.accessibilityLabel = "中文，双拼"

        candidateBar.heightAnchor.constraint(equalToConstant: SKConfig.topBarHeight).isActive = true
        candidateBar.onSelect = { [weak self] in self?.selectCandidate($0) }
        candidateBar.onToggleExpanded = { [weak self] in self?.toggleCandidates() }
        expandedCandidates.onSelect = { [weak self] in self?.selectCandidate($0) }
        expandedCandidates.onLoadMore = { [weak self] in self?.inputSession?.loadMoreCandidates() }
        candidateBar.onRetry = { [weak self] in self?.loadEngine() }
        let topBar = UIStackView(arrangedSubviews: [languageButton, shuangpinLabel, candidateBar])
        topBar.axis = .horizontal
        topBar.alignment = .center
        topBar.isLayoutMarginsRelativeArrangement = true
        topBar.directionalLayoutMargins = NSDirectionalEdgeInsets(top: 0, leading: SKMainKeyboardMetrics.inset, bottom: 0, trailing: 0)
        topBar.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(topBar)
        NSLayoutConstraint.activate([
            topBar.topAnchor.constraint(equalTo: view.topAnchor),
            topBar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            topBar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            topBar.heightAnchor.constraint(equalToConstant: SKConfig.topBarHeight)
        ])
        chineseJapaneseView.eventHandler = self
        shuangpinView.eventHandler = self
        numberView.eventHandler = self
        for keyboard in [chineseJapaneseView, shuangpinView, numberView] as [UIView] {
            keyboard.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(keyboard)
            NSLayoutConstraint.activate([
                keyboard.topAnchor.constraint(equalTo: topBar.bottomAnchor),
                keyboard.leadingAnchor.constraint(equalTo: view.leadingAnchor),
                keyboard.trailingAnchor.constraint(equalTo: view.trailingAnchor)
            ])
            keyboardBottomConstraints.append(keyboard.bottomAnchor.constraint(equalTo: view.bottomAnchor))
        }
        expandedCandidates.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(expandedCandidates)
        NSLayoutConstraint.activate([
            expandedCandidates.topAnchor.constraint(equalTo: topBar.bottomAnchor),
            expandedCandidates.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            expandedCandidates.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            expandedCandidates.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        mainHeightConstraint = chineseJapaneseView.heightAnchor.constraint(equalToConstant: SKMainKeyboardMetrics.portraitHeight)
        mainHeightConstraint?.priority = .init(999)
        updateVisibleKeyboard()
        loadEngine()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let mainHeight: CGFloat = traitCollection.verticalSizeClass == .compact ? 162 : SKMainKeyboardMetrics.portraitHeight
        if mainHeightConstraint?.constant != mainHeight { mainHeightConstraint?.constant = mainHeight }
        SKUtils.disableClipping(for: view)
    }

    private func loadEngine() {
        SKDeleteKeyInteraction.cancelActive()
        do {
            let engine = try SKConversionEngine(configuration: keyboardState.configuration)
            let session = SKInputSession(engine: engine, configuration: keyboardState.configuration,
                candidateIsDisplayable: SKCandidateGlyphCoverage().canDisplay,
                insertText: { [weak self] text in
                    guard let self else { return }
                    textConnection.insert(text, in: textDocumentProxy)
                },
                deleteText: { [weak self] in
                    guard let self else { return }
                    textConnection.deleteBackward(in: textDocumentProxy)
                }, updateComposition: { [weak self] text in
                    guard let self else { return }
                    textConnection.updateComposition(text, in: textDocumentProxy)
                })
            session.onUpdate = { [weak self] state in self?.renderCandidates(state) }
            inputSession = session
            renderCandidates(session.state)
        } catch {
            inputSession = nil
            candidateBar.showError()
        }
    }

    private func renderCandidates(_ state: SKEngineState) {
        if state.candidates.isEmpty { candidatesExpanded = false }
        candidateBar.update(state, expanded: candidatesExpanded)
        expandedCandidates.update(state)
        updateVisibleKeyboard()
    }

    private func toggleCandidates() {
        SKDeleteKeyInteraction.cancelActive()
        guard let inputSession, !inputSession.state.candidates.isEmpty else { return }
        candidatesExpanded.toggle()
        expandedCandidates.update(inputSession.state, resetScroll: true)
        renderCandidates(inputSession.state)
        // Prefetch enough for the first screen only. Reopening an already
        // populated grid should not fetch another page and rebuild the strip.
        let firstScreenCapacity = Int(ceil(expandedCandidates.bounds.height / 44)) * 4
        if candidatesExpanded && inputSession.state.candidates.count < firstScreenCapacity {
            inputSession.loadMoreCandidates()
        }
    }

    private func selectCandidate(_ candidate: SKCandidate) {
        SKDeleteKeyInteraction.cancelActive()
        candidatesExpanded = false
        inputSession?.select(candidate)
    }

    func didTapKey(_ key: String) {
        SKDeleteKeyInteraction.cancelActive()
        if let inputSession { inputSession.type(key) }
        else { textDocumentProxy.insertText(key) }
    }
    func didTapDelete() { _ = didDeleteBackward(byWord: false) }

    func didDeleteBackward(byWord: Bool) -> SKDeleteFeedback {
        if let inputSession, !inputSession.state.input.isEmpty {
            // Composition always retreats through its decoder, never by words.
            inputSession.deleteBackward()
            return inputSession.state.input.isEmpty ? .restartDelay : .continueRepeating
        }
        textConnection.deleteBackward(in: textDocumentProxy, byWord: byWord)
        return .continueRepeating
    }
    func didTapNextKeyboard() {
        SKDeleteKeyInteraction.cancelActive()
        inputSession?.commitPending()
        advanceToNextInputMode()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        SKDeleteKeyInteraction.cancelActive()
        textConnection.releaseComposition(in: textDocumentProxy)
        inputSession?.cancel()
    }

    override func textWillChange(_ textInput: UITextInput?) {
        // A host-side cursor/document change invalidates the engine composition.
        if !textConnection.isEditing {
            SKDeleteKeyInteraction.cancelActive()
            textConnection.releaseComposition(in: textDocumentProxy)
            inputSession?.cancel()
        }
    }

    override func textDidChange(_ textInput: UITextInput?) {
        super.textDidChange(textInput)
        updateReturnKey()
    }

    private func updateReturnKey() {
        for footer in [chineseJapaneseView.footer, shuangpinView.footer] {
            footer?.updateReturnKey(type: textDocumentProxy.returnKeyType ?? .default)
        }
    }

    func didTapSwitchScheme() {
        SKDeleteKeyInteraction.cancelActive()
        let next = keyboardState.scheme.next
        do { try inputSession?.switchConfiguration(to: next == .chineseJapanese
            ? SKChineseJapaneseScheme.configuration(for: keyboardState.languageMode) : next.configuration) }
        catch { candidateBar.showError(); return }
        candidatesExpanded = false
        keyboardState.scheme = next
        keyboardState.layout = .alphabet
        UserDefaults.standard.set(keyboardState.scheme.rawValue, forKey: SKInputScheme.preferenceKey)
        updateVisibleKeyboard()
        if let inputSession { renderCandidates(inputSession.state) }
        UIAccessibility.post(notification: .announcement,
                             argument: keyboardState.scheme == .shuangpin ? "双拼" : "中日混合")
        (next == .shuangpin ? shuangpinView.footer : chineseJapaneseView.footer)?.showSchemeTitle()
    }

    func didTapSwitchLayout(to layout: SKKeyboardLayoutType) {
        SKDeleteKeyInteraction.cancelActive()
        inputSession?.commitPending()
        candidatesExpanded = false
        keyboardState.layout = layout
        updateVisibleKeyboard()
    }

    private func renderLanguageMode() {
        languageButton.currentState = keyboardState.languageMode
        chineseJapaneseView.currentLanguageState = keyboardState.languageMode
        chineseJapaneseView.footer?.showSchemeTitle()
    }

    private func updateVisibleKeyboard() {
        updateReturnKey()
        chineseJapaneseView.isHidden = candidatesExpanded || keyboardState.layout != .alphabet || keyboardState.scheme != .chineseJapanese
        shuangpinView.isHidden = candidatesExpanded || keyboardState.layout != .alphabet || keyboardState.scheme != .shuangpin
        numberView.isHidden = candidatesExpanded || keyboardState.layout != .number
        expandedCandidates.isHidden = !candidatesExpanded
        let hasCandidates = !(inputSession?.state.candidates.isEmpty ?? true)
        languageButton.isHidden = hasCandidates || keyboardState.scheme != .chineseJapanese
        shuangpinLabel.isHidden = hasCandidates || keyboardState.scheme != .shuangpin
        // Hidden legacy number-page constraints must not stretch the measured alphabet rows.
        for (index, constraint) in keyboardBottomConstraints.enumerated() {
            constraint.isActive = index == 2 ? keyboardState.layout == .number : keyboardState.layout == .alphabet
        }
        mainHeightConstraint?.isActive = keyboardState.layout == .alphabet
    }
}
