import UIKit

private func tree(_ view: UIView) -> [UIView] { [view] + view.subviews.flatMap(tree) }
private func tap(_ button: UIControl) { button.sendActions(for: .touchDown); button.sendActions(for: .touchUpInside) }
private final class EditorProxy: NSObject, UITextDocumentProxy {
    let editor = UITextView()
    var documentIdentifier = UUID()
    var documentContextBeforeInput: String? { (editor.text as NSString).substring(to: editor.selectedRange.location) }
    var documentContextAfterInput: String? { (editor.text as NSString).substring(from: NSMaxRange(editor.selectedRange)) }
    var selectedText: String? { editor.selectedTextRange.flatMap { editor.text(in: $0) } }
    var documentInputMode: UITextInputMode? { editor.textInputMode }
    var hasText: Bool { editor.hasText }
    func insertText(_ text: String) { editor.insertText(text) }
    func deleteBackward() { editor.deleteBackward() }
    func adjustTextPosition(byCharacterOffset offset: Int) {}
    func setMarkedText(_ text: String, selectedRange: NSRange) { editor.setMarkedText(text, selectedRange: selectedRange) }
    func unmarkText() { editor.unmarkText() }
}
private final class TestKeyboard: KeyboardViewController {
    let proxy = EditorProxy()
    var nextModeCalls = 0
    var inputModeEvents: [(UIView, UIEvent)] = []
    var textAtSwitch = ""
    var markedAtSwitch = false
    override var textDocumentProxy: UITextDocumentProxy { proxy }
    override func advanceToNextInputMode() {
        nextModeCalls += 1
        recordSwitch()
    }
    override func handleInputModeList(from view: UIView, with event: UIEvent) {
        inputModeEvents.append((view, event))
        recordSwitch()
    }
    private func recordSwitch() {
        textAtSwitch = proxy.editor.text ?? ""
        markedAtSwitch = proxy.editor.markedTextRange != nil
    }
}
@main final class SymbolMemoryAndModeChecks: UIResponder, UIApplicationDelegate {
    var window: UIWindow?
    var checks = 0
    var failures: [String] = []
    func expect(_ value: Bool, _ message: String) { checks += 1; if !value { failures.append(message) } }
    static func main() { UIApplicationMain(CommandLine.argc, CommandLine.unsafeArgv, nil, NSStringFromClass(Self.self)) }
    func application(_ app: UIApplication, didFinishLaunchingWithOptions options: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        let window = UIWindow(frame: UIScreen.main.bounds)
        let host = UIViewController(); window.rootViewController = host; window.makeKeyAndVisible(); self.window = window
        Task { @MainActor in await run(host) }
        return true
    }
    @MainActor func run(_ host: UIViewController) async {
        let suite = "symbol-memory-tests"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        defer { defaults.removePersistentDomain(forName: suite) }
        let memory = SKSymbolMemory(defaults: defaults)
        let original = SKSymbolLayout.punctuation
        expect(memory.orderedSymbols() == original, "Fresh install preserves familiar ordering")
        for _ in 0..<4 { memory.record("]") }
        expect(Array(memory.orderedSymbols().prefix(2)) == ["[", "]"], "Closing bracket promotes the entire ordered pair")
        memory.record("[")
        for _ in 0..<5 { memory.record("@") }
        expect(Array(memory.orderedSymbols().prefix(3)) == ["@", "[", "]"], "Equal group frequency has deterministic original-order tie break")
        expect(SKSymbolMemory(defaults: defaults).orderedSymbols() == memory.orderedSymbols(), "Usage survives memory object recreation")
        memory.record("private sentence")
        expect(!(defaults.dictionary(forKey: "keyboard.symbolUsage.v1") ?? [:]).keys.contains("private sentence"), "Only whitelisted symbols are stored")
        let pairs = SKSymbolLayout.pairedSymbols
        for round in 0..<40 {
            for i in 0...round % 7 { memory.record(original[(round * 13 + i * 11) % original.count]) }
            let order = memory.orderedSymbols()
            expect(order.count == original.count && Set(order) == Set(original), "No lost/duplicated symbol in round \(round)")
            for pair in pairs {
                let a = order.firstIndex(of: pair[0])!, b = order.firstIndex(of: pair[1])!
                expect(b == a + 1 && a / 4 == b / 4, "Pair stays adjacent in same column: \(pair), round \(round)")
                expect((a < 16) == (b < 16), "Frequent region never splits a pair")
            }
        }
        let saved = UserDefaults.standard.dictionary(forKey: "keyboard.symbolUsage.v1")
        let savedScheme = UserDefaults.standard.string(forKey: SKInputScheme.preferenceKey)
        let savedMode = UserDefaults.standard.string(forKey: SKChineseJapaneseMode.preferenceKey)
        defer {
            UserDefaults.standard.set(saved, forKey: "keyboard.symbolUsage.v1")
            UserDefaults.standard.set(savedScheme, forKey: SKInputScheme.preferenceKey)
            UserDefaults.standard.set(savedMode, forKey: SKChineseJapaneseMode.preferenceKey)
        }
        UserDefaults.standard.removeObject(forKey: "keyboard.symbolUsage.v1")
        let keyboard = TestKeyboard()
        host.addChild(keyboard); host.view.addSubview(keyboard.view); keyboard.didMove(toParent: host)
        host.view.addSubview(keyboard.proxy.editor)
        keyboard.proxy.editor.frame = CGRect(x: 0, y: 40, width: 320, height: 44)
        keyboard.view.frame = CGRect(x: 0, y: 150, width: 402, height: 260)
        keyboard.view.layoutIfNeeded()
        let selector = tree(keyboard.view).compactMap { $0 as? SKInputSwitchButton }.first!
        func select(_ title: String) {
            let action = selector.menu!.children.compactMap { $0 as? UIAction }.first { $0.title == title }!
            let sender = UIButton(); sender.addAction(action, for: .touchUpInside); tap(sender)
            keyboard.view.layoutIfNeeded()
        }
        expect(selector.showsMenuAsPrimaryAction && selector.menu?.children.count == 4, "Single primary menu contains all four modes")
        for title in ["中文", "日文", "中日混合", "自然码双拼"] {
            select(title)
            expect(selector.accessibilityValue == title && !selector.isHidden, "Menu selects and displays \(title)")
            expect(selector.menu!.children.compactMap { $0 as? UIAction }.filter { $0.state == .on }.map(\.title) == [title], "Exactly one selected menu action")
        }
        select("中文")
        for c in "nihao" { keyboard.didTapKey(String(c)) }
        keyboard.view.layoutIfNeeded()
        expect(selector.isHidden, "Candidate content hides the mode selector")
        let bar = tree(keyboard.view).compactMap { $0 as? CandidateBarView }.first!
        expect(abs(bar.convert(bar.bounds, to: keyboard.view).minX - SKMainKeyboardMetrics.inset) < 0.5, "Candidates reclaim the hidden selector width")
        let expand = tree(bar).compactMap { $0 as? UIButton }.first { $0.accessibilityIdentifier == "candidates.expand" }!
        tap(expand); keyboard.view.layoutIfNeeded()
        expect(selector.isHidden, "Expanded candidates keep the mode selector hidden")
        tap(expand); keyboard.view.layoutIfNeeded()
        expect(selector.isHidden, "Collapsed nonempty candidates keep the mode selector hidden")
        for _ in 0..<5 { keyboard.didTapDelete() }
        keyboard.view.layoutIfNeeded()
        expect(!selector.isHidden && selector.bounds.width > 40, "Deleting composition restores the selector and its width")
        for c in "nihao" { keyboard.didTapKey(String(c)) }
        keyboard.didTapKey(" ")
        keyboard.view.layoutIfNeeded()
        expect(!selector.isHidden, "Committing candidates restores mode selection")
        select("日文")
        expect(keyboard.proxy.editor.text == "你好", "Committing before menu switch inserts text exactly once")
        expect(tree(keyboard.view).compactMap { $0 as? SKMainKeyButton }.contains { $0.accessibilityLabel == "空格，当前方案：日文" }, "Space feedback matches selected mode")
        for c in "sekai" { keyboard.didTapKey(String(c)) }
        keyboard.didTapKey(" ")
        expect(keyboard.proxy.editor.text == "你好世界", "Selected Japanese mode converts text")
        for (title, input, output) in [("中文", "nihao", "你好"), ("日文", "sekai", "世界"),
                                       ("中日混合", "nihao", "你好"), ("自然码双拼", "nihk", "你好")] {
            select(title)
            let switchKey = tree(keyboard.view).compactMap { $0 as? UIButton }.first {
                $0.accessibilityIdentifier == "keyboard.inputMode" && $0.superview?.superview?.isHidden == false
            }!
            let before = keyboard.proxy.editor.text ?? ""
            for c in input { keyboard.didTapKey(String(c)) }
            expect(keyboard.proxy.editor.markedTextRange != nil, "\(title): has pending composition before switch")
            let touchEvents: [UIControl.Event] = [.touchDown, .touchDragInside, .touchDragOutside,
                .touchDragEnter, .touchDragExit, .touchUpInside, .touchUpOutside, .touchCancel]
            for eventKind in touchEvents {
                let actions = switchKey.actions(forTarget: keyboard, forControlEvent: eventKind) ?? []
                expect(actions.count == 1, "\(title): system receives touch event \(eventKind.rawValue)")
                let event = UIEvent()
                let previousCount = keyboard.inputModeEvents.count
                for action in actions { switchKey.sendAction(NSSelectorFromString(action), to: keyboard, for: event) }
                expect(keyboard.inputModeEvents.count == previousCount + 1 &&
                       keyboard.inputModeEvents.last?.0 === switchKey && keyboard.inputModeEvents.last?.1 === event,
                       "\(title): UIKit receives original control and event")
                expect(keyboard.textAtSwitch == before + output && !keyboard.markedAtSwitch,
                       "\(title): composition committed exactly once before UIKit handles event")
            }
            expect(keyboard.nextModeCalls == 0, "Touch routing does not additionally advance keyboards")
            let nextCalls = keyboard.nextModeCalls
            for c in input { keyboard.didTapKey(String(c)) }
            switchKey.sendActions(for: .touchUpInside) // Activation without a UIEvent.
            expect(keyboard.nextModeCalls == nextCalls + 1 && keyboard.textAtSwitch == before + output + output && !keyboard.markedAtSwitch,
                   "\(title): eventless activation commits and advances exactly once")
            keyboard.nextModeCalls = 0
            keyboard.viewWillDisappear(false); keyboard.viewWillAppear(false)
            expect(keyboard.proxy.editor.text == before + output + output && selector.accessibilityValue == title,
                   "\(title): return from system keyboard preserves text and selected mode")
        }
        keyboard.didTapSwitchLayout(to: .number); keyboard.view.layoutIfNeeded()
        let numbers = tree(keyboard.view).compactMap { $0 as? SKNumberInputView }.first!
        let symbolKeys = tree(numbers).compactMap { $0 as? SKMainKeyButton }.filter(\.usesSymbolTint)
        let close = symbolKeys.first { $0.keyTitle == "]" }!
        let previousFrame = close.frame
        tap(close); tap(close)
        expect(close.frame == previousFrame, "Symbol usage does not move keys mid-session")
        keyboard.didTapSwitchLayout(to: .alphabet); keyboard.didTapSwitchLayout(to: .number); keyboard.view.layoutIfNeeded()
        let open = symbolKeys.first { $0.keyTitle == "[" }!
        expect(open.frame.minX == close.frame.minX && open.frame.minY < close.frame.minY && open.frame.minX < 5, "Reopening promotes bracket pair to first column")
        let output = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        for style: UIUserInterfaceStyle in [.light, .dark] {
            keyboard.overrideUserInterfaceStyle = style
            for width in [320.0, 402, 874] {
                host.setOverrideTraitCollection(UITraitCollection(verticalSizeClass: width > 600 ? .compact : .regular), forChild: keyboard)
                keyboard.view.frame.size = CGSize(width: width, height: width > 600 ? 206 : 260)
                keyboard.view.setNeedsLayout(); keyboard.view.layoutIfNeeded(); numbers.layoutIfNeeded()
                let scroll = tree(numbers).compactMap { $0 as? UIScrollView }.first!
                let first16 = symbolKeys.sorted { a,b in a.frame.minX == b.frame.minX ? a.frame.minY < b.frame.minY : a.frame.minX < b.frame.minX }.prefix(16)
                expect(first16.allSatisfy { scroll.bounds.contains($0.convert($0.bounds, to: scroll)) }, "16 frequent symbols fully visible at \(width)")
                let digit = tree(numbers).compactMap { $0 as? SKMainKeyButton }.first { $0.keyTitle == "1" }!
                expect(digit.backgroundColor != open.backgroundColor, "Numeric and symbol regions have different colors in \(style.rawValue)")
                let image = UIGraphicsImageRenderer(bounds: keyboard.view.bounds).image { UIColor(white: style == .dark ? 0.09 : 0.88, alpha: 1).setFill(); $0.fill(keyboard.view.bounds); keyboard.view.layer.render(in: $0.cgContext) }
                try? image.pngData()?.write(to: output.appendingPathComponent("memory-numbers-\(Int(width))-\(style.rawValue).png"))
            }
        }
        keyboard.overrideUserInterfaceStyle = .light
        host.setOverrideTraitCollection(UITraitCollection(verticalSizeClass: .regular), forChild: keyboard)
        keyboard.view.frame.size = CGSize(width: 402, height: 260)
        keyboard.didTapSwitchLayout(to: .alphabet); keyboard.view.setNeedsLayout(); keyboard.view.layoutIfNeeded()
        let image = UIGraphicsImageRenderer(bounds: keyboard.view.bounds).image { UIColor(white: 0.88, alpha: 1).setFill(); $0.fill(keyboard.view.bounds); keyboard.view.layer.render(in: $0.cgContext) }
        try? image.pngData()?.write(to: output.appendingPathComponent("system-keyboard-entry.png"))
        let report = (failures.isEmpty ? "PASS " : "FAIL ") + "\(checks) symbol memory/mode/system keyboard assertions\n" + failures.joined(separator: "\n")
        try? report.write(to: output.appendingPathComponent("result.txt"), atomically: true, encoding: .utf8)
    }
}
