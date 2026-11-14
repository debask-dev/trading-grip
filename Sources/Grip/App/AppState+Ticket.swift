#if os(macOS)
import SwiftUI
import AppKit
import GripCore

// MARK: - Ticket: building, editing and placing an order (one or more entries, add to / reduce a position)

extension AppState {
    /// Calculation for the current ticket.
    var plan: Plan? {
        guard let t = ticket else { return nil }
        return plan(for: t, riskSizing: panelMode != .manual)
    }

    func plan(for t: Ticket, riskSizing: Bool) -> Plan? {
        guard let a = asset else { return nil }
        var entries = t.entries.map { TPTarget(price: $0.price, fraction: max($0.pct, 0) / 100) }
        if t.isMarket, !entries.isEmpty { entries[0].price = price }
        var input = PlanInput(accountValue: sizingEquity, riskPercent: riskSizing ? riskPercent : nil, isLong: t.isLong,
                              entries: entries, stopLoss: t.useStopLoss && !t.reduceOnly ? t.stopLoss : nil,
                              maxLeverage: a.maxLeverage, szDecimals: a.szDecimals)
        input.takerFeeRate = feeRates.taker
        input.entryFeeRate = t.isMarket && t.entries.count == 1 ? feeRates.taker : feeRates.maker
        input.takeProfits = ticketTPTargets(t)
        if !riskSizing || t.lock == .size { input.sizeOverride = t.size ?? 0 }
        input.leverageOverride = t.leverage
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

    /// New order. Lines start inside what is visible on the chart. With an open position in the same direction
    /// this adds to it; in the other direction it reduces it (manual panel) or asks first.
    func newTicket(long: Bool, entry atPrice: Double? = nil) {
        let p = price
        guard p > 0 else { return }
        if panelMode == .quick { panelMode = .risk }
        if let pos = position, pos.isLong != long, panelMode != .manual {
            let side = pos.isLong ? "long" : "short"
            pendingConfirm = ConfirmRequest(
                title: "Je zit \(side) in \(coin)",
                message: "Hyperliquid heeft één positie per munt. Een \(long ? "long" : "short")-order opent geen aparte trade, maar maakt je \(side) kleiner.\nVerkleinen kan in het paneel Handmatig. Sluiten kan ook direct met de knoppen bij je positie.",
                confirmTitle: "Verkleinen in Handmatig", destructive: false) { [weak self] in
                    self?.panelMode = .manual
                    self?.newTicket(long: long, entry: atPrice)
                }
            return
        }
        let r = { (v: Double) in HLFormat.roundPrice(v, szDecimals: self.szDecimals) }
        var vis = (lo: p * 0.98, hi: p * 1.02)
        if let v = chartCanvas?.visiblePriceRange, v.lo > 0, v.hi > v.lo, v.lo < p, v.hi > p { vis = v }
        let span = max(vis.hi - vis.lo, p * 0.002)
        let dir: Double = long ? 1 : -1
        let pos = position
        let reducing = pos.map { $0.isLong != long } ?? false
        let adding = pos.map { $0.isLong == long } ?? false
        let entry = atPrice ?? (p - dir * span * (reducing ? -0.06 : 0.04))
        let risk = span * 0.08

        var t = Ticket(isLong: long, entries: [TPLevel(price: r(entry), pct: 100)], stopLoss: r(entry - dir * risk), tps: [], isMarket: false)
        if reducing, let pos {
            t.reduceOnly = true
            t.useStopLoss = false
            t.size = HLFormat.roundSize(abs(pos.size) * 0.5, szDecimals: szDecimals)
        } else {
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
        }
        if panelMode == .manual && !reducing {
            t.size = plan(for: t, riskSizing: true)?.size
            if let pos, adding { t.leverage = pos.leverage }
        }
        ticket = t
        tab = .trade
    }

    func panelModeChanged(_ old: PanelMode) {
        guard var t = ticket else { return }
        if panelMode == .manual { t.size = t.size ?? plan(for: t, riskSizing: true)?.size }
        if panelMode == .risk {
            if t.reduceOnly { ticket = nil; return }
            t.lock = .risk; t.size = nil; t.useStopLoss = true
        }
        ticket = t
    }

    // MARK: Editing (panel and chart)

    func setTicketRisk(_ pct: Double) {
        riskPercent = min(max(pct, 0.05), 10)
        ticket?.lock = .risk
        if panelMode != .manual { ticket?.size = nil }
    }

    func setTicketSize(_ size: Double) {
        var s = max(size, 0)
        if ticket?.reduceOnly == true, let pos = position { s = min(s, abs(pos.size)) }
        ticket?.size = s
        if panelMode == .risk { ticket?.lock = .size }
    }

    func setTicketLeverage(_ lev: Int?) {
        ticket?.leverage = lev.map { min(max($0, 1), asset?.maxLeverage ?? 50) }
    }

    func toggleLock() {
        guard let t = ticket else { return }
        if t.lock == .risk { ticket?.size = plan?.size; ticket?.lock = .size } else { ticket?.lock = .risk; ticket?.size = nil }
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
                _ = try await execOrders(reqs)
                toast("Verkleinorder\(entryCount > 1 ? "s" : "") geplaatst: \(fmt.size(pl.size, coin: c, decimals: a.szDecimals))", .success)
                ticket = nil
                await refreshAccount()
                await refreshHistory()
                return
            }

            let stop = t.useStopLoss ? HLFormat.roundPrice(t.stopLoss, szDecimals: a.szDecimals) : nil
            // A single fresh entry with a stop goes in one go (entry + stop linked); everything else Grip keeps in line itself.
            let simple = pos == nil && entryCount == 1 && stop != nil
            if simple, let stop {
                reqs.append(OrderRequest(asset: a, isBuy: !isBuy, size: pl.size, limitPx: stop, reduceOnly: true,
                                         kind: .trigger(triggerPx: stop, isMarket: true, tpsl: .sl)))
            }
            let statuses = try await execOrders(reqs, grouping: simple ? "normalTpsl" : "na")

            // From here Grip keeps stop and take-profits in line with the position.
            var m = managed[c] ?? ManagedTrade(isLong: isBuy, lastSize: 0)
            m.isLong = isBuy
            m.lastSize = abs(pos?.size ?? 0)
            if let stop { m.stop = stop }
            for st in statuses.prefix(entryCount) { if case .resting(let oid) = st { m.entryOids.append(oid); orderKinds[oid] = .limit } }
            let avg = pl.after.avgEntry
            let ladder = t.tps.filter { isBuy ? $0.price > avg : $0.price < avg }
            if !ladder.isEmpty {
                let total = max(ladder.reduce(0) { $0 + $1.pct }, 1)
                m.tps = PendingTPs(entryOid: 0, isLong: isBuy, prices: ladder.map(\.price), fractions: ladder.map { $0.pct / total })
                if pos != nil {
                    // New ladder replaces the old take-profits.
                    for o in existingTPOrders { try? await execCancel(a, oid: o.oid) }
                }
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
            if resting > 0 {
                let what = pl.isAdd ? "Bijkoop-order\(resting > 1 ? "s" : "")" : (resting > 1 ? "\(resting) entries" : "Limit \(side)")
                toast("\(what) geplaatst · \(t.leverage ?? pl.leverage)×", .success)
                notify(.orderPlaced, "\(what) geplaatst", "\(c) \(side) · \(fmt.size(pl.size, coin: c, decimals: a.szDecimals))")
            } else if !filled {
                toast("Order verstuurd.", .success)
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

    /// Called after every account refresh. When a managed position grows, the stop is resized to the whole position and the
    /// take-profits are placed or scaled up. When it is closed, entries that never filled are cancelled.
    func reconcileManaged() async {
        guard !reconciling, !managed.isEmpty else { return }
        reconciling = true
        defer { reconciling = false }
        let openOids = Set(account.openOrders.map(\.oid))
        for (c, m0) in managed {
            var m = m0
            let pos = account.position(for: c)
            let size = pos.map { $0.isLong == m.isLong ? abs($0.size) : 0 } ?? 0
            m.entryOids = m.entryOids.filter { openOids.contains($0) }
            let a = assets.first { $0.name == c }

            if size < 1e-12 {
                if m.lastSize > 1e-12 {
                    if let a, !m.entryOids.isEmpty {
                        for oid in m.entryOids { try? await execCancel(a, oid: oid) }
                        toast("\(c)-trade gesloten: \(m.entryOids.count) niet-gevulde entr\(m.entryOids.count > 1 ? "ies" : "y") geannuleerd", .info)
                    }
                    managed[c] = nil
                    breakEvenAfterTP.remove(c)
                } else if m.entryOids.isEmpty {
                    managed[c] = nil          // cancelled before anything filled
                } else {
                    managed[c] = m
                }
                continue
            }

            if size > m.lastSize + 1e-12, let a, let pos {
                await syncStop(coin: c, asset: a, position: pos, stop: m.stop)
                if let tps = m.tps {
                    if await placeTakeProfits(coin: c, tps) { m.tps = nil }
                } else if m.lastSize > 1e-12 {
                    await scaleTakeProfits(coin: c, asset: a, from: m.lastSize, to: size)
                }
            }
            m.lastSize = size
            managed[c] = m
        }
    }

    /// One stop for the whole position.
    private func syncStop(coin c: String, asset a: AssetInfo, position pos: Position, stop: Double?) async {
        let size = HLFormat.roundSize(abs(pos.size), szDecimals: a.szDecimals)
        let sl = account.openOrders.first { $0.coin == c && $0.isTrigger && $0.tpsl == .sl }
        guard let px = stop ?? sl?.displayPx else { return }
        let req = OrderRequest(asset: a, isBuy: !pos.isLong, size: size, limitPx: px, reduceOnly: true,
                               kind: .trigger(triggerPx: px, isMarket: true, tpsl: .sl))
        do {
            if let sl {
                // size 0 = a stop for the whole position already
                guard sl.size > 0, abs(sl.size - size) > 1e-12 || abs(sl.displayPx - px) > 1e-9 else { return }
                try await execModify(oid: sl.oid, req)
            } else {
                _ = try await execOrders([req])
            }
        } catch {
            toast("Stop-loss niet bijgewerkt: \(error.localizedDescription)", .error)
            notify(.orderProblem, "Stop-loss niet bijgewerkt", error.localizedDescription)
        }
    }

    /// Same prices and split, larger sizes (after adding to the position).
    private func scaleTakeProfits(coin c: String, asset a: AssetInfo, from old: Double, to new: Double) async {
        let factor = new / old
        let orders = account.openOrders.filter { $0.coin == c && $0.reduceOnly && (!$0.isTrigger || $0.tpsl == .tp) && $0.size > 0 }
        guard !orders.isEmpty else { return }
        var n = 0
        for o in orders {
            let sz = HLFormat.roundSize(o.size * factor, szDecimals: a.szDecimals)
            guard sz > o.size else { continue }
            let kind: OrderKind = o.isTrigger ? .trigger(triggerPx: o.displayPx, isMarket: true, tpsl: .tp) : .limit(tif: "Gtc")
            do {
                try await execModify(oid: o.oid, OrderRequest(asset: a, isBuy: o.isBuy, size: sz, limitPx: o.displayPx, reduceOnly: true, kind: kind))
                n += 1
            } catch {
                toast("Take-profit niet vergroot: \(error.localizedDescription)", .error)
            }
        }
        if n > 0 { toast("\(n) take-profit\(n > 1 ? "s" : "") meegegroeid met je positie", .success) }
    }
}
#endif
