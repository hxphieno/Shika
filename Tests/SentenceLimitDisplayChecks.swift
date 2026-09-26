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

@main final class SentenceLimitDisplayChecks: UIResponder, UIApplicationDelegate {
    var window: UIWindow?
    var failures: [String] = []
    var checks = 0
    func expect(_ value: Bool, _ name: String) { checks += 1; if !value { failures.append(name) } }
    static func main() { UIApplicationMain(CommandLine.argc, CommandLine.unsafeArgv, nil, NSStringFromClass(Self.self)) }
    func application(_ application: UIApplication, didFinishLaunchingWithOptions options: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        let window = UIWindow(frame: UIScreen.main.bounds)
        let host = UIViewController(); host.view.backgroundColor = .systemBackground
        window.rootViewController = host; window.makeKeyAndVisible(); self.window = window
        Task { @MainActor in await run(host) }; return true
    }
    @MainActor func run(_ host: UIViewController) async {
        let output = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        do {
            let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            try? FileManager.default.removeItem(at: support.appendingPathComponent("RimeUser"))
            UserDefaults.standard.set("chineseJapanese", forKey: SKInputScheme.preferenceKey)
            UserDefaults.standard.set("mixed", forKey: SKChineseJapaneseMode.preferenceKey)
            let raw = "haibiandianqiyanhuo"
            let engine = try SKConversionEngine(configuration: SKChineseJapaneseScheme.configuration(for: .mixed))
            for c in raw.unicodeScalars { _ = engine.process(key: Int32(c.value)) }
            var candidates: [SKCandidate] = [], cursor = 0
            for _ in 0..<30 {
                let page = engine.candidatePage(startingAt: cursor, limit: 13)
                candidates += page.candidates
                if !page.hasMore { break }; cursor = page.nextIndex
            }
            let visible = candidates.filter { SKCandidateGlyphCoverage().canDisplay($0.text) }
            expect(visible.filter { $0.consumedInputCount == raw.count }.count <= 6, "at most six full screenshot sentences across all pages")
            expect(visible.firstIndex { $0.text == "海边" } == 6, "海边 is seventh, immediately after six sentences")
            expect(visible.contains { $0.text == "海" }, "single-character prefix remains reachable")
            let controller = EditorKeyboard(), editor = controller.proxy.editor
            editor.frame = CGRect(x: 16, y: 120, width: host.view.bounds.width - 32, height: 150)
            editor.font = .systemFont(ofSize: 24); editor.autocorrectionType = .no; editor.spellCheckingType = .no
            editor.inputView = UIView(frame: .zero)
            host.view.addSubview(editor); editor.becomeFirstResponder()
            host.addChild(controller); host.view.addSubview(controller.view); controller.didMove(toParent: host)
            controller.view.frame = CGRect(x: 0, y: host.view.bounds.height - 360, width: host.view.bounds.width, height: 360)
            controller.view.backgroundColor = UIColor(white: 0.88, alpha: 1); controller.view.layoutIfNeeded()
            for c in raw { controller.didTapKey(String(c)); await Task.yield() }
            let panel = tree(controller.view).compactMap { $0 as? SKExpandedCandidatesView }.first!
            let grid = tree(panel).compactMap { $0 as? UICollectionView }.first!
            let expand = tree(controller.view).compactMap { $0 as? UIButton }.first { $0.accessibilityIdentifier == "candidates.expand" }!
            expand.sendActions(for: .touchUpInside)
            for _ in 0..<15 { panel.onLoadMore?(); await Task.yield() }
            controller.view.layoutIfNeeded(); grid.layoutIfNeeded()
            var labels: [String] = []
            for index in 0..<grid.numberOfItems(inSection: 0) {
                let path = IndexPath(item: index, section: 0)
                grid.scrollToItem(at: path, at: .centeredVertically, animated: false); grid.layoutIfNeeded()
                labels.append(grid.cellForItem(at: path)?.accessibilityLabel ?? "<missing>")
            }
            expect(labels == visible.map(\.text), "real expanded grid matches engine after all pages")
            grid.setContentOffset(.zero, animated: false); grid.layoutIfNeeded()
            let image = UIGraphicsImageRenderer(bounds: host.view.bounds).image { host.view.layer.render(in: $0.cgContext) }
            try image.pngData()!.write(to: output.appendingPathComponent("sentence-limit-ios.png"))
            if let position = labels.firstIndex(of: "海边") {
                grid.delegate?.collectionView?(grid, didSelectItemAt: IndexPath(item: position, section: 0))
                await Task.yield()
                expect(editor.text == "海边dianqiyanhuo", "prefix selection preserves pending raw tail in real UITextView")
                controller.didTapKey("\n"); await Task.yield()
                expect(editor.text == "海边dianqiyanhuo" && editor.markedTextRange == nil, "Return confirms prefix and raw tail once")
            } else { expect(false, "海边 cell exists") }
            let report: [String: Any] = ["platform": UIDevice.current.systemVersion, "input": raw,
                "checks": checks, "failures": failures, "candidates": visible.map { ["text": $0.text, "index": $0.index, "consumed": $0.consumedInputCount ?? -1] }]
            try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]).write(to: output.appendingPathComponent("sentence-limit-ios.json"))
        } catch { failures.append(String(describing: error)) }
        let result = failures.isEmpty ? "PASS \(checks) sentence limit iOS checks" : "FAIL " + failures.joined(separator: "\n")
        try! result.write(to: output.appendingPathComponent("result.txt"), atomically: true, encoding: .utf8)
    }
}
