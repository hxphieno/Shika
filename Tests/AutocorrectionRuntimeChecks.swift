import UIKit
import Darwin

/// Simulator UIKit host: production Rime/Swift engine and keyboard views.
/// This is intentionally distinct from measuring an iOS keyboard extension process.
private func physicalFootprint() -> UInt64? {
    var info = task_vm_info_data_t()
    var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
    let result: kern_return_t = withUnsafeMutablePointer(to: &info) { pointer in
        pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
            task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
        }
    }
    return result == KERN_SUCCESS ? info.phys_footprint : nil
}

private final class RuntimeProxy: NSObject, UITextDocumentProxy {
    // Committed output is separate from the pending composition in this spy.
    var text = ""
    var markedText: String?
    var documentContextBeforeInput: String? { text + (markedText ?? "") }
    var documentContextAfterInput: String? { "" }
    var selectedText: String? { nil }
    var documentInputMode: UITextInputMode? { nil }
    var documentIdentifier = UUID()
    var hasText: Bool { !text.isEmpty }
    func insertText(_ text: String) { self.text += text }
    func deleteBackward() { if !text.isEmpty { text.removeLast() } }
    func adjustTextPosition(byCharacterOffset offset: Int) {}
    func setMarkedText(_ markedText: String, selectedRange: NSRange) { self.markedText = markedText }
    func unmarkText() {
        text += markedText ?? ""
        markedText = nil
    }
}
private final class RuntimeKeyboard: KeyboardViewController {
    let proxy = RuntimeProxy()
    override var textDocumentProxy: UITextDocumentProxy { proxy }
}
private func allViews(_ view: UIView) -> [UIView] { [view] + view.subviews.flatMap(allViews) }

