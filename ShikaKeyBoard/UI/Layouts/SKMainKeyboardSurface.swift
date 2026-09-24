import UIKit

/// Geometry shared by the independent Chinese/Japanese and double-pinyin keyboards.
class SKMainKeyboardSurface: UIView {
    var keyRows: [[SKMainKeyButton]] = [] {
        didSet {
            oldValue.flatMap { $0 }.filter { key in !keyRows.flatMap { $0 }.contains(where: { $0 === key }) }.forEach { $0.removeFromSuperview() }
            keyRows.flatMap { $0 }.forEach { if $0.superview !== self { addSubview($0) } }
            setNeedsLayout()
        }
    }
    var footer: SKKeyboardFooterView? {
        didSet { oldValue?.removeFromSuperview(); if let footer { addSubview(footer) }; setNeedsLayout() }
    }
    override var intrinsicContentSize: CGSize { CGSize(width: UIView.noIntrinsicMetric, height: SKMainKeyboardMetrics.portraitHeight) }
    override func layoutSubviews() {
        super.layoutSubviews()
        guard keyRows.count == 3 else { return }
        let frames = SKMainKeyboardMetrics.frames(width: bounds.width, height: bounds.height, secondRowCount: keyRows[1].count)
        for (keys, rowFrames) in zip(keyRows, frames) {
            for (key, rect) in zip(keys, rowFrames) { key.frame = rect }
        }
        footer?.frame = bounds
        footer?.keyFrames = frames[3]
        footer?.setNeedsLayout()
        footer?.layoutIfNeeded()
        let allRows = keyRows + [footer?.subviews.compactMap { $0 as? SKMainKeyButton } ?? []]
        // Partition only the invisible gutters, halfway between neighboring key
        // edges. The resulting non-overlapping cells tile the main keyboard.
        for (rowIndex, row) in allRows.enumerated() where !row.isEmpty {
            let rowFrames = frames[rowIndex]
            let top: CGFloat = rowIndex == 0 ? 0 : (frames[rowIndex - 1][0].maxY + rowFrames[0].minY) / 2
            let bottom = rowIndex == allRows.count - 1 ? bounds.height : (rowFrames[0].maxY + frames[rowIndex + 1][0].minY) / 2
            for (column, key) in row.enumerated() {
                let rect = rowFrames[column]
                let left: CGFloat = column == 0 ? 0 : (rowFrames[column - 1].maxX + rect.minX) / 2
                let right = column == row.count - 1 ? bounds.width : (rect.maxX + rowFrames[column + 1].minX) / 2
                key.touchBounds = CGRect(x: left - rect.minX, y: top - rect.minY, width: right - left, height: bottom - top)
            }
        }
    }
}
