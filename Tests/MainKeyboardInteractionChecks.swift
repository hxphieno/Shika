import UIKit

private final class EventRecorder: SKKeyboardEventHandler {
    var text: [String] = []
    var deletes = 0
    var switches = 0
    var layouts: [SKKeyboardLayoutType] = []
    func didTapKey(_ key: String) { text.append(key) }
    func didTapDelete() { deletes += 1 }
    func didTapSwitchScheme() { switches += 1 }
    func didTapNextKeyboard() {}
    func didTapSwitchLayout(to layout: SKKeyboardLayoutType) { layouts.append(layout) }
}
private final class InteractionProxy: NSObject, UITextDocumentProxy {
    // Keep committed output separate from the pending composition in this spy.
    var text = ""
    var markedText: String?
    var documentContextBeforeInput: String? { text + (markedText ?? "") }
    var documentContextAfterInput: String? { "" }
    var selectedText: String? { nil }
    var documentInputMode: UITextInputMode? { nil }
    var documentIdentifier = UUID()
    var hasText: Bool { !text.isEmpty }
    func insertText(_ value: String) { text += value }
    func deleteBackward() { if !text.isEmpty { text.removeLast() } }
    func adjustTextPosition(byCharacterOffset offset: Int) {}
    func setMarkedText(_ markedText: String, selectedRange: NSRange) { self.markedText = markedText }
    func unmarkText() {
        text += markedText ?? ""
        markedText = nil
    }
}
private final class InteractionController: KeyboardViewController {
    let proxy = InteractionProxy()
    override var textDocumentProxy: UITextDocumentProxy { proxy }
}
private func tree(_ view: UIView) -> [UIView] { [view] + view.subviews.flatMap(tree) }
private func press(_ key: UIButton) { key.sendActions(for: .touchDown); key.sendActions(for: .touchUpInside) }

