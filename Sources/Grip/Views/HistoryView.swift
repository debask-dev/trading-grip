#if os(macOS)
import SwiftUI
import AppKit
import UniformTypeIdentifiers
import GripCore

struct HistoryView: View {
    @EnvironmentObject var state: AppState
    @State private var coinFilter = "Alle"
    @State private var periodDays = 0
    @State private var expanded: Set<String> = []

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
                Button { exportCSV() } label: { Label("CSV", systemImage: "square.and.arrow.up") }
                    .disabled(trades.isEmpty)
                    .help("Exporteer deze trades als CSV")
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
                StatTile(title: "Fees", value: f.usd(-stats.fees), color: Theme.muted)
                StatTile(title: "Funding", value: f.signedUsd(stats.funding, decimals: 2), color: Theme.pnl(stats.funding))
            }

            Text("Netto = resultaat van de prijs − fees (in en uit) + funding. Gem. exit is volume-gewogen over alle TP's, stop en handmatige exits.")
                .font(.system(size: 11)).foregroundStyle(Theme.dim)

            if !state.hasAccount {
                EmptyState(icon: "person.crop.circle.badge.questionmark", text: "Koppel je account (⇧⌘A) om je tradehistorie te zien.")
            } else if trades.isEmpty {
                EmptyState(icon: "clock.arrow.circlepath", text: state.loadingHistory ? "Historie laden…" : "Nog geen afgeronde trades in deze periode.")
            } else {
                header
                ScrollView {
                    LazyVStack(spacing: 6) {
                        ForEach(trades) { t in
                            TradeRow(trade: t, expanded: expanded.contains(t.id)) {
                                if expanded.contains(t.id) { expanded.remove(t.id) } else { expanded.insert(t.id) }
                            }
                        }
                    }
                }
            }
        }
        .padding(22)
    }

    private var header: some View {
        HStack(spacing: 0) {
            Group {
                Text("").frame(width: 22)
                Text("Gesloten").frame(width: 120, alignment: .leading)
                Text("Markt").frame(width: 70, alignment: .leading)
                Text("Gem. entry → exit").frame(minWidth: 170, alignment: .leading)
                Spacer(minLength: 8)
                Text("In/uit").frame(width: 56, alignment: .trailing)
                Text("Bruto").frame(width: 84, alignment: .trailing)
                Text("Fees").frame(width: 70, alignment: .trailing)
                Text("Funding").frame(width: 70, alignment: .trailing)
            }
            Group {
                Text("Netto").frame(width: 92, alignment: .trailing)
                Text("R").frame(width: 56, alignment: .trailing)
                Text("Duur").frame(width: 76, alignment: .trailing)
                Text("").frame(width: 34)
            }
        }
        .font(.system(size: 10.5, weight: .semibold)).foregroundStyle(Theme.muted)
        .padding(.horizontal, 12)
    }

    private func exportCSV() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.commaSeparatedText]
        panel.nameFieldStringValue = "grip-trades.csv"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        var rows = ["trade_id,coin,side,open_time,close_time,size,avg_entry,avg_exit,entries,exits,gross_pnl,fees,funding,net_pnl,r_multiple,executions"]
        let iso = ISO8601DateFormatter()
        for t in trades {
            let ex = t.executions.map { "\($0.label) \($0.isBuy ? "buy" : "sell") \($0.size)@\($0.price)" }.joined(separator: " | ")
            rows.append([t.id, t.coin, t.isLong ? "long" : "short", iso.string(from: t.openTime), iso.string(from: t.closeTime),
                         "\(t.size)", "\(t.avgEntry)", "\(t.avgExit)", "\(t.entries.count)", "\(t.exits.count)",
                         "\(t.grossPnl)", "\(t.fees)", "\(t.funding)", "\(t.netPnl)", t.rMultiple.map { "\($0)" } ?? "", "\"\(ex)\""].joined(separator: ","))
        }
        do {
            try rows.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
            state.toast("\(trades.count) trades geëxporteerd", .success)
        } catch {
            state.toast("Exporteren mislukt: \(error.localizedDescription)", .error)
        }
    }
}

struct TradeRow: View {
    @EnvironmentObject var state: AppState
    let trade: ClosedTrade
    let expanded: Bool
    let toggle: () -> Void
    @State private var hovering = false

