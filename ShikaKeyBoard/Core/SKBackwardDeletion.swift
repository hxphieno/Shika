import Foundation

/// Units for accelerated deletion of committed text only. UIKit remains the
/// authority for each actual backward deletion (including composed characters).
enum SKBackwardDeletion {
    static func characterCount(in context: String) -> Int {
        guard let last = context.last, !last.isNewline else { return 1 }
        let start = context.lastIndex(where: { $0.isNewline }).map { context.index(after: $0) } ?? context.startIndex
        let line = String(context[start...])
        let trimmed = line.replacingOccurrences(of: "[\\t ]+$", with: "", options: .regularExpression)
        let spaces = line.count - trimmed.count
        guard !trimmed.isEmpty else { return min(32, max(1, spaces)) }
        var wordRange: Range<String.Index>?
        trimmed.enumerateSubstrings(in: trimmed.startIndex..<trimmed.endIndex, options: [.byWords, .reverse, .substringNotRequired]) { _, range, _, stop in
            if range.upperBound == trimmed.endIndex { wordRange = range }
            stop = true
        }
        let length = wordRange.map { trimmed[$0].count } ?? 1
        // Don't turn an identifier/URL with a huge token into an unbounded burst.
        let count = length + spaces
        return count <= 32 ? count : 1
    }
}
