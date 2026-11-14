#if os(macOS)
import SwiftUI
import AppKit
import GripCore

/// Everything the order calculation depends on.
struct PlanKey: Equatable {
    var ticket: Ticket
    var riskSizing: Bool
    var riskPercent: Double
    var price: Double
    var equity: Double
    var free: Double
    var position: Position?
    var tpOrders: [String]
    var fees: [Double]
    var coin: String
}

// MARK: - Ticket: building, editing and placing an order (one or more entries, add to / reduce a position)

extension AppState {
    /// Calculation for the current ticket (cached: it is asked for by every chart label on every redraw).
    var plan: Plan? {
        guard let t = ticket else { return nil }
        let key = PlanKey(ticket: t, riskSizing: t.riskSized, riskPercent: riskPercent, price: price,
                          equity: sizingEquity, free: account.withdrawable, position: position, tpOrders: existingTPOrders.map { "\($0.oid)-\($0.size)" },
                          fees: [feeRates.taker, feeRates.maker, Double(maxPositions)], coin: coin)
        if key == planCacheKey { return planCache }
        planCacheKey = key
        planCache = plan(for: t, riskSizing: t.riskSized)
        return planCache
    }

    /// Size-weighted entry of the ticket (market entry at the current price).
    func averageEntry(_ t: Ticket) -> Double {
        let total = t.entries.reduce(0) { $0 + max($1.pct, 0) }
        guard total > 0 else { return t.isMarket ? price : t.entry }
        return t.entries.enumerated().reduce(0) { acc, e in
            acc + (t.isMarket && e.offset == 0 ? price : e.element.price) * max(e.element.pct, 0) / total
        }
    }

    /// Leverage used for the ticket: chosen, else the position's, else the Bedrag default.
    func ticketLeverage(_ t: Ticket) -> Int { t.leverage ?? position?.leverage ?? amountLev }

    /// Size in coins from what was typed (Bedrag tab, adding, reducing).
    func derivedSize(_ t: Ticket) -> Double {
        let avg = averageEntry(t)
        guard avg > 0 else { return 0 }
        var size: Double
        switch t.amountUnit {
        case .margin: size = t.amount * Double(ticketLeverage(t)) / avg
        case .notional: size = t.amount / avg
        case .coin: size = t.amount
        }
        if t.reduceOnly, let pos = position { size = min(size, abs(pos.size)) }
        return max(size, 0)
    }

    /// Converts a size in coins to the ticket's unit (for switching units without changing the size).
    func amount(forSize size: Double, unit: AmountUnit, _ t: Ticket) -> Double {
        let avg = averageEntry(t)
        switch unit {
        case .margin: return size * avg / Double(max(ticketLeverage(t), 1))
        case .notional: return size * avg
        case .coin: return size
        }
    }

    func plan(for t: Ticket, riskSizing: Bool) -> Plan? {
        guard let a = asset else { return nil }
        var entries = t.entries.map { TPTarget(price: $0.price, fraction: max($0.pct, 0) / 100) }
        if t.isMarket, !entries.isEmpty { entries[0].price = price }
        let sizedByRisk = riskSizing && !t.reduceOnly
        var input = PlanInput(accountValue: sizingEquity, riskPercent: sizedByRisk ? riskPercent : nil, isLong: t.isLong,
                              entries: entries, stopLoss: t.useStopLoss && !t.reduceOnly ? t.stopLoss : nil,
                              maxLeverage: a.maxLeverage, szDecimals: a.szDecimals)
        input.takerFeeRate = feeRates.taker
        input.entryFeeRate = t.isMarket && t.entries.count == 1 ? feeRates.taker : feeRates.maker
        input.takeProfits = ticketTPTargets(t)
        if !sizedByRisk { input.sizeOverride = derivedSize(t) }
        input.leverageOverride = t.leverage
        input.availableMargin = isExampleEquity ? nil : account.withdrawable
        // Budget: a new position fits in one slot (auto leverage goes up instead).
        if budgetActive && position == nil && !t.reduceOnly { input.availableMargin = min(input.availableMargin ?? slotMargin, slotMargin) }
        input.isCross = position?.isCross ?? (useCrossMargin && !a.onlyIsolated)
        if let pos = position {
            input.existing = ExistingPosition(size: pos.size, entryPx: pos.entryPx, isLong: pos.isLong, leverage: pos.leverage)
        }
        return OrderPlanner.plan(input)
    }

