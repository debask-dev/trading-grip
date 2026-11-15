import Foundation

/// What the position label in the chart shows as a bar: the whole trade from "stop hit" (left) to "all take-profits
/// hit" (right), with where it stands now. Entries that still wait count as filled for both ends (a stop is reached
/// through them; take-profits grow along with the position), so 1R does not jump at every fill.
public struct TradeMeter: Equatable, Sendable {
    public struct Input: Sendable {
        public var isLong: Bool
        /// Open position in coins (0 before the first fill).
        public var size: Double
        public var entry: Double
        /// Already settled for this trade: realized parts − fees paid + funding.
        public var locked: Double
        /// Entries that still wait to fill.
        public var restingEntries: [(price: Double, size: Double)]
        public var stop: Double?
        public var liquidation: Double?
        /// Share of the position each take-profit closes (fractions may add up to less than 1).
        public var takeProfits: [TPTarget]
        /// Risk of the plan as placed (positive). Nil: worked out from the stop and all entries.
        public var plannedRisk: Double?
        public var maker: Double
        public var taker: Double

        public init(isLong: Bool, size: Double, entry: Double, locked: Double = 0, restingEntries: [(price: Double, size: Double)] = [],
                    stop: Double?, liquidation: Double? = nil, takeProfits: [TPTarget], plannedRisk: Double? = nil,
                    maker: Double, taker: Double) {
            self.isLong = isLong; self.size = size; self.entry = entry; self.locked = locked; self.restingEntries = restingEntries
            self.stop = stop; self.liquidation = liquidation; self.takeProfits = takeProfits; self.plannedRisk = plannedRisk
            self.maker = maker; self.taker = taker
        }
    }

    /// Whole-trade result if everything closed now at the current price.
    public var now: Double
    /// Left end: result when the stop is hit (or the liquidation price without a stop). Nil: neither known.
    public var low: Double?
    public var lowIsLiquidation: Bool
    /// Right end: result when all take-profits are hit, with all entries filled. Nil without take-profits.
    public var high: Double?
    /// Same, with only what is filled now.
    public var highNow: Double?
    /// Take-profits close less than the whole position: the right end is "at least".
    public var openEnded: Bool
    /// Result at each take-profit that is still open, nearest first (all entries filled).
    public var marks: [Double]
    /// 1R in dollars (positive). Nil without a stop.
    public var oneR: Double?
    /// Weighted average take-profit price (nil without take-profits).
    public var averageTP: Double?
    /// Average entry if all entries fill.
    public var plannedEntry: Double
    public var hasPosition: Bool
    public var entriesFilled: Int
    public var entriesTotal: Int

    public func r(_ v: Double) -> Double? { oneR.map { v / max($0, 1e-9) } }

    public static func compute(_ i: Input, price: Double, filledEntries: Int = 0) -> TradeMeter {
        let dir: Double = i.isLong ? 1 : -1
        let q = abs(i.size), e = i.entry, locked = i.locked
        func close(_ q: Double, _ e: Double, _ locked: Double, at p: Double, fee: Double) -> Double {
            locked + q * dir * (p - e) - q * p * fee
        }
        // All waiting entries filled (the ones the stop does not come before).
        var fq = q, fe = e, flocked = locked
        for en in i.restingEntries where en.size > 0 {
            if let s = i.stop, dir * (en.price - s) <= 0 { continue }
            fe = fq + en.size > 0 ? (fe * fq + en.price * en.size) / (fq + en.size) : en.price
            fq += en.size
            flocked -= en.size * en.price * i.maker
        }
        let tps = i.takeProfits.filter { $0.fraction > 1e-9 && $0.price > 0 && dir * ($0.price - fe) > 0 }
            .sorted { dir * ($0.price - $1.price) < 0 }
        let cover = min(tps.reduce(0) { $0 + $1.fraction }, 1)
        // Result when the price walks to p from here: take-profits on the way fill, the rest closes at p.
        func walk(_ q: Double, _ e: Double, _ locked: Double, to p: Double, restFee: Double) -> Double {
            var res = locked, left = 1.0
            for t in tps where dir * (p - t.price) >= 0 {
                let part = q * min(t.fraction, left)
                res += part * dir * (t.price - e) - part * t.price * i.maker
                left -= min(t.fraction, left)
            }
            return res + close(q * max(left, 0), e, 0, at: p, fee: restFee)
        }

        let now = close(q, e, locked, at: price, fee: i.taker)
        var low: Double? = nil, isLiq = false
        if let s = i.stop { low = close(fq, fe, flocked, at: s, fee: i.taker) }
        else if let l = i.liquidation, l > 0 { low = close(fq, fe, flocked, at: l, fee: i.taker); isLiq = true }
        let last = tps.last?.price
        let high = last.map { walk(fq, fe, flocked, to: $0, restFee: i.maker) }
        let highNow = last.map { q > 0 ? walk(q, e, locked, to: $0, restFee: i.maker) : 0 }
        // The last take-profit is the right end itself.
        let marks = tps.dropLast().map { walk(fq, fe, flocked, to: $0.price, restFee: i.taker) }
        var oneR: Double? = nil
        if let s = i.stop {
            if let p = i.plannedRisk, p > 0 { oneR = p }
            else {
                // Risk of what is in play now: all entries filled, stop hit, without what was already settled.
                let risk = -(fq * dir * (s - fe) - fq * s * i.taker - fq * fe * i.maker)
                oneR = risk > 0 ? risk : nil
            }
        }
        let avgTP = tps.isEmpty ? nil : tps.reduce(0) { $0 + $1.price * $1.fraction } / max(tps.reduce(0) { $0 + $1.fraction }, 1e-12)
        return TradeMeter(now: now, low: low, lowIsLiquidation: isLiq, high: high, highNow: highNow, openEnded: !tps.isEmpty && cover < 0.995,
                          marks: marks, oneR: oneR, averageTP: avgTP, plannedEntry: fe, hasPosition: abs(i.size) > 1e-12,
                          entriesFilled: filledEntries, entriesTotal: filledEntries + i.restingEntries.count)
    }
}
