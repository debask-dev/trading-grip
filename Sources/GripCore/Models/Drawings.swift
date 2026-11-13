import Foundation

/// A point anchored in time and price, so drawings stay put across timeframes.
public struct ChartPoint: Codable, Equatable, Sendable {
    public var time: Int64   // ms
    public var price: Double
    public init(time: Int64, price: Double) { self.time = time; self.price = price }
}

public enum DrawingColor: String, Codable, CaseIterable, Sendable {
    case yellow, blue, purple, white, green, red
}

public struct Trendline: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var coin: String
    public var a: ChartPoint
    public var b: ChartPoint
    public var color: DrawingColor
    public var extendRight: Bool
    public var createdAt: Date

    public init(id: UUID = UUID(), coin: String, a: ChartPoint, b: ChartPoint, color: DrawingColor = .yellow, extendRight: Bool = false, createdAt: Date = Date()) {
        self.id = id; self.coin = coin; self.a = a; self.b = b; self.color = color; self.extendRight = extendRight; self.createdAt = createdAt
    }

    /// Price of the line at a given time (linear in time).
    public func price(at time: Int64) -> Double {
        let dt = Double(b.time - a.time)
        if dt == 0 { return b.price }
        return a.price + (b.price - a.price) * Double(time - a.time) / dt
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
