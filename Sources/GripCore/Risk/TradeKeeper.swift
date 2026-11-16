import Foundation

/// Take-profit ladder still to be placed (prices + share of the position).
public struct PendingTPs: Codable, Equatable, Sendable {
    public var entryOid: Int64
    public var isLong: Bool
    public var prices: [Double]
    public var fractions: [Double]
    public init(entryOid: Int64 = 0, isLong: Bool, prices: [Double], fractions: [Double]) {
        self.entryOid = entryOid; self.isLong = isLong; self.prices = prices; self.fractions = fractions
    }
}

/// What Grip keeps in line for a trade it placed: one stop for the whole position, take-profits that grow with it,
/// and entries that never filled are cancelled when the position is closed.
public struct ManagedTrade: Codable, Equatable, Sendable {
    public var isLong: Bool
    public var stop: Double?
    public var entryOids: [Int64]
    /// Position size the last time everything was in line.
    public var lastSize: Double
    /// Take-profit ladder to place at the first fill.
    public var tps: PendingTPs?
    public var failures: Int = 0
    /// Risk of the whole trade as placed (positive): 1R in the chart and the position list.
    public var plannedRisk: Double?
    /// How many entries the trade was placed with (for ●○○ in the chart).
    public var entryCount: Int?
    /// Sized by max loss: moving an entry or the stop before the fill resizes the setup to the same risk.
    public var riskSized: Bool?
    /// Leverage the setup was placed with.
    public var leverage: Int?

    public init(isLong: Bool, stop: Double? = nil, entryOids: [Int64] = [], lastSize: Double, tps: PendingTPs? = nil) {
        self.isLong = isLong; self.stop = stop; self.entryOids = entryOids; self.lastSize = lastSize; self.tps = tps
    }
}

public struct TPOrder: Equatable, Sendable {
    public var price: Double
    public var size: Double
}

public enum KeeperAction: Equatable, Sendable {
    case cancel(oid: Int64)
    case placeStop(size: Double, price: Double)
    case resizeStop(oid: Int64, size: Double, price: Double)
    case placeTakeProfits([TPOrder])
    case resizeTakeProfit(oid: Int64, size: Double, price: Double, isTrigger: Bool)
}

public struct KeeperStep: Equatable, Sendable {
    public var actions: [KeeperAction]
    /// State to keep once the actions succeeded; nil = done with this trade.
    public var next: ManagedTrade?
    public var cancelledEntries: Int
}

public enum TradeKeeper {
    /// Hyperliquid's minimum order value.
    public static let minOrderValue = 10.0

    /// Sizes for a take-profit ladder. Levels under $10 are merged into the next one (the last takes the rest),
    /// so Hyperliquid does not reject them. Fractions that add up to less than 1 cover only that part of `total`
    /// (the rest runs until the stop); more than 1 is scaled down to the whole position.
    public static func split(total: Double, prices: [Double], fractions: [Double], szDecimals: Int, minValue: Double = minOrderValue) -> [TPOrder] {
        guard total > 0, !prices.isEmpty, prices.count == fractions.count else { return [] }
        let sum = max(fractions.reduce(0, +), 1e-12)
        let covered = sum < 0.999 ? HLFormat.roundSize(total * sum, szDecimals: szDecimals) : total
        return splitCovered(covered, prices: prices, fractions: fractions.map { $0 / sum }, szDecimals: szDecimals, minValue: minValue)
    }

    private static func splitCovered(_ total: Double, prices: [Double], fractions: [Double], szDecimals: Int, minValue: Double) -> [TPOrder] {
        guard total > 0 else { return [] }
        let sum = 1.0
        var out: [TPOrder] = []
        var left = HLFormat.roundSize(total, szDecimals: szDecimals)
        var carry = 0.0
        for (i, px) in prices.enumerated() {
            let isLast = i == prices.count - 1
            var sz = isLast ? left : HLFormat.roundSize(total * fractions[i] / sum + carry, szDecimals: szDecimals, down: true)
            sz = min(sz, left)
            if !isLast && (sz * px < minValue || sz <= 0) {
                carry += total * fractions[i] / sum
                continue
            }
            carry = 0
            guard sz > 0 else { continue }
            out.append(TPOrder(price: px, size: sz))
            left = HLFormat.roundSize(left - sz, szDecimals: szDecimals)
        }
        // The last level too small on its own: add it to the one before.
        if out.count > 1, let last = out.last, last.size * last.price < minValue {
            out.removeLast()
            out[out.count - 1].size = HLFormat.roundSize(out[out.count - 1].size + last.size, szDecimals: szDecimals)
        }
        return out
    }