    /// Take-profit orders already on the position (reduce-only limits and TP triggers).
    var existingTPOrders: [OpenOrder] {
        coinOrders.filter { $0.reduceOnly && (!$0.isTrigger || $0.tpsl == .tp) }
    }

    var existingStopOrder: OpenOrder? { coinOrders.first { $0.isTrigger && $0.tpsl == .sl } }

    private func ticketTPTargets(_ t: Ticket) -> [TPTarget] {
        if !t.tps.isEmpty { return t.tps.map { TPTarget(price: $0.price, fraction: $0.pct / 100) } }
        guard let pos = position, pos.isLong == t.isLong else { return [] }
        let total = abs(pos.size)
        return existingTPOrders.map { TPTarget(price: $0.displayPx, fraction: $0.size > 0 ? min($0.size / total, 1) : 1) }
    }

    // MARK: New ticket

    /// New order. Lines start inside what is visible on the chart. Risico: sized by your max loss.
    /// Bedrag / Positie: sized by the amount you type. With an open position in the same direction this adds to it;
    /// in the other direction it reduces it (Positie tab) or asks first.
    func newTicket(long: Bool, entry atPrice: Double? = nil) {
        let p = price
        guard p > 0 else { return }
        let pos = position
        if let pos, pos.isLong != long, panelMode != .position {
            let side = pos.isLong ? "long" : "short"
            pendingConfirm = ConfirmRequest(
                title: "Je zit \(side) in \(coin)",
                message: "Hyperliquid heeft één positie per munt. Een \(long ? "long" : "short")-order opent geen aparte trade, maar maakt je \(side) kleiner.\nVerkleinen of sluiten doe je in het tabblad Positie.",
                confirmTitle: "Naar Positie", destructive: false) { [weak self] in
                    self?.panelMode = .position
                }
            return
        }
        if panelMode == .position && pos == nil { panelMode = .risk }
        let r = { (v: Double) in HLFormat.roundPrice(v, szDecimals: self.szDecimals) }
        var vis = (lo: p * 0.98, hi: p * 1.02)
        if let v = chartCanvas?.visiblePriceRange, v.lo > 0, v.hi > v.lo, v.lo < p, v.hi > p { vis = v }
        let span = max(vis.hi - vis.lo, p * 0.002)
        let dir: Double = long ? 1 : -1
        let reducing = pos.map { $0.isLong != long } ?? false
        let adding = pos.map { $0.isLong == long } ?? false
        let entry = atPrice ?? (p - dir * span * (reducing ? -0.06 : 0.04))
        let risk = span * 0.08

        var t = Ticket(isLong: long, entries: [TPLevel(price: r(entry), pct: 100)], stopLoss: r(entry - dir * risk), tps: [], isMarket: false)
        t.riskSized = panelMode == .risk && !reducing
        t.amountUnit = amountUnit
        t.amount = amountValue
        if reducing, let pos {
            t.reduceOnly = true
            t.useStopLoss = false
            t.amountUnit = .coin
            t.amount = HLFormat.roundSize(abs(pos.size) * 0.5, szDecimals: szDecimals)
        } else if t.riskSized {
            if adding, let sl = existingStopOrder { t.stopLoss = sl.displayPx }
            if !(adding && !existingTPOrders.isEmpty) {
                let split = lastSplit.isEmpty ? [100] : lastSplit
                let edge = long ? vis.hi - span * 0.04 : vis.lo + span * 0.04
                for (i, pct) in split.enumerated() {
                    var px = entry + dir * risk * (1.5 + Double(i))
                    if long ? px > edge : px < edge { px = entry + (edge - entry) * Double(i + 1) / Double(split.count) }
                    t.tps.append(TPLevel(price: r(px), pct: pct))
                }
                t.moveSLToBreakEven = split.count > 1
            }
        } else {
            // Bedrag / adding from Positie: last used amount, leverage, stop and TP.
            t.leverage = pos?.leverage ?? amountLev
            if adding {
                if let sl = existingStopOrder { t.stopLoss = sl.displayPx; t.useStopLoss = true } else { t.useStopLoss = false }
            } else {
                t.useStopLoss = amountUseStop
                t.stopLoss = r(entry * (1 - dir * amountSLPct / 100))
                if amountUseTP { t.tps = [TPLevel(price: r(entry * (1 + dir * amountTPPct / 100)), pct: 100)] }
            }
        }
        ticket = t
        tab = .trade
    }

