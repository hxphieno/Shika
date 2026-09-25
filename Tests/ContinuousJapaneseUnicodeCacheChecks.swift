// Compare UTF-8, not Swift String equality: canonical equivalence is not the
// byte-based vocabulary contract. Run unchanged against baseline and candidate.
import Foundation

@main struct ContinuousJapaneseUnicodeCacheChecks {
    static func bytes(_ values: [String]) -> [[UInt8]] { values.map { Array($0.utf8) } }
    static func main() throws {
        let a = CommandLine.arguments, resources = URL(fileURLWithPath: CommandLine.arguments[1])
        let pairs = [("ba", "ば", "は\u{3099}"), ("pa", "ぱ", "は\u{309A}"), ("ga", "が", "か\u{3099}"), ("za", "ざ", "さ\u{3099}"), ("vu", "ゔ", "う\u{3099}")]
        var rows: [[String: Any]] = [], checks: [[String: Any]] = []
        for (id, composed, decomposed) in pairs {
            let freshC = try SKJapaneseLexicon(resources: resources).convert(composed)
            let freshD = try SKJapaneseLexicon(resources: resources).convert(decomposed)
            let cFirst = try SKJapaneseLexicon(resources: resources)
            let c1 = cFirst.convert(composed), d2 = cFirst.convert(decomposed)
            let dFirst = try SKJapaneseLexicon(resources: resources)
            let d1 = dFirst.convert(decomposed), c2 = dFirst.convert(composed)
            let freshDistinct = bytes(freshC) != bytes(freshD)
            let firstPreserved = bytes(c1) == bytes(freshC) && bytes(d1) == bytes(freshD)
            let forwardPreserved = bytes(d2) == bytes(freshD)
            let reversePreserved = bytes(c2) == bytes(freshC)
            checks.append(["label": "\(id): first lookup preserves fresh bytes", "passed": firstPreserved])
            checks.append(["label": "\(id): NFC then NFD preserves independent bytes", "passed": forwardPreserved])
            checks.append(["label": "\(id): NFD then NFC preserves independent bytes", "passed": reversePreserved])
            rows.append(["id": id, "composedUTF8": Array(composed.utf8), "decomposedUTF8": Array(decomposed.utf8), "swiftStringsEqual": composed == decomposed, "freshByteResultsDistinct": freshDistinct,
                         "freshComposed": freshC, "freshDecomposed": freshD, "freshComposedUTF8": bytes(freshC), "freshDecomposedUTF8": bytes(freshD),
                         "composedThenDecomposedUTF8": bytes(d2), "decomposedThenComposedUTF8": bytes(c2),
                         "forwardPreserved": forwardPreserved, "reversePreserved": reversePreserved])
        }
        let mapping = try JSONDecoder().decode([String: [String]].self, from: Data(contentsOf: resources.appendingPathComponent("japanese-romaji.json")))
        let nonNFC = mapping.filter { entry in entry.value.contains { Array($0.utf8) != Array($0.precomposedStringWithCanonicalMapping.utf8) } }
        let failed = checks.filter { $0["passed"] as? Bool != true }.count
        let output: [String: Any] = ["checks": checks, "passed": checks.count-failed, "failed": failed, "results": rows, "romajiEntries": mapping.count, "romajiEntriesWithNonNFCOutput": nonNFC.count, "scope": "Internal convert API byte-preservation boundary; current romaji mapping reachability measured separately"]
        try JSONSerialization.data(withJSONObject: output, options: [.prettyPrinted,.sortedKeys]).write(to: URL(fileURLWithPath: a[2]))
        print("\(checks.count-failed)/\(checks.count) byte-preservation checks; non-NFC romaji mappings \(nonNFC.count)")
        if failed > 0 { exit(1) }
    }
}
