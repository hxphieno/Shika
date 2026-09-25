import UIKit

/// Chinese-only scheme; shares main-key geometry, not Chinese/Japanese language state.
final class SKShuangpinKeyboardView: SKMainKeyboardSurface {
    weak var eventHandler: SKKeyboardEventHandler? { didSet { footer?.eventHandler = eventHandler } }
    private var shiftState = SKShiftState()
    private var letterButtons: [SKAnnotatedKeyButton] = []
    private let shift = SKMainKeyButton(title: "⇧", role: .function)
    private let delete = SKMainKeyButton(title: "⌫", role: .function)

    override init(frame: CGRect) {
        super.init(frame: frame)
        let rows = SKShuangpinLayout.rows.map { row in
            row.map { letter -> SKMainKeyButton in
                let key = SKAnnotatedKeyButton(letter: String(letter), initial: SKShuangpinLayout.initials[letter], final: SKShuangpinLayout.finals[letter] ?? "")
                key.accessibilityIdentifier = "shuangpin.\(letter)"
                key.addTarget(self, action: #selector(typeLetter(_:)), for: .touchUpInside)
                letterButtons.append(key)
                return key
            }
        }
        footer = SKKeyboardFooterView(schemeTitle: "双拼", nextSchemeTitle: "中日混合")
        delete.useSymbol("delete.left", label: "删除")
        delete.onPress = { [weak self] in self?.eventHandler?.didTapDelete() }
        delete.onRepeat = { [weak self] in self?.eventHandler?.didTapDelete() }
        keyRows = [rows[0], rows[1], [shift] + rows[2] + [delete]]
        shift.addTarget(self, action: #selector(toggleShift), for: .touchUpInside)
        let hold = UILongPressGestureRecognizer(target: self, action: #selector(holdShift(_:)))
        shift.addGestureRecognizer(hold)
        updateShift()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    @objc private func typeLetter(_ sender: SKAnnotatedKeyButton) {
        shiftState.willTypeLetter()
        eventHandler?.didTapKey(sender.keyTitle)
        if shiftState.didTypeLetter() { updateShift() }
    }
    @objc private func toggleShift() {
        shiftState.tap(at: CACurrentMediaTime())
        updateShift()
    }
    @objc private func lockShift() { shiftState.lock(); updateShift() }
    @objc private func holdShift(_ gesture: UILongPressGestureRecognizer) { if gesture.state == .began { lockShift() } }
    private func updateShift() {
        shift.useSymbol(shiftState.casing == .locked ? "capslock.fill" : (shiftState.casing == .upper ? "shift.fill" : "shift"), label: "切换大小写")
        shift.accessibilityValue = shiftState.casing == .locked ? "大写锁定" : (shiftState.casing == .upper ? "大写" : "小写")
        for key in letterButtons { key.keyTitle = shiftState.casing == .lower ? key.keyTitle.lowercased() : key.keyTitle.uppercased() }
    }
}
