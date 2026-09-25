import Foundation

/// Read-only, mapped Mozc vocabulary and connection costs. No word objects are
/// materialized until a reading participates in the current conversion lattice.
final class SKJapaneseLexicon {
    struct Word {
        let text: String
        let left: Int
        let right: Int
        let cost: Int
    }
    private let data: Data
    private let connections: Data
    private let count: Int
    private let tokenStart: Int
    private let pool: Int
    private let dimension: Int
    private let roman: [String: [String]]

    init(resources: URL) throws {
        data = try Data(contentsOf: resources.appendingPathComponent("japanese-lexicon.bin"), options: .alwaysMapped)
        connections = try Data(contentsOf: resources.appendingPathComponent("japanese-connections.bin"), options: .alwaysMapped)
        roman = try JSONDecoder().decode([String: [String]].self,
            from: Data(contentsOf: resources.appendingPathComponent("japanese-romaji.json")))
        guard data.count >= 16, data.prefix(4) == Data("SKJ1".utf8),
              connections.count >= 8, connections.prefix(4) == Data("SKJM".utf8) else { throw SKRimeEngine.EngineError.missingResources }
        count = data.withUnsafeBytes { Int($0.loadUnaligned(fromByteOffset: 4, as: UInt32.self).littleEndian) }
        tokenStart = 16 + count * 12
        pool = data.withUnsafeBytes { Int($0.loadUnaligned(fromByteOffset: 12, as: UInt32.self).littleEndian) }
        dimension = connections.withUnsafeBytes { Int($0.loadUnaligned(fromByteOffset: 4, as: UInt32.self).littleEndian) }
        guard count > 0, tokenStart <= pool, pool <= data.count,
              dimension > 0, dimension <= 10000, connections.count == 8 + dimension * dimension * 2 else {
            throw SKRimeEngine.EngineError.missingResources
        }
    }

    func reading(_ input: String) -> (kana: String, pending: String) {
        var remaining = input, kana = ""
        while !remaining.isEmpty {
            // In konnichiha, the first n is ん and the second starts に.
            // An explicit n' or a terminal nn also produces a single ん.
            if remaining.hasPrefix("nn"), remaining.count > 2,
               let next = remaining.dropFirst(2).first, "aiueoy".contains(next) {
                kana += "ん"; remaining.removeFirst(); continue
            }
            var matched = false
            for length in stride(from: min(4, remaining.count), through: 1, by: -1) {
                let code = String(remaining.prefix(length))
                guard let value = roman[code], value.count == 2 else { continue }
                kana += value[0]
                remaining = value[1] + remaining.dropFirst(length)
                matched = true; break
            }
            if !matched { return (kana, remaining) }
        }
        return (kana, "")
    }

    /// Backspace follows the visible kana, not a hidden romaji keystroke history.
    /// Incomplete romaji still retreats one key; e.g. ky → k, but ka/か → empty.
    func removingLastUnit(kana: String, pending: String, preferring input: String) -> (literalPrefix: String, input: String) {
        let target = pending.isEmpty ? String(kana.dropLast()) : kana
        let targetPending = String(pending.dropLast())
        guard !target.isEmpty else { return ("", targetPending) }
        // Prefer the original spelling when a complete prefix represents it.
        var prefix = input
        while !prefix.isEmpty {
            prefix.removeLast()
            let decoded = reading(prefix)
            if decoded.pending == targetPending && decoded.kana == target { return ("", prefix) }
        }
        // Removing a small kana can change a syllable (kya/きゃ → ki/き).
        // A carried consonant also needs reconstruction: gakk/がっk → がっ.
        // Use the same imported romaji rules to encode the remaining reading.
        var codes: [String: String] = [:]
        for (code, value) in roman where value.count == 2 && value[1].isEmpty && !value[0].isEmpty {
            let kana = value[0]
            if let old = codes[kana], old.count < code.count || (old.count == code.count && old < code) { continue }
            codes[kana] = code
        }
        codes["ん"] = "n'" // An n followed by a vowel must remain syllabic ん.
        let tokens = codes.keys.sorted { $0.count == $1.count ? $0 < $1 : $0.count > $1.count }
        var remaining = target, result = ""
        while !remaining.isEmpty {
            guard let token = tokens.first(where: { remaining.hasPrefix($0) }), let code = codes[token] else {
                // Some imported rules emit literal Latin text. Keep completed
                // text separate instead of feeding it through romaji a second time.
                return (target, targetPending)
            }
            result += code; remaining.removeFirst(token.count)
        }
        return ("", result + targetPending)
    }