    func panelModeChanged(_ old: PanelMode) {
        guard var t = ticket else { return }
        switch panelMode {
        case .risk:
            if t.reduceOnly { ticket = nil; return }
            t.riskSized = true
            t.useStopLoss = true
        case .amount:
            if t.reduceOnly { ticket = nil; return }
            if t.riskSized {
                // Keep the size it had, now as an amount you can change.
                let size = plan(for: t, riskSizing: true)?.size ?? 0
                t.riskSized = false
                t.leverage = t.leverage ?? plan(for: t, riskSizing: true)?.leverage ?? amountLev
                t.amount = amount(forSize: size, unit: t.amountUnit, t)
            }
        case .position:
            break
        }
        ticket = t
    }

    /// Positie tab → "Op prijs…": a limit order that reduces the position, shown in the chart.
    func startReduce(fraction: Double) {
        guard let pos = position else { return }
        panelMode = .position
        newTicket(long: !pos.isLong)
        ticket?.amount = HLFormat.roundSize(abs(pos.size) * fraction, szDecimals: szDecimals)
    }

    // MARK: Editing (panel and chart)

    func setTicketRisk(_ pct: Double) {
        riskPercent = min(max(pct, 0.05), 10)
    }

    /// Amount as typed, in the ticket's unit.
    func setTicketAmount(_ v: Double) {
        guard var t = ticket else { return }
        t.amount = max(v, 0)
        if t.reduceOnly, let pos = position, t.amountUnit == .coin { t.amount = min(t.amount, abs(pos.size)) }
        ticket = t
        if panelMode == .amount && !t.reduceOnly { amountValue = t.amount; amountUnit = t.amountUnit }
    }

    /// Next unit (marge → positie → munten), keeping the same size.
    func cycleAmountUnit() {
        guard var t = ticket else { return }
        let size = derivedSize(t)
        t.amountUnit = t.amountUnit.next
        t.amount = amount(forSize: size, unit: t.amountUnit, t)
        ticket = t
        if panelMode == .amount && !t.reduceOnly { amountUnit = t.amountUnit; amountValue = t.amount }
    }

    func setTicketLeverage(_ lev: Int?) {
        ticket?.leverage = lev.map { min(max($0, 1), asset?.maxLeverage ?? 50) }
        if panelMode == .amount, let l = ticket?.leverage { amountLev = l }
    }

    /// Stop price from the panel; remembers the distance as the Bedrag default.
    func setTicketStop(_ px: Double) {
        guard var t = ticket else { return }
        t.stopLoss = roundToTick(px)
        t.useStopLoss = true
        ticket = t
        let e = averageEntry(t)
        if panelMode == .amount, e > 0 { amountSLPct = abs(e - t.stopLoss) / e * 100 }
    }

    func setTicketTP(_ i: Int, _ px: Double) {
        guard var t = ticket, t.tps.indices.contains(i) else { return }
        t.tps[i].price = roundToTick(px)
        ticket = t
        let e = averageEntry(t)
        if panelMode == .amount, i == 0, e > 0 { amountTPPct = abs(t.tps[0].price - e) / e * 100 }
    }

    func setUseStop(_ on: Bool) {
        ticket?.useStopLoss = on
        if panelMode == .amount { amountUseStop = on }
    }

    func setUseTP(_ on: Bool) {
        guard var t = ticket else { return }
        if on && t.tps.isEmpty {
            let e = averageEntry(t)
            let dir: Double = t.isLong ? 1 : -1
            t.tps = [TPLevel(price: roundToTick(e * (1 + dir * amountTPPct / 100)), pct: 100)]
        } else if !on {
            t.tps = []
        }
        ticket = t
        if panelMode == .amount { amountUseTP = on }
    }

    func roundToTick(_ p: Double) -> Double {
        let t = priceTick
        return HLFormat.roundPrice((p / t).rounded() * t, szDecimals: szDecimals)
    }

    // Entries

