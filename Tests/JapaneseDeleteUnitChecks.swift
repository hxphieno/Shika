import Foundation

@main struct JapaneseDeleteUnitChecks {
    @MainActor static func main() throws {
        let resources = URL(fileURLWithPath: CommandLine.arguments[1])
        let lexicon = try SKJapaneseLexicon(resources: resources)
        let table = try JSONDecoder().decode([String: [String]].self,
            from: Data(contentsOf: resources.appendingPathComponent("japanese-romaji.json")))
        var failures: [String] = [], count = 0
        func check(_ condition: Bool, _ label: String) {
            count += 1; if !condition { failures.append(label) }
        }
        let samples = Set(table.keys.flatMap { code in (1...code.count).map { String(code.prefix($0)) } })
        for code in samples.sorted() {
            for prefix in ["", "kan'", "gakkou"] {
                var raw = prefix + code
                var previous = lexicon.reading(raw)
                var budget = raw.count + previous.kana.count + 4
                while !raw.isEmpty && budget > 0 {
                    budget -= 1
                    let next = lexicon.removingLastUnit(kana: previous.kana, pending: previous.pending, preferring: raw)
                    let decoded = lexicon.reading(next.input)
                    let visible = (kana: next.literalPrefix + decoded.kana, pending: decoded.pending)
                    if previous.pending.isEmpty {
                        check(visible.kana == String(previous.kana.dropLast()) && visible.pending.isEmpty,
                              "\(raw): \(previous.kana) -> \(next) / \(visible)")
                    } else {
                        check(visible.kana == previous.kana && visible.pending == String(previous.pending.dropLast()),
                              "pending \(raw) must preserve kana and lose one visible key: \(visible)")
                    }
                    raw = next.literalPrefix + next.input; previous = visible
                }
                check(raw.isEmpty, "\(prefix + code) deletion must terminate")
            }
        }
        for (input, kana, pending) in [("ka", "", ""), ("kya", "き", ""), ("kka", "っ", ""),
                                        ("gakko", "がっ", ""), ("ky", "", "k"), ("n'", "", ""),
                                        ("ko-hi-", "こーひ", ""), ("kan'ya", "かん", ""),
                                        ("gakk", "がっ", ""), ("kky", "っ", "k"), ("ss", "っ", "")] {
            let current = lexicon.reading(input)
            let next = lexicon.removingLastUnit(kana: current.kana, pending: current.pending, preferring: input)
            let decoded = lexicon.reading(next.input)
            check(next.literalPrefix + decoded.kana == kana && decoded.pending == pending, "example \(input) -> \(next)")
        }
        print("\(failures.isEmpty ? "PASS" : "FAIL") \(count) Japanese deletion invariants over \(table.count) imported romaji rules and their \(samples.count) distinct prefixes")
        for failure in failures { print(failure) }
        if !failures.isEmpty { exit(1) }
    }
}
