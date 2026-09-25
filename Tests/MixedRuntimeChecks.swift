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
private final class MixedProxy: NSObject, UITextDocumentProxy {
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
private final class MixedKeyboard: KeyboardViewController {
    let proxy = MixedProxy()
    override var textDocumentProxy: UITextDocumentProxy { proxy }
}
private func views(_ root: UIView) -> [UIView] { [root] + root.subviews.flatMap(views) }

@main final class MixedRuntimeChecks: UIResponder, UIApplicationDelegate {
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
            let engine = try SKConversionEngine(configuration: SKChineseJapaneseScheme.configuration(for: .mixed))
            struct Corpus: Decodable { struct Item: Decodable {let input: String}; let cases:[Item] }
            let url = Bundle.main.url(forResource: "MixedEngineCases", withExtension: "json")!
            let corpus = try JSONDecoder().decode(Corpus.self, from: Data(contentsOf: url))
            for (i,item) in corpus.cases.prefix(Int(ProcessInfo.processInfo.environment["MIXED_RUNTIME_LIMIT"] ?? "250") ?? 250).enumerated() {
                _ = engine.clear()
                for key in item.input.utf8 {
                    let start = DispatchTime.now().uptimeNanoseconds
                    let state = engine.process(key: Int32(key))
                    timings.append(Double(DispatchTime.now().uptimeNanoseconds - start) / 1e6)
                    expect(state.committedText.isEmpty, "no early commit \(i)")
                }
                if i % 20 == 0 { sample("corpus-\(i)"); await Task.yield() }
            }
            _ = engine.clear()
        } catch { failures.append("engine: \(error)") }
        sample("after-engine")
        UserDefaults.standard.set("chineseJapanese", forKey: SKInputScheme.preferenceKey)
        UserDefaults.standard.set("mixed", forKey: SKChineseJapaneseMode.preferenceKey)
        let keyboard = MixedKeyboard(), editor = keyboard.proxy.editor
        editor.frame = CGRect(x: 16, y: 100, width: 370, height: 130)
        editor.font = .systemFont(ofSize: 24); editor.inputView = UIView(frame: .zero)
        editor.autocorrectionType = .no; editor.spellCheckingType = .no
        host.view.addSubview(editor); editor.becomeFirstResponder()
        host.addChild(keyboard); host.view.addSubview(keyboard.view); keyboard.didMove(toParent: host)
        keyboard.view.frame = CGRect(x: 0, y: 320, width: 402, height: 260)
        keyboard.view.layoutIfNeeded()
        func type(_ input: String) async {
            for c in input { keyboard.didTapKey(String(c)); await Task.yield() }
        }
        func reset() {
            keyboard.textWillChange(editor); editor.text = ""; editor.selectedRange = NSRange(location: 0, length: 0)
            keyboard.textDidChange(editor)
        }
        func snapshot(_ name: String) {
            host.view.layoutIfNeeded()
            let image = UIGraphicsImageRenderer(bounds: host.view.bounds).image {host.view.layer.render(in:$0.cgContext)}
            try? image.pngData()?.write(to:output.appendingPathComponent(name+".png"))
        }
        func select(_ text: String) {
            if let button = views(keyboard.view).compactMap({$0 as? UIButton}).first(where: {$0.accessibilityLabel == text}) {
                button.sendActions(for:.touchUpInside)
            } else {failures.append("UI missing \(text)")}
        }
        func marked() -> String? {editor.markedTextRange.flatMap {editor.text(in:$0)}}
        try? await Task.sleep(nanoseconds:100_000_000)
        await type("jintianyearigatou")
        expect(marked() == "jintianyearigatou", "raw mixed marked text")
        snapshot("mixed-whole-candidate")
        select("今天也ありがとう")
        expect(editor.text == "今天也ありがとう" && marked() == nil, "whole sentence replaces marked text once")
        snapshot("mixed-whole-committed")
        reset(); await type("jintianyearigatou")
        if let expand = views(keyboard.view).compactMap({$0 as? UIButton}).first(where: {$0.accessibilityIdentifier == "candidates.expand"}) {
            expand.sendActions(for:.touchUpInside)
        }
        select("今天也")
        expect(marked() == "今天也arigatou", "partial Chinese selection keeps raw Japanese remainder")
        snapshot("mixed-partial-remainder")
        select("ありがとう")
        expect(editor.text == "今天也ありがとう" && marked() == nil, "partial then Japanese commit has no duplication: \(editor.text ?? "nil") marked=\(marked() ?? "nil")")
        reset(); await type("zhegesugoiwoxihuan")
        select("这个すごい我喜欢")
        expect(editor.text == "这个すごい我喜欢" && marked() == nil, "multiple language transitions through UI")
        snapshot("mixed-multiple-switches")
        reset(); await type("jintianyearigadou"); select("今天也ありがとう")
        expect(editor.text == "今天也ありがとう", "mixed correction through UI")
        reset(); await type("nihao"); keyboard.didTapSwitchScheme(); await type("nihc"); keyboard.didTapKey(" ")
        expect(editor.text == "你好你好", "scheme switch preserves mixed composition and double pinyin")
        sample("after-ui")
        let sorted = timings.sorted()
        let report:[String:Any] = ["platform":"iOS Simulator production controller/UITextView host; not physical-device extension", "assertions":assertions,
            "keyP50MS":sorted.isEmpty ? 0 : sorted[sorted.count/2], "keyP95MS":sorted.isEmpty ? 0 : sorted[Int(Double(sorted.count-1)*0.95)],
            "keyP99MS":sorted.isEmpty ? 0 : sorted[Int(Double(sorted.count-1)*0.99)], "keys":timings.count,
            "memorySamples":samples,"failures":failures]
        try? JSONSerialization.data(withJSONObject:report,options:[.prettyPrinted,.sortedKeys]).write(to:output.appendingPathComponent("mixed-runtime.json"))
        try? "\(failures.isEmpty ? "PASS" : "FAIL") \(assertions) checks; \(failures.joined(separator:"; "))".write(to:output.appendingPathComponent("result.txt"),atomically:true,encoding:.utf8)
    }
}
