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
    struct Completion {
        let reading: String
        let word: Word
        let isLiteral: Bool
    }
    private let data: Data
    private let connections: Data
    private let count: Int
    private let tokenStart: Int
    private let pool: Int
    private let dimension: Int
    private let roman: [String: [String]]
    // This layer has no user history. The engine reapplies learned ranking to
    // these immutable conversion results on every input, including cache hits.
    // Match the lexicon's UTF-8 lookup semantics. Swift String keys would merge
    // canonically equivalent but byte-distinct readings (ば and は + U+3099).
    private var conversionCache: [Data: [String]] = [:]
    private var conversionCacheOrder: [Data] = []
    private var completionCache: [String: [Completion]] = [:]
    private var completionCacheOrder: [String] = []

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

    func words(for reading: String) -> [Word] {
        lookup(reading, completing: false).map(\.word)
    }

    private func lookup(_ reading: String, completing: Bool) -> [(reading: String, word: Word)] {
        let key = Array(reading.utf8)
        return data.withUnsafeBytes { bytes in
            func readingBytes(_ index: Int) -> UnsafeRawBufferPointer {
                let record = 16 + index * 12
                let start = pool + Int(bytes.loadUnaligned(fromByteOffset: record, as: UInt32.self).littleEndian)
                let length = Int(bytes.loadUnaligned(fromByteOffset: record + 4, as: UInt16.self).littleEndian)
                guard start <= bytes.count, length <= bytes.count - start else { return UnsafeRawBufferPointer(start: nil, count: 0) }
                return UnsafeRawBufferPointer(rebasing: bytes[start..<(start + length)])
            }
            var low = 0, high = count
            while low < high {
                let mid = (low + high) / 2
                if readingBytes(mid).lexicographicallyPrecedes(key) { low = mid + 1 }
                else { high = mid }
            }
            var result: [(reading: String, word: Word)] = []
            while low < count {
                let candidate = readingBytes(low)
                guard completing ? candidate.starts(with: key) : candidate.elementsEqual(key) else { break }
                let reading = String(decoding: candidate, as: UTF8.self)
                let record = 16 + low * 12
                let n = Int(bytes.loadUnaligned(fromByteOffset: record + 6, as: UInt16.self).littleEndian)
                let first = Int(bytes.loadUnaligned(fromByteOffset: record + 8, as: UInt32.self).littleEndian)
                guard tokenStart + (first + n) * 12 <= pool else { break }
                for index in first..<(first + n) {
                    let offset = tokenStart + index * 12
                    let start = pool + Int(bytes.loadUnaligned(fromByteOffset: offset, as: UInt32.self).littleEndian)
                    let length = Int(bytes.loadUnaligned(fromByteOffset: offset + 4, as: UInt16.self).littleEndian)
                    guard start <= bytes.count, length <= bytes.count - start else { continue }
                    let word = Word(text: String(decoding: bytes[start..<(start + length)], as: UTF8.self),
                        left: Int(bytes.loadUnaligned(fromByteOffset: offset + 6, as: UInt16.self).littleEndian),
                        right: Int(bytes.loadUnaligned(fromByteOffset: offset + 8, as: UInt16.self).littleEndian),
                        cost: Int(bytes.loadUnaligned(fromByteOffset: offset + 10, as: Int16.self).littleEndian))
                    result.append((reading, word))
                }
                if !completing { break }
                low += 1
            }
            return result
        }
    }

    /// Complete only legal romaji rules at the active tail. The raw composition
    /// stays untouched; each choice carries its completed reading for learning.
    func completionWords(for input: String) -> [Completion] {
        if let cached = completionCache[input] { return cached }
        let partial = reading(input)
        guard !partial.pending.isEmpty else { return [] }
        let readings = Set(roman.compactMap { code, value -> String? in
            guard code.hasPrefix(partial.pending), code != partial.pending,
                  value.count == 2, value[1].isEmpty else { return nil }
            return partial.kana + value[0]
        })
        var choices: [Completion] = []
        for reading in readings.sorted() {
            // One kana can cover most of a dictionary section. Keep that case
            // to syllable completions; longer prefixes also predict whole words.
            choices += lookup(reading, completing: reading.count >= 2).map {
                Completion(reading: $0.reading, word: $0.word, isLiteral: false)
            }
            choices.append(Completion(reading: reading,
                word: Word(text: reading, left: 0, right: 0, cost: 18000), isLiteral: true))
        }
        // Score once per word, not once per sort comparison across a prefix
        // range. Cache only immutable results; engines apply learning afterward.
        let scored = choices.map { choice in
            (choice: choice, cost: choice.word.cost + connection(from: 0, to: choice.word.left)
                + connection(from: choice.word.right, to: 0))
        }
        var seen = Set<String>()
        let result = Array(scored.sorted {
            if $0.cost != $1.cost { return $0.cost < $1.cost }
            if $0.choice.word.text != $1.choice.word.text { return $0.choice.word.text < $1.choice.word.text }
            return $0.choice.reading < $1.choice.reading
        }.map(\.choice).filter { seen.insert($0.word.text).inserted }.prefix(64))
        if completionCacheOrder.count == 32 {
            completionCache.removeValue(forKey: completionCacheOrder.removeFirst())
        }
        completionCacheOrder.append(input); completionCache[input] = result
        return result
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
        let cacheKey = Data(kana.utf8)
        if let cached = conversionCache[cacheKey] { return cached }
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
        if conversionCacheOrder.count == 16 {
            conversionCache.removeValue(forKey: conversionCacheOrder.removeFirst())
        }
        conversionCacheOrder.append(cacheKey); conversionCache[cacheKey] = result
        return result
    }
}
