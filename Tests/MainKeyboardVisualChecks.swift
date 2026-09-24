import UIKit

final class VisualChecksApp: UIResponder, UIApplicationDelegate {
    var window: UIWindow?
    func application(_ application: UIApplication, didFinishLaunchingWithOptions options: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        let window = UIWindow(frame: UIScreen.main.bounds)
        window.rootViewController = UIViewController()
        window.makeKeyAndVisible()
        self.window = window
        DispatchQueue.main.async { self.check() }
        return true
    }
    func check() {
        let output = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let host = window!.rootViewController!.view!
        let chinese = SKChineseJapaneseKeyboardView()
        let double = SKShuangpinKeyboardView()
        let numbers = SKNumberInputView()
        for v in [chinese, double, numbers] as [UIView] { host.addSubview(v) }
        var frames: [[String: Any]] = []
        for style: UIUserInterfaceStyle in [.light, .dark] {
            window!.overrideUserInterfaceStyle = style
            for width: CGFloat in [320, 375, 402, 440, 874] {
                let height: CGFloat = width > 600 ? 162 : 216
                for (name, view): (String, UIView) in [("chinese", chinese), ("japanese", chinese), ("shuangpin", double), ("numbers", numbers)] {
                    ([chinese, double, numbers] as [UIView]).forEach { $0.isHidden = $0 !== view }
                    if name == "chinese" { chinese.currentLanguageState = .chinese }
                    if name == "japanese" { chinese.currentLanguageState = .japanese }
                    let h: CGFloat = name == "numbers" ? 221 : height
                    view.frame = CGRect(x: 0, y: 100, width: width, height: h)
                    view.backgroundColor = style == .dark ? UIColor(white: 23.0 / 255, alpha: 1) : UIColor(red: 223.0 / 255, green: 224.0 / 255, blue: 230.0 / 255, alpha: 1)
                    view.setNeedsLayout(); view.layoutIfNeeded()
                    let format = UIGraphicsImageRendererFormat(); format.scale = 3
                    let image = UIGraphicsImageRenderer(bounds: view.bounds, format: format).image { view.layer.render(in: $0.cgContext) }
                    let prefix = "\(name)-\(Int(width))-\(style == .dark ? "dark" : "light")"
                    try! image.pngData()!.write(to: output.appendingPathComponent(prefix + ".png"))
                    if let surface = view as? SKMainKeyboardSurface {
                        for (r, keys) in surface.keyRows.enumerated() {
                            for key in keys {
                                assert(key.frame.minX >= 0 && key.frame.maxX <= width && key.frame.minY >= 0 && key.frame.maxY <= height)
                                frames.append(["case": prefix, "row": r, "key": key.keyTitle, "x": key.frame.minX, "y": key.frame.minY, "width": key.frame.width, "height": key.frame.height])
                            }
                        }
                        if width == 402 && style == .light && name == "chinese" {
                            let q = surface.keyRows[0][0], a = surface.keyRows[1][0], z = surface.keyRows[2][1]
                            assert(abs(q.frame.minX - 6.5) < 0.01 && q.frame.height == 43)
                            assert(abs(a.frame.minX - 26.25) < 0.01 && a.frame.minY - q.frame.minY == 54)
                            assert(abs(z.frame.minX - 65.75) < 0.01)
                            for key in [q, surface.keyRows[0][4], surface.keyRows[0][9]] {
                                key.sendActions(for: .touchDown)
                                // Preview is attached to the window, so include its layer in the capture.
                                let full = UIGraphicsImageRenderer(bounds: window!.bounds, format: format).image { window!.layer.render(in: $0.cgContext) }
                                try! full.pngData()!.write(to: output.appendingPathComponent("popup-\(key.keyTitle).png"))
                                key.sendActions(for: .touchCancel)
                                assert(window!.subviews.filter { $0.accessibilityIdentifier == "main-key-preview" }.isEmpty)
                            }
                        }
                    }
                }
            }
        }
        // Public-font calibration swatches; compare actual rasterized glyphs
        // against the captured native keyboard instead of guessing point size.
        for name in ["System", "SystemNarrow", "HelveticaNeue", "Arial"] {
            for size: CGFloat in [24, 25, 26] {
                let font = name == "SystemNarrow" ? UIFont.systemFont(ofSize: size, weight: .regular, width: UIFont.Width(rawValue: -0.1)) : (name == "System" ? UIFont.systemFont(ofSize: size) : UIFont(name: name, size: size)!)
                let format = UIGraphicsImageRendererFormat(); format.scale = 3
                let image = UIGraphicsImageRenderer(size: CGSize(width: 60, height: 60), format: format).image { context in
                    UIColor.white.setFill(); context.fill(CGRect(x: 0, y: 0, width: 60, height: 60))
                    ("q" as NSString).draw(at: CGPoint(x: 15, y: 5), withAttributes: [.font: font, .foregroundColor: UIColor.black])
                }
                try! image.pngData()!.write(to: output.appendingPathComponent("font-\(name)-\(Int(size)).png"))
            }
        }
        try! JSONSerialization.data(withJSONObject: frames, options: [.prettyPrinted, .sortedKeys]).write(to: output.appendingPathComponent("key-frames.json"))
        try! "PASS main-key geometry, five widths/two themes, native-inspired previews, legacy numeric snapshots".write(to: output.appendingPathComponent("result.txt"), atomically: true, encoding: .utf8)
    }
}
@main struct Main {
    static func main() { UIApplicationMain(CommandLine.argc, CommandLine.unsafeArgv, nil, NSStringFromClass(VisualChecksApp.self)) }
}
