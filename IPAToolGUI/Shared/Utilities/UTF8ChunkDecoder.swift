import Foundation

/// Incrementally decodes UTF-8 without splitting multi-byte sequences across chunks.
struct UTF8ChunkDecoder: Sendable {
    private var pending: [UInt8] = []

    mutating func decode(_ data: Data) -> String {
        pending.append(contentsOf: data)
        let cut = Self.safeCutIndex(pending)
        let complete = pending[..<cut]
        let text = String(decoding: complete, as: UTF8.self)
        pending.removeFirst(cut)
        return text
    }

    mutating func flush() -> String {
        defer { pending.removeAll() }
        return String(decoding: pending, as: UTF8.self)
    }

    /// Index after which bytes may belong to an unfinished sequence.
    private static func safeCutIndex(_ bytes: [UInt8]) -> Int {
        guard !bytes.isEmpty else { return 0 }
        var index = bytes.count - 1
        var lookedBack = 0
        while index >= 0 && lookedBack < 4 {
            let byte = bytes[index]
            if byte & 0b1100_0000 == 0b1000_0000 {
                index -= 1
                lookedBack += 1
                continue
            }
            let expected: Int
            if byte & 0b1000_0000 == 0 { expected = 1 }
            else if byte & 0b1110_0000 == 0b1100_0000 { expected = 2 }
            else if byte & 0b1111_0000 == 0b1110_0000 { expected = 3 }
            else if byte & 0b1111_1000 == 0b1111_0000 { expected = 4 }
            else { return bytes.count }
            let available = bytes.count - index
            return available >= expected ? bytes.count : index
        }
        return bytes.count
    }
}
