import Foundation

/// Which parts of the smart money concepts indicator are drawn, and how coarse its swings are.
public struct SMCOptions: Codable, Equatable, Sendable {
    public var structure = true
    public var orderBlocks = true
    public var fairValueGaps = true
    public var liquidity = false
    public var premiumDiscount = false
    /// Candles on each side that must be lower (higher) for a swing high (low).
    public var swing = 5
    public init() {}
}

/// Smart money concepts worked out from candles: swings, breaks of structure, order blocks, fair value gaps,
/// equal highs/lows and the premium/discount range. Indices are candle indices.
public struct SMCResult: Equatable, Sendable {
    public struct Swing: Equatable, Sendable { public var index: Int; public var price: Double; public var isHigh: Bool }
    /// Close through the last swing: with the trend (BOS) or against it (CHoCH, change of character).
    public struct Break: Equatable, Sendable {
        public var from: Int; public var at: Int; public var price: Double; public var isBullish: Bool; public var isChange: Bool
    }
    /// A price zone from `start`; `end` is the candle that ended it (nil: still open).
    public struct Zone: Equatable, Sendable {
        public var start: Int; public var top: Double; public var bottom: Double; public var isBullish: Bool; public var end: Int?
    }
    public struct EqualLevel: Equatable, Sendable { public var first: Int; public var second: Int; public var price: Double; public var isHigh: Bool }

    public var swings: [Swing] = []
    public var breaks: [Break] = []
    public var orderBlocks: [Zone] = []
    public var fairValueGaps: [Zone] = []
    public var equals: [EqualLevel] = []
    /// Last swing high and low: above the middle is premium, below it discount.
    public var range: (high: Swing, low: Swing)?

    public static func == (a: SMCResult, b: SMCResult) -> Bool {
        a.swings == b.swings && a.breaks == b.breaks && a.orderBlocks == b.orderBlocks && a.fairValueGaps == b.fairValueGaps
            && a.equals == b.equals && a.range?.high == b.range?.high && a.range?.low == b.range?.low
    }
}

public enum SmartMoney {
    /// Swing highs and lows: the highest (lowest) candle among `n` candles on each side. Known `n` candles later.
    public static func swings(_ c: [Candle], n: Int) -> [SMCResult.Swing] {
        let n = max(n, 1)
        guard c.count > 2 * n else { return [] }
        var out: [SMCResult.Swing] = []
        for i in n..<(c.count - n) {
            var isHigh = true, isLow = true
            for k in (i - n)...(i + n) where k != i {
                // Earlier candles may tie, later ones may not: of equal tops the first one counts.
                if k < i ? c[k].high > c[i].high : c[k].high >= c[i].high { isHigh = false }
                if k < i ? c[k].low < c[i].low : c[k].low <= c[i].low { isLow = false }
            }
            if isHigh { out.append(.init(index: i, price: c[i].high, isHigh: true)) }
            if isLow { out.append(.init(index: i, price: c[i].low, isHigh: false)) }
        }
        return out
    }

    /// Average candle range over the last `length` candles before `i` (a simple yardstick for "small").
    static func averageRange(_ c: [Candle], at i: Int, length: Int = 14) -> Double {
        let lo = max(i - length, 0)
        guard i > lo else { return c.isEmpty ? 0 : c[min(i, c.count - 1)].high - c[min(i, c.count - 1)].low }
        return c[lo..<i].reduce(0) { $0 + ($1.high - $1.low) } / Double(i - lo)
    }

