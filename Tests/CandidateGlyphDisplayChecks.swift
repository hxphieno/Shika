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

@main final class CandidateGlyphDisplayChecks: UIResponder, UIApplicationDelegate {
    var window: UIWindow?
    var failures: [String] = []
    var checks = 0
    func expect(_ value: Bool, _ label: String) { checks += 1; if !value { failures.append(label) } }
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
            // This executable is an isolated temporary test host, never the app.
            let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            try? FileManager.default.removeItem(at: support.appendingPathComponent("RimeUser"))
            let coverage = SKCandidateGlyphCoverage()
            let fixture = Bundle.main.url(forResource: "CandidateGlyphCases", withExtension: "json")!
            let fontCases = try JSONSerialization.jsonObject(with: Data(contentsOf: fixture)) as! [[String: String]]
            var fontResults: [[String: Any]] = []
            for item in fontCases {
                let visible = coverage.canDisplay(item["text"]!)
                if item["expect"] == "preserve-normal-display" { expect(visible, "preserve " + item["id"]!) }
                fontResults.append(["id": item["id"]!, "text": item["text"]!, "visible": visible])
            }
            let baseEngine = try SKConversionEngine(configuration: SKInputScheme.shuangpin.configuration)
            let baseline = SKInputSession(engine: baseEngine, configuration: SKInputScheme.shuangpin.configuration,
                insertText: { _ in }, deleteText: {})
            for c in "dmbodnbo" { baseline.type(String(c)) }
            for _ in 0..<20 where !baseline.state.isLastPage { baseline.loadMoreCandidates() }
            let raw = baseline.state.candidates
            let expected = raw.filter { coverage.canDisplay($0.text) }
            expect(raw.count > expected.count, "screenshot input reproduces missing-font candidates on iOS")
            expect(expected.contains { $0.text.unicodeScalars.contains { $0.value > 0xffff } }, "displayable supplementary Han survives")
            UserDefaults.standard.set("shuangpin", forKey: SKInputScheme.preferenceKey)
            let controller = EditorKeyboard(), editor = controller.proxy.editor
            editor.frame = CGRect(x: 16, y: 120, width: host.view.bounds.width - 32, height: 120)
            editor.font = .systemFont(ofSize: 24); editor.autocorrectionType = .no; editor.spellCheckingType = .no
            editor.inputView = UIView(frame: .zero)
            host.view.addSubview(editor); editor.becomeFirstResponder()
            host.addChild(controller); host.view.addSubview(controller.view); controller.didMove(toParent: host)
            controller.view.frame = CGRect(x: 0, y: 310, width: host.view.bounds.width, height: 310)
            controller.view.backgroundColor = UIColor(white: 0.88, alpha: 1); controller.view.layoutIfNeeded()
            for c in "dmbodnbo" { controller.didTapKey(String(c)); try? await Task.sleep(nanoseconds: 10_000_000) }
            let panel = tree(controller.view).compactMap { $0 as? SKExpandedCandidatesView }.first!
            let grid = tree(panel).compactMap { $0 as? UICollectionView }.first!
            let expand = tree(controller.view).compactMap { $0 as? UIButton }.first { $0.accessibilityIdentifier == "candidates.expand" }!
            expand.sendActions(for: .touchUpInside)
            for _ in 0..<12 { panel.onLoadMore?(); try? await Task.sleep(nanoseconds: 20_000_000) }
            controller.view.layoutIfNeeded(); grid.layoutIfNeeded()
            let count = grid.numberOfItems(inSection: 0)
            var labels: [String] = []
            for index in 0..<count {
                let path = IndexPath(item: index, section: 0)
                grid.scrollToItem(at: path, at: .centeredVertically, animated: false)
                grid.layoutIfNeeded()
                labels.append(grid.cellForItem(at: path)?.accessibilityLabel ?? "<not visible>")
            }
            expect(labels == expected.map(\.text), "real controller shows every displayable candidate in original order")
            expect(labels.allSatisfy(coverage.canDisplay), "no LastResort candidates in real expanded UI")
            func snapshot(_ name: String) {
                host.view.layoutIfNeeded(); grid.layoutIfNeeded()
                let image = UIGraphicsImageRenderer(bounds: host.view.bounds).image { host.view.layer.render(in: $0.cgContext) }
                try! image.pngData()!.write(to: output.appendingPathComponent(name))
            }
            grid.setContentOffset(CGPoint(x: 0, y: max(0, grid.contentSize.height - grid.bounds.height)), animated: false)
            snapshot("glyph-filtered-ios.png")
            // Render the original candidates through exactly the same grid to
            // make the before/after comparison independent of screenshot tools.
            var original = baseline.state; original.isLastPage = true
            panel.update(original); grid.layoutIfNeeded()
            grid.setContentOffset(CGPoint(x: 0, y: max(0, grid.contentSize.height - grid.bounds.height)), animated: false)
            snapshot("glyph-original-ios.png")
            panel.onLoadMore?(); try? await Task.sleep(nanoseconds: 10_000_000)
            // Verify actual controller wiring for selection after removed IDs.
            panel.update(SKEngineState(input: "dmbodnbo", candidates: expected))
            if let position = expected.indices.last {
                grid.delegate?.collectionView?(grid, didSelectItemAt: IndexPath(item: position, section: 0))
                try? await Task.sleep(nanoseconds: 30_000_000)
                expect(editor.text.contains(expected[position].text), "selecting surviving late native ID inserts its exact text")
            }
            let report: [String: Any] = ["platform": UIDevice.current.systemVersion, "rawCount": raw.count,
                "visibleCount": expected.count, "removedCount": raw.count - expected.count,
                "raw": raw.map { ["index": $0.index, "text": $0.text, "visible": coverage.canDisplay($0.text)] as [String: Any] },
                "fontResults": fontResults, "checks": checks, "failures": failures]
            try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]).write(to: output.appendingPathComponent("glyph-report.json"))
        } catch { failures.append(String(describing: error)) }
        let result = failures.isEmpty ? "PASS \(checks) iOS glyph/UI checks" : "FAIL " + failures.joined(separator: "\n")
        try! result.write(to: output.appendingPathComponent("result.txt"), atomically: true, encoding: .utf8)
    }
}
