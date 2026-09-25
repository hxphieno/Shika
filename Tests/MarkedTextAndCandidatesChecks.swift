import UIKit

/// Routes the production controller into a real UIKit text editor (not a string-only fake).
private final class EditorProxy: NSObject, UITextDocumentProxy {
    let editor = UITextView()
    var documentIdentifier = UUID()
    var documentAvailable = true
    override func perform(_ selector: Selector!) -> Unmanaged<AnyObject>! {
        if selector == #selector(getter: UITextDocumentProxy.documentIdentifier), !documentAvailable { return nil }
        return super.perform(selector)
    }
    var documentContextBeforeInput: String? { (editor.text as NSString).substring(to: min(editor.selectedRange.location, (editor.text as NSString).length)) }
    var documentContextAfterInput: String? { (editor.text as NSString).substring(from: min(NSMaxRange(editor.selectedRange), (editor.text as NSString).length)) }
    var selectedText: String? { editor.selectedTextRange.flatMap { editor.text(in: $0) } }
    var documentInputMode: UITextInputMode? { editor.textInputMode }
    var hasText: Bool { editor.hasText }
    func insertText(_ text: String) { editor.insertText(text) }
    func deleteBackward() { editor.deleteBackward() }
    func adjustTextPosition(byCharacterOffset offset: Int) {}
    func setMarkedText(_ text: String, selectedRange: NSRange) {
        editor.setMarkedText(text, selectedRange: selectedRange)
    }
    func unmarkText() { editor.unmarkText() }
}
private final class EditorKeyboard: KeyboardViewController {
    let proxy = EditorProxy()
    override var textDocumentProxy: UITextDocumentProxy { proxy }
}
private func tree(_ view: UIView) -> [UIView] { [view] + view.subviews.flatMap(tree) }

