import Foundation

public enum Timeframe: String, CaseIterable, Codable, Identifiable, Sendable {
    case m1 = "1m", m3 = "3m", m5 = "5m", m15 = "15m", m30 = "30m", h1 = "1h", h2 = "2h", h4 = "4h", h8 = "8h", h12 = "12h",
         d1 = "1d", d3 = "3d", w1 = "1w"

    /// Shown in the header until you pick your own favourites.
    public static let defaultFavorites: [Timeframe] = [.m1, .m5, .m15, .h1, .h4, .d1, .w1]

    public var id: String { rawValue }
    public var label: String { rawValue }

    public var milliseconds: Int64 {
        switch self {
        case .m1: return 60_000
        case .m3: return 180_000
        case .m5: return 300_000
        case .m15: return 900_000
        case .m30: return 1_800_000
        case .h1: return 3_600_000
        case .h2: return 7_200_000
        case .h4: return 14_400_000
        case .h8: return 28_800_000
        case .h12: return 43_200_000
        case .d1: return 86_400_000
        case .d3: return 259_200_000
        case .w1: return 604_800_000
        }
    }

    /// TradingView-style typed interval: "1", "5", "15" (minutes), "60"/"1h", "240"/"4h", "d"/"1d", "w"/"1w".
    public static func parse(_ raw: String) -> Timeframe? {
        let s = raw.lowercased().trimmingCharacters(in: .whitespaces)
        switch s {
        case "1", "1m": return .m1
        case "3", "3m": return .m3
        case "5", "5m": return .m5
        case "15", "15m": return .m15
        case "30", "30m": return .m30
        case "60", "1h", "h": return .h1
        case "120", "2h": return .h2
        case "240", "4h": return .h4
        case "480", "8h": return .h8
        case "720", "12h": return .h12
        case "d", "1d", "24h": return .d1
        case "3d": return .d3
        case "w", "1w", "7d": return .w1
        default: return nil
        }
    }

    public var next: Timeframe? { Timeframe.allCases.firstIndex(of: self).flatMap { $0 + 1 < Timeframe.allCases.count ? Timeframe.allCases[$0 + 1] : nil } }
    public var previous: Timeframe? { Timeframe.allCases.firstIndex(of: self).flatMap { $0 > 0 ? Timeframe.allCases[$0 - 1] : nil } }

    /// How far back to load on first open (Hyperliquid serves at most 5000 candles).
    public var historyCount: Int { 1500 }
}

public struct Candle: Codable, Equatable, Sendable {
    public var time: Int64      // open time, ms
    public var open: Double
    public var high: Double
    public var low: Double
    public var close: Double
    public var volume: Double

    public init(time: Int64, open: Double, high: Double, low: Double, close: Double, volume: Double = 0) {
        self.time = time; self.open = open; self.high = high; self.low = low; self.close = close; self.volume = volume
    }

    /// The four snap targets for trendline drawing.
    public var ohlc: [Double] { [open, high, low, close] }
}

public struct AssetInfo: Codable, Equatable, Hashable, Identifiable, Sendable {
    public var name: String
    public var index: Int
    public var szDecimals: Int
    public var maxLeverage: Int
    public var onlyIsolated: Bool
    public var id: String { name }

    public init(name: String, index: Int, szDecimals: Int, maxLeverage: Int, onlyIsolated: Bool = false) {
        self.name = name; self.index = index; self.szDecimals = szDecimals; self.maxLeverage = maxLeverage; self.onlyIsolated = onlyIsolated
    }
}

public struct AssetContext: Equatable, Sendable {
    public var markPx: Double
    public var prevDayPx: Double
    public var funding: Double
    public var dayVolume: Double          // USD
    public var openInterest: Double = 0   // in coins
    public var change24h: Double { prevDayPx > 0 ? (markPx - prevDayPx) / prevDayPx : 0 }
}

// MARK: Account

public struct Position: Equatable, Identifiable, Sendable {
    public var coin: String
    public var size: Double          // signed: >0 long, <0 short
    public var entryPx: Double
    public var unrealizedPnl: Double
    public var liquidationPx: Double?
    public var leverage: Int
    public var isCross: Bool
    public var marginUsed: Double
    public var id: String { coin }
    public var isLong: Bool { size > 0 }

    public init(coin: String, size: Double, entryPx: Double, unrealizedPnl: Double, liquidationPx: Double?, leverage: Int, isCross: Bool, marginUsed: Double) {
        self.coin = coin; self.size = size; self.entryPx = entryPx; self.unrealizedPnl = unrealizedPnl
        self.liquidationPx = liquidationPx; self.leverage = leverage; self.isCross = isCross; self.marginUsed = marginUsed
    }
}

public enum TpSl: String, Codable, Sendable { case tp, sl }

public struct OpenOrder: Equatable, Identifiable, Sendable {
    public var oid: Int64
    public var coin: String
    public var isBuy: Bool
    public var limitPx: Double
    public var size: Double
    public var reduceOnly: Bool
    public var isTrigger: Bool
    public var triggerPx: Double?
    public var tpsl: TpSl?
    public var isPositionTpsl: Bool
    public var orderType: String
    public var timestamp: Int64
    public var id: Int64 { oid }

    /// The price at which this order shows up in the chart.
    public var displayPx: Double { isTrigger ? (triggerPx ?? limitPx) : limitPx }

