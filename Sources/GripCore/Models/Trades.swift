import Foundation

/// What kind of order produced a fill (from Hyperliquid's historicalOrders, or Grip's own records).
public enum OrderKindTag: String, Codable, Sendable {
    case limit, market, takeProfit, stopLoss, liquidation

    /// Maps Hyperliquid's orderType / reduceOnly / tif to a tag.
    public static func from(orderType: String, reduceOnly: Bool, tif: String?) -> OrderKindTag {
        let t = orderType.lowercased()
        if t.contains("liquidat") { return .liquidation }
        if t.contains("take profit") { return .takeProfit }
        if t.contains("stop") { return .stopLoss }
        if t.contains("market") || (tif ?? "").lowercased() == "ioc" { return .market }
        return reduceOnly ? .takeProfit : .limit     // a resting reduce-only limit is a take-profit
    }
}

/// One order's executions within a trade (partial fills merged), as shown on the chart and in history.
public struct Execution: Identifiable, Equatable, Sendable {
    public enum Role: String, Sendable { case entry, exit }
    public var id: String                 // "<tradeID>-<oid>"
    public var oid: Int64
    public var coin: String
    public var isBuy: Bool
    public var role: Role
    public var kind: OrderKindTag?
    public var label: String              // E1, E2, TP1, TP2, SL, Close, Liq
    public var time: Int64                // first fill, ms
    public var price: Double              // volume-weighted
    public var size: Double
    public var fee: Double
    public var closedPnl: Double
    public var fills: Int
    public var tradeID: String
}

/// A completed round trip: from flat, to a position, back to flat.
public struct ClosedTrade: Identifiable, Equatable, Sendable {
    public var id: String
    public var coin: String
    public var isLong: Bool
    public var openTime: Date
    public var closeTime: Date
    public var size: Double            // max absolute position size reached
    public var avgEntry: Double        // volume-weighted over all entries
    public var avgExit: Double         // volume-weighted over all exits (TPs, SL, manual)
    public var grossPnl: Double        // price result (Hyperliquid's closedPnl, excludes fees)
    public var fees: Double            // entry + exit fees
    public var funding: Double = 0     // funding received (+) or paid (−) while open
    public var fills: Int
    public var rMultiple: Double?
    public var plannedRiskUsd: Double?
    public var executions: [Execution] = []

    public var netPnl: Double { grossPnl - fees + funding }
    public var duration: TimeInterval { closeTime.timeIntervalSince(openTime) }
    public var returnOnNotional: Double { avgEntry * size > 0 ? netPnl / (avgEntry * size) : 0 }
    public var isWin: Bool { netPnl > 0 }
    public var entries: [Execution] { executions.filter { $0.role == .entry } }
    public var exits: [Execution] { executions.filter { $0.role == .exit } }
}

/// The trade that is still open for a coin: what has happened so far.
public struct OpenTrade: Equatable, Sendable {
    public var id: String
    public var coin: String
    public var isLong: Bool
    public var openTime: Int64
    public var executions: [Execution]
    public var feesPaid: Double
    public var realized: Double        // closedPnl of partial exits so far
    public var funding: Double
}

public struct TradeAnalysis: Equatable, Sendable {
    public var closed: [ClosedTrade]
    public var open: [String: OpenTrade]
    public var executions: [Execution] { closed.flatMap { $0.executions } + open.values.flatMap { $0.executions } }
}

public struct FundingPayment: Codable, Equatable, Hashable, Sendable {
    public var time: Int64
    public var coin: String
    public var usdc: Double            // + received, − paid
    public init(time: Int64, coin: String, usdc: Double) { self.time = time; self.coin = coin; self.usdc = usdc }
}

public struct FeeRates: Codable, Equatable, Sendable {
    public var taker: Double
    public var maker: Double
    public static let base = FeeRates(taker: 0.00045, maker: 0.00015)
    public init(taker: Double, maker: Double) { self.taker = taker; self.maker = maker }
}

public struct TradeStats: Equatable, Sendable {
    public var count: Int
    public var wins: Int
    public var netPnl: Double
    public var fees: Double
    public var funding: Double = 0
    public var avgWin: Double
    public var avgLoss: Double
    public var best: Double
    public var worst: Double
    public var profitFactor: Double?
    public var avgR: Double?
    public var winRate: Double { count > 0 ? Double(wins) / Double(count) : 0 }