    /// What to do now for one coin. `orders` are the open orders of that coin.
    public static func step(_ m: ManagedTrade, position: Position?, orders: [OpenOrder], szDecimals: Int) -> KeeperStep {
        let size = position.map { $0.isLong == m.isLong ? abs($0.size) : 0 } ?? 0
        let open = Set(orders.map(\.oid))
        var next = m
        next.entryOids = m.entryOids.filter { open.contains($0) }

        if size < 1e-12 {
            if m.lastSize > 1e-12 {
                // Closed (stop, last TP or by hand): cancel the entries that never filled.
                return KeeperStep(actions: next.entryOids.map { .cancel(oid: $0) }, next: nil, cancelledEntries: next.entryOids.count)
            }
            // Nothing filled yet; done when all entries are gone.
            return KeeperStep(actions: [], next: next.entryOids.isEmpty ? nil : next, cancelledEntries: 0)
        }

        var actions: [KeeperAction] = []
        let total = HLFormat.roundSize(size, szDecimals: szDecimals)
        // Whenever the size changed: one stop that covers the whole position (also after a fast move where an entry
        // filled and the stop was hit before Grip could resize it). Unchanged size: leave the stop to the user.
        // A ladder or an add brings one stop per entry (linked on the exchange, so the trade is protected while
        // Grip is closed). While entries still wait, those stops are left alone; once nothing waits, they are
        // merged into one stop for the whole position.
        let stops = orders.filter { $0.isTrigger && $0.tpsl == .sl && $0.reduceOnly }
        let sl = stops.first
        let changed = abs(size - m.lastSize) > 1e-12
        if !changed {
        } else if stops.count > 1 {
            if next.entryOids.isEmpty, let first = sl {
                for extra in stops.dropFirst() { actions.append(.cancel(oid: extra.oid)) }
                actions.append(.resizeStop(oid: first.oid, size: total, price: m.stop ?? first.displayPx))
            }
        } else if let sl {
            let px = m.stop ?? sl.displayPx
            if sl.size > 0 && (abs(sl.size - total) > 1e-12 || abs(sl.displayPx - px) > 1e-12) {
                actions.append(.resizeStop(oid: sl.oid, size: total, price: px))
            }
        } else if let px = m.stop {
            actions.append(.placeStop(size: total, price: px))
        }
        if size > m.lastSize + 1e-12 {
            // Take-profits: place the ladder at the first fill, scale existing ones after that.
            let existingTPs = orders.filter { $0.reduceOnly && (!$0.isTrigger || $0.tpsl == .tp) && $0.size > 0 }
            if let tps = m.tps {
                for o in existingTPs where m.lastSize > 0 { actions.append(.cancel(oid: o.oid)) }
                let ladder = split(total: total, prices: tps.prices, fractions: tps.fractions, szDecimals: szDecimals)
                if !ladder.isEmpty { actions.append(.placeTakeProfits(ladder)) }
                next.tps = nil
            } else if m.lastSize > 1e-12, !existingTPs.isEmpty {
                let factor = size / m.lastSize
                for o in existingTPs {
                    let sz = HLFormat.roundSize(o.size * factor, szDecimals: szDecimals)
                    if sz > o.size { actions.append(.resizeTakeProfit(oid: o.oid, size: sz, price: o.displayPx, isTrigger: o.isTrigger)) }
                }
            }
        }
        next.lastSize = size
        return KeeperStep(actions: actions, next: next, cancelledEntries: 0)
    }
}
