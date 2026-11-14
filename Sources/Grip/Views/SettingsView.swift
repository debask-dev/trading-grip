#if os(macOS)
import SwiftUI
import GripCore

struct SettingsView: View {
    @EnvironmentObject var state: AppState
    var body: some View {
        TabView {
            AccountSettingsView()
                .tabItem { Label(T("Account"), systemImage: "person.crop.circle") }
            ChartSettingsView()
                .tabItem { Label(T("Chart"), systemImage: "chart.bar.xaxis") }
            RiskSettingsView()
                .tabItem { Label(T("Risico"), systemImage: "gauge.with.dots.needle.33percent") }
            AlertSettingsView()
                .tabItem { Label(T("Meldingen"), systemImage: "bell.badge") }
        }
        .frame(width: 560, height: 720)
    }
}

struct AccountSettingsView: View {
    @EnvironmentObject var state: AppState
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Form {
            Section(T("Taal")) {
                Picker(T("Taal"), selection: $state.language) {
                    ForEach(AppLanguage.allCases) { Text(T($0.label)).tag($0) }
                }
            }

            Section {
                if let a = state.activeAccount {
                    HStack(spacing: 12) {
                        ExchangeIcon(kind: a.exchange).frame(width: 30, height: 30)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(a.label).font(.system(size: 13, weight: .semibold))
                            HStack(spacing: 6) {
                                NetworkPill(network: a.network)
                                Text(Credentials.mask(a.address)).font(.system(.caption, design: .monospaced)).foregroundStyle(Theme.muted)
                                Text(a.canTrade ? T("· handelen") : T("· alleen-lezen")).font(.caption).foregroundStyle(Theme.muted)
                            }
                        }
                        Spacer()
                        StatusDot(ok: a.lastCheckOK)
                    }
                } else {
                    Text(state.paperMode ? T("Geen account gekoppeld – je zit in de oefenmodus.") : T("Nog geen account gekoppeld."))
                        .foregroundStyle(Theme.muted)
                }
                Button(state.accounts.isEmpty ? T("Account koppelen…") : T("Accounts beheren…")) { openWindow(id: "accounts") }
            } header: {
                Text(T("Account"))
            } footer: {
                Text(T("Koppelen, testen en wisselen van account gaat in het accountscherm (⇧⌘A)."))
            }

            if state.activeAccount == nil {
                Section(T("Koersen")) {
                    Picker(T("Koersen van"), selection: $state.network) {
                        ForEach(HLNetwork.allCases) { Text($0.isMainnet ? T("Mainnet") : T("Testnet")).tag($0) }
                    }
                }
            }

            Section {
                Toggle(T("Oefenmodus (papier-traden)"), isOn: $state.paperMode)
                if state.paperMode {
                    LabeledContent(T("Startsaldo")) { Text(state.fmt.usd(state.paperStartingBalance)) }
                    HStack {
                        Text(T("Reset naar"))
                        ForEach([1_000.0, 10_000.0, 100_000.0], id: \.self) { b in
                            Button("$" + Fmt.number(b, decimals: 0)) { state.resetPaper(balance: b) }
                        }
                    }
                }
            } header: {
                Text(T("Oefenmodus"))
            } footer: {
                Text(T("Handel met nepgeld tegen live koersen van Hyperliquid. Orders, fills, fees, historie en portfolio worden lokaal gesimuleerd."))
            }

            Section(T("Trading")) {
                LabeledContent(T("Standaard risico per trade")) {
                    Stepper(Fmt.number(state.riskPercent, decimals: 2) + "%", value: $state.riskPercent, in: 0.1...5, step: 0.25)
                }
                LabeledContent(T("Max slippage market-orders")) {
                    Stepper(Fmt.number(state.slippagePercent, decimals: 1) + "%", value: $state.slippagePercent, in: 0.1...5, step: 0.1)
                }
                Picker(T("Margin-modus"), selection: $state.useCrossMargin) {
                    Text(T("Cross")).tag(true)
                    Text(T("Isolated")).tag(false)
                }
                Toggle(T("Bedragen verbergen (privacymodus)"), isOn: $state.hideAmounts)
            }
        }
        .formStyle(.grouped)
    }
}

