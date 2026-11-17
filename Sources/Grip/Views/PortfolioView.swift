#if os(macOS)
import SwiftUI
import Charts
import GripCore

struct PortfolioView: View {
    @EnvironmentObject var state: AppState
    @State private var period: PortfolioPeriod = .month
    @State private var pnlHover: Date?
    @State private var valueHover: Date?
    @State private var tradeHover: Int?

    var body: some View {
        let series = state.portfolio[period]
        let values = series?.accountValue ?? []
        let pnl = series?.pnl ?? []
        let start = values.first?.value ?? 0
        let end = values.last?.value ?? state.account.accountValue
        let pnlTotal = pnl.last?.value ?? 0
        let pnlPct = start > 0 ? pnlTotal / start : 0
        let f = state.fmt
        let curve = TradeBuilder.equityCurve(state.closedTrades)
        let trades = state.closedTrades.sorted { $0.closeTime < $1.closeTime }
        let pnlPoint = pnlHover.flatMap { nearest($0, in: pnl) }
        let valuePoint = valueHover.flatMap { nearest($0, in: values) }

        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    Text(T("Portfolio")).font(.system(size: 20, weight: .bold))
                    Spacer()
                    Picker("", selection: $period) {
                        ForEach(PortfolioPeriod.allCases) { Text(T($0.label)).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(width: 300)
                }

                if !state.hasAccount {
                    EmptyState(icon: "chart.xyaxis.line", text: T("Koppel je account (klik rechtsboven op ACCOUNT KOPPELEN of ⇧⌘A) om je portfolio te zien."))
                        .frame(height: 300)
                } else {
                    HStack(spacing: 12) {
                        StatTile(title: T("Accountwaarde"), value: f.usd(end, decimals: abs(end) < 1000 ? 2 : 0))
                        StatTile(title: T("PnL \(period.label.lowercased())"), value: f.signedUsd(pnlTotal, decimals: abs(pnlTotal) < 100 ? 2 : 0), color: Theme.pnl(pnlTotal))
                        StatTile(title: T("Rendement"), value: Fmt.percent(pnlPct), color: Theme.pnl(pnlPct))
                        StatTile(title: T("Open posities"), value: "\(state.account.positions.count)")
                    }

                    ChartCard(title: T("Winst / verlies (\(period.label.lowercased()))")) {
                        if pnl.isEmpty {
                            Text(T("Nog geen data.")).foregroundStyle(Theme.muted).frame(maxWidth: .infinity, minHeight: 220)
                        } else {
                            Chart(pnl) { p in
                                AreaMark(x: .value(T("Tijd"), p.time), y: .value(T("PnL"), p.value))
                                    .foregroundStyle(LinearGradient(colors: [Theme.pnl(pnlTotal).opacity(0.35), Theme.pnl(pnlTotal).opacity(0.02)], startPoint: .top, endPoint: .bottom))
                                LineMark(x: .value(T("Tijd"), p.time), y: .value(T("PnL"), p.value))
                                    .foregroundStyle(Theme.pnl(pnlTotal))
                                    .lineStyle(StrokeStyle(lineWidth: 2))
                                if pnl.count <= 160 {
                                    PointMark(x: .value(T("Tijd"), p.time), y: .value(T("PnL"), p.value))
                                        .foregroundStyle(Theme.pnl(pnlTotal)).symbolSize(16)
                                }
                                RuleMark(y: .value(T("Nul"), 0)).foregroundStyle(Theme.dim.opacity(0.4))
                                if let h = pnlPoint, h.id == p.id {
                                    RuleMark(x: .value(T("Tijd"), h.time))
                                        .foregroundStyle(Theme.muted.opacity(0.5))
                                        .annotation(position: .top, spacing: 4, overflowResolution: .init(x: .fit(to: .chart), y: .disabled)) {
                                            HoverTip(lines: [dateText(h.time), f.signedUsd(h.value, decimals: 2) + "  ·  " + Fmt.percent(start > 0 ? h.value / start : 0)],
                                                     color: Theme.pnl(h.value), hide: state.hideAmounts)
                                        }
                                    PointMark(x: .value(T("Tijd"), h.time), y: .value(T("PnL"), h.value))
                                        .foregroundStyle(Theme.pnl(h.value)).symbolSize(40)
                                }
                            }
                            .chartXSelection(value: $pnlHover)
                            .chartYAxis(state.hideAmounts ? .hidden : .automatic)
                            .frame(height: 240)
                        }
                    }

                    ChartCard(title: T("Accountwaarde")) {
                        if values.isEmpty {
                            Text(T("Nog geen data.")).foregroundStyle(Theme.muted).frame(maxWidth: .infinity, minHeight: 200)
                        } else {
                            Chart(values) { p in
                                LineMark(x: .value(T("Tijd"), p.time), y: .value(T("Waarde"), p.value))
                                    .foregroundStyle(Theme.blue)
                                    .lineStyle(StrokeStyle(lineWidth: 2))
                                if values.count <= 160 {
                                    PointMark(x: .value(T("Tijd"), p.time), y: .value(T("Waarde"), p.value))
                                        .foregroundStyle(Theme.blue).symbolSize(16)
                                }
                                if let h = valuePoint, h.id == p.id {
                                    RuleMark(x: .value(T("Tijd"), h.time))
                                        .foregroundStyle(Theme.muted.opacity(0.5))
                                        .annotation(position: .top, spacing: 4, overflowResolution: .init(x: .fit(to: .chart), y: .disabled)) {
                                            let change = h.value - start
                                            HoverTip(lines: [dateText(h.time), f.usd(h.value, decimals: 2) + "  ·  " + f.signedUsd(change, decimals: 2)],
                                                     color: Theme.blue, hide: state.hideAmounts)
                                        }
                                    PointMark(x: .value(T("Tijd"), h.time), y: .value(T("Waarde"), h.value))
                                        .foregroundStyle(Theme.blue).symbolSize(40)
                                }
                            }
                            .chartXSelection(value: $valueHover)
                            .chartYScale(domain: .automatic(includesZero: false))
                            .chartYAxis(state.hideAmounts ? .hidden : .automatic)
                            .frame(height: 200)
                        }
                    }

                    ChartCard(title: T("Gerealiseerde winst per trade (cumulatief, na fees)")) {
                        if curve.isEmpty {
                            Text(T("Nog geen afgeronde trades.")).foregroundStyle(Theme.muted).frame(maxWidth: .infinity, minHeight: 200)
                        } else {
                            Chart(Array(curve.enumerated()), id: \.offset) { item in
                                LineMark(x: .value(T("Trade"), item.offset + 1), y: .value(T("Cumulatief"), item.element.value))
                                    .foregroundStyle(Theme.accent)
                                    .interpolationMethod(.stepEnd)
                                PointMark(x: .value(T("Trade"), item.offset + 1), y: .value(T("Cumulatief"), item.element.value))
                                    .foregroundStyle(Theme.accent)
                                    .symbolSize(tradeHover == item.offset + 1 ? 60 : 18)
                                if let n = tradeHover, n == item.offset + 1, trades.indices.contains(item.offset) {
                                    let t = trades[item.offset]
                                    RuleMark(x: .value(T("Trade"), n))
                                        .foregroundStyle(Theme.muted.opacity(0.5))
                                        .annotation(position: .top, spacing: 4, overflowResolution: .init(x: .fit(to: .chart), y: .disabled)) {
                                            HoverTip(lines: [T("#\(n) · \(t.coin) \(t.isLong ? "long" : "short") · \(dateText(t.closeTime))"),
                                                             T("Trade \(f.signedUsd(t.netPnl, decimals: 2))") + (t.rMultiple.map { " · " + Fmt.number($0, decimals: 1) + "R" } ?? ""),
                                                             T("Totaal \(f.signedUsd(item.element.value, decimals: 2))")],
                                                     color: Theme.pnl(t.netPnl), hide: state.hideAmounts)
                                        }
                                }
                            }
                            .chartXSelection(value: Binding(get: { tradeHover }, set: { tradeHover = $0.map { min(max($0, 1), curve.count) } }))
                            .chartXAxisLabel(T("Trade #"))
                            .chartYAxis(state.hideAmounts ? .hidden : .automatic)
                            .frame(height: 200)
                        }
                    }
                    // Figures over the closed trades of the chosen period.
                    PortfolioStats(trades: state.closedTrades.filter { $0.closeTime >= periodStart })
                    if state.hideAmounts {
                        Label(T("Bedragen zijn verborgen – je kunt deze pagina veilig screenshotten."), systemImage: "eye.slash")
                            .font(.system(size: 11.5)).foregroundStyle(Theme.muted)
                    }
                }
            }
            .padding(22)
        }
    }
}

