#if os(macOS)
import AppKit
import GripCore

/// Words the chart draws itself, translated by the app.
struct ChartWords: Equatable {
    var noStop = "⚠ geen stop"
    var fromPrice = "vanaf koers"
}

/// The trade as a whole, for the bar in the position label, the Ø TP line and R in the position list.
struct ChartMeter: Equatable {
    var meter: TradeMeter
    var isLong: Bool
    var stop: Double?
    /// Waiting entries count as part of the trade (striped part of the bar).
    var restingEntries: Int
}

extension AppState {
    /// Side of the trade on a coin: the position, else a waiting entry, else what Grip keeps for it.
    func side(of c: String) -> Bool? {
        if let pos = account.position(for: c) { return pos.isLong }
        if let e = account.orders(for: c).first(where: { !$0.isTrigger && !$0.reduceOnly }) { return e.isBuy }
        return managed[c]?.isLong
    }

    /// The whole trade on a coin. `stop` / `takeProfits` replace the real ones while a line is dragged.
    func meter(for c: String, price px: Double? = nil, stop stopOverride: Double? = nil, takeProfits tpOverride: [TPTarget]? = nil) -> ChartMeter? {
        guard let isLong = side(of: c) else { return nil }
        let orders = account.orders(for: c)
        let pos = account.position(for: c).flatMap { $0.isLong == isLong ? $0 : nil }
        let resting = TPEditor.restingEntries(orders, isLong: isLong)
        guard pos != nil || !resting.isEmpty else { return nil }
        let o = analysis.open[c]
        let locked = pos != nil ? (o?.realized ?? 0) - (o?.feesPaid ?? 0) + (o?.funding ?? 0) : 0
        let stop = stopOverride ?? orders.first(where: { $0.isTrigger && $0.tpsl == .sl })?.displayPx ?? managed[c]?.stop
        let tps = tpOverride ?? TPEditor.current(managed[c], isLong: isLong, position: pos, orders: orders)
        let total = managed[c]?.entryCount ?? (resting.count + (pos != nil ? 1 : 0))
        let input = TradeMeter.Input(isLong: isLong, size: abs(pos?.size ?? 0), entry: pos?.entryPx ?? 0, locked: locked,
                                     restingEntries: resting.map { ($0.limitPx, $0.size) }, stop: stop, liquidation: pos?.liquidationPx,
                                     takeProfits: tps, plannedRisk: managed[c]?.plannedRisk, maker: feeRates.maker, taker: feeRates.taker)
        let now = px ?? livePrice(c) ?? pos?.entryPx ?? 0
        let m = TradeMeter.compute(input, price: now, filledEntries: max(total - resting.count, 0))
        return ChartMeter(meter: m, isLong: isLong, stop: stop, restingEntries: resting.count)
    }

    var chartMeter: ChartMeter? { meter(for: coin) }

    /// ½, ⅓, ¼ … for the share a take-profit or entry has; otherwise a percentage.
    func shareText(_ f: Double) -> String {
        let known: [(Double, String)] = [(1, "100%"), (0.5, "½"), (1.0 / 3, "⅓"), (2.0 / 3, "⅔"), (0.25, "¼"), (0.75, "¾"), (0.2, "⅕")]
        if let k = known.first(where: { abs($0.0 - f) < 0.005 }) { return k.1 }
        return "\(Int((f * 100).rounded()))%"
    }

    /// "+1,1R" style, or nil without a stop.
    func rText(_ m: TradeMeter, _ v: Double) -> String? {
        m.r(v).map { Fmt.number($0, decimals: 1) + "R" }
    }

    /// Text in the position label: side, size, filled entries, result now and R (or % of the account without a stop).
    func meterLabel(_ cm: ChartMeter, plan: Bool) -> String {
        let m = cm.meter
        let side = cm.isLong ? T("LONG") : T("SHORT")
        let dots = m.entriesTotal > 1 ? " " + String(repeating: "●", count: min(m.entriesFilled, m.entriesTotal)) + String(repeating: "○", count: max(m.entriesTotal - m.entriesFilled, 0)) : ""
        if plan {
            let size = account.orders(for: coin).filter { !$0.isTrigger && !$0.reduceOnly && $0.isBuy == cm.isLong }.reduce(0) { $0 + $1.size }
            let risk = m.low.map { "  ·  " + T("risico \(fmt.signedUsd($0))") } ?? ""
            return T("PLAN \(side) \(fmt.size(size, coin: coin, decimals: szDecimals))") + dots + risk
        }
        let size = abs(position?.size ?? 0)
        let tail = rText(m, m.now) ?? Fmt.percent(m.now / max(account.accountValue, 1), decimals: 1)
        return "\(side) \(fmt.size(size, coin: coin, decimals: szDecimals))\(dots)  \(fmt.signedUsd(m.now, decimals: 2)) · \(tail)"
    }

    /// Ø TP line: what the trade brings when all take-profits are hit.
    func averageTPLabel(_ cm: ChartMeter) -> String {
        let m = cm.meter
        guard let hi = m.high else { return "Ø TP" }
        let atLeast = m.openEnded ? "≥ " : ""
        if m.hasPosition && cm.restingEntries > 0, let now = m.highNow {
            return T("Ø TP · nu \(fmt.signedUsd(now)) · alles \(atLeast)\(fmt.signedUsd(hi))")
        }
        let r = rText(m, hi).map { " · " + $0 } ?? ""
        return T("Ø TP · alles \(atLeast)\(fmt.signedUsd(hi))") + r
    }
}
#endif
