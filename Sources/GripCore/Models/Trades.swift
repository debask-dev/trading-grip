import Foundation

/// A completed round trip: from flat, to a position, back to flat.
public struct ClosedTrade: Identifiable, Equatable, Sendable {
    public var id: String
    public var coin: String
    public var isLong: Bool
    public var openTime: Date
    public var closeTime: Date
    public var size: Double            // max absolute position size reached
    public var avgEntry: Double
    public var avgExit: Double
    public var grossPnl: Double        // sum of closedPnl (Hyperliquid reports this excluding fees)
    public var fees: Double
    public var fills: Int
    public var rMultiple: Double?
    public var plannedRiskUsd: Double?

    public var netPnl: Double { grossPnl - fees }
    public var duration: TimeInterval { closeTime.timeIntervalSince(openTime) }
    public var returnOnNotional: Double { avgEntry * size > 0 ? netPnl / (avgEntry * size) : 0 }
    public var isWin: Bool { netPnl > 0 }
}

public struct TradeStats: Equatable, Sendable {
    public var count: Int
    public var wins: Int
    public var netPnl: Double
    public var fees: Double
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
        var coin: String
        var isLong: Bool
        var openTime: Int64
        var entryQty = 0.0, entryValue = 0.0
        var exitQty = 0.0, exitValue = 0.0
        var maxSize = 0.0
        var pnl = 0.0, fees = 0.0, fills = 0
        var firstTid: Int64
    }

    /// Groups fills into round trips. Fills for a coin that start mid-position
    /// (history window cut off the opening fills) are skipped until the position is flat.
    public static func build(fills: [Fill], plans: [TradePlan] = []) -> [ClosedTrade] {
        let sorted = fills.sorted { ($0.time, $0.tid) < ($1.time, $1.tid) }
        var open: [String: Open] = [:]
        var synced: Set<String> = []
        var result: [ClosedTrade] = []
        let eps = 1e-9

        for f in sorted {
            // Only perp fills carry a position; skip spot ("Buy"/"Sell") fills.
            guard f.dir.contains("Long") || f.dir.contains("Short") else { continue }
            let start = f.startPosition
            let delta = f.isBuy ? f.sz : -f.sz
            let end = start + delta

            if !synced.contains(f.coin) {
                if abs(start) > eps && open[f.coin] == nil {
                    // We missed how this position was opened; wait until flat.
                    if abs(end) < eps || (start > 0) != (end > 0) { synced.insert(f.coin) }
                    if (start > 0) != (end > 0) && abs(end) > eps {
                        // Flip: the new side starts here.
                        open[f.coin] = Open(coin: f.coin, isLong: end > 0, openTime: f.time, firstTid: f.tid)
                        var o = open[f.coin]!
                        o.entryQty = abs(end); o.entryValue = abs(end) * f.px; o.maxSize = abs(end); o.fills = 1
                        o.fees = f.fee * abs(end) / f.sz
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
                remainingFee -= feePart
                qtyLeft -= closeQty
                if abs(start) - closeQty < eps {
                    result.append(finish(o, closeTime: f.time, plans: plans))
                    open[f.coin] = nil
                } else {
                    open[f.coin] = o
                }
            }

            // Opening / increasing part.
            if qtyLeft > eps {
                var o = open[f.coin] ?? Open(coin: f.coin, isLong: f.isBuy, openTime: f.time, firstTid: f.tid)
                o.entryQty += qtyLeft; o.entryValue += qtyLeft * f.px
                o.fees += remainingFee; o.fills += 1
                o.maxSize = max(o.maxSize, abs(end))
                open[f.coin] = o
            }
        }
        return result.sorted { $0.closeTime > $1.closeTime }
    }

    private static func finish(_ o: Open, closeTime: Int64, plans: [TradePlan]) -> ClosedTrade {
        let openDate = Date(timeIntervalSince1970: Double(o.openTime) / 1000)
        // Match the plan made just before this trade opened (within 3 days, same coin + side).
        let plan = plans
            .filter { $0.coin == o.coin && $0.isLong == o.isLong && $0.createdAt <= openDate.addingTimeInterval(60) && $0.createdAt > openDate.addingTimeInterval(-3 * 86400) }
            .max { $0.createdAt < $1.createdAt }
        let net = o.pnl - o.fees
        return ClosedTrade(
            id: "\(o.coin)-\(o.firstTid)",
            coin: o.coin,
            isLong: o.isLong,
            openTime: openDate,
            closeTime: Date(timeIntervalSince1970: Double(closeTime) / 1000),
            size: o.maxSize,
            avgEntry: o.entryQty > 0 ? o.entryValue / o.entryQty : 0,
            avgExit: o.exitQty > 0 ? o.exitValue / o.exitQty : 0,
            grossPnl: o.pnl,
            fees: o.fees,
            fills: o.fills,
            rMultiple: plan.map { $0.riskUsd > 0 ? net / $0.riskUsd : 0 },
            plannedRiskUsd: plan?.riskUsd
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
