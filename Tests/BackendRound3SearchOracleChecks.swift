import Foundation

/// Independent exhaustive comparison against each fixture dictionary entry. The
/// oracle does not enumerate search variants or reuse production comparison code.
@main struct BackendRound3SearchOracleChecks {
    struct Word { let code: String; let text: String; let frequency: UInt32 }
    static func main() throws {
        let args = CommandLine.arguments, root = URL(fileURLWithPath: CommandLine.arguments[1])
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        func append<T: FixedWidthInteger>(_ value: T, to data: inout Data) { var n = value.littleEndian; withUnsafeBytes(of: &n) { data.append(contentsOf: $0) } }
        func write(_ words: [Word], schema: String) throws {
            var records = Data(), pool = Data()
            for w in words.sorted(by: { $0.code < $1.code }) {
                let offset = UInt32(pool.count); pool.append(contentsOf: w.code.utf8)
                let textOffset = UInt32(pool.count); pool.append(contentsOf: w.text.utf8)
                append(offset, to: &records); append(UInt16(w.code.utf8.count), to: &records); append(UInt16(w.text.utf8.count), to: &records)
                append(textOffset, to: &records); append(w.frequency, to: &records)
            }
            var data = Data("SKC1".utf8); append(UInt32(words.count), to: &data); data.append(records); data.append(pool)
            try data.write(to: root.appendingPathComponent(schema + ".correction.bin"))
        }
        let rows = ["qwertyuiop", "asdfghjkl", "zxcvbnm"].map(Array.init)
        func coordinate(_ c: Character) -> (Double, Double) {
            for (r, row) in rows.enumerated() { if let x = row.firstIndex(of: c) { return (Double(x) + [0, 0.5, 1.5][r], Double(r)) } }
            fatalError("nonkeyboard fixture")
        }
        func cost(_ raw: String, _ target: String) -> Double? {
            let a = Array(raw), b = Array(target)
            if a == b || abs(a.count-b.count) > 1 { return nil }
            if a.count == b.count {
                let different = a.indices.filter { a[$0] != b[$0] }
                if different.count == 1 {
                    let p = coordinate(a[different[0]]), q = coordinate(b[different[0]])
                    let distanceSquared = (p.0-q.0)*(p.0-q.0) + (p.1-q.1)*(p.1-q.1)
                    return distanceSquared <= 1.25*1.25 ? 1 : 1.5
                }
                if different.count == 2 && different[1] == different[0]+1 && a[different[0]] == b[different[1]] && a[different[1]] == b[different[0]] { return 0.85 }
                return nil
            }
            let shorter = a.count < b.count ? a : b, longer = a.count < b.count ? b : a
            // Exhaustive removal is deliberately different from production generation.
            for index in longer.indices { var rest = longer; rest.remove(at: index); if rest == shorter { return 1 } }
            return nil
        }
        var seed: UInt64 = 0x5368696b6133
        func random(_ bound: Int) -> Int { seed = seed &* 6364136223846793005 &+ 1442695040888963407; return Int(seed >> 32) % bound }
        let alphabet = Array("abcdefghijklmnopqrstuvwxyz")
        let pairs = ["ma", "ni", "hc", "vs", "go", "xi", "an", "ui", "jp"]
        try JSONSerialization.data(withJSONObject: Dictionary(uniqueKeysWithValues: pairs.map { ($0, $0) }), options: [.sortedKeys]).write(to: root.appendingPathComponent("correction-syllables.json"))
        var reports: [[String: Any]] = [], total = 0, failed = 0
        for (schema, profile) in [("shika_flypy", SKSpellingProfile.doublePinyin), ("shika_pinyin", .fullPinyin)] {
            var codes = Set<String>()
            for _ in 0..<120 {
                codes.insert(profile == .doublePinyin ? (0..<(2+random(3))).map { _ in pairs[random(pairs.count)] }.joined() : String((0..<(3+random(9))).map { _ in alphabet[random(26)] }))
            }
            codes.formUnion(profile == .doublePinyin ? ["mama", "nini", "mamani", "mamama", String(repeating: "ma", count: 24)] : ["abcd", "abce", "abcf", "abcg", "abch", "abci", "abcj", "abck", "abcl", "abcm", "abcn", "abco", "abcp", "abcq", "abcr", "abcde", "aaaa", "baaa", String(repeating: "a", count: 48)])
            let words = codes.sorted().enumerated().map { Word(code: $0.element, text: "词\($0.offset)", frequency: UInt32(($0.offset % 9 + 1) * 100)) }
            try write(words, schema: schema)
            let corrector = SKSpellingCorrector(resources: root, configuration: SKInputConfiguration(schemaID: schema, inputPolicy: .chineseRomanization, spelling: profile))!
            var inputs = Set(["", "a", "ab", "abc", "abca", "ABC", "ni'hao", "nǐhao", "中文", "a b", "a1c", String(repeating: "a", count: 49)])
            for word in words {
                inputs.insert(word.code)
                let chars = Array(word.code)
                for i in chars.indices {
                    var removed = chars; removed.remove(at: i); inputs.insert(String(removed))
                    if i+1 < chars.count { var swapped = chars; swapped.swapAt(i,i+1); inputs.insert(String(swapped)) }
                    for key in [Character("a"), Character("q"), Character("z")] { var replaced = chars; replaced[i] = key; inputs.insert(String(replaced)) }
                }
                for i in [0, chars.count/2, chars.count] { var inserted = chars; inserted.insert("x", at: i); inputs.insert(String(inserted)) }
            }
            var mismatches: [[String: Any]] = [], actualSignatures: [String] = []
            for input in inputs.sorted() {
                let allowed = (3...48).contains(input.utf8.count) && input.utf8.allSatisfy { (97...122).contains($0) }
                let expected = allowed ? words.compactMap { w -> (Word, Double)? in cost(input,w.code).map { (w,$0) } }.sorted {
                    let lhs = log(Double($0.0.frequency)+1)-2.5*$0.1, rhs = log(Double($1.0.frequency)+1)-2.5*$1.1
                    return lhs == rhs ? $0.0.code < $1.0.code : lhs > rhs
                }.prefix(12).map { "\($0.0.code)|\($0.0.text)|\($0.1)|\(Double($0.0.frequency))" } : []
                let actual = corrector.suggestions(for: input).map { "\($0.code)|\($0.text)|\($0.cost)|\($0.frequency)" }
                let cached = corrector.suggestions(for: input).map { "\($0.code)|\($0.text)|\($0.cost)|\($0.frequency)" }
                total += 2
                if actual != expected { failed += 1; mismatches.append(["input": input, "actual": actual, "expected": expected]) }
                if cached != expected { failed += 1; mismatches.append(["input": input, "cacheMismatch": true]) }
                actualSignatures.append(input+":"+actual.joined(separator: ";"))
            }
            // A second sweep also exercises cache eviction, which immediate retype does not.
            for (input, signature) in zip(inputs.sorted(), actualSignatures) {
                total += 1
                let actual = input+":"+corrector.suggestions(for: input).map { "\($0.code)|\($0.text)|\($0.cost)|\($0.frequency)" }.joined(separator: ";")
                if actual != signature { failed += 1; mismatches.append(["input": input, "evictionMismatch": true]) }
            }
            reports.append(["schema": schema, "dictionaryCount": words.count, "inputCount": inputs.count, "mismatches": mismatches, "signatures": actualSignatures])
        }
        let report: [String: Any] = ["passed": total-failed, "failed": failed, "profiles": reports,
            "scope": "Independent direct per-entry one-edit oracle on synthetic sorted dictionaries; cold, hot and eviction paths; not corpus accuracy"]
        try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]).write(to: URL(fileURLWithPath: args[2]))
        print("search oracle \(total-failed)/\(total)")
        if failed > 0 { exit(1) }
    }
}