    func addTicketEntry(at px: Double? = nil) {
        guard var t = ticket, t.entries.count < 5 else { return }
        let dir: Double = t.isLong ? 1 : -1
        let step = t.useStopLoss && !t.reduceOnly ? max(abs(t.entry - t.stopLoss) / 3, priceTick * 4) : max(price * 0.003, priceTick * 4)
        let last = t.entries.last?.price ?? price
        // Buying: extra entries lower; selling: higher.
        t.entries.append(TPLevel(price: roundToTick(px ?? (last - dir * step)), pct: 0))
        t.entries = applySplit(defaultSplit(t.entries.count), to: t.entries)
        ticket = t
    }

    func removeTicketEntry(_ i: Int) {
        guard var t = ticket, t.entries.indices.contains(i) else { return }
        guard t.entries.count > 1 else { ticket = nil; return }
        let removed = t.entries.remove(at: i)
        t.entries[t.entries.count - 1].pct += removed.pct
        ticket = t
    }

    func setEntryPct(_ i: Int, _ value: Double) { setPct(\.entries, i, value) }
    func applyEntrySplit(_ parts: [Double]) { if var t = ticket { t.entries = applySplit(parts, to: t.entries); ticket = t } }

    // Take-profits

    func addTicketTP(at px: Double? = nil) {
        guard var t = ticket, t.tps.count < 5 else { return }
        let dir: Double = t.isLong ? 1 : -1
        let risk = t.useStopLoss ? abs(t.entry - t.stopLoss) : price * 0.005
        let last = t.tps.last?.price ?? t.entry
        t.tps.append(TPLevel(price: roundToTick(px ?? (last + dir * max(risk, priceTick * 4))), pct: 0))
        let n = t.tps.count
        t.tps = applySplit(lastSplit.count == n ? lastSplit : defaultSplit(n), to: t.tps)
        ticket = t
        lastSplit = t.tps.map(\.pct)
    }

    func removeTicketTP(_ i: Int) {
        guard var t = ticket, t.tps.indices.contains(i) else { return }
        let removed = t.tps.remove(at: i)
        if !t.tps.isEmpty { t.tps[t.tps.count - 1].pct += removed.pct; lastSplit = t.tps.map(\.pct) }
        if t.tps.count < 2 { t.moveSLToBreakEven = false }
        ticket = t
    }

    func setTPPct(_ i: Int, _ value: Double) {
        setPct(\.tps, i, value)
        if let t = ticket { lastSplit = t.tps.map(\.pct) }
    }

    func applySplitPreset(_ parts: [Double]) {
        guard var t = ticket else { return }
        t.tps = applySplit(parts, to: t.tps)
        ticket = t
        lastSplit = t.tps.map(\.pct)
    }

    func defaultSplit(_ n: Int) -> [Double] { Array(repeating: (100 / Double(max(n, 1)) / 5).rounded(.down) * 5, count: n) }

    /// Sets one level's share; the last level (or the one before it) absorbs the difference so the total stays 100%.
    private func setPct(_ kp: WritableKeyPath<Ticket, [TPLevel]>, _ i: Int, _ value: Double) {
        guard var t = ticket else { return }
        var lv = t[keyPath: kp]
        guard lv.indices.contains(i), lv.count > 1 else { return }
        lv[i].pct = min(max((value / 5).rounded() * 5, 5), 100 - 5 * Double(lv.count - 1))
        let k = i == lv.count - 1 ? lv.count - 2 : lv.count - 1
        let rest = 100 - lv.reduce(0) { $0 + $1.pct }
        lv[k].pct = max(5, lv[k].pct + rest)
        t[keyPath: kp] = lv
        ticket = t
    }

    func applySplit(_ parts: [Double], to levels: [TPLevel]) -> [TPLevel] {
        var out = levels
        let n = out.count
        guard n > 0 else { return out }
        var p = Array(parts.prefix(n))
        while p.count < n { p.append(5) }
        p[n - 1] += 100 - p.reduce(0, +)
        for i in 0..<n { out[i].pct = p[i] }
        return out
    }

    // MARK: Placing

    /// Asks for confirmation first when part of it is a market order (setting).
    func requestPlaceTicket() {
        guard let t = ticket, let pl = plan else { return }
        guard t.isMarket && confirmMarketOrders else { Task { await placeTicket() }; return }
        let side = t.isLong ? "long" : "short"
        let what = t.reduceOnly ? "Verkleinen (market)" : (pl.isAdd ? "Market bijkopen (\(side))" : "Market \(side) openen")
        var msg = "\(fmt.size(pl.entrySizes.first ?? 0, coin: coin, decimals: szDecimals)) · ≈ \(Fmt.price(price)) · \(t.leverage ?? pl.leverage)×"
        if let risk = pl.riskUsd { msg += "\nRisico tot je stop: \(fmt.usd(-risk, decimals: 2))\(pl.isAdd ? " voor de hele positie" : "")" }
        if let r = pl.reducePnl { msg += "\nResultaat van dit deel ≈ \(fmt.signedUsd(r, decimals: 2))" }
        pendingConfirm = ConfirmRequest(title: what + "?", message: msg, confirmTitle: what, destructive: t.reduceOnly) { [weak self] in
            Task { await self?.placeTicket() }
        }
    }

