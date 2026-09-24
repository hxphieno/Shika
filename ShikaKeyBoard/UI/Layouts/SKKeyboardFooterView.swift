import UIKit

/// Shared controls, independent of language and encoding scheme.
final class SKKeyboardFooterView: UIStackView {
    weak var eventHandler: SKKeyboardEventHandler?

    init(schemeTitle: String) {
        super.init(frame: .zero)
        axis = .horizontal
        alignment = .fill
        distribution = .fill
        spacing = SKConfig.keyboardHorizontalSpacing

        let number = key("123", width: 42, action: #selector(showNumbers))
        let scheme = key("🦌", width: 42, action: #selector(switchScheme), fontSize: 24)
        scheme.accessibilityLabel = "切换输入方案"
        scheme.accessibilityHint = schemeTitle == "中日混合" ? "切换到小鹤双拼" : "切换到中日混合"
        let space = key(schemeTitle, width: 185, action: #selector(insertSpace))
        space.accessibilityLabel = "空格，当前方案：\(schemeTitle)"
        space.constraints.first { $0.firstAttribute == .width }?.isActive = false
        space.widthAnchor.constraint(greaterThanOrEqualToConstant: 70).isActive = true
        let enter = key("换行", width: 90, action: #selector(insertNewline))
        [number, scheme, space, enter].forEach { addArrangedSubview($0) }
    }

    required init(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func key(_ title: String, width: CGFloat, action: Selector, fontSize: CGFloat = 16) -> UIButton {
        let button = SKIMKeyButtonWithoutPopUpView(title: title, width: width,
                                                  font: .systemFont(ofSize: fontSize))
        button.addTarget(self, action: action, for: .touchUpInside)
        return button
    }

    @objc private func showNumbers() { eventHandler?.didTapSwitchLayout(to: .number) }
    @objc private func switchScheme() { eventHandler?.didTapSwitchScheme() }
    @objc private func insertSpace() { eventHandler?.didTapKey(" ") }
    @objc private func insertNewline() { eventHandler?.didTapKey("\n") }
}
