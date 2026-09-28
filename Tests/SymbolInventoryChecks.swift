import UIKit

private func tree(_ v: UIView) -> [UIView] { [v] + v.subviews.flatMap(tree) }
private final class Recorder: SKKeyboardEventHandler {
    var inputs: [String] = []
    func didTapKey(_ key: String) { inputs.append(key) }
    func didTapSwitchScheme() {}
    func didTapDelete() {}
    func didTapNextKeyboard() {}
    func didTapSwitchLayout(to layout: SKKeyboardLayoutType) {}
}
@main final class SymbolInventoryChecks: UIResponder, UIApplicationDelegate {
    var window: UIWindow?
    var failures: [String] = []
    var checks = 0
    func expect(_ condition: Bool, _ message: String) { checks += 1; if !condition { failures.append(message) } }
    static func main() { UIApplicationMain(CommandLine.argc, CommandLine.unsafeArgv, nil, NSStringFromClass(Self.self)) }
    func application(_ application: UIApplication, didFinishLaunchingWithOptions options: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        let window = UIWindow(frame: UIScreen.main.bounds)
        let host = UIViewController(); window.rootViewController = host; window.makeKeyAndVisible(); self.window = window
        DispatchQueue.main.async { self.run(host) }
        return true
    }
    func run(_ host: UIViewController) {
        let out = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let original = SKSymbolLayout.punctuation
        expect(original.count == 116 && Set(original).count == 116, "116 distinct symbols")
        let data = try! Data(contentsOf: Bundle.main.url(forResource: "ios26-symbols", withExtension: "json")!)
        let fixture = try! JSONSerialization.jsonObject(with: data) as! [String: Any]
        for symbol in fixture["symbols"] as! [String] { expect(original.contains(symbol), "Native inventory coverage: \(symbol)") }
        for symbol in ["(", ")", "!", "?", ".", "'", "\""] { expect(SKSymbolLayout.badge(for: symbol) == "英", "English hint \(symbol)") }
        for symbol in ["（", "）", "！", "？", "。", "「", "」", "〔", "〕"] { expect(SKSymbolLayout.badge(for: symbol) == "中日", "CJK hint \(symbol)") }
        for symbol in ["€", "×", "☆"] { expect(SKSymbolLayout.badge(for: symbol) == nil, "No language ownership for general symbol") }
        let suite = "symbol-inventory-checks"; let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let memory = SKSymbolMemory(defaults: defaults)
        expect(memory.orderedSymbols() == original, "Fresh order unchanged")
        defaults.set(["@": 100], forKey: "keyboard.symbolUsage.v1")
        expect(memory.orderedSymbols().first == "@", "Old counts preserved")
        for pair in [["〔", "〕"], ["〈", "〉"], ["［", "］"], ["‘", "’"], ["«", "»"]] {
            defaults.removePersistentDomain(forName: suite); memory.record(pair[1])
            expect(Array(memory.orderedSymbols().prefix(2)) == pair, "Closing mark promotes full new pair")
        }
        for round in 0..<80 {
            memory.record(original[(round * 17) % original.count])
            let order = memory.orderedSymbols()
            expect(Set(order) == Set(original) && order.count == original.count, "No lost or duplicate keys")
            for pair in SKSymbolLayout.pairedSymbols {
                let a = order.firstIndex(of: pair[0])!, b = order.firstIndex(of: pair[1])!
                expect(b == a + 1 && a / 4 == b / 4 && (a < 16) == (b < 16), "Pair boundaries: \(pair)")
            }
        }
        defaults.removePersistentDomain(forName: suite)
        let saved = UserDefaults.standard.object(forKey: "keyboard.symbolUsage.v1")
        defer { UserDefaults.standard.set(saved, forKey: "keyboard.symbolUsage.v1") }
        UserDefaults.standard.removeObject(forKey: "keyboard.symbolUsage.v1")
        let keyboard = SKNumberInputView(); let recorder = Recorder(); keyboard.eventHandler = recorder
        host.view.addSubview(keyboard)
        for (width, height) in [(320.0,216.0),(402.0,216.0),(874.0,162.0)] {
            for dark in [false,true] {
                keyboard.overrideUserInterfaceStyle = dark ? .dark : .light
                keyboard.frame = CGRect(x: 0,y: 120,width: width,height: height); keyboard.layoutIfNeeded()
                let keys = tree(keyboard).compactMap { $0 as? SKSymbolKeyButton }
                expect(keys.count == 116, "All symbol keys present")
                for key in keys {
                    key.layoutIfNeeded()
                    let hint = key.subviews.compactMap { $0 as? UILabel }.first { $0 !== key.titleLabel }!
                    expect(hint.isHidden == (SKSymbolLayout.badge(for: key.keyTitle) == nil), "Badge visibility")
                    expect(!hint.isUserInteractionEnabled && !hint.isAccessibilityElement, "Badge cannot steal tap")
                    if !hint.isHidden {
                        expect(key.bounds.contains(hint.frame), "Badge contained")
                        expect(hint.intrinsicContentSize.width <= hint.frame.width, "Badge fits narrow key")
                    }
                    key.sendActions(for: .touchUpInside)
                    expect(recorder.inputs.last == key.keyTitle, "Exact symbol insertion \(key.keyTitle)")
                }
                let renderer = UIGraphicsImageRenderer(size: keyboard.bounds.size)
                let image = renderer.image { ctx in keyboard.layer.render(in: ctx.cgContext) }
                try! image.pngData()!.write(to: out.appendingPathComponent("symbols-\(Int(width))-\(dark ? "dark" : "light").png"))
            }
        }
        let result = failures.isEmpty ? "PASS \(checks) symbol inventory, exact-input, layout and paired-memory checks" : "FAIL\n" + failures.joined(separator: "\n")
        try! result.write(to: out.appendingPathComponent("result.txt"), atomically: true, encoding: .utf8)
    }
}