    var body: some View {
        let t = trade
        let f = state.fmt
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                Group {
                    Image(systemName: expanded ? "chevron.down" : "chevron.right").font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Theme.muted).frame(width: 22)
                    Text(t.closeTime.formatted(.dateTime.day().month(.abbreviated).hour().minute())).frame(width: 120, alignment: .leading)
                    HStack(spacing: 6) { Text(t.coin).fontWeight(.semibold); SidePill(isLong: t.isLong) }.frame(width: 70, alignment: .leading)
                    Text("\(Fmt.price(t.avgEntry)) → \(Fmt.price(t.avgExit))").monospacedDigit().frame(minWidth: 170, alignment: .leading)
                    Spacer(minLength: 8)
                    Text("\(t.entries.count)/\(t.exits.count)").monospacedDigit().foregroundStyle(Theme.muted).frame(width: 56, alignment: .trailing)
                        .help("\(t.entries.count) keer ingestapt, \(t.exits.count) keer uitgestapt")
                    Text(f.signedUsd(t.grossPnl, decimals: 2)).monospacedDigit().frame(width: 84, alignment: .trailing)
                    Text(f.usd(-t.fees, decimals: 2)).monospacedDigit().foregroundStyle(Theme.muted).frame(width: 70, alignment: .trailing)
                    Text(t.funding == 0 ? "–" : f.signedUsd(t.funding, decimals: 2)).monospacedDigit().foregroundStyle(Theme.muted).frame(width: 70, alignment: .trailing)
                }
                Group {
                    Text(f.signedUsd(t.netPnl, decimals: 2)).monospacedDigit().fontWeight(.semibold).foregroundStyle(Theme.pnl(t.netPnl)).frame(width: 92, alignment: .trailing)
                    Text(t.rMultiple.map { Fmt.number($0, decimals: 2) + "R" } ?? "–").monospacedDigit().frame(width: 56, alignment: .trailing)
                    Text(duration(t.duration)).foregroundStyle(Theme.muted).frame(width: 76, alignment: .trailing)
                    Button { state.show(trade: t) } label: { Image(systemName: "chart.xyaxis.line") }
                        .buttonStyle(HoverButtonStyle(active: false)).frame(width: 34).help("Toon in chart")
                }
            }
            .font(.system(size: 12.5))
            .padding(.horizontal, 12).padding(.vertical, 9)
            .contentShape(Rectangle())
            .onTapGesture(perform: toggle)

            if expanded {
                VStack(spacing: 4) {
                    ForEach(t.executions) { e in
                        HStack(spacing: 0) {
                            Text(e.label).fontWeight(.bold).foregroundStyle(e.role == .entry ? Theme.blue : (e.kind == .stopLoss ? Theme.red : Theme.green))
                                .frame(width: 60, alignment: .leading)
                            Text(Date(timeIntervalSince1970: Double(e.time) / 1000).formatted(.dateTime.day().month(.abbreviated).hour().minute().second()))
                                .frame(width: 150, alignment: .leading).foregroundStyle(Theme.muted)
                            Text("\(e.isBuy ? "Koop" : "Verkoop") \(f.size(e.size, coin: e.coin, decimals: 4))").frame(width: 170, alignment: .leading)
                            Text("@ \(Fmt.price(e.price))").monospacedDigit().frame(width: 110, alignment: .leading)
                            Text(kindName(e)).foregroundStyle(Theme.muted).frame(width: 110, alignment: .leading)
                            Spacer()
                            Text("fee \(f.usd(e.fee, decimals: 2))").monospacedDigit().foregroundStyle(Theme.dim).frame(width: 90, alignment: .trailing)
                            Text(e.role == .exit ? f.signedUsd(e.closedPnl - e.fee, decimals: 2) : "").monospacedDigit()
                                .foregroundStyle(Theme.pnl(e.closedPnl - e.fee)).frame(width: 96, alignment: .trailing)
                        }
                        .font(.system(size: 11.5))
                    }
                    if let risk = t.plannedRiskUsd {
                        HStack {
                            Text("Gepland risico \(f.usd(risk, decimals: 2)) · grootste positie \(f.size(t.size, coin: t.coin, decimals: 4))")
                            Spacer()
                        }
                        .font(.system(size: 11)).foregroundStyle(Theme.dim)
                    }
                }
                .padding(.horizontal, 34).padding(.bottom, 10)
            }
        }
        .background(RoundedRectangle(cornerRadius: 9).fill(hovering || expanded ? Theme.card : Theme.card.opacity(0.55)))
        .overlay(RoundedRectangle(cornerRadius: 9).stroke(expanded ? Theme.line : .clear))
        .onHover { hovering = $0 }
    }

    private func kindName(_ e: Execution) -> String {
        switch e.kind {
        case .limit?: return "limit"
        case .market?: return "market"
        case .takeProfit?: return "take-profit"
        case .stopLoss?: return "stop-loss"
        case .liquidation?: return "liquidatie"
        case nil: return ""
        }
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
