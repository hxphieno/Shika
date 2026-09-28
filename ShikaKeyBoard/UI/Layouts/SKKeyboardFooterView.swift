import UIKit

/// Main-keyboard controls. The custom number/symbol page uses its own controls.
final class SKKeyboardFooterView: UIView {
    weak var eventHandler: SKKeyboardEventHandler?
    let inputModeSwitchKey = SKMainKeyButton(title: "", role: .function)
    var keyFrames: [CGRect] = []
    private var keys: [SKMainKeyButton] = []
    private let space: SKMainKeyButton
    private var hideSpaceTitle: DispatchWorkItem?
    private let enter = SKMainKeyButton(title: "换行", role: .function)

    init(schemeTitle: String, nextSchemeTitle: String) {
        space = SKMainKeyButton(title: schemeTitle, role: .space)
        super.init(frame: .zero)
        let number = SKMainKeyButton(title: "123", role: .function)
        number.addTarget(self, action: #selector(showNumbers), for: .touchUpInside)
        inputModeSwitchKey.useSymbol("globe", label: "切换系统键盘")
        inputModeSwitchKey.accessibilityIdentifier = "keyboard.inputMode"
        inputModeSwitchKey.accessibilityHint = "轻点切换键盘，长按选择表情符号键盘"
        space.accessibilityLabel = "空格，当前方案：\(schemeTitle)"
        space.addTarget(self, action: #selector(insertSpace), for: .touchUpInside)
        enter.useSymbol("return", label: "换行")
        enter.addTarget(self, action: #selector(performReturn), for: .touchUpInside)
        keys = [number, inputModeSwitchKey, space, enter]
        keys.forEach(addSubview)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func showSchemeTitle(_ title: String? = nil) {
        if let title {
            space.keyTitle = title
            space.accessibilityLabel = "空格，当前方案：\(title)"
        }
        hideSpaceTitle?.cancel()
        space.titleLabel?.layer.removeAllAnimations()
        space.titleLabel?.alpha = 1
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            UIView.animate(withDuration: 0.35, delay: 0, options: [.curveEaseOut, .allowUserInteraction]) {
                self.space.titleLabel?.alpha = 0
            }
        }
        hideSpaceTitle = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 2, execute: work)
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window != nil { showSchemeTitle() }
        else {
            hideSpaceTitle?.cancel()
            space.titleLabel?.layer.removeAllAnimations()
            space.titleLabel?.alpha = 0
        }
    }

    func updateReturnKey(type: UIReturnKeyType) {
        let title: String
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
        enter.keyTitle = title
        enter.setImage(nil, for: .normal)
        enter.accessibilityLabel = title
        enter.isPrimaryAction = title != "换行"
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
    @objc private func insertSpace() { eventHandler?.didTapKey(" ") }
    @objc private func performReturn() { eventHandler?.didTapKey("\n") }
}
