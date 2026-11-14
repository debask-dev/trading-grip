import Foundation

/// The position that is already open on this coin (for adding to it or reducing it).
public struct ExistingPosition: Equatable, Sendable {
    public var size: Double          // absolute
    public var entryPx: Double
    public var isLong: Bool
    public var leverage: Int
    public init(size: Double, entryPx: Double, isLong: Bool, leverage: Int) {
        self.size = abs(size); self.entryPx = entryPx; self.isLong = isLong; self.leverage = leverage
    }
}

/// Everything about an order before it is sent: one or more entries, optional stop, optional TP ladder,
/// sized by risk (riskPercent) or by hand (sizeOverride), optionally on top of an open position.
public struct PlanInput: Equatable, Sendable {
    public var accountValue: Double
    /// Max loss for the whole trade in % of the account. nil = free sizing (manual panel).
    public var riskPercent: Double?
    public var isLong: Bool
    /// Entry prices with their share (fractions are normalised).
    public var entries: [TPTarget]
    public var stopLoss: Double?
    public var takeProfits: [TPTarget] = []
    /// New size in coins (manual or locked size). Overrides risk sizing.
    public var sizeOverride: Double?
    public var leverageOverride: Int?
    public var maxLeverage: Int
    public var szDecimals: Int
    public var takerFeeRate: Double = 0.00045
    public var entryFeeRate: Double = 0.00015
    public var existing: ExistingPosition?

    public init(accountValue: Double, riskPercent: Double?, isLong: Bool, entries: [TPTarget], stopLoss: Double?,
                maxLeverage: Int, szDecimals: Int) {
        self.accountValue = accountValue; self.riskPercent = riskPercent; self.isLong = isLong; self.entries = entries
        self.stopLoss = stopLoss; self.maxLeverage = maxLeverage; self.szDecimals = szDecimals
    }
}

/// Size, entry and risk of the position as a whole.
public struct PositionSnapshot: Equatable, Sendable {
    public var size: Double
    public var avgEntry: Double
    public var breakEven: Double
    public var riskUsd: Double?
    public var margin: Double
    public var estLiquidationPx: Double
}

public struct Plan: Equatable, Sendable {
    public var isLong: Bool
    /// Reducing an open position in the other direction (reduce-only).
    public var isReduce: Bool
    /// Adding to an open position in the same direction.
    public var isAdd: Bool
    public var size: Double                 // new coins (all entries)
    public var entrySizes: [Double]
    public var avgEntry: Double             // of the new part
    public var notional: Double             // of the new part
    public var leverage: Int
    public var minLeverage: Int
    /// Loss at the stop for the whole position, fees included. nil without a stop.
    public var riskUsd: Double?
    public var riskPercentActual: Double?
    /// Loss at the stop if only the first entry fills.
    public var riskFirstEntryOnly: Double?
    public var existingRiskUsd: Double?
    public var rewardRisk: Double?
    public var potentialProfit: Double?
    public var estFees: Double
    /// Realised result of a reduce order (gross, before fees).
    public var reducePnl: Double?
    public var before: PositionSnapshot?
    public var after: PositionSnapshot
    public var warnings: [String]

    public var estLiquidationPx: Double { after.estLiquidationPx }
    public var marginRequired: Double { after.margin }
}

public enum OrderPlanner {
    static func liquidation(entry: Double, isLong: Bool, leverage: Int, maxLeverage: Int) -> Double {
        let maintenance = 1.0 / Double(max(maxLeverage, 1)) / 2
        let l = Double(max(leverage, 1))
        return isLong ? entry * (1 - 1 / l + maintenance) : entry * (1 + 1 / l - maintenance)
    }

    static func breakEven(entry: Double, isLong: Bool, entryFee: Double, exitFee: Double) -> Double {
        isLong ? entry * (1 + entryFee) / (1 - exitFee) : entry * (1 - entryFee) / (1 + exitFee)
    }

