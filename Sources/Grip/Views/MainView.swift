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
        .sheet(isPresented: $state.showShortcuts) { ShortcutsView() }
        .alert("Let op", isPresented: Binding(get: { state.securityNotice != nil }, set: { if !$0 { state.securityNotice = nil } })) {
            Button("Begrepen") { state.securityNotice = nil }
        } message: {
            Text(state.securityNotice ?? "")
        }
        .task { await state.start() }
    }
}

/// Toolbar button that shows the connection status and opens the accounts window.
struct NetworkBadge: View {
    @EnvironmentObject var state: AppState
    @Environment(\.openWindow) private var openWindow
    @State private var hovering = false

    var body: some View {
        Button { openWindow(id: "accounts") } label: {
            HStack(spacing: 7) {
                Circle().fill(dotColor).frame(width: 7, height: 7)
                Text(title).font(.system(size: 11, weight: .bold)).foregroundStyle(badgeColor)
                if let sub = subtitle {
                    Text(sub).font(.system(size: 11, weight: .medium, design: .monospaced)).foregroundStyle(Theme.muted)
                }
            }
            .padding(.horizontal, 9).padding(.vertical, 4)
            .background(RoundedRectangle(cornerRadius: 6).fill(badgeColor.opacity(hovering ? 0.24 : 0.14)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(helpText)
    }

    private var title: String {
        switch state.connectionStatus {
        case .paper: return "OEFENEN"
        case .none: return "ACCOUNT KOPPELEN"
        default: return state.network.isMainnet ? "MAINNET" : "TESTNET"
        }
    }

    private var subtitle: String? {
        guard let a = state.activeAccount, !state.paperMode else { return nil }
        return Credentials.mask(a.address)
    }

    private var dotColor: Color {
        switch state.connectionStatus {
        case .trading: return state.streamConnected ? Theme.green : Theme.orange
        case .readOnly: return Theme.orange
        case .error: return Theme.red
        case .paper: return Theme.accent
        case .none: return Theme.dim
        }
    }

    private var helpText: String {
        switch state.connectionStatus {
        case .trading: return "Verbonden: handelen werkt. Klik om accounts te beheren."
        case .readOnly: return "Verbonden, alleen-lezen (geen API-wallet). Klik om er een toe te voegen."
        case .error(let e): return "Probleem met de verbinding: \(e)"
        case .paper: return "Oefenmodus: gesimuleerde orders. Klik om een account te koppelen."
        case .none: return "Koppel je Hyperliquid-account."
        }
    }
}

extension NetworkBadge {
    var badgeColor: Color {
        if state.paperMode { return Theme.accent }
        if state.activeAccount == nil { return Theme.blue }
        return state.network == .mainnet ? Theme.red : Theme.orange
    }
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
                ForEach(Array(Timeframe.allCases.enumerated()), id: \.element) { i, tf in
                    Button {
                        state.timeframe = tf
                    } label: {
                        Text(tf.label)
                            .font(.system(size: 12, weight: .semibold))
                            .frame(minWidth: 32, minHeight: 24)
                    }
                    .buttonStyle(HoverButtonStyle(active: state.timeframe == tf, activeFill: Theme.card))
                    .help("Timeframe \(tf.label) (⌘\(i + 1) · of typ \(typedHint(tf)) + ⏎ in de chart)")
                    .demoAnchor("tf-\(tf.rawValue)")
                }
            }
            .padding(3)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.black.opacity(0.25)))

            Divider().frame(height: 22)

