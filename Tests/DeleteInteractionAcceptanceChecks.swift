import UIKit

// Independent acceptance: actual UIKit text operations and real run-loop timers.
// Touch control events are programmatically delivered; this is not a claim of
// physical-finger or undocumented Apple repeat-timing equivalence.
private final class DeleteEditorProxy: NSObject, UITextDocumentProxy {
    let editor = UITextView()
    var documentIdentifier = UUID()
    var documentAvailable = true
    override func perform(_ selector: Selector!) -> Unmanaged<AnyObject>! {
        if selector == #selector(getter: UITextDocumentProxy.documentIdentifier), !documentAvailable { return nil }
        return super.perform(selector)
    }
    var frozenContext: String?
    var contextWindow: Int?
    var nilContext = false
    var deleteCalls = 0
    var onDelete: (() -> Void)?
    var documentContextBeforeInput: String? {
        if nilContext { return nil }
        if let frozenContext { return frozenContext }
        let text = (editor.text ?? "") as NSString
        let prefix = text.substring(to: min(editor.selectedRange.location, text.length))
        return contextWindow.map { String(prefix.suffix($0)) } ?? prefix
    }
    var documentContextAfterInput: String? {
        let text = (editor.text ?? "") as NSString
        return text.substring(from: min(NSMaxRange(editor.selectedRange), text.length))
    }
    var selectedText: String? { editor.selectedTextRange.flatMap { editor.text(in: $0) } }
    var documentInputMode: UITextInputMode? { editor.textInputMode }
    var hasText: Bool { editor.hasText }
    func insertText(_ text: String) { editor.insertText(text) }
    func deleteBackward() { deleteCalls += 1; editor.deleteBackward(); onDelete?() }
    func adjustTextPosition(byCharacterOffset offset: Int) {}
    func setMarkedText(_ text: String, selectedRange: NSRange) { editor.setMarkedText(text, selectedRange: selectedRange) }
    func unmarkText() { editor.unmarkText() }
}
private final class DeleteKeyboard: KeyboardViewController {
    let proxy = DeleteEditorProxy()
    override var textDocumentProxy: UITextDocumentProxy { proxy }
}
private func descendants(_ view: UIView) -> [UIView] { [view] + view.subviews.flatMap(descendants) }
private func visible(_ view: UIView) -> Bool {
    var next: UIView? = view
    while let v = next { if v.isHidden || v.alpha <= 0.01 { return false }; next = v.superview }
    return true
}

