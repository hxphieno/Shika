import Foundation
import CoreText

/// Device-local display capability, not a dictionary/Unicode-range policy.
/// Inspect shaped runs after font fallback, so supplementary Han, combining
/// marks and emoji sequences receive the same treatment as ordinary text.
@MainActor
final class SKCandidateGlyphCoverage {
    private let font = CTFontCreateUIFontForLanguage(.system, 20, nil)!
    private var cache: [Data: Bool] = [:]
    private var order: [Data] = []

    func canDisplay(_ text: String) -> Bool {
        let key = Data(text.utf8)
        if let cached = cache[key] { return cached }
        let attributed = NSAttributedString(string: text,
            attributes: [NSAttributedString.Key(kCTFontAttributeName as String): font])
        let line = CTLineCreateWithAttributedString(attributed)
        let runs = CTLineGetGlyphRuns(line) as! [CTRun]
        let displayable = !runs.contains { run in
            let attributes = CTRunGetAttributes(run) as NSDictionary
            guard let runFont = attributes[kCTFontAttributeName] else { return false }
            let name = CTFontCopyPostScriptName(runFont as! CTFont) as String
            // A zero glyph alone can represent an invisible variation selector
            // or joiner. Only a confirmed missing-font fallback rejects text.
            guard name.lowercased().contains("lastresort") else { return false }
            // Standalone variation selectors can use LastResort's invisible
            // glyph (zero ink). They are not a displayed missing-glyph box.
            return !CTRunGetImageBounds(run, nil, CFRange(location: 0, length: 0)).isEmpty
        }
        // Byte keys preserve distinct normalization/variation sequences. Bound
        // both the entry count and the size of strings retained by this cache.
        if key.count <= 512 {
            if order.count == 512 { cache.removeValue(forKey: order.removeFirst()) }
            order.append(key)
            cache[key] = displayable
        }
        return displayable
    }
}
