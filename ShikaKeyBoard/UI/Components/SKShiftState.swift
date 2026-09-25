import Foundation

/// Shared interaction state; each keyboard keeps its own instance and appearance.
struct SKShiftState {
    enum Casing { case lower, upper, locked }
    private(set) var casing: Casing = .lower
    private var lastTap: TimeInterval?

    mutating func tap(at time: TimeInterval) {
        if casing == .locked {
            casing = .lower
            lastTap = nil
        } else if let previous = lastTap, time - previous <= 0.3 {
            casing = .locked
            lastTap = nil
        } else {
            casing = casing == .lower ? .upper : .lower
            lastTap = time
        }
    }

    mutating func lock() { lastTap = nil; casing = .locked }
    mutating func willTypeLetter() { lastTap = nil }
    mutating func didTypeLetter() -> Bool {
        guard casing == .upper else { return false }
        casing = .lower
        return true
    }
}
