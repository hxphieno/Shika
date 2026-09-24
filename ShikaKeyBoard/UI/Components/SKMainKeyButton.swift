import UIKit
import CoreText

/// iOS 26 main-keyboard key. The legacy key classes still serve the custom number page.
class SKMainKeyButton: UIButton {
    enum Role { case letter, function, space }
    private let letterFont = UIFont.systemFont(ofSize: 25)
    let keyRole: Role
    var keyTitle: String { didSet { setTitle(keyTitle, for: .normal) } }
    private var preview: SKMainKeyPreview?
    private var repeatTimer: Timer?
    var touchBounds: CGRect?
    var onPress: (() -> Void)?
    var onRepeat: (() -> Void)?

    init(title: String, role: Role = .letter) {
        keyTitle = title
        self.keyRole = role
        super.init(frame: .zero)
        setTitle(title, for: .normal)
        titleLabel?.font = role == .letter ? letterFont : .systemFont(ofSize: 18)
        setTitleColor(SKMainKeyboardMetrics.textColor, for: .normal)
        layer.cornerRadius = SKMainKeyboardMetrics.cornerRadius
        layer.cornerCurve = .continuous
        isExclusiveTouch = false
        accessibilityLabel = title
        addTarget(self, action: #selector(pressBegan), for: .touchDown)
        addTarget(self, action: #selector(pressEnded), for: [.touchUpInside, .touchUpOutside, .touchCancel, .touchDragExit])
        addTarget(self, action: #selector(pressBegan), for: .touchDragEnter)
        updateAppearance()
        registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (self: SKMainKeyButton, _) in self.updateAppearance() }
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func titleRect(forContentRect contentRect: CGRect) -> CGRect {
        let rect = super.titleRect(forContentRect: contentRect)
        guard keyRole == .letter else { return rect }
        return rect.offsetBy(dx: Self.opticalOffset(for: keyTitle, font: letterFont), dy: -8.0 / 3)
    }

    fileprivate static func opticalOffset(for text: String, font: UIFont) -> CGFloat {
        guard let scalar = text.utf16.first, text.utf16.count == 1 else { return 0 }
        var character = scalar, glyph: CGGlyph = 0
        let ctFont = font as CTFont
        guard CTFontGetGlyphsForCharacters(ctFont, &character, &glyph, 1) else { return 0 }
        var advance = CGSize.zero
        CTFontGetAdvancesForGlyphs(ctFont, .horizontal, &glyph, &advance, 1)
        let ink = CTFontGetBoundingRectsForGlyphs(ctFont, .horizontal, &glyph, nil, 1)
        return (advance.width - ink.width) / 2 - ink.minX
    }

    // UIKit tracking must agree with hit testing for presses in visual gutters.
    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        touchBounds?.contains(point) ?? super.point(inside: point, with: event)
    }

    override func accessibilityActivate() -> Bool {
        // VoiceOver activates controls without a touchDown/touchUp sequence.
        if let onPress { onPress(); return true }
        return super.accessibilityActivate()
    }

    override var isHighlighted: Bool { didSet { updateAppearance() } }
    private func updateAppearance() {
        let base = SKMainKeyboardMetrics.keyColor.resolvedColor(with: traitCollection)
        backgroundColor = isHighlighted && keyRole != .letter
            ? (traitCollection.userInterfaceStyle == .dark ? UIColor(white: 0.42, alpha: 1) : UIColor(white: 0.81, alpha: 1)) : base
    }

    func useSymbol(_ name: String, label: String) {
        setTitle(nil, for: .normal)
        setImage(UIImage(systemName: name, withConfiguration: UIImage.SymbolConfiguration(pointSize: 20, weight: .regular)), for: .normal)
        tintColor = SKMainKeyboardMetrics.textColor
        accessibilityLabel = label
    }

    @objc private func pressBegan() {
        onPress?()
        if keyRole == .letter { showPreview() }
        if onRepeat != nil && repeatTimer == nil {
            repeatTimer = Timer.scheduledTimer(withTimeInterval: 0.45, repeats: false) { [weak self] _ in
                guard let self else { return }
                onRepeat?()
                repeatTimer = Timer.scheduledTimer(withTimeInterval: 0.085, repeats: true) { [weak self] _ in self?.onRepeat?() }
                if let repeatTimer { RunLoop.main.add(repeatTimer, forMode: .common) }
            }
            if let repeatTimer { RunLoop.main.add(repeatTimer, forMode: .common) }
        }
    }
    @objc private func pressEnded() {
        preview?.removeFromSuperview()
        preview = nil
        repeatTimer?.invalidate()
        repeatTimer = nil
    }
    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window == nil { pressEnded() }
    }
    private func showPreview() {
        guard preview == nil, let window else { return }
        let keyRect = convert(bounds, to: window)
        var width = max(54, bounds.width + 24)
        if keyRect.minX <= SKMainKeyboardMetrics.inset + 0.5 { width = min(width, 55.5) }
        if keyRect.maxX >= window.bounds.width - SKMainKeyboardMetrics.inset - 0.5 { width = min(width, 54) }
        let height = bounds.height + 67
        let left = max(SKMainKeyboardMetrics.inset, min(keyRect.midX - width / 2, window.bounds.width - width - SKMainKeyboardMetrics.inset))
        let bubble = SKMainKeyPreview(frame: CGRect(x: left, y: keyRect.maxY - height, width: width, height: height))
        bubble.keyFrame = CGRect(x: keyRect.minX - left, y: height - bounds.height, width: bounds.width, height: bounds.height)
        bubble.fillColor = SKMainKeyboardMetrics.keyColor.resolvedColor(with: traitCollection)
        bubble.textColor = SKMainKeyboardMetrics.textColor.resolvedColor(with: traitCollection)
        bubble.letter = keyTitle
        bubble.isUserInteractionEnabled = false
        window.addSubview(bubble)
        preview = bubble
    }
}

private final class SKMainKeyPreview: UIView {
    var keyFrame = CGRect.zero
    var fillColor = UIColor.white
    var textColor = UIColor.black
    var letter = ""
    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        layer.shadowOpacity = 0.12
        layer.shadowRadius = 1
        layer.shadowOffset = CGSize(width: 0, height: 2)
        accessibilityIdentifier = "main-key-preview"
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func draw(_ rect: CGRect) {
        // The native preview joins its tall cap to the key in one continuous
        // contour. Edge keys keep the outside edge aligned with the keycap.
        let width = bounds.width, bottom = bounds.height
        let radius: CGFloat = 10, keyRadius = SKMainKeyboardMetrics.cornerRadius
        let shoulder: CGFloat = 51, neckBottom = keyFrame.minY + 7
        let path = UIBezierPath()
        path.move(to: CGPoint(x: radius, y: 0))
        path.addLine(to: CGPoint(x: width - radius, y: 0))
        path.addQuadCurve(to: CGPoint(x: width, y: radius), controlPoint: CGPoint(x: width, y: 0))
        path.addLine(to: CGPoint(x: width, y: shoulder))
        path.addCurve(to: CGPoint(x: keyFrame.maxX, y: neckBottom),
                      controlPoint1: CGPoint(x: width, y: shoulder + 9),
                      controlPoint2: CGPoint(x: keyFrame.maxX, y: neckBottom - 10))
        path.addLine(to: CGPoint(x: keyFrame.maxX, y: bottom - keyRadius))
        path.addQuadCurve(to: CGPoint(x: keyFrame.maxX - keyRadius, y: bottom), controlPoint: CGPoint(x: keyFrame.maxX, y: bottom))
        path.addLine(to: CGPoint(x: keyFrame.minX + keyRadius, y: bottom))
        path.addQuadCurve(to: CGPoint(x: keyFrame.minX, y: bottom - keyRadius), controlPoint: CGPoint(x: keyFrame.minX, y: bottom))
        path.addLine(to: CGPoint(x: keyFrame.minX, y: neckBottom))
        path.addCurve(to: CGPoint(x: 0, y: shoulder),
                      controlPoint1: CGPoint(x: keyFrame.minX, y: neckBottom - 10),
                      controlPoint2: CGPoint(x: 0, y: shoulder + 9))
        path.addLine(to: CGPoint(x: 0, y: radius))
        path.addQuadCurve(to: CGPoint(x: radius, y: 0), controlPoint: .zero)
        path.close()
        fillColor.setFill()
        path.fill()
        let font = UIFont.systemFont(ofSize: 37)
        let size = (letter as NSString).size(withAttributes: [.font: font])
        (letter as NSString).draw(at: CGPoint(x: (bounds.width - size.width) / 2 + SKMainKeyButton.opticalOffset(for: letter, font: font), y: 12), withAttributes: [.font: font, .foregroundColor: textColor])
    }
}
