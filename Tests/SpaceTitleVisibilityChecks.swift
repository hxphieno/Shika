import UIKit

private final class SpaceEventRecorder: SKKeyboardEventHandler {
    var text = ""
    func didTapKey(_ key: String) { text += key }
    func didTapDelete() {}
    func didTapSwitchScheme() {}
    func didTapNextKeyboard() {}
    func didTapSwitchLayout(to layout: SKKeyboardLayoutType) {}
}

@MainActor
final class SpaceTitleApp: UIResponder, UIApplicationDelegate {
    var window: UIWindow?
    private var failures: [String] = []
    private var assertions = 0

    private func expect(_ value: Bool, _ message: String) {
        assertions += 1
        if !value { failures.append(message) }
    }
    private func pause(_ seconds: Double) async {
        try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
    }
    private func opacity(_ key: UIButton) -> Float {
        key.titleLabel?.layer.presentation()?.opacity ?? Float(key.titleLabel?.alpha ?? -1)
    }
    func application(_ application: UIApplication, didFinishLaunchingWithOptions options: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        let host = UIViewController()
        let window = UIWindow(frame: UIScreen.main.bounds)
        window.rootViewController = host
        window.makeKeyAndVisible()
        self.window = window
        Task { await run(host) }
        return true
    }
    private func run(_ host: UIViewController) async {
        let footer = SKKeyboardFooterView(schemeTitle: "中日混合", nextSchemeTitle: "双拼")
        let recorder = SpaceEventRecorder()
        footer.eventHandler = recorder
        footer.frame = CGRect(x: 0, y: 100, width: 400, height: 50)
        footer.keyFrames = (0..<4).map { CGRect(x: $0 * 100, y: 0, width: 94, height: 44) }
        host.view.addSubview(footer)
        footer.layoutIfNeeded()
        let space = footer.subviews.compactMap { $0 as? SKMainKeyButton }.first { $0.keyRole == .space }!
        await pause(1.8)
        expect(opacity(space) > 0.99, "Title remains visible for about two seconds")
        await pause(0.3)
        expect(opacity(space) > 0 && opacity(space) < 1, "Title fades gradually after two seconds")
        await pause(0.4)
        expect(opacity(space) == 0, "Title disappears after fade")
        expect(space.alpha == 1 && space.accessibilityLabel == "空格，当前方案：中日混合", "Only the visual title fades; key and VoiceOver label remain")
        space.sendActions(for: .touchDown)
        space.sendActions(for: .touchUpInside)
        await pause(0.1)
        expect(recorder.text == " " && opacity(space) == 0, "Hidden-title space still types without redisplaying the title")
        footer.showSchemeTitle()
        await pause(1.4)
        footer.showSchemeTitle()
        await pause(0.9)
        expect(opacity(space) == 1, "Repeated switch cancels the previous deadline")
        await pause(1.2)
        expect(opacity(space) > 0 && opacity(space) < 1, "Restarted title fades on its new deadline")
        footer.showSchemeTitle()
        await pause(0.1)
        expect(opacity(space) == 1, "Switch during fade immediately restores the title")
        footer.removeFromSuperview()
        await pause(2.1)
        host.view.addSubview(footer)
        await pause(0.1)
        expect(opacity(space) == 1, "Reattaching keyboard starts a fresh title display")
        await pause(2.4)
        expect(opacity(space) == 0, "Reattached title also disappears")
        let output = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let report = (failures.isEmpty ? "PASS " : "FAIL ") + "\(assertions) space title visibility assertions\n" + failures.joined(separator: "\n")
        try? report.write(to: output.appendingPathComponent("result.txt"), atomically: true, encoding: .utf8)
    }
}

@main
struct SpaceTitleEntry {
    @MainActor static func main() {
        UIApplicationMain(CommandLine.argc, CommandLine.unsafeArgv, nil, NSStringFromClass(SpaceTitleApp.self))
    }
}