    func placeTicket() async {
        guard let t = ticket, let a = asset, let pl = plan else { return }
        guard pl.size > 0 else { toast("Vul een grootte in.", .error); return }
        guard hasAccount else { toast("Koppel eerst een account (⇧⌘A), of zet de oefenmodus aan.", .error); return }
        for (k, s) in pl.entrySizes.enumerated() where s > 0 {
            let px = t.isMarket && k == 0 ? price : t.entries[k].price
            if s * px < 10 && !t.reduceOnly {
                toast(t.entries.count > 1 ? "E\(k + 1) is kleiner dan $10, het minimum van Hyperliquid." : "Hyperliquid vereist minimaal $10 per order.", .error)
                return
            }
        }
        busy = true
        defer { busy = false }
        let c = coin
        let pos = position
        do {
            let isBuy = t.isLong
            if !t.reduceOnly {
                let lev = min(max(t.leverage ?? pl.leverage, 1), a.maxLeverage)
                if let pos {
                    if lev != pos.leverage { try await execLeverage(a, isCross: pos.isCross, leverage: lev) }
                } else {
                    try await execLeverage(a, isCross: useCrossMargin && !a.onlyIsolated, leverage: lev)
                }
            }
            var reqs: [OrderRequest] = []
            for (k, lvl) in t.entries.enumerated() {
                let sz = pl.entrySizes.indices.contains(k) ? pl.entrySizes[k] : 0
                guard sz > 0 else { continue }
                let market = t.isMarket && k == 0
                let px = market ? HLFormat.slippagePrice(price, isBuy: isBuy, slippage: slippagePercent / 100, szDecimals: a.szDecimals)
                                : HLFormat.roundPrice(lvl.price, szDecimals: a.szDecimals)
                reqs.append(OrderRequest(asset: a, isBuy: isBuy, size: sz, limitPx: px, reduceOnly: t.reduceOnly, kind: .limit(tif: market ? "Ioc" : "Gtc")))
            }
            let entryCount = reqs.count

            if t.reduceOnly {
                try throwIfRejected(try await execOrders(reqs))
                toast("Verkleinorder\(entryCount > 1 ? "s" : "") geplaatst: \(fmt.size(pl.size, coin: c, decimals: a.szDecimals))", .success)
                ticket = nil
                await refreshAccount()
                await refreshHistory()
                return
            }

            let stop = t.useStopLoss ? HLFormat.roundPrice(t.stopLoss, szDecimals: a.szDecimals) : nil
            let avg = pl.after.avgEntry
            let ladder = t.tps.filter { isBuy ? $0.price > avg : $0.price < avg }
            // A single fresh entry goes in one go with its stop and (one) take-profit linked to it, so you see them
            // on Hyperliquid straight away. Everything else Grip keeps in line itself after the fills.
            let attachTP = pos == nil && entryCount == 1 && ladder.count == 1 && pl.size * ladder[0].price >= TradeKeeper.minOrderValue
            let simple = pos == nil && entryCount == 1 && (stop != nil || attachTP)
            if simple, let stop {
                reqs.append(OrderRequest(asset: a, isBuy: !isBuy, size: pl.size, limitPx: stop, reduceOnly: true,
                                         kind: .trigger(triggerPx: stop, isMarket: true, tpsl: .sl)))
            }
            if simple && attachTP {
                let tp = HLFormat.roundPrice(ladder[0].price, szDecimals: a.szDecimals)
                // Trigger with a limit price: rests as a maker order once triggered.
                reqs.append(OrderRequest(asset: a, isBuy: !isBuy, size: pl.size, limitPx: tp, reduceOnly: true,
                                         kind: .trigger(triggerPx: tp, isMarket: false, tpsl: .tp)))
            }
            let statuses = try await execOrders(reqs, grouping: simple ? "normalTpsl" : "na")
            let rejected = statuses.compactMap { if case .error(let e) = $0 { return e } else { return nil } }

            // From here Grip keeps stop and take-profits in line with the position.
            var m = managed[c] ?? ManagedTrade(isLong: isBuy, lastSize: 0)
            m.isLong = isBuy
            m.lastSize = abs(pos?.size ?? 0)
            if let stop { m.stop = stop }
            for st in statuses.prefix(entryCount) { if case .resting(let oid) = st { m.entryOids.append(oid); orderKinds[oid] = .limit } }
            if !ladder.isEmpty && !(simple && attachTP) {
                let total = max(ladder.reduce(0) { $0 + $1.pct }, 1)
                // Placed by the keeper at the first fill; when adding, this new ladder replaces the old take-profits.
                m.tps = PendingTPs(entryOid: 0, isLong: isBuy, prices: ladder.map(\.price), fractions: ladder.map { $0.pct / total })
            }
            if t.moveSLToBreakEven && ladder.count > 1 { breakEvenAfterTP.insert(c) } else if pos == nil { breakEvenAfterTP.remove(c) }
            managed[c] = m

            // Adding with a moved stop: move the position's stop now.
            if let pos, let stop {
                if let sl = existingStopOrder {
                    if abs(sl.displayPx - stop) > priceTick / 2 {
                        try? await execModify(oid: sl.oid, OrderRequest(asset: a, isBuy: !pos.isLong, size: sl.size > 0 ? sl.size : abs(pos.size), limitPx: stop,
                                                                       reduceOnly: true, kind: .trigger(triggerPx: stop, isMarket: true, tpsl: .sl)))
                    }
                } else {
                    _ = try? await execOrders([OrderRequest(asset: a, isBuy: !pos.isLong, size: abs(pos.size), limitPx: stop, reduceOnly: true,
                                                            kind: .trigger(triggerPx: stop, isMarket: true, tpsl: .sl))])
                }
            }

            if pos == nil, let stop {
                plans.append(TradePlan(coin: c, isLong: isBuy, entry: pl.avgEntry, stopLoss: stop, takeProfit: t.takeProfit,
                                       riskUsd: pl.riskUsd ?? 0, riskPercent: riskPercent))
                if !isDemoVideo { store.save(plans, to: "plans") }
            }

            let filled = statuses.prefix(entryCount).contains { if case .filled = $0 { return true } else { return false } }
            let resting = statuses.prefix(entryCount).filter { if case .resting = $0 { return true } else { return false } }.count
            let side = isBuy ? "long" : "short"
            if resting > 0, m.tps != nil {
                toast("Take-profits worden geplaatst zodra je entry gevuld is (zie de lichte lijnen in de chart).", .info)
            }
            if resting > 0 {
                let what = pl.isAdd ? "Bijkoop-order\(resting > 1 ? "s" : "")" : (resting > 1 ? "\(resting) entries" : "Limit \(side)")
                toast("\(what) geplaatst · \(t.leverage ?? pl.leverage)×", .success)
                notify(.orderPlaced, "\(what) geplaatst", "\(c) \(side) · \(fmt.size(pl.size, coin: c, decimals: a.szDecimals))")
            } else if !filled {
                toast("Order verstuurd.", .success)
            }
            if !rejected.isEmpty {
                let msg = Array(Set(rejected)).joined(separator: " · ")
                toast("Niet alles geplaatst: \(msg)", .error)
                notify(.orderProblem, "Order deels geweigerd", msg)
            }
            ticket = nil
            await refreshAccount()
            if filled { await refreshHistory() }
        } catch {
            toast(error.localizedDescription, .error)
            notify(.orderProblem, "Order niet geplaatst", error.localizedDescription)
        }
    }