struct AlertSettingsView: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        Form {
            Section {
                ForEach(TradeEvent.allCases) { e in
                    HStack {
                        Text(e.label)
                        Spacer()
                        Toggle(T("Melding"), isOn: binding(e, \.notify)).toggleStyle(.checkbox)
                        Toggle(T("Geluid"), isOn: binding(e, \.sound)).toggleStyle(.checkbox)
                        Button { Notifier.shared.play(e) } label: { Image(systemName: "speaker.wave.2") }
                            .buttonStyle(.borderless).help(T("Geluid afspelen (\(e.sound))"))
                    }
                }
            } header: {
                Text(T("Meldingen en geluid"))
            } footer: {
                Text(T("Meldingen verschijnen ook als Grip op de achtergrond staat; bij een fill springt het Dock-icoon. Werkt alleen zolang Grip draait. Toestemming voor meldingen regel je in Systeeminstellingen → Meldingen → Grip."))
            }

            Section(T("Bevestigen")) {
                Toggle(T("Vraag bevestiging bij market orders (openen en sluiten)"), isOn: $state.confirmMarketOrders)
            }

            Section(T("Menubalk")) {
                Toggle(T("Toon positie en netto resultaat in de menubalk"), isOn: $state.showMenuBar)
            }
        }
        .formStyle(.grouped)
    }

    private func binding(_ e: TradeEvent, _ key: WritableKeyPath<EventPref, Bool>) -> Binding<Bool> {
        Binding(get: { state.pref(e)[keyPath: key] }, set: { v in
            var p = state.pref(e)
            p[keyPath: key] = v
            state.eventPrefs[e.rawValue] = p
        })
    }
}

struct OnboardingView: View {
    @EnvironmentObject var state: AppState
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 14) {
                AppLogo().frame(width: 52, height: 52)
                VStack(alignment: .leading) {
                    Text(T("Welkom bij Grip")).font(.system(size: 24, weight: .bold))
                    Text(T("Trading op Hyperliquid, gewoon in de chart.")).foregroundStyle(Theme.muted)
                }
            }
            VStack(alignment: .leading, spacing: 12) {
                Step(n: 1, text: T("**Koppel je Hyperliquid-account**: kies Testnet of Mainnet, vul je wallet-adres in en (om te handelen) een API-wallet. Grip test alles voordat je opslaat."))
                Step(n: 2, text: T("Of probeer eerst de **oefenmodus**: nepgeld, live koersen, geen sleutels nodig."))
                Step(n: 3, text: T("Klik **Long** of **Short**, sleep entry, stop-loss en take-profit in de chart en kies je risico. Klaar."))
            }
            Text(T("Zonder account kun je de charts, trendlijnen en de risicocalculator gewoon gebruiken."))
                .font(.system(size: 12)).foregroundStyle(Theme.dim)
            HStack {
                Button(T("Later")) { dismiss() }
                Button(T("Probeer de oefenmodus")) { state.paperMode = true; dismiss() }
                Spacer()
                Button(T("Account koppelen")) { dismiss(); openWindow(id: "accounts") }
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(28)
        .frame(width: 520)
    }

    struct Step: View {
        var n: Int
        var text: String
        var body: some View {
            HStack(alignment: .top, spacing: 12) {
                Text("\(n)").font(.system(size: 12, weight: .bold)).frame(width: 22, height: 22)
                    .background(Circle().fill(Theme.accent.opacity(0.3)))
                Text(LocalizedStringKey(text)).fixedSize(horizontal: false, vertical: true)   // keeps the **bold** markup
            }
        }
    }
}

struct AppLogo: View {
    var body: some View {
        GeometryReader { g in
            let s = min(g.size.width, g.size.height)
            ZStack {
                RoundedRectangle(cornerRadius: s * 0.25)
                    .fill(LinearGradient(colors: [Color(nsColor: NSColor(hex: 0x9A8CFF)), Theme.green], startPoint: .topLeading, endPoint: .bottomTrailing))
                Path { p in
                    let c = CGPoint(x: s / 2, y: s / 2)
                    p.addArc(center: c, radius: s * 0.25, startAngle: .degrees(-40), endAngle: .degrees(0), clockwise: true)
                    p.addLine(to: CGPoint(x: s * 0.53, y: s * 0.53))
                }
                .stroke(Color(nsColor: Palette.bg), style: StrokeStyle(lineWidth: s * 0.11, lineCap: .round, lineJoin: .round))
            }
            .frame(width: s, height: s)
        }
    }
}
#endif
