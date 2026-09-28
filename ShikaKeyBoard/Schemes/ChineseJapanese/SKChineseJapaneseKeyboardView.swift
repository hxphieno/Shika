import UIKit

final class SKChineseJapaneseKeyboardView: SKMainKeyboardSurface {
    weak var eventHandler: SKKeyboardEventHandler? { didSet { footer?.eventHandler = eventHandler } }
    private var shiftState = SKShiftState()
    private var letters: [[SKMainKeyButton]] = []
    private let shift = SKMainKeyButton(title: "⇧", role: .function)
    private let delete = SKMainKeyButton(title: "⌫", role: .function)
    private let longVowelKey = SKLongVowelKeyButton()
    var currentLanguageState: SKChineseJapaneseMode = .mixed { didSet { arrangeRows() } }
    override var isHidden: Bool {
        didSet { if isHidden { longVowelKey.cancelLongVowelSelection() } }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        letters = SKChineseJapaneseLayout.lowercase.map { row in
            row.map { title in
                let button: SKMainKeyButton = title == "l" ? longVowelKey : SKMainKeyButton(title: title == "—" ? "ー" : title)
                button.accessibilityIdentifier = "chineseJapanese.\(button.keyTitle)"
                button.addTarget(self, action: #selector(typeLetter(_:)), for: .touchUpInside)
                return button
            }
        }
        longVowelKey.onSelection = { [weak self] text in self?.typeText(text) }
        let bottom = SKKeyboardFooterView(schemeTitle: "中日混合", nextSchemeTitle: "自然码双拼")
        footer = bottom
        delete.useSymbol("delete.left", label: "删除")
        delete.onDelete = { [weak self] byWord in
            self?.eventHandler?.didDeleteBackward(byWord: byWord) ?? .stop
        }
        shift.addTarget(self, action: #selector(toggleShift), for: .touchUpInside)
        let hold = UILongPressGestureRecognizer(target: self, action: #selector(holdShift(_:)))
        shift.addGestureRecognizer(hold)
        arrangeRows()
        updateShift()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    private func arrangeRows() {
        guard letters.count == 3 else { return }
        longVowelKey.isLongVowelEnabled = currentLanguageState == .mixed
        let middle = currentLanguageState == .japanese ? letters[1] : Array(letters[1].prefix(9))
        keyRows = [letters[0], middle, [shift] + letters[2] + [delete]]
    }
    private func updateShift() {
        let symbol = shiftState.casing == .locked ? "capslock.fill" : (shiftState.casing == .upper ? "shift.fill" : "shift")
        shift.useSymbol(symbol, label: "切换大小写")
        shift.accessibilityValue = shiftState.casing == .locked ? "大写锁定" : (shiftState.casing == .upper ? "大写" : "小写")
        for key in letters.flatMap({ $0 }) {
            key.keyTitle = shiftState.casing == .lower ? key.keyTitle.lowercased() : key.keyTitle.uppercased()
        }
    }
    @objc private func typeLetter(_ sender: SKMainKeyButton) {
        typeText(sender.keyTitle)
    }
    private func typeText(_ text: String) {
        shiftState.willTypeLetter()
        eventHandler?.didTapKey(text)
        if shiftState.didTypeLetter() { updateShift() }
    }
    @objc private func toggleShift() {
        shiftState.tap(at: CACurrentMediaTime())
        updateShift()
    }
    @objc private func lockShift() { shiftState.lock(); updateShift() }
    @objc private func holdShift(_ gesture: UILongPressGestureRecognizer) { if gesture.state == .began { lockShift() } }
}