    public static func plan(_ i: PlanInput) -> Plan? {
        let levels = i.entries.filter { $0.price > 0 && $0.fraction > 0 }
        guard i.accountValue > 0, !levels.isEmpty else { return nil }
        let totalFrac = levels.reduce(0) { $0 + $1.fraction }
        let fracs = levels.map { $0.fraction / totalFrac }
        let avg = zip(levels, fracs).reduce(0) { $0 + $1.0.price * $1.1 }
        let dir: Double = i.isLong ? 1 : -1
        var warnings: [String] = []

        let existing = i.existing.flatMap { $0.size > 0 ? $0 : nil }
        let isReduce = existing.map { $0.isLong != i.isLong } ?? false
        let isAdd = existing.map { $0.isLong == i.isLong } ?? false

        // Stop: must be on the losing side of the (average) entry.
        var stop = i.stopLoss
        if let s = stop, isReduce { _ = s; stop = nil }
        if let s = stop, dir * (avg - s) <= 0 {
            warnings.append("Stop-loss ligt aan de verkeerde kant van de entry.")
            stop = nil
        }

        let lossPerCoin = stop.map { dir * (avg - $0) + i.entryFeeRate * avg + i.takerFeeRate * $0 }
        let existingLoss: Double? = {
            guard isAdd, let e = existing, let s = stop else { return nil }
            return e.size * (dir * (e.entryPx - s) + i.takerFeeRate * s)
        }()

        // Size
        var size: Double
        if let manual = i.sizeOverride {
            size = max(manual, 0)
        } else if let rp = i.riskPercent, let lpc = lossPerCoin, lpc > 0 {
            let budget = i.accountValue * rp / 100 - (existingLoss ?? 0)
            if budget <= 0 {
                warnings.append("Geen risicoruimte meer: je huidige positie kost bij de stop al \(String(format: "%.2f", existingLoss ?? 0)) dollar. Zet je stop dichterbij of naar break-even.")
            }
            size = max(budget, 0) / lpc
        } else {
            size = 0
        }
        if isReduce, let e = existing, size > e.size {
            size = e.size
            warnings.append("Verkleinen kan tot maximaal je hele positie.")
        }
        size = HLFormat.roundSize(size, szDecimals: i.szDecimals, down: true)

        // Split over the entries; the last one takes what rounding leaves.
        var entrySizes: [Double] = []
        var left = size
        for (k, f) in fracs.enumerated() {
            let s = k == fracs.count - 1 ? HLFormat.roundSize(left, szDecimals: i.szDecimals) : HLFormat.roundSize(size * f, szDecimals: i.szDecimals, down: true)
            entrySizes.append(max(min(s, left), 0))
            left -= entrySizes.last ?? 0
        }
        if size > 0 {
            for (k, s) in entrySizes.enumerated() where s * levels[k].price < 10 {
                warnings.append(levels.count > 1 ? "E\(k + 1) is kleiner dan het Hyperliquid-minimum van $10 per order." : "Hyperliquid vereist minimaal $10 per order.")
            }
        } else if i.sizeOverride != nil || i.riskPercent == nil {
            warnings.append("Vul een grootte in.")
        } else {
            warnings.append("Positie te klein voor de minimale ordergrootte.")
        }

        let notional = size * avg
        let fees = size * (i.entryFeeRate * avg + (stop.map { i.takerFeeRate * $0 } ?? 0))

        // Position after
        let eSize = existing?.size ?? 0
        let eEntry = existing?.entryPx ?? avg
        let afterSize: Double
        let afterEntry: Double
        if isReduce {
            afterSize = max(eSize - size, 0)
            afterEntry = eEntry
        } else {
            afterSize = eSize + size
            afterEntry = afterSize > 0 ? (eSize * eEntry + size * avg) / afterSize : avg
        }
        let posLong = isReduce ? !i.isLong : i.isLong
        let afterNotional = afterSize * afterEntry
        let minLev = max(1, Int((afterNotional / i.accountValue - 1e-9).rounded(.up)))
        var lev = max(minLev, existing?.leverage ?? 1)
        if let chosen = i.leverageOverride {
            lev = chosen
            if chosen < minLev && !isReduce { warnings.append("Te weinig marge voor deze grootte: minstens \(minLev)× nodig.") }
            if let e = existing, chosen < e.leverage, !isReduce {
                warnings.append("Lager dan je huidige hefboom (\(e.leverage)×). Hyperliquid staat verlagen met een open positie vaak niet toe.")
            }
        }
        if minLev > i.maxLeverage && !isReduce {
            warnings.append("Te groot: dit vraagt \(minLev)× hefboom, maximaal \(i.maxLeverage)× toegestaan.")
        }
        lev = min(max(lev, 1), i.maxLeverage)

        let riskTotal: Double? = isReduce ? nil : lossPerCoin.map { size * $0 + (existingLoss ?? 0) }
        if let rp = i.riskPercent, i.sizeOverride != nil, let r = riskTotal, r > i.accountValue * rp / 100 * 1.0001 {
            warnings.append("Risico \(String(format: "%.2f", r / i.accountValue * 100))% is meer dan je max van \(String(format: "%.2f", rp))%.")
        }
        let firstOnly: Double? = {
            guard levels.count > 1, !isReduce, let s = stop, let first = levels.first, let es = entrySizes.first else { return nil }
            return es * (dir * (first.price - s) + i.entryFeeRate * first.price + i.takerFeeRate * s) + (existingLoss ?? 0)
        }()

        let liqAfter = afterSize > 0 ? liquidation(entry: afterEntry, isLong: posLong, leverage: lev, maxLeverage: i.maxLeverage) : 0
        if let s = stop, afterSize > 0, (i.isLong && liqAfter >= s) || (!i.isLong && liqAfter <= s) {
            warnings.append("Let op: de geschatte liquidatieprijs ligt vóór je stop-loss.")
        }

        // Take-profits against the average entry of the whole position.
        var rr: Double? = nil
        var profit: Double? = nil
        if !isReduce {
            let ladder = i.takeProfits.filter { dir * ($0.price - afterEntry) > 0 && $0.fraction > 0 }
            if ladder.count < i.takeProfits.filter({ $0.fraction > 0 }).count {
                warnings.append("Een of meer take-profits liggen aan de verkeerde kant van de entry.")
            }
            if !ladder.isEmpty {
                let tf = ladder.reduce(0) { $0 + $1.fraction }
                profit = ladder.reduce(0) { acc, tp in
                    let q = afterSize * tp.fraction / max(tf, 1)
                    return acc + q * (dir * (tp.price - afterEntry) - i.entryFeeRate * tp.price)
                } - size * i.entryFeeRate * avg
                if let s = stop {
                    let move = ladder.reduce(0) { $0 + abs($1.price - afterEntry) * $1.fraction } / tf
                    rr = move / max(abs(afterEntry - s), 1e-12)
                }
            }
        }

        let reducePnl: Double? = isReduce ? size * (posLong ? avg - eEntry : eEntry - avg) : nil

        let before: PositionSnapshot? = existing.map { e in
            PositionSnapshot(size: e.size, avgEntry: e.entryPx,
                             breakEven: breakEven(entry: e.entryPx, isLong: e.isLong, entryFee: i.entryFeeRate, exitFee: i.takerFeeRate),
                             riskUsd: isAdd ? existingLoss : nil, margin: e.size * e.entryPx / Double(max(e.leverage, 1)),
                             estLiquidationPx: liquidation(entry: e.entryPx, isLong: e.isLong, leverage: e.leverage, maxLeverage: i.maxLeverage))
        }
        let after = PositionSnapshot(size: afterSize, avgEntry: afterEntry,
                                     breakEven: breakEven(entry: afterEntry, isLong: posLong, entryFee: i.entryFeeRate, exitFee: i.takerFeeRate),
                                     riskUsd: riskTotal, margin: afterNotional / Double(lev), estLiquidationPx: liqAfter)

        return Plan(isLong: i.isLong, isReduce: isReduce, isAdd: isAdd, size: size, entrySizes: entrySizes, avgEntry: avg,
                    notional: notional, leverage: lev, minLeverage: minLev, riskUsd: riskTotal,
                    riskPercentActual: riskTotal.map { $0 / i.accountValue * 100 }, riskFirstEntryOnly: firstOnly,
                    existingRiskUsd: existingLoss, rewardRisk: rr, potentialProfit: profit, estFees: fees,
                    reducePnl: reducePnl, before: before, after: after, warnings: warnings)
    }
}
