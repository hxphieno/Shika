import UIKit

/// Shared deletion gesture for alphabet and custom number keys. Timings are
/// Shika's native-like defaults, not undocumented Apple implementation constants.
@MainActor
final class SKDeleteKeyInteraction: NSObject {
    static let initialDelay: TimeInterval = 0.45
    static let characterInterval: TimeInterval = 0.10
    static let wordInterval: TimeInterval = 0.15
    static let wordRepeatThreshold = 16
    private static weak var active: SKDeleteKeyInteraction?

    private weak var control: UIControl?
    private let action: (Bool) -> SKDeleteFeedback
    private var timer: Timer?
    private var repeatCount = 0
    private var pressed = false
    private var paused = false
    private var remaining = initialDelay

    init(control: UIControl, action: @escaping (Bool) -> SKDeleteFeedback) {
        self.control = control; self.action = action
        super.init()
        control.addTarget(self, action: #selector(begin), for: .touchDown)
        control.addTarget(self, action: #selector(pause), for: .touchDragExit)
        control.addTarget(self, action: #selector(resume), for: .touchDragEnter)
        control.addTarget(self, action: #selector(cancel), for: [.touchUpInside, .touchUpOutside, .touchCancel])
        NotificationCenter.default.addObserver(self, selector: #selector(cancel), name: UIApplication.willResignActiveNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(cancel), name: UIScene.willDeactivateNotification, object: nil)
    }
    deinit { timer?.invalidate(); NotificationCenter.default.removeObserver(self) }
    static func cancelActive() { active?.cancel() }

    private var isAvailable: Bool {
        guard let control, control.isEnabled, control.window != nil else { return false }
        var view: UIView? = control
        while let current = view {
            if current.isHidden || current.alpha <= 0.01 || !current.isUserInteractionEnabled { return false }
            view = current.superview
        }
        return true
    }
    @objc private func begin() {
        guard !pressed, isAvailable else { return }
        Self.cancelActive(); Self.active = self
        pressed = true; paused = false; repeatCount = 0
        let result = action(false)
        guard pressed, result != .stop, isAvailable else { cancel(); return }
        schedule(Self.initialDelay)
    }
    @objc private func pause() {
        guard pressed, !paused else { return }
        remaining = max(0.05, timer?.fireDate.timeIntervalSinceNow ?? Self.characterInterval)
        paused = true; timer?.invalidate(); timer = nil
    }
    @objc private func resume() {
        guard pressed, paused, isAvailable else { return }
        paused = false
        // Re-entering is not a fresh tap. Preserve cadence without an extra delete.
        schedule(remaining)
    }
    @objc func cancel() {
        timer?.invalidate(); timer = nil
        pressed = false; paused = false; repeatCount = 0
        if Self.active === self { Self.active = nil }
    }
    func activateOnce() -> Bool {
        guard isAvailable else { return false }
        Self.cancelActive(); _ = action(false); return true
    }
    private func schedule(_ interval: TimeInterval) {
        timer?.invalidate()
        let next = Timer(timeInterval: interval, repeats: false) { [weak self] _ in self?.repeatDeletion() }
        timer = next; RunLoop.main.add(next, forMode: .common)
    }
    private func repeatDeletion() {
        guard pressed, !paused, isAvailable else { cancel(); return }
        timer = nil
        let byWord = repeatCount >= Self.wordRepeatThreshold
        let result = action(byWord)
        guard pressed, !paused, isAvailable else { cancel(); return }
        switch result {
        case .stop: cancel()
        case .restartDelay:
            repeatCount = 0; schedule(Self.initialDelay)
        case .continueRepeating:
            repeatCount += 1
            schedule(byWord ? Self.wordInterval : Self.characterInterval)
        }
    }
}
