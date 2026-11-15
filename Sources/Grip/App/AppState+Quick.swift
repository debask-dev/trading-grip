#if os(macOS)
import SwiftUI
import GripCore

// MARK: - Snel: straight into a trade (side, market/limit, % of the account as margin), stop and TP afterwards

extension AppState {
    /// Margin for the Snel order: a share of the account value.
    var quickMargin: Double { sizingEquity * quickPct / 100 }

    /// Leverage for the Snel order: as chosen, never below the open position's, at most what the market allows.
    var quickLeverage: Int {
        min(max(fastLev, position?.leverage ?? 1, 1), asset?.maxLeverage ?? 50)
    }

    /// Why the Snel order cannot go (nil = it can).
    var quickBlocked: String? {
        if let pos = position, pos.isLong != quickLong {
            let side = pos.isLong ? "long" : "short"
            return T("Je zit \(side) in \(coin). Verkleinen of sluiten doe je in Positie.")
        }
        return nil
    }

    /// Keeps the order behind the Snel tab in line with its choices. It is an ordinary order without stop or TP,
    /// sized by margin, so the chart shows the limit line (draggable) and liquidation, and placing goes the usual way.
    func syncQuickTicket() {
        guard panelMode == .fast, price > 0, asset != nil else { return }
        let dir: Double = quickLong ? 1 : -1
        var t = ticket ?? Ticket(isLong: quickLong, entries: [], stopLoss: 0, tps: [], isMarket: quickMarket)
        if t.reduceOnly || t.riskSized || t.entries.count != 1 || t.isLong != quickLong {
            // New, or the side changed: the limit starts just inside the price.
            t.entries = [TPLevel(price: roundToTick(price * (1 - dir * 0.003)), pct: 100)]
        }
        t.isLong = quickLong
        t.isMarket = quickMarket
        t.reduceOnly = false
        t.riskSized = false
        t.useStopLoss = false
        t.stopLoss = roundToTick(t.entry * (1 - dir * 0.01))
        t.tps = []
        t.moveSLToBreakEven = false
        t.amountUnit = .margin
        t.amount = (quickMargin * 100).rounded(.down) / 100
        t.leverage = quickLeverage
        if ticket != t { ticket = t }
    }

    /// Places the Snel order straight away (no question). After a market fill Grip opens Positie for the stop and TPs.
    func placeQuick() {
        syncQuickTicket()
        if let why = quickBlocked { toast(why, .error); return }
        let market = quickMarket
        Task {
            await placeTicket()
            guard panelMode == .fast else { return }
            if market, position != nil {
                panelMode = .position
                toast(T("In trade. Zet nu je stop en take-profits."), .info)
            } else {
                syncQuickTicket()
            }
        }
    }
}
#endif
