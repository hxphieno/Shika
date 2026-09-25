import UIKit

/// Manual reference: operate Apple's actual onscreen keys, then inspect the trace.
@main final class NativeReturnReference: UIResponder, UIApplicationDelegate, UITextViewDelegate {
    var window: UIWindow?
    private let editor = UITextView()
    private let status = UILabel()
    private var events: [[String: Any]] = []
    private let output = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    func application(_ application: UIApplication, didFinishLaunchingWithOptions options: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        let window = UIWindow(frame: UIScreen.main.bounds), host = UIViewController()
        host.view.backgroundColor = .systemBackground; window.rootViewController = host
        window.makeKeyAndVisible(); self.window = window
        let types = UISegmentedControl(items: ["换行", "发送", "搜索"])
        types.frame = CGRect(x: 16, y: 65, width: 370, height: 40); types.selectedSegmentIndex = 0
        types.addTarget(self, action: #selector(changeType), for: .valueChanged); host.view.addSubview(types)
        let languages = UILabel(frame: CGRect(x: 16, y: 115, width: 370, height: 40))
        languages.text = "使用系统地球键切换语言"; host.view.addSubview(languages)
        let reset = UIButton(type: .system); reset.setTitle("清空并记录", for: .normal)
        reset.frame = CGRect(x: 16, y: 165, width: 160, height: 40)
        reset.addTarget(self, action: #selector(resetText), for: .touchUpInside); host.view.addSubview(reset)
        editor.frame = CGRect(x: 16, y: 210, width: 370, height: 125)
        editor.font = .systemFont(ofSize: 23); editor.delegate = self
        host.view.addSubview(editor)
        status.frame = CGRect(x: 16, y: 335, width: 370, height: 140)
        status.numberOfLines = 0; status.font = .monospacedSystemFont(ofSize: 13, weight: .regular)
        host.view.addSubview(status); editor.becomeFirstResponder(); record("ready")
        try? "PASS native return reference ready; observations require real UI actions".write(to: output.appendingPathComponent("result.txt"), atomically: true, encoding: .utf8)
        return true
    }
    @objc private func changeType(_ sender: UISegmentedControl) {
        editor.returnKeyType = [.default, .send, .search][sender.selectedSegmentIndex]
        editor.reloadInputViews(); record("type changed")
    }
    @objc private func resetText() { editor.text = ""; record("reset") }
    private func record(_ event: String, replacement: String = "") {
        let item: [String: Any] = ["event": event, "text": editor.text ?? "", "replacement": replacement,
            "marked": editor.markedTextRange != nil, "language": editor.textInputMode?.primaryLanguage ?? "nil",
            "returnType": editor.returnKeyType.rawValue]
        events.append(item)
        status.text = "\(event)\ntext=\(String(reflecting: editor.text ?? ""))\nmarked=\(editor.markedTextRange != nil)\nmode=\(editor.textInputMode?.primaryLanguage ?? "nil")"
        try? JSONSerialization.data(withJSONObject: events, options: [.prettyPrinted, .sortedKeys]).write(to: output.appendingPathComponent("native-return-events.json"))
    }
    func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool {
        record("shouldChange", replacement: text)
        if text == "\n" && editor.returnKeyType != .default { record("host action", replacement: text); return false }
        return true
    }
    func textViewDidChange(_ textView: UITextView) { record("didChange") }
    func textViewDidChangeSelection(_ textView: UITextView) { record("selection") }
}