    func words(for reading: String) -> [Word] {
        let key = Array(reading.utf8)
        return data.withUnsafeBytes { bytes in
            var low = 0, high = count
            while low < high {
                let mid = (low + high) / 2, record = 16 + mid * 12
                let start = pool + Int(bytes.loadUnaligned(fromByteOffset: record, as: UInt32.self).littleEndian)
                let length = Int(bytes.loadUnaligned(fromByteOffset: record + 4, as: UInt16.self).littleEndian)
                guard start <= bytes.count, length <= bytes.count - start else { return [] }
                var order = 0
                for i in 0..<min(length, key.count) where bytes[start + i] != key[i] {
                    order = bytes[start + i] < key[i] ? -1 : 1; break
                }
                if order == 0 { order = length == key.count ? 0 : (length < key.count ? -1 : 1) }
                if order < 0 { low = mid + 1; continue }
                if order > 0 { high = mid; continue }
                let n = Int(bytes.loadUnaligned(fromByteOffset: record + 6, as: UInt16.self).littleEndian)
                let first = Int(bytes.loadUnaligned(fromByteOffset: record + 8, as: UInt32.self).littleEndian)
                guard tokenStart + (first + n) * 12 <= pool else { return [] }
                return (first..<(first + n)).compactMap { index in
                    let offset = tokenStart + index * 12
                    let start = pool + Int(bytes.loadUnaligned(fromByteOffset: offset, as: UInt32.self).littleEndian)
                    let length = Int(bytes.loadUnaligned(fromByteOffset: offset + 4, as: UInt16.self).littleEndian)
                    guard start <= bytes.count, length <= bytes.count - start else { return nil }
                    return Word(text: String(decoding: bytes[start..<(start + length)], as: UTF8.self),
                        left: Int(bytes.loadUnaligned(fromByteOffset: offset + 6, as: UInt16.self).littleEndian),
                        right: Int(bytes.loadUnaligned(fromByteOffset: offset + 8, as: UInt16.self).littleEndian),
                        cost: Int(bytes.loadUnaligned(fromByteOffset: offset + 10, as: Int16.self).littleEndian))
                }
            }
            return []
        }
    }

    func connection(from right: Int, to left: Int) -> Int {
        guard right < dimension, left < dimension, right >= 0, left >= 0 else { return 20000 }
        return connections.withUnsafeBytes {
            Int($0.loadUnaligned(fromByteOffset: 8 + (right * dimension + left) * 2, as: Int16.self).littleEndian)
        }
    }

    /// Bounded N-best Viterbi search over all matching word boundaries. This is
    /// our decoder using Mozc data, not a port of Mozc's complete converter.
    func convert(_ kana: String) -> [String] {
        struct Path { let text: String; let right: Int; let cost: Int }
        let characters = Array(kana)
        guard !characters.isEmpty, characters.count <= 80 else { return kana.isEmpty ? [] : [kana] }
        var lattice = Array(repeating: [Path](), count: characters.count + 1)
        lattice[0] = [Path(text: "", right: 0, cost: 0)]
        for start in characters.indices {
            // Keep POS alternatives, not only differently spelled surfaces.
            var seen = Set<String>()
            let incoming = lattice[start].sorted { $0.cost == $1.cost ? $0.text < $1.text : $0.cost < $1.cost }
                .filter { seen.insert("\($0.right):\($0.text)").inserted }.prefix(32)
            guard !incoming.isEmpty else { continue }
            for end in (start + 1)...min(characters.count, start + 32) {
                let reading = String(characters[start..<end])
                var words = words(for: reading)
                if end == start + 1 {
                    words.append(Word(text: reading, left: 0, right: 0, cost: 18000))
                }
                // There can be hundreds of homophones. The connection cost
                // participates before pruning, so grammatical options survive.
                var additions: [Path] = []
                for word in words {
                    for previous in incoming {
                        additions.append(Path(text: previous.text + word.text, right: word.right,
                            cost: previous.cost + word.cost + connection(from: previous.right, to: word.left)))
                    }
                }
                lattice[end] += additions
                if lattice[end].count > 128 {
                    var seen = Set<String>()
                    lattice[end] = Array(lattice[end].sorted { $0.cost == $1.cost ? $0.text < $1.text : $0.cost < $1.cost }
                        .filter { seen.insert("\($0.right):\($0.text)").inserted }.prefix(64))
                }
            }
        }
        let final = lattice[characters.count].sorted {
            let a = $0.cost + connection(from: $0.right, to: 0)
            let b = $1.cost + connection(from: $1.right, to: 0)
            return a == b ? $0.text < $1.text : a < b
        }
        var seen = Set<String>()
        var result = Array(final.map(\.text).filter { seen.insert($0).inserted }.prefix(20))
        let katakana = String(String.UnicodeScalarView(kana.unicodeScalars.map {
            (0x3041...0x3096).contains($0.value) ? UnicodeScalar($0.value + 0x60)! : $0
        }))
        for literal in [kana, katakana] where seen.insert(literal).inserted { result.append(literal) }
        return result
    }
}
