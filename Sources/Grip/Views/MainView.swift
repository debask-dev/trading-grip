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
                MarketTabs()
            }
            ToolbarItem(placement: .principal) {
                Picker(T("Weergave"), selection: $state.tab) {
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
                    Label(state.hideAmounts ? T("Bedragen tonen") : T("Bedragen verbergen"), systemImage: state.hideAmounts ? "eye.slash.fill" : "eye")
                }
                .help(T("Bedragen verbergen voor screenshots (⇧⌘H)"))
                SettingsLink {
                    Label(T("Instellingen"), systemImage: "gearshape")
                }
                .help(T("Instellingen (⌘,)"))
            }
        }
        .overlay(alignment: .top) { ToastStack().padding(.top, 10) }
        .sheet(isPresented: $state.showOnboarding) { OnboardingView() }
        .sheet(isPresented: $state.showShortcuts) { ShortcutsView() }
        .alert(state.pendingConfirm?.title ?? "", isPresented: Binding(get: { state.pendingConfirm != nil }, set: { if !$0 { state.pendingConfirm = nil } }), presenting: state.pendingConfirm) { req in
            Button(req.confirmTitle, role: req.destructive ? .destructive : nil) { req.action(); state.pendingConfirm = nil }
                .keyboardShortcut(.defaultAction)
            Button(T("Annuleer"), role: .cancel) { state.pendingConfirm = nil }
        } message: { req in
            Text(req.message)
        }
        .alert(T("Let op"), isPresented: Binding(get: { state.securityNotice != nil }, set: { if !$0 { state.securityNotice = nil } })) {
            Button(T("Begrepen")) { state.securityNotice = nil }
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
        case .paper: return T("OEFENEN")
        case .none: return T("ACCOUNT KOPPELEN")
        default: return state.network.isMainnet ? T("MAINNET") : T("TESTNET")
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
        case .trading: return T("Verbonden: handelen werkt. Klik om accounts te beheren.")
        case .readOnly: return T("Verbonden, alleen-lezen (geen API-wallet). Klik om er een toe te voegen.")
        case .error(let e): return T("Probleem met de verbinding: \(e)")
        case .paper: return T("Oefenmodus: gesimuleerde orders. Klik om een account te koppelen.")
        case .none: return T("Koppel je Hyperliquid-account.")
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

enum MarketSort: String, CaseIterable { case volume, change, name }

struct CoinPicker: View {
    @EnvironmentObject var state: AppState
    @State private var query = ""
    @AppStorage("marketSort") private var sortRaw = MarketSort.volume.rawValue
    @AppStorage("marketSortAsc") private var ascending = false

    var body: some View {
        Button {
            state.showMarketPicker.toggle()
        } label: {
            Image(systemName: "plus").font(.system(size: 11, weight: .semibold)).padding(.horizontal, 6)
        }
        .help(T("Markt openen in een nieuwe tab (⌘T)"))
        .popover(isPresented: $state.showMarketPicker, arrowEdge: .bottom) {
            VStack(spacing: 8) {
                TextField(T("Zoek markt"), text: $query)
                    .textFieldStyle(.roundedBorder)
                HStack(spacing: 0) {
                    header(T("Markt"), .name).frame(maxWidth: .infinity, alignment: .leading)
                    Text(T("Prijs")).frame(width: 82, alignment: .trailing)
                    header("24u", .change).frame(width: 62, alignment: .trailing)
                    header(T("Volume 24u"), .volume).frame(width: 92, alignment: .trailing)
                }
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(Theme.muted)
                .padding(.horizontal, 8)
                List(filtered) { a in
                    Button {
                        state.coin = a.name
                        state.showMarketPicker = false
                        query = ""
                    } label: {
                        HStack(spacing: 0) {
                            HStack(spacing: 5) {
                                Text(a.name).font(.system(size: 13, weight: .semibold))
                                Text(T("\(a.maxLeverage)×")).font(.system(size: 10)).foregroundStyle(Theme.muted)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            if let c = state.contexts[a.name] {
                                Text(Fmt.price(c.markPx)).mono(12).frame(width: 82, alignment: .trailing)
                                Text(Fmt.percent(c.change24h, decimals: 1)).mono(11).foregroundStyle(Theme.pnl(c.change24h)).frame(width: 62, alignment: .trailing)
                                Text("$" + Fmt.compact(c.dayVolume)).mono(11).foregroundStyle(Theme.muted).frame(width: 92, alignment: .trailing)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                .listStyle(.plain)
            }
            .padding(10)
            .frame(width: 420, height: 460)
        }
    }

    private var sort: MarketSort { MarketSort(rawValue: sortRaw) ?? .volume }

    private func header(_ title: String, _ key: MarketSort) -> some View {
        Button {
            if sort == key { ascending.toggle() } else { sortRaw = key.rawValue; ascending = key == .name }
        } label: {
            HStack(spacing: 2) {
                Text(title)
                if sort == key { Image(systemName: ascending ? "chevron.up" : "chevron.down").font(.system(size: 8, weight: .bold)) }
            }
            .foregroundStyle(sort == key ? Theme.text : Theme.muted)
        }
        .buttonStyle(.plain)
        .help(T("Sorteer op \(title.lowercased())"))
    }

    private var filtered: [AssetInfo] {
        let q = query.trimmingCharacters(in: .whitespaces).uppercased()
        let list = q.isEmpty ? state.assets : state.assets.filter { $0.name.uppercased().contains(q) }
        let ctx = state.contexts
        let sorted: [AssetInfo]
        switch sort {
        case .name: sorted = list.sorted { $0.name < $1.name }
        case .change: sorted = list.sorted { (ctx[$0.name]?.change24h ?? 0) > (ctx[$1.name]?.change24h ?? 0) }
        case .volume: sorted = list.sorted { (ctx[$0.name]?.dayVolume ?? 0) > (ctx[$1.name]?.dayVolume ?? 0) }
        }
        let flip = sort == .name ? !ascending : ascending
        return flip ? sorted.reversed() : sorted
    }
}

/// Market info in the header: label above value, like TradingView's symbol bar. Drops items when narrow.
struct MarketStats: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        ViewThatFits(in: .horizontal) {
            row(level: 0)
            row(level: 1)
            row(level: 2)
            EmptyView()
        }
    }

    private func row(level: Int) -> some View {
        let ctx = state.contexts[state.coin]
        let h = state.hourStats
        return HStack(spacing: 14) {
            if let h {
                stat("1u", Fmt.percent(h.change, decimals: 2), Theme.pnl(h.change))
                    .help(T("Laatste uur: \(Fmt.price(h.low)) – \(Fmt.price(h.high))"))
                stat(T("Vol 1u"), "$" + Fmt.compact(h.volumeUsd))
                    .help(T("\(Fmt.compact(h.volume)) \(state.coin) in het laatste uur"))
            }
            if let ctx {
                if level < 2 { stat(T("Vol 24u"), "$" + Fmt.compact(ctx.dayVolume)) }
                stat(T("Funding"), Fmt.number(ctx.funding * 100, decimals: 4) + "%", ctx.funding >= 0 ? Theme.text : Theme.green)
                    .help(T("Funding per uur. Positief: longs betalen shorts. Negatief: shorts betalen longs."))
                if level < 1 && ctx.openInterest > 0 {
                    stat(T("Open int."), "$" + Fmt.compact(ctx.openInterest * ctx.markPx))
                        .help(T("Waarde van alle open posities op deze markt"))
                }
            }
        }
        .fixedSize()
    }

    private func stat(_ k: String, _ v: String, _ color: Color = Theme.text) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(T(k)).font(.system(size: 9.5)).foregroundStyle(Theme.dim)
            Text(v).mono(11).foregroundStyle(color)
        }
        .fixedSize()
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
                StatusDock()
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
                Text(Fmt.percent(state.change24h) + T(" 24u")).mono(11).foregroundStyle(Theme.pnl(state.change24h))
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
                    .help(T("Timeframe \(tf.label) (⌘\(i + 1) · of typ \(typedHint(tf)) + ⏎ in de chart)"))
                    .demoAnchor("tf-\(tf.rawValue)")
                }
            }
            .padding(3)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.black.opacity(0.25)))

            Divider().frame(height: 22)

            HStack(spacing: 4) {
                ToolButton(icon: "cursorarrow", active: state.tool == .cursor, help: T("Aanwijzer (Esc)")) { state.tool = .cursor }
                ToolButton(icon: "line.diagonal", active: state.tool == .trendline, help: T("Trendlijn (⌥T) · ⌘ = snap aan/uit")) {
                    state.toggleTool(.trendline)
                }
                .demoAnchor("tool-trend")
                ToolButton(icon: "minus", active: state.tool == .horizontal, help: T("Horizontale lijn: klik op een prijs · ⌥H = direct op de cursor")) {
                    state.toggleTool(.horizontal)
                }
                ToolButton(icon: "ruler", active: state.tool == .measure, help: T("Meten: klik begin en eind · of ⇧-klik in de chart")) {
                    state.toggleTool(.measure)
                }
                Menu {
                    Section(T("Gemiddelden")) {
                        ForEach([9, 21, 50, 100, 200], id: \.self) { n in
                            Button("EMA \(n)") { state.addIndicator(.ema, length: n) }
                                .disabled(state.indicators.contains { $0.kind == .ema && $0.length == n })
                        }
                        ForEach([20, 50, 200], id: \.self) { n in
                            Button("SMA \(n)") { state.addIndicator(.sma, length: n) }
                                .disabled(state.indicators.contains { $0.kind == .sma && $0.length == n })
                        }
                    }
                    Section {
                        ForEach([IndicatorKind.vwap, .bollinger, .rsi, .volume], id: \.self) { k in
                            Button(T(k.title)) { state.addIndicator(k) }
                                .disabled(k == .volume && state.indicators.contains { $0.kind == .volume && $0.visible })
                        }
                    }
                } label: {
                    Text(T("ƒx")).font(.system(size: 13, weight: .semibold, design: .serif)).italic()
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .help(T("Indicator toevoegen"))
                if !state.coinTrendlines.isEmpty {
                    Menu {
                        Button(T("Wis alle lijnen voor \(state.coin)"), role: .destructive) { state.clearTrendlines() }
                    } label: {
                        Image(systemName: "trash").font(.system(size: 12))
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                    .help(T("Lijnen wissen"))
                }
            }

            Divider().frame(height: 22)
            // Takes what is left and drops items that do not fit, so the header never pushes the window wider.
            MarketStats()
                .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
                .layoutPriority(-1)
                .clipped()

            if state.loadingCandles { ProgressView().controlSize(.small) }
            HStack(spacing: 4) {
                if state.markerDays != 0 {
                    ToolButton(icon: state.showPastTrades ? "clock.arrow.circlepath" : "clock.badge.xmark", active: !state.showPastTrades,
                               help: state.showPastTrades ? T("Eerdere trades verbergen (⌥P)") : T("Eerdere trades tonen (⌥P)")) {
                        state.showPastTrades.toggle()
                    }
                }
                ToolButton(icon: "camera", active: false, help: T("Screenshot van de chart (⇧⌘S) – bewaard in \((state.screenshotFolder as NSString).abbreviatingWithTildeInPath)")) {
                    state.takeScreenshot()
                }
                ToolButton(icon: "arrow.clockwise", active: false, help: T("Vernieuwen: opnieuw verbinden en alles herladen (⌘R)")) {
                    state.refreshEverything()
                }
            }
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
        case .h4: return T("4h")
        case .d1: return T("D")
        case .w1: return T("W")
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
        (T("Chart"), [
            ("⌘1 … ⌘7", T("Timeframe 1m … 1w")),
            (T("Typ 1 · 5 · 15 · 60 · 4h · D · W, dan ⏎"), T("Timeframe kiezen zoals in TradingView")),
            ("⌘[  /  ⌘]", T("Vorige / volgende timeframe")),
            (T("← →  (⇧ = 10 candles)"), T("Chart verschuiven")),
            ("↑ ↓", T("In- en uitzoomen")),
            ("⌥R", T("Chart resetten (zoom, positie, schaal)")),
            (T("Scrollen · knijpen"), T("Zoomen rond de cursor")),
            (T("Slepen op tijd-as / prijs-as"), T("Horizontaal / verticaal schalen")),
            (T("Dubbelklik op een as"), T("As terugzetten")),
        ]),
        (T("Tekenen & meten"), [
            ("⌥T", T("Trendlijn aan/uit")),
            (T("⌥H  /  ⌥V"), T("Horizontale / verticale lijn op de cursor")),
            ("⌥M", T("Magneet aan/uit")),
            (T("⌘ ingedrukt"), T("Snap tijdelijk omzetten")),
            (T("⇧ + klik, klik"), T("Meten: %, candles, tijd")),
            ("⌫", T("Geselecteerde lijn verwijderen")),
            (T("Esc"), T("Terug naar aanwijzer / annuleren")),
        ]),
        (T("Traden"), [
            (T("⌥L  /  ⌥S"), T("Nieuwe long / short")),
            (T("⌥B  /  ⌥N  /  ⌥X"), T("Snel: market long / short / sluiten")),
            ("⇧⌘S", T("Screenshot van de chart")),
            ("⌘↩", T("Order plaatsen")),
            ("⇧⌘H", T("Bedragen verbergen")),
            ("⌥⌘1 / 2 / 3", T("Traden / Historie / Portfolio")),
            ("⌘R", T("Vernieuwen")),
        ]),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text(T("Sneltoetsen")).font(.system(size: 20, weight: .bold))
                Spacer()
                Button(T("Sluiten")) { dismiss() }.keyboardShortcut(.cancelAction)
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
