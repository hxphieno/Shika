import Foundation

/// Joint word/language segmentation. All offsets address ASCII input bytes,
/// never output character counts. No UIKit or document access is needed here.
final class SKMixedDecoder {
    enum Language: String, Codable { case chinese, japanese }
    struct Segment: Codable {
        let raw: String
        let text: String
        let language: Language
        let left: Int
        let right: Int
        let cost: Double
        let corrected: Bool
    }
    struct Path {
        var segments: [Segment]
        var cost: Double
        let text: String
        let consumed: Int
        init(segments: [Segment], cost: Double) {
            self.segments = segments; self.cost = cost
            text = segments.map(\.text).joined()
            consumed = segments.reduce(0) { $0 + $1.raw.utf8.count }
        }
        var last: Segment? { segments.last }
        var languages: Set<Language> { Set(segments.map(\.language)) }
    }
    let japanese: SKJapaneseLexicon
    private let chinese: SKMixedChineseLexicon
    private let corrector: SKSpellingCorrector?
    private var cache: [String: [Segment]] = [:]
    private var correctionCache: [String: [Segment]] = [:]
    let beamWidth: Int

    init(resources: URL, beamWidth: Int = 16) throws {
        japanese = try SKJapaneseLexicon(resources: resources)
        chinese = try SKMixedChineseLexicon(resources: resources)
        corrector = SKSpellingCorrector(resources: resources,
            configuration: SKInputConfiguration(schemaID: "shika_pinyin", inputPolicy: .chineseRomanization, spelling: .fullPinyin))
        self.beamWidth = max(8, min(64, beamWidth))
    }

    func resetCache() {
        cache.removeAll(keepingCapacity: true); correctionCache.removeAll(keepingCapacity: true)
    }

    private func words(_ raw: String) -> [Segment] {
        if let cached = cache[raw] { return cached }
        // An apostrophe forces a Chinese syllable boundary. Word lookup never
        // erases an interior delimiter (xi'an must not become xian). A trailing
        // delimiter belongs to the preceding edge; Rime supplies whole phrases
        // across explicit boundaries without changing Japanese n' semantics.
        let code = raw.hasSuffix("'") ? String(raw.dropLast()) : raw
        var result = (code.contains("'") ? [] : chinese.words(for: code)).prefix(8).map {
            Segment(raw: raw, text: $0.text, language: .chinese, left: 0, right: 0,
                cost: max(1.0, 7.5 - 0.40 * log($0.frequency + 1)), corrected: false)
        }
        let reading = japanese.reading(raw)
        if reading.pending.isEmpty, !reading.kana.isEmpty {
            // Retain POS alternatives: short particles need their connection
            // costs, and cannot be ranked by zero dictionary cost in isolation.
            let matches = japanese.words(for: reading.kana).sorted { $0.cost < $1.cost }
            result += matches.prefix(16).map {
                Segment(raw: raw, text: $0.text, language: .japanese, left: $0.left, right: $0.right,
                    cost: 1.5 + Double($0.cost) / 2000, corrected: false)
            }
        }
        if cache.count >= 2048 { cache.removeAll(keepingCapacity: true) }
        cache[raw] = result
        return result
    }

    /// A conservative voiced/unvoiced + adjacent-transposition channel. Only
    /// full dictionary words qualify; arbitrary kana are never typo targets.
    private func corrections(_ raw: String) -> [Segment] {
        guard (6...24).contains(raw.count), raw.allSatisfy({ $0.isASCII && $0.isLetter }) else { return [] }
        if let cached = correctionCache[raw] { return cached }
        guard japanese.reading(raw).pending.isEmpty else { return [] }
        let pairs: [Character: Character] = ["d":"t", "t":"d", "g":"k", "k":"g", "z":"s", "s":"z", "b":"p", "p":"b"]
        let characters = Array(raw)
        var variants = Set<String>()
        for i in characters.indices {
            if let other = pairs[characters[i]] {
                var changed = characters; changed[i] = other; variants.insert(String(changed))
            }
            if i + 1 < characters.count, characters[i] != characters[i + 1] {
                var changed = characters; changed.swapAt(i, i + 1); variants.insert(String(changed))
            }
        }
        var results: [Segment] = []
        for variant in variants.sorted() {
            let reading = japanese.reading(variant)
            guard reading.pending.isEmpty else { continue }
            for word in japanese.words(for: reading.kana) where word.cost < 6000 {
                results.append(Segment(raw: raw, text: word.text, language: .japanese,
                    left: word.left, right: word.right, cost: 4.5 + Double(word.cost) / 2000, corrected: true))
            }
        }
        let result = Array(results.sorted { $0.cost == $1.cost ? $0.text < $1.text : $0.cost < $1.cost }.prefix(6))
        if correctionCache.count > 256 { correctionCache.removeAll(keepingCapacity: true) }
        correctionCache[raw] = result
        return result
    }

