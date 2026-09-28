import UIKit

private final class NumberRecorder: SKKeyboardEventHandler {
    var text = ""
    var deletes = 0
    var returned = false
    func didTapKey(_ key: String) { text += key }
    func didTapDelete() { deletes += 1 }
    func didTapSwitchScheme() {}
    func didTapNextKeyboard() {}
    func didTapSwitchLayout(to layout: SKKeyboardLayoutType) { returned = layout == .alphabet }
}
private func descendants(_ view: UIView) -> [UIView] { [view] + view.subviews.flatMap(descendants) }
private func tap(_ key: UIControl) { key.sendActions(for: .touchDown); key.sendActions(for: .touchUpInside) }

@MainActor
final class NumberAndEdgeApp: UIResponder, UIApplicationDelegate {
    var window: UIWindow?
    var failures: [String] = []
    var count = 0
    func expect(_ value: Bool, _ description: String) {
        count += 1
        if !value { failures.append(description) }
    }
    func wait(_ seconds: Double) async { try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000)) }
    func application(_ application: UIApplication, didFinishLaunchingWithOptions options: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        let window = UIWindow(frame: UIScreen.main.bounds)
        window.rootViewController = UIViewController()
        window.makeKeyAndVisible()
        self.window = window
        Task { await run(window.rootViewController!.view) }
        return true
    }
    func run(_ host: UIView) async {
        let output = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let recorder = NumberRecorder()
        let container = UIView(frame: CGRect(x: 0, y: 100, width: 402, height: 276))
        container.clipsToBounds = true
        host.addSubview(container)
        let numbers = SKNumberInputView()
        numbers.eventHandler = recorder
        container.addSubview(numbers)
        let scroll = descendants(numbers).compactMap { $0 as? UIScrollView }.first!
        let keys = descendants(numbers).compactMap { $0 as? SKMainKeyButton }
        expect(keys.count == 12 + SKSymbolLayout.punctuation.count, "All numeric/function keys and symbols use shared keycaps")
        expect(descendants(numbers).allSatisfy { !($0 is SKIMKeyButtonWithoutPopUpView) }, "No legacy keycaps remain in numeric UI")
        expect(Set(keys.filter { $0.accessibilityIdentifier?.hasPrefix("symbol.") == true }.map(\.keyTitle)) == Set(SKSymbolLayout.punctuation), "Symbol inventory unchanged")

        for style: UIUserInterfaceStyle in [.light, .dark] {
            container.overrideUserInterfaceStyle = style
            for (width, height) in [(320.0,216.0), (390,216), (402,216), (430,216), (874,162)] {
                container.frame.size = CGSize(width: width, height: height + 60)
                numbers.frame = CGRect(x: 0, y: 60, width: width, height: height)
                numbers.setNeedsLayout(); numbers.layoutIfNeeded()
                let rows = SKMainKeyboardMetrics.frames(width: width, height: height, secondRowCount: 9)
                for digit in 0...9 {
                    let key = keys.first { $0.keyTitle == String(digit) }!
                    let rect = key.convert(key.bounds, to: numbers)
                    expect(rect.height == rows[0][0].height && numbers.bounds.contains(rect), "Numeric geometry fits \(width) / \(style.rawValue) / \(digit)")
                    expect(key.layer.cornerRadius == SKMainKeyboardMetrics.cornerRadius, "Shared rounded keycap")
                    let center = CGPoint(x: rect.midX, y: rect.midY)
                    expect(numbers.hitTest(center, with: nil) === key, "Numeric center routes correctly")
                }
                // Sample the whole fixed pad including all outer margins/gutters.
                for y in stride(from: 1.0, to: height, by: 13) {
                    for x in stride(from: 1.0, to: scroll.frame.minX, by: 11) {
                        expect(numbers.hitTest(CGPoint(x: x, y: y), with: nil) is SKMainKeyButton, "No numeric dead zone at \(x),\(y), width \(width)")
                    }
                }
                for offset in [0.0, max(0, scroll.contentSize.width - scroll.bounds.width)] {
                    scroll.contentOffset.x = offset
                    let viewport = scroll.convert(scroll.bounds, to: numbers)
                    for key in keys where key.accessibilityIdentifier?.hasPrefix("symbol.") == true {
                        let rect = key.convert(key.bounds, to: numbers)
                        let center = CGPoint(x: rect.midX, y: rect.midY)
                        if viewport.contains(center) {
                            expect(numbers.hitTest(center, with: nil) === key, "Scrolled symbol center belongs to visible symbol")
                        }
                    }
                    let lastDigit = keys.first { $0.keyTitle == "3" }!
                    let center = lastDigit.convert(CGPoint(x: lastDigit.bounds.midX, y: lastDigit.bounds.midY), to: numbers)
                    expect(numbers.hitTest(center, with: nil) === lastDigit, "Scrolled symbols never steal numeric touches")
                }
                scroll.contentOffset = .zero
                numbers.backgroundColor = style == .dark ? UIColor(white: 0.09, alpha: 1) : UIColor(white: 0.88, alpha: 1)
                if width == 402 || width == 874 {
                    let image = UIGraphicsImageRenderer(bounds: numbers.bounds).image { numbers.layer.render(in: $0.cgContext) }
                    try? image.pngData()?.write(to: output.appendingPathComponent("numbers-\(Int(width))-\(style.rawValue).png"))
                }
            }
        }
        container.frame.size = CGSize(width: 402, height: 276)
        numbers.frame = CGRect(x: 0, y: 60, width: 402, height: 216)
        numbers.setNeedsLayout(); numbers.layoutIfNeeded()
        for title in ["1", "2", "0", "，", "……", "\\", "——"] {
            let key = keys.first { $0.keyTitle == title }!
            tap(key)
        }
        expect(recorder.text == "120，……\\——", "Numbers and multi-character symbols insert unchanged, exactly once")
        let deletion = keys.first { $0.accessibilityLabel == "删除" }!
        deletion.sendActions(for: .touchDown)
        await wait(0.62)
        deletion.sendActions(for: .touchUpInside)
        let deleted = recorder.deletes
        expect(deleted >= 3, "Numeric delete supports hold repeat")
        await wait(0.18)
        expect(recorder.deletes == deleted, "Delete stops on release")
        tap(keys.first { $0.keyTitle == "返回" }!)
        expect(recorder.returned, "Return restores alphabet layout event")
        let symbol = keys.first { $0.keyTitle == "，" }!
        symbol.sendActions(for: .touchDown)
        expect(descendants(container).contains { $0 is SKMainKeyPreview }, "Symbol preview escapes scroll clipping into keyboard root")
        symbol.sendActions(for: .touchCancel)
        expect(!descendants(container).contains { $0 is SKMainKeyPreview }, "Scroll cancellation removes symbol preview immediately")
        expect(scroll.touchesShouldCancel(in: symbol), "Symbol swipe can cancel a key press")
        numbers.isHidden = true

        let full = SKChineseJapaneseKeyboardView(), double = SKShuangpinKeyboardView()
        for surface in [full, double] as [SKMainKeyboardSurface] {
            container.addSubview(surface)
            for width in [320.0, 402, 430, 874] {
                let height = width > 600 ? 162.0 : 216.0
                container.frame.size = CGSize(width: width, height: height + 60)
                surface.frame = CGRect(x: 0, y: 60, width: width, height: height)
                surface.layoutIfNeeded()
                for index in [0, 9] {
                    let key = surface.keyRows[0][index]
                    for point in [CGPoint(x: index == 0 ? 0.5 : width - 0.5, y: 1), CGPoint(x: key.frame.midX, y: key.frame.midY)] {
                        expect(surface.hitTest(point, with: nil) === key, "Q/P outer edge and center route to same key at \(width)")
                        expect(key.point(inside: key.convert(point, from: surface), with: nil), "Tracking accepts expanded edge target")
                        // Reproduce a complete tap within a single render cycle.
                        tap(key)
                        expect(descendants(container).contains { $0 is SKMainKeyPreview }, "Rapid edge tap retains preview through release")
                        await wait(0.025)
                        if let preview = descendants(container).first(where: { $0 is SKMainKeyPreview }) {
                            expect(container.bounds.contains(preview.frame), "Edge preview remains within extension bounds")
                        } else { expect(false, "Rapid preview survives until a rendered frame") }
                        await wait(0.14)
                        expect(!descendants(container).contains { $0 is SKMainKeyPreview }, "Released preview expires")
                    }
                }
            }
            let q = surface.keyRows[0][0], p = surface.keyRows[0][9]
            tap(q); p.sendActions(for: .touchDown)
            expect(descendants(container).filter { $0 is SKMainKeyPreview }.count == 1, "Rapid neighboring taps never stack previews")
            await wait(0.15)
            expect(descendants(container).contains { ($0 as? SKMainKeyPreview)?.letter == p.keyTitle }, "Previous timer cannot dismiss the next held preview")
            p.sendActions(for: .touchDragExit)
            expect(!descendants(container).contains { $0 is SKMainKeyPreview }, "Drag exit cancels preview immediately")
            p.sendActions(for: .touchDragEnter)
            expect(descendants(container).contains { $0 is SKMainKeyPreview }, "Dragging back restores preview")
            surface.isHidden = true
            expect(!descendants(container).contains { $0 is SKMainKeyPreview }, "Switching layouts clears previews")
            surface.removeFromSuperview()
        }
        let report = (failures.isEmpty ? "PASS " : "FAIL ") + "\(count) number/symbol and edge preview assertions\n" + failures.joined(separator: "\n")
        try? report.write(to: output.appendingPathComponent("result.txt"), atomically: true, encoding: .utf8)
    }
}
@main struct NumberAndEdgeEntry {
    @MainActor static func main() { UIApplicationMain(CommandLine.argc, CommandLine.unsafeArgv, nil, NSStringFromClass(NumberAndEdgeApp.self)) }
}
