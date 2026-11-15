#if os(macOS)
import SwiftUI
import GripCore

/// Take-profits being changed after the trade was placed. Shares are of the position, or before the fill of the entry.
struct TPDraft: Equatable {
    struct Level: Equatable, Identifiable {
        let id = UUID()
        var price: Double
        var pct: Double
    }
    var coin: String
    var isLong: Bool
    var levels: [Level]
    var total: Double { levels.reduce(0) { $0 + $1.pct } }
}

/// One open order being changed in the order list.
struct OrderEdit: Equatable {
    var oid: Int64
    var price: Double
    /// Size in coins.
    var size: Double
}

extension AppState {
    // MARK: Take-profits

    /// Side of the trade on this coin: the position, else the waiting entry.
    var tradeSide: Bool? {
        if let pos = position { return pos.isLong }
        if let e = coinOrders.first(where: { !$0.isTrigger && !$0.reduceOnly }) { return e.isBuy }
        return managed[coin]?.isLong
    }

    /// Size and average entry the take-profit shares refer to.
    func tpBase(isLong: Bool) -> (size: Double, entry: Double) {
        if let pos = position, pos.isLong == isLong { return (abs(pos.size), pos.entryPx) }
        let entries = TPEditor.restingEntries(coinOrders, isLong: isLong)
        let size = entries.reduce(0) { $0 + $1.size }
        let avg = size > 0 ? entries.reduce(0) { $0 + $1.size * $1.limitPx } / size : price
        return (size, avg)
    }

    /// Can the take-profits be changed here: a position or an entry that waits to fill.
    var canEditTPs: Bool {
        guard let side = tradeSide else { return false }
        return tpBase(isLong: side).size > 0
    }

    var currentTPs: [TPTarget] {
        guard let side = tradeSide else { return [] }
        return TPEditor.current(managed[coin], isLong: side, position: position, orders: coinOrders)
    }

    func startTPEdit() {
        guard let side = tradeSide else { return }
        orderEdit = nil
        var levels = currentTPs.map { TPDraft.Level(price: $0.price, pct: ($0.fraction * 100).rounded()) }
        if levels.isEmpty {
            let entry = tpBase(isLong: side).entry
            levels = [TPDraft.Level(price: roundToTick(entry * (side ? 1.015 : 0.985)), pct: 100)]
        }
        tpDraft = TPDraft(coin: coin, isLong: side, levels: levels)
    }

    func setDraftPrice(_ i: Int, _ px: Double) {
        guard tpDraft?.levels.indices.contains(i) == true else { return }
        tpDraft?.levels[i].price = roundToTick(px)
    }

    /// Sets one level's share. The total may stay under 100% (the rest runs until the stop), never above.
    func setDraftPct(_ i: Int, _ v: Double) {
        guard let d = tpDraft, d.levels.indices.contains(i) else { return }
        let others = d.total - d.levels[i].pct
        tpDraft?.levels[i].pct = min(max(v.rounded(), 1), max(100 - others, 1))
    }

    /// New level beyond the last one. It takes what is still uncovered, or half of the last level.
    func addDraftTP() {
        guard var d = tpDraft, d.levels.count < 5 else { return }
        let dir: Double = d.isLong ? 1 : -1
        let entry = tpBase(isLong: d.isLong).entry
        let last = d.levels.last?.price ?? entry
        let step = max(abs(last - entry) * 0.5, priceTick * 4)
        var pct = (100 - d.total).rounded()
        if pct < 1, let j = d.levels.indices.last {
            pct = (d.levels[j].pct / 2).rounded(.down)
            d.levels[j].pct -= pct
        }
        guard pct >= 1 else { return }
        d.levels.append(TPDraft.Level(price: roundToTick(last + dir * step), pct: pct))
        tpDraft = d
    }

    /// A take-profit for exactly the part that has none yet.
    func addDraftRest() {
        guard let d = tpDraft, d.total < 99.5 else { return }
        addDraftTP()
    }

    func removeDraftTP(_ i: Int) {
        guard tpDraft?.levels.indices.contains(i) == true else { return }
        tpDraft?.levels.remove(at: i)
    }

    func applyDraftSplit(_ split: [Double]) {
        guard var d = tpDraft, split.count == d.levels.count else { return }
        var p = split
        p[p.count - 1] += 100 - p.reduce(0, +)
        for i in d.levels.indices { d.levels[i].pct = p[i] }
        tpDraft = d
    }

    /// Something to tell about the draft; `blocks` when it cannot be applied like this.
    var draftIssue: (text: String, blocks: Bool)? {
        guard let d = tpDraft else { return nil }
        for (i, l) in d.levels.enumerated() {
            // A take-profit beyond the current price would fill straight away.
            let wrong = d.isLong ? l.price <= price : l.price >= price
            if wrong { return (T("TP\(i + 1) ligt aan de verkeerde kant van de koers"), true) }
        }
        let base = tpBase(isLong: d.isLong).size
        for (i, l) in d.levels.enumerated() where base * l.pct / 100 * l.price < TradeKeeper.minOrderValue {
            if d.levels.count == 1 { return (T("Te klein: een order moet minimaal $10 zijn"), true) }
            return (T("TP\(i + 1) is kleiner dan $10; Grip voegt hem samen met de volgende"), false)
        }
        return nil
    }

