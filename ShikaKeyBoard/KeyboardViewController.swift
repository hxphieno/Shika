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
    private var keyboardState = SKKeyboardState(scheme: SKInputScheme(rawValue:
        UserDefaults.standard.string(forKey: SKInputScheme.preferenceKey) ?? "") ?? .chineseJapanese,
        languageMode: SKChineseJapaneseMode(rawValue: UserDefaults.standard.string(forKey: SKChineseJapaneseMode.preferenceKey) ?? "") ?? .mixed)
    private var keyboardBottomConstraints: [NSLayoutConstraint] = []
    private var keyboardHeightConstraint: NSLayoutConstraint?

    override func viewDidLoad() {
        super.viewDidLoad()
        // Size the input view itself, rather than asking UIKit to infer its
        // height from a (possibly hidden) keyboard page. System chrome stays
        // outside these 44 + 216 points; do not add safe-area padding again.
        inputView?.allowsSelfSizing = true
        keyboardHeightConstraint = view.heightAnchor.constraint(equalToConstant: keyboardHeight)
        keyboardHeightConstraint?.priority = .init(999)
        keyboardHeightConstraint?.isActive = true
        languageButton.translatesAutoresizingMaskIntoConstraints = false
        languageButton.heightAnchor.constraint(equalToConstant: SKConfig.defaultKeyHeight).isActive = true
        let modeWidth = languageButton.widthAnchor.constraint(equalToConstant: SKConfig.defaultKeyHeight)
        modeWidth.priority = .init(999) // Allow the stack to collapse the hidden mode button.
        modeWidth.isActive = true
        languageButton.accessibilityIdentifier = "mode.selector"
        languageButton.showsMenuAsPrimaryAction = true
        renderLanguageMode()

        candidateBar.heightAnchor.constraint(equalToConstant: SKConfig.topBarHeight).isActive = true
        candidateBar.onSelect = { [weak self] in self?.selectCandidate($0) }
        candidateBar.onToggleExpanded = { [weak self] in self?.toggleCandidates() }
        expandedCandidates.onSelect = { [weak self] in self?.selectCandidate($0) }
        expandedCandidates.onLoadMore = { [weak self] in self?.inputSession?.loadMoreCandidates() }
        candidateBar.onRetry = { [weak self] in self?.loadEngine() }
        let topBar = SKCandidateInteractionRow(arrangedSubviews: [languageButton, candidateBar])
        topBar.candidateBar = candidateBar
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
        for footer in [chineseJapaneseView.footer, shuangpinView.footer] {
            footer?.inputModeSwitchKey.addTarget(self, action: #selector(switchSystemKeyboard(_:with:)), for: .allTouchEvents)
        }
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
        updateVisibleKeyboard()
        loadEngine()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        shuangpinView.setLearningMode(SKKeyboardPreferences.load().shuangpinLearningMode)
    }

    private var keyboardHeight: CGFloat {
        SKConfig.topBarHeight + (traitCollection.verticalSizeClass == .compact ? 162 : SKMainKeyboardMetrics.portraitHeight)
    }

    override func viewWillLayoutSubviews() {
        super.viewWillLayoutSubviews()
        if keyboardHeightConstraint?.constant != keyboardHeight {
            keyboardHeightConstraint?.constant = keyboardHeight
        }
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

    @objc private func switchSystemKeyboard(_ sender: UIView, with event: UIEvent?) {
        // Accessibility activation may arrive without a touch event.
        guard let event else { didTapNextKeyboard(); return }
        SKDeleteKeyInteraction.cancelActive()
        inputSession?.commitPending()
        // UIKit owns short taps and the long-press keyboard list. There is no
        // public API for selecting the system Emoji keyboard directly.
        handleInputModeList(from: sender, with: event)
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
        selectInputMode(scheme: keyboardState.scheme.next, languageMode: keyboardState.languageMode)
    }

    func selectInputMode(scheme: SKInputScheme, languageMode: SKChineseJapaneseMode) {
        SKDeleteKeyInteraction.cancelActive()
        let configuration = scheme == .chineseJapanese
            ? SKChineseJapaneseScheme.configuration(for: languageMode) : scheme.configuration
        do { try inputSession?.switchConfiguration(to: configuration) }
        catch { candidateBar.showError(); return }
        candidatesExpanded = false
        keyboardState.scheme = scheme
        keyboardState.languageMode = languageMode
        keyboardState.layout = .alphabet
        UserDefaults.standard.set(scheme.rawValue, forKey: SKInputScheme.preferenceKey)
        UserDefaults.standard.set(languageMode.rawValue, forKey: SKChineseJapaneseMode.preferenceKey)
        renderLanguageMode()
        updateVisibleKeyboard()
        if let inputSession { renderCandidates(inputSession.state) }
        (scheme == .shuangpin ? shuangpinView.footer : chineseJapaneseView.footer)?.showSchemeTitle()
        UIAccessibility.post(notification: .announcement, argument: languageButton.accessibilityValue)
    }

    private func updateModeMenu() {
        let choices: [(String, SKInputScheme, SKChineseJapaneseMode)] = [
            ("自然码双拼", .shuangpin, keyboardState.languageMode),
            ("中文", .chineseJapanese, .chinese),
            ("日文", .chineseJapanese, .japanese),
            ("中日混合", .chineseJapanese, .mixed)
        ]
        languageButton.menu = UIMenu(children: choices.map { title, scheme, mode in
            let selected = keyboardState.scheme == scheme && (scheme == .shuangpin || keyboardState.languageMode == mode)
            return UIAction(title: title, state: selected ? .on : .off) { [weak self] _ in
                self?.selectInputMode(scheme: scheme, languageMode: mode)
            }
        })
        languageButton.isShuangpin = keyboardState.scheme == .shuangpin
        languageButton.accessibilityLabel = "切换输入模式"
        languageButton.accessibilityValue = choices.first {
            $0.1 == keyboardState.scheme && ($0.1 == .shuangpin || $0.2 == keyboardState.languageMode)
        }?.0
    }

    func didTapSwitchLayout(to layout: SKKeyboardLayoutType) {
        SKDeleteKeyInteraction.cancelActive()
        inputSession?.commitPending()
        candidatesExpanded = false
        keyboardState.layout = layout
        updateVisibleKeyboard()
    }

    private func renderLanguageMode() {
        updateModeMenu()
        languageButton.currentState = keyboardState.languageMode
        chineseJapaneseView.currentLanguageState = keyboardState.languageMode
        let title = keyboardState.languageMode == .chinese ? "中文" : keyboardState.languageMode == .japanese ? "日文" : "中日混合"
        chineseJapaneseView.footer?.showSchemeTitle(title)
    }

    private func updateVisibleKeyboard() {
        updateReturnKey()
        chineseJapaneseView.isHidden = candidatesExpanded || keyboardState.layout != .alphabet || keyboardState.scheme != .chineseJapanese
        shuangpinView.isHidden = candidatesExpanded || keyboardState.layout != .alphabet || keyboardState.scheme != .shuangpin
        numberView.isHidden = candidatesExpanded || keyboardState.layout != .number
        expandedCandidates.isHidden = !candidatesExpanded
        languageButton.isHidden = !(inputSession?.state.candidates.isEmpty ?? true)
        // Every layout uses the same keyboard height, including the number/symbol page.
        for constraint in keyboardBottomConstraints { constraint.isActive = true }
    }
}
