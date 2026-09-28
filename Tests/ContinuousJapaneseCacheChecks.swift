// Independent checks against real Japanese data: no learned rank may be cached.
import Foundation

@main struct ContinuousJapaneseCacheChecks {
    @MainActor static func main() throws {
        let a = CommandLine.arguments, resources = URL(fileURLWithPath: CommandLine.arguments[1])
        let user = URL(fileURLWithPath: a[2])
        if a.count > 4 && a[4] == "reload" {
            let old = try JSONSerialization.jsonObject(with: Data(contentsOf: URL(fileURLWithPath: a[5]))) as! [String: Any]
            let expected = old["selectedAlternate"] as! String
            let engine = try SKJapaneseEngine(resources: resources, userDirectory: user)
            let state = engine.replaceInput("hashi")
            let passed = state.candidates.first?.text == expected && state.candidates.count > 2 && state.candidates[2].text == "はし"
            try JSONSerialization.data(withJSONObject: ["passed": passed, "expected": expected, "top": state.candidates.first?.text ?? "", "scope": "Separate executable process reads prior learning after fresh conversion"], options: [.prettyPrinted,.sortedKeys]).write(to: URL(fileURLWithPath: a[3]))
            print("cross-process learning: \(passed)")
            if !passed { exit(1) }
            return
        }
        var checks: [[String: Any]] = []
        func check(_ label: String, _ passed: Bool) { checks.append(["label": label, "passed": passed]) }
        let lexicon = try SKJapaneseLexicon(resources: resources)
        func cache(_ instance: SKJapaneseLexicon) -> [Data: [String]] {
            Mirror(reflecting: instance).children.first { $0.label == "conversionCache" }?.value as? [Data: [String]] ?? [:]
        }
        let cold = lexicon.convert("はし")
        check("real dictionary offers multiple readings", cold.count > 3 && cold.contains("はし"))
        check("warm immutable conversion equals cold output", lexicon.convert("はし") == cold)
        var edited = lexicon.convert("はし"); edited.removeAll()
        check("caller mutation cannot modify cached array", edited.isEmpty && lexicon.convert("はし") == cold)
        for reading in ["あ", "い", "う", "え", "お", "か", "き", "く", "け", "こ", "さ", "し", "す", "せ", "そ", "た", "ち"] { _ = lexicon.convert(reading) }
        check("conversion cache bounded to 16 readings", cache(lexicon).count == 16)
        check("oldest conversion evicted", cache(lexicon)[Data("はし".utf8)] == nil)
        check("evicted conversion recomputed identically", lexicon.convert("はし") == cold)
        let count = cache(lexicon).count
        check("empty input returns no conversion", lexicon.convert("").isEmpty)
        let overlong = String(repeating: "あ", count: 81)
        check("overlong reading remains literal", lexicon.convert(overlong) == [overlong])
        check("empty and overlong input not cached", cache(lexicon).count == count && cache(lexicon)[Data()] == nil && cache(lexicon)[Data(overlong.utf8)] == nil)
        check("unknown Unicode preserves literal fallback", lexicon.convert("🦌") == ["🦌"])
        let boundary = String(repeating: "🦌", count: 80)
        check("80-character boundary converts and is cacheable", lexicon.convert(boundary) == [boundary] && cache(lexicon)[Data(boundary.utf8)] != nil)
        let resident = cache(lexicon)
        let payload = resident.reduce(0) { $0 + $1.key.count + $1.value.reduce(0) { $0 + $1.utf8.count } }
        check("cached result count bounded by N-best plus literals", resident.values.allSatisfy { $0.count <= 22 })
        let mirrorLabels = Mirror(reflecting: lexicon).children.compactMap(\.label)
        check("lexicon owns no learned-history fields", !mirrorLabels.contains { $0.localizedCaseInsensitiveContains("learn") || $0.localizedCaseInsensitiveContains("history") || $0.localizedCaseInsensitiveContains("user") })
        let engine = try SKJapaneseEngine(resources: resources, userDirectory: user)
        let initial = engine.replaceInput("hashi")
        let all = engine.candidatePage(startingAt: 0, limit: 64).candidates
        let originalTop = initial.candidates.first?.text
        guard let alternate = all.first(where: { $0.text != originalTop && $0.text != "はし" && $0.text != "ハシ" }) else { fatalError("Real はし dictionary needs a selectable alternate") }
        check("raw letters remain preedit", initial.preedit == "hashi")
        check("literal kana remains third", initial.candidates.count > 2 && initial.candidates[2].text == "はし")
        let committed = engine.selectCandidate(at: alternate.index)
        check("alternate commits exactly and clears", committed.committedText == alternate.text && committed.input.isEmpty && committed.candidates.isEmpty)
        let warm = engine.replaceInput("hashi")
        check("learned selection reranks on cache hit", warm.candidates.first?.text == alternate.text)
        check("kana stays third after learned reranking", warm.candidates[2].text == "はし")
        check("promoted index routes correctly", engine.selectCandidate(at: 0).committedText == alternate.text)
        let learningURL = user.appendingPathComponent("japanese-learning.json")
        let saved = try Data(contentsOf: learningURL)
        _ = engine.replaceInput("hashi"); _ = engine.clear()
        check("clear preserves saved learning", try Data(contentsOf: learningURL) == saved)
        _ = engine.replaceInput("hashi")
        let raw = engine.process(key: 0xff0d)
        check("Return preserves raw-letter feature", raw.committedText == "hashi" && raw.input.isEmpty && raw.candidates.isEmpty)
        check("Return does not train a cached candidate", try Data(contentsOf: learningURL) == saved)
        _ = engine.replaceInput("hashi")
        let pending = engine.process(key: 104)
        check("pending consonant offers fresh completions instead of stale cached candidates",
              pending.input == "hashih" && !pending.candidates.isEmpty && !pending.candidates.contains { $0.text == alternate.text })
        let deleted = engine.process(key: 0xff08)
        check("deleting pending consonant restores fresh learned rank", deleted.input == "hashi" && deleted.candidates.first?.text == alternate.text)
        _ = engine.clear()
        check("stale post-clear index cannot commit cached words", engine.selectCandidate(at: 0).committedText.isEmpty)
        let restarted = try SKJapaneseEngine(resources: resources, userDirectory: user)
        check("new engine reloads learned rank", restarted.replaceInput("hashi").candidates.first?.text == alternate.text)
        let otherUser = user.appendingPathComponent("independent-user")
        let independent = try SKJapaneseEngine(resources: resources, userDirectory: otherUser)
        check("different user does not share learned promotion", independent.replaceInput("hashi").candidates.first?.text == originalTop)
        check("standalone lexicon still has original order after learning", lexicon.convert("はし") == cold)
        let failed = checks.filter { $0["passed"] as? Bool != true }
        try JSONSerialization.data(withJSONObject: ["checks": checks, "passed": checks.count - failed.count, "failed": failed.count, "cachedReadings": resident.count, "observedUTF8KeyAndValuePayloadBytes": payload, "payloadIsRSS": false, "maximumCachedOutputCount": resident.values.map(\.count).max() ?? 0, "maximumCachedInputCharacters": resident.keys.map { String(decoding: $0, as: UTF8.self).count }.max() ?? 0, "originalTop": originalTop ?? "", "selectedAlternate": alternate.text, "scope": "Independent real-resource conversion-cache and live learning regression checks"], options: [.prettyPrinted,.sortedKeys]).write(to: URL(fileURLWithPath: a[3]))
        print("\(checks.count - failed.count)/\(checks.count) passed")
        if !failed.isEmpty { exit(1) }
    }
}
