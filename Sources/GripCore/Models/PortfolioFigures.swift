import Foundation

/// Figures over a set of closed trades, for the Portfolio tab.
public struct PortfolioFigures: Equatable, Sendable {
    public struct Group: Equatable, Sendable, Identifiable {
        public var name: String
        public var net: Double
        public var count: Int
        public var wins: Int
        public var id: String { name }
        public var winRate: Double { count > 0 ? Double(wins) / Double(count) : 0 }
    }
    public struct Day: Equatable, Sendable, Identifiable {
        public var date: Date          // start of the day
        public var net: Double
        public var count: Int
        public var id: Date { date }
    }

    public var count = 0
    public var wins = 0
    public var net = 0.0
    public var fees = 0.0
    public var funding = 0.0
    /// Average result of winning / losing trades in R (only trades with a known risk), nil without any.
    public var avgWinR: Double?
    public var avgLossR: Double?
    public var avgWin = 0.0
    public var avgLoss = 0.0
    /// Sum of wins ÷ sum of losses (nil without a losing trade).
    public var profitFactor: Double?
    /// Largest fall of the cumulative result from an earlier top (positive number).
    public var maxDrawdown = 0.0
    public var byCoin: [Group] = []
    public var bySide: [Group] = []
    /// Four parts of the day by local closing time: night, morning, afternoon, evening.
    public var byDayPart: [Group] = []
    public var days: [Day] = []

    public var winRate: Double { count > 0 ? Double(wins) / Double(count) : 0 }

    public static func compute(_ all: [ClosedTrade], calendar: Calendar = .current) -> PortfolioFigures {
        var s = PortfolioFigures()
        let trades = all.sorted { $0.closeTime < $1.closeTime }
        guard !trades.isEmpty else { return s }
        s.count = trades.count
        var winSum = 0.0, lossSum = 0.0, winN = 0, lossN = 0
        var winR: [Double] = [], lossR: [Double] = []
        var run = 0.0, top = 0.0
        var coins: [String: Group] = [:], sides: [String: Group] = [:], parts: [Int: Group] = [:], days: [Date: Day] = [:]
        let partNames = ["00–06", "06–12", "12–18", "18–24"]
        func add(_ g: inout Group, _ t: ClosedTrade) { g.net += t.netPnl; g.count += 1; if t.isWin { g.wins += 1 } }
        for t in trades {
            let p = t.netPnl
            s.net += p; s.fees += t.fees; s.funding += t.funding
            if t.isWin { s.wins += 1; winSum += p; winN += 1; if let r = t.rMultiple { winR.append(r) } }
            else { lossSum += p; lossN += 1; if let r = t.rMultiple { lossR.append(r) } }
            run += p
            top = max(top, run)
            s.maxDrawdown = max(s.maxDrawdown, top - run)
            add(&coins[t.coin, default: Group(name: t.coin, net: 0, count: 0, wins: 0)], t)
            let side = t.isLong ? "Long" : "Short"
            add(&sides[side, default: Group(name: side, net: 0, count: 0, wins: 0)], t)
            let part = min(calendar.component(.hour, from: t.closeTime) / 6, 3)
            add(&parts[part, default: Group(name: partNames[part], net: 0, count: 0, wins: 0)], t)
            let day = calendar.startOfDay(for: t.closeTime)
            days[day, default: Day(date: day, net: 0, count: 0)].net += p
            days[day]?.count += 1
        }
        s.avgWin = winN > 0 ? winSum / Double(winN) : 0
        s.avgLoss = lossN > 0 ? lossSum / Double(lossN) : 0
        s.avgWinR = winR.isEmpty ? nil : winR.reduce(0, +) / Double(winR.count)
        s.avgLossR = lossR.isEmpty ? nil : lossR.reduce(0, +) / Double(lossR.count)
        s.profitFactor = lossSum < 0 ? winSum / -lossSum : nil
        s.byCoin = coins.values.sorted { abs($0.net) > abs($1.net) }
        s.bySide = ["Long", "Short"].compactMap { sides[$0] }
        s.byDayPart = (0..<4).compactMap { parts[$0] }
        s.days = days.values.sorted { $0.date < $1.date }
        return s
    }
}
