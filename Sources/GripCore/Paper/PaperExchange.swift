import Foundation

/// Paper trading ("oefenmodus"): simulates Hyperliquid order handling locally against live prices.
/// Same inputs (OrderRequest) and outputs (OrderStatus, AccountState, Fill) as the real exchange,
/// so the app works identically in both modes.
public final class PaperExchange: Codable, @unchecked Sendable {
    public struct Order: Codable, Equatable, Sendable {
        public var oid: Int64
        public var coin: String
        public var isBuy: Bool
        public var px: Double
        public var size: Double
        public var reduceOnly: Bool
        public var triggerPx: Double?
        public var tpsl: TpSl?
        public var isMarketTrigger: Bool
        public var isPositionTpsl: Bool
        public var parentOid: Int64?      // child TP/SL of a normalTpsl entry: inactive until the parent fills
        public var time: Int64
    }

    public struct Holding: Codable, Equatable, Sendable {
        public var size: Double          // signed
        public var entry: Double
        public var leverage: Int
        public var isCross: Bool
    }

    public struct Snapshot: Codable, Equatable, Sendable {
        public var time: Int64
        public var accountValue: Double
        public var pnl: Double
    }

    public static let takerFee = 0.00045
    public static let makerFee = 0.00015

    public private(set) var startingBalance: Double
    public private(set) var balance: Double
    public private(set) var holdings: [String: Holding] = [:]
    public private(set) var orders: [Order] = []
    public private(set) var fills: [Fill] = []
    public private(set) var snapshots: [Snapshot] = []
    /// What each order was (entry limit, take-profit, stop, market close) to label fills.
    public private(set) var orderKinds: [Int64: OrderKindTag] = [:]
    private var leverage: [String: (Int, Bool)] = [:]
    private var nextOid: Int64 = 1_000_000
    private var nextTid: Int64 = 1

    public init(balance: Double = 10_000) {
        startingBalance = balance
        self.balance = balance
    }

    // MARK: Codable (tuple dictionary needs manual coding)

    private enum CodingKeys: String, CodingKey { case startingBalance, balance, holdings, orders, fills, snapshots, leverage, nextOid, nextTid, orderKinds }
    private struct Lev: Codable { var value: Int; var cross: Bool }

