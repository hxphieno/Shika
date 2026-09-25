import Foundation

/// A memory-mapped sorted index, loaded for one scheme only. Records are 16 bytes;
/// words/codes stay in the mapped byte pool instead of tens of thousands of objects.
final class SKSpellingCorrector {
    struct Suggestion {
        let code: String
        let text: String
        let frequency: Double
        let cost: Double
        var score: Double { log(frequency + 1) - 2.5 * cost }
    }
    private let data: Data
    private let count: Int
    private let pool: Int
    private let syllables: [String: String]
    private let profile: SKSpellingProfile
    private static let alphabet = Array(UInt8(97)...UInt8(122))
    private static let positions: [UInt8: (Double, Double)] = {
        var result: [UInt8: (Double, Double)] = [:]
        for (row, text) in ["qwertyuiop", "asdfghjkl", "zxcvbnm"].enumerated() {
            for (column, key) in text.utf8.enumerated() {
                result[key] = (Double(column) + [0, 0.5, 1.5][row], Double(row))
            }
        }
        return result
    }()

    init?(resources: URL, configuration: SKInputConfiguration) {
        guard let bytes = try? Data(contentsOf: resources.appendingPathComponent(configuration.schemaID + ".correction.bin"), options: .mappedIfSafe),
              bytes.count >= 8, bytes.prefix(4) == Data("SKC1".utf8) else { return nil }
        let n = bytes.withUnsafeBytes { Int($0.loadUnaligned(fromByteOffset: 4, as: UInt32.self).littleEndian) }
        guard n > 0, n <= (bytes.count - 8) / 16 else { return nil }
        data = bytes; count = n; pool = 8 + n * 16
        profile = configuration.spelling
        syllables = profile.syllableResource.flatMap { name in
            try? JSONDecoder().decode([String: String].self,
                from: Data(contentsOf: resources.appendingPathComponent(name)))
        } ?? [:]
    }

    /// Rime's spelling comment describes the whole candidate, including learned
    /// phrases. Comparing its canonical code protects exact user words as well.
    func isExact(comment: String, input: String) -> Bool {
        profile.isExact(comment: comment, input: input, syllables: syllables)
    }

    func suggestions(for input: String) -> [Suggestion] {
        let code = Array(input.utf8)
        // Explicit syllable delimiters are intentional. Short prefixes are still
        // being typed; arbitrary long text must not cause unbounded decoding.
        guard (3...48).contains(code.count), code.allSatisfy({ (97...122).contains($0) }) else { return [] }
        var variants: [[UInt8]: Double] = [:]
        func add(_ value: [UInt8], _ cost: Double) {
            guard value != code else { return }
            variants[value] = min(variants[value] ?? .infinity, cost)
        }
        for i in code.indices {
            var removed = code; removed.remove(at: i); add(removed, 1)
            for key in Self.alphabet where key != code[i] {
                var changed = code; changed[i] = key
                let a = Self.positions[key]!, b = Self.positions[code[i]]!
                let nearby = hypot(a.0 - b.0, a.1 - b.1) <= 1.25
                add(changed, nearby ? 1 : 1.5)
            }
            if i + 1 < code.count {
                var swapped = code; swapped.swapAt(i, i + 1); add(swapped, 0.85)
            }
        }
        for i in 0...code.count {
            for key in Self.alphabet {
                var inserted = code; inserted.insert(key, at: i); add(inserted, 1)
            }
        }
        return data.withUnsafeBytes { bytes in
            var matches: [Suggestion] = []
            for (variant, cost) in variants {
                var low = 0, high = count
                while low < high {
                    let mid = (low + high) / 2, record = 8 + mid * 16
                    let offset = pool + Int(bytes.loadUnaligned(fromByteOffset: record, as: UInt32.self).littleEndian)
                    let length = Int(bytes.loadUnaligned(fromByteOffset: record + 4, as: UInt16.self).littleEndian)
                    guard offset <= bytes.count, length <= bytes.count - offset else { break }
                    var order = 0
                    for i in 0..<min(length, variant.count) {
                        if bytes[offset + i] != variant[i] { order = bytes[offset + i] < variant[i] ? -1 : 1; break }
                    }
                    if order == 0 { order = length == variant.count ? 0 : (length < variant.count ? -1 : 1) }
                    if order < 0 { low = mid + 1 }
                    else if order > 0 { high = mid }
                    else {
                        let textOffset = pool + Int(bytes.loadUnaligned(fromByteOffset: record + 8, as: UInt32.self).littleEndian)
                        let textLength = Int(bytes.loadUnaligned(fromByteOffset: record + 6, as: UInt16.self).littleEndian)
                        guard textOffset <= bytes.count, textLength <= bytes.count - textOffset else { break }
                        let word = String(decoding: bytes[textOffset..<(textOffset + textLength)], as: UTF8.self)
                        let frequency = Double(bytes.loadUnaligned(fromByteOffset: record + 12, as: UInt32.self).littleEndian)
                        matches.append(Suggestion(code: String(decoding: variant, as: UTF8.self), text: word, frequency: frequency, cost: cost))
                        break
                    }
                }
            }
            return matches.sorted { $0.score == $1.score ? $0.code < $1.code : $0.score > $1.score }.prefix(12).map { $0 }
        }
    }
}
