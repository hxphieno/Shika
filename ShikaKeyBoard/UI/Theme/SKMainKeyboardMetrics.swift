import UIKit

/// Measurements from the iOS 26.5 / 402pt system alphabet keyboard.
/// Shared by the alphabet and number/symbol surfaces.
enum SKMainKeyboardMetrics {
    static let portraitHeight: CGFloat = 216
    static let keyHeight: CGFloat = 43
    static let rowPitch: CGFloat = 54
    static let inset: CGFloat = 6.5
    static let gap: CGFloat = 6
    static let cornerRadius: CGFloat = 8
    static let keyColor = UIColor { $0.userInterfaceStyle == .dark
        ? UIColor(white: 61.0 / 255, alpha: 1) : .white }
    static let symbolColor = UIColor { $0.userInterfaceStyle == .dark
        ? UIColor(white: 0.23, alpha: 1) : UIColor(white: 0.83, alpha: 1) }
    static let textColor = UIColor.label

    static func frames(width: CGFloat, height: CGFloat, secondRowCount: Int) -> [[CGRect]] {
        let availableHeight = max(0, height - 11)
        let keyHeight = min(Self.keyHeight, availableHeight / 4 - 8.25)
        let pitch = (availableHeight - keyHeight) / 3
        let keyWidth = (width - 2 * inset - 9 * gap) / 10
        func row(count: Int, y: CGFloat, x: CGFloat) -> [CGRect] {
            (0..<count).map { CGRect(x: x + CGFloat($0) * (keyWidth + gap), y: y, width: keyWidth, height: keyHeight) }
        }
        let first = row(count: 10, y: 6, x: inset)
        let secondInset = secondRowCount == 9 ? inset + (keyWidth + gap) / 2 : inset
        let second = row(count: secondRowCount, y: 6 + pitch, x: secondInset)
        let thirdY = 6 + 2 * pitch
        let letterInset = inset + 1.5 * (keyWidth + gap)
        let functionWidth = (width - 2 * inset) * (45.5 / 389)
        let third = [CGRect(x: inset, y: thirdY, width: functionWidth, height: keyHeight)]
            + row(count: 7, y: thirdY, x: letterInset)
            + [CGRect(x: width - inset - functionWidth, y: thirdY, width: functionWidth, height: keyHeight)]
        let bottomY = 6 + 3 * pitch
        let unit = (width - 2 * inset) * (43.5 / 389)
        let returnWidth = (width - 2 * inset) * (93 / 389)
        let footerWidths = [unit, unit, width - 2 * inset - 3 * gap - 2 * unit - returnWidth, returnWidth]
        var x = inset
        let footer = footerWidths.map { w -> CGRect in
            defer { x += w + gap }
            return CGRect(x: x, y: bottomY, width: w, height: keyHeight)
        }
        return [first, second, third, footer]
    }
}
