import UIKit
import Darwin

private func footprint() -> UInt64 {
    var info = task_vm_info_data_t()
    var size = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
    let result = withUnsafeMutablePointer(to: &info) { pointer in
        pointer.withMemoryRebound(to: integer_t.self, capacity: Int(size)) {
            task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &size)
        }
    }
    return result == KERN_SUCCESS ? info.phys_footprint : 0
}
private final class LexiconProxy: NSObject, UITextDocumentProxy {
    let editor = UITextView()
    var documentIdentifier = UUID()
    var documentContextBeforeInput: String? { editor.text }
    var documentContextAfterInput: String? { "" }
    var selectedText: String? { nil }
    var documentInputMode: UITextInputMode? { editor.textInputMode }
    var hasText: Bool { editor.hasText }
    func insertText(_ text: String) { editor.insertText(text) }
    func deleteBackward() { editor.deleteBackward() }
    func adjustTextPosition(byCharacterOffset offset: Int) {}
    func setMarkedText(_ text: String, selectedRange: NSRange) { editor.setMarkedText(text, selectedRange: selectedRange) }
    func unmarkText() { editor.unmarkText() }
}
private final class LexiconKeyboard: KeyboardViewController {
    let proxy = LexiconProxy()
    override var textDocumentProxy: UITextDocumentProxy { proxy }
}
private func views(_ root: UIView) -> [UIView] { [root] + root.subviews.flatMap(views) }