    public static func from(_ trades: [ClosedTrade]) -> TradeStats {
        let wins = trades.filter { $0.isWin }
        let losses = trades.filter { !$0.isWin }
        let grossWin = wins.reduce(0) { $0 + $1.netPnl }
        let grossLoss = -losses.reduce(0) { $0 + $1.netPnl }
        let rs = trades.compactMap { $0.rMultiple }
        return TradeStats(
            count: trades.count,
            wins: wins.count,
            netPnl: trades.reduce(0) { $0 + $1.netPnl },
            fees: trades.reduce(0) { $0 + $1.fees },
            funding: trades.reduce(0) { $0 + $1.funding },
            avgWin: wins.isEmpty ? 0 : grossWin / Double(wins.count),
            avgLoss: losses.isEmpty ? 0 : -grossLoss / Double(losses.count),
            best: trades.map { $0.netPnl }.max() ?? 0,
            worst: trades.map { $0.netPnl }.min() ?? 0,
            profitFactor: grossLoss > 0 ? grossWin / grossLoss : nil,
            avgR: rs.isEmpty ? nil : rs.reduce(0, +) / Double(rs.count)
        )
    }
}

public enum TradeBuilder {
    private struct Open {
        var id: String
        var coin: String
        var isLong: Bool
        var openTime: Int64
        var entryQty = 0.0, entryValue = 0.0
        var exitQty = 0.0, exitValue = 0.0
        var maxSize = 0.0
        var pnl = 0.0, fees = 0.0, fills = 0
        var execs: [Execution] = []
        var tpCount = 0, entryCount = 0

        mutating func add(oid: Int64, isBuy: Bool, role: Execution.Role, kind: OrderKindTag?, time: Int64, px: Double, qty: Double, fee: Double, pnl: Double) {
            if let i = execs.firstIndex(where: { $0.oid == oid && $0.role == role }) {
                var e = execs[i]
                e.price = (e.price * e.size + px * qty) / (e.size + qty)
                e.size += qty
                e.fee += fee
                e.closedPnl += pnl
                e.fills += 1
                execs[i] = e
                return
            }
            let label: String
            switch role {
            case .entry:
                entryCount += 1
                label = "E\(entryCount)"
            case .exit:
                switch kind {
                case .takeProfit?: tpCount += 1; label = "TP\(tpCount)"
                case .stopLoss?: label = "SL"
                case .liquidation?: label = "Liq"
                default: label = "Close"
                }
            }
            execs.append(Execution(id: "\(id)-\(oid)-\(role.rawValue)", oid: oid, coin: coin, isBuy: isBuy, role: role, kind: kind, label: label,
                                   time: time, price: px, size: qty, fee: fee, closedPnl: pnl, fills: 1, tradeID: id))
        }
    }

    /// Groups fills into round trips with their executions. Fills for a coin that start mid-position
    /// (history window cut off the opening fills) are skipped until the position is flat.
    public static func analyze(fills: [Fill], plans: [TradePlan] = [], funding: [FundingPayment] = [],
                               orderKinds: [Int64: OrderKindTag] = [:]) -> TradeAnalysis {
        let sorted = fills.sorted { ($0.time, $0.tid) < ($1.time, $1.tid) }
        var open: [String: Open] = [:]
        var synced: Set<String> = []
        var result: [ClosedTrade] = []
        let eps = 1e-9

        func newTrade(_ f: Fill, isLong: Bool) -> Open {
            Open(id: "\(f.coin)-\(f.tid)", coin: f.coin, isLong: isLong, openTime: f.time)
        }

        for f in sorted {
            // Only perp fills carry a position; skip spot ("Buy"/"Sell") fills.
            guard f.dir.contains("Long") || f.dir.contains("Short") || f.dir.lowercased().contains("liquidat") else { continue }
            let start = f.startPosition
            let delta = f.isBuy ? f.sz : -f.sz
            let end = start + delta
            let kind = orderKinds[f.oid]

            if !synced.contains(f.coin) {
                if abs(start) > eps && open[f.coin] == nil {
                    // We missed how this position was opened; wait until flat.
                    if abs(end) < eps || (start > 0) != (end > 0) { synced.insert(f.coin) }
                    if (start > 0) != (end > 0) && abs(end) > eps {
                        var o = newTrade(f, isLong: end > 0)
                        o.entryQty = abs(end); o.entryValue = abs(end) * f.px; o.maxSize = abs(end); o.fills = 1
                        let fee = f.fee * abs(end) / f.sz
                        o.fees = fee
                        o.add(oid: f.oid, isBuy: f.isBuy, role: .entry, kind: kind, time: f.time, px: f.px, qty: abs(end), fee: fee, pnl: 0)
                        open[f.coin] = o
                    }
                    continue
                }
                synced.insert(f.coin)
            }

            var remainingFee = f.fee
            var qtyLeft = f.sz

            // Closing part (reduces the current position).
            if var o = open[f.coin], abs(start) > eps, (start > 0) != f.isBuy {
                let closeQty = min(abs(start), f.sz)
                let feePart = f.fee * closeQty / f.sz
                o.exitQty += closeQty; o.exitValue += closeQty * f.px
                o.pnl += f.closedPnl; o.fees += feePart; o.fills += 1
                o.add(oid: f.oid, isBuy: f.isBuy, role: .exit, kind: kind, time: f.time, px: f.px, qty: closeQty, fee: feePart, pnl: f.closedPnl)
                remainingFee -= feePart
                qtyLeft -= closeQty
                if abs(start) - closeQty < eps {
                    result.append(finish(o, closeTime: f.time, plans: plans, funding: funding))
                    open[f.coin] = nil
                } else {
                    open[f.coin] = o
                }
            }

            // Opening / increasing part.
            if qtyLeft > eps {
                var o = open[f.coin] ?? newTrade(f, isLong: f.isBuy)
                o.entryQty += qtyLeft; o.entryValue += qtyLeft * f.px
                o.fees += remainingFee; o.fills += 1
                o.maxSize = max(o.maxSize, abs(end))
                o.add(oid: f.oid, isBuy: f.isBuy, role: .entry, kind: kind, time: f.time, px: f.px, qty: qtyLeft, fee: remainingFee, pnl: 0)
                open[f.coin] = o
            }
        }

        var openTrades: [String: OpenTrade] = [:]
        for (coin, o) in open {
            let fund = funding.filter { $0.coin == coin && $0.time >= o.openTime }.reduce(0) { $0 + $1.usdc }
            openTrades[coin] = OpenTrade(id: o.id, coin: coin, isLong: o.isLong, openTime: o.openTime, executions: o.execs,
                                         feesPaid: o.fees, realized: o.pnl, funding: fund)
        }
        return TradeAnalysis(closed: result.sorted { $0.closeTime > $1.closeTime }, open: openTrades)
    }

