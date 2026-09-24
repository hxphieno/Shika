import UIKit

/// Owns scheme selection and the iOS text connection; views only emit key events.
class KeyboardViewController: UIInputViewController, SKKeyboardEventHandler {
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

        let topBar = UIStackView(arrangedSubviews: [languageButton, shuangpinLabel, CandidateBarView()])
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
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        SKUtils.disableClipping(for: view)
    }

    func didTapKey(_ key: String) { textDocumentProxy.insertText(key) }
    func didTapDelete() { textDocumentProxy.deleteBackward() }
    func didTapNextKeyboard() { advanceToNextInputMode() }

    func didTapSwitchScheme() {
        currentScheme = currentScheme.next
        currentLayout = .alphabet
        UserDefaults.standard.set(currentScheme.rawValue, forKey: SKInputScheme.preferenceKey)
        updateVisibleKeyboard()
        UIAccessibility.post(notification: .announcement,
                             argument: currentScheme == .shuangpin ? "小鹤双拼" : "中日混合")
    }

    func didTapSwitchLayout(to layout: SKKeyboardLayoutType) {
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
