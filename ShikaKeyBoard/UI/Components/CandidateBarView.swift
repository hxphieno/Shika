import UIKit

/// One row of candidates; composition is displayed in the host's marked range.
final class CandidateBarView: UIView {
    var onSelect: ((SKCandidate) -> Void)?
    var onToggleExpanded: (() -> Void)?
    var onRetry: (() -> Void)?
    private let scroll = UIScrollView()
    private let candidates = UIStackView()
    private let expand = UIButton(type: .system)
    private let message = UILabel()
    private let retry = UIButton(type: .system)
    private var visibleCandidates: [SKCandidate] = []

    override init(frame: CGRect) {
        super.init(frame: frame)
        accessibilityIdentifier = "candidate-bar"
        scroll.showsHorizontalScrollIndicator = false
        scroll.clipsToBounds = true
        candidates.axis = .horizontal
        candidates.spacing = 4
        expand.accessibilityIdentifier = "candidates.expand"
        expand.tintColor = .label
        expand.addTarget(self, action: #selector(toggleExpanded), for: .touchUpInside)
        message.font = .systemFont(ofSize: 15)
        message.textColor = .secondaryLabel
        message.isHidden = true
        retry.setTitle("重试", for: .normal)
        retry.addTarget(self, action: #selector(retryLoading), for: .touchUpInside)
        retry.isHidden = true
        [scroll, expand, message, retry].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            addSubview($0)
        }
        candidates.translatesAutoresizingMaskIntoConstraints = false
        scroll.addSubview(candidates)
        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: topAnchor),
            scroll.leadingAnchor.constraint(equalTo: leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: expand.leadingAnchor),
            scroll.bottomAnchor.constraint(equalTo: bottomAnchor),
            expand.widthAnchor.constraint(equalToConstant: 44),
            expand.trailingAnchor.constraint(equalTo: trailingAnchor),
            expand.topAnchor.constraint(equalTo: topAnchor),
            expand.bottomAnchor.constraint(equalTo: bottomAnchor),
            candidates.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor),
            candidates.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor),
            candidates.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor),
            candidates.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor),
            candidates.heightAnchor.constraint(equalTo: scroll.frameLayoutGuide.heightAnchor),
            message.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            message.centerYAnchor.constraint(equalTo: centerYAnchor),
            message.trailingAnchor.constraint(lessThanOrEqualTo: expand.leadingAnchor),
            retry.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            retry.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
        update(SKEngineState())
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func update(_ state: SKEngineState, expanded: Bool = false) {
        retry.isHidden = true
        message.text = expanded ? "全部候选" : nil
        message.isHidden = !expanded
        scroll.isHidden = expanded
        expand.isHidden = state.candidates.isEmpty
        expand.setImage(UIImage(systemName: expanded ? "chevron.up" : "chevron.down"), for: .normal)
        expand.accessibilityLabel = expanded ? "收起候选" : "展开候选"
        guard visibleCandidates != state.candidates else { return }
        visibleCandidates = state.candidates
        candidates.arrangedSubviews.forEach { $0.removeFromSuperview() }
        for candidate in state.candidates {
            let button = UIButton(type: .system)
            var config = UIButton.Configuration.plain()
            config.title = candidate.text
            config.baseForegroundColor = .label
            config.contentInsets = NSDirectionalEdgeInsets(top: 0, leading: 9, bottom: 0, trailing: 9)
            config.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { values in
                var values = values; values.font = UIFont.systemFont(ofSize: 20); return values
            }
            button.configuration = config
            button.tag = candidate.index
            button.accessibilityIdentifier = "candidate.\(candidate.index)"
            button.accessibilityLabel = candidate.text
            button.addTarget(self, action: #selector(selectCandidate(_:)), for: .touchUpInside)
            candidates.addArrangedSubview(button)
        }
        scroll.setContentOffset(.zero, animated: false)
    }

    func showError() {
        update(SKEngineState())
        message.text = "词库加载失败"
        message.isHidden = false
        retry.isHidden = false
    }
    @objc private func selectCandidate(_ sender: UIButton) {
        guard let candidate = visibleCandidates.first(where: { $0.index == sender.tag }) else { return }
        onSelect?(candidate)
    }
    @objc private func toggleExpanded() { onToggleExpanded?() }
    @objc private func retryLoading() { onRetry?() }
}
