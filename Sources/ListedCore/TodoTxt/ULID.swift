import Foundation

/// Lightweight ULID implementation (Crockford base32, 26 chars).
///
/// The representation is monotonic-ish: 48 bits of millisecond timestamp followed by
/// 80 bits of randomness. We don't need a full library here, just stable, sortable,
/// human-friendly task IDs to write into `uid:` metadata.
public enum ULID {
    private static let alphabet: [Character] = Array("0123456789ABCDEFGHJKMNPQRSTVWXYZ")

    public static func generate(at date: Date = Date()) -> String {
        let ms = UInt64(max(0, date.timeIntervalSince1970 * 1000))
        var random = [UInt8](repeating: 0, count: 10)
        for i in 0..<random.count {
            random[i] = UInt8.random(in: 0...255)
        }
        return encode(timestamp: ms, random: random)
    }

    /// Returns true if `string` looks like a ULID (26 Crockford-base32 characters).
    public static func isValid(_ string: String) -> Bool {
        guard string.count == 26 else { return false }
        let allowed = Set(alphabet)
        return string.allSatisfy { allowed.contains($0) }
    }

    private static func encode(timestamp ms: UInt64, random: [UInt8]) -> String {
        // Build 16-byte big-endian representation: 6 bytes timestamp + 10 bytes random.
        var bytes = [UInt8](repeating: 0, count: 16)
        bytes[0] = UInt8((ms >> 40) & 0xFF)
        bytes[1] = UInt8((ms >> 32) & 0xFF)
        bytes[2] = UInt8((ms >> 24) & 0xFF)
        bytes[3] = UInt8((ms >> 16) & 0xFF)
        bytes[4] = UInt8((ms >> 8) & 0xFF)
        bytes[5] = UInt8(ms & 0xFF)
        for i in 0..<10 { bytes[6 + i] = random[i] }

        // Encode 16 bytes (128 bits) into 26 Crockford base32 chars.
        // We treat the 128 bits as a big-endian unsigned integer and pull 5 bits at a time.
        // 128 bits = 26 chars * 5 bits = 130, so the leading char only encodes 3 bits.
        var output = [Character](repeating: "0", count: 26)

        // Top 3 bits → first char (only the lowest 3 bits of bytes[0])
        let topBits = (bytes[0] >> 5) & 0b00000111
        output[0] = alphabet[Int(topBits)]

        // Now stream the remaining 125 bits as a bit buffer.
        // Easier to just iterate a bit cursor.
        var bitBuffer: UInt32 = 0
        var bitsInBuffer: Int = 0
        var byteIndex = 0
        // We've already consumed the top 3 bits of bytes[0]; preload the lower 5 bits.
        bitBuffer = UInt32(bytes[0] & 0b00011111)
        bitsInBuffer = 5
        byteIndex = 1

        var outIndex = 1
        while outIndex < 26 {
            if bitsInBuffer < 5 && byteIndex < 16 {
                bitBuffer = (bitBuffer << 8) | UInt32(bytes[byteIndex])
                bitsInBuffer += 8
                byteIndex += 1
            }
            let shift = bitsInBuffer - 5
            let chunk = UInt32((bitBuffer >> shift) & 0b11111)
            bitBuffer &= (1 << shift) - 1
            bitsInBuffer -= 5
            output[outIndex] = alphabet[Int(chunk)]
            outIndex += 1
        }
        return String(output)
    }
}
