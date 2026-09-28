import UIKit

/// Keeps the numeric pad and horizontally scrolling symbol columns, using the
/// same keycaps, row geometry and interactions as the alphabet keyboards.
final class SKNumberInputView: UIView {
    weak var eventHandler: SKKeyboardEventHandler?
    private var numberButtons: [SKMainKeyButton] = []
    private var symbolButtons: [SKMainKeyButton] = []
    private let symbolScrollView = SKKeyboardScrollView()
    private let symbolContent = UIView()
    private let symbolMemory = SKSymbolMemory()

    override init(frame: CGRect) {
        super.init(frame: frame)
        for title in (1...9).map(String.init) + ["返回", "0", "⌫"] {
            let isFunction = title == "返回" || title == "⌫"
            let key = SKMainKeyButton(title: title, role: isFunction ? .function : .letter)
            key.accessibilityIdentifier = "number.\(title)"
            if title == "返回" {
                key.addTarget(self, action: #selector(returnToAlpha), for: .touchUpInside)
            } else if title == "⌫" {
                key.useSymbol("delete.left", label: "删除")
                key.onDelete = { [weak self] byWord in
                    self?.eventHandler?.didDeleteBackward(byWord: byWord) ?? .stop
                }
            } else {
                key.addTarget(self, action: #selector(typeKey(_:)), for: .touchUpInside)
            }
            numberButtons.append(key)
            addSubview(key)
        }
        symbolScrollView.showsHorizontalScrollIndicator = false
        symbolScrollView.alwaysBounceHorizontal = true
        symbolScrollView.clipsToBounds = true
        symbolScrollView.addSubview(symbolContent)
        addSubview(symbolScrollView)
        for (index, title) in SKSymbolLayout.punctuation.enumerated() {
            let key = SKSymbolKeyButton(symbol: title)
            key.accessibilityIdentifier = "symbol.\(index)"
            key.addTarget(self, action: #selector(typeKey(_:)), for: .touchUpInside)
            symbolButtons.append(key)
            symbolContent.addSubview(key)
        }
        refreshSymbolOrder()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override var intrinsicContentSize: CGSize {
        CGSize(width: UIView.noIntrinsicMetric, height: SKMainKeyboardMetrics.portraitHeight)
    }

    override var isHidden: Bool {
        didSet {
            if isHidden { (numberButtons + symbolButtons).forEach { $0.cancelPreview() } }
            else if oldValue { refreshSymbolOrder() }
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let inset = SKMainKeyboardMetrics.inset, gap = SKMainKeyboardMetrics.gap
        let rows = SKMainKeyboardMetrics.frames(width: bounds.width, height: bounds.height, secondRowCount: 9)
        let numberWidth = min(60, ((bounds.width - 2 * inset - gap) * 0.46 - 2 * gap) / 3)
        let split = inset + 3 * numberWidth + 2.5 * gap
        for (index, key) in numberButtons.enumerated() {
            let row = index / 3, column = index % 3
            let y = rows[row][0].minY, height = rows[row][0].height
            key.frame = CGRect(x: inset + CGFloat(column) * (numberWidth + gap), y: y, width: numberWidth, height: height)
            let left = column == 0 ? 0 : key.frame.minX - gap / 2
            let right = column == 2 ? split : key.frame.maxX + gap / 2
            let top = row == 0 ? 0 : (rows[row - 1][0].maxY + y) / 2
            let bottom = row == 3 ? bounds.height : (key.frame.maxY + rows[row + 1][0].minY) / 2
            key.touchBounds = CGRect(x: left - key.frame.minX, y: top - y, width: right - left, height: bottom - top)
        }
        symbolScrollView.frame = CGRect(x: split, y: 0, width: max(0, bounds.width - split), height: bounds.height)
        let symbolWidth = min(48, max(24, (symbolScrollView.bounds.width - inset - 3.5 * gap) / 4))
        let columnCount = (symbolButtons.count + 3) / 4
        let contentWidth = gap / 2 + CGFloat(columnCount) * (symbolWidth + gap) - gap + inset
        symbolContent.frame = CGRect(x: 0, y: 0, width: contentWidth, height: bounds.height)
        symbolScrollView.contentSize = symbolContent.bounds.size
        for (index, key) in symbolButtons.enumerated() {
            let row = index % 4, column = index / 4
            let y = rows[row][0].minY, height = rows[row][0].height
            key.frame = CGRect(x: gap / 2 + CGFloat(column) * (symbolWidth + gap), y: y, width: symbolWidth, height: height)
            let top = row == 0 ? 0 : (rows[row - 1][0].maxY + y) / 2
            let bottom = row == 3 ? bounds.height : (key.frame.maxY + rows[row + 1][0].minY) / 2
            let right = column == columnCount - 1 ? contentWidth : key.frame.maxX + gap / 2
            key.touchBounds = CGRect(x: -gap / 2, y: top - y, width: right - key.frame.minX + gap / 2, height: bottom - top)
        }
        let maxOffset = max(0, contentWidth - symbolScrollView.bounds.width)
        if !symbolScrollView.isDragging && !symbolScrollView.isDecelerating {
            symbolScrollView.contentOffset.x = min(maxOffset, max(0, symbolScrollView.contentOffset.x))
        }
    }

    // Keep the symbol viewport clipped; enlarged symbol targets cannot steal
    // numeric taps. Returning the actual key lets UIKit track the whole cell.
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        guard !isHidden, alpha > 0.01, isUserInteractionEnabled, bounds.contains(point) else { return nil }
        return super.hitTest(point, with: event)
    }
    private func refreshSymbolOrder() {
        let order = symbolMemory.orderedSymbols()
        let positions = Dictionary(uniqueKeysWithValues: order.enumerated().map { ($0.element, $0.offset) })
        symbolButtons.sort { positions[$0.keyTitle, default: 0] < positions[$1.keyTitle, default: 0] }
        symbolScrollView.contentOffset = .zero
        setNeedsLayout()
    }
    @objc private func typeKey(_ key: SKMainKeyButton) {
        if key.usesSymbolTint { symbolMemory.record(key.keyTitle) }
        eventHandler?.didTapKey(key.keyTitle)
    }
    @objc private func returnToAlpha() { eventHandler?.didTapSwitchLayout(to: .alphabet) }
}
