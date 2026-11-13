import Foundation

/// Keccak-256 as used by Ethereum (original Keccak padding, not SHA3-256).
public enum Keccak {
    private static let roundConstants: [UInt64] = [
        0x0000000000000001, 0x0000000000008082, 0x800000000000808A, 0x8000000080008000,
        0x000000000000808B, 0x0000000080000001, 0x8000000080008081, 0x8000000000008009,
        0x000000000000008A, 0x0000000000000088, 0x0000000080008009, 0x000000008000000A,
        0x000000008000808B, 0x800000000000008B, 0x8000000000008089, 0x8000000000008003,
        0x8000000000008002, 0x8000000000000080, 0x000000000000800A, 0x800000008000000A,
        0x8000000080008081, 0x8000000000008080, 0x0000000080000001, 0x8000000080008008,
    ]
    private static let rotations: [Int] = [
        0, 1, 62, 28, 27, 36, 44, 6, 55, 20, 3, 10, 43, 25, 39, 41, 45, 15, 21, 8, 18, 2, 61, 56, 14,
    ]

    @inline(__always) private static func rotl(_ x: UInt64, _ n: Int) -> UInt64 {
        n == 0 ? x : (x << UInt64(n)) | (x >> UInt64(64 - n))
    }

    private static func keccakF(_ a: inout [UInt64]) {
        var c = [UInt64](repeating: 0, count: 5)
        var b = [UInt64](repeating: 0, count: 25)
        for round in 0..<24 {
            for x in 0..<5 { c[x] = a[x] ^ a[x + 5] ^ a[x + 10] ^ a[x + 15] ^ a[x + 20] }
            for x in 0..<5 {
                let d = c[(x + 4) % 5] ^ rotl(c[(x + 1) % 5], 1)
                for y in 0..<5 { a[x + 5 * y] ^= d }
            }
            for x in 0..<5 {
                for y in 0..<5 {
                    let idx = x + 5 * y
                    b[y + 5 * ((2 * x + 3 * y) % 5)] = rotl(a[idx], rotations[idx])
                }
            }
            for x in 0..<5 {
                for y in 0..<5 {
                    a[x + 5 * y] = b[x + 5 * y] ^ (~b[(x + 1) % 5 + 5 * y] & b[(x + 2) % 5 + 5 * y])
                }
            }
            a[0] ^= roundConstants[round]
        }
    }

    public static func hash256(_ data: Data) -> Data { hash256([UInt8](data)) }

    public static func hash256(_ input: [UInt8]) -> Data {
        let rate = 136
        var msg = input
        msg.append(0x01)
        while msg.count % rate != 0 { msg.append(0x00) }
        msg[msg.count - 1] |= 0x80

        var state = [UInt64](repeating: 0, count: 25)
        var offset = 0
        while offset < msg.count {
            for i in 0..<(rate / 8) {
                var lane: UInt64 = 0
                for j in 0..<8 { lane |= UInt64(msg[offset + i * 8 + j]) << UInt64(8 * j) }
                state[i] ^= lane
            }
            keccakF(&state)
            offset += rate
        }
        var out = [UInt8]()
        out.reserveCapacity(32)
        for i in 0..<4 {
            for j in 0..<8 { out.append(UInt8((state[i] >> UInt64(8 * j)) & 0xFF)) }
        }
        return Data(out)
    }
}

public extension Data {
    var hex: String { map { String(format: "%02x", $0) }.joined() }

    init?(hex: String) {
        var s = hex.lowercased()
        if s.hasPrefix("0x") { s.removeFirst(2) }
        guard s.count % 2 == 0 else { return nil }
        var bytes = [UInt8]()
        bytes.reserveCapacity(s.count / 2)
        var it = s.makeIterator()
        while let a = it.next(), let b = it.next() {
            guard let v = UInt8(String([a, b]), radix: 16) else { return nil }
            bytes.append(v)
        }
        self.init(bytes)
    }
}