    /// Profit of one draft level after fees.
    func draftProfit(_ l: TPDraft.Level, isLong: Bool) -> Double {
        let b = tpBase(isLong: isLong)
        let qty = b.size * l.pct / 100
        return qty * (isLong ? l.price - b.entry : b.entry - l.price) - qty * feeRates.maker * (b.entry + l.price)
    }

    func applyTPDraft() async {
        guard let d = tpDraft, d.coin == coin, let a = asset else { tpDraft = nil; return }
        let levels = d.levels.map { TPTarget(price: HLFormat.roundPrice($0.price, szDecimals: a.szDecimals), fraction: $0.pct / 100) }
        let edit = TPEditor.apply(levels, to: managed[coin], isLong: d.isLong, position: position, orders: coinOrders, szDecimals: a.szDecimals)
        busy = true
        defer { busy = false }
        do {
            for action in edit.actions { try await execute(action, coin: d.coin, asset: a, isLong: d.isLong) }
            managed[d.coin] = edit.next
            tpDraft = nil
            let cover = Int(min(d.total, 100).rounded())
            if position == nil && edit.next.tps == nil {
                toast(T("Take-profit aangepast"), .success)
            } else if position == nil {
                toast(T("Take-profits aangepast. Grip plaatst ze zodra je entry gevuld is."), .success)
            } else {
                toast(cover < 100 ? T("Take-profits aangepast: samen \(cover)%, de rest loopt tot je stop") : T("Take-profits aangepast"), .success)
            }
        } catch {
            toast(T("Take-profits niet aangepast: \(error.localizedDescription)"), .error)
        }
        await refreshAccount()
    }

    // MARK: One order

    func startOrderEdit(_ o: OpenOrder) {
        tpDraft = nil
        let base = o.size > 0 ? o.size : abs(position?.size ?? 0)
        orderEdit = OrderEdit(oid: o.oid, price: pendingOrderPrices[o.oid] ?? o.displayPx, size: base)
    }

    /// What the size of a reduce-only order refers to: the position, or before the fill the entry.
    func orderBaseSize(_ o: OpenOrder) -> Double {
        tpBase(isLong: !o.isBuy).size
    }

    func applyOrderEdit() async {
        guard let e = orderEdit, let o = account.openOrders.first(where: { $0.oid == e.oid }),
              let a = assets.first(where: { $0.name == o.coin }) else { orderEdit = nil; return }
        let px = HLFormat.roundPrice(e.price, szDecimals: a.szDecimals)
        let isStop = o.isTrigger && o.tpsl == .sl
        // The stop always covers the whole position; only its price changes.
        let size = isStop ? (o.size > 0 ? o.size : abs(position?.size ?? 0)) : HLFormat.roundSize(e.size, szDecimals: a.szDecimals)
        guard size > 0, isStop || size * px >= TradeKeeper.minOrderValue else {
            toast(T("Te klein: een order moet minimaal $10 zijn"), .error)
            return
        }
        busy = true
        defer { busy = false }
        do {
            try await execModify(oid: o.oid, request(for: o, asset: a, price: px, size: size))
            if isStop { managed[o.coin]?.stop = px }
            // An entry that has not filled yet: its linked stop and take-profit follow the new size.
            if !o.reduceOnly && !o.isTrigger && position == nil, o.size > 0, abs(size - o.size) > 1e-12 {
                for c in coinOrders where c.reduceOnly && c.isBuy != o.isBuy && abs(c.size - o.size) < 1e-12 {
                    try await execModify(oid: c.oid, request(for: c, asset: a, price: c.displayPx, size: size))
                }
            }
            orderEdit = nil
            toast(T("\(orderName(o)) aangepast: \(fmt.size(size, coin: o.coin, decimals: a.szDecimals)) @ \(Fmt.price(px))"), .success)
        } catch {
            toast(T("Order niet aangepast: \(error.localizedDescription)"), .error)
        }
        await refreshAccount()
    }

    func request(for o: OpenOrder, asset a: AssetInfo, price px: Double, size: Double) -> OrderRequest {
        let kind: OrderKind = o.isTrigger
            ? .trigger(triggerPx: px, isMarket: o.orderType.lowercased().contains("market"), tpsl: o.tpsl ?? .sl)
            : .limit(tif: "Gtc")
        return OrderRequest(asset: a, isBuy: o.isBuy, size: size, limitPx: px, reduceOnly: o.reduceOnly, kind: kind)
    }
}
#endif
