#if os(macOS)
import SwiftUI
import Charts
import GripCore

/// Portfolio: key figures, result per market, a calendar of days, long against short and per part of the day.
/// All of it over the closed trades of the chosen period.
struct PortfolioStats: View {
    @EnvironmentObject var state: AppState
    let trades: [ClosedTrade]
    @State private var day: Date?

    var body: some View {
        let s = TradeStats.compute(trades)
        let f = state.fmt
        if s.count == 0 {
            EmptyView()
        } else {
            HStack(spacing: 12) {
                StatTile(title: T("Trades · winst%"), value: "\(s.count) · " + Fmt.percent(s.winRate, decimals: 0, signed: false))
                StatTile(title: T("Gem. winst / verlies"), value: averages(s, f))
                StatTile(title: T("Profit factor"), value: s.profitFactor.map { Fmt.number($0, decimals: 2) } ?? "–",
                         color: (s.profitFactor ?? 1) >= 1 ? Theme.green : Theme.red)
                StatTile(title: T("Grootste drawdown"), value: f.usd(-s.maxDrawdown, decimals: 0), color: s.maxDrawdown > 0 ? Theme.red : Theme.text)
                StatTile(title: T("Fees · funding"), value: f.usd(-s.fees, decimals: 0) + " · " + f.signedUsd(s.funding, decimals: 0), color: Theme.muted)
            }

            HStack(alignment: .top, spacing: 12) {
                ChartCard(title: T("Per markt")) {
                    VStack(spacing: 6) {
                        let top = Array(s.byCoin.prefix(8))
                        let scale = max(top.map { abs($0.net) }.max() ?? 1, 1e-9)
                        ForEach(top) { g in bar(g, scale: scale, f) }
                    }
                }
                VStack(spacing: 12) {
                    ChartCard(title: T("Long tegen short")) {
                        VStack(spacing: 6) {
                            let scale = max(s.bySide.map { abs($0.net) }.max() ?? 1, 1e-9)
                            ForEach(s.bySide) { g in bar(g, scale: scale, f) }
                        }
                    }
                    ChartCard(title: T("Per dagdeel (sluittijd)")) {
                        VStack(spacing: 6) {
                            let scale = max(s.byDayPart.map { abs($0.net) }.max() ?? 1, 1e-9)
                            ForEach(s.byDayPart) { g in bar(g, scale: scale, f) }
                        }
                    }
                }
            }

            ChartCard(title: T("Kalender: resultaat per dag")) {
                calendar(s, f)
            }
        }
    }

    /// Weeks start on Monday.
    private var mondayCalendar: Calendar {
        var c = Calendar.current
        c.firstWeekday = 2
        return c
    }

    private func averages(_ s: TradeStats, _ f: Fmt) -> String {
        if let w = s.avgWinR, let l = s.avgLossR {
            return "+" + Fmt.number(w, decimals: 1) + "R / " + Fmt.number(l, decimals: 1) + "R"
        }
        return f.signedUsd(s.avgWin, decimals: 0) + " / " + f.signedUsd(s.avgLoss, decimals: 0)
    }

    /// One row: name, a bar from the middle to the right (profit) or left (loss), result and win rate.
    private func bar(_ g: TradeStats.Group, scale: Double, _ f: Fmt) -> some View {
        HStack(spacing: 8) {
            Text(g.name).font(.system(size: 12, weight: .semibold)).frame(width: 52, alignment: .leading).lineLimit(1)
            GeometryReader { geo in
                let half = geo.size.width / 2
                let w = max(CGFloat(abs(g.net) / scale) * half, 1)
                ZStack(alignment: .leading) {
                    Rectangle().fill(Theme.line).frame(width: 1, height: 14).offset(x: half)
                    RoundedRectangle(cornerRadius: 2).fill(Theme.pnl(g.net).opacity(0.7))
                        .frame(width: w, height: 10).offset(x: g.net >= 0 ? half : half - w)
                }
                .frame(height: 14)
            }
            .frame(height: 14)
            Text(f.signedUsd(g.net, decimals: 0)).mono(11.5, .semibold).foregroundStyle(Theme.pnl(g.net)).frame(width: 70, alignment: .trailing)
            Text("\(g.count)× · " + Fmt.percent(g.winRate, decimals: 0, signed: false)).mono(10.5).foregroundStyle(Theme.muted).frame(width: 74, alignment: .trailing)
        }
    }

