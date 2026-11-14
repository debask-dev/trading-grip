import Foundation

/// A point anchored in time and price, so drawings stay put across timeframes.
public struct ChartPoint: Codable, Equatable, Sendable {
    public var time: Int64   // ms
    public var price: Double
    public init(time: Int64, price: Double) { self.time = time; self.price = price }
}

public enum LineDash: String, Codable, CaseIterable, Sendable {
    case solid, dashed, dotted
}

/// Colors offered in the line toolbar (any hex color is allowed).
public enum LineSwatches {
    public static let all = ["#D55C26", "#F5D547", "#FFB547", "#FF5C6C", "#2FD394", "#5AA2FF", "#7C6CFF", "#E7EBF2", "#8A94A6"]
    public static let defaultColor = "#D55C26"
}

/// Appearance used for newly drawn lines (remembered from the last change in the toolbar).
public struct LineAppearance: Codable, Equatable, Sendable {
    public var color: String
    public var width: Double
    public var dash: LineDash
    public var extendLeft: Bool
    public var extendRight: Bool

    public init(color: String = LineSwatches.defaultColor, width: Double = 2, dash: LineDash = .solid, extendLeft: Bool = false, extendRight: Bool = false) {
        self.color = color; self.width = width; self.dash = dash; self.extendLeft = extendLeft; self.extendRight = extendRight
    }
}

public struct Trendline: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var coin: String
    public var a: ChartPoint
    public var b: ChartPoint
    public var color: String         // hex, e.g. "#F5D547"
    public var width: Double         // 1...4 pt
    public var dash: LineDash
    public var extendLeft: Bool
    public var extendRight: Bool
    public var createdAt: Date

    public init(id: UUID = UUID(), coin: String, a: ChartPoint, b: ChartPoint, color: String = LineSwatches.defaultColor, width: Double = 2,
                dash: LineDash = .solid, extendLeft: Bool = false, extendRight: Bool = false, createdAt: Date = Date()) {
        self.id = id; self.coin = coin; self.a = a; self.b = b; self.color = color; self.width = width; self.dash = dash
        self.extendLeft = extendLeft; self.extendRight = extendRight; self.createdAt = createdAt
    }

    public init(coin: String, a: ChartPoint, b: ChartPoint, appearance: LineAppearance) {
        self.init(coin: coin, a: a, b: b, color: appearance.color, width: appearance.width, dash: appearance.dash,
                  extendLeft: appearance.extendLeft, extendRight: appearance.extendRight)
    }

    public var appearance: LineAppearance {
        get { LineAppearance(color: color, width: width, dash: dash, extendLeft: extendLeft, extendRight: extendRight) }
        set { color = newValue.color; width = newValue.width; dash = newValue.dash; extendLeft = newValue.extendLeft; extendRight = newValue.extendRight }
    }

    /// Price of the line at a given time (linear in time).
    public func price(at time: Int64) -> Double {
        let dt = Double(b.time - a.time)
        if dt == 0 { return b.price }
        return a.price + (b.price - a.price) * Double(time - a.time) / dt
    }

    // Lines saved by version 0.1 used named colors and had no width/style.
    private enum CodingKeys: String, CodingKey { case id, coin, a, b, color, width, dash, extendLeft, extendRight, createdAt }
    private static let legacyColors = ["yellow": "#F5D547", "blue": "#5AA2FF", "purple": "#7C6CFF", "white": "#E7EBF2", "green": "#2FD394", "red": "#FF5C6C"]

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        coin = try c.decode(String.self, forKey: .coin)
        a = try c.decode(ChartPoint.self, forKey: .a)
        b = try c.decode(ChartPoint.self, forKey: .b)
        let raw = try c.decodeIfPresent(String.self, forKey: .color) ?? "#F5D547"
        color = Self.legacyColors[raw] ?? raw
        width = try c.decodeIfPresent(Double.self, forKey: .width) ?? 2
        dash = try c.decodeIfPresent(LineDash.self, forKey: .dash) ?? .solid
        extendLeft = try c.decodeIfPresent(Bool.self, forKey: .extendLeft) ?? false
        extendRight = try c.decodeIfPresent(Bool.self, forKey: .extendRight) ?? false
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
    }
}

/// What the user intended when placing a trade from the ticket; used for R-multiples in history.
public struct TradePlan: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var coin: String
    public var isLong: Bool
    public var entry: Double
    public var stopLoss: Double
    public var takeProfit: Double?
    public var riskUsd: Double
    public var riskPercent: Double
    public var createdAt: Date

    public init(id: UUID = UUID(), coin: String, isLong: Bool, entry: Double, stopLoss: Double, takeProfit: Double?, riskUsd: Double, riskPercent: Double, createdAt: Date = Date()) {
        self.id = id; self.coin = coin; self.isLong = isLong; self.entry = entry; self.stopLoss = stopLoss
        self.takeProfit = takeProfit; self.riskUsd = riskUsd; self.riskPercent = riskPercent; self.createdAt = createdAt
    }
}

/// Snap helper: the OHLC value of the nearest candle closest to the cursor price.
public enum Snap {
    public static func snap(time: Int64, price: Double, candles: [Candle], timeframe: Timeframe) -> ChartPoint? {
        guard let idx = nearestIndex(time: time, candles: candles) else { return nil }
        // Only snap when the cursor is actually over (or right next to) a candle.
        guard abs(candles[idx].time - time) <= timeframe.milliseconds else { return nil }
        let c = candles[idx]
        let best = c.ohlc.min(by: { abs($0 - price) < abs($1 - price) }) ?? c.close
        return ChartPoint(time: c.time, price: best)
    }

    /// Binary search for the candle whose open time is closest to `time`.
    public static func nearestIndex(time: Int64, candles: [Candle]) -> Int? {
        guard !candles.isEmpty else { return nil }
        var lo = 0, hi = candles.count - 1
        while lo < hi {
            let mid = (lo + hi) / 2
            if candles[mid].time < time { lo = mid + 1 } else { hi = mid }
        }
        if lo > 0, abs(candles[lo - 1].time - time) <= abs(candles[lo].time - time) { return lo - 1 }
        return lo
    }
}