@MainActor
final class MainInteractionApp: UIResponder, UIApplicationDelegate {
    var window: UIWindow?
    var failures: [String] = []
    var assertions = 0
    func expect(_ value: Bool, _ label: String) {
        assertions += 1
        if !value { failures.append(label) }
    }
    func application(_ application: UIApplication, didFinishLaunchingWithOptions options: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        let window = UIWindow(frame: UIScreen.main.bounds)
        let host = UIViewController()
        host.view.backgroundColor = .systemBackground
        window.rootViewController = host
        window.makeKeyAndVisible()
        self.window = window
        Task { @MainActor in await self.run(host) }
        return true
    }
    func run(_ host: UIViewController) async {
        let output = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let full = SKChineseJapaneseKeyboardView()
        let double = SKShuangpinKeyboardView()
        let recorder = EventRecorder()
        full.eventHandler = recorder
        double.eventHandler = recorder
        for surface in [full, double] as [SKMainKeyboardSurface] {
            host.view.addSubview(surface)
            surface.frame = CGRect(x: 0, y: 200, width: 402, height: 216)
            surface.layoutIfNeeded()
            surface.footer?.layoutIfNeeded()
            let shift = surface.keyRows[2][0]
            let letter = surface.keyRows[0][0]
            expect(!(shift.gestureRecognizers ?? []).contains { ($0 as? UITapGestureRecognizer)?.numberOfTapsRequired == 2 }, "Shift has no delayed double-tap recognizer")
            press(shift)
            expect(shift.accessibilityValue == "大写" && letter.keyTitle == "Q", "Shift first tap applies uppercase synchronously")
            press(letter)
            expect(recorder.text.last == "Q" && letter.keyTitle == "q", "One-shot Shift emits uppercase then resets")
            press(shift); press(shift)
            expect(shift.accessibilityValue == "大写锁定", "Rapid double Shift locks uppercase")
            press(letter); press(letter)
            expect(recorder.text.suffix(2) == ["Q", "Q"] && letter.keyTitle == "Q", "Caps lock survives multiple letters")
            press(shift)
            expect(shift.accessibilityValue == "小写" && letter.keyTitle == "q", "Single Shift unlocks caps")

            for (width, height) in [(320.0,216.0),(390,216),(402,216),(430,216),(874,162)] {
                surface.frame.size = CGSize(width: width, height: height)
                surface.setNeedsLayout(); surface.layoutIfNeeded(); surface.footer?.layoutIfNeeded()
                let keys = surface.keyRows.flatMap { $0 } + (surface.footer?.subviews.compactMap { $0 as? SKMainKeyButton } ?? [])
                expect(keys.allSatisfy { key in
                    let rect = key.convert(key.bounds, to: surface)
                    return rect.width > 0 && rect.height > 0 && surface.bounds.insetBy(dx: -0.01, dy: -0.01).contains(rect)
                }, "All visible keys fit \(width) × \(height)")
                expect(keys.allSatisfy { key in
                    let center = key.convert(CGPoint(x: key.bounds.midX, y: key.bounds.midY), to: surface)
                    return surface.hitTest(center, with: nil) === key
                }, "Exact key centers preserve their own actions at \(width)")
                var deadZones = 0
                for y in stride(from: 1.0, to: height, by: 7) {
                    for x in stride(from: 1.0, to: width, by: 7) {
                        let location = CGPoint(x: x, y: y)
                        if let hit = surface.hitTest(location, with: nil) as? SKMainKeyButton {
                            if !hit.point(inside: surface.convert(location, to: hit), with: nil) { deadZones += 1 }
                        } else { deadZones += 1 }
                    }
                }
                expect(deadZones == 0, "No dead touch gutters at \(width), found \(deadZones)")
                let left = surface.keyRows[0][0], right = surface.keyRows[0][1]
                let gapMiddle = (left.frame.maxX + right.frame.minX) / 2
                expect(surface.hitTest(CGPoint(x: gapMiddle - 0.2, y: left.frame.midY), with: nil) === left,
                       "Left half of gutter routes left at \(width)")
                expect(surface.hitTest(CGPoint(x: gapMiddle + 0.2, y: left.frame.midY), with: nil) === right,
                       "Right half of gutter routes right at \(width)")
                expect(surface.hitTest(CGPoint(x: 5, y: -1), with: nil) == nil, "Main keys cannot steal candidate-bar touches")
            }
            surface.frame.size = CGSize(width: 402, height: 216)
            surface.setNeedsLayout(); surface.layoutIfNeeded(); surface.footer?.layoutIfNeeded()
            let deletion = surface.keyRows[2].last!
            let beforeAccessibility = recorder.deletes
            expect(deletion.accessibilityActivate() && recorder.deletes == beforeAccessibility + 1,
                   "Accessibility activation deletes exactly once")
            let before = recorder.deletes
            deletion.sendActions(for: .touchDown)
            expect(recorder.deletes == before + 1, "Delete occurs on touchDown")
            try? await Task.sleep(nanoseconds: 250_000_000)
            expect(recorder.deletes == before + 1, "Delete repeat waits for hold threshold")
            try? await Task.sleep(nanoseconds: 340_000_000)
            expect(recorder.deletes >= before + 3, "Held delete repeats")
            let repeated = recorder.deletes
            deletion.sendActions(for: .touchUpInside)
            expect(recorder.deletes == repeated, "Delete release does not delete an extra character")
            try? await Task.sleep(nanoseconds: 180_000_000)
            expect(recorder.deletes == repeated, "Delete timer stops after release")
            deletion.sendActions(for: .touchDown)
            deletion.sendActions(for: .touchCancel)
            let cancelled = recorder.deletes
            try? await Task.sleep(nanoseconds: 500_000_000)
            expect(recorder.deletes == cancelled, "Delete timer stops after cancellation")
            deletion.sendActions(for: .touchDown)
            surface.removeFromSuperview()
            let removed = recorder.deletes
            try? await Task.sleep(nanoseconds: 500_000_000)
            expect(recorder.deletes == removed, "Removing keyboard stops held delete")
        }
        full.currentLanguageState = .chinese
        expect(full.keyRows[1].count == 9, "Chinese main row has nine keys")
        full.currentLanguageState = .japanese
        expect(full.keyRows[1].count == 10, "Japanese main row keeps long-vowel key")
        full.currentLanguageState = .mixed
        expect(full.keyRows[1].count == 10, "Mixed main row keeps long-vowel key")

        UserDefaults.standard.set("shuangpin", forKey: SKInputScheme.preferenceKey)
        let controller = InteractionController()
        host.addChild(controller); host.view.addSubview(controller.view); controller.didMove(toParent: host)
        controller.view.frame = CGRect(x: 0, y: 200, width: 402, height: 276)
        controller.view.layoutIfNeeded()
        let number = tree(controller.view).first { $0 is SKNumberInputView }!
        let main = tree(controller.view).compactMap { $0 as? SKShuangpinKeyboardView }.first!
        let mainFrames = main.keyRows.flatMap { $0 }.map(\.frame)
        for _ in 0..<5 {
            controller.didTapSwitchLayout(to: .number)
            controller.view.layoutIfNeeded()
            expect(!number.isHidden && main.isHidden, "Number page is the sole visible keyboard")
            expect(!number.hasAmbiguousLayout && abs(number.frame.maxY - controller.view.bounds.maxY) < 0.5,
                   "Number page keeps bottom constraints")
            controller.didTapSwitchLayout(to: .alphabet)
            controller.view.layoutIfNeeded()
            expect(number.isHidden && !main.isHidden, "Returning from numbers restores selected alphabet scheme")
            expect(main.keyRows.flatMap { $0 }.map(\.frame) == mainFrames, "Number switch leaves main-key geometry unchanged")
        }
        let image = UIGraphicsImageRenderer(bounds: controller.view.bounds).image { controller.view.layer.render(in: $0.cgContext) }
        try? image.pngData()?.write(to: output.appendingPathComponent("main-interaction-final.png"))
        // Language state belongs to the controller and survives scheme switches.
        controller.didTapSwitchScheme()
        let language = tree(controller.view).compactMap { $0 as? SKInputSwitchButton }.first!
        let mixed = tree(controller.view).compactMap { $0 as? SKChineseJapaneseKeyboardView }.first!
        expect(language.currentState == .mixed && mixed.currentLanguageState == .mixed, "Language mode starts mixed")
        for letter in "nihao" { controller.didTapKey(String(letter)) }
        press(language)
        expect(language.currentState == .chinese && mixed.keyRows[1].count == 9, "Language tap renders Chinese state and layout")
        expect(controller.proxy.text.isEmpty && controller.proxy.markedText?.replacingOccurrences(of: " ", with: "") == "nihao", "Language tap preserves pending Chinese composition")
        controller.didTapKey(" ")
        expect(controller.proxy.text == "你好", "Chinese mode commits existing composition once")
        press(language)
        expect(language.currentState == .japanese && mixed.keyRows[1].count == 10, "Next language tap renders Japanese layout")
        controller.didTapSwitchScheme(); controller.didTapSwitchScheme()
        expect(language.currentState == .japanese && mixed.currentLanguageState == .japanese, "Language state survives switching away and back")
        for letter in "shijie" { controller.didTapKey(String(letter)) }
        controller.didTapKey(" ")
        expect(controller.proxy.text == "你好世界", "Japanese UI mode retains MVP Chinese conversion")
        press(language)
        expect(language.currentState == .mixed && mixed.currentLanguageState == .mixed, "Language cycle returns to mixed")
        let report = (failures.isEmpty ? "PASS " : "FAIL ") + "\(assertions) main keyboard interaction assertions\n" + failures.joined(separator: "\n")
        try? report.write(to: output.appendingPathComponent("result.txt"), atomically: true, encoding: .utf8)
        try? JSONSerialization.data(withJSONObject: ["assertions": assertions, "failures": failures], options: .prettyPrinted)
            .write(to: output.appendingPathComponent("main-interaction-report.json"))
    }
}
@main
struct MainKeyboardInteractionEntry {
    @MainActor static func main() {
        UIApplicationMain(CommandLine.argc, CommandLine.unsafeArgv, nil, NSStringFromClass(MainInteractionApp.self))
    }
}