    private func transition(_ previous: Segment?, _ next: Segment) -> Double {
        if next.language == .japanese {
            return Double(japanese.connection(from: previous?.language == .japanese ? previous!.right : 0,
                                               to: next.left)) / 2000
                + (previous?.language == .chinese ? 0.8 : 0)
        }
        if previous?.language == .japanese {
            return 0.8 + Double(japanese.connection(from: previous!.right, to: 0)) / 2000
        }
        return 0
    }

    private func ordered(_ paths: [Path], limit: Int) -> [Path] {
        var seen = Set<String>()
        return Array(paths.sorted {
            $0.cost == $1.cost ? $0.text < $1.text : $0.cost < $1.cost
        }.filter { seen.insert("\($0.last?.language.rawValue ?? ""):\($0.last?.right ?? 0):\($0.text)").inserted }.prefix(limit))
    }

    /// Match native readings to raw letters, including per-syllable initials
    /// and a final unfinished syllable. Output length is never an input offset.
    private func consumedInput(_ input: String, syllables: [String]) -> Int? {
        let raw = Array(input)
        var offsets: Set<Int> = [0]
        for (index, syllable) in syllables.enumerated() {
            var next = Set<Int>()
            let spellings = Set([syllable, syllable.replacingOccurrences(of: "nue", with: "nve")
                .replacingOccurrences(of: "lue", with: "lve")])
            for offset in offsets where offset < raw.count {
                for spelling in spellings {
                    let letters = Array(spelling)
                    var lengths: Set<Int> = [1, letters.count]
                    if index == syllables.count - 1 { lengths.formUnion(1...letters.count) }
                    for length in lengths where offset + length <= raw.count {
                        guard raw[offset..<(offset + length)].elementsEqual(letters.prefix(length)) else { continue }
                        // Only a terminal syllable may be partly completed;
                        // other syllables must be full spellings or initials.
                        if length != 1 && length != letters.count && offset + length != raw.count { continue }
                        var end = offset + length
                        if end < raw.count && raw[end] == "'" { end += 1 }
                        next.insert(end)
                    }
                }
            }
            offsets = next
        }
        return offsets.max()
    }