    // MARK: Keeping stop and take-profits in line

    /// Called after every account refresh (live and practice). The keeper (GripCore, tested against the practice
    /// exchange) decides; this executes: resize or place the stop, place or scale take-profits, cancel unfilled entries.
    func reconcileManaged() async {
        guard !managed.isEmpty else { return }
        if reconciling { reconcileAgain = true; return }
        reconciling = true
        defer { reconciling = false }
        repeat {
            reconcileAgain = false
            await reconcileOnce()
        } while reconcileAgain
    }

    private func reconcileOnce() async {
        for (c, m) in managed {
            guard let a = assets.first(where: { $0.name == c }) else { continue }
            let step = TradeKeeper.step(m, position: account.position(for: c), orders: account.orders(for: c), szDecimals: a.szDecimals)
            var ok = true
            for action in step.actions {
                do {
                    try await execute(action, coin: c, asset: a, isLong: m.isLong)
                } catch {
                    ok = false
                    toast("\(describe(action)) mislukt: \(error.localizedDescription)", .error)
                    notify(.orderProblem, "\(describe(action)) mislukt", "\(c): \(error.localizedDescription)")
                }
            }
            if step.cancelledEntries > 0 {
                toast("\(c)-trade gesloten: \(step.cancelledEntries) niet-gevulde entr\(step.cancelledEntries > 1 ? "ies" : "y") geannuleerd", .info)
            }
            if ok {
                managed[c] = step.next
                if step.next == nil { breakEvenAfterTP.remove(c) }
            } else {
                // Try again at the next refresh, but not forever.
                var retry = m
                retry.failures += 1
                if retry.failures >= 3 {
                    managed[c] = step.next
                    notify(.orderProblem, "Grip stopt met bijwerken van \(c)", "Controleer je stop-loss en take-profits zelf.")
                } else {
                    managed[c] = retry
                }
            }
            if !step.actions.isEmpty {
                if let fresh = try? await refreshedState() { account = fresh }
            }
        }
    }

