import UIKit

/// Main-keyboard controls. The custom number/symbol page uses its own controls.
final class SKKeyboardFooterView: UIView {
    weak var eventHandler: SKKeyboardEventHandler?
    var keyFrames: [CGRect] = []
    private var keys: [SKMainKeyButton] = []
    private let enter = SKMainKeyButton(title: "换行", role: .function)

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
        enter.useSymbol("return", label: "换行")
        enter.addTarget(self, action: #selector(performReturn), for: .touchUpInside)
        keys = [number, scheme, space, enter]
        keys.forEach(addSubview)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func updateReturnKey(type: UIReturnKeyType, confirmsJapanese: Bool) {
        let title: String
        if confirmsJapanese { title = "确定" }
        else {
            switch type {
            case .go: title = "前往"
            case .google, .yahoo, .search: title = "搜索"
            case .join: title = "加入"
            case .next: title = "下一项"
            case .route: title = "路线"
            case .send: title = "发送"
            case .done: title = "完成"
            case .emergencyCall: title = "紧急呼叫"
            case .continue: title = "继续"
            default: title = "换行"
            }
        }
        enter.keyTitle = title
        enter.setImage(nil, for: .normal)
        enter.accessibilityLabel = title
        enter.isPrimaryAction = !confirmsJapanese && title != "换行"
        if title == "换行" { enter.useSymbol("return", label: title) }
        else if title == "发送" { enter.useSymbol("arrow.up", label: title) }
    }
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
    @objc private func performReturn() { eventHandler?.didTapKey("\n") }
}
