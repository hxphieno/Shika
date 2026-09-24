import UIKit

final class CandidateBarView: UIView {
    var onSelect: ((SKCandidate) -> Void)?
    var onPage: ((Bool) -> Void)?
    var onCommitRaw: (() -> Void)?
    var onRetry: (() -> Void)?
    private let composition = UILabel()
    private let scroll = UIScrollView()
    private let candidates = UIStackView()
    private let previous = UIButton(type: .system)
    private let nextButton = UIButton(type: .system)
    private let retry = UIButton(type: .system)
    private var visibleCandidates: [SKCandidate] = []

    override init(frame: CGRect) {
        super.init(frame: frame)
        composition.font = .systemFont(ofSize: 13)
        composition.textColor = SKConfig.keyHintColor
        composition.lineBreakMode = .byTruncatingHead
        composition.accessibilityIdentifier = "composition"
        composition.accessibilityTraits = .button
        composition.isUserInteractionEnabled = true
        composition.accessibilityHint = "点按以原样输入字母"
        composition.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(commitRaw)))
        scroll.showsHorizontalScrollIndicator = false
        scroll.clipsToBounds = true
        candidates.axis = .horizontal
        candidates.spacing = 4
        previous.setImage(UIImage(systemName: "chevron.left"), for: .normal)
        nextButton.setImage(UIImage(systemName: "chevron.right"), for: .normal)
        previous.accessibilityLabel = "上一页候选"
        nextButton.accessibilityLabel = "下一页候选"
        previous.addTarget(self, action: #selector(previousPage), for: .touchUpInside)
        nextButton.addTarget(self, action: #selector(nextPage), for: .touchUpInside)
        retry.setTitle("重试", for: .normal)
        retry.addTarget(self, action: #selector(retryLoading), for: .touchUpInside)
        retry.isHidden = true
        [composition, scroll, previous, nextButton, retry].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            addSubview($0)
        }
        candidates.translatesAutoresizingMaskIntoConstraints = false
        scroll.addSubview(candidates)
        NSLayoutConstraint.activate([
            composition.topAnchor.constraint(equalTo: topAnchor, constant: 2),
            composition.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 6),
            composition.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -45),
            composition.heightAnchor.constraint(equalToConstant: 19),
            scroll.topAnchor.constraint(equalTo: composition.bottomAnchor),
            scroll.leadingAnchor.constraint(equalTo: leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: previous.leadingAnchor),
            scroll.bottomAnchor.constraint(equalTo: bottomAnchor),
            previous.widthAnchor.constraint(equalToConstant: 26),
            nextButton.widthAnchor.constraint(equalToConstant: 26),
            previous.trailingAnchor.constraint(equalTo: nextButton.leadingAnchor),
            nextButton.trailingAnchor.constraint(equalTo: trailingAnchor),
            previous.topAnchor.constraint(equalTo: scroll.topAnchor),
            nextButton.topAnchor.constraint(equalTo: scroll.topAnchor),
            previous.bottomAnchor.constraint(equalTo: bottomAnchor),
            nextButton.bottomAnchor.constraint(equalTo: bottomAnchor),
            candidates.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor),
            candidates.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor),
            candidates.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor),
            candidates.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor),
            candidates.heightAnchor.constraint(equalTo: scroll.frameLayoutGuide.heightAnchor),
            retry.trailingAnchor.constraint(equalTo: trailingAnchor),
            retry.topAnchor.constraint(equalTo: topAnchor)
        ])
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func update(_ state: SKEngineState) {
        retry.isHidden = true
        composition.text = state.preedit
        visibleCandidates = state.candidates
        candidates.arrangedSubviews.forEach { $0.removeFromSuperview() }
        for candidate in state.candidates {
            let button = UIButton(type: .system)
            button.setTitle(candidate.text, for: .normal)
            button.setTitleColor(SKConfig.keyTitleColor, for: .normal)
            button.titleLabel?.font = .systemFont(ofSize: 20)
            button.contentEdgeInsets = UIEdgeInsets(top: 0, left: 9, bottom: 0, right: 9)
            button.tag = candidate.index
            button.accessibilityIdentifier = "candidate.\(candidate.index)"
            button.accessibilityLabel = candidate.text
            button.addTarget(self, action: #selector(selectCandidate(_:)), for: .touchUpInside)
            candidates.addArrangedSubview(button)
        }
        scroll.setContentOffset(.zero, animated: false)
        previous.isEnabled = state.page > 0
        nextButton.isEnabled = !state.candidates.isEmpty && !state.isLastPage
    }

    func showError() {
        update(SKEngineState())
        composition.text = "词库加载失败"
        retry.isHidden = false
    }
    @objc private func selectCandidate(_ sender: UIButton) {
        guard let candidate = visibleCandidates.first(where: { $0.index == sender.tag }) else { return }
        onSelect?(candidate)
    }
    @objc private func previousPage() { onPage?(true) }
    @objc private func nextPage() { onPage?(false) }
    @objc private func commitRaw() { onCommitRaw?() }
    @objc private func retryLoading() { onRetry?() }
}
