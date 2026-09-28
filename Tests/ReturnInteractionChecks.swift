import UIKit

// Focused return-key acceptance only. Uses production controller/footer/session
// with a real UITextView. The send delegate explicitly models a messaging host;
// no claim is made about every third-party host's newline handling.
private final class ReturnHostDelegate: NSObject, UITextViewDelegate {
    var sent: [String] = []
    func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool {
        if text == "\n", textView.returnKeyType == .send {
            sent.append(textView.text ?? "")
            return false
        }
        return true
    }
}
private final class ReturnEditorProxy: NSObject, UITextDocumentProxy {
    let editor = UITextView()
    let host = ReturnHostDelegate()
    var documentIdentifier = UUID()
    var insertions: [String] = []
    override init() { super.init(); editor.delegate = host }
    var returnKeyType: UIReturnKeyType {
        get { editor.returnKeyType }
        set { editor.returnKeyType = newValue }
    }
    var documentContextBeforeInput: String? {
        let text = (editor.text ?? "") as NSString
        return text.substring(to: min(editor.selectedRange.location, text.length))
    }
    var documentContextAfterInput: String? {
        let text = (editor.text ?? "") as NSString
        return text.substring(from: min(NSMaxRange(editor.selectedRange), text.length))
    }
    var selectedText: String? { editor.selectedTextRange.flatMap { editor.text(in: $0) } }
    var documentInputMode: UITextInputMode? { editor.textInputMode }
    var hasText: Bool { editor.hasText }
    func insertText(_ text: String) {
        insertions.append(text)
        // A real extension forwards to its host. Explicitly route the send
        // action to the test host delegate, which consumes it without inserting
        // a literal newline. Ordinary edits still use UITextView itself.
        if text == "\n", editor.returnKeyType == .send,
           !host.textView(editor, shouldChangeTextIn: editor.selectedRange, replacementText: text) { return }
        editor.insertText(text)
    }
    func deleteBackward() { editor.deleteBackward() }
    func adjustTextPosition(byCharacterOffset offset: Int) {}
    func setMarkedText(_ text: String, selectedRange: NSRange) { editor.setMarkedText(text, selectedRange: selectedRange) }
    func unmarkText() { editor.unmarkText() }
}
private final class ReturnKeyboard: KeyboardViewController {
    let proxy = ReturnEditorProxy()
    override var textDocumentProxy: UITextDocumentProxy { proxy }
}
private func returnTree(_ view: UIView) -> [UIView] { [view] + view.subviews.flatMap(returnTree) }
private func returnVisible(_ view: UIView) -> Bool {
    var current: UIView? = view
    while let item = current { if item.isHidden { return false }; current = item.superview }
    return true
}

