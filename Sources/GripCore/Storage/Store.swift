import Foundation

/// Small JSON file store in ~/Library/Application Support/Grip.
public final class JSONStore: @unchecked Sendable {
    public let directory: URL
    private let queue = DispatchQueue(label: "grip.store")

    public init(directory: URL? = nil) {
        if let directory {
            self.directory = directory
        } else {
            let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                ?? URL(fileURLWithPath: NSTemporaryDirectory())
            self.directory = base.appendingPathComponent("Grip", isDirectory: true)
        }
        try? FileManager.default.createDirectory(at: self.directory, withIntermediateDirectories: true)
    }

    private func url(_ name: String) -> URL { directory.appendingPathComponent(name + ".json") }

    public func load<T: Decodable>(_ type: T.Type, from name: String) -> T? {
        guard let data = try? Data(contentsOf: url(name)) else { return nil }
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        return try? dec.decode(T.self, from: data)
    }

    public func save<T: Encodable>(_ value: T, to name: String) {
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? enc.encode(value) else { return }
        let target = url(name)
        queue.async { try? data.write(to: target, options: .atomic) }
    }

    /// Writes synchronously (used in tests and on quit).
    public func saveNow<T: Encodable>(_ value: T, to name: String) throws {
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        try enc.encode(value).write(to: url(name), options: .atomic)
    }
}

/// Number formatting with a privacy switch: when `hidden` is on, every dollar amount
/// and position size is masked so a screenshot can be shared safely. Percentages and prices stay.
public struct Fmt: Sendable {
    public var hidden: Bool
    public static let mask = "•••"

    public init(hidden: Bool) { self.hidden = hidden }

    private static func nf(_ min: Int, _ max: Int) -> NumberFormatter {
        let f = NumberFormatter()
        f.locale = Locale(identifier: "nl_NL")
        f.numberStyle = .decimal
        f.minimumFractionDigits = min
        f.maximumFractionDigits = max
        f.roundingMode = .halfUp
        return f
    }

    public static func number(_ v: Double, decimals: Int) -> String {
        nf(decimals, decimals).string(from: NSNumber(value: v)) ?? String(v)
    }

    /// Price with sensible decimals for its magnitude (always visible).
    public static func price(_ v: Double) -> String {
        let a = abs(v)
        let decimals = a >= 10_000 ? 0 : a >= 100 ? 2 : a >= 1 ? 3 : a >= 0.01 ? 5 : 7
        return number(v, decimals: decimals)
    }

    public func usd(_ v: Double, decimals: Int = 0) -> String {
        if hidden { return "$" + Self.mask }
        return (v < 0 ? "−" : "") + "$" + Self.number(abs(v), decimals: decimals)
    }

    public func signedUsd(_ v: Double, decimals: Int = 0) -> String {
        if hidden { return (v >= 0 ? "+" : "−") + "$" + Self.mask }
        return (v >= 0 ? "+" : "−") + "$" + Self.number(abs(v), decimals: decimals)
    }

    public func size(_ v: Double, coin: String, decimals: Int) -> String {
        if hidden { return Self.mask + " " + coin }
        return Self.number(abs(v), decimals: decimals) + " " + coin
    }

    /// 1.2K, 3.45M, 1.20B.
    public static func compact(_ v: Double) -> String {
        let a = abs(v)
        if a >= 1e9 { return number(v / 1e9, decimals: 2) + "B" }
        if a >= 1e6 { return number(v / 1e6, decimals: 2) + "M" }
        if a >= 1e3 { return number(v / 1e3, decimals: 1) + "K" }
        return number(v, decimals: a < 10 ? 2 : 0)
    }

    public static func percent(_ fraction: Double, decimals: Int = 2, signed: Bool = true) -> String {
        let s = number(abs(fraction * 100), decimals: decimals) + "%"
        guard signed else { return (fraction < 0 ? "−" : "") + s }
        return (fraction >= 0 ? "+" : "−") + s
    }
}
