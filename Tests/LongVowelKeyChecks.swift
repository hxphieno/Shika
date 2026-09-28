import UIKit

private final class LongVowelEvents: SKKeyboardEventHandler {
    var typed: [String] = []
    func didTapKey(_ key: String) { typed.append(key) }
    func didTapDelete() {}
    func didTapSwitchScheme() {}
    func didTapNextKeyboard() {}
    func didTapSwitchLayout(to layout: SKKeyboardLayoutType) {}
}

private final class HoldProbe: UILongPressGestureRecognizer {
    var phase: UIGestureRecognizer.State = .began
    var point = CGPoint.zero
    weak var coordinateView: UIView?
    override var state: UIGestureRecognizer.State { get { phase } set { phase = newValue } }
    override func location(in view: UIView?) -> CGPoint { coordinateView?.convert(point, to: view) ?? point }
}

@main final class LongVowelKeyChecks: UIResponder, UIApplicationDelegate {
    var window: UIWindow?
    static func main() { UIApplicationMain(CommandLine.argc, CommandLine.unsafeArgv, nil, NSStringFromClass(Self.self)) }
    func application(_ application: UIApplication, didFinishLaunchingWithOptions options: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        let window = UIWindow(frame: UIScreen.main.bounds)
        let host = UIViewController(); host.view.backgroundColor = .systemBackground
        window.rootViewController = host; window.makeKeyAndVisible(); self.window = window
        DispatchQueue.main.async { self.run(host) }
        return true
    }
    private func tree(_ view: UIView) -> [UIView] { [view] + view.subviews.flatMap(tree) }
    private func run(_ host: UIViewController) {
        var count = 0, failures: [String] = []
        func expect(_ condition: Bool, _ label: String) { count += 1; if !condition { failures.append(label) } }
        let output = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let keyboard = SKChineseJapaneseKeyboardView(), events = LongVowelEvents()
        keyboard.eventHandler = events
        keyboard.frame = CGRect(x: 0, y: 240, width: host.view.bounds.width, height: 260)
        host.view.addSubview(keyboard); keyboard.layoutIfNeeded()
        keyboard.backgroundColor = UIColor { $0.userInterfaceStyle == .dark ? UIColor(white: 0.08, alpha: 1) : UIColor(white: 0.88, alpha: 1) }
        let key = tree(keyboard).compactMap { $0 as? SKLongVowelKeyButton }.first!
        let probe = HoldProbe(); probe.coordinateView = key
        func hold(_ phase: UIGestureRecognizer.State, dx: CGFloat = 0, dy: CGFloat = 0) {
            probe.phase = phase; probe.point = CGPoint(x: key.bounds.midX + dx, y: key.bounds.midY + dy)
            key.handleHold(probe)
        }
        func popup() -> UIView? { tree(host.view).first { $0.accessibilityIdentifier == "long-vowel.options" } }
        func save(_ name: String) {
            let image = UIGraphicsImageRenderer(bounds: host.view.bounds).image { host.view.layer.render(in: $0.cgContext) }
            try! image.pngData()!.write(to: output.appendingPathComponent(name + ".png"))
        }
        expect(keyboard.keyRows[1].count == 9 && key.isLongVowelEnabled, "mixed uses standard 26-key layout")
        expect(!tree(key).first { $0.accessibilityIdentifier == "long-vowel.hint" }!.isHidden, "mixed L shows the hint")
        expect(key.titleLabel?.textAlignment == .center, "annotated L stays horizontally centered")
        expect((tree(key).first { $0.accessibilityIdentifier == "long-vowel.hint" } as? UILabel)?.text == "ー", "hint contains only the small long vowel")
        expect(key.titleLabel.map { abs($0.center.x - key.bounds.midX) < 0.5 && abs($0.center.y - (key.bounds.midY - 4)) < 0.5 } ?? false,
               "L is centered slightly above the key midpoint")
        let recognizer = key.gestureRecognizers!.compactMap { $0 as? UILongPressGestureRecognizer }.first!
        expect(recognizer.minimumPressDuration == 0, "selection begins immediately without a hold delay")
        expect(recognizer.isEnabled && recognizer.cancelsTouchesInView, "long hold cancels normal button tap")
        key.sendActions(for: .touchUpInside)
        expect(events.typed == ["l"], "normal L tap preserved")
        save("mixed-long-vowel-hint")
        key.sendActions(for: .touchDown)
        expect(tree(host.view).contains { $0.accessibilityIdentifier == "main-key-preview" }, "touch down opens plain letter preview")
        hold(.began)
        expect(popup() != nil && events.typed == ["l"], "hold opens popup without committing")
        expect(!tree(host.view).contains { $0.accessibilityIdentifier == "main-key-preview" }, "expanded popup replaces plain preview")
        hold(.changed, dx: -56)
        let left = popup()?.subviews.compactMap { $0 as? UILabel }.first
        expect(left?.text == "ー" && left?.backgroundColor == .systemBlue, "slide left highlights long vowel")
        save("mixed-long-vowel-selected")
        hold(.ended, dx: -56)
        expect(events.typed == ["l", "ー"] && popup() == nil, "left release emits only long vowel")
        hold(.began); hold(.changed, dx: -56); hold(.changed); hold(.ended)
        expect(events.typed.last == "l" && events.typed.count == 3, "slide back right selects L")
        hold(.began); hold(.ended)
        expect(events.typed.last == "l" && events.typed.count == 4, "hold without sliding still emits L")
        hold(.began); hold(.ended, dx: -200)
        expect(events.typed.count == 4, "release outside cancels")
        hold(.began); hold(.cancelled)
        expect(events.typed.count == 4 && popup() == nil, "cancelled gesture emits nothing")
        let shift = keyboard.keyRows[2].first!
        shift.sendActions(for: .touchUpInside)
        hold(.began); hold(.ended)
        expect(events.typed.last == "L" && key.keyTitle == "l", "uppercase option consumes one-shot shift")
        hold(.began); keyboard.currentLanguageState = .chinese; hold(.ended, dx: -56)
        expect(events.typed.count == 5 && popup() == nil, "mode switch cancels held selection")
        expect(!key.isLongVowelEnabled && keyboard.keyRows[1].count == 9 && key.accessibilityCustomActions == nil, "Chinese has ordinary L only")
        key.sendActions(for: .touchUpInside)
        expect(events.typed.last == "l" && events.typed.count == 6, "Chinese L still types")
        keyboard.currentLanguageState = .japanese
        expect(!key.isLongVowelEnabled && keyboard.keyRows[1].count == 10 && keyboard.keyRows[1].last?.keyTitle == "ー", "Japanese keeps dedicated long vowel")
        keyboard.currentLanguageState = .mixed; hold(.began); keyboard.isHidden = true; hold(.ended, dx: -56)
        expect(popup() == nil && events.typed.count == 6, "hiding layout cancels pending option")
        keyboard.isHidden = false
        for width: CGFloat in [320, 402, 874] {
            host.view.frame.size.width = width; keyboard.frame.size.width = width; keyboard.layoutIfNeeded()
            hold(.began)
            expect(popup().map { $0.frame.minX >= 0 && $0.frame.maxX <= width } ?? false, "popup stays inside width \(width)")
            hold(.cancelled)
        }
        keyboard.frame.size.width = 402; host.view.frame.size.width = 402; keyboard.layoutIfNeeded()
        host.overrideUserInterfaceStyle = .dark
        hold(.began); hold(.changed, dx: -56); save("mixed-long-vowel-dark"); hold(.cancelled)
        do {
            let config = SKChineseJapaneseScheme.configuration(for: .mixed)
            let engine = try SKConversionEngine(configuration: config, userURL: output.appendingPathComponent("long-vowel-user", isDirectory: true))
            var text = ""
            let session = SKInputSession(engine: engine, configuration: config, insertText: { text += $0 }, deleteText: {})
            for c in "ko" { session.type(String(c)) }
            key.onSelection = { session.type($0) }
            hold(.began); hold(.ended, dx: -56)
            for c in "hi" { session.type(String(c)) }
            hold(.began); hold(.ended, dx: -56)
            expect(session.state.input == "ko-hi-" && text.isEmpty, "selected marks stay inside mixed composition")
            if let coffee = session.state.candidates.first(where: { $0.text == "コーヒー" }) {
                session.select(coffee)
                expect(text == "コーヒー", "mixed engine commits coffee from L-selected long vowels")
            } else { expect(false, "mixed engine offers coffee") }
        } catch { expect(false, "real mixed engine initializes: \(error)") }
        let report = "\(failures.isEmpty ? "PASS" : "FAIL") \(count) long-vowel interaction checks\n" + failures.joined(separator: "\n")
        try! report.write(to: output.appendingPathComponent("result.txt"), atomically: true, encoding: .utf8)
    }
}