    /// The last six weeks as squares, Monday first. A click shows that day's trades underneath.
    @ViewBuilder
    private func calendar(_ s: TradeStats, _ f: Fmt) -> some View {
        let cal = mondayCalendar
        let today = cal.startOfDay(for: Date())
        let weekStart = cal.dateInterval(of: .weekOfYear, for: today)?.start ?? today
        let first = cal.date(byAdding: .day, value: -35, to: weekStart) ?? today
        let byDate = Dictionary(uniqueKeysWithValues: s.days.map { ($0.date, $0) })
        let scale = max(s.days.map { abs($0.net) }.max() ?? 1, 1e-9)
        let names = L10n.isEnglish ? ["Mo", "Tu", "We", "Th", "Fr", "Sa", "Su"] : ["ma", "di", "wo", "do", "vr", "za", "zo"]
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                ForEach(names, id: \.self) { Text($0).font(.system(size: 10)).foregroundStyle(Theme.dim).frame(maxWidth: .infinity) }
            }
            ForEach(0..<6, id: \.self) { w in
                HStack(spacing: 4) {
                    ForEach(0..<7, id: \.self) { d in
                        let date = cal.date(byAdding: .day, value: w * 7 + d, to: first) ?? first
                        let info = byDate[date]
                        let strength = info.map { 0.18 + 0.6 * min(abs($0.net) / scale, 1) } ?? 0
                        Button { day = day == date ? nil : date } label: {
                            VStack(spacing: 1) {
                                Text("\(cal.component(.day, from: date))").font(.system(size: 10)).foregroundStyle(date > today ? Theme.dim : Theme.muted)
                                Text(info.map { f.signedUsd($0.net, decimals: 0) } ?? " ").mono(10, .semibold).foregroundStyle(Theme.text)
                                    .lineLimit(1).minimumScaleFactor(0.6)
                            }
                            .frame(maxWidth: .infinity, minHeight: 34)
                            .background(RoundedRectangle(cornerRadius: 5).fill(info.map { Theme.pnl($0.net).opacity(strength) } ?? Color.white.opacity(0.03)))
                            .overlay(RoundedRectangle(cornerRadius: 5).stroke(day == date ? Theme.text : Color.clear))
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .disabled(info == nil)
                    }
                }
            }
            if let day {
                let list = trades.filter { cal.startOfDay(for: $0.closeTime) == day }.sorted { $0.closeTime < $1.closeTime }
                VStack(spacing: 2) {
                    ForEach(list) { t in
                        Button { state.show(trade: t) } label: {
                            HStack(spacing: 8) {
                                SidePill(isLong: t.isLong)
                                Text(t.coin).font(.system(size: 12, weight: .semibold))
                                Text(t.closeTime.formatted(date: .omitted, time: .shortened)).mono(10.5).foregroundStyle(Theme.muted)
                                Spacer()
                                if let r = t.rMultiple { Text(Fmt.number(r, decimals: 1) + "R").mono(11).foregroundStyle(Theme.muted) }
                                Text(f.signedUsd(t.netPnl, decimals: 2)).mono(12, .semibold).foregroundStyle(Theme.pnl(t.netPnl))
                                Image(systemName: "chevron.right").font(.system(size: 9, weight: .bold)).foregroundStyle(Theme.dim)
                            }
                            .padding(.vertical, 4)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .help(T("Toon deze trade in de chart"))
                    }
                }
                .padding(.top, 6)
            }
        }
    }
}
#endif
