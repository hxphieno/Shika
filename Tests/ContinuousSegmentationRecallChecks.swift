// Read-only discovery of native-backed alternatives missed by the one-path budget.
// Source terms are frozen before lookup; these are not a natural-input accuracy set.
import Foundation

@main struct ContinuousSegmentationRecallChecks {
    static func decode(_ data: [AnyHashable: Any]) -> SKEngineState {
        SKEngineState(input: data["input"] as? String ?? "", preedit: data["preedit"] as? String ?? "",
            candidates: (data["candidates"] as? [[String: Any]] ?? []).compactMap {
                guard let index = $0["index"] as? Int, let text = $0["text"] as? String else { return nil }
                return SKCandidate(index: index, text: text, comment: $0["comment"] as? String ?? "")
            }, committedText: data["commit"] as? String ?? "", page: data["page"] as? Int ?? 0)
    }
    static func code(_ text: String) -> String { text.split(whereSeparator: { $0 == " " || $0 == "'" }).joined(separator: "'") }
    static func paths(_ input: String, syllables: Set<String>) -> [String] {
        let raw = Array(input)
        guard (3...32).contains(raw.count), raw.allSatisfy({ $0.isASCII && $0.isLowercase }) else { return [] }
        var result = Array(repeating: [[String]](), count: raw.count + 1); result[raw.count] = [[]]
        for start in stride(from: raw.count - 1, through: 0, by: -1) {
            for end in (start + 1)...min(raw.count, start + 6) {
                let syllable = String(raw[start..<end])
                if syllables.contains(syllable) { result[start] += result[end].map { [syllable] + $0 } }
            }
            result[start] = Array(result[start].sorted {
                $0.count == $1.count ? $0.joined(separator: "'") < $1.joined(separator: "'") : $0.count < $1.count
            }.prefix(8))
        }
        return result[0].map { $0.joined(separator: "'") }
    }
    static func row(_ c: SKCandidate) -> [String: Any] { ["text": c.text, "comment": c.comment, "index": c.index] }
    @MainActor static func main() throws {
        let a = CommandLine.arguments
        let resources = URL(fileURLWithPath: a[1])
        let cases = try JSONSerialization.jsonObject(with: Data(contentsOf: URL(fileURLWithPath: a[3]))) as! [[String: Any]]
        let mapping = try JSONDecoder().decode([String: String].self, from: Data(contentsOf: resources.appendingPathComponent("correction-syllables.json")))
        let syllables = Set(mapping.keys).union(["nue", "lue"])
        let session = try SKRimeSession(sharedPath: a[1], userPath: a[2], schema: "shika_pinyin")
        let probe = try SKRimeSession(sharedPath: a[1], userPath: a[2], schema: "shika_pinyin")
        let presenter = SKPinyinSegmentationCandidates(resources: resources, configuration: SKChineseJapaneseScheme.configuration)!
        var results: [[String: Any]] = [], scanned = 0, ambiguous = 0, firstFailure = 0, recoverable = 0
        var timings: [Double] = []
        for test in cases {
            let input = test["input"] as! String, all = paths(input, syllables: syllables)
            scanned += 1
            guard all.count > 1 else { continue }; ambiguous += 1
            let state = decode(session.replaceInput(input))
            guard state.page == 0, state.committedText.isEmpty, !state.preedit.unicodeScalars.contains(where: {$0.value > 127}) else {continue}
            let existingPaths = Set(state.candidates.map { code($0.comment) }), texts = Set(state.candidates.map(\.text))
            let missing = all.filter { !existingPaths.contains($0) }
            guard !missing.isEmpty else { continue }
            var observations: [[String: Any]] = []
            for path in missing {
                let start = DispatchTime.now().uptimeNanoseconds
                let result = decode(probe.replaceInput(path))
                let ms = Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000
                timings.append(ms)
                let exact = result.candidates.first { code($0.comment) == path }
                observations.append(["path": path, "candidates": result.candidates.map(row), "firstExact": exact.map(row) ?? [:], "novel": exact.map { !texts.contains($0.text) } ?? false, "ms": ms])
            }
            guard observations.first?["novel"] as? Bool == false else { continue }; firstFailure += 1
            let recovered = observations.dropFirst().first { $0["novel"] as? Bool == true }
            if recovered != nil { recoverable += 1 }
            let actual = presenter.present(state) { decode(probe.replaceInput($0)) }
            results.append(["source": test, "input": input, "native": state.candidates.map(row), "displayed": actual.candidates.map(row), "paths": all, "probes": observations, "recoverable": recovered != nil])
        }
        timings.sort()
        let output: [String: Any] = ["scanned": scanned, "ambiguous": ambiguous, "firstProbeNoNovel": firstFailure, "laterProbeNovel": recoverable, "queryCount": timings.count, "queryP95MS": timings.isEmpty ? 0 : timings[min(timings.count-1, Int(Double(timings.count)*0.95))], "results": results, "scope": "Native-backed alternative discovery; no quality target inferred from lookup; no training selections"]
        try JSONSerialization.data(withJSONObject: output, options: [.prettyPrinted,.sortedKeys]).write(to: URL(fileURLWithPath: a[4]))
        print("scanned \(scanned), ambiguous \(ambiguous), first failed \(firstFailure), later recovered \(recoverable)")
    }
}
