import Foundation

/// Independent contract checks. Real production Rime + session, no UIKit or mocks.
/// Run behavior with a fresh user directory; run learn then probe in separate
/// processes sharing another fresh directory. Never share either with ranking.
@main struct ShuangpinOptimizationBehaviorChecks {
    @MainActor static func main() throws {
        let args = CommandLine.arguments
        guard args.count == 5, ["behavior", "learn", "probe", "index"].contains(args[4]) else {
            fatalError("Usage: checks resources user report.json behavior|learn|probe|index")
        }
        let resource = URL(fileURLWithPath: args[1]), user = URL(fileURLWithPath: args[2])
        try FileManager.default.createDirectory(at: user, withIntermediateDirectories: true)
        let double = SKInputScheme.shuangpin.configuration
        let full = SKInputScheme.chineseJapanese.configuration
        let engine = try SKRimeEngine(configuration: double, resourceURL: resource, userURL: user)
        var output = "", marked = "", insertions: [String] = [], deletes = 0
        let session = SKInputSession(engine: engine, configuration: double,
            insertText: { output += $0; insertions.append($0) },
            deleteText: { deletes += 1; if !output.isEmpty { output.removeLast() } },
            updateComposition: { marked = $0 })
        var checks: [[String: Any]] = [], observations: [[String: Any]] = []
        func check(_ name: String, _ passed: Bool, _ detail: String = "") {
            checks.append(["name": name, "passed": passed, "detail": detail])
            print("\(passed ? "PASS" : "FAIL"): \(name) \(detail)")
        }
        func type(_ raw: String) { for c in raw { session.type(String(c)) } }
        func reset(_ raw: String = "") throws {
            session.cancel(); try session.switchConfiguration(to: double)
            output = ""; marked = ""; insertions = []; deletes = 0; type(raw)
        }
        func candidate(_ text: String, maxLoads: Int = 25) -> SKCandidate? {
            for _ in 0...maxLoads {
                if let c = session.state.candidates.first(where: { $0.text == text }) { return c }
                if session.state.isLastPage { break }
                let before = session.state.candidates.count; session.loadMoreCandidates()
                if session.state.candidates.count == before { break }
            }
            return nil
        }
        func choose(_ text: String) -> Bool {
            guard let c = candidate(text) else { return false }; session.select(c); return true
        }
        func isClear() -> Bool {
            session.state.input.isEmpty && session.state.preedit.isEmpty && session.state.candidates.isEmpty && marked.isEmpty
        }
        func trace(_ name: String) {
            observations.append(["name": name, "output": output, "input": session.state.input,
                "preedit": session.state.preedit, "marked": marked,
                "candidates": session.state.candidates.prefix(12).map { ["text": $0.text, "index": $0.index, "comment": $0.comment] as [String: Any] }])
        }
        let metadata = user.appendingPathComponent("ziranma-double-pinyin-spelling.json")
        if args[4] == "index" {
            let migrationDirectory = user.appendingPathComponent("migration-fixtures")
            try FileManager.default.createDirectory(at: migrationDirectory, withIntermediateDirectories: true)
            let legacyFile = migrationDirectory.appendingPathComponent("double-pinyin-spelling.json")
            let legacy: [[String: String]] = [["code": "nihc", "text": "你好"], ["code": "lujmmn", "text": "鹿键喵"],
                ["code": "aaooeeaieiaoouanenaheger", "text": String(repeating: "字", count: 12)]]
            let legacyData = try JSONEncoder().encode(legacy)
            try legacyData.write(to: legacyFile)
            let migrated = SKLearnedSpellingIndex(userDirectory: migrationDirectory)
            check("old learned spelling converts to Ziranma", migrated.suggestions(for: "nijk").contains(where: { $0.code == "nihk" && $0.text == "你好" }))
            check("old custom phrase converts to Ziranma", migrated.suggestions(for: "lujmc").contains(where: { $0.code == "lujmmc" && $0.text == "鹿键喵" }))
            check("migration preserves the legacy file", try Data(contentsOf: legacyFile) == legacyData)
            let migratedFile = migrationDirectory.appendingPathComponent("ziranma-double-pinyin-spelling.json")
            let migratedData = try Data(contentsOf: migratedFile)
            let migratedRecords = try JSONDecoder().decode([[String: String]].self, from: migratedData)
            check("migration preserves all zero initial spellings", migratedRecords.last == legacy.last)
            try Data("[]".utf8).write(to: legacyFile)
            _ = SKLearnedSpellingIndex(userDirectory: migrationDirectory)
            check("existing natural code index is not reimported", try Data(contentsOf: migratedFile) == migratedData)
            let directory = user.appendingPathComponent("index-fixtures")
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let file = directory.appendingPathComponent("ziranma-double-pinyin-spelling.json")
            func records() throws -> [[String: String]] {
                try JSONDecoder().decode([[String: String]].self, from: Data(contentsOf: file))
            }
            func code(_ number: Int) -> String {
                var n = number
                var bytes = [UInt8](repeating: 97, count: 4)
                for i in (0..<4).reversed() { bytes[i] += UInt8(n % 26); n /= 26 }
                return String(bytes: bytes, encoding: .utf8)!
            }
            try Data("{broken json".utf8).write(to: file)
            var index = SKLearnedSpellingIndex(userDirectory: directory)
            check("corrupt metadata loads as empty without a crash", index.suggestions(for: "nijk").isEmpty)
            index.record(code: "nihk", text: "你好")
            check("natural valid record repairs corrupt metadata", try records() == [["code": "nihk", "text": "你好"]])
            let clean = try Data(contentsOf: file)
            for (raw, text) in [("nihao", "你好"), ("NIHK", "你好"), ("ni'hk", "你好"), ("nihk", "ni"), ("nihk", "🦌鹿")] {
                index.record(code: raw, text: text)
            }
            check("invalid raw or non-Chinese records do not mutate metadata", try Data(contentsOf: file) == clean)
            index.record(code: "nihk", text: "你好")
            check("repeated same user word does not create duplicates", try records().count == 1)
            for raw in ["nijk", "nhk", "niihk", "nhik"] {
                check("bounded metadata supports one edit: \(raw)", index.suggestions(for: raw).contains(where: { $0.code == "nihk" && $0.text == "你好" }))
            }
            check("exact input is not mislabeled as a correction", index.suggestions(for: "nihk").isEmpty)
            check("two unrelated edits do not match a single-edit index", index.suggestions(for: "xxhk").isEmpty)
            var oversized = clean
            oversized.append(Data(repeating: 32, count: 131073 - oversized.count))
            try oversized.write(to: file)
            index = SKLearnedSpellingIndex(userDirectory: directory)
            check("oversize metadata is rejected before loading", index.suggestions(for: "nijk").isEmpty)
            try Data("[]".utf8).write(to: file)
            index = SKLearnedSpellingIndex(userDirectory: directory)
            for i in 0..<600 {
                index.record(code: String(repeating: "a", count: 44) + code(i),
                             text: String(repeating: "词", count: 23) + String(UnicodeScalar(0x4e00 + i)!))
            }
            let bounded = try records(), boundedData = try Data(contentsOf: file)
            check("600 maximum-length records retain only newest 512", bounded.count == 512 && bounded.first?["code"] == String(repeating: "a", count: 44) + code(88))
            check("maximum-length metadata stays within 128 KiB", boundedData.count <= 131072, "bytes=\(boundedData.count)")
            index = SKLearnedSpellingIndex(userDirectory: directory)
            let lastCode = String(repeating: "a", count: 44) + code(599)
            let near = "b" + lastCode.dropFirst()
            check("restarted bounded index restores its newest user entry", index.suggestions(for: near).contains(where: { $0.code == lastCode }))
            check("candidate count is bounded independently of index size", index.suggestions(for: String(lastCode.dropLast())).count <= 4)
        } else if args[4] == "learn" {
            let originalMetadata = try? Data(contentsOf: metadata)
            try reset("lujmmc"); session.loadMoreCandidates(); session.cancel()
            try reset("nihk"); session.type("\n")
            check("typing browsing cancel and raw Return do not create metadata", (try? Data(contentsOf: metadata)) == originalMetadata)
            try reset("nihkuijx"); let partialOnly = choose("你好")
            check("uncommitted partial selection does not record a whole user word", partialOnly && output.isEmpty && (try? Data(contentsOf: metadata)) == originalMetadata)
            session.cancel()
            // Not a production dictionary addition: create this phrase only
            // through the exact same displayed-candidate selections as a user.
            for i in 0..<5 {
                try reset("lujmmc")
                let fullChoice = session.state.candidates.first(where: { $0.text == "鹿键喵" })
                var selected = true
                if let fullChoice { session.select(fullChoice) }
                else { for character in ["鹿", "键", "喵"] { selected = choose(character) && selected } }
                check("user phrase natural selection \(i + 1) commits exactly once", selected && output == "鹿键喵" && isClear(), "output=\(output), remaining=\(session.state.input)")
                session.commitPending(); check("learning selection \(i + 1) is drained", output == "鹿键喵")
            }
            try reset("lujmmc")
            check("five explicit selections promote exact user phrase", session.state.candidates.first?.text == "鹿键喵")
            trace("same-process learned ranking"); session.cancel()
        } else if args[4] == "probe" {
            try reset("lujmmc")
            check("new process restores learned user phrase at first rank", session.state.candidates.first?.text == "鹿键喵")
            check("loading and typing learned phrase do not commit", output.isEmpty)
            trace("new-process learned ranking")
            session.loadMoreCandidates(); session.cancel(); type("lujmmc")
            check("browsing and cancel preserve learned first ranking", session.state.candidates.first?.text == "鹿键喵" && output.isEmpty)
            session.type("\n")
            check("Return on learned phrase still confirms raw letters", output == "lujmmc" && isClear())
            let persisted = try? Data(contentsOf: metadata)
            try reset("nihk"); session.loadMoreCandidates(); session.cancel()
            try reset("nihk"); session.type("\n")
            check("noncommitting actions leave persisted metadata unchanged", (try? Data(contentsOf: metadata)) == persisted)
            // Three substitutions plus omission, insertion and transposition.
            // Freeze and rank all before selecting any typo.
            let userTypos = ["kujmmc", "lukmmc", "lujmmv", "lujmc", "lujjmmc", "lumjmc"]
            for raw in userTypos {
                try reset(raw)
                trace("learned user phrase single-key typo: \(raw)")
                check("learned user phrase is offered for single-key typo: \(raw)",
                      session.state.candidates.contains(where: { $0.text == "鹿键喵" }))
            }
            for raw in userTypos {
                try reset(raw)
                let chosen = choose("鹿键喵")
                check("learned typo selection consumes whole input: \(raw)",
                      chosen && output == "鹿键喵" && isClear(), "output=\(output), remaining=\(session.state.input)")
            }
            if let data = try? Data(contentsOf: metadata),
               let records = try? JSONDecoder().decode([[String: String]].self, from: data) {
                check("corrected selections retain the correct spelling metadata", records.contains(where: { $0["code"] == "lujmmc" && $0["text"] == "鹿键喵" }))
                check("typo codes never replace the learned correct spelling", !records.contains(where: { userTypos.contains($0["code"] ?? "") && $0["text"] == "鹿键喵" }))
            } else { check("learned spelling metadata is readable", false) }
            session.cancel()
        } else {
            for raw in ["nihk", "nijk", "nhk", "niihk", "nhik", "nihkuijx", String(repeating: "q", count: 129)] {
                try reset(raw)
                check("input retained before Return: \(raw.prefix(16))", session.state.input == raw && output.isEmpty)
                session.type("\n")
                check("Return preserves original letters: \(raw.prefix(16))", output == raw && isClear() && insertions == [raw], "output=\(output)")
                session.type("\n")
                check("idle Return reaches host once: \(raw.prefix(16))", output == raw + "\n" && insertions == [raw, "\n"])
            }
            try reset("niihk"); session.commitRaw(); session.commitRaw()
            check("explicit raw commit preserves typo once", output == "niihk" && isClear() && insertions == ["niihk"])
            try reset("nihk"); session.type(" ")
            check("space selects displayed clean first candidate", output == "你好" && isClear())
            session.type(" "); check("idle space inserts one literal space", output == "你好 ")
            for literal in ["，", "。", "1", "A", "🦌", "-"] {
                try reset("nihk"); session.type(literal)
                check("literal flush commits clean composition once: \(literal)", output == "你好" + literal && isClear())
                session.commitPending(); check("literal flush has no stale replay: \(literal)", output == "你好" + literal)
            }
            for raw in ["nihk", "niihk", "nhk", "nihkuijx"] {
                try reset(); output = "宿主"; type(raw)
                var rawDeleted = true
                for remaining in stride(from: raw.count - 1, through: 0, by: -1) {
                    session.deleteBackward()
                    rawDeleted = rawDeleted && session.state.input == String(raw.prefix(remaining)) && output == "宿主" && deletes == 0
                }
                check("backspace edits every real input letter only: \(raw)", rawDeleted && isClear())
                session.deleteBackward(); check("idle backspace reaches host once: \(raw)", output == "宿" && deletes == 1)
            }
            try reset("niihk"); session.deleteBackward(); type("k")
            check("delete then retype restores the exact typo", session.state.input == "niihk" && output.isEmpty)
            session.cancel(); check("cancel discards composition without committing", output.isEmpty && isClear())
            type("nihk"); session.type(" "); check("cancelled input cannot contaminate next word", output == "你好")

            for terminator in [" ", "\n", "，", "switch"] {
                try reset("nihkuijx")
                let found = choose("你好")
                check("partial selection preserves marked prefix: \(terminator.debugDescription)", found && output.isEmpty && marked.hasPrefix("你好") && !session.state.input.isEmpty)
                if terminator == "switch" { try session.switchConfiguration(to: full) }
                else { session.type(terminator) }
                let expected = terminator == "\n" ? "你好uijx" : "你好世界" + (terminator == "，" ? "，" : "")
                check("partial selection completes without losing tail: \(terminator.debugDescription)", output == expected && isClear(), "output=\(output)")
            }
            try reset("nihkuijx"); let selectedPrefix = choose("你好")
            session.deleteBackward()
            check("first partial-selection delete restores all raw spelling",
                  selectedPrefix && session.state.input == "nihkuijx" && output.isEmpty && deletes == 0 && !marked.hasPrefix("你好"))
            session.type("\n")
            check("Return after undoing partial choice preserves every original key",
                  output == "nihkuijx" && isClear(), "output=\(output)")
            try reset("nihkuijx"); _ = choose("你好")
            var deleteSteps = 0
            while !session.state.input.isEmpty && deleteSteps < 30 { session.deleteBackward(); deleteSteps += 1 }
            check("deleting partial selection eventually clears without host edits", isClear() && output.isEmpty && deletes == 0)
            type("nihk"); session.type(" "); check("input after deleting a partial selection is independent", output == "你好")

            try reset("ni")
            let firstInput = session.state.input, firstMarked = marked, initial = session.state.candidates
            session.loadMoreCandidates()
            check("expanded candidates preserve composition and emit nothing", session.state.input == firstInput && marked == firstMarked && output.isEmpty)
            check("expanded candidate IDs are unique", Set(session.state.candidates.map(\.index)).count == session.state.candidates.count)
            if let later = session.state.candidates.first(where: { !initial.contains($0) }) {
                session.select(later)
                check("expanded nonfirst selection follows its displayed ID", output == later.text && isClear(), "selected=\(later.text), output=\(output)")
            } else { check("expanded nonfirst candidate exists", false) }
            try reset("ni"); session.changePage(backward: false)
            if let later = session.state.candidates.dropFirst().first {
                session.select(later); check("paged nonfirst selection follows its displayed ID", output == later.text && isClear())
            } else { check("second page has a nonfirst candidate", false) }
            try reset("niihk"); let before = session.state.candidates
            session.changePage(backward: false); session.changePage(backward: true)
            check("paging round trip preserves typo and selection choices", output.isEmpty && session.state.input == "niihk" && session.state.candidates == before)
            if let corrected = session.state.candidates.first(where: { $0.text == "你好" }) {
                session.loadMoreCandidates(); session.select(corrected)
                check("correction remains selectable after expansion", output == "你好" && isClear())
            } else { check("known insertion correction is available", false) }
            try reset("nihk"); let stale = session.state.candidates.first
            session.cancel()
            if let stale { session.select(stale) }
            check("stale candidate from cancelled input cannot commit", output.isEmpty && isClear())

            try reset("nihk"); try session.switchConfiguration(to: full)
            check("switch to full pinyin commits pending double pinyin once", output == "你好" && isClear())
            type("shijie"); session.type(" ")
            check("full pinyin decodes using its own spelling", output == "你好世界")
            try session.switchConfiguration(to: double); type("nihk"); session.type(" ")
            check("switch back restores double-pinyin spelling", output == "你好世界你好")
            try reset(String(repeating: "nihkuijx", count: 18)); session.commitRaw()
            check("long raw commit has no truncation or implicit partial commit", output == String(repeating: "nihkuijx", count: 18) && isClear())
            try reset("nihk"); trace("final clean composition"); session.cancel()
        }
        let failed = checks.filter { !($0["passed"] as! Bool) }.count
        let report: [String: Any] = ["mode": args[4], "environment": "macOS native real Rime and production input session; no UIKit or physical device", "checks": checks, "checkCount": checks.count, "failures": failed, "observations": observations]
        let reportURL = URL(fileURLWithPath: args[3])
        try FileManager.default.createDirectory(at: reportURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]).write(to: reportURL)
        print("\(failed == 0 ? "PASS" : "FAIL") \(checks.count - failed)/\(checks.count) independent \(args[4]) checks")
        if failed > 0 { exit(1) }
    }
}