    private func refreshedState() async throws -> AccountState {
        if paperMode { return paper.accountState(marks: marks(), assets: assets) }
        return try await client.accountState(user: accountAddress.trimmingCharacters(in: .whitespaces))
    }

    private func describe(_ a: KeeperAction) -> String {
        switch a {
        case .cancel: return "Entry annuleren"
        case .placeStop: return "Stop-loss plaatsen"
        case .resizeStop: return "Stop-loss bijwerken"
        case .placeTakeProfits: return "Take-profits plaatsen"
        case .resizeTakeProfit: return "Take-profit vergroten"
        }
    }

    private func execute(_ action: KeeperAction, coin c: String, asset a: AssetInfo, isLong: Bool) async throws {
        switch action {
        case .cancel(let oid):
            try await execCancel(a, oid: oid)
        case .placeStop(let size, let px):
            let st = try await execOrders([OrderRequest(asset: a, isBuy: !isLong, size: size, limitPx: px, reduceOnly: true,
                                                        kind: .trigger(triggerPx: px, isMarket: true, tpsl: .sl))])
            try throwIfRejected(st)
            toast("Stop-loss op \(Fmt.price(px)) voor de hele positie", .success)
        case .resizeStop(let oid, let size, let px):
            try await execModify(oid: oid, OrderRequest(asset: a, isBuy: !isLong, size: size, limitPx: px, reduceOnly: true,
                                                        kind: .trigger(triggerPx: px, isMarket: true, tpsl: .sl)))
        case .placeTakeProfits(let tps):
            let st = try await execOrders(tps.map { OrderRequest(asset: a, isBuy: !isLong, size: $0.size, limitPx: HLFormat.roundPrice($0.price, szDecimals: a.szDecimals),
                                                                 reduceOnly: true, kind: .limit(tif: "Gtc")) })
            for s in st { if case .resting(let oid) = s { orderKinds[oid] = .takeProfit } }
            try throwIfRejected(st)
            toast("\(tps.count) take-profit\(tps.count > 1 ? "s" : "") geplaatst", .success)
        case .resizeTakeProfit(let oid, let size, let px, let isTrigger):
            let isMarket = account.openOrders.first { $0.oid == oid }?.orderType.lowercased().contains("market") ?? false
            let kind: OrderKind = isTrigger ? .trigger(triggerPx: px, isMarket: isMarket, tpsl: .tp) : .limit(tif: "Gtc")
            try await execModify(oid: oid, OrderRequest(asset: a, isBuy: !isLong, size: size, limitPx: px, reduceOnly: true, kind: kind))
        }
    }

    /// Hyperliquid answers per order; only the first error used to be thrown. Report the rest too.
    func throwIfRejected(_ statuses: [OrderStatus]) throws {
        let errors = statuses.compactMap { if case .error(let e) = $0 { return e } else { return nil } }
        if !errors.isEmpty { throw HLError.exchange(Array(Set(errors)).joined(separator: " · ")) }
    }
}
#endif
