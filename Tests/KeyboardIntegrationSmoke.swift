import UIKit

final class TestProxy: NSObject, UITextDocumentProxy {
    var text = ""
    var documentContextBeforeInput: String? { text }
    var documentContextAfterInput: String? { "" }
    var selectedText: String? { nil }
    var documentInputMode: UITextInputMode? { nil }
    var documentIdentifier = UUID()
    var hasText: Bool { !text.isEmpty }
    func insertText(_ text: String) { self.text += text }
    func deleteBackward() { if !text.isEmpty { text.removeLast() } }
    func adjustTextPosition(byCharacterOffset offset: Int) {}
    func setMarkedText(_ markedText: String, selectedRange: NSRange) {}
    func unmarkText() {}
}
final class TestKeyboardController: KeyboardViewController {
    let proxy = TestProxy()
    override var textDocumentProxy: UITextDocumentProxy { proxy }
}
func descendants(_ view: UIView) -> [UIView] { [view] + view.subviews.flatMap(descendants) }
func tap(_ title: String, in view: UIView) {
    let key = descendants(view).compactMap { $0 as? UIButton }.first { $0.title(for: .normal) == title }!
    key.sendActions(for: .touchUpInside)
}
final class SmokeApp: UIResponder, UIApplicationDelegate {
    var window: UIWindow?
    func application(_ application: UIApplication, didFinishLaunchingWithOptions options: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        let window = UIWindow(frame: UIScreen.main.bounds)
        let host = UIViewController()
        host.view.backgroundColor = .white
        window.rootViewController = host
        window.makeKeyAndVisible()
        self.window = window
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { self.check(host) }
        return true
    }
    func check(_ host: UIViewController) {
        let output = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        UserDefaults.standard.set("shuangpin", forKey: SKInputScheme.preferenceKey)
        let start = Date()
        let controller = TestKeyboardController()
        host.addChild(controller)
        host.view.addSubview(controller.view)
        controller.didMove(toParent: host)
        controller.view.frame = CGRect(x: 0, y: 250, width: 390, height: 281)
        controller.view.backgroundColor = UIColor(white: 0.85, alpha: 1)
        controller.view.layoutIfNeeded()
        let coldLoad = Date().timeIntervalSince(start)
        let double = descendants(controller.view).first { $0 is SKShuangpinKeyboardView }!
        let mixed = descendants(controller.view).first { $0 is SKChineseJapaneseKeyboardView }!
        let bar = descendants(controller.view).first { $0 is CandidateBarView }!
        let number = descendants(controller.view).first { $0 is SKNumberInputView }!
        let language = descendants(controller.view).first { $0 is SKInputSwitchButton } as! UIButton
        for key in "nihc" { tap(String(key), in: double) }
        assert(controller.proxy.text.isEmpty)
        tap("你好", in: bar)
        assert(controller.proxy.text == "你好")
        for key in "vsgo" { tap(String(key), in: double) }
        tap("双拼", in: double)
        assert(controller.proxy.text == "你好中国")
        tap("⌫", in: double)
        assert(controller.proxy.text == "你好中")
        for key in "nihc" { tap(String(key), in: double) }
        tap("⌫", in: double)
        assert(controller.proxy.text == "你好中")
        tap("c", in: double)
        tap("换行", in: double)
        assert(controller.proxy.text == "你好中你好\n")
        for key in "nihc" { tap(String(key), in: double) }
        tap("123", in: double)
        assert(controller.proxy.text.hasSuffix("你好"))
        tap("1", in: number)
        tap("返回", in: number)
        assert(!double.isHidden && controller.proxy.text.hasSuffix("你好1"))
        for key in "vsgo" { tap(String(key), in: double) }
        tap("🦌", in: double)
        assert(!mixed.isHidden && controller.proxy.text.hasSuffix("中国"))
        for _ in 0..<3 {
            for key in "nihao" { tap(String(key), in: mixed) }
            tap("你好", in: bar)
            language.sendActions(for: .touchUpInside)
        }
        assert(controller.proxy.text.hasSuffix("你好你好你好"))
        tap("🦌", in: mixed)
        for key in "nihc" { tap(String(key), in: double) }
        controller.view.layoutIfNeeded()
        for width: CGFloat in [320, 390, 430] {
            controller.view.frame.size.width = width
            controller.view.layoutIfNeeded()
            let image = UIGraphicsImageRenderer(bounds: controller.view.bounds).image { context in controller.view.layer.render(in: context.cgContext) }
            try! image.pngData()!.write(to: output.appendingPathComponent("rime-\(Int(width)).png"))
        }
        controller.view.frame.size.width = 390
        controller.view.layoutIfNeeded()
        let text = UILabel(frame: CGRect(x: 16, y: 100, width: 360, height: 100))
        text.numberOfLines = 0
        text.text = controller.proxy.text
        host.view.addSubview(text)
        let report = "PASS actual UIKit keys -> Rime -> proxy; dual schemas, all language states, selection/space/newline/delete/numeric/scheme flush. Cold load: \(coldLoad)s. Output: \(controller.proxy.text)"
        try! report.write(to: output.appendingPathComponent("result.txt"), atomically: true, encoding: .utf8)
    }
}
@main
struct Main {
    static func main() { UIApplicationMain(CommandLine.argc, CommandLine.unsafeArgv, nil, NSStringFromClass(SmokeApp.self)) }
}
