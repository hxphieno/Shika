import UIKit

/// Owns scheme selection and the iOS text connection; views only emit key events.
class KeyboardViewController: UIInputViewController, SKKeyboardEventHandler {
    private let candidateBar = CandidateBarView()
    private var applyingEngineEdit = false
    private var inputSession: SKInputSession?
    private let globe = UIButton(type: .system)
    private let chineseJapaneseView = SKChineseJapaneseKeyboardView()
    private let shuangpinView = SKShuangpinKeyboardView()
    private let numberView = SKNumberInputView()
    private let languageButton = SKInputSwitchButton()
    private let shuangpinLabel = UILabel()
    private var currentScheme = SKInputScheme(rawValue:
        UserDefaults.standard.string(forKey: SKInputScheme.preferenceKey) ?? "") ?? .chineseJapanese
    private var currentLayout: SKKeyboardLayoutType = .alphabet

    override func viewDidLoad() {
        super.viewDidLoad()
        languageButton.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            languageButton.widthAnchor.constraint(equalToConstant: SKConfig.defaultKeyHeight),
            languageButton.heightAnchor.constraint(equalToConstant: SKConfig.defaultKeyHeight)
        ])
        languageButton.stateChangeHandler = { [weak self] state in
            self?.chineseJapaneseView.currentLanguageState = state
        }
        shuangpinLabel.text = "双拼"
        shuangpinLabel.font = .systemFont(ofSize: 16, weight: .medium)
        shuangpinLabel.textColor = SKConfig.keyTitleColor
        shuangpinLabel.textAlignment = .center
        shuangpinLabel.widthAnchor.constraint(equalToConstant: SKConfig.defaultKeyHeight).isActive = true
        shuangpinLabel.accessibilityLabel = "中文，小鹤双拼"

        globe.setImage(UIImage(systemName: "globe"), for: .normal)
        globe.accessibilityLabel = "切换到下一个系统键盘"
        globe.addTarget(self, action: #selector(nextSystemKeyboard), for: .touchUpInside)
        globe.widthAnchor.constraint(equalToConstant: 32).isActive = true
        candidateBar.heightAnchor.constraint(equalToConstant: SKConfig.topBarHeight).isActive = true
        candidateBar.onSelect = { [weak self] in self?.inputSession?.select($0) }
        candidateBar.onPage = { [weak self] in self?.inputSession?.changePage(backward: $0) }
        candidateBar.onCommitRaw = { [weak self] in self?.inputSession?.commitRaw() }
        candidateBar.onRetry = { [weak self] in self?.loadEngine() }
        let topBar = UIStackView(arrangedSubviews: [languageButton, shuangpinLabel, candidateBar, globe])
        topBar.axis = .horizontal
        topBar.alignment = .center
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
                keyboard.trailingAnchor.constraint(equalTo: view.trailingAnchor),
                keyboard.bottomAnchor.constraint(equalTo: view.bottomAnchor)
            ])
        }
        updateVisibleKeyboard()
        loadEngine()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        SKUtils.disableClipping(for: view)
    }

    private func loadEngine() {
        do {
            let engine = try SKRimeEngine(schema: currentScheme.schemaID)
            let session = SKInputSession(engine: engine,
                insertText: { [weak self] text in
                    guard let self else { return }
                    applyingEngineEdit = true
                    textDocumentProxy.insertText(text)
                    applyingEngineEdit = false
                },
                deleteText: { [weak self] in self?.textDocumentProxy.deleteBackward() })
            session.onUpdate = { [weak self] state in self?.renderCandidates(state) }
            inputSession = session
            renderCandidates(session.state)
        } catch {
            inputSession = nil
            candidateBar.showError()
        }
    }

    private func renderCandidates(_ state: SKEngineState) {
        candidateBar.update(state, idleTitle: currentScheme == .shuangpin ? "小鹤双拼" : "中文全拼")
    }

    func didTapKey(_ key: String) {
        if let inputSession { inputSession.type(key) }
        else { textDocumentProxy.insertText(key) }
    }
    func didTapDelete() {
        if let inputSession { inputSession.deleteBackward() }
        else { textDocumentProxy.deleteBackward() }
    }
    func didTapNextKeyboard() {
        inputSession?.commitPending()
        advanceToNextInputMode()
    }
    @objc private func nextSystemKeyboard() { didTapNextKeyboard() }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        inputSession?.cancel()
    }

    override func textWillChange(_ textInput: UITextInput?) {
        // A host-side cursor/document change invalidates an uncommitted composition.
        if !applyingEngineEdit { inputSession?.cancel() }
    }

    func didTapSwitchScheme() {
        let next = currentScheme.next
        do { try inputSession?.switchSchema(to: next.schemaID) }
        catch { candidateBar.showError(); return }
        currentScheme = next
        currentLayout = .alphabet
        UserDefaults.standard.set(currentScheme.rawValue, forKey: SKInputScheme.preferenceKey)
        updateVisibleKeyboard()
        if let inputSession { renderCandidates(inputSession.state) }
        UIAccessibility.post(notification: .announcement,
                             argument: currentScheme == .shuangpin ? "小鹤双拼" : "中日混合")
    }

    func didTapSwitchLayout(to layout: SKKeyboardLayoutType) {
        inputSession?.commitPending()
        currentLayout = layout
        updateVisibleKeyboard()
    }

    private func updateVisibleKeyboard() {
        chineseJapaneseView.isHidden = currentLayout != .alphabet || currentScheme != .chineseJapanese
        shuangpinView.isHidden = currentLayout != .alphabet || currentScheme != .shuangpin
        numberView.isHidden = currentLayout != .number
        languageButton.isHidden = currentScheme != .chineseJapanese
        shuangpinLabel.isHidden = currentScheme != .shuangpin
    }
}
