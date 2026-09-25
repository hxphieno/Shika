import UIKit

/// Main-keyboard controls. The custom number/symbol page uses its own controls.
final class SKKeyboardFooterView: UIView {
    weak var eventHandler: SKKeyboardEventHandler?
    var keyFrames: [CGRect] = []
    private var keys: [SKMainKeyButton] = []

    init(schemeTitle: String, nextSchemeTitle: String) {
        super.init(frame: .zero)
        let number = SKMainKeyButton(title: "123", role: .function)
        number.addTarget(self, action: #selector(showNumbers), for: .touchUpInside)
        let scheme = SKMainKeyButton(title: "🦌", role: .function)
        scheme.titleLabel?.font = .systemFont(ofSize: 24)
        scheme.accessibilityLabel = "切换输入方案"
        scheme.accessibilityHint = "切换到\(nextSchemeTitle)"
        scheme.addTarget(self, action: #selector(switchScheme), for: .touchUpInside)
        let space = SKMainKeyButton(title: schemeTitle, role: .space)
        space.accessibilityLabel = "空格，当前方案：\(schemeTitle)"
        space.addTarget(self, action: #selector(insertSpace), for: .touchUpInside)
        let enter = SKMainKeyButton(title: "换行", role: .function)
        enter.useSymbol("return", label: "换行")
        // Keep the logical title for existing keyboard-action tests and VoiceOver.
        enter.addTarget(self, action: #selector(insertNewline), for: .touchUpInside)
        keys = [number, scheme, space, enter]
        keys.forEach(addSubview)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func layoutSubviews() {
        super.layoutSubviews()
        for (key, frame) in zip(keys, keyFrames) { key.frame = frame }
    }
    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        keys.contains { $0.point(inside: convert(point, to: $0), with: event) }
    }
    @objc private func showNumbers() { eventHandler?.didTapSwitchLayout(to: .number) }
    @objc private func switchScheme() { eventHandler?.didTapSwitchScheme() }
    @objc private func insertSpace() { eventHandler?.didTapKey(" ") }
    @objc private func insertNewline() { eventHandler?.didTapKey("\n") }
}
