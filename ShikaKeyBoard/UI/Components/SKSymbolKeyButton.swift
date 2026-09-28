import UIKit

/// The corner caption describes the writing convention; insertion stays exact.
final class SKSymbolKeyButton: SKMainKeyButton {
    private let badge = UILabel()
    init(symbol: String) {
        super.init(title: symbol)
        usesSymbolTint = true
        badge.text = SKSymbolLayout.badge(for: symbol)
        badge.textColor = .secondaryLabel
        badge.textAlignment = .right
        badge.isUserInteractionEnabled = false
        badge.isAccessibilityElement = false
        badge.isHidden = badge.text == nil
        addSubview(badge)
        accessibilityValue = badge.text.map { $0 == "英" ? "英文标点" : "中日文标点" }
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layoutSubviews() {
        let compact = bounds.height < 38
        titleLabel?.font = .systemFont(ofSize: compact && !badge.isHidden ? 17 : keyTitle.count > 1 ? 20 : 25)
        badge.font = .systemFont(ofSize: compact ? 8 : 9, weight: .medium)
        super.layoutSubviews()
        badge.frame = CGRect(x: 2, y: 2, width: max(0, bounds.width - 5), height: compact ? 9 : 11)
        bringSubviewToFront(badge)
    }
    override func titleRect(forContentRect contentRect: CGRect) -> CGRect {
        let rect = badge.isHidden ? contentRect : contentRect.inset(by: UIEdgeInsets(top: 13, left: 0, bottom: 0, right: 0))
        return super.titleRect(forContentRect: rect)
    }
}