    /// Native Chinese candidates provide sentence ranking and abbreviations.
    /// Word graph decoding itself performs zero per-substring Rime queries.
    func decode(_ input: String, context: Segment?, native: [SKCandidate], chineseQuery: (String) -> [SKCandidate],
                bonus: (Segment?, Segment) -> Double) -> [Path] {
        let raw = Array(input)
        guard !raw.isEmpty else { return [] }
        // Keep the full raw input in the session even when decoding is bounded.
        let length = min(96, raw.count)
        var lattice = Array(repeating: [Path](), count: length + 1)
        var chineseCosts = Array(repeating: Double.infinity, count: length + 1)
        lattice[0] = [Path(segments: [], cost: 0)]; chineseCosts[0] = 0
        var prefixes: [Path] = []
        var predictions: [Path] = []
        var wholeWords = Set<String>()
        for start in 0..<length {
            let incoming = ordered(lattice[start], limit: beamWidth)
            guard !incoming.isEmpty else { continue }
            for end in (start + 1)...min(length, start + 40) {
                let code = String(raw[start..<end])
                var choices = words(code)
                // Corrections are considered at the active tail. Cached exact
                // words retain priority; this cannot multiply at every boundary.
                if end == length, !choices.contains(where: { $0.language == .japanese }) {
                    choices += corrections(code)
                    // Literal kana completions belong to Japanese-only input.
                    // They must not turn an undecoded Chinese tail into a whole
                    // speculative kana sentence in the joint word graph.
                    let completions = japanese.completionWords(for: code).filter { !$0.isLiteral }.prefix(16).map {
                        Segment(raw: code, text: $0.word.text, language: .japanese,
                            left: $0.word.left, right: $0.word.right,
                            cost: 4.5 + Double($0.word.cost) / 2000, corrected: false)
                    }
                    for word in completions {
                        for path in incoming {
                            let previous = path.last ?? context
                            let score = path.cost + word.cost + transition(previous, word) - bonus(previous, word)
                                + Double(japanese.connection(from: word.right, to: 0)) / 2000
                            predictions.append(Path(segments: path.segments + [word], cost: score))
                        }
                    }
                    if predictions.count > beamWidth * 4 { predictions = ordered(predictions, limit: beamWidth * 2) }
                }
                for word in choices {
                    // Selectable prefixes are dictionary words from the first
                    // boundary, not shorter sentences assembled by the beam.
                    if start == 0 {
                        if end == raw.count { wholeWords.insert(word.text) }
                        else {
                            prefixes.append(Path(segments: [word],
                                cost: word.cost + transition(context, word) - bonus(context, word)))
                        }
                    }
                    if word.language == .chinese {
                        chineseCosts[end] = min(chineseCosts[end], chineseCosts[start] + word.cost)
                    }
                    for path in incoming {
                        let previous = path.last ?? context
                        let score = path.cost + word.cost + transition(previous, word) - bonus(previous, word)
                        lattice[end].append(Path(segments: path.segments + [word], cost: score))
                    }
                }
                if lattice[end].count > beamWidth * 4 {
                    lattice[end] = ordered(lattice[end], limit: beamWidth * 2)
                }
            }
        }
        var complete = lattice[length].map { path -> Path in
            var path = path
            if let last = path.last, last.language == .japanese {
                path.cost += Double(japanese.connection(from: last.right, to: 0)) / 2000
            }
            return path
        }
        // Calibrate native sentence alternatives against the Chinese word path,
        // instead of comparing Rime and Mozc's unrelated raw cost scales.
        var nativeWords: [Path] = []
        for (rank, item) in native.enumerated() {
            let syllables = item.comment.split(whereSeparator: { $0 == " " || $0 == "'" }).map(String.init)
            let code = syllables.joined()
            guard !code.isEmpty, code.allSatisfy({ $0.isASCII && $0.isLetter }),
                  let end = consumedInput(input, syllables: syllables), end <= length else { continue }
            let exact = String(raw.prefix(end)).replacingOccurrences(of: "'", with: "") == code
            let dictionaryWord = chinese.words(for: code).first { $0.text == item.text }
            // The compact mixed index prunes rare homophones. A native single
            // character is still a dictionary entry, never a generated sentence.
            let isWord = dictionaryWord != nil || (item.text.count == 1 && syllables.count == 1)
            // Abbreviated dictionary words are useful; a generated sentence
            // interpreting an arbitrary Japanese/raw tail as Chinese initials
            // must not replace that tail during an automatic flush.
            guard exact || (raw.count <= length && isWord) else { continue }
            let base = chineseCosts[end].isFinite ? chineseCosts[end] :
                dictionaryWord.map { max(1, 7.5 - 0.40 * log($0.frequency + 1)) } ?? Double(syllables.count) * 3
            let segment = Segment(raw: String(raw.prefix(end)), text: item.text, language: .chinese,
                left: 0, right: 0, cost: base - 0.25 + Double(rank) * 0.35 + (exact ? 0 : 3), corrected: false)
            let path = Path(segments: [segment], cost: segment.cost + transition(context, segment) - bonus(context, segment))
            if end == raw.count { complete.append(path) } else { prefixes.append(path) }
            if isWord, end == raw.count {
                wholeWords.insert(item.text)
                nativeWords.append(path)
            }
        }
        // Preserve the existing Chinese typo channel for the active remainder.
        // These are lexicon-supported full words, never arbitrary replacements
        // of already selected text; exact matches retain their lower cost.
        for suggestion in (corrector?.suggestions(for: input) ?? []).prefix(3) {
            let word = Segment(raw: input, text: suggestion.text, language: .chinese, left: 0, right: 0,
                cost: max(1, 7.5 - 0.40 * log(suggestion.frequency + 1)) + 3 * suggestion.cost, corrected: true)
            complete.append(Path(segments: [word], cost: word.cost + transition(context, word) - bonus(context, word)))
            wholeWords.insert(word.text)
        }
        // Refine promising Chinese runs with Rime's sentence model AFTER joint
        // boundary search. At most four distinct runs are queried, with the
        // caller caching prefixes across keystrokes. No O(n²) session probing.
        var refined: [Path] = []
        var queries: [String: [SKCandidate]] = [:]
        for path in ordered(complete, limit: 6) {
            var runs: [[Segment]] = []
            for segment in path.segments {
                if segment.language == .chinese, runs.last?.last?.language == .chinese {
                    runs[runs.count - 1].append(segment)
                } else { runs.append([segment]) }
            }
            var alternatives = [Path(segments: [], cost: 0)]
            for run in runs {
                let code = run.map(\.raw).joined(), text = run.map(\.text).joined()
                let baseCost = run.reduce(0) { $0 + $1.cost }
                var options = [run]
                if run.first?.language == .chinese, code.count >= 4 {
                    if queries[code] == nil, queries.count < 4 { queries[code] = chineseQuery(code) }
                    let exact = (queries[code] ?? []).filter {
                        $0.comment.replacingOccurrences(of: " ", with: "").replacingOccurrences(of: "'", with: "") == code.replacingOccurrences(of: "'", with: "")
                    }
                    options = exact.prefix(4).enumerated().map { rank, candidate in
                        [Segment(raw: code, text: candidate.text, language: .chinese, left: 0, right: 0,
                            cost: baseCost - 0.9 + Double(rank) * 0.25, corrected: run.contains(where: \.corrected))]
                    }
                    if !options.contains(where: { $0.map(\.text).joined() == text }) { options.append(run) }
                }
                var expanded: [Path] = []
                for previous in alternatives {
                    for option in options {
                        var score = previous.cost, last = previous.last ?? context
                        for segment in option {
                            score += segment.cost + transition(last, segment) - bonus(last, segment)
                            last = segment
                        }
                        expanded.append(Path(segments: previous.segments + option, cost: score))
                    }
                }
                alternatives = ordered(expanded, limit: beamWidth)
            }
            refined += alternatives.map { p in
                var p = p
                if let last = p.last, last.language == .japanese { p.cost += Double(japanese.connection(from: last.right, to: 0)) / 2000 }
                return p
            }
        }
        complete += refined
        var seen = Set<String>()
        let whole = ordered(complete, limit: beamWidth * 2).filter { seen.insert("\($0.consumed):\($0.text)").inserted }
        // Native/refined sentences may have been collapsed into one segment.
        // Verify actual dictionary membership rather than guessing from segment
        // count or output length; genuine long words remain available.
        wholeWords.formUnion(chinese.words(for: input.replacingOccurrences(of: "'", with: "")).map(\.text))
        // Six complete recommendations at most, then words from the beginning
        // of the remaining input. Never append more generated sentences later.
        var result = Array(whole.prefix(6))
        let predicted = ordered(predictions, limit: beamWidth)
        // Completed paths keep their places. Tail predictions fill unused
        // recommendation slots, so they cannot prune existing full sentences.
        for path in predicted where result.count < 6 {
            if seen.insert("\(path.consumed):\(path.text)").inserted { result.append(path) }
        }
        let partial = prefixes.sorted {
            $0.consumed == $1.consumed ? ($0.cost == $1.cost ? $0.text < $1.text : $0.cost < $1.cost) : $0.consumed > $1.consumed
        }.filter { seen.insert("\($0.consumed):\($0.text)").inserted }
        result += partial
        result += whole.dropFirst(6).filter { wholeWords.contains($0.text) }
        result += nativeWords.filter { seen.insert("\($0.consumed):\($0.text)").inserted }
        result += predicted.filter { $0.segments.count == 1 && seen.insert("\($0.consumed):\($0.text)").inserted }
        let completedWords = Set(predicted.filter { $0.segments.count == 1 }.map { "\($0.consumed):\($0.text)" })
        let words = result.filter {
            $0.consumed < input.count || wholeWords.contains($0.text) || completedWords.contains("\($0.consumed):\($0.text)")
        }
        return SKCandidateGrouping.arrange(recommendations: Array(result.prefix(6)), words: words,
            text: { $0.text }, identity: { "\($0.consumed):\($0.text)" })
    }
}
