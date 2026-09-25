import UIKit

/// Interactive measurement fixture. Only real native keyboard UI touches are
/// recorded; this never synthesizes an Apple key press or calls private APIs.
private enum Trace {
    static var start = CACurrentMediaTime()
    static var events: [[String: Any]] = []
    static let directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    static func add(_ fields: [String: Any]) {
        var fields = fields; fields["seconds"] = CACurrentMediaTime() - start
        events.append(fields)
        try? JSONSerialization.data(withJSONObject: events, options: [.prettyPrinted, .sortedKeys])
            .write(to: directory.appendingPathComponent("native-delete-events.json"))
    }
}
private final class TraceWindow: UIWindow {
    override func sendEvent(_ event: UIEvent) {
        if let touches = event.allTouches {
            for touch in touches where touch.phase != .stationary {
                Trace.add(["event": "touch", "phase": touch.phase.rawValue])
            }
        }
        super.sendEvent(event)
    }
}
@main final class NativeDeleteReference: UIResponder, UIApplicationDelegate, UITextViewDelegate {
    var window: UIWindow?
    private let editor = UITextView()
    func application(_ application: UIApplication, didFinishLaunchingWithOptions options: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        let window = TraceWindow(frame: UIScreen.main.bounds), host = UIViewController()
        host.view.backgroundColor = .systemBackground
        window.rootViewController = host; window.makeKeyAndVisible(); self.window = window
        editor.frame = CGRect(x: 16, y: 150, width: 365, height: 260)
        editor.font = .systemFont(ofSize: 21); editor.delegate = self
        editor.autocorrectionType = .no; editor.spellCheckingType = .no
        editor.keyboardType = .asciiCapable
        host.view.addSubview(editor)
        let reset = UIButton(type: .system)
        reset.frame = CGRect(x: 20, y: 80, width: 180, height: 50)
        reset.setTitle("Reset deletion trace", for: .normal)
        reset.addTarget(self, action: #selector(resetTrace), for: .touchUpInside)
        host.view.addSubview(reset)
        resetTrace(); editor.becomeFirstResponder()
        try? "PASS native reference fixture ready; no timing assertion yet".write(to: Trace.directory.appendingPathComponent("result.txt"), atomically: true, encoding: .utf8)
        return true
    }
    @objc private func resetTrace() {
        editor.text = "A native keyboard deletion reference. The quick brown fox jumps over the lazy dog. A long sentence with several words to observe repeated deletion."
        editor.selectedRange = NSRange(location: (editor.text as NSString).length, length: 0)
        Trace.start = CACurrentMediaTime(); Trace.events = []; Trace.add(["event": "reset"])
    }
    func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool {
        Trace.add(["event": "edit", "replacement": text, "removed": (textView.text as NSString).substring(with: range), "rangeLength": range.length])
        return true
    }
}
