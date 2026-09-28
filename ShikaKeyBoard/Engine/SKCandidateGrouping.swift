import Foundation

/// A composition-wide quota, applied before paging. The first six ranked
/// recommendations stay in place; shorter dictionary choices follow them.
enum SKCandidateGrouping {
    static let limit = 6

    static func arrange<T, ID: Hashable>(recommendations: [T], words: [T],
                                        text: (T) -> String, identity: (T) -> ID) -> [T] {
        var seen = Set<ID>(), counts: [Int: Int] = [:], result: [T] = []
        let longWords = Set(words.filter { text($0).count >= 4 }.map(identity))
        func append(_ item: T, recommendation: Bool = false) {
            let group = min(4, text(item).count)
            // Known long dictionary words get their own six slots after the
            // sentence recommendations (e.g. ありがとう before a mixed tail).
            let generatedSentence = recommendation && group == 4 && !longWords.contains(identity(item))
            guard group > 0, !seen.contains(identity(item)),
                  generatedSentence || group == 1 || counts[group, default: 0] < limit else { return }
            seen.insert(identity(item))
            if !generatedSentence { counts[group, default: 0] += 1 }
            result.append(item)
        }
        for item in recommendations.prefix(limit) { append(item, recommendation: true) }
        // Four-or-more-character words share one bounded tier, rather than
        // adding six candidates for every possible word length.
        for group in stride(from: 4, through: 1, by: -1) {
            for item in words where min(4, text(item).count) == group { append(item) }
        }
        return result
    }

    /// Abbreviations can bury the first single character hundreds of entries
    /// deep. Enumerate without selecting or changing Rime's composition.
    @MainActor static func nativeWindow(_ session: SKRimeSession) -> (items: [SKCandidate], next: Int, more: Bool) {
        var items: [SKCandidate] = [], next = 0, more = true, singles = 0
        while more && next < 4096 && singles < 128 {
            let data = session.candidatePage(from: UInt(next), limit: 256)
            let batch = decode(data)
            items += batch
            singles += batch.filter { $0.text.count == 1 }.count
            let cursor = data["nextIndex"] as? Int ?? next
            more = data["hasMore"] as? Bool ?? false
            guard cursor > next else { more = false; break }
            next = cursor
        }
        return (items, next, more)
    }

    static func decode(_ data: [AnyHashable: Any]) -> [SKCandidate] {
        (data["candidates"] as? [[String: Any]] ?? []).compactMap {
            guard let index = $0["index"] as? Int, let text = $0["text"] as? String else { return nil }
            return SKCandidate(index: index, text: text, comment: $0["comment"] as? String ?? "")
        }
    }
}
