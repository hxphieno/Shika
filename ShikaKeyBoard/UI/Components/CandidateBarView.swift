import UIKit

/// One row of candidates; composition is displayed in the host's marked range.
final class CandidateBarView: UIView {
    var onSelect: ((SKCandidate) -> Void)?
    var onToggleExpanded: (() -> Void)?
    var onRetry: (() -> Void)?
    private let scroll = SKCandidateStripScrollView()
    private let candidates = UIStackView()
    private let expand = SKCandidateDisclosureButton()
    private let disclosureTarget = SKCandidateDisclosureButton()
    var interactionBounds: CGRect? { didSet { if oldValue != interactionBounds { setNeedsLayout() } } }
    private var contentLeading: NSLayoutConstraint!
    private var contentTop: NSLayoutConstraint!
    private var contentBottom: NSLayoutConstraint!
    var hasCandidates: Bool { !visibleCandidates.isEmpty }
    private let message = UILabel()
    private let retry = UIButton(type: .system)
    private var visibleCandidates: [SKCandidate] = []

    override init(frame: CGRect) {
        super.init(frame: frame)
        accessibilityIdentifier = "candidate-bar"
        scroll.showsHorizontalScrollIndicator = false
        scroll.clipsToBounds = true
        scroll.alwaysBounceHorizontal = true
        scroll.isDirectionalLockEnabled = true
        candidates.axis = .horizontal
        candidates.spacing = 0
        expand.accessibilityIdentifier = "candidates.expand"
        expand.tintColor = .label
        expand.acceptsPoint = { [weak self] point in
            guard let self else { return false }
            return !expand.isHidden && fixedDisclosureRegion.contains(expand.convert(point, to: self))
        }
        expand.acceptsTrackingPoint = { [weak self] point in
            guard let self else { return false }
            // Only an existing arrow touch may drift across the border. New
            // touches there still belong to the candidate or keyboard key.
            return !expand.isHidden && fixedDisclosureRegion.insetBy(dx: -8, dy: -8)
                .contains(expand.convert(point, to: self))
        }
        expand.addTarget(self, action: #selector(toggleExpanded), for: .touchUpInside)
        // Blank space keeps native panning, which can cancel its disclosure
        // tap. The fixed arrow is outside the scroll view and owns its touches.
        disclosureTarget.accessibilityIdentifier = "candidates.disclosureTarget"
        disclosureTarget.isAccessibilityElement = false
        disclosureTarget.acceptsPoint = { [weak self] point in
            guard let self else { return false }
            return disclosureContains(disclosureTarget.convert(point, to: self))
        }
        disclosureTarget.onHighlight = { [weak expand] highlighted in expand?.isHighlighted = highlighted }
        disclosureTarget.addTarget(self, action: #selector(toggleExpanded), for: .touchUpInside)
        scroll.addSubview(disclosureTarget)
        message.font = .systemFont(ofSize: 15)
        message.textColor = .secondaryLabel
        message.isHidden = true
        retry.setTitle("重试", for: .normal)
        retry.addTarget(self, action: #selector(retryLoading), for: .touchUpInside)
        retry.isHidden = true
        addSubview(scroll)
        [expand, message, retry].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            addSubview($0)
        }
        candidates.translatesAutoresizingMaskIntoConstraints = false
        scroll.addSubview(candidates)
        contentLeading = candidates.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor)
        contentTop = candidates.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor)
        contentBottom = candidates.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor)
        NSLayoutConstraint.activate([
            // Reserve a wider target so edge taps belong to the chevron,
            // without overlapping candidate buttons or the first keyboard row.
            expand.widthAnchor.constraint(equalToConstant: 72),
            expand.trailingAnchor.constraint(equalTo: trailingAnchor),
            expand.topAnchor.constraint(equalTo: topAnchor),
            expand.bottomAnchor.constraint(equalTo: bottomAnchor),
            contentLeading,
            candidates.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor),
            contentTop,
            contentBottom,
            candidates.heightAnchor.constraint(equalTo: heightAnchor),
            message.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            message.centerYAnchor.constraint(equalTo: centerYAnchor),
            message.trailingAnchor.constraint(lessThanOrEqualTo: expand.leadingAnchor),
            retry.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            retry.centerYAnchor.constraint(equalTo: centerYAnchor),
            retry.widthAnchor.constraint(greaterThanOrEqualToConstant: 44),
            retry.heightAnchor.constraint(equalToConstant: 44)
        ])
        update(SKEngineState())
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private var touchRegion: CGRect { interactionBounds ?? bounds }

    private var fixedDisclosureRegion: CGRect {
        if scroll.isHidden { return touchRegion }
        return CGRect(x: expand.frame.minX, y: touchRegion.minY,
                      width: max(0, touchRegion.maxX - expand.frame.minX), height: touchRegion.height)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let region = touchRegion
        // Enlarge the actual native gesture viewport, while the text remains
        // centered in its original row and clipped before the disclosure icon.
        scroll.frame = region
        contentLeading.constant = max(0, -region.minX)
        contentTop.constant = max(0, -region.minY)
        contentBottom.constant = -max(0, region.maxY - bounds.maxY)
        scroll.contentInset = UIEdgeInsets(top: 0, left: 0, bottom: 0, right: 72)
        scroll.layoutIfNeeded()
    }

    private func candidate(at point: CGPoint) -> UIView? {
        guard !scroll.isHidden, touchRegion.contains(point), point.x < expand.frame.minX else { return nil }
        // Include the row's outer left margin, but never extend into the keys.
        let firstTextX = candidates.convert(candidates.bounds.origin, to: self).x
        let x = max(max(bounds.minX, firstTextX) + 0.5, point.x)
        let inContent = convert(CGPoint(x: x, y: bounds.midY), to: candidates)
        return candidates.arrangedSubviews.first { !$0.isHidden && $0.frame.contains(inContent) }
    }

    private func disclosureContains(_ point: CGPoint) -> Bool {
        guard !expand.isHidden, touchRegion.contains(point) else { return false }
        if !retry.isHidden && retry.frame.contains(point) { return false }
        return candidate(at: point) == nil
    }

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        guard !isHidden, alpha > 0.01, isUserInteractionEnabled, touchRegion.contains(point) else { return nil }
        if disclosureContains(point), fixedDisclosureRegion.contains(point) { return expand }
        if let candidate = candidate(at: point) { return candidate }
        if disclosureContains(point) { return disclosureTarget }
        return super.hitTest(point, with: event)
    }

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
            let button = SKCandidateTouchButton(type: .system)
            button.acceptsPoint = { [weak self, weak button] point in
                guard let self, let button else { return false }
                return self.candidate(at: button.convert(point, to: self)) === button
            }
            var config = UIButton.Configuration.plain()
            config.title = candidate.text
            config.baseForegroundColor = .label
            config.contentInsets = NSDirectionalEdgeInsets(top: 0, leading: 9, bottom: 0, trailing: 9)
            config.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { values in
                var values = values; values.font = UIFont.systemFont(ofSize: 20); return values
            }
            config.titleLineBreakMode = .byClipping
            button.configuration = config
            button.titleLabel?.numberOfLines = 1
            // Configuration titles may otherwise wrap and compress inside the
            // scroll stack. Preserve each word's natural single-line width.
            let textWidth = (candidate.text as NSString).size(withAttributes: [.font: UIFont.systemFont(ofSize: 20)]).width
            button.widthAnchor.constraint(equalToConstant: max(44, ceil(textWidth) + 18)).isActive = true
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