    /// Three-candle gaps: the third candle's low above the first one's high (bullish), or the mirror image.
    /// A gap ends when price trades back through all of it.
    public static func fairValueGaps(_ c: [Candle], minShare: Double = 0.3) -> [SMCResult.Zone] {
        guard c.count >= 3 else { return [] }
        var out: [SMCResult.Zone] = []
        for i in 2..<c.count {
            let avg = averageRange(c, at: i)
            if c[i].low > c[i - 2].high, c[i].low - c[i - 2].high >= avg * minShare {
                out.append(.init(start: i - 1, top: c[i].low, bottom: c[i - 2].high, isBullish: true, end: nil))
            } else if c[i].high < c[i - 2].low, c[i - 2].low - c[i].high >= avg * minShare {
                out.append(.init(start: i - 1, top: c[i - 2].low, bottom: c[i].high, isBullish: false, end: nil))
            }
        }
        for k in out.indices {
            let z = out[k]
            var j = z.start + 2
            while j < c.count {
                if z.isBullish ? c[j].low <= z.bottom : c[j].high >= z.top { out[k].end = j; break }
                j += 1
            }
        }
        return out
    }

    public static func compute(_ c: [Candle], options o: SMCOptions = SMCOptions()) -> SMCResult {
        var r = SMCResult()
        let n = max(o.swing, 1)
        guard c.count > 2 * n + 1 else { return r }
        r.swings = swings(c, n: n)
        r.fairValueGaps = fairValueGaps(c)

        // Structure: walk through time. A swing is known n candles after it formed.
        var known = 0                                   // swings[..<known] are confirmed
        var lastHigh: SMCResult.Swing?, lastLow: SMCResult.Swing?
        var highBroken = true, lowBroken = true
        var trend = 0
        for j in 0..<c.count {
            while known < r.swings.count, r.swings[known].index + n <= j {
                let s = r.swings[known]
                if s.isHigh { lastHigh = s; highBroken = false } else { lastLow = s; lowBroken = false }
                known += 1
            }
            if let h = lastHigh, !highBroken, c[j].close > h.price {
                highBroken = true
                r.breaks.append(.init(from: h.index, at: j, price: h.price, isBullish: true, isChange: trend == -1))
                trend = 1
                // Order block: the last falling candle before the move that broke the high.
                let from = h.index
                if let k = stride(from: j - 1, through: from, by: -1).first(where: { c[$0].close < c[$0].open }) {
                    r.orderBlocks.append(.init(start: k, top: c[k].high, bottom: c[k].low, isBullish: true, end: nil))
                }
            }
            if let l = lastLow, !lowBroken, c[j].close < l.price {
                lowBroken = true
                r.breaks.append(.init(from: l.index, at: j, price: l.price, isBullish: false, isChange: trend == 1))
                trend = -1
                let from = l.index
                if let k = stride(from: j - 1, through: from, by: -1).first(where: { c[$0].close > c[$0].open }) {
                    r.orderBlocks.append(.init(start: k, top: c[k].high, bottom: c[k].low, isBullish: false, end: nil))
                }
            }
        }
        // An order block ends when price closes through it.
        for k in r.orderBlocks.indices {
            let z = r.orderBlocks[k]
            let created = r.breaks.first { $0.isBullish == z.isBullish && $0.at > z.start }?.at ?? z.start
            var j = created + 1
            while j < c.count {
                if z.isBullish ? c[j].close < z.bottom : c[j].close > z.top { r.orderBlocks[k].end = j; break }
                j += 1
            }
        }

        // Equal highs / lows: two swings in a row at almost the same price (resting liquidity).
        for isHigh in [true, false] {
            let s = r.swings.filter { $0.isHigh == isHigh }
            guard s.count > 1 else { continue }
            for k in 1..<s.count {
                let tolerance = averageRange(c, at: s[k].index) * 0.1
                if abs(s[k].price - s[k - 1].price) <= tolerance {
                    r.equals.append(.init(first: s[k - 1].index, second: s[k].index, price: isHigh ? max(s[k].price, s[k - 1].price) : min(s[k].price, s[k - 1].price), isHigh: isHigh))
                }
            }
        }
        if let h = r.swings.last(where: { $0.isHigh }), let l = r.swings.last(where: { !$0.isHigh }) { r.range = (h, l) }
        return r
    }
}