@main final class LexiconRuntimeChecks: UIResponder, UIApplicationDelegate {
    var window: UIWindow?
    private var failures: [String] = []
    private var samples: [[String: Any]] = []
    private var timings: [Double] = []
    private var assertions = 0
    private var output: URL { FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0] }
    static func main() { UIApplicationMain(CommandLine.argc, CommandLine.unsafeArgv, nil, NSStringFromClass(Self.self)) }
    func expect(_ condition: Bool, _ label: String) { assertions += 1; if !condition { failures.append(label) } }
    func sample(_ phase: String) { samples.append(["phase": phase, "physicalFootprintBytes": footprint()]) }
    func application(_ application: UIApplication, didFinishLaunchingWithOptions options: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        let window = UIWindow(frame: UIScreen.main.bounds), host = UIViewController()
        host.view.backgroundColor = .systemBackground
        window.rootViewController = host; window.makeKeyAndVisible(); self.window = window
        Task { @MainActor in await run(host) }
        return true
    }
    @MainActor func run(_ host: UIViewController) async {
        sample("before-engine")
        do {
            let modes: [(SKInputConfiguration, String, String)] = [
                (SKChineseJapaneseScheme.configuration(for: .chinese), "sihua", "丝滑"),
                (SKInputScheme.shuangpin.configuration, "sihx", "丝滑"),
                (SKChineseJapaneseScheme.configuration(for: .japanese), "nihongowobenkyoushiteimasu", "日本語を勉強しています"),
                (SKChineseJapaneseScheme.configuration(for: .mixed), "nihon", "日本")]
            let engine = try SKConversionEngine(configuration: modes[0].0)
            for iteration in 0..<120 {
                let (config, input, target) = modes[iteration % modes.count]
                _ = try engine.selectConfiguration(config)
                var state = SKEngineState()
                for key in input.utf8 {
                    let start = DispatchTime.now().uptimeNanoseconds
                    state = engine.process(key: Int32(key))
                    timings.append(Double(DispatchTime.now().uptimeNanoseconds - start) / 1e6)
                    expect(state.committedText.isEmpty, "no premature commit at \(iteration)")
                }
                if let choice = state.candidates.first(where: { $0.text == target }) {
                    let result = engine.selectCandidate(at: choice.index)
                    expect(result.committedText == target && result.input.isEmpty, "exact selection \(iteration)")
                } else { expect(false, "missing \(target) in mode \(iteration % 4)") }
                _ = engine.clear()
                if iteration % 12 == 11 { sample("switches-\(iteration + 1)") }
                await Task.yield()
            }
            sample("after-engine-workload")
            struct Corpus: Decodable {
                struct Item: Decodable { let pinyin: String; let shuangpin: String }
                let cases: [Item]
            }
            guard let url = Bundle.main.url(forResource: "LexiconQualityCases", withExtension: "json") else {
                throw NSError(domain: "LexiconRuntime", code: 1, userInfo: [NSLocalizedDescriptionKey: "Missing runtime corpus fixture"])
            }
            let cases = try JSONDecoder().decode(Corpus.self, from: Data(contentsOf: url)).cases
            for (label, config) in [("full", modes[0].0), ("double", modes[1].0), ("mixed", modes[3].0)] {
                _ = try engine.selectConfiguration(config)
                for (offset, item) in cases.enumerated() {
                    _ = engine.clear()
                    for key in (label == "double" ? item.shuangpin : item.pinyin).utf8 {
                        let start = DispatchTime.now().uptimeNanoseconds
                        let state = engine.process(key: Int32(key))
                        timings.append(Double(DispatchTime.now().uptimeNanoseconds - start) / 1e6)
                        expect(state.committedText.isEmpty, "diverse input must not commit unexpectedly")
                    }
                    if offset % 50 == 49 { sample("diverse-\(label)-\(offset + 1)") }
                    await Task.yield()
                }
                _ = engine.clear(); sample("diverse-\(label)-complete")
            }
        } catch { failures.append("engine: \(error)") }

        UserDefaults.standard.set("chineseJapanese", forKey: SKInputScheme.preferenceKey)
        UserDefaults.standard.set("chinese", forKey: SKChineseJapaneseMode.preferenceKey)
        let keyboard = LexiconKeyboard(), editor = keyboard.proxy.editor
        editor.frame = CGRect(x: 16, y: 110, width: 370, height: 130)
        editor.font = .systemFont(ofSize: 24); editor.inputView = UIView(frame: .zero)
        editor.autocorrectionType = .no; editor.spellCheckingType = .no
        host.view.addSubview(editor); editor.becomeFirstResponder()
        host.addChild(keyboard); host.view.addSubview(keyboard.view); keyboard.didMove(toParent: host)
        keyboard.view.frame = CGRect(x: 0, y: 320, width: 402, height: 260)
        keyboard.view.backgroundColor = UIColor(white: 0.86, alpha: 1); keyboard.view.layoutIfNeeded()
        let bar = views(keyboard.view).compactMap { $0 as? CandidateBarView }.first!
        let language = views(keyboard.view).compactMap { $0 as? SKInputSwitchButton }.first!
        func type(_ text: String) async {
            try? await Task.sleep(nanoseconds: 30_000_000)
            func visible(_ view: UIView) -> Bool {
                if view.isHidden { return false }
                return view.superview.map(visible) ?? true
            }
            for key in text {
                let buttons = views(keyboard.view).compactMap { $0 as? SKMainKeyButton }
                if let button = buttons.first(where: { $0.keyTitle == String(key) && visible($0) && $0.window != nil }) {
                    button.sendActions(for: .touchDown); button.sendActions(for: .touchUpInside)
                } else { failures.append("missing visible UI key \(key)") }
                try? await Task.sleep(nanoseconds: 15_000_000)
            }
        }
        func snapshot(_ name: String) {
            keyboard.view.layoutIfNeeded()
            let image = UIGraphicsImageRenderer(bounds: host.view.bounds).image { host.view.layer.render(in: $0.cgContext) }
            try? image.pngData()?.write(to: output.appendingPathComponent(name + ".png"))
        }
        func select(_ text: String) {
            if let button = views(bar).compactMap({ $0 as? UIButton }).first(where: { $0.accessibilityLabel == text }) {
                button.sendActions(for: .touchUpInside)
            } else { failures.append("UI missing \(text)") }
        }
        try? await Task.sleep(nanoseconds: 300_000_000)
        await type("sihua"); snapshot("lexicon-chinese-sihua"); select("丝滑")
        expect(editor.text == "丝滑" && editor.markedTextRange == nil, "Chinese marked text replaced once")
        language.sendActions(for: .touchUpInside)
        await type("nihon"); snapshot("lexicon-japanese-nihon"); select("日本")
        expect(editor.text == "丝滑日本", "Japanese UI mode converts")
        language.sendActions(for: .touchUpInside)
        await type("sihua"); snapshot("lexicon-mixed-sihua"); select("丝滑")
        expect(editor.text == "丝滑日本丝滑", "mixed Chinese selection")
        keyboard.didTapSwitchScheme()
        await type("sihx"); snapshot("lexicon-double-sihua"); select("丝滑")
        expect(editor.text == "丝滑日本丝滑丝滑", "double-pinyin UI conversion")
        snapshot("lexicon-committed"); sample("after-ui-screenshots")
        try? await Task.sleep(nanoseconds: 300_000_000)
        sample("after-ui-autorelease-drain")
        let sorted = timings.sorted()
        let report: [String: Any] = ["environment": "iOS Simulator UIKit host, production controller/engines, NOT physical-device extension", "optimized": true,
            "assertions": assertions, "switches": 120, "keys": timings.count, "diverseCasesPerMode": 172, "diverseModes": ["full", "double", "mixed"], "keyP95MS": sorted[Int(Double(sorted.count-1)*0.95)],
            "memorySamples": samples, "failures": failures]
        try? JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]).write(to: output.appendingPathComponent("lexicon-runtime.json"))
        let result = "\(failures.isEmpty ? "PASS" : "FAIL") \(assertions) assertions, 120 language/scheme switches, \(timings.count) keys: \(failures.joined(separator: "; "))"
        try? result.write(to: output.appendingPathComponent("result.txt"), atomically: true, encoding: .utf8)
    }
}
