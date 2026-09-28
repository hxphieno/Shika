import Foundation

/// Bounded spelling metadata, not a second user dictionary or frequency model.
/// Every suggested word must still exist in a fresh native Rime lookup.
final class SKLearnedSpellingIndex {
    struct Entry: Codable, Equatable {
        let code: String
        let text: String
    }
    private let url: URL
    private let profile: SKSpellingProfile
    private var entries: [Entry]
    private static let capacity = 512
    private static let byteLimit = 131072

    init(userDirectory: URL, profile: SKSpellingProfile = .doublePinyin) {
        self.profile = profile
        let filename = profile == .doublePinyin ? "ziranma-double-pinyin-spelling.json" : "full-pinyin-spelling.json"
        url = userDirectory.appendingPathComponent(filename)
        // The Rime user dictionary stores phonetic readings and remains shared.
        // Only this auxiliary index stores layout-specific keystrokes.
        let migrate = profile == .doublePinyin && !FileManager.default.fileExists(atPath: url.path)
        let source = migrate ? userDirectory.appendingPathComponent("double-pinyin-spelling.json") : url
        let size = (try? source.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        if size > 0, size <= Self.byteLimit, let data = try? Data(contentsOf: source),
           let decoded = try? JSONDecoder().decode([Entry].self, from: data) {
            entries = Array(decoded.filter { Self.valid($0, profile: profile) }.suffix(Self.capacity))
            if migrate {
                entries = entries.map { Entry(code: Self.ziranmaCode(fromXiaohe: $0.code), text: $0.text) }
                // Keep the old file intact; never reimport it once migrated.
                if let data = try? JSONEncoder().encode(entries) { try? data.write(to: url, options: .atomic) }
            }
        } else { entries = [] }
    }

    private static func ziranmaCode(fromXiaohe code: String) -> String {
        let zeroInitials: Set<String> = ["aa", "oo", "ee", "ai", "ei", "ao", "ou", "an", "en", "ah", "eg", "er"]
        let finals: [Character: Character] = ["w": "z", "y": "p", "p": "x", "d": "l",
            "k": "y", "l": "d", "z": "b", "x": "w", "c": "k", "b": "n", "n": "c"]
        var letters = Array(code)
        for offset in stride(from: 0, to: letters.count, by: 2) {
            let pair = String(letters[offset...offset + 1])
            if !zeroInitials.contains(pair) { letters[offset + 1] = finals[letters[offset + 1]] ?? letters[offset + 1] }
        }
        return String(letters)
    }

    private static func valid(_ entry: Entry, profile: SKSpellingProfile) -> Bool {
        let code = entry.code.utf8
        let lengthMatches = profile == .doublePinyin ? code.count == entry.text.count * 2 :
            entry.text.count >= 2 && (entry.text.count...entry.text.count * 6).contains(code.count)
        return (4...48).contains(code.count) && lengthMatches &&
            code.allSatisfy { (97...122).contains($0) } &&
            entry.text.unicodeScalars.allSatisfy {
                (0x3400...0x9fff).contains($0.value) || (0x20000...0x323af).contains($0.value)
            }
    }

    func record(code: String, text: String) {
        let entry = Entry(code: code, text: text)
        guard Self.valid(entry, profile: profile), entries.last != entry else { return }
        entries.removeAll { $0 == entry }
        entries.append(entry)
        if entries.count > Self.capacity { entries.removeFirst(entries.count - Self.capacity) }
        let encoder = JSONEncoder()
        guard var data = try? encoder.encode(entries) else { return }
        // Supplementary Han characters use four UTF-8 bytes. A record-count
        // bound alone can exceed our own reload limit for long full-pinyin words.
        while data.count > Self.byteLimit {
            entries.removeFirst()
            guard let trimmed = try? encoder.encode(entries) else { return }
            data = trimmed
        }
        try? data.write(to: url, options: .atomic)
    }

    func suggestions(for input: String) -> [Entry] {
        let raw = Array(input.utf8)
        guard (3...49).contains(raw.count), raw.allSatisfy({ (97...122).contains($0) }) else { return [] }
        return entries.enumerated().compactMap { offset, entry -> (Int, Double, Entry)? in
            // One edit cannot bridge a larger length gap. Check the UTF-8 view
            // before allocating bytes for an unrelated learned phrase.
            guard abs(raw.count - entry.code.utf8.count) <= 1 else { return nil }
            guard let cost = Self.editCost(raw, Array(entry.code.utf8)) else { return nil }
            return (offset, cost, entry)
        }.sorted { $0.1 == $1.1 ? $0.0 > $1.0 : $0.1 < $1.1 }.prefix(4).map { $0.2 }
    }

    /// A bounded one-edit search covers replacement, omission, insertion and
    /// adjacent transposition without generating a permanent typo vocabulary.
    private static func editCost(_ a: [UInt8], _ b: [UInt8]) -> Double? {
        guard abs(a.count - b.count) <= 1 else { return nil }
        if a.count == b.count {
            var first: Int?
            for i in a.indices where a[i] != b[i] {
                guard let previous = first else { first = i; continue }
                // Two differences can only be an adjacent transposition.
                // Reject other paths immediately without allocating positions.
                guard i == previous + 1, a[previous] == b[i], a[i] == b[previous] else { return nil }
                return ((i + 1)..<a.count).allSatisfy { a[$0] == b[$0] } ? 0.85 : nil
            }
            return first == nil ? nil : 1
        }
        let shorter = a.count < b.count ? a : b, longer = a.count < b.count ? b : a
        var i = 0
        while i < shorter.count && shorter[i] == longer[i] { i += 1 }
        while i < shorter.count {
            if shorter[i] != longer[i + 1] { return nil }
            i += 1
        }
        return 1
    }
}
