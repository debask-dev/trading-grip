#if os(macOS)
import SwiftUI
import AppKit
import GripCore

struct MainView: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        Group {
            switch state.tab {
            case .trade: TradeScreen()
            case .history: HistoryView()
            case .portfolio: PortfolioView()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.bg)
        .toolbar {
            ToolbarItem(placement: .navigation) {
                CoinPicker()
            }
            ToolbarItem(placement: .principal) {
                Picker("Weergave", selection: $state.tab) {
                    ForEach(MainTab.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
                .frame(width: 270)
            }
            ToolbarItemGroup(placement: .primaryAction) {
                NetworkBadge()
                Button {
                    state.hideAmounts.toggle()
                } label: {
                    Label(state.hideAmounts ? "Bedragen tonen" : "Bedragen verbergen", systemImage: state.hideAmounts ? "eye.slash.fill" : "eye")
                }
                .help("Bedragen verbergen voor screenshots (⇧⌘H)")
                SettingsLink {
                    Label("Instellingen", systemImage: "gearshape")
                }
                .help("Instellingen (⌘,)")
            }
        }
        .overlay(alignment: .top) { ToastStack().padding(.top, 10) }
        .sheet(isPresented: $state.showOnboarding) { OnboardingView() }
        .task { await state.start() }
    }
}

struct NetworkBadge: View {
    @EnvironmentObject var state: AppState
    var body: some View {
        HStack(spacing: 6) {
            Circle().fill(state.streamConnected ? Theme.green : Theme.orange).frame(width: 7, height: 7)
            Text(state.paperMode ? "OEFENEN" : (state.network == .mainnet ? "MAINNET" : "TESTNET"))
                .font(.system(size: 10.5, weight: .bold))
                .foregroundStyle(badgeColor)
        }
        .padding(.horizontal, 8).padding(.vertical, 4)
        .background(RoundedRectangle(cornerRadius: 6).fill(badgeColor.opacity(0.14)))
        .help(state.streamConnected ? "Live verbonden met Hyperliquid \(state.network.label)" : "Verbinden…")
    }
}

extension NetworkBadge {
    var badgeColor: Color { state.paperMode ? Theme.accent : (state.network == .mainnet ? Theme.red : Theme.orange) }
}

struct CoinPicker: View {
    @EnvironmentObject var state: AppState
    @State private var open = false
    @State private var query = ""

    var body: some View {
        Button {
            open.toggle()
        } label: {
            HStack(spacing: 6) {
                Text("\(state.coin)-PERP").font(.system(size: 13, weight: .semibold))
                Image(systemName: "chevron.down").font(.system(size: 9, weight: .bold)).foregroundStyle(Theme.muted)
            }
            .padding(.horizontal, 6)
        }
        .help("Kies markt")
        .popover(isPresented: $open, arrowEdge: .bottom) {
            VStack(spacing: 8) {
                TextField("Zoek markt", text: $query)
                    .textFieldStyle(.roundedBorder)
                List(filtered) { a in
                    Button {
                        state.coin = a.name
                        open = false
                        query = ""
                    } label: {
                        HStack {
                            Text(a.name).font(.system(size: 13, weight: .semibold))
                            Text("\(a.maxLeverage)×").font(.system(size: 10)).foregroundStyle(Theme.muted)
                            Spacer()
                            if let c = state.contexts[a.name] {
                                Text(Fmt.price(c.markPx)).mono(12)
                                Text(Fmt.percent(c.change24h, decimals: 1)).mono(11).foregroundStyle(Theme.pnl(c.change24h)).frame(width: 58, alignment: .trailing)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                .listStyle(.plain)
            }
            .padding(10)
            .frame(width: 330, height: 420)
        }
    }

    private var filtered: [AssetInfo] {
        let q = query.trimmingCharacters(in: .whitespaces).uppercased()
        return q.isEmpty ? state.assets : state.assets.filter { $0.name.uppercased().contains(q) }
    }
}

struct ToastStack: View {
    @EnvironmentObject var state: AppState
    var body: some View {
        VStack(spacing: 8) {
            ForEach(state.toasts) { t in
                HStack(spacing: 10) {
                    Circle().fill(color(t.kind)).frame(width: 8, height: 8)
                    Text(t.text).font(.system(size: 12.5)).foregroundStyle(Theme.text)
                }
                .padding(.horizontal, 16).padding(.vertical, 10)
                .background(RoundedRectangle(cornerRadius: 10).fill(Theme.card.opacity(0.97)))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.line))
                .shadow(color: .black.opacity(0.35), radius: 14, y: 6)
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .allowsHitTesting(false)
    }

    private func color(_ k: Toast.Kind) -> Color {
        switch k {
        case .success: return Theme.green
        case .error: return Theme.red
        case .info: return Theme.blue
        }
    }
}

// MARK: - Trade screen

struct TradeScreen: View {
    @EnvironmentObject var state: AppState
    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                ChartHeader()
                Divider().overlay(Theme.line)
                ChartView(state: state)
                    .overlay(alignment: .top) {
                        if let line = state.selectedLine {
                            LineToolbar(line: line).padding(.top, 34)
                        }
                    }
            }
            Divider().overlay(Theme.line)
            TradePanel()
                .frame(width: 320)
                .background(Theme.panel)
        }
    }
}

struct ChartHeader: View {
    @EnvironmentObject var state: AppState
    var body: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 1) {
                Text(Fmt.price(state.price)).mono(17, .semibold)
                Text(Fmt.percent(state.change24h) + " 24u").mono(11).foregroundStyle(Theme.pnl(state.change24h))
            }
            .frame(minWidth: 110, alignment: .leading)