@main final class ReturnInteractionChecks: UIResponder, UIApplicationDelegate {
    var window: UIWindow?
    var checks: [[String: Any]] = []
    static func main() { UIApplicationMain(CommandLine.argc, CommandLine.unsafeArgv, nil, NSStringFromClass(Self.self)) }
    func expect(_ passed: Bool, _ label: String, _ detail: String = "") {
        checks.append(["label": label, "passed": passed, "detail": detail])
        print("\(passed ? "PASS" : "FAIL") \(label) \(detail)")
    }
    func application(_ application: UIApplication, didFinishLaunchingWithOptions options: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        let window = UIWindow(frame: UIScreen.main.bounds), host = UIViewController()
        window.rootViewController = host; window.makeKeyAndVisible(); self.window = window
        Task { @MainActor in await run(host) }
        return true
    }
    @MainActor func run(_ host: UIViewController) async {
        func settle() async { try? await Task.sleep(nanoseconds: 20_000_000) }
        func make(_ scheme: SKInputScheme, _ language: SKChineseJapaneseMode, _ returnType: UIReturnKeyType) -> ReturnKeyboard {
            UserDefaults.standard.set(scheme.rawValue, forKey: SKInputScheme.preferenceKey)
            UserDefaults.standard.set(language.rawValue, forKey: SKChineseJapaneseMode.preferenceKey)
            let keyboard = ReturnKeyboard(), editor = keyboard.proxy.editor
            keyboard.proxy.returnKeyType = returnType
            editor.frame = CGRect(x: 10, y: 80, width: 380, height: 120)
            editor.inputView = UIView(frame: .zero); editor.autocorrectionType = .no; editor.spellCheckingType = .no
            host.view.addSubview(editor); editor.becomeFirstResponder()
            host.addChild(keyboard); host.view.addSubview(keyboard.view); keyboard.didMove(toParent: host)
            keyboard.view.frame = CGRect(x: 0, y: 250, width: 402, height: 260)
            keyboard.view.layoutIfNeeded(); keyboard.textDidChange(editor)
            return keyboard
        }
        func detach(_ keyboard: ReturnKeyboard) {
            keyboard.viewWillDisappear(false); keyboard.proxy.editor.resignFirstResponder()
            keyboard.proxy.editor.removeFromSuperview(); keyboard.willMove(toParent: nil)
            keyboard.view.removeFromSuperview(); keyboard.removeFromParent()
        }
        func footer(_ keyboard: ReturnKeyboard) -> SKKeyboardFooterView {
            returnTree(keyboard.view).compactMap { $0 as? SKKeyboardFooterView }.first(where: returnVisible)!
        }
        func enter(_ keyboard: ReturnKeyboard) -> SKMainKeyButton {
            footer(keyboard).subviews.compactMap { $0 as? SKMainKeyButton }.last!
        }
        func style(_ keyboard: ReturnKeyboard, _ title: String) -> Bool {
            let button = enter(keyboard)
            guard button.accessibilityLabel == title else { return false }
            if title == "换行" || title == "回车" || title == "发送" { return button.currentTitle == title || button.currentImage != nil }
            return button.currentTitle == title
        }
        func marked(_ keyboard: ReturnKeyboard) -> String? {
            let editor = keyboard.proxy.editor
            return editor.markedTextRange.flatMap { editor.text(in: $0) }
        }
        func candidate(_ keyboard: ReturnKeyboard, _ title: String) -> UIButton? {
            guard let bar = returnTree(keyboard.view).compactMap({ $0 as? CandidateBarView }).first else { return nil }
            return returnTree(bar).compactMap { $0 as? UIButton }.first { $0.accessibilityLabel == title }
        }
        func type(_ input: String, _ keyboard: ReturnKeyboard) async {
            await settle()
            for character in input { keyboard.didTapKey(String(character)); await settle() }
        }
        func reset(_ keyboard: ReturnKeyboard) async {
            keyboard.textWillChange(keyboard.proxy.editor)
            keyboard.proxy.editor.text = ""; keyboard.proxy.editor.selectedRange = NSRange(location: 0, length: 0)
            keyboard.proxy.host.sent = []; keyboard.proxy.insertions = []
            keyboard.textDidChange(keyboard.proxy.editor); await settle()
        }
        let cases: [(String, SKInputScheme, SKChineseJapaneseMode, String, String)] = [
            ("full pinyin", .chineseJapanese, .chinese, "nihao", "nihao"),
            ("double pinyin", .shuangpin, .chinese, "nihk", "nihk"),
            ("Japanese", .chineseJapanese, .japanese, "nihon", "nihon"),
            ("mixed", .chineseJapanese, .mixed, "nihao", "nihao")
        ]
        for (name, scheme, language, input, confirmation) in cases {
            let keyboard = make(scheme, language, .send), proxy = keyboard.proxy
            expect(style(keyboard, "发送"), "\(name): idle footer follows send host")
            await type(input, keyboard)
            expect(marked(keyboard) != nil && style(keyboard, "发送"), "\(name): composing keeps the host return label")
            if language == .japanese {
                expect(marked(keyboard) == input, "Japanese marked text shows the original romaji")
                expect(candidate(keyboard, "にほん")?.tag == 2, "Japanese kana is the third selectable candidate")
            }
            // First return travels through the real footer. It must not pick the
            // first converted candidate, send, or insert a newline.
            enter(keyboard).sendActions(for: .touchUpInside); await settle()
            expect(proxy.editor.text == confirmation && marked(keyboard) == nil && proxy.host.sent.isEmpty && !proxy.insertions.contains("\n"), "\(name): first return confirms composition only", proxy.editor.text ?? "nil")
            expect(style(keyboard, "发送"), "\(name): host return label restores after confirmation")
            // The second press also covers the controller's public key path.
            keyboard.didTapKey("\n"); await settle()
            expect(proxy.host.sent == [confirmation] && proxy.insertions.filter { $0 == "\n" }.count == 1 && proxy.editor.text == confirmation, "\(name): second return reaches send host exactly once")
            if language == .japanese {
                await reset(keyboard); await type("kya", keyboard)
                keyboard.didTapDelete()
                expect(marked(keyboard) == "ky", "Japanese backspace deletes one visible original letter")
                enter(keyboard).sendActions(for: .touchUpInside)
                expect(proxy.editor.text == "ky" && marked(keyboard) == nil && proxy.host.sent.isEmpty, "Japanese return after deletion preserves exact remaining spelling")
                await reset(keyboard); await type("nihon", keyboard)
                candidate(keyboard, "にほん")?.sendActions(for: .touchUpInside)
                expect(proxy.editor.text == "にほん" && marked(keyboard) == nil && proxy.host.sent.isEmpty, "third kana candidate commits kana without sending")
                enter(keyboard).sendActions(for: .touchUpInside)
                expect(proxy.host.sent == ["にほん"], "return after selecting kana invokes host send")
            }
            detach(keyboard)
        }
        let keyboard = make(.chineseJapanese, .chinese, .default), proxy = keyboard.proxy
        expect(style(keyboard, "换行"), "default host displays newline")
        await type("nihao", keyboard); candidate(keyboard, "你好")?.sendActions(for: .touchUpInside); await settle()
        expect(proxy.editor.text == "你好" && marked(keyboard) == nil && style(keyboard, "换行"), "candidate selection restores host newline action")
        enter(keyboard).sendActions(for: .touchUpInside); await settle()
        expect(proxy.editor.text == "你好\n" && proxy.insertions.filter { $0 == "\n" }.count == 1 && proxy.host.sent.isEmpty, "return after candidate inserts one native newline")
        proxy.returnKeyType = .search; keyboard.textDidChange(proxy.editor)
        expect(style(keyboard, "搜索"), "host trait refresh changes footer to search")
        await type("shi", keyboard)
        expect(style(keyboard, "搜索"), "Chinese composition preserves host search label")
        for _ in 0..<3 { keyboard.didTapDelete() }
        expect(marked(keyboard) == nil && style(keyboard, "搜索"), "deleting composition restores search label")
        proxy.returnKeyType = .send; keyboard.textDidChange(proxy.editor)
        expect(style(keyboard, "发送"), "host trait refresh changes footer to send")
        await reset(keyboard); await type("nihao", keyboard)
        candidate(keyboard, "你好")?.sendActions(for: .touchUpInside); enter(keyboard).sendActions(for: .touchUpInside); await settle()
        expect(proxy.host.sent == ["你好"] && proxy.editor.text == "你好" && proxy.insertions.filter { $0 == "\n" }.count == 1, "return after selected candidate sends exactly once")
        await reset(keyboard); await type("nihao", keyboard)
        footer(keyboard).subviews.compactMap { $0 as? SKMainKeyButton }.first { $0.keyRole == .space }?.sendActions(for: .touchUpInside)
        expect(proxy.editor.text == "你好" && marked(keyboard) == nil && proxy.host.sent.isEmpty && !proxy.insertions.contains("\n"), "space still selects the first converted candidate")
        await reset(keyboard); await type("nihaoshijie", keyboard)
        let partial = candidate(keyboard, "你好")
        expect(partial != nil, "partial Chinese selection target is available")
        partial?.sendActions(for: .touchUpInside); await settle()
        expect(marked(keyboard)?.hasPrefix("你好") == true, "partial selection keeps chosen Chinese in the marked range")
        enter(keyboard).sendActions(for: .touchUpInside); await settle()
        expect(proxy.editor.text == "你好shijie" && marked(keyboard) == nil && proxy.host.sent.isEmpty && !proxy.insertions.contains("\n"), "return preserves selected Chinese and confirms only remaining raw code", proxy.editor.text ?? "nil")
        enter(keyboard).sendActions(for: .touchUpInside); await settle()
        expect(proxy.host.sent == ["你好shijie"] && proxy.insertions.filter { $0 == "\n" }.count == 1, "second return after partial confirmation sends once")
        await reset(keyboard); keyboard.didTapSwitchScheme(); keyboard.view.layoutIfNeeded()
        await type("nihkuijx", keyboard)
        let doublePartial = candidate(keyboard, "你好")
        doublePartial?.sendActions(for: .touchUpInside); await settle()
        enter(keyboard).sendActions(for: .touchUpInside); await settle()
        expect(doublePartial != nil && proxy.editor.text == "你好uijx" && marked(keyboard) == nil && proxy.host.sent.isEmpty && !proxy.insertions.contains("\n"), "double-pinyin partial return preserves selected Chinese and remaining code without sending", proxy.editor.text ?? "nil")
        do {
            let resources = Bundle.main.url(forResource: "RimeData", withExtension: "bundle")!
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent("return-japanese-\(UUID())")
            let japanese = try SKJapaneseEngine(resources: resources, userDirectory: directory)
            for (raw, kana) in [("nihon", "にほん"), ("toukyou", "とうきょう"), ("gakkou", "がっこう")] {
                var state = japanese.replaceInput(raw)
                expect(state.preedit == raw && state.candidates.count >= 3 && state.candidates[2].text == kana,
                       "\(raw): raw preedit and third kana candidate")
                for _ in 0..<3 { _ = japanese.selectCandidate(at: 2); state = japanese.replaceInput(raw) }
                let candidates = japanese.candidatePage(startingAt: 0, limit: 64).candidates
                expect(candidates.filter { $0.text == kana }.count == 1 && candidates[2].text == kana,
                       "\(raw): learned kana remains third without duplicate")
                expect(japanese.process(key: 0x20).committedText == state.candidates.first?.text,
                       "\(raw): space still commits the displayed first word")
            }
            let incomplete = japanese.replaceInput("gakk")
            expect(incomplete.preedit == "gakk" && japanese.process(key: 0xff0d).committedText == "gakk", "incomplete Japanese return preserves every original letter")
        } catch { expect(false, "Japanese focused engine loads", error.localizedDescription) }
        let failed = checks.filter { !($0["passed"] as! Bool) }
        let report = "\(failed.isEmpty ? "PASS" : "FAIL") \(checks.count) focused return-key checks\n" + failed.map { "\($0["label"]!): \($0["detail"]!)" }.joined(separator: "\n")
        let output = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        try! JSONSerialization.data(withJSONObject: ["checks": checks, "failures": failed.count], options: [.prettyPrinted,.sortedKeys]).write(to: output.appendingPathComponent("return-results.json"))
        try! report.write(to: output.appendingPathComponent("result.txt"), atomically: true, encoding: .utf8)
    }
}
