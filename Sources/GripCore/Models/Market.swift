import Foundation

public enum Timeframe: String, CaseIterable, Codable, Identifiable, Sendable {
    case m1 = "1m", m5 = "5m", m15 = "15m", h1 = "1h", h4 = "4h", d1 = "1d", w1 = "1w"

    public var id: String { rawValue }
    public var label: String { rawValue }

    public var milliseconds: Int64 {
        switch self {
        case .m1: return 60_000
        case .m5: return 300_000
        case .m15: return 900_000
        case .h1: return 3_600_000
        case .h4: return 14_400_000
        case .d1: return 86_400_000
        case .w1: return 604_800_000
        }
    }

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
    public var dayVolume: Double
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

public struct AccountState: Equatable, Sendable {
    public var accountValue: Double
    public var withdrawable: Double
    public var marginUsed: Double
    public var positions: [Position]
    public var openOrders: [OpenOrder]

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
