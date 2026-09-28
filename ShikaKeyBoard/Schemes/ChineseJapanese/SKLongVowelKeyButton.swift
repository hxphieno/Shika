import UIKit

/// Mixed-mode L keeps its normal tap; a held touch can select ー to its left.
final class SKLongVowelKeyButton: SKMainKeyButton {
    var onSelection: ((String) -> Void)?
    var isLongVowelEnabled = false {
        didSet {
            cancelLongVowelSelection()
            hold.isEnabled = isLongVowelEnabled
            hint.isHidden = !isLongVowelEnabled
            titleLabel?.font = .systemFont(ofSize: isLongVowelEnabled ? 22 : 25)
            setNeedsLayout()
            accessibilityHint = isLongVowelEnabled ? "按住并向左滑动输入长音符" : nil
            accessibilityCustomActions = isLongVowelEnabled
                ? [UIAccessibilityCustomAction(name: "输入长音符", target: self, selector: #selector(insertLongVowel))] : nil
        }
    }
    private let hint = UILabel()
    private lazy var hold: UILongPressGestureRecognizer = {
        let gesture = UILongPressGestureRecognizer(target: self, action: #selector(handleHold(_:)))
        gesture.minimumPressDuration = 0
        gesture.allowableMovement = 12
        // Begin on touch-down so a left slide never has to wait. Cancel the
        // normal button tap; release sends exactly the selected character.
        gesture.cancelsTouchesInView = true
        return gesture
    }()
    private var bubble: SKMainKeyPreview?
    private var options: [UILabel] = []
    private var selectedText: String?

    init() {
        super.init(title: "l")
        titleLabel?.textAlignment = .center
        hint.text = "ー"
        hint.font = .systemFont(ofSize: 10, weight: .medium)
        hint.textColor = .secondaryLabel
        hint.textAlignment = .center
        hint.isUserInteractionEnabled = false
        hint.isHidden = true
        hint.accessibilityIdentifier = "long-vowel.hint"
        addSubview(hint)
        hold.isEnabled = false
        addGestureRecognizer(hold)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layoutSubviews() {
        super.layoutSubviews()
        if isLongVowelEnabled {
            titleLabel?.frame = CGRect(x: 0, y: bounds.midY - 17, width: bounds.width, height: 26)
        }
        hint.frame = CGRect(x: 1, y: bounds.height - 14, width: bounds.width - 2, height: 12)
    }

    func cancelLongVowelSelection() {
        // Disabling a live recognizer prevents its eventual release from typing
        // into another mode or layout after the keyboard has been hidden.
        hold.isEnabled = false
        dismissAlternatives()
        hold.isEnabled = isLongVowelEnabled
        cancelPreview()
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window == nil { cancelLongVowelSelection() }
    }

    @objc private func insertLongVowel() -> Bool {
        guard isLongVowelEnabled else { return false }
        onSelection?("ー")
        return true
    }

    @objc func handleHold(_ gesture: UILongPressGestureRecognizer) {
        guard isLongVowelEnabled else { dismissAlternatives(); return }
        switch gesture.state {
        case .began:
            cancelPreview()
            showAlternatives()
            updateSelection(at: gesture.location(in: bubble))
        case .changed:
            updateSelection(at: gesture.location(in: bubble))
        case .ended:
            updateSelection(at: gesture.location(in: bubble))
            let text = selectedText
            dismissAlternatives()
            if let text { onSelection?(text) }
        case .cancelled, .failed:
            dismissAlternatives()
        default: break
        }
    }

    private func showAlternatives() {
        guard bubble == nil, let window else { return }
        var ancestor = superview
        var container: UIView = window
        while let view = ancestor {
            if view is SKMainKeyboardSurface { container = view.superview ?? view; break }
            ancestor = view.superview
        }
        let keyRect = convert(bounds, to: container)
        let width: CGFloat = min(112, container.bounds.width - 2 * SKMainKeyboardMetrics.inset)
        let left = max(SKMainKeyboardMetrics.inset,
                       min(keyRect.midX - width * 0.75, container.bounds.width - width - SKMainKeyboardMetrics.inset))
        let top = max(container.bounds.minY + 2, keyRect.minY - 67)
        let popup = SKMainKeyPreview(frame: CGRect(x: left, y: top, width: width, height: keyRect.maxY - top))
        popup.keyFrame = keyRect.offsetBy(dx: -left, dy: -top)
        popup.fillColor = SKMainKeyboardMetrics.keyColor
        popup.textColor = SKMainKeyboardMetrics.textColor
        popup.registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (view: SKMainKeyPreview, _) in
            view.setNeedsDisplay()
        }
        popup.isUserInteractionEnabled = false
        popup.accessibilityIdentifier = "long-vowel.options"
        options = ["ー", keyTitle].enumerated().map { index, text in
            let label = UILabel(frame: CGRect(x: CGFloat(index) * width / 2 + 4, y: 4,
                                              width: width / 2 - 8, height: SKMainKeyPreview.capHeight - 8))
            label.text = text
            label.font = .systemFont(ofSize: 32)
            label.textAlignment = .center
            label.layer.cornerRadius = 7
            label.clipsToBounds = true
            popup.addSubview(label)
            return label
        }
        container.addSubview(popup)
        bubble = popup
    }

    private func updateSelection(at point: CGPoint) {
        guard let bubble else { selectedText = nil; return }
        // Horizontal sliding at the original key's height also selects the
        // option above it; users need not drag their finger up into the popup.
        let inside = bubble.bounds.insetBy(dx: -12, dy: -20).contains(point)
        let index = point.x < bubble.bounds.midX ? 0 : 1
        selectedText = inside ? options[index].text : nil
        for (i, label) in options.enumerated() {
            label.backgroundColor = inside && i == index ? .systemBlue : .clear
            label.textColor = inside && i == index ? .white : SKMainKeyboardMetrics.textColor
        }
    }

    private func dismissAlternatives() {
        bubble?.removeFromSuperview()
        bubble = nil
        options = []
        selectedText = nil
    }
}