    /// Closed round trips only (newest first).
    public static func build(fills: [Fill], plans: [TradePlan] = []) -> [ClosedTrade] {
        analyze(fills: fills, plans: plans).closed
    }

    private static func finish(_ o: Open, closeTime: Int64, plans: [TradePlan], funding: [FundingPayment]) -> ClosedTrade {
        let openDate = Date(timeIntervalSince1970: Double(o.openTime) / 1000)
        // Match the plan made just before this trade opened (within 3 days, same coin + side).
        let plan = plans
            .filter { $0.coin == o.coin && $0.isLong == o.isLong && $0.createdAt <= openDate.addingTimeInterval(60) && $0.createdAt > openDate.addingTimeInterval(-3 * 86400) }
            .max { $0.createdAt < $1.createdAt }
        let fund = funding.filter { $0.coin == o.coin && $0.time >= o.openTime && $0.time <= closeTime }.reduce(0) { $0 + $1.usdc }
        let net = o.pnl - o.fees + fund
        return ClosedTrade(
            id: o.id,
            coin: o.coin,
            isLong: o.isLong,
            openTime: openDate,
            closeTime: Date(timeIntervalSince1970: Double(closeTime) / 1000),
            size: o.maxSize,
            avgEntry: o.entryQty > 0 ? o.entryValue / o.entryQty : 0,
            avgExit: o.exitQty > 0 ? o.exitValue / o.exitQty : 0,
            grossPnl: o.pnl,
            fees: o.fees,
            funding: fund,
            fills: o.fills,
            rMultiple: plan.map { $0.riskUsd > 0 ? net / $0.riskUsd : 0 },
            plannedRiskUsd: plan?.riskUsd,
            executions: o.execs
        )
    }

    /// Cumulative net PnL after each closed trade, oldest first.
    public static func equityCurve(_ trades: [ClosedTrade]) -> [PortfolioSeries.Point] {
        var total = 0.0
        return trades.sorted { $0.closeTime < $1.closeTime }.map {
            total += $0.netPnl
            return PortfolioSeries.Point(time: $0.closeTime, value: total)
        }
    }
}

/// Net result of the open trade and its break-even price, including fees and funding.
public enum PositionMath {
    /// Net result if the rest of the position were closed at `price` (taker fee on the exit).
    /// `size` is signed (+ long, − short).
    public static func net(price: Double, entry: Double, size: Double, feesPaid: Double, realized: Double, funding: Double, takerRate: Double) -> Double {
        realized + (price - entry) * size - feesPaid - abs(size) * price * takerRate + funding
    }

    /// Price at which the whole trade ends at exactly zero after all costs.
    public static func breakEven(entry: Double, size: Double, feesPaid: Double, realized: Double, funding: Double, takerRate: Double) -> Double? {
        let denom = size - abs(size) * takerRate
        guard abs(denom) > 1e-12 else { return nil }
        let p = (feesPaid - funding - realized + entry * size) / denom
        return p > 0 ? p : nil
    }
}
