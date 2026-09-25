// Independent Japanese decoder benchmark and behavior checks; no corpus training.
import Foundation
import Darwin

private struct JapaneseCorpus: Decodable { let cases: [JapaneseItem] }
private struct JapaneseItem: Decodable { let id: String; let target: String; let romaji: String }

@main
struct LexiconQualityJapaneseChecks {
    @MainActor static func main() throws {
        let args = CommandLine.arguments
        guard args.count == 6 else { fatalError("runner resources userdir cases ranking|functional|learning-write|learning-read output") }
        let resources = URL(fileURLWithPath: args[1]), user = URL(fileURLWithPath: args[2])
        let mode = args[4]
        let engine = try SKJapaneseEngine(resources: resources, userDirectory: user)
        var checks: [[String: Any]] = []
        func check(_ label: String, _ passed: Bool, _ detail: String = "") {
            checks.append(["label": label, "passed": passed, "detail": detail])
        }
        @MainActor func type(_ text: String, into target: any SKInputEngine) -> SKEngineState {
            _ = target.clear(); var state = SKEngineState()
            for c in text.utf8 { state = target.process(key: Int32(c)) }
            return state
        }
        var rows: [[String: Any]] = []
        if mode == "ranking" {
            let corpus = try JSONDecoder().decode(JapaneseCorpus.self, from: Data(contentsOf: URL(fileURLWithPath: args[3])))
            for item in corpus.cases {
                _ = engine.clear(); var durations: [Double] = []; var state = SKEngineState(); var commits = ""
                for key in item.romaji.utf8 {
                    let start = DispatchTime.now().uptimeNanoseconds
                    state = engine.process(key: Int32(key))
                    durations.append(Double(DispatchTime.now().uptimeNanoseconds - start) / 1e6)
                    commits += state.committedText
                }
                let candidates = engine.candidatePage(startingAt: 0, limit: 10).candidates
                var usage = rusage(); getrusage(RUSAGE_SELF, &usage)
                rows.append(["id": item.id, "input": item.romaji, "target": item.target,
                    "preedit": state.preedit, "rank": candidates.firstIndex(where: { $0.text == item.target }).map { $0 + 1 } ?? 0,
                    "candidates": candidates.map(\.text), "initialCandidateCount": state.candidates.count,
                    "keyDurationsMS": durations, "peakRSSBytes": usage.ru_maxrss, "unexpectedCommit": commits])
            }
        } else if mode == "commit" {
            let corpus = try JSONDecoder().decode(JapaneseCorpus.self, from: Data(contentsOf: URL(fileURLWithPath: args[3])))
            for item in corpus.cases {
                _ = type(item.romaji, into: engine)
                let candidates = engine.candidatePage(startingAt: 0, limit: 64).candidates
                if let target = candidates.first(where: { $0.text == item.target }) {
                    let selected = engine.selectCandidate(at: target.index)
                    check("\(item.id) target commits exactly and clears", selected.committedText == item.target && selected.input.isEmpty && selected.candidates.isEmpty, selected.committedText)
                } else { check("\(item.id) target selectable", false, item.target) }
            }
        } else if mode == "learning-write" {
            let state = type("nihon", into: engine)
            guard state.candidates.count > 1 else { throw NSError(domain: "JapaneseAcceptance", code: 1) }
            let candidate = state.candidates[1]
            let result = engine.selectCandidate(at: candidate.index)
            check("selected alternative commits exactly", result.committedText == candidate.text)
            try Data(candidate.text.utf8).write(to: user.appendingPathComponent("expected-promotion.txt"))
        } else if mode == "learning-read" {
            let expected = try String(contentsOf: user.appendingPathComponent("expected-promotion.txt"), encoding: .utf8)
            let state = type("nihon", into: engine)
            check("selection frequency survives fresh process", state.candidates.first?.text == expected, "expected \(expected), actual \(state.candidates.first?.text ?? "empty")")
        } else {
            let lexicon = try SKJapaneseLexicon(resources: resources)
            for (input, expected) in [("shi", "し"), ("chi", "ち"), ("tsu", "つ"), ("kya", "きゃ"), ("sha", "しゃ"), ("ryo", "りょ"), ("gakkou", "がっこう"), ("konnichiha", "こんにちは"), ("kanpai", "かんぱい"), ("kin'youbi", "きんようび"), ("shin'you", "しんよう"), ("nn", "ん"), ("nan", "なん"), ("nani", "なに"), ("nihon", "にほん"), ("ko-hi-", "こーひー")] {
                let reading = lexicon.reading(input)
                check("romaji \(input)", reading.kana == expected && reading.pending.isEmpty, "\(reading.kana) + \(reading.pending)")
            }
            let incomplete = lexicon.reading("ky")
            check("incomplete consonants remain pending", incomplete.kana.isEmpty && incomplete.pending == "ky")
            let first = type("nihon", into: engine)
            check("Japanese candidates available", !first.candidates.isEmpty)
            let removed = engine.process(key: 0xff08)
            check("backspace edits raw composition", removed.input == "niho" && removed.preedit == "にほ", "\(removed.input) / \(removed.preedit)")
            let erased = engine.clear()
            check("clear removes composition and candidates", erased.input.isEmpty && erased.preedit.isEmpty && erased.candidates.isEmpty)
            let emptyDelete = engine.process(key: 0xff08)
            check("backspace on empty remains empty", emptyDelete.input.isEmpty && emptyDelete.committedText.isEmpty)
            let before = type("toukyou", into: engine)
            let space = engine.process(key: 0x20)
            check("space commits displayed top exactly once", space.committedText == before.candidates.first?.text && space.input.isEmpty && space.candidates.isEmpty)
            check("second commit is empty", engine.commit().committedText.isEmpty)
            let beforeInvalid = type("nihon", into: engine)
            let invalid = engine.selectCandidate(at: Int.max)
            check("invalid selection preserves composition", invalid.input == beforeInvalid.input && invalid.candidates == beforeInvalid.candidates)
            let page1 = engine.candidatePage(startingAt: 0, limit: 3), page2 = engine.candidatePage(startingAt: 3, limit: 3)
            check("Japanese pagination advances indices", page1.nextIndex == 3 && page2.candidates.first?.index == 3)
            let pending = type("ky", into: engine)
            check("pending letters have marked text", pending.preedit == "ky" && pending.candidates.isEmpty)
            check("pending commit does not lose letters", engine.commit().committedText == "ky")
            let mixed = try SKConversionEngine(configuration: SKChineseJapaneseScheme.configuration(for: .mixed), resourceURL: resources, userURL: user.appendingPathComponent("mixed"))
            for (input, expected) in [("nihon", "日本"), ("toukyou", "東京"), ("gakkou", "学校")] {
                let state = type(input, into: mixed)
                let jp = state.candidates.filter { $0.comment.hasPrefix("日文") }
                check("mixed \(input) exposes Japanese", !jp.isEmpty)
                if let candidate = jp.first(where: { $0.text == expected }) ?? jp.first {
                    let committed = mixed.selectCandidate(at: candidate.index)
                    check("mixed \(input) routes selected Japanese exactly", committed.committedText == candidate.text && committed.input.isEmpty && committed.candidates.isEmpty, "candidate \(candidate.text), output \(committed.committedText)")
                }
            }
            var mixedOutput = ""
            let session = SKInputSession(engine: mixed, configuration: SKChineseJapaneseScheme.configuration(for: .mixed), insertText: { mixedOutput += $0 }, deleteText: {})
            session.cancel()
            for c in "nihon" { session.type(String(c)) }
            session.loadMoreCandidates()
            check("mixed expansion exposes beyond three Japanese choices", session.state.candidates.filter { $0.comment.hasPrefix("日文") }.count > 3)
            if let later = session.state.candidates.filter({ $0.comment.hasPrefix("日文") }).dropFirst(3).first {
                session.select(later)
                check("expanded Japanese candidate routes exactly", mixedOutput == later.text && session.state.input.isEmpty)
            }
            let changed = try mixed.selectConfiguration(SKChineseJapaneseScheme.configuration(for: .japanese))
            check("language switch clears old composition", changed.input.isEmpty && changed.candidates.isEmpty)
            let native = type("nihon", into: mixed)
            check("pure Japanese configured through common boundary", !native.candidates.isEmpty && native.preedit == "にほん")
        }
        var finalUsage = rusage(); getrusage(RUSAGE_SELF, &finalUsage)
        let report: [String: Any] = ["processPeakRSSBytes": finalUsage.ru_maxrss, "mode": mode, "results": rows, "checks": checks, "failed": checks.filter { !($0["passed"] as! Bool) }.count,
            "platform": "macOS real production engines; not iOS UI or memory validation", "rankingTraining": false]
        try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]).write(to: URL(fileURLWithPath: args[5]))
        print("Japanese \(mode): \(rows.count) rankings, \(checks.count) checks, \(checks.filter { !($0["passed"] as! Bool) }.count) failures")
    }
}