            HStack(spacing: 2) {
                ForEach(Timeframe.allCases) { tf in
                    Button {
                        state.timeframe = tf
                    } label: {
                        Text(tf.label)
                            .font(.system(size: 12, weight: .semibold))
                            .frame(minWidth: 30)
                            .padding(.vertical, 5)
                            .background(RoundedRectangle(cornerRadius: 6).fill(state.timeframe == tf ? Theme.card : .clear))
                            .foregroundStyle(state.timeframe == tf ? Theme.text : Theme.muted)
                    }
                    .buttonStyle(.plain)
                    .demoAnchor("tf-\(tf.rawValue)")
                }
            }
            .padding(3)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.black.opacity(0.25)))

            Divider().frame(height: 22)

            HStack(spacing: 4) {
                ToolButton(icon: "cursorarrow", active: state.tool == .cursor, help: "Aanwijzer") { state.tool = .cursor }
                ToolButton(icon: "line.diagonal", active: state.tool == .trendline, help: "Trendlijn (⌥T). Houd ⌘ ingedrukt om te snappen op open/high/low/close.") {
                    state.tool = state.tool == .trendline ? .cursor : .trendline
                }
                .demoAnchor("tool-trend")
                ToolButton(icon: NSImage(systemSymbolName: "magnet", accessibilityDescription: nil) != nil ? "magnet" : "scope",
                           active: state.magnet, help: "Magneet: snap op open/high/low/close van candles (⌘ zet tijdelijk om)") {
                    state.magnet.toggle()
                }
                .demoAnchor("tool-magnet")
                if !state.coinTrendlines.isEmpty {
                    Menu {
                        Button("Wis alle trendlijnen voor \(state.coin)", role: .destructive) { state.clearTrendlines() }
                    } label: {
                        Image(systemName: "trash").font(.system(size: 12))
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                    .help("Trendlijnen wissen")
                }
            }

            if state.tool == .trendline {
                Text("Klik en sleep om te tekenen · houd **⌘** ingedrukt om te snappen op candle/wick · Esc = stoppen")
                    .font(.system(size: 11.5))
                    .foregroundStyle(Theme.orange)
                    .lineLimit(1)
            } else if state.selectedTrendline != nil {
                Text("Sleep de uiteinden om aan te passen · ⌫ verwijdert")
                    .font(.system(size: 11.5))
                    .foregroundStyle(Theme.muted)
                    .lineLimit(1)
            } else {
                Text("⇧-klik = meten")
                    .font(.system(size: 11.5))
                    .foregroundStyle(Theme.dim)
                    .lineLimit(1)
                    .help("Houd ⇧ ingedrukt en klik in de chart, beweeg de muis en klik nog eens: % omhoog/omlaag, aantal candles en tijd.")
            }

            Spacer()
            if state.loadingCandles { ProgressView().controlSize(.small) }
        }
        .padding(.horizontal, 14)
        .frame(height: 50)
        .background(Theme.panel)
    }
}

struct ToolButton: View {
    var icon: String
    var active: Bool
    var help: String
    var action: () -> Void
    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .medium))
                .frame(width: 30, height: 26)
                .background(RoundedRectangle(cornerRadius: 6).fill(active ? Theme.accent.opacity(0.3) : .clear))
                .foregroundStyle(active ? Theme.text : Theme.muted)
        }
        .buttonStyle(.plain)
        .help(help)
    }
}
#endif