    public init(oid: Int64, coin: String, isBuy: Bool, limitPx: Double, size: Double, reduceOnly: Bool, isTrigger: Bool, triggerPx: Double?, tpsl: TpSl?, isPositionTpsl: Bool, orderType: String, timestamp: Int64) {
        self.oid = oid; self.coin = coin; self.isBuy = isBuy; self.limitPx = limitPx; self.size = size; self.reduceOnly = reduceOnly
        self.isTrigger = isTrigger; self.triggerPx = triggerPx; self.tpsl = tpsl; self.isPositionTpsl = isPositionTpsl
        self.orderType = orderType; self.timestamp = timestamp
    }
}

/// Hyperliquid account abstraction mode (`userAbstraction`).
public enum AccountMode: String, Equatable, Sendable {
    case standard          // "disabled": separate perps and spot balances
    case unified           // "unifiedAccount": one balance per asset, kept on the spot side
    case portfolioMargin   // "portfolioMargin"
    case dexAbstraction    // legacy

    public init(api raw: String) {
        let s = raw.lowercased()
        if s.contains("unified") { self = .unified }
        else if s.contains("portfolio") { self = .portfolioMargin }
        else if s.contains("dex") { self = .dexAbstraction }
        else { self = .standard }
    }

    /// Unified and portfolio margin keep all balances in the spot clearinghouse state.
    public var balancesOnSpot: Bool { self == .unified || self == .portfolioMargin }

    public var label: String {
        switch self {
        case .standard: return "Standaard account"
        case .unified: return "Unified account"
        case .portfolioMargin: return "Portfolio margin"
        case .dexAbstraction: return "DEX-abstractie"
        }
    }
}

public struct SpotBalance: Equatable, Sendable {
    public var coin: String
    public var token: Int
    public var total: Double
    public var hold: Double
    public var usdValue: Double
    public init(coin: String, token: Int, total: Double, hold: Double, usdValue: Double) {
        self.coin = coin; self.token = token; self.total = total; self.hold = hold; self.usdValue = usdValue
    }
}

public struct AccountState: Equatable, Sendable {
    public var accountValue: Double
    public var withdrawable: Double
    public var marginUsed: Double
    public var positions: [Position]
    public var openOrders: [OpenOrder]
    public var mode: AccountMode = .standard
    /// USD value of spot balances (in unified mode: the whole trading balance).
    public var spotValue: Double = 0
    public var spotBalances: [SpotBalance] = []
    /// In standard mode only the perps balance; spot is separate.
    public var perpsValue: Double = 0

    /// Combines perps state with spot balances according to the account mode.
    public static func combine(perps: AccountState, mode: AccountMode, spot: [SpotBalance]) -> AccountState {
        var s = perps
        s.mode = mode
        s.spotBalances = spot.filter { $0.total != 0 }
        s.spotValue = spot.reduce(0) { $0 + $1.usdValue }
        s.perpsValue = perps.accountValue
        if mode.balancesOnSpot {
            // Unified / portfolio margin: the spot balances are the collateral; add open perp PnL.
            let unrealized = perps.positions.reduce(0) { $0 + $1.unrealizedPnl }
            s.accountValue = s.spotValue + unrealized
            let usdcFree = spot.filter { $0.token == 0 }.reduce(0) { $0 + max(0, $1.total - $1.hold) }
            s.withdrawable = max(0, usdcFree + min(0, unrealized))
        }
        return s
    }

    public static let empty = AccountState(accountValue: 0, withdrawable: 0, marginUsed: 0, positions: [], openOrders: [])

    public func position(for coin: String) -> Position? { positions.first { $0.coin == coin } }
    public func orders(for coin: String) -> [OpenOrder] { openOrders.filter { $0.coin == coin } }
}

public struct Fill: Codable, Equatable, Hashable, Identifiable, Sendable {
    public var coin: String
    public var px: Double
    public var sz: Double
    public var isBuy: Bool
    public var time: Int64
    public var startPosition: Double
    public var dir: String
    public var closedPnl: Double
    public var fee: Double
    public var oid: Int64
    public var tid: Int64
    public var id: Int64 { tid }

    public init(coin: String, px: Double, sz: Double, isBuy: Bool, time: Int64, startPosition: Double, dir: String, closedPnl: Double, fee: Double, oid: Int64, tid: Int64) {
        self.coin = coin; self.px = px; self.sz = sz; self.isBuy = isBuy; self.time = time; self.startPosition = startPosition
        self.dir = dir; self.closedPnl = closedPnl; self.fee = fee; self.oid = oid; self.tid = tid
    }
}

public struct PortfolioSeries: Equatable, Sendable {
    public struct Point: Equatable, Sendable, Identifiable {
        public var time: Date
        public var value: Double
        public var id: Date { time }
        public init(time: Date, value: Double) { self.time = time; self.value = value }
    }
    public var accountValue: [Point]
    public var pnl: [Point]
    public init(accountValue: [Point], pnl: [Point]) { self.accountValue = accountValue; self.pnl = pnl }
}

public enum PortfolioPeriod: String, CaseIterable, Identifiable, Sendable {
    case day, week, month, allTime
    public var id: String { rawValue }
    public var label: String {
        switch self {
        case .day: return "24 uur"
        case .week: return "Week"
        case .month: return "Maand"
        case .allTime: return "Alles"
        }
    }
}
