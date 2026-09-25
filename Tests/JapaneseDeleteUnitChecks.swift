import Foundation

@main struct JapaneseDeleteUnitChecks {
    @MainActor static func main() throws {
        let resources = URL(fileURLWithPath: CommandLine.arguments[1])
        let userDirectory = FileManager.default.temporaryDirectory.appendingPathComponent("shika-japanese-raw-delete-\(UUID())")
        defer { try? FileManager.default.removeItem(at: userDirectory) }
        let engine = try SKJapaneseEngine(resources: resources, userDirectory: userDirectory)
        let table = try JSONDecoder().decode([String: [String]].self,
            from: Data(contentsOf: resources.appendingPathComponent("japanese-romaji.json")))
        var failures: [String] = [], count = 0
        func check(_ condition: Bool, _ label: String) {
            count += 1; if !condition { failures.append(label) }
        }
        let samples = Set(table.keys.filter { !$0.isEmpty }.flatMap { code in
            (1...code.count).map { String(code.prefix($0)) }
        })
        // The imported rules still drive Japanese candidate conversion. Visible
        // composition and backward deletion now retain the user's raw spelling.
        // Exercise the real engine instead of the removed kana re-encoder.
        for code in samples.sorted() {
            for prefix in ["", "kan'", "gakkou"] {
                let original = prefix + code
                var remaining = original
                var state = engine.replaceInput(original)
                while !remaining.isEmpty {
                    remaining.removeLast()
                    state = engine.process(key: 0xff08)
                    check(state.input == remaining && state.preedit == remaining && state.committedText.isEmpty,
                          "\(original): expected raw \(remaining), got input \(state.input) / preedit \(state.preedit)")
                }
                check(state.input.isEmpty && state.preedit.isEmpty && state.candidates.isEmpty,
                      "\(original) deletion must terminate with empty composition")
            }
        }
        for (input, expected) in [("ka", "k"), ("kya", "ky"), ("kka", "kk"),
                                  ("gakko", "gakk"), ("ky", "k"), ("n'", "n"),
                                  ("ko-hi-", "ko-hi"), ("kan'ya", "kan'y"),
                                  ("gakk", "gak"), ("kky", "kk"), ("ss", "s")] {
            _ = engine.replaceInput(input)
            let next = engine.process(key: 0xff08)
            check(next.input == expected && next.preedit == expected && next.committedText.isEmpty,
                  "example \(input) -> raw \(next.input) / \(next.preedit)")
        }
        print("\(failures.isEmpty ? "PASS" : "FAIL") \(count) Japanese raw-input deletion invariants over \(table.count) imported romaji rules and their \(samples.count) distinct prefixes")
        for failure in failures { print(failure) }
        if !failures.isEmpty { exit(1) }
    }
}
