import UIKit

/// Chinese-only keyboard. Its layout and state do not depend on the Japanese modes.
final class SKShuangpinKeyboardView: UIView {
    weak var eventHandler: SKKeyboardEventHandler? {
        didSet { footer.eventHandler = eventHandler }
    }

    private enum ShiftState { case lower, upper, locked }
    private var shiftState: ShiftState = .lower
    private var letterButtons: [SKAnnotatedKeyButton] = []
    private let shift = SKIMKeyButtonWithoutPopUpView(title: "⇧", width: 42)
    private let footer = SKKeyboardFooterView(schemeTitle: "双拼")

    override init(frame: CGRect) {
        super.init(frame: frame)
        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = SKConfig.keyboardVerticalSpacing
        stack.distribution = .fillEqually
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 3),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -3),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -5)
        ])

        for (index, letters) in SKShuangpinLayout.rows.enumerated() {
            let row = UIStackView()
            row.axis = .horizontal
            row.spacing = SKConfig.keyboardHorizontalSpacing
            row.distribution = .fillEqually
            for letter in letters {
                let key = SKAnnotatedKeyButton(letter: String(letter),
                    initial: SKShuangpinLayout.initials[letter],
                    final: SKShuangpinLayout.finals[letter] ?? "")
                key.constraints.first { $0.firstAttribute == .width }?.isActive = false
                key.accessibilityIdentifier = "shuangpin.\(letter)"
                key.addTarget(self, action: #selector(typeLetter(_:)), for: .touchUpInside)
                letterButtons.append(key)
                row.addArrangedSubview(key)
            }
            if index == 2 {
                let outer = UIStackView()
                outer.spacing = SKConfig.keyboardHorizontalSpacing
                outer.axis = .horizontal
                outer.addArrangedSubview(shift)
                outer.addArrangedSubview(row)
                let delete = SKIMKeyButtonWithoutPopUpView(title: "⌫", width: 42)
                delete.accessibilityLabel = "删除"
                delete.addTarget(self, action: #selector(deleteBackward), for: .touchUpInside)
                outer.addArrangedSubview(delete)
                stack.addArrangedSubview(outer)
            } else {
                if index == 1 {
                    row.isLayoutMarginsRelativeArrangement = true
                    row.layoutMargins = UIEdgeInsets(top: 0, left: 19.5, bottom: 0, right: 19.5)
                }
                stack.addArrangedSubview(row)
            }
        }
        stack.addArrangedSubview(footer)

        // Keep one stable Shift button so recognizing the second tap survives state updates.
        let single = UITapGestureRecognizer(target: self, action: #selector(toggleShift))
        let double = UITapGestureRecognizer(target: self, action: #selector(lockShift))
        double.numberOfTapsRequired = 2
        single.require(toFail: double)
        let hold = UILongPressGestureRecognizer(target: self, action: #selector(holdShift(_:)))
        shift.addGestureRecognizer(single)
        shift.addGestureRecognizer(double)
        shift.addGestureRecognizer(hold)
        shift.accessibilityLabel = "切换大小写"
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    @objc private func typeLetter(_ sender: SKAnnotatedKeyButton) {
        // Hints are labels only; until an engine is connected, emit the actual key.
        eventHandler?.didTapKey(sender.keyTitle)
        if shiftState == .upper { shiftState = .lower; updateShift() }
    }

    @objc private func deleteBackward() { eventHandler?.didTapDelete() }
    @objc private func toggleShift() {
        shiftState = shiftState == .lower ? .upper : .lower
        updateShift()
    }
    @objc private func lockShift() { shiftState = .locked; updateShift() }
    @objc private func holdShift(_ gesture: UILongPressGestureRecognizer) {
        if gesture.state == .began { lockShift() }
    }

    private func updateShift() {
        shift.setTitle(shiftState == .lower ? "⇧" : "⇪", for: .normal)
        shift.accessibilityValue = shiftState == .locked ? "大写锁定" : (shiftState == .upper ? "大写" : "小写")
        for button in letterButtons {
            button.keyTitle = shiftState == .lower ? button.keyTitle.lowercased() : button.keyTitle.uppercased()
            button.setTitle(button.keyTitle, for: .normal)
        }
    }
}