extension PortfolioView {
    /// Start of the chosen period (for the trade figures).
    var periodStart: Date {
        switch period {
        case .day: return Date().addingTimeInterval(-86_400)
        case .week: return Date().addingTimeInterval(-7 * 86_400)
        case .month: return Date().addingTimeInterval(-30 * 86_400)
        case .allTime: return .distantPast
        }
    }

    /// The data point closest in time to where the mouse is.
    func nearest(_ t: Date, in pts: [PortfolioSeries.Point]) -> PortfolioSeries.Point? {
        pts.min { abs($0.time.timeIntervalSince(t)) < abs($1.time.timeIntervalSince(t)) }
    }

    func dateText(_ d: Date) -> String {
        d.formatted(Date.FormatStyle(date: .abbreviated, time: period == .day || period == .week ? .shortened : .omitted)
            .locale(Locale(identifier: L10n.isEnglish ? "en_US" : "nl_NL")))
    }
}

/// Small card above the hovered point in the portfolio charts. With hidden amounts only the first line (the date) shows.
struct HoverTip: View {
    let lines: [String]
    var color: Color = Theme.text
    var hide = false
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(Array((hide ? Array(lines.prefix(1)) : lines).enumerated()), id: \.offset) { i, l in
                Text(l).font(.system(size: i == 0 ? 10.5 : 11.5, weight: i == 0 ? .regular : .semibold, design: i == 0 ? .default : .monospaced))
                    .foregroundStyle(i == 0 ? Theme.muted : color)
            }
        }
        .padding(.horizontal, 8).padding(.vertical, 5)
        .background(RoundedRectangle(cornerRadius: 6).fill(Theme.panel))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Theme.line))
    }
}

struct ChartCard<Content: View>: View {
    var title: String
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.muted)
            content
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 12).fill(Theme.card))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.line))
    }
}
#endif