/// Initial hit regions stay separate; the fixed arrow allows slight drift only
/// after it owns the touch, without widening any neighboring initial hit area.
private final class SKCandidateDisclosureButton: UIButton {
    var acceptsPoint: ((CGPoint) -> Bool)?
    var acceptsTrackingPoint: ((CGPoint) -> Bool)?
    var onHighlight: ((Bool) -> Void)?
    override init(frame: CGRect) {
        super.init(frame: frame)
        layer.cornerRadius = 10
        layer.cornerCurve = .continuous
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        if isTracking, let acceptsTrackingPoint { return acceptsTrackingPoint(point) }
        return acceptsPoint?(point) ?? bounds.contains(point)
    }
    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesMoved(touches, with: event)
        if let touch = touches.first, let acceptsTrackingPoint {
            isHighlighted = acceptsTrackingPoint(touch.location(in: self))
        }
    }
    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        // UIButton's native tracking can tolerate much more movement than our
        // point(inside:) region. Enforce the same release boundary as feedback.
        if let touch = touches.first, let acceptsTrackingPoint,
           !acceptsTrackingPoint(touch.location(in: self)) {
            super.touchesCancelled(touches, with: event)
        } else {
            super.touchesEnded(touches, with: event)
        }
    }
    override var isHighlighted: Bool {
        didSet {
            backgroundColor = isHighlighted ? .tertiarySystemFill : .clear
            onHighlight?(isHighlighted)
        }
    }
}

private final class SKCandidateTouchButton: UIButton {
    var acceptsPoint: ((CGPoint) -> Bool)?
    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        acceptsPoint?(point) ?? bounds.contains(point)
    }
}

/// Gives the entire available header to candidate interaction, including stack
/// margins, without changing its visual layout or reaching into the keyboard.
final class SKCandidateInteractionRow: UIStackView {
    weak var candidateBar: CandidateBarView?
    override func layoutSubviews() {
        super.layoutSubviews()
        if let candidateBar { candidateBar.interactionBounds = convert(bounds, to: candidateBar) }
    }
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        guard !isHidden, alpha > 0.01, isUserInteractionEnabled, bounds.contains(point) else { return nil }
        if let candidateBar, candidateBar.hasCandidates {
            return candidateBar.hitTest(convert(point, to: candidateBar), with: event)
        }
        return super.hitTest(point, with: event)
    }
}

/// Native scrolling spans the whole touch header; only its drawing is clipped
/// before the fixed disclosure control. Insets preserve the last word's reach.
private final class SKCandidateStripScrollView: UIScrollView {
    private let viewportMask = CAShapeLayer()
    override init(frame: CGRect) {
        super.init(frame: frame)
        delaysContentTouches = false
        canCancelContentTouches = true
        contentInsetAdjustmentBehavior = .never
        layer.mask = viewportMask
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func touchesShouldCancel(in view: UIView) -> Bool { view is UIControl || super.touchesShouldCancel(in: view) }
    override func layoutSubviews() {
        super.layoutSubviews()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        viewportMask.frame = bounds
        viewportMask.path = UIBezierPath(rect: CGRect(x: 0, y: 0, width: max(0, bounds.width - contentInset.right), height: bounds.height)).cgPath
        CATransaction.commit()
    }
}
