import Foundation

/// Changing the take-profits of a trade after it was placed. Before the entry fills, Grip keeps the new ladder and
/// places it at the fill (a take-profit linked to the entry is cancelled). With a position, the old take-profits are
/// cancelled and the new ones placed. The levels may cover less than the whole position: the rest runs until the stop.
public enum TPEditor {
    public struct Edit: Equatable, Sendable {
        public var actions: [KeeperAction]
        public var next: ManagedTrade
    }

    /// Orders that count as take-profits: reduce-only limits and TP triggers.
    public static func takeProfitOrders(_ orders: [OpenOrder], isLong: Bool) -> [OpenOrder] {
        orders.filter { $0.reduceOnly && (!$0.isTrigger || $0.tpsl == .tp) && $0.isBuy != isLong }
    }

    /// Entries that still wait to fill, on the side of the trade.
    public static func restingEntries(_ orders: [OpenOrder], isLong: Bool) -> [OpenOrder] {
        orders.filter { !$0.isTrigger && !$0.reduceOnly && $0.isBuy == isLong }
    }

    /// Size the shares refer to: the position, or before the fill the resting entries together.
    public static func baseSize(isLong: Bool, position: Position?, orders: [OpenOrder]) -> Double {
        let size = positionSize(isLong: isLong, position)
        return size > 1e-12 ? size : restingEntries(orders, isLong: isLong).reduce(0) { $0 + $1.size }
    }

    /// The take-profits as they are now, nearest first, each with its share of the position (or of the entries).
    public static func current(_ m: ManagedTrade?, isLong: Bool, position: Position?, orders: [OpenOrder]) -> [TPTarget] {
        let size = positionSize(isLong: isLong, position)
        var list: [TPTarget]
        if size < 1e-12, let tps = m?.tps, tps.isLong == isLong {
            list = zip(tps.prices, tps.fractions).map { TPTarget(price: $0, fraction: $1) }
        } else {
            let base = baseSize(isLong: isLong, position: position, orders: orders)
            list = takeProfitOrders(orders, isLong: isLong).map {
                TPTarget(price: $0.displayPx, fraction: base > 0 && $0.size > 0 ? min($0.size / base, 1) : 1)
            }
        }
        return sorted(list, isLong: isLong)
    }

    /// Share of the position the levels close together (0...1).
    public static func coverage(_ levels: [TPTarget]) -> Double {
        min(max(levels.reduce(0) { $0 + $1.fraction }, 0), 1)
    }

    /// What to do to get `levels` in place.
    public static func apply(_ levels: [TPTarget], to m: ManagedTrade?, isLong: Bool, position: Position?, orders: [OpenOrder], szDecimals: Int) -> Edit {
        let size = positionSize(isLong: isLong, position)
        let wanted = sorted(levels.filter { $0.fraction > 1e-9 && $0.price > 0 }, isLong: isLong)
        var next = m ?? ManagedTrade(isLong: isLong,
                                     stop: orders.first { $0.isTrigger && $0.tpsl == .sl }?.displayPx,
                                     entryOids: restingEntries(orders, isLong: isLong).map(\.oid),
                                     lastSize: size)
        next.isLong = isLong
        let old = takeProfitOrders(orders, isLong: isLong)
        // One take-profit for everything, linked to a waiting entry: just move it, so it stays on the exchange.
        let base = baseSize(isLong: isLong, position: position, orders: orders)
        if size < 1e-12, wanted.count == 1, wanted[0].fraction >= 0.995, old.count == 1, old[0].isTrigger, abs(old[0].size - base) < 1e-12 {
            next.tps = nil
            let same = abs(old[0].displayPx - wanted[0].price) < 1e-12
            return Edit(actions: same ? [] : [.resizeTakeProfit(oid: old[0].oid, size: old[0].size, price: wanted[0].price, isTrigger: true)], next: next)
        }
        var actions: [KeeperAction] = old.map { .cancel(oid: $0.oid) }
        if size < 1e-12 {
            next.tps = wanted.isEmpty ? nil : PendingTPs(isLong: isLong, prices: wanted.map(\.price), fractions: wanted.map(\.fraction))
        } else {
            next.tps = nil
            let ladder = TradeKeeper.split(total: HLFormat.roundSize(size, szDecimals: szDecimals), prices: wanted.map(\.price),
                                           fractions: wanted.map(\.fraction), szDecimals: szDecimals)
            if !ladder.isEmpty { actions.append(.placeTakeProfits(ladder)) }
        }
        return Edit(actions: actions, next: next)
    }

    private static func positionSize(isLong: Bool, _ position: Position?) -> Double {
        position.map { $0.isLong == isLong ? abs($0.size) : 0 } ?? 0
    }

    private static func sorted(_ list: [TPTarget], isLong: Bool) -> [TPTarget] {
        list.sorted { isLong ? $0.price < $1.price : $0.price > $1.price }
    }
}
