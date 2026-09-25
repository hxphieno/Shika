import UIKit

/// A virtualized, vertically scrolling candidate grid over the alphabet keyboard.
final class SKExpandedCandidatesView: UIView, UICollectionViewDataSource, UICollectionViewDelegateFlowLayout {
    var onSelect: ((SKCandidate) -> Void)?
    var onLoadMore: (() -> Void)?
    private let collection: UICollectionView
    private var candidates: [SKCandidate] = []
    private var hasMore = false
    private var previousWidth: CGFloat = 0

    override init(frame: CGRect) {
        let layout = UICollectionViewFlowLayout()
        layout.minimumInteritemSpacing = 0
        layout.minimumLineSpacing = 0
        collection = UICollectionView(frame: .zero, collectionViewLayout: layout)
        super.init(frame: frame)
        accessibilityIdentifier = "candidates.expanded"
        collection.backgroundColor = .clear
        collection.alwaysBounceVertical = true
        collection.dataSource = self
        collection.delegate = self
        collection.register(CandidateCell.self, forCellWithReuseIdentifier: "candidate")
        addSubview(collection)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func layoutSubviews() {
        super.layoutSubviews()
        collection.frame = bounds
        if previousWidth != bounds.width {
            previousWidth = bounds.width
            collection.collectionViewLayout.invalidateLayout()
        }
    }
    func update(_ state: SKEngineState, resetScroll: Bool = false) {
        candidates = state.candidates
        hasMore = !state.isLastPage
        collection.reloadData()
        if resetScroll { collection.setContentOffset(.zero, animated: false) }
    }
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int { candidates.count }
    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "candidate", for: indexPath) as! CandidateCell
        let candidate = candidates[indexPath.item]
        cell.label.text = candidate.text
        cell.accessibilityLabel = candidate.text
        cell.accessibilityIdentifier = "expanded-candidate.\(candidate.index)"
        return cell
    }
    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        onSelect?(candidates[indexPath.item])
    }
    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> CGSize {
        let width = collectionView.bounds.width
        let textWidth = (candidates[indexPath.item].text as NSString).size(withAttributes: [.font: UIFont.systemFont(ofSize: 20)]).width
        let scale = max(1, traitCollection.displayScale)
        // Flow layout rounds origins to physical pixels. Round widths down too
        // so the last column never extends beyond the viewport by half a pixel.
        let unit = max(1, floor(width / 4 * scale) / scale)
        return CGSize(width: min(width, max(unit, ceil((textWidth + 24) / unit) * unit)), height: 44)
    }
    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        guard !isHidden, hasMore, scrollView.contentSize.height > 0,
              scrollView.contentOffset.y + scrollView.bounds.height > scrollView.contentSize.height - 88 else { return }
        hasMore = false
        onLoadMore?()
    }
}

private final class CandidateCell: UICollectionViewCell {
    let label = UILabel()
    private let separator = UIView()
    override init(frame: CGRect) {
        super.init(frame: frame)
        label.font = .systemFont(ofSize: 20)
        label.textAlignment = .center
        label.textColor = .label
        separator.backgroundColor = .separator
        contentView.addSubview(label)
        contentView.addSubview(separator)
        isAccessibilityElement = true
        accessibilityTraits = .button
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override var isHighlighted: Bool {
        didSet { contentView.backgroundColor = isHighlighted ? .tertiarySystemFill : .clear }
    }
    override func layoutSubviews() {
        super.layoutSubviews()
        label.frame = contentView.bounds.insetBy(dx: 8, dy: 0)
        separator.frame = CGRect(x: bounds.width - 0.5, y: 12, width: 0.5, height: bounds.height - 24)
    }
}
