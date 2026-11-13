#if os(macOS)
import SwiftUI
import GripCore

struct SettingsView: View {
    @EnvironmentObject var state: AppState
    @State private var keyInput = ""
    @State private var keyMessage: String?
    @State private var keyError = false

    var body: some View {
        Form {
            Section("Netwerk") {
                Picker("Netwerk", selection: $state.network) {
                    ForEach(HLNetwork.allCases) { Text($0.label).tag($0) }
                }
                if state.network == .mainnet {
                    Label("Je handelt met echt geld.", systemImage: "exclamationmark.triangle.fill").foregroundStyle(Theme.orange)
                }
            }

            Section {
                TextField("Wallet-adres (0x…)", text: $state.accountAddress)
                    .font(.system(.body, design: .monospaced))
                if !state.accountAddress.isEmpty && !state.hasAccount {
                    Text("Dit lijkt geen geldig adres (0x + 40 tekens).").font(.caption).foregroundStyle(Theme.red)
                }
            } header: {
                Text("Account")
            } footer: {
                Text("Het adres van je hoofdwallet waarmee je op Hyperliquid inlogt. Alleen-lezen: hiermee toont Grip saldo, posities en historie.")
            }

            Section {
                if let addr = state.agentAddress {
                    LabeledContent("API-wallet") { Text(addr).font(.system(.caption, design: .monospaced)).textSelection(.enabled) }
                    Button("API-wallet verwijderen", role: .destructive) { state.removeAgentKey(); keyMessage = nil }
                } else {
                    SecureField("Private key van je API-wallet", text: $keyInput)
                        .font(.system(.body, design: .monospaced))
                    Button("Opslaan in sleutelhanger") {
                        do {
                            let a = try state.saveAgentKey(keyInput)
                            keyMessage = "Opgeslagen. API-wallet: \(a)"
                            keyError = false
                            keyInput = ""
                        } catch {
                            keyMessage = error.localizedDescription
                            keyError = true
                        }
                    }
                    .disabled(keyInput.isEmpty)
                }
                if let m = keyMessage { Text(m).font(.caption).foregroundStyle(keyError ? Theme.red : Theme.green) }
            } header: {
                Text("Handelen (\(state.network == .mainnet ? "mainnet" : "testnet"))")
            } footer: {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Gebruik een **API-wallet** (Hyperliquid → More → API), niet de key van je hoofdwallet. Een API-wallet kan handelen maar **geen geld opnemen**.")
                    Text("De key wordt alleen in de macOS-sleutelhanger bewaard en verlaat je Mac nooit, behalve als handtekening op je orders.")
                    Link("API-wallet aanmaken op Hyperliquid", destination: URL(string: state.network == .mainnet ? "https://app.hyperliquid.xyz/API" : "https://app.hyperliquid-testnet.xyz/API")!)
                }
            }

            Section("Trading") {
                LabeledContent("Standaard risico per trade") {
                    Stepper(Fmt.number(state.riskPercent, decimals: 2) + "%", value: $state.riskPercent, in: 0.1...5, step: 0.25)
                }
                LabeledContent("Max slippage market-orders") {
                    Stepper(Fmt.number(state.slippagePercent, decimals: 1) + "%", value: $state.slippagePercent, in: 0.1...5, step: 0.1)
                }
                Picker("Margin-modus", selection: $state.useCrossMargin) {
                    Text("Cross").tag(true)
                    Text("Isolated").tag(false)
                }
                Toggle("Bedragen verbergen (privacymodus)", isOn: $state.hideAmounts)
            }
        }
        .formStyle(.grouped)
        .frame(width: 520, height: 640)
    }
}

struct OnboardingView: View {
    @EnvironmentObject var state: AppState
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 14) {
                AppLogo().frame(width: 52, height: 52)
                VStack(alignment: .leading) {
                    Text("Welkom bij Grip").font(.system(size: 24, weight: .bold))
                    Text("Trading op Hyperliquid, gewoon in de chart.").foregroundStyle(Theme.muted)
                }
            }
            VStack(alignment: .leading, spacing: 12) {
                Step(n: 1, text: "Kies **Testnet** om veilig te oefenen (standaard), of Mainnet voor echt geld.")
                Step(n: 2, text: "Vul het **adres van je wallet** in. Daarmee ziet Grip je saldo, posities en historie.")
                Step(n: 3, text: "Maak op Hyperliquid een **API-wallet** aan (More → API) en plak de private key in Grip. Die kan handelen maar nooit geld opnemen, en staat alleen in je sleutelhanger.")
                Step(n: 4, text: "Klik **Long** of **Short**, sleep entry, stop-loss en take-profit in de chart, kies je risico. Klaar.")
            }
            Text("Zonder account kun je de charts, trendlijnen en de risicocalculator gewoon gebruiken.")
                .font(.system(size: 12)).foregroundStyle(Theme.dim)
            HStack {
                Button("Later") { dismiss() }
                Spacer()
                SettingsLink { Text("Instellingen openen") }
                    .buttonStyle(.borderedProminent)
                    .simultaneousGesture(TapGesture().onEnded { dismiss() })
            }
        }
        .padding(28)
        .frame(width: 520)
    }

    struct Step: View {
        var n: Int
        var text: LocalizedStringKey
        var body: some View {
            HStack(alignment: .top, spacing: 12) {
                Text("\(n)").font(.system(size: 12, weight: .bold)).frame(width: 22, height: 22)
                    .background(Circle().fill(Theme.accent.opacity(0.3)))
                Text(text).fixedSize(horizontal: false, vertical: true)
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
