import Foundation

/// Stores only symbol counts locally; never stores the surrounding input.
final class SKSymbolMemory {
    private let defaults: UserDefaults
    private let key = "keyboard.symbolUsage.v1"
    init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    func record(_ symbol: String) {
        guard SKSymbolLayout.punctuation.contains(symbol) else { return }
        var counts = defaults.dictionary(forKey: key) as? [String: Int] ?? [:]
        counts[symbol] = min(max(0, counts[symbol, default: 0]), 1_000_000) + 1
        defaults.set(counts, forKey: key)
    }

    func orderedSymbols() -> [String] {
        let counts = defaults.dictionary(forKey: key) as? [String: Int] ?? [:]
        let original = SKSymbolLayout.punctuation
        let pairs = SKSymbolLayout.pairedSymbols
        var groups: [[String]] = []
        var grouped = Set<String>()
        for symbol in original where !grouped.contains(symbol) {
            let group = pairs.first { $0.contains(symbol) } ?? [symbol]
            groups.append(group)
            grouped.formUnion(group)
        }
        func score(_ group: [String]) -> Int {
            group.reduce(0) { $0 + min(1_000_001, max(0, counts[$1, default: 0])) }
        }
        var ranked = groups.indices.sorted {
            let a = score(groups[$0]), b = score(groups[$1])
            return a == b ? $0 < $1 : a > b
        }
        var order: [String] = []
        var used = Set<Int>()
        // Four keys form a vertical column. Never split a pair across columns
        // or the 16-key frequent region; use the next fitting group to fill it.
        while order.count < 16, !ranked.isEmpty {
            let room = 4 - order.count % 4
            guard let index = ranked.firstIndex(where: { groups[$0].count <= room }) else { break }
            let group = ranked.remove(at: index)
            used.insert(group)
            order += groups[group]
        }
        var remaining = groups.indices.filter { !used.contains($0) }
        while !remaining.isEmpty {
            let room = 4 - order.count % 4
            guard let index = remaining.firstIndex(where: { groups[$0].count <= room }) else {
                // Current inventory has enough single keys to fill every column.
                order += remaining.flatMap { groups[$0] }
                break
            }
            order += groups[remaining.remove(at: index)]
        }
        return order
    }
}
