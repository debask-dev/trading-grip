#if os(macOS)
import SwiftUI
import Charts
import GripCore

struct PortfolioView: View {
    @EnvironmentObject var state: AppState
    @State private var period: PortfolioPeriod = .month

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
                        StatTile(title: T("Accountwaarde"), value: f.usd(end))
                        StatTile(title: T("PnL \(period.label.lowercased())"), value: f.signedUsd(pnlTotal), color: Theme.pnl(pnlTotal))
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
                                RuleMark(y: .value(T("Nul"), 0)).foregroundStyle(Theme.dim.opacity(0.4))
                            }
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
                            }
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
                                    .symbolSize(18)
                            }
                            .chartXAxisLabel(T("Trade #"))
                            .chartYAxis(state.hideAmounts ? .hidden : .automatic)
                            .frame(height: 200)
                        }
                    }
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