@main final class MarkedTextChecks: UIResponder, UIApplicationDelegate {
    var window: UIWindow?
    var failures: [String] = []
    var count = 0
    func expect(_ value: Bool, _ label: String) { count += 1; if !value { failures.append(label) }; print("\(value ? "PASS" : "FAIL") \(label)") }
    static func main() { UIApplicationMain(CommandLine.argc, CommandLine.unsafeArgv, nil, NSStringFromClass(Self.self)) }
    func application(_ application: UIApplication, didFinishLaunchingWithOptions options: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        let window = UIWindow(frame: UIScreen.main.bounds)
        let host = UIViewController();host.view.backgroundColor = .systemBackground
        window.rootViewController = host;window.makeKeyAndVisible();self.window = window
        Task { @MainActor in await self.run(host) }
        return true
    }
    @MainActor
    func run(_ host: UIViewController) async {
        let output = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        UserDefaults.standard.set("chineseJapanese", forKey: SKInputScheme.preferenceKey)
        let controller = EditorKeyboard(), editor = controller.proxy.editor
        editor.frame = CGRect(x: 16, y: 90, width: 370, height: 140)
        editor.font = .systemFont(ofSize: 24)
        editor.autocorrectionType = .no
        editor.spellCheckingType = .no
        editor.inputView = UIView(frame: .zero)
        host.view.addSubview(editor);editor.becomeFirstResponder()
        host.addChild(controller);host.view.addSubview(controller.view);controller.didMove(toParent: host)
        controller.view.frame = CGRect(x: 0, y: 260, width: 402, height: 260)
        controller.view.backgroundColor = UIColor(red: 223/255, green: 224/255, blue: 230/255, alpha: 1)
        controller.view.layoutIfNeeded()
        let bar = tree(controller.view).compactMap { $0 as? CandidateBarView }.first!
        let expand = tree(bar).compactMap { $0 as? UIButton }.first { $0.accessibilityIdentifier == "candidates.expand" }!
        let panel = tree(controller.view).compactMap { $0 as? SKExpandedCandidatesView }.first!
        let grid = tree(panel).compactMap { $0 as? UICollectionView }.first!
        // UIKit settles selection/text layout between real touch events. Give the
        // test host the same run-loop boundary, including after selecting text.
        func type(_ text: String) async {
            // Yield the main queue, not a nested run loop inside one callback.
            // Selection/layout notifications then settle between touch events.
            try? await Task.sleep(nanoseconds: 20_000_000)
            for c in text {
                controller.didTapKey(String(c))
                try? await Task.sleep(nanoseconds: 20_000_000)
            }
        }
        func mark() -> String? { editor.markedTextRange.flatMap { editor.text(in: $0) } }
        func candidate(_ title: String) -> UIButton? { tree(bar).compactMap { $0 as? UIButton }.first { $0.accessibilityLabel == title } }
        func snapshot(_ name: String) {
            controller.view.layoutIfNeeded();panel.layoutIfNeeded();grid.layoutIfNeeded()
            let image = UIGraphicsImageRenderer(bounds: host.view.bounds).image { host.view.layer.render(in: $0.cgContext) }
            try! image.pngData()!.write(to: output.appendingPathComponent(name + ".png"))
        }
        func reset() { controller.textWillChange(editor);editor.text = "";editor.selectedRange = NSRange(location: 0, length: 0) }
        expect(bar.bounds.height == 44,"candidate bar is one 44pt row")
        expect(!tree(bar).contains { $0.accessibilityIdentifier == "composition" },"candidate bar has no composition line")
        await type("nihao")
        expect(mark() != nil && editor.text.contains("ni"),"pinyin is marked in real UITextView")
        snapshot("marked-pinyin")
        candidate("你好")?.sendActions(for: .touchUpInside)
        expect(editor.text == "你好" && mark() == nil,"candidate replaces marked pinyin once")
        await type("shijie");controller.didTapKey(" ")
        expect(editor.text == "你好世界" && mark() == nil,"space replaces next marked phrase: \(editor.text ?? "nil")")
        controller.didTapDelete();expect(editor.text == "你好世","idle deletion deletes committed text: \(editor.text ?? "nil")")
        await type("nihao");controller.didTapDelete()
        expect(mark() != nil && !editor.text.hasSuffix("ni hao"),"backspace edits marked composition")
        for _ in 0..<4 { controller.didTapDelete() }
        expect(editor.text == "你好世" && mark() == nil,"deleting composition to empty preserves surrounding text: \(editor.text ?? "nil")")
        reset();await type("nihaoshijie");candidate("你好")?.sendActions(for: .touchUpInside)
        expect(mark()?.hasPrefix("你好") == true,"partial Chinese selection stays marked with remaining pinyin")
        controller.didTapKey(" ");expect(editor.text == "你好世界" && mark() == nil,"partial selection completes without duplication")
        reset();await type("ni")
        let originalMarked = mark()
        expand.sendActions(for: .touchUpInside);panel.layoutIfNeeded();grid.layoutIfNeeded()
        expect(!panel.isHidden && grid.numberOfItems(inSection: 0) > 8,"down arrow expands beyond first candidate page")
        expect(mark() == originalMarked,"expansion does not alter marked text")
        snapshot("expanded-candidates")
        let firstBatch = grid.numberOfItems(inSection: 0)
        grid.setContentOffset(CGPoint(x: 0, y: max(0, grid.contentSize.height - grid.bounds.height + 10)), animated: false)
        grid.layoutIfNeeded()
        expect(grid.numberOfItems(inSection: 0) > firstBatch,"scrolling loads more candidates automatically")
        expect(mark() == originalMarked,"scrolling more candidates preserves marked range")
        for width: CGFloat in [320, 402, 874] {
            controller.view.frame.size = CGSize(width: width, height: width > 600 ? 206 : 260)
            controller.view.setNeedsLayout();controller.view.layoutIfNeeded();panel.layoutIfNeeded();grid.layoutIfNeeded()
            expect(grid.visibleCells.allSatisfy { $0.frame.minX >= -0.1 && $0.frame.maxX <= grid.bounds.width + 0.1 },"expanded candidates fit width \(width)")
        }
        controller.view.frame.size = CGSize(width: 402, height: 260)
        controller.view.layoutIfNeeded();panel.layoutIfNeeded();grid.layoutIfNeeded()
        let item = IndexPath(item: 10, section: 0)
        grid.scrollToItem(at: item, at: .centeredVertically, animated: false);grid.layoutIfNeeded()
        let expected = grid.cellForItem(at: item)?.accessibilityLabel
        grid.delegate?.collectionView?(grid, didSelectItemAt: item)
        expect(expected != nil && editor.text == expected && mark() == nil,"expanded candidate replaces marked text")
        expect(panel.isHidden,"selecting expanded candidate restores keyboard")
        reset();await type("nihoa");let correction = candidate("你好")
        expand.sendActions(for: .touchUpInside);expand.sendActions(for: .touchUpInside)
        // Fetch the current button after candidate browsing rebuilds the strip.
        expect(correction != nil,"typo correction is available")
        candidate("你好")?.sendActions(for: .touchUpInside)
        expect(editor.text == "你好" && mark() == nil,"correction survives expand-collapse and replaces typo")
        reset();controller.didTapSwitchScheme();await type("nihc")
        expect(mark() != nil,"double-pinyin also uses marked text")
        controller.didTapKey("，");expect(editor.text == "你好，" && mark() == nil,"punctuation confirms marked double-pinyin")
        await type("nihc");controller.didTapSwitchLayout(to: .number)
        expect(editor.text == "你好，你好" && mark() == nil,"number-page switch confirms composition")
        controller.didTapSwitchLayout(to: .alphabet)
        reset();await type("nihc");controller.didTapKey("\n")
        expect(editor.text == "你好\n" && mark() == nil,"newline confirms marked text then inserts newline")
        reset();await type("ni");let visible = editor.text
        controller.textWillChange(editor)
        expect(editor.text == visible && mark() == nil,"host cursor change keeps visible text and releases composition")
        editor.selectedRange = NSRange(location: 0, length: 0);await type("nihc");controller.didTapKey(" ")
        expect(editor.text == "你好" + (visible ?? ""),"new composition after cursor movement does not erase old text")
        reset();editor.text = "替换🙂这里";editor.layoutIfNeeded();editor.selectedRange = NSRange(location: 0, length: 2)
        await type("nihc");controller.didTapKey(" ")
        expect(editor.text == "你好🙂这里" && mark() == nil,"selected text replacement preserves emoji and surrounding text: \(editor.text ?? "nil")")
        reset();await type("nihc");controller.didTapKey(" ");snapshot("confirmed-text")
        let disconnected = EditorProxy(), connection = SKMarkedTextConnection()
        disconnected.documentAvailable = false
        connection.releaseComposition(in: disconnected)
        connection.updateComposition("", in: disconnected)
        connection.updateComposition("ni", in: disconnected)
        expect(disconnected.editor.text.isEmpty,"detached proxy with nil document identity does not trap or insert")
        disconnected.documentAvailable = true
        connection.updateComposition("ni", in: disconnected)
        disconnected.documentAvailable = false
        connection.releaseComposition(in: disconnected)
        expect(disconnected.editor.text == "ni","detaching an active document does not erase its text")
        let report = (failures.isEmpty ? "PASS " : "FAIL ") + "\(count) marked-text and expanded-candidate checks\n" + failures.joined(separator: "\n")
        try! report.write(to: output.appendingPathComponent("result.txt"), atomically: true, encoding: .utf8)
    }
}
