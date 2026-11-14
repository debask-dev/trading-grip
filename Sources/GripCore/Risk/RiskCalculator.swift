import Foundation

/// One step of a take-profit ladder.
public struct TPTarget: Equatable, Sendable {
    public var price: Double
    public var fraction: Double      // of the position, 0...1
    public init(price: Double, fraction: Double) { self.price = price; self.fraction = fraction }
}

/// Position sizing from "how much of my portfolio am I willing to lose".
public struct RiskInput: Equatable, Sendable {
    public var accountValue: Double
    public var riskPercent: Double      // e.g. 1.0 = 1%
    public var entry: Double
    public var stopLoss: Double
    public var takeProfit: Double?
    public var maxLeverage: Int
    public var szDecimals: Int
    public var takerFeeRate: Double     // stop-loss exit (market)
    public var entryFeeRate: Double     // maker for a limit entry, taker for a market entry
    /// Size typed or scrubbed by the user (lock on size / manual panel). Risk is then derived from it.
    public var sizeOverride: Double?
    /// Leverage chosen by the user; nil = the minimum needed.
    public var leverageOverride: Int?
    /// Take-profit ladder: (price, fraction of the position). Overrides `takeProfit` when not empty.
    public var takeProfits: [TPTarget] = []

    public init(accountValue: Double, riskPercent: Double, entry: Double, stopLoss: Double, takeProfit: Double?, maxLeverage: Int, szDecimals: Int,
                takerFeeRate: Double = 0.00045, entryFeeRate: Double? = nil) {
        self.accountValue = accountValue; self.riskPercent = riskPercent; self.entry = entry; self.stopLoss = stopLoss
        self.takeProfit = takeProfit; self.maxLeverage = maxLeverage; self.szDecimals = szDecimals; self.takerFeeRate = takerFeeRate
        self.entryFeeRate = entryFeeRate ?? takerFeeRate
    }
}

public struct RiskResult: Equatable, Sendable {
    public var isLong: Bool
    public var riskUsd: Double
    public var size: Double              // coins, rounded down to szDecimals
    public var notional: Double
    public var leverage: Int             // minimum leverage needed to open this with the full account as margin
    public var marginRequired: Double
    public var rewardRisk: Double?
    public var potentialProfit: Double?
    public var estLiquidationPx: Double
    public var warnings: [String]
    /// Fees for entry + stop-loss exit (already part of riskUsd).
    public var estFees: Double = 0
    /// Actual risk as % of the account (differs from the chosen max when the size is set by hand).
    public var riskPercentActual: Double = 0
    public var minLeverage: Int = 1
}

