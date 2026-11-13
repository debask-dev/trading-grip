#if os(macOS)
import SwiftUI
import GripCore

struct HistoryView: View {
    @EnvironmentObject var state: AppState
    @State private var coinFilter = "Alle"
    @State private var periodDays = 0

    private var trades: [ClosedTrade] {
        var t = state.closedTrades
        if coinFilter != "Alle" { t = t.filter { $0.coin == coinFilter } }
        if periodDays > 0 {
            let from = Date().addingTimeInterval(-Double(periodDays) * 86400)
            t = t.filter { $0.closeTime >= from }
        }
        return t
    }

    var body: some View {
        let stats = TradeStats.from(trades)
        let f = state.fmt
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Afgeronde trades").font(.system(size: 20, weight: .bold))
                Spacer()
                Picker("Periode", selection: $periodDays) {
                    Text("7 dagen").tag(7)
                    Text("30 dagen").tag(30)
                    Text("90 dagen").tag(90)
                    Text("Alles").tag(0)
                }
                .frame(width: 170)
                Picker("Markt", selection: $coinFilter) {
                    Text("Alle").tag("Alle")
                    ForEach(Array(Set(state.closedTrades.map { $0.coin })).sorted(), id: \.self) { Text($0).tag($0) }
                }
                .frame(width: 150)
                Button {
                    Task { await state.refreshHistory() }
                } label: {
                    if state.loadingHistory { ProgressView().controlSize(.small) } else { Image(systemName: "arrow.clockwise") }
                }
                .help("Vernieuwen")
            }

            HStack(spacing: 12) {
                StatTile(title: "Netto PnL", value: f.signedUsd(stats.netPnl), color: Theme.pnl(stats.netPnl))
                StatTile(title: "Trades", value: "\(stats.count)")
                StatTile(title: "Winrate", value: Fmt.percent(stats.winRate, decimals: 0, signed: false))
                StatTile(title: "Profit factor", value: stats.profitFactor.map { Fmt.number($0, decimals: 2) } ?? "–")
                StatTile(title: "Gem. R", value: stats.avgR.map { (($0 >= 0) ? "+" : "") + Fmt.number($0, decimals: 2) + "R" } ?? "–")
                StatTile(title: "Gem. winst / verlies", value: f.signedUsd(stats.avgWin) + " / " + f.signedUsd(stats.avgLoss))
                StatTile(title: "Fees", value: f.usd(-stats.fees), color: Theme.muted)
            }

            if !state.hasAccount {
                EmptyState(icon: "person.crop.circle.badge.questionmark", text: "Koppel je wallet-adres in Instellingen om je tradehistorie te zien.")
            } else if trades.isEmpty {
                EmptyState(icon: "clock.arrow.circlepath", text: state.loadingHistory ? "Historie laden…" : "Nog geen afgeronde trades in deze periode.")
            } else {
                Table(trades) {
                    TableColumn("Gesloten") { t in Text(t.closeTime.formatted(.dateTime.day().month(.abbreviated).hour().minute())) }
                        .width(min: 110, ideal: 120)
                    TableColumn("Markt") { t in Text(t.coin).fontWeight(.semibold) }
                        .width(min: 50, ideal: 60)
                    TableColumn("Richting") { t in SidePill(isLong: t.isLong) }
                        .width(min: 60, ideal: 64)
                    TableColumn("Grootte") { t in Text(f.size(t.size, coin: "", decimals: 4)).monospacedDigit() }
                    TableColumn("Entry") { t in Text(Fmt.price(t.avgEntry)).monospacedDigit() }
                    TableColumn("Exit") { t in Text(Fmt.price(t.avgExit)).monospacedDigit() }
                    TableColumn("Netto PnL") { t in Text(f.signedUsd(t.netPnl, decimals: 2)).monospacedDigit().foregroundStyle(Theme.pnl(t.netPnl)) }
                    TableColumn("Rendement") { t in Text(Fmt.percent(t.returnOnNotional)).monospacedDigit().foregroundStyle(Theme.pnl(t.netPnl)) }
                    TableColumn("R") { t in Text(t.rMultiple.map { Fmt.number($0, decimals: 2) + "R" } ?? "–").monospacedDigit() }
                        .width(min: 44, ideal: 54)
                    TableColumn("Duur") { t in Text(duration(t.duration)).foregroundStyle(Theme.muted) }
                }
                .tableStyle(.inset(alternatesRowBackgrounds: true))
                .scrollContentBackground(.hidden)
                .background(RoundedRectangle(cornerRadius: 12).fill(Theme.card))
            }
        }
        .padding(22)
    }

    private func duration(_ s: TimeInterval) -> String {
        let m = Int(s / 60)
        if m < 60 { return "\(max(m, 1)) min" }
        let h = m / 60
        if h < 48 { return "\(h) u \(m % 60) m" }
        return "\(h / 24) d \(h % 24) u"
    }
}

struct StatTile: View {
    var title: String
    var value: String
    var color: Color = Theme.text
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title.uppercased()).font(.system(size: 10, weight: .semibold)).tracking(0.7).foregroundStyle(Theme.muted)
            Text(value).mono(16, .semibold).foregroundStyle(color).lineLimit(1).minimumScaleFactor(0.6)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10).fill(Theme.card))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.line))
    }
}

struct EmptyState: View {
    var icon: String
    var text: String
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: icon).font(.system(size: 34)).foregroundStyle(Theme.dim)
            Text(text).foregroundStyle(Theme.muted)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
#endif
