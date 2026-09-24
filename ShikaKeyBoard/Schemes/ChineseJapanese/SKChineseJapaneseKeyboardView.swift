import UIKit

final class SKChineseJapaneseKeyboardView: SKMainKeyboardSurface {
    weak var eventHandler: SKKeyboardEventHandler? { didSet { footer?.eventHandler = eventHandler } }
    private enum ShiftState { case lower, upper, locked }
    private var shiftState: ShiftState = .lower
    private var lastShiftTapTime: CFTimeInterval?
    private var letters: [[SKMainKeyButton]] = []
    private let shift = SKMainKeyButton(title: "⇧", role: .function)
    private let delete = SKMainKeyButton(title: "⌫", role: .function)
    var currentLanguageState: SKInputSwitchState = .mixed { didSet { arrangeRows() } }

    override init(frame: CGRect) {
        super.init(frame: frame)
        letters = SKChineseJapaneseLayout.lowercase.map { row in
            row.map { title in
                let button = SKMainKeyButton(title: title == "—" ? "ー" : title)
                button.accessibilityIdentifier = "chineseJapanese.\(button.keyTitle)"
                button.addTarget(self, action: #selector(typeLetter(_:)), for: .touchUpInside)
                return button
            }
        }
        let bottom = SKKeyboardFooterView(schemeTitle: "中日混合")
        footer = bottom
        delete.useSymbol("delete.left", label: "删除")
        delete.onPress = { [weak self] in self?.eventHandler?.didTapDelete() }
        delete.onRepeat = { [weak self] in self?.eventHandler?.didTapDelete() }
        shift.addTarget(self, action: #selector(toggleShift), for: .touchUpInside)
        let hold = UILongPressGestureRecognizer(target: self, action: #selector(holdShift(_:)))
        shift.addGestureRecognizer(hold)
        arrangeRows()
        updateShift()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    private func arrangeRows() {
        guard letters.count == 3 else { return }
        let middle = currentLanguageState == .chinese ? Array(letters[1].prefix(9)) : letters[1]
        keyRows = [letters[0], middle, [shift] + letters[2] + [delete]]
    }
    private func updateShift() {
        let symbol = shiftState == .locked ? "capslock.fill" : (shiftState == .upper ? "shift.fill" : "shift")
        shift.useSymbol(symbol, label: "切换大小写")
        shift.accessibilityValue = shiftState == .locked ? "大写锁定" : (shiftState == .upper ? "大写" : "小写")
        for key in letters.flatMap({ $0 }) {
            key.keyTitle = shiftState == .lower ? key.keyTitle.lowercased() : key.keyTitle.uppercased()
        }
    }
    @objc private func typeLetter(_ sender: SKMainKeyButton) {
        lastShiftTapTime = nil
        eventHandler?.didTapKey(sender.keyTitle)
        if shiftState == .upper { shiftState = .lower; updateShift() }
    }
    @objc private func toggleShift() {
        let now = CACurrentMediaTime()
        if shiftState == .locked {
            shiftState = .lower
            lastShiftTapTime = nil
        } else if let previous = lastShiftTapTime, now - previous <= 0.3 {
            shiftState = .locked
            lastShiftTapTime = nil
        } else {
            shiftState = shiftState == .lower ? .upper : .lower
            lastShiftTapTime = now
        }
        updateShift()
    }
    @objc private func lockShift() { lastShiftTapTime = nil; shiftState = .locked; updateShift() }
    @objc private func holdShift(_ gesture: UILongPressGestureRecognizer) { if gesture.state == .began { lockShift() } }
}