public enum RiskCalculator {
    public static func calculate(_ i: RiskInput) -> RiskResult? {
        let dist = abs(i.entry - i.stopLoss)
        guard i.accountValue > 0, i.entry > 0, dist > 0, i.riskPercent > 0 else { return nil }
        let isLong = i.stopLoss < i.entry
        // Loss per coin = price distance + fees on entry and exit.
        let lossPerCoin = dist + i.entryFeeRate * i.entry + i.takerFeeRate * i.stopLoss
        var riskUsd = i.accountValue * i.riskPercent / 100
        let size: Double
        if let manual = i.sizeOverride {
            size = HLFormat.roundSize(max(manual, 0), szDecimals: i.szDecimals, down: true)
            riskUsd = size * lossPerCoin
        } else {
            size = HLFormat.roundSize(riskUsd / lossPerCoin, szDecimals: i.szDecimals, down: true)
        }
        let notional = size * i.entry
        var warnings: [String] = []
        let minLev = max(1, Int((notional / i.accountValue).rounded(.up)))
        var lev = max(minLev, 1)
        if let chosen = i.leverageOverride {
            lev = min(max(chosen, 1), i.maxLeverage)
            if chosen < minLev { warnings.append("Te weinig marge voor deze grootte: minstens \(minLev)× nodig.") }
        }
        if minLev > i.maxLeverage {
            warnings.append("Te groot: dit vraagt \(minLev)× hefboom, maximaal \(i.maxLeverage)× toegestaan. Zet je stop-loss verder weg of verklein de positie.")
            lev = i.maxLeverage
        }
        if i.sizeOverride != nil && riskUsd > i.accountValue * i.riskPercent / 100 * 1.0001 {
            warnings.append("Risico \(String(format: "%.2f", riskUsd / i.accountValue * 100))% is meer dan je max van \(String(format: "%.2f", i.riskPercent))%.")
        }
        if size <= 0 { warnings.append("Positie te klein voor de minimale ordergrootte.") }
        if notional > 0 && notional < 10 { warnings.append("Hyperliquid vereist minimaal $10 per order.") }

        let maintenance = 1.0 / Double(i.maxLeverage) / 2
        let liq = isLong ? i.entry * (1 - 1 / Double(lev) + maintenance) : i.entry * (1 + 1 / Double(lev) - maintenance)
        if (isLong && liq >= i.stopLoss) || (!isLong && liq <= i.stopLoss) {
            warnings.append("Let op: de geschatte liquidatieprijs ligt vóór je stop-loss.")
        }

        var rr: Double? = nil
        var profit: Double? = nil
        let ladder = i.takeProfits.filter { isLong ? $0.price > i.entry : $0.price < i.entry }
        if !ladder.isEmpty {
            let totalFrac = ladder.reduce(0) { $0 + $1.fraction }
            let avgMove = ladder.reduce(0) { $0 + abs($1.price - i.entry) * $1.fraction } / max(totalFrac, 1e-9)
            rr = avgMove / dist
            profit = ladder.reduce(0) { $0 + size * $1.fraction * (abs($1.price - i.entry) - i.entryFeeRate * i.entry - i.entryFeeRate * $1.price) }
            if ladder.count < i.takeProfits.count { warnings.append("Een of meer take-profits liggen aan de verkeerde kant van de entry.") }
        } else if let tp = i.takeProfit {
            let validTp = isLong ? tp > i.entry : tp < i.entry
            if validTp {
                rr = abs(tp - i.entry) / dist
                profit = size * abs(tp - i.entry)
            } else {
                warnings.append("Take-profit ligt aan de verkeerde kant van de entry.")
            }
        }
        return RiskResult(isLong: isLong, riskUsd: riskUsd, size: size, notional: notional, leverage: lev,
                          marginRequired: notional / Double(lev), rewardRisk: rr, potentialProfit: profit,
                          estLiquidationPx: liq, warnings: warnings,
                          estFees: size * (i.entryFeeRate * i.entry + i.takerFeeRate * i.stopLoss),
                          riskPercentActual: riskUsd / i.accountValue * 100, minLeverage: minLev)
    }
}

/// Hyperliquid number rules.
public enum HLFormat {
    /// Same output as the official SDK's float_to_wire.
    public static func wire(_ x: Double) -> String {
        var s = String(format: "%.8f", x)
        if s.contains(".") {
            while s.hasSuffix("0") { s.removeLast() }
            if s.hasSuffix(".") { s.removeLast() }
        }
        if s == "-0" || s.isEmpty { s = "0" }
        return s
    }

    public static func roundSize(_ size: Double, szDecimals: Int, down: Bool = false) -> Double {
        let f = pow(10.0, Double(szDecimals))
        let v = size * f
        return (down ? (v + 1e-9).rounded(.down) : v.rounded()) / f
    }

    /// Perp prices: at most 5 significant figures and at most (6 - szDecimals) decimals.
    /// Integer prices are always allowed.
    public static func roundPrice(_ px: Double, szDecimals: Int) -> Double {
        guard px > 0 else { return 0 }
        if px >= 100_000 { return px.rounded() }
        let magnitude = Int(floor(log10(px)))
        let sigDecimals = max(0, 4 - magnitude)
        let decimals = min(sigDecimals, max(0, 6 - szDecimals))
        let f = pow(10.0, Double(decimals))
        return (px * f).rounded() / f
    }

    /// Smallest sensible price increment for dragging lines around.
    public static func tick(for px: Double, szDecimals: Int) -> Double {
        guard px > 0 else { return 0.01 }
        let magnitude = Int(floor(log10(px)))
        let decimals = min(max(0, 4 - magnitude), max(0, 6 - szDecimals))
        return pow(10.0, -Double(decimals))
    }

    /// Aggressive limit price for "market" (IOC) orders.
    public static func slippagePrice(_ px: Double, isBuy: Bool, slippage: Double, szDecimals: Int) -> Double {
        roundPrice(px * (isBuy ? 1 + slippage : 1 - slippage), szDecimals: szDecimals)
    }
}