    public required init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        startingBalance = try c.decode(Double.self, forKey: .startingBalance)
        balance = try c.decode(Double.self, forKey: .balance)
        holdings = try c.decode([String: Holding].self, forKey: .holdings)
        orders = try c.decode([Order].self, forKey: .orders)
        fills = try c.decode([Fill].self, forKey: .fills)
        snapshots = try c.decodeIfPresent([Snapshot].self, forKey: .snapshots) ?? []
        leverage = (try c.decodeIfPresent([String: Lev].self, forKey: .leverage) ?? [:]).mapValues { ($0.value, $0.cross) }
        nextOid = try c.decode(Int64.self, forKey: .nextOid)
        nextTid = try c.decode(Int64.self, forKey: .nextTid)
        orderKinds = (try c.decodeIfPresent([String: OrderKindTag].self, forKey: .orderKinds) ?? [:])
            .reduce(into: [:]) { acc, kv in if let k = Int64(kv.key) { acc[k] = kv.value } }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(startingBalance, forKey: .startingBalance)
        try c.encode(balance, forKey: .balance)
        try c.encode(holdings, forKey: .holdings)
        try c.encode(orders, forKey: .orders)
        try c.encode(fills, forKey: .fills)
        try c.encode(snapshots, forKey: .snapshots)
        try c.encode(leverage.mapValues { Lev(value: $0.0, cross: $0.1) }, forKey: .leverage)
        try c.encode(nextOid, forKey: .nextOid)
        try c.encode(nextTid, forKey: .nextTid)
        try c.encode(Dictionary(uniqueKeysWithValues: orderKinds.map { (String($0.key), $0.value) }), forKey: .orderKinds)
    }

    public func reset(balance: Double) {
        startingBalance = balance
        self.balance = balance
        holdings = [:]; orders = []; fills = []; snapshots = []; leverage = [:]; orderKinds = [:]
    }

    public static func now() -> Int64 { Int64(Date().timeIntervalSince1970 * 1000) }

    // MARK: Actions

    public func updateLeverage(coin: String, isCross: Bool, leverage lev: Int) {
        leverage[coin] = (lev, isCross)
        if var h = holdings[coin] { h.leverage = lev; h.isCross = isCross; holdings[coin] = h }
    }

    /// Margin that is free: account value minus margin of positions and of resting orders that open or add.
    func freeMargin(marks: [String: Double]) -> Double {
        var value = balance
        var used = 0.0
        for (coin, h) in holdings {
            let mark = marks[coin] ?? h.entry
            value += (mark - h.entry) * h.size
            used += abs(h.size) * mark / Double(max(h.leverage, 1))
        }
        for o in orders where !o.reduceOnly && o.triggerPx == nil {
            let lev = leverage[o.coin]?.0 ?? holdings[o.coin]?.leverage ?? 1
            used += o.size * o.px / Double(max(lev, 1))
        }
        return value - used
    }

    public func place(_ reqs: [OrderRequest], grouping: String, marks: [String: Double], time: Int64 = PaperExchange.now()) throws -> [OrderStatus] {
        var statuses: [OrderStatus] = []
        var parent: Int64? = nil
        var parentFilled = false
        for (i, r) in reqs.enumerated() {
            let coin = r.asset.name
            guard let mark = marks[coin], mark > 0 else { throw HLError.exchange("Geen prijs voor \(coin).") }
            let oid = nextOid; nextOid += 1
            switch r.kind {
            case .trigger(_, _, let tpsl): orderKinds[oid] = tpsl == .tp ? .takeProfit : .stopLoss
            case .limit(let tif): orderKinds[oid] = tif == "Ioc" ? .market : (r.reduceOnly ? .takeProfit : .limit)
            }
            let size = HLFormat.roundSize(r.size, szDecimals: r.asset.szDecimals)
            guard size > 0 else { throw HLError.exchange("Order te klein.") }
            if !r.reduceOnly && size * mark < 10 { throw HLError.exchange("Order te klein: minimaal $10.") }
            if !r.reduceOnly, case .limit = r.kind {
                // Like Hyperliquid: an order that opens or adds needs free margin at the chosen leverage.
                let lev = leverage[coin]?.0 ?? holdings[coin]?.leverage ?? 1
                let opensOrAdds = (holdings[coin]?.size ?? 0) == 0 || ((holdings[coin]?.size ?? 0) > 0) == r.isBuy
                let crossesNow = r.isBuy ? r.limitPx >= mark : r.limitPx <= mark
                if opensOrAdds && size * (crossesNow ? mark : r.limitPx) / Double(max(lev, 1)) > freeMargin(marks: marks) + 1e-9 {
                    if i == 0 { throw HLError.exchange("Onvoldoende marge voor deze order.") }
                    statuses.append(.error("Onvoldoende marge voor deze order."))
                    continue
                }
            }

            switch r.kind {
            case .trigger(let trig, let isMarket, let tpsl):
                let isChild = grouping == "normalTpsl" && i > 0
                orders.append(Order(oid: oid, coin: coin, isBuy: r.isBuy, px: r.limitPx, size: size, reduceOnly: true,
                                    triggerPx: trig, tpsl: tpsl, isMarketTrigger: isMarket, isPositionTpsl: grouping == "positionTpsl",
                                    parentOid: isChild && !parentFilled ? parent : nil, time: time))
                statuses.append(.resting(oid: oid))
            case .limit(let tif):
                let crosses = r.isBuy ? r.limitPx >= mark : r.limitPx <= mark
                if crosses {
                    guard let filled = fill(coin: coin, isBuy: r.isBuy, size: size, px: mark, reduceOnly: r.reduceOnly, maker: false, oid: oid, time: time) else {
                        throw HLError.exchange("Reduce-only order zou je positie vergroten.")
                    }
                    statuses.append(.filled(oid: oid, size: filled, avgPx: mark))
                    if i == 0 { parentFilled = true }
                } else if tif == "Ioc" {
                    throw HLError.exchange("Geen directe match (te weinig liquiditeit binnen slippage).")
                } else {
                    orders.append(Order(oid: oid, coin: coin, isBuy: r.isBuy, px: r.limitPx, size: size, reduceOnly: r.reduceOnly,
                                        triggerPx: nil, tpsl: nil, isMarketTrigger: false, isPositionTpsl: false, parentOid: nil, time: time))
                    statuses.append(.resting(oid: oid))
                }
            }
            if i == 0 { parent = oid }
        }
        return statuses
    }

    public func modify(oid: Int64, to r: OrderRequest) throws {
        guard let i = orders.firstIndex(where: { $0.oid == oid }) else { throw HLError.exchange("Order bestaat niet meer.") }
        orders[i].px = r.limitPx
        if case .trigger(let trig, _, _) = r.kind { orders[i].triggerPx = trig }
        orders[i].size = HLFormat.roundSize(r.size, szDecimals: r.asset.szDecimals)
    }

    public func cancel(oid: Int64) throws {
        guard orders.contains(where: { $0.oid == oid }) else { throw HLError.exchange("Order bestaat niet meer.") }
        orders.removeAll { $0.oid == oid || $0.parentOid == oid }
    }

    /// Checks resting orders against new prices. Returns the fills that happened.
    @discardableResult
    public func onPrices(_ marks: [String: Double], time: Int64 = PaperExchange.now()) -> [Fill] {
        var result: [Fill] = []
        var changed = true
        while changed {
            changed = false
            for o in orders where o.parentOid == nil {
                guard let mark = marks[o.coin], mark > 0 else { continue }
                var hit = false
                var px = o.px
                var maker = true
                if let trig = o.triggerPx, let tpsl = o.tpsl {
                    // Sell TP / buy SL trigger when price rises through the trigger; the others when it falls.
                    let up = (tpsl == .tp) != o.isBuy
                    hit = up ? mark >= trig : mark <= trig
                    px = o.isMarketTrigger ? mark : o.px
                    maker = false
                } else {
                    hit = o.isBuy ? mark <= o.px : mark >= o.px
                }
                guard hit else { continue }
                orders.removeAll { $0.oid == o.oid }
                if o.isPositionTpsl || o.reduceOnly, holdings[o.coin] == nil { changed = true; break }
                let size = o.isPositionTpsl && o.size == 0 ? abs(holdings[o.coin]?.size ?? 0) : o.size
                if fill(coin: o.coin, isBuy: o.isBuy, size: size, px: px, reduceOnly: o.reduceOnly, maker: maker, oid: o.oid, time: time) != nil,
                   let f = fills.last {
                    result.append(f)
                }
                // Activate children of a filled entry
                for j in orders.indices where orders[j].parentOid == o.oid { orders[j].parentOid = nil }
                changed = true
                break
            }
        }
        return result
    }

    /// Executes a fill. Returns the filled size, or nil when a reduce-only order would not reduce.
    @discardableResult
    private func fill(coin: String, isBuy: Bool, size reqSize: Double, px: Double, reduceOnly: Bool, maker: Bool, oid: Int64, time: Int64) -> Double? {
        let start = holdings[coin]?.size ?? 0
        var size = reqSize
        if reduceOnly {
            guard start != 0, (start > 0) != isBuy else { return nil }
            size = min(size, abs(start))
        }
        let delta = isBuy ? size : -size
        let end = start + delta
        var closedPnl = 0.0
        let entry = holdings[coin]?.entry ?? px
        let closing = start != 0 && (start > 0) != isBuy
        if closing {
            let closeQty = min(abs(start), size)
            closedPnl = (px - entry) * closeQty * (start > 0 ? 1 : -1)
        }
        let fee = size * px * (maker ? Self.makerFee : Self.takerFee)
        balance += closedPnl - fee

        let lev = leverage[coin] ?? (holdings[coin].map { ($0.leverage, $0.isCross) } ?? (1, true))
        if abs(end) < 1e-12 {
            holdings[coin] = nil
            orders.removeAll { $0.coin == coin && ($0.reduceOnly || $0.isPositionTpsl) && $0.parentOid == nil }
        } else if start == 0 || (start > 0) != (end > 0) {
            holdings[coin] = Holding(size: end, entry: px, leverage: lev.0, isCross: lev.1)   // new or flipped
        } else if abs(end) > abs(start) {
            let newEntry = (abs(start) * entry + size * px) / abs(end)
            holdings[coin] = Holding(size: end, entry: newEntry, leverage: lev.0, isCross: lev.1)
        } else {
            holdings[coin]?.size = end
        }

        let dir: String
        switch (start > 0, start < 0, isBuy) {
        case (false, false, true): dir = "Open Long"
        case (false, false, false): dir = "Open Short"
        case (true, _, true): dir = "Open Long"
        case (true, _, false): dir = end < 0 ? "Long > Short" : "Close Long"
        case (_, true, false): dir = "Open Short"
        case (_, true, true): dir = end > 0 ? "Short > Long" : "Close Short"
        }
        fills.append(Fill(coin: coin, px: px, sz: size, isBuy: isBuy, time: time, startPosition: start, dir: dir,
                          closedPnl: closedPnl, fee: fee, oid: oid, tid: nextTid))
        nextTid += 1
        return size
    }

    // MARK: Views

    public func accountState(marks: [String: Double], assets: [AssetInfo]) -> AccountState {
        var positions: [Position] = []
        var unrealized = 0.0
        var margin = 0.0
        for (coin, h) in holdings.sorted(by: { $0.key < $1.key }) {
            let mark = marks[coin] ?? h.entry
            let u = (mark - h.entry) * h.size
            unrealized += u
            let m = abs(h.size) * mark / Double(max(h.leverage, 1))
            margin += m
            let maxLev = Double(assets.first { $0.name == coin }?.maxLeverage ?? 20)
            let mm = 1 / maxLev / 2
            let liq = h.size > 0 ? h.entry * (1 - 1 / Double(h.leverage) + mm) : h.entry * (1 + 1 / Double(h.leverage) - mm)
            positions.append(Position(coin: coin, size: h.size, entryPx: h.entry, unrealizedPnl: u, liquidationPx: h.leverage > 1 ? liq : nil,
                                      leverage: h.leverage, isCross: h.isCross, marginUsed: m))
        }
        // Like Hyperliquid: stop and take-profit linked to an entry are listed (and can be cancelled) before it fills.
        let open = orders.map { o in
            OpenOrder(oid: o.oid, coin: o.coin, isBuy: o.isBuy, limitPx: o.px, size: o.size, reduceOnly: o.reduceOnly,
                      isTrigger: o.triggerPx != nil, triggerPx: o.triggerPx, tpsl: o.tpsl, isPositionTpsl: o.isPositionTpsl,
                      orderType: o.triggerPx == nil ? "Limit" : (o.tpsl == .tp ? "Take Profit Market" : "Stop Market"), timestamp: o.time)
        }
        let value = balance + unrealized
        return AccountState(accountValue: value, withdrawable: max(0, value - margin), marginUsed: margin, positions: positions, openOrders: open)
    }

    public func recordSnapshot(marks: [String: Double], assets: [AssetInfo], time: Int64 = PaperExchange.now(), minInterval: Int64 = 30_000) {
        let v = accountState(marks: marks, assets: assets).accountValue
        // Keep moving the newest point until `minInterval` has passed since the one before it.
        if snapshots.count >= 2, time - snapshots[snapshots.count - 2].time < minInterval {
            snapshots[snapshots.count - 1] = Snapshot(time: time, accountValue: v, pnl: v - startingBalance)
            return
        }
        snapshots.append(Snapshot(time: time, accountValue: v, pnl: v - startingBalance))
        if snapshots.count > 20_000 { snapshots.removeFirst(snapshots.count - 20_000) }
    }

    public func portfolio(now: Date = Date()) -> [PortfolioPeriod: PortfolioSeries] {
        var out: [PortfolioPeriod: PortfolioSeries] = [:]
        let spans: [PortfolioPeriod: TimeInterval] = [.day: 86400, .week: 7 * 86400, .month: 30 * 86400, .allTime: .greatestFiniteMagnitude]
        for (period, span) in spans {
            let from = span == .greatestFiniteMagnitude ? Int64.min : Int64((now.timeIntervalSince1970 - span) * 1000)
            let pts = snapshots.filter { $0.time >= from }
            let base = pts.first?.pnl ?? 0
            out[period] = PortfolioSeries(
                accountValue: pts.map { .init(time: Date(timeIntervalSince1970: Double($0.time) / 1000), value: $0.accountValue) },
                pnl: pts.map { .init(time: Date(timeIntervalSince1970: Double($0.time) / 1000), value: $0.pnl - base) })
        }
        return out
    }
}
