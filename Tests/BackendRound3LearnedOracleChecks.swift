import Foundation

/// Exhaustive short-code oracle for the learned index; expected costs are
/// computed by deleting/swapping characters, separately from its scan algorithm.
@main struct BackendRound3LearnedOracleChecks {
    struct Entry: Codable { let code: String; let text: String }
    static func main() throws {
        let args = CommandLine.arguments, root = URL(fileURLWithPath: CommandLine.arguments[1])
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        func all(_ length: Int) -> [String] { if length == 0 { return [""] }; return all(length-1).flatMap { prefix in ["a", "b", "c"].map { prefix+$0 } } }
        func edit(_ a: [Character], _ b: [Character]) -> Double? {
            guard a != b, abs(a.count-b.count) <= 1 else { return nil }
            if a.count == b.count {
                // Compare each independently swapped sequence; repeated characters
                // and swaps at either end are covered by the exhaustive input set.
                for i in 0..<(a.count-1) { var swapped = a; swapped.swapAt(i,i+1); if swapped == b { return 0.85 } }
                return a.indices.filter { a[$0] != b[$0] }.count == 1 ? 1 : nil
            }
            let longer = a.count > b.count ? a : b, shorter = a.count > b.count ? b : a
            for i in longer.indices { var removed = longer; removed.remove(at: i); if removed == shorter { return 1 } }
            return nil
        }
        var total = 0, failed = 0, reports: [[String: Any]] = []
        for (name, profile) in [("double", SKSpellingProfile.doublePinyin), ("full", .fullPinyin)] {
            let directory = root.appendingPathComponent(name)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let codes = all(4) + (profile == .doublePinyin ? Array(all(6).prefix(243)) : all(5)) +
                ["abac", "abac", String(repeating: "a", count: 48), "ab"+String(repeating: "c", count: 46)]
            let entries = codes.enumerated().map { i, code in Entry(code: code, text: String(repeating: "词", count: (profile == .doublePinyin ? code.count/2 : max(2, (code.count+5)/6))-1)+String(UnicodeScalar(0x4e00+i)!)) }
            let filename = profile == .doublePinyin ? "double-pinyin-spelling.json" : "full-pinyin-spelling.json"
            try JSONEncoder().encode(entries).write(to: directory.appendingPathComponent(filename))
            let index = SKLearnedSpellingIndex(userDirectory: directory, profile: profile)
            let prepared = entries.map { Array($0.code) }
            let inputs = ["", "a", "ab", "ABC", "a'bc", "a bc", "a1bc", "你好", "ābc", String(repeating: "a", count: 50),
                String(repeating: "a", count: 47), String(repeating: "a", count: 48), String(repeating: "a", count: 49),
                "ba"+String(repeating: "c", count: 46), "abab"+String(repeating: "c", count: 44)] + (3...7).flatMap(all)
            var mismatches: [[String: Any]] = [], signatures: [String] = []
            for input in inputs {
                let valid = (3...49).contains(input.utf8.count) && input.utf8.allSatisfy { (97...122).contains($0) }, raw = Array(input)
                var scored: [(Int, Double)] = []
                if valid {
                    for i in entries.indices { if let value = edit(raw, prepared[i]) { scored.append((i, value)) } }
                }
                scored.sort { lhs, rhs in lhs.1 == rhs.1 ? lhs.0 > rhs.0 : lhs.1 < rhs.1 }
                let expected = scored.prefix(4).map { entries[$0.0].code + "|" + entries[$0.0].text }
                let actual = index.suggestions(for: input).map { $0.code+"|"+$0.text }
                total += 1
                if actual != expected { failed += 1; mismatches.append(["input": input, "expected": expected, "actual": actual]) }
                signatures.append(input+":"+actual.joined(separator: ";"))
            }
            reports.append(["profile": name, "entryCount": entries.count, "inputCount": inputs.count, "mismatches": mismatches, "signatures": signatures])
        }
        let result: [String: Any] = ["passed": total-failed, "failed": failed, "profiles": reports,
            "scope": "Exhaustive abc short codes and fixed length/Unicode boundaries; independent one-edit oracle; not natural language accuracy"]
        try JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys]).write(to: URL(fileURLWithPath: args[2]))
        print("learned oracle \(total-failed)/\(total)")
        if failed > 0 { exit(1) }
    }
}