            HStack(spacing: 4) {
                ToolButton(icon: "cursorarrow", active: state.tool == .cursor, help: "Aanwijzer (Esc)") { state.tool = .cursor }
                ToolButton(icon: "line.diagonal", active: state.tool == .trendline, help: "Trendlijn (⌥T, nog eens ⌥T = terug)") {
                    state.toggleTool(.trendline)
                }
                .demoAnchor("tool-trend")
                ToolButton(icon: "minus", active: state.tool == .horizontal, help: "Horizontale lijn (⌥H)") {
                    state.toggleTool(.horizontal)
                }
                ToolButton(icon: NSImage(systemSymbolName: "magnet", accessibilityDescription: nil) != nil ? "magnet" : "scope",
                           active: state.magnet, help: "Magneet: snap op open/high/low/close (⌥M · ⌘ ingedrukt = tijdelijk omzetten)") {
                    state.magnet.toggle()
                }
                .demoAnchor("tool-magnet")
                if !state.coinTrendlines.isEmpty {
                    Menu {
                        Button("Wis alle lijnen voor \(state.coin)", role: .destructive) { state.clearTrendlines() }
                    } label: {
                        Image(systemName: "trash").font(.system(size: 12))
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                    .help("Lijnen wissen")
                }
            }

            Group {
                switch state.tool {
                case .trendline:
                    Text("Klik en sleep om te tekenen · **⌘** = snap aan/uit · Esc = stoppen").foregroundStyle(Theme.orange)
                case .horizontal:
                    Text("Klik op een prijs · **⌘** = snap aan/uit · Esc = stoppen").foregroundStyle(Theme.orange)
                case .cursor:
                    if state.selectedTrendline != nil {
                        Text("Sleep de uiteinden om aan te passen · ⌫ verwijdert").foregroundStyle(Theme.muted)
                    } else {
                        Text("⇧-klik = meten · ⌘/ = sneltoetsen").foregroundStyle(Theme.dim)
                    }
                }
            }
            .font(.system(size: 11.5))
            .lineLimit(1)

            Spacer()
            if state.loadingCandles { ProgressView().controlSize(.small) }
        }
        .padding(.horizontal, 14)
        .frame(height: 50)
        .background(Theme.panel)
    }

    private func typedHint(_ tf: Timeframe) -> String {
        switch tf {
        case .m1: return "1"
        case .m5: return "5"
        case .m15: return "15"
        case .h1: return "60"
        case .h4: return "4h"
        case .d1: return "D"
        case .w1: return "W"
        }
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
        }
        .buttonStyle(HoverButtonStyle(active: active))
        .help(help)
    }
}

/// Sneltoetsen-overzicht (⌘/).
struct ShortcutsView: View {
    @Environment(\.dismiss) private var dismiss
    private let groups: [(String, [(String, String)])] = [
        ("Chart", [
            ("⌘1 … ⌘7", "Timeframe 1m … 1w"),
            ("Typ 1 · 5 · 15 · 60 · 4h · D · W, dan ⏎", "Timeframe kiezen zoals in TradingView"),
            ("⌘[  /  ⌘]", "Vorige / volgende timeframe"),
            ("← →  (⇧ = 10 candles)", "Chart verschuiven"),
            ("↑ ↓", "In- en uitzoomen"),
            ("⌥R", "Chart resetten (zoom, positie, schaal)"),
            ("Scrollen · knijpen", "Zoomen rond de cursor"),
            ("Slepen op tijd-as / prijs-as", "Horizontaal / verticaal schalen"),
            ("Dubbelklik op een as", "As terugzetten"),
        ]),
        ("Tekenen & meten", [
            ("⌥T", "Trendlijn aan/uit"),
            ("⌥H", "Horizontale lijn aan/uit"),
            ("⌥M", "Magneet aan/uit"),
            ("⌘ ingedrukt", "Snap tijdelijk omzetten"),
            ("⇧ + klik, klik", "Meten: %, candles, tijd"),
            ("⌫", "Geselecteerde lijn verwijderen"),
            ("Esc", "Terug naar aanwijzer / annuleren"),
        ]),
        ("Traden", [
            ("⌥L  /  ⌥S", "Nieuwe long / short"),
            ("⌘↩", "Order plaatsen"),
            ("⇧⌘H", "Bedragen verbergen"),
            ("⌥⌘1 / 2 / 3", "Traden / Historie / Portfolio"),
            ("⌘R", "Vernieuwen"),
        ]),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text("Sneltoetsen").font(.system(size: 20, weight: .bold))
                Spacer()
                Button("Sluiten") { dismiss() }.keyboardShortcut(.cancelAction)
            }
            HStack(alignment: .top, spacing: 28) {
                ForEach(groups, id: \.0) { group in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(group.0.uppercased()).font(.system(size: 10.5, weight: .semibold)).tracking(0.8).foregroundStyle(Theme.muted)
                        ForEach(group.1, id: \.0) { item in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.0).font(.system(size: 12.5, weight: .semibold, design: .rounded))
                                Text(item.1).font(.system(size: 11.5)).foregroundStyle(Theme.muted)
                            }
                        }
                    }
                    .frame(width: 230, alignment: .leading)
                }
            }
        }
        .padding(26)
    }
}
#endif