private final class RuntimeApp: UIResponder, UIApplicationDelegate {
    var window: UIWindow?
    private var engine: SKRimeEngine?
    private var host: UIViewController!
    private var memory: [[String: Any]] = []
    private var keyTimes: [Double] = []
    private var switchTimes: [Double] = []
    private var failures: [String] = []
    private var initMilliseconds = 0.0
    private let totalSwitches = 300
    private let stabilityWindowStart = 120
    private var documents: URL { FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0] }

    func application(_ application: UIApplication, didFinishLaunchingWithOptions options: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        let window = UIWindow(frame: UIScreen.main.bounds)
        host = UIViewController()
        host.view.backgroundColor = .systemBackground
        window.rootViewController = host
        window.makeKeyAndVisible()
        self.window = window
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { self.begin() }
        return true
    }

    private func sample(_ phase: String, iteration: Int) {
        if let value = physicalFootprint() {
            memory.append(["phase": phase, "switches": iteration, "physFootprintBytes": value])
        } else { failures.append("task_info failed at \(phase)") }
    }

    private func begin() {
        sample("before-engine", iteration: 0)
        do {
            let start = CFAbsoluteTimeGetCurrent()
            // The process-wide runtime and the later production controller must
            // use the same user directory (the test app has its own sandbox).
            engine = try SKRimeEngine(configuration: SKInputScheme.shuangpin.configuration)
            initMilliseconds = (CFAbsoluteTimeGetCurrent() - start) * 1000
            sample("after-initialization", iteration: 0)
            iteration(1)
        } catch {
            failures.append("engine initialization: \(error)")
            finish()
        }
    }

    private func iteration(_ number: Int) {
        autoreleasepool {
            guard let engine else { return }
            let fullPinyin = number % 2 == 1
            let schema = fullPinyin ? "shika_pinyin" : "shika_flypy"
            let full = [("nohao", "你好"), ("zhnogguo", "中国"), ("zhongguoo", "中国"), ("zhonguo", "中国")]
            let double = [("nijc", "你好"), ("niihc", "你好"), ("nhc", "你好"), ("svgo", "中国")]
            let test = (fullPinyin ? full : double)[((number - 1) / 2) % 4]
            do {
                _ = engine.clear()
                let switchStart = CFAbsoluteTimeGetCurrent()
                _ = try engine.selectConfiguration(SKInputScheme(schemaID: schema)!.configuration)
                switchTimes.append((CFAbsoluteTimeGetCurrent() - switchStart) * 1000)
                var state = SKEngineState()
                for key in test.0.utf8 {
                    let keyStart = CFAbsoluteTimeGetCurrent()
                    state = engine.process(key: Int32(key))
                    keyTimes.append((CFAbsoluteTimeGetCurrent() - keyStart) * 1000)
                    if !state.committedText.isEmpty { failures.append("unexpected commit while typing \(test.0)") }
                }
                if let choice = state.candidates.first(where: { $0.text == test.1 }) {
                    let result = engine.selectCandidate(at: choice.index)
                    if result.committedText != test.1 || !result.input.isEmpty {
                        failures.append("incomplete correction \(schema) \(test.0) → \(result.committedText), remaining \(result.input)")
                    }
                    if !engine.clear().committedText.isEmpty { failures.append("repeated commit at switch \(number)") }
                } else { failures.append("missing target \(schema) \(test.0) → \(test.1)") }
            } catch { failures.append("schema switch \(number): \(error)") }
        }
        // Each checkpoint runs after the iteration's autorelease pool drains.
        if number == 1 || number == 10 || number % 20 == 0 { sample("after-switches", iteration: number) }
        if number < totalSwitches {
            DispatchQueue.main.async { self.iteration(number + 1) }
        } else {
            engine = nil
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                self.sample("after-session-release", iteration: number)
                self.keyboardScreenshots()
                // Let UIKit and image-rendering autoreleases drain before the
                // final UI footprint observation. This is not engine memory.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                    self.sample("after-ui-autorelease-drain", iteration: number)
                    self.finish()
                }
            }
        }
    }

    private func press(_ title: String, in view: UIView) {
        let button = allViews(view).compactMap { $0 as? UIButton }.first {
            ($0 as? SKMainKeyButton)?.keyTitle == title || $0.title(for: .normal) == title || $0.configuration?.title == title || $0.accessibilityLabel == title
        }
        if let button {
            button.sendActions(for: .touchDown)
            button.sendActions(for: .touchUpInside)
        }
        else { failures.append("missing UIKit key \(title)") }
    }

    private func saveScreen(_ name: String) {
        autoreleasepool {
            guard let window else { return }
            window.layoutIfNeeded()
            let image = UIGraphicsImageRenderer(bounds: window.bounds).image { context in
                window.layer.render(in: context.cgContext)
            }
            do { try image.pngData()?.write(to: documents.appendingPathComponent(name + ".png")) }
            catch { failures.append("screenshot \(name): \(error)") }
        }
    }

    private func keyboardScreenshots() {
        UserDefaults.standard.set(SKInputScheme.chineseJapanese.rawValue, forKey: SKInputScheme.preferenceKey)
        let controller = RuntimeKeyboard()
        host.addChild(controller)
        host.view.addSubview(controller.view)
        controller.didMove(toParent: host)
        let width = host.view.bounds.width
        let height = SKConfig.topBarHeight + SKMainKeyboardMetrics.portraitHeight
        controller.view.frame = CGRect(x: 0, y: host.view.bounds.height - host.view.safeAreaInsets.bottom - height, width: width, height: height)
        controller.view.layoutIfNeeded()
        let label = UILabel(frame: CGRect(x: 20, y: host.view.safeAreaInsets.top + 24, width: width - 40, height: 200))
        label.numberOfLines = 0
        label.font = .systemFont(ofSize: 22)
        label.text = "生产键盘 · 纠错运行验证\n\(totalSwitches) 次方案切换已完成\n全拼错码：zhnogguo\n等待选择候选"
        host.view.addSubview(label)
        guard let full = allViews(controller.view).first(where: { $0 is SKChineseJapaneseKeyboardView }),
              let double = allViews(controller.view).first(where: { $0 is SKShuangpinKeyboardView }),
              let bar = allViews(controller.view).first(where: { $0 is CandidateBarView }) else {
            failures.append("production keyboard views unavailable"); return
        }
        for key in "zhnogguo" { press(String(key), in: full) }
        saveScreen("runtime-pinyin-candidates")
        press("中国", in: bar)
        if controller.proxy.text != "中国" { failures.append("UIKit full-pinyin correction did not commit 中国") }
        label.text = "全拼纠错\nzhnogguo → \(controller.proxy.text)\n真实按键 → Rime → 文本代理"
        saveScreen("runtime-pinyin-committed")
        press("🦌", in: full)
        for key in "niihc" { press(String(key), in: double) }
        label.text = "双拼纠错\n原输入：niihc\n已上屏：\(controller.proxy.text)\n等待选择候选"
        saveScreen("runtime-shuangpin-candidates")
        press("你好", in: bar)
        if controller.proxy.text != "中国你好" { failures.append("UIKit double-pinyin correction did not commit 你好 once") }
        label.text = "双拼纠错\nniihc → 你好\n累计上屏：\(controller.proxy.text)\n已完成 \(totalSwitches) 次方案切换"
        saveScreen("runtime-shuangpin-committed")
        sample("after-keyboard-screenshots", iteration: totalSwitches)
    }

    private func finish() {
        func percentile(_ values: [Double], _ p: Double) -> Double {
            guard !values.isEmpty else { return 0 }
            let sorted = values.sorted()
            return sorted[min(sorted.count - 1, Int(Double(sorted.count - 1) * p))]
        }
        let checkpoints = memory.filter { $0["phase"] as? String == "after-switches" && ($0["switches"] as? Int ?? 0) >= stabilityWindowStart }
        let footprints = checkpoints.compactMap { $0["physFootprintBytes"] as? UInt64 }
        let start = footprints.first ?? 0, end = footprints.last ?? 0
        let growth = Int64(end) - Int64(start)
        let spread = Int64(footprints.max() ?? 0) - Int64(footprints.min() ?? 0)
        // A bounded late-window growth guard, not a universal iOS extension limit.
        let stable = !footprints.isEmpty && growth <= 8 * 1024 * 1024 && spread <= 12 * 1024 * 1024
        if !stable { failures.append("late-window footprint did not stabilize: growth=\(growth), spread=\(spread)") }
        var report: [String: Any] = [:]
        report["environment"] = "iOS Simulator UIKit host, production Rime and Swift; not a keyboard extension process or physical device"
        report["osVersion"] = UIDevice.current.systemVersion
        report["switchCount"] = totalSwitches
        report["keyCount"] = keyTimes.count
        report["initializationMilliseconds"] = initMilliseconds
        report["keyP50Milliseconds"] = percentile(keyTimes, 0.50)
        report["keyP95Milliseconds"] = percentile(keyTimes, 0.95)
        report["keyP99Milliseconds"] = percentile(keyTimes, 0.99)
        report["keyMaxMilliseconds"] = keyTimes.max() ?? 0
        report["switchP95Milliseconds"] = percentile(switchTimes, 0.95)
        report["memorySamples"] = memory
        report["lateWindowGrowthBytes"] = growth
        report["lateWindowSpreadBytes"] = spread
        report["memoryStable"] = stable
        report["stabilityWindowStart"] = stabilityWindowStart
        let firstTwenty = memory.first { $0["phase"] as? String == "after-switches" && $0["switches"] as? Int == 20 }?["physFootprintBytes"] as? UInt64
        let first120 = memory.first { $0["phase"] as? String == "after-switches" && $0["switches"] as? Int == 120 }?["physFootprintBytes"] as? UInt64
        if let firstTwenty, let first120 {
            report["initial20To120GrowthBytes"] = Int64(first120) - Int64(firstTwenty)
        }
        report["failures"] = failures
        report["notes"] = "Footprint includes this UIKit host and Rime process-global caches. Samples 120–300 assess sustained growth after an extended warm-up. The 20–120 initial growth remains separately reported; the first 120-switch failure is preserved in repository evidence. The 8 MiB growth and 12 MiB spread thresholds are unchanged. Input timings include production decoding and correction; this script builds without -O. The repeated small word set is for stress/retention, not correction accuracy."
        do {
            try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]).write(to: documents.appendingPathComponent("runtime-report.json"))
            let status = failures.isEmpty ? "PASS " : "FAIL "
            let text = status + "\(totalSwitches) scheme switches; \(keyTimes.count) production keys; P95 \(percentile(keyTimes, 0.95)) ms; late footprint growth \(growth) bytes; errors: \(failures.joined(separator: "; "))"
            try text.write(to: documents.appendingPathComponent("result.txt"), atomically: true, encoding: .utf8)
        } catch { NSLog("Runtime evidence write failed: %@", String(describing: error)) }
    }
}

@main private struct RuntimeMain {
    static func main() { UIApplicationMain(CommandLine.argc, CommandLine.unsafeArgv, nil, NSStringFromClass(RuntimeApp.self)) }
}
