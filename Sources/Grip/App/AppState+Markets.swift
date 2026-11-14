#if os(macOS)
import SwiftUI
import GripCore

// MARK: - Market tabs, positions and orders across all markets

extension AppState {
    /// Tabs: the markets you opened, plus every market with a position or open order.
    var marketTabs: [String] {
        var tabs = openMarkets
        if !tabs.contains(coin) { tabs.append(coin) }
        for c in account.positions.map(\.coin) + account.openOrders.map(\.coin) where !tabs.contains(c) { tabs.append(c) }
        return tabs
    }

    /// A tab with a position or order stays open.
    func isPinned(_ c: String) -> Bool { account.position(for: c) != nil || !account.orders(for: c).isEmpty }

    func closeTab(_ c: String) {
        guard !isPinned(c) else { return }
        let tabs = marketTabs
        openMarkets.removeAll { $0 == c }
        stashedTickets[c] = nil
        if c == coin, let i = tabs.firstIndex(of: c) {
            let rest = tabs.filter { $0 != c }
            if !rest.isEmpty { coin = rest[min(i, rest.count - 1)] }
        }
    }

    func selectTab(offset: Int) {
        let tabs = marketTabs
        guard let i = tabs.firstIndex(of: coin), !tabs.isEmpty else { return }
        coin = tabs[(i + offset + tabs.count) % tabs.count]
    }

    func selectTab(number n: Int) {
        let tabs = marketTabs
        if n >= 1 && n <= tabs.count { coin = tabs[n - 1] }
    }

    func livePrice(_ c: String) -> Double? { c == coin && price > 0 ? price : (liveMids[c] ?? mids[c]) }

    /// Distance from the current price to an order, as a fraction (0.003 = 0.3%).
    func distance(_ o: OpenOrder) -> Double? {
        guard let p = livePrice(o.coin), p > 0 else { return nil }
        return abs(o.displayPx - p) / p
    }

    var ordersByDistance: [OpenOrder] {
        account.openOrders.sorted { (distance($0) ?? 1) < (distance($1) ?? 1) }
    }

    func nearestDistance(_ c: String) -> Double? {
        account.orders(for: c).compactMap { distance($0) }.min()
    }

    func stopOrder(_ c: String) -> OpenOrder? { account.orders(for: c).first { $0.isTrigger && $0.tpsl == .sl } }

    func takeProfits(_ c: String) -> [OpenOrder] { account.orders(for: c).filter { $0.reduceOnly && (!$0.isTrigger || $0.tpsl == .tp) } }

    func breakEven(for pos: Position) -> Double? {
        let o = analysis.open[pos.coin]
        return PositionMath.breakEven(entry: pos.entryPx, size: pos.size, feesPaid: o?.feesPaid ?? 0, realized: o?.realized ?? 0,
                                      funding: o?.funding ?? 0, takerRate: feeRates.taker)
    }

    /// Open the market and its Positie tab.
    func goToPosition(_ c: String) {
        coin = c
        panelMode = .position
        tab = .trade
    }

    // MARK: Reverse

    func requestReverse(coin c: String) {
        guard let pos = account.position(for: c) else { return }
        let side = pos.isLong ? "long" : "short", other = pos.isLong ? "short" : "long"
        let px = livePrice(c) ?? pos.entryPx
        pendingConfirm = ConfirmRequest(
            title: "\(c) omkeren naar \(other)?",
            message: "Sluit je \(side) van \(fmt.size(pos.size, coin: c, decimals: 4)) en opent een \(other) van dezelfde grootte (market, ≈ \(Fmt.price(px))).\nJe stop en take-profits vervallen; zet daarna een nieuwe stop.",
            confirmTitle: "Omkeren", destructive: true) { [weak self] in
                Task { await self?.reverse(coin: c) }
            }
    }

    func reverse(coin c: String) async {
        guard let pos = account.position(for: c), let a = assets.first(where: { $0.name == c }) else { return }
        busy = true
        defer { busy = false }
        do {
            for o in account.orders(for: c) where o.reduceOnly || o.isTrigger { try? await execCancel(a, oid: o.oid) }
            managed[c] = nil
            breakEvenAfterTP.remove(c)
            let isBuy = !pos.isLong
            let px = HLFormat.slippagePrice(livePrice(c) ?? pos.entryPx, isBuy: isBuy, slippage: slippagePercent / 100, szDecimals: a.szDecimals)
            let size = HLFormat.roundSize(abs(pos.size) * 2, szDecimals: a.szDecimals)
            let st = try await execOrders([OrderRequest(asset: a, isBuy: isBuy, size: size, limitPx: px, reduceOnly: false, kind: .limit(tif: "Ioc"))])
            try throwIfRejected(st)
            toast("\(c) omgekeerd naar \(isBuy ? "long" : "short"). Zet een nieuwe stop.", .success)
            goToPosition(c)
        } catch {
            toast("Omkeren mislukt: \(error.localizedDescription)", .error)
            notify(.orderProblem, "Omkeren mislukt", error.localizedDescription)
        }
        await refreshAccount()
        await refreshHistory()
    }
}
#endif
