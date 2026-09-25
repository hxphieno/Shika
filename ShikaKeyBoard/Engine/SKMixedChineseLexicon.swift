import Foundation

/// Read-only word lookup for joint decoding. Rime remains the Chinese sentence
/// expert; this index exposes word boundaries without creating a Rime session
/// for every substring. Built from the same pinned, attributed dictionary.
final class SKMixedChineseLexicon {
    struct Word { let text: String; let frequency: Double }
    private let data: Data
    private let count: Int
    private let tokens: Int
    private let pool: Int

    init(resources: URL) throws {
        data = try Data(contentsOf: resources.appendingPathComponent("mixed-chinese.bin"), options: .alwaysMapped)
        guard data.count >= 16, data.prefix(4) == Data("SKM1".utf8) else { throw SKRimeEngine.EngineError.missingResources }
        count = data.withUnsafeBytes { Int($0.loadUnaligned(fromByteOffset: 4, as: UInt32.self).littleEndian) }
        tokens = 16 + count * 12
        pool = data.withUnsafeBytes { Int($0.loadUnaligned(fromByteOffset: 12, as: UInt32.self).littleEndian) }
        guard count > 0, tokens <= pool, pool <= data.count else { throw SKRimeEngine.EngineError.missingResources }
    }

    func words(for code: String) -> [Word] {
        let key = Array(code.utf8)
        return data.withUnsafeBytes { bytes in
            var low = 0, high = count
            while low < high {
                let mid = (low + high) / 2, record = 16 + mid * 12
                let offset = pool + Int(bytes.loadUnaligned(fromByteOffset: record, as: UInt32.self).littleEndian)
                let length = Int(bytes.loadUnaligned(fromByteOffset: record + 4, as: UInt16.self).littleEndian)
                guard offset <= bytes.count, length <= bytes.count - offset else { return [] }
                var order = 0
                for i in 0..<min(length, key.count) where bytes[offset + i] != key[i] {
                    order = bytes[offset + i] < key[i] ? -1 : 1; break
                }
                if order == 0 { order = length == key.count ? 0 : (length < key.count ? -1 : 1) }
                if order < 0 { low = mid + 1; continue }
                if order > 0 { high = mid; continue }
                let n = Int(bytes.loadUnaligned(fromByteOffset: record + 6, as: UInt16.self).littleEndian)
                let first = Int(bytes.loadUnaligned(fromByteOffset: record + 8, as: UInt32.self).littleEndian)
                guard tokens + (first + n) * 12 <= pool else { return [] }
                return (first..<(first + n)).compactMap { index in
                    let record = tokens + index * 12
                    let offset = pool + Int(bytes.loadUnaligned(fromByteOffset: record, as: UInt32.self).littleEndian)
                    let length = Int(bytes.loadUnaligned(fromByteOffset: record + 4, as: UInt16.self).littleEndian)
                    guard offset <= bytes.count, length <= bytes.count - offset else { return nil }
                    return Word(text: String(decoding: bytes[offset..<(offset + length)], as: UTF8.self),
                        frequency: Double(bytes.loadUnaligned(fromByteOffset: record + 8, as: UInt32.self).littleEndian))
                }
            }
            return []
        }
    }
}