@main final class DeleteInteractionAcceptanceChecks: UIResponder, UIApplicationDelegate {
    var window: UIWindow?
    var checks: [[String: Any]] = []
    var traces: [[String: Any]] = []
    func expect(_ value: Bool, _ label: String, _ detail: String = "") {
        checks.append(["label": label, "passed": value, "detail": detail])
        print("\(value ? "PASS" : "FAIL") \(label) \(detail)")
    }
    @MainActor func wait(_ seconds: Double) async { try? await Task.sleep(nanoseconds: UInt64(seconds * 1e9)) }
    @MainActor func until(_ predicate: () -> Bool, timeout: Double) async {
        let limit = Date().addingTimeInterval(timeout)
        while !predicate() && Date() < limit { await wait(0.02) }
    }
    static func main() { UIApplicationMain(CommandLine.argc, CommandLine.unsafeArgv, nil, NSStringFromClass(Self.self)) }
    func application(_ application: UIApplication, didFinishLaunchingWithOptions options: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        let window = UIWindow(frame: UIScreen.main.bounds), host = UIViewController()
        host.view.backgroundColor = .systemBackground; window.rootViewController = host
        window.makeKeyAndVisible(); self.window = window
        Task { @MainActor in await run(host) }
        return true
    }
    @MainActor func run(_ host: UIViewController) async {
        let output = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        func snapshot(_ name: String) {
            host.view.layoutIfNeeded()
            let image = UIGraphicsImageRenderer(bounds: host.view.bounds).image { host.view.layer.render(in: $0.cgContext) }
            try? image.pngData()?.write(to: output.appendingPathComponent(name + ".png"))
        }
        let holder = UIView(frame: CGRect(x: 10, y: 20, width: 240, height: 70)); host.view.addSubview(holder)
        let main = SKMainKeyButton(title: "⌫", role: .function)
        main.frame = CGRect(x: 0, y: 0, width: 55, height: 50); holder.addSubview(main)
        let number = SKIMKeyButtonWithoutPopUpView(title: "⌫", width: 55)
        number.frame = CGRect(x: 80, y: 0, width: 55, height: 50); holder.addSubview(number)
        var events: [(Double, Bool)] = []; var start = Date()
        var response: (Int) -> SKDeleteFeedback = { _ in .continueRepeating }
        let action: (Bool) -> SKDeleteFeedback = { word in
            events.append((Date().timeIntervalSince(start), word)); return response(events.count)
        }
        main.onDelete = action; number.onDelete = action
        for (name, key) in [("main", main as UIButton), ("number", number as UIButton)] {
            let normal = key.backgroundColor
            key.isHighlighted = true
            expect(key.backgroundColor != normal, "\(name) delete has visible highlighted state")
            key.isHighlighted = false
            expect(key.backgroundColor == normal, "\(name) highlight returns to normal color")
        }
        func reset() { SKDeleteKeyInteraction.cancelActive(); events = []; start = Date(); response = { _ in .continueRepeating } }
        func save(_ label: String) { traces.append(["label": label, "events": events.map { ["seconds": $0.0, "byWord": $0.1] as [String: Any] }]) }
        for (name, button) in [("main", main as UIControl), ("number", number as UIControl)] {
            reset(); button.sendActions(for: .touchDown)
            expect(events.count == 1 && !events[0].1, "\(name) deletes once on press")
            button.sendActions(for: .touchUpInside); await wait(0.55)
            expect(events.count == 1, "\(name) release has no second delete or leftover timer")
            reset(); button.sendActions(for: .touchDown); await wait(0.25)
            expect(events.count == 1, "\(name) brief hold has initial delay")
            await until({ events.count >= 4 }, timeout: 1.1)
            button.sendActions(for: .touchCancel)
            expect(events.count >= 4 && events[1].0 >= 0.40, "\(name) real timer repeats after delay")
            let count = events.count; await wait(0.20)
            expect(events.count == count, "\(name) touchCancel stops repetitions")
            save("\(name)-repeat")
            reset(); button.sendActions(for: .touchDown); await wait(0.15)
            button.sendActions(for: .touchDragExit); await wait(0.55)
            expect(events.count == 1, "\(name) drag exit pauses")
            button.sendActions(for: .touchDragEnter)
            expect(events.count == 1, "\(name) reentry does not immediately delete again")
            await until({ events.count >= 2 }, timeout: 0.7)
            button.sendActions(for: .touchUpOutside)
            expect(events.count >= 2, "\(name) reentry resumes remaining cadence")
            let resumed = events.count; await wait(0.2)
            expect(events.count == resumed, "\(name) release outside stops")
            reset()
            let activated = (button as! UIButton).accessibilityActivate()
            await wait(0.55)
            expect(activated && events.count == 1, "\(name) VoiceOver activation deletes once without timer")
        }
        reset(); main.sendActions(for: .touchDown)
        await until({ events.filter { $0.1 }.count >= 2 }, timeout: 4)
        main.sendActions(for: .touchUpInside)
        let firstWord = events.firstIndex(where: { $0.1 })
        expect(firstWord == 17, "sustained hold reaches word stage after sixteen character repeats", "firstWordEvent=\(String(describing: firstWord))")
        let wordTimes = events.filter { $0.1 }.map { $0.0 }
        expect(wordTimes.count >= 2 && wordTimes[1] - wordTimes[0] >= 0.13, "word-stage repeats use the slower bounded cadence")
        save("acceleration")
        reset(); response = { $0 == 2 ? .restartDelay : .continueRepeating }
        main.sendActions(for: .touchDown); await until({ events.count >= 3 }, timeout: 1.7)
        main.sendActions(for: .touchCancel)
        expect(events.count >= 3 && events[2].0 - events[1].0 >= 0.40 && !events[2].1, "composition boundary feedback restarts delay and character stage")
        save("boundary-delay")
        reset(); response = { _ in .stop }; main.sendActions(for: .touchDown); await wait(0.55)
        expect(events.count == 1, "stop feedback ends gesture")
        for reason in ["disabled", "hidden-parent", "alpha-parent", "interaction-parent", "removed", "app-inactive", "scene-inactive", "second-control"] {
            reset(); main.sendActions(for: .touchDown)
            switch reason {
            case "disabled": main.isEnabled = false
            case "hidden-parent": holder.isHidden = true
            case "alpha-parent": holder.alpha = 0
            case "interaction-parent": holder.isUserInteractionEnabled = false
            case "removed": main.removeFromSuperview()
            case "app-inactive": NotificationCenter.default.post(name: UIApplication.willResignActiveNotification, object: nil)
            case "scene-inactive": NotificationCenter.default.post(name: UIScene.willDeactivateNotification, object: nil)
            default: number.sendActions(for: .touchDown); number.sendActions(for: .touchUpInside)
            }
            let count = events.count; await wait(0.58)
            expect(events.count == count, "\(reason) cancels held deletion")
            main.isEnabled = true; holder.isHidden = false; holder.alpha = 1; holder.isUserInteractionEnabled = true
            if main.superview == nil { holder.addSubview(main) }
        }
        reset(); holder.removeFromSuperview()

        // The oracle is UIKit itself. These checks do not assume that one
        // backward edit always removes one Swift Character.
        let proxy = DeleteEditorProxy(), oracle = UITextView(), connection = SKMarkedTextConnection()
        proxy.editor.frame = CGRect(x: 10, y: 90, width: 180, height: 70)
        oracle.frame = CGRect(x: 200, y: 90, width: 180, height: 70)
        host.view.addSubview(proxy.editor); host.view.addSubview(oracle)
        func set(_ editor: UITextView, _ text: String, range: NSRange? = nil) {
            editor.unmarkText(); editor.text = text; editor.selectedRange = range ?? NSRange(location: (text as NSString).length, length: 0)
            editor.layoutIfNeeded()
        }
        for text in ["中文", "hello", "123", "甲，", "A\n", "A🙂", "A👨‍👩‍👧‍👦", "A👍🏽", "A🇯🇵", "Ae\u{301}", "A1️⃣", "A👩🏽‍💻", "Aक्‍ष", ""] {
            set(proxy.editor, text); set(oracle, text); await wait(0.02)
            oracle.deleteBackward(); connection.deleteBackward(in: proxy)
            expect(proxy.editor.text == oracle.text && proxy.editor.selectedRange == oracle.selectedRange, "native character deletion matches UIKit: \(text)", proxy.editor.text ?? "nil")
        }
        for text in ["A👨‍👩‍👧‍👦B", "甲中文乙", "A👍🏽B", "Ae\u{301}B"] {
            let selection = NSRange(location: 1, length: (text as NSString).length - 2)
            set(proxy.editor, text, range: selection); set(oracle, text, range: selection); await wait(0.02)
            proxy.deleteCalls = 0; oracle.deleteBackward(); connection.deleteBackward(in: proxy, byWord: true)
            expect(proxy.editor.text == oracle.text && proxy.deleteCalls == 1, "selected range is one native edit even in word stage: \(text)")
        }
        for (text, expected) in [("hello world", "hello "), ("hello world   ", "hello "), ("hello!", "hello"), ("hello\n", "hello"), ("hello\nworld", "hello\n"), ("   ", ""), ("x " + String(repeating: "a", count: 40), "x " + String(repeating: "a", count: 39))] {
            set(proxy.editor, text); await wait(0.02); proxy.deleteCalls = 0
            connection.deleteBackward(in: proxy, byWord: true)
            expect(proxy.editor.text == expected && proxy.deleteCalls <= 32, "word deletion respects boundary/burst cap: \(text)", proxy.editor.text ?? "nil")
        }
        for (kind, setup) in [("stale-context", 0), ("moving-window", 1), ("changed-document", 2), ("nil-context", 3), ("nil-document-id", 4)] {
            set(proxy.editor, "hello world"); await wait(0.02); proxy.deleteCalls = 0
            switch setup {
            case 0: proxy.frozenContext = "hello world"
            case 1: proxy.contextWindow = 5
            case 2: proxy.onDelete = { proxy.documentIdentifier = UUID() }
            case 3: proxy.nilContext = true
            default: proxy.documentAvailable = false
            }
            connection.deleteBackward(in: proxy, byWord: true)
            expect(proxy.deleteCalls == 1 && proxy.editor.text == "hello worl", "\(kind) never bursts against stale assumptions")
            proxy.frozenContext = nil; proxy.contextWindow = nil; proxy.onDelete = nil; proxy.nilContext = false; proxy.documentAvailable = true
        }
        proxy.editor.removeFromSuperview(); oracle.removeFromSuperview()

        // Exercise production keyboard/controller/session/marked-text integration.
        UserDefaults.standard.set("chineseJapanese", forKey: SKInputScheme.preferenceKey)
        UserDefaults.standard.set("chinese", forKey: SKChineseJapaneseMode.preferenceKey)
        let keyboard = DeleteKeyboard(), editor = keyboard.proxy.editor
        editor.frame = CGRect(x: 10, y: 90, width: 380, height: 120); editor.inputView = UIView(frame: .zero)
        editor.autocorrectionType = .no; editor.spellCheckingType = .no
        host.view.addSubview(editor); editor.becomeFirstResponder()
        host.addChild(keyboard); host.view.addSubview(keyboard.view); keyboard.didMove(toParent: host)
        keyboard.view.frame = CGRect(x: 0, y: 280, width: 402, height: 260); keyboard.view.layoutIfNeeded()
        func deleteKey() -> UIButton { descendants(keyboard.view).compactMap { $0 as? UIButton }.first { $0.accessibilityLabel == "删除" && visible($0) }! }
        func mark() -> String? { editor.markedTextRange.flatMap { editor.text(in: $0) } }
        func resetEditor(_ text: String = "") { keyboard.textWillChange(editor); set(editor, text) }
        func type(_ value: String) async {
            await wait(0.02)
            for c in value { keyboard.didTapKey(String(c)); await wait(0.01) }
        }
        for scheme in ["pinyin", "shuangpin"] {
            if scheme == "shuangpin" { keyboard.didTapSwitchScheme() }
            resetEditor("正文"); await type(scheme == "pinyin" ? "nihao" : "nihc")
            let rawCount = scheme == "pinyin" ? 5 : 4
            for step in 0..<rawCount {
                let feedback = keyboard.didDeleteBackward(byWord: true)
                expect(editor.text.hasPrefix("正文"), "\(scheme) composition delete \(step) preserves surrounding body")
                if step == rawCount - 1 { expect(feedback == .restartDelay && mark() == nil && editor.text == "正文", "\(scheme) empty composition signals fresh body delay") }
            }
            _ = keyboard.didDeleteBackward(byWord: false)
            expect(editor.text == "正", "\(scheme) following deletion reaches body once")
            resetEditor("abcdef"); let key = deleteKey(); key.sendActions(for: .touchDown)
            if scheme == "pinyin" { key.isHighlighted = true; snapshot("delete-main-pressed") }
            key.sendActions(for: .touchUpInside); key.isHighlighted = false
            if scheme == "pinyin" { snapshot("delete-main-released") }
            expect(editor.text == "abcde", "\(scheme) actual key tap has no duplicate controller action")
            keyboard.didTapSwitchLayout(to: .number); keyboard.view.layoutIfNeeded()
            resetEditor("abcdef"); let numberKey = deleteKey(); numberKey.sendActions(for: .touchDown)
            await wait(0.60)
            if scheme == "pinyin" { numberKey.isHighlighted = true; snapshot("delete-number-pressed") }
            numberKey.sendActions(for: .touchUpInside); numberKey.isHighlighted = false
            if scheme == "pinyin" { snapshot("delete-number-released") }
            expect((editor.text ?? "").count <= 4, "\(scheme) number-page actual delete repeats")
            keyboard.didTapSwitchLayout(to: .alphabet); keyboard.view.layoutIfNeeded()
        }
        keyboard.didTapSwitchScheme() // back to full pinyin
        resetEditor("正文"); await type("ni")
        let held = deleteKey(); held.sendActions(for: .touchDown)
        await wait(0.52)
        expect(editor.text == "正文" && mark() == nil, "held deletion stops at composition boundary for fresh delay")
        await until({ editor.text == "正" }, timeout: 0.8)
        held.sendActions(for: .touchUpInside)
        expect(editor.text == "正", "held deletion resumes body after boundary pause")
        for change in ["other-key", "layout", "scheme", "cursor", "disappear"] {
            resetEditor("abcdef"); let key = deleteKey(); key.sendActions(for: .touchDown)
            switch change {
            case "other-key": keyboard.didTapKey("！")
            case "layout": keyboard.didTapSwitchLayout(to: .number)
            case "scheme": keyboard.didTapSwitchScheme()
            case "cursor": keyboard.textWillChange(editor); editor.selectedRange = NSRange(location: 0, length: 0)
            default: keyboard.viewWillDisappear(false)
            }
            let text = editor.text; await wait(0.58)
            expect(editor.text == text, "controller \(change) cancels held key")
            keyboard.didTapSwitchLayout(to: .alphabet); keyboard.view.layoutIfNeeded()
        }

        do {
            let resources = Bundle.main.url(forResource: "RimeData", withExtension: "bundle")!
            let japanese = try SKJapaneseEngine(resources: resources, userDirectory: output.appendingPathComponent("delete-japanese-\(UUID())"))
            for (input, expected) in [("ky", "k"), ("ka", ""), ("kya", "き"), ("gakkou", "がっこ"), ("galtu", "が"), ("gakk", "がっ"), ("kk", "っ"), ("ss", "っ"), ("tt", "っ"), ("ssa", "っ"), ("kky", "っk"), ("sshi", "っ"), ("kanpai", "かんぱ"), ("shin'you", "しんよ"), ("ko-hi-", "こーひ"), ("nihon", "にほ"), ("nna", "ん"), ("nn", ""), ("va", "ゔ")] {
                _ = japanese.replaceInput(input)
                let result = japanese.process(key: 0xff08)
                expect(result.preedit == expected && result.committedText.isEmpty, "Japanese deletes pending letter or visible kana: \(input)", result.preedit)
                var last = result
                for _ in 0..<20 {
                    if last.input.isEmpty { break }
                    last = japanese.process(key: 0xff08)
                }
                expect(last.input.isEmpty && last.preedit.isEmpty, "Japanese \(input) deletion reaches empty without stalling")
            }
            let special = japanese.replaceInput("www")
            expect(special.preedit == "wっw", "imported literal/carry rule is represented before deletion")
            for expected in ["wっ", "w", ""] {
                let deleted = japanese.process(key: 0xff08)
                expect(deleted.preedit == expected, "literal-prefix consecutive deletion preserves visible units: \(expected)", deleted.preedit)
            }
            _ = japanese.replaceInput("www"); _ = japanese.process(key: 0xff08)
            let continued = japanese.process(key: 97)
            expect(continued.preedit == "wっあ", "typing after literal-prefix deletion does not reinterpret completed Latin text", continued.preedit)
            expect(japanese.process(key: 0xff08).preedit == "wっ", "deleting appended kana restores frozen literal prefix")
            let replaced = japanese.replaceInput("ka")
            expect(replaced.preedit == "か", "replaceInput resets frozen prefix")
            _ = japanese.replaceInput("www"); _ = japanese.process(key: 0xff08); _ = japanese.clear()
            expect(japanese.process(key: 97).preedit == "あ", "clear resets frozen prefix before new input")
            _ = japanese.replaceInput("www"); _ = japanese.process(key: 0xff08)
            let beforeCommit = japanese.candidatePage(startingAt: 0, limit: 1).candidates.first?.text
            let committedLiteral = japanese.commit()
            expect(committedLiteral.input.isEmpty && committedLiteral.preedit.isEmpty && !committedLiteral.committedText.isEmpty && (beforeCommit == nil || committedLiteral.committedText == beforeCommit), "literal-prefix candidate commit clears state")
            expect(japanese.process(key: 97).preedit == "あ", "candidate commit does not leak frozen prefix into next composition")
        } catch { expect(false, "Japanese delete engine loads", error.localizedDescription) }
        keyboard.viewWillDisappear(false)
        keyboard.view.removeFromSuperview(); editor.removeFromSuperview()
        UserDefaults.standard.set("chineseJapanese", forKey: SKInputScheme.preferenceKey)
        UserDefaults.standard.set("japanese", forKey: SKChineseJapaneseMode.preferenceKey)
        let jpKeyboard = DeleteKeyboard(), jpEditor = jpKeyboard.proxy.editor
        jpEditor.frame = CGRect(x: 10, y: 90, width: 380, height: 120); jpEditor.inputView = UIView(frame: .zero)
        jpEditor.autocorrectionType = .no; jpEditor.spellCheckingType = .no
        host.view.addSubview(jpEditor); jpEditor.becomeFirstResponder()
        host.addChild(jpKeyboard); host.view.addSubview(jpKeyboard.view); jpKeyboard.didMove(toParent: host)
        jpKeyboard.view.frame = CGRect(x: 0, y: 280, width: 402, height: 260); jpKeyboard.view.layoutIfNeeded()
        set(jpEditor, "正文"); await wait(0.03)
        for c in "kya" { jpKeyboard.didTapKey(String(c)); await wait(0.02) }
        expect(jpEditor.text == "正文きゃ" && jpEditor.markedTextRange != nil, "Japanese controller presents kana in host marked range")
        _ = jpKeyboard.didDeleteBackward(byWord: false)
        expect(jpEditor.text == "正文き" && jpEditor.markedTextRange != nil, "Japanese host deletes small kana without leaking romaji")
        let jpBoundary = jpKeyboard.didDeleteBackward(byWord: true)
        expect(jpBoundary == .restartDelay && jpEditor.text == "正文" && jpEditor.markedTextRange == nil, "Japanese last kana clears marked range and protects body")
        for c in "gakk" { jpKeyboard.didTapKey(String(c)); await wait(0.02) }
        _ = jpKeyboard.didDeleteBackward(byWord: false)
        expect(jpEditor.text == "正文がっ", "Japanese host pending deletion preserves completed sokuon")
        _ = jpKeyboard.didDeleteBackward(byWord: false)
        expect(jpEditor.text == "正文が", "Japanese host next delete removes sokuon itself")
        _ = jpKeyboard.didDeleteBackward(byWord: false)
        expect(jpEditor.text == "正文" && jpEditor.markedTextRange == nil, "Japanese composition reaches empty without body loss")
        _ = jpKeyboard.didDeleteBackward(byWord: false)
        expect(jpEditor.text == "正", "Japanese next native delete reaches committed body")
        let image = UIGraphicsImageRenderer(bounds: host.view.bounds).image { host.view.layer.render(in: $0.cgContext) }
        try? image.pngData()?.write(to: output.appendingPathComponent("delete-acceptance-host.png"))
        let failures = checks.filter { !($0["passed"] as! Bool) }
        let report = "\(failures.isEmpty ? "PASS" : "FAIL") \(checks.count) independent deletion checks\n" + failures.map { "\($0["label"]!): \($0["detail"]!)" }.joined(separator: "\n")
        let result: [String: Any] = ["checks": checks, "traces": traces, "failures": failures.count, "method": "Real UIKit editors, real timers, programmatic UIControl events. No private touch injection, physical-finger gesture, or claim of Apple's exact cadence."]
        try! JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted,.sortedKeys]).write(to: output.appendingPathComponent("deletion-results.json"))
        try! report.write(to: output.appendingPathComponent("result.txt"), atomically: true, encoding: .utf8)
    }
}
