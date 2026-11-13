import Foundation

/// A small ordered value tree that can be encoded both as MessagePack (for Hyperliquid's
/// action hash, where key order matters) and as JSON (for the HTTP request body).
public indirect enum WireValue: Equatable, Sendable {
    case null
    case bool(Bool)
    case int(Int64)
    case string(String)
    case array([WireValue])
    case map([(String, WireValue)])

    public static func == (lhs: WireValue, rhs: WireValue) -> Bool {
        switch (lhs, rhs) {
        case (.null, .null): return true
        case let (.bool(a), .bool(b)): return a == b
        case let (.int(a), .int(b)): return a == b
        case let (.string(a), .string(b)): return a == b
        case let (.array(a), .array(b)): return a == b
        case let (.map(a), .map(b)):
            return a.count == b.count && zip(a, b).allSatisfy { $0.0 == $1.0 && $0.1 == $1.1 }
        default: return false
        }
    }

    // MARK: MessagePack

    public func msgpack() -> Data {
        var out = [UInt8]()
        encode(into: &out)
        return Data(out)
    }

    private func encode(into out: inout [UInt8]) {
        switch self {
        case .null:
            out.append(0xC0)
        case .bool(let b):
            out.append(b ? 0xC3 : 0xC2)
        case .int(let v):
            Self.encodeInt(v, into: &out)
        case .string(let s):
            let bytes = Array(s.utf8)
            let n = bytes.count
            if n < 32 { out.append(0xA0 | UInt8(n)) }
            else if n < 256 { out.append(0xD9); out.append(UInt8(n)) }
            else if n < 65536 { out.append(0xDA); Self.be(UInt64(n), 2, &out) }
            else { out.append(0xDB); Self.be(UInt64(n), 4, &out) }
            out.append(contentsOf: bytes)
        case .array(let items):
            let n = items.count
            if n < 16 { out.append(0x90 | UInt8(n)) }
            else if n < 65536 { out.append(0xDC); Self.be(UInt64(n), 2, &out) }
            else { out.append(0xDD); Self.be(UInt64(n), 4, &out) }
            for item in items { item.encode(into: &out) }
        case .map(let pairs):
            let n = pairs.count
            if n < 16 { out.append(0x80 | UInt8(n)) }
            else if n < 65536 { out.append(0xDE); Self.be(UInt64(n), 2, &out) }
            else { out.append(0xDF); Self.be(UInt64(n), 4, &out) }
            for (k, v) in pairs {
                WireValue.string(k).encode(into: &out)
                v.encode(into: &out)
            }
        }
    }

    private static func encodeInt(_ v: Int64, into out: inout [UInt8]) {
        if v >= 0 {
            let u = UInt64(v)
            if u < 128 { out.append(UInt8(u)) }
            else if u < 256 { out.append(0xCC); out.append(UInt8(u)) }
            else if u < 65536 { out.append(0xCD); be(u, 2, &out) }
            else if u < 4_294_967_296 { out.append(0xCE); be(u, 4, &out) }
            else { out.append(0xCF); be(u, 8, &out) }
        } else {
            if v >= -32 { out.append(UInt8(bitPattern: Int8(v))) }
            else if v >= -128 { out.append(0xD0); out.append(UInt8(bitPattern: Int8(v))) }
            else if v >= -32768 { out.append(0xD1); be(UInt64(bitPattern: v), 2, &out) }
            else if v >= -2_147_483_648 { out.append(0xD2); be(UInt64(bitPattern: v), 4, &out) }
            else { out.append(0xD3); be(UInt64(bitPattern: v), 8, &out) }
        }
    }

    private static func be(_ v: UInt64, _ bytes: Int, _ out: inout [UInt8]) {
        for i in stride(from: bytes - 1, through: 0, by: -1) { out.append(UInt8((v >> UInt64(8 * i)) & 0xFF)) }
    }

    // MARK: JSON

    public func json() -> String {
        switch self {
        case .null: return "null"
        case .bool(let b): return b ? "true" : "false"
        case .int(let v): return String(v)
        case .string(let s): return Self.jsonString(s)
        case .array(let items): return "[" + items.map { $0.json() }.joined(separator: ",") + "]"
        case .map(let pairs): return "{" + pairs.map { Self.jsonString($0.0) + ":" + $0.1.json() }.joined(separator: ",") + "}"
        }
    }

    private static func jsonString(_ s: String) -> String {
        var r = "\""
        for ch in s.unicodeScalars {
            switch ch {
            case "\"": r += "\\\""
            case "\\": r += "\\\\"
            case "\n": r += "\\n"
            case "\r": r += "\\r"
            case "\t": r += "\\t"
            default:
                if ch.value < 0x20 { r += String(format: "\\u%04x", ch.value) } else { r.unicodeScalars.append(ch) }
            }
        }
        return r + "\""
    }
}
