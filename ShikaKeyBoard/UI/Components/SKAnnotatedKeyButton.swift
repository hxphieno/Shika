import UIKit

/// Reuses the normal key's appearance and popup, with optional phonetic hints.
final class SKAnnotatedKeyButton: SKMainKeyButton {
    private let initialInset: CGFloat

    init(letter: String, initial: String?, final: String) {
        initialInset = initial == nil ? 0 : 12
        super.init(title: letter)
        titleLabel?.font = .systemFont(ofSize: 22)
        titleLabel?.textAlignment = .center
        let hint = UILabel()
        hint.text = final
        hint.font = .systemFont(ofSize: 10, weight: .medium)
        hint.textColor = UIColor.secondaryLabel
        hint.textAlignment = .center
        hint.numberOfLines = 2
        hint.adjustsFontSizeToFitWidth = true
        hint.minimumScaleFactor = 0.75
        hint.translatesAutoresizingMaskIntoConstraints = false
        addSubview(hint)
        NSLayoutConstraint.activate([
            hint.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 1),
            hint.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -1),
            hint.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -2),
            hint.heightAnchor.constraint(equalToConstant: 20)
        ])
        hint.text = final.replacingOccurrences(of: " / ", with: "\n")
        if let initial {
            let label = UILabel()
            label.text = initial
            label.font = .systemFont(ofSize: 9, weight: .semibold)
            label.textColor = SKConfig.keyInitialColor
            label.translatesAutoresizingMaskIntoConstraints = false
            addSubview(label)
            NSLayoutConstraint.activate([
                label.topAnchor.constraint(equalTo: topAnchor, constant: 2),
                label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -2)
            ])
        }
        accessibilityLabel = "\(letter)，\(initial.map { "声母\($0)，" } ?? "")韵母\(final)"
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        titleLabel?.frame = CGRect(x: 0, y: 0, width: bounds.width - initialInset, height: 23)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}
