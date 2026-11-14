#if os(macOS)
import SwiftUI
import AppKit
import GripCore

/// Separate window for connecting and managing exchange accounts.
struct AccountsView: View {
    @EnvironmentObject var state: AppState
    @State private var selection: Selection?

    enum Selection: Hashable { case account(UUID), new }

    var body: some View {
        HStack(spacing: 0) {
            sidebar
                .frame(width: 250)
                .background(Theme.panel)
            Divider().overlay(Theme.line)
            Group {
                switch selection {
                case .account(let id)?:
                    if let a = state.accounts.first(where: { $0.id == id }) {
                        AccountDetailView(account: a, onDeleted: { selection = state.accounts.first.map { .account($0.id) } ?? .new })
                            .id(id)
                    } else {
                        AddAccountView(onSaved: { selection = .account($0) })
                    }
                case .new?, nil:
                    AddAccountView(onSaved: { selection = .account($0) })
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Theme.bg)
        }
        .frame(minWidth: 860, minHeight: 600)
        .onAppear {
            if selection == nil { selection = state.activeAccountID.map { .account($0) } ?? .new }
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("ACCOUNTS").font(.system(size: 10.5, weight: .semibold)).tracking(0.8).foregroundStyle(Theme.muted)
                .padding(.horizontal, 14).padding(.top, 16).padding(.bottom, 4)
            ScrollView {
                VStack(spacing: 4) {
                    ForEach(state.accounts) { a in
                        Button { selection = .account(a.id) } label: { AccountRow(account: a, active: a.id == state.activeAccountID) }
                            .buttonStyle(SidebarButtonStyle(selected: selection == .account(a.id)))
                    }
                    Button { selection = .new } label: {
                        Label("Account toevoegen", systemImage: "plus.circle.fill")
                            .font(.system(size: 13, weight: .medium))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 10).padding(.vertical, 9)
                    }
                    .buttonStyle(SidebarButtonStyle(selected: selection == .new))
                }
                .padding(.horizontal, 8)
            }
            Spacer()
            VStack(alignment: .leading, spacing: 6) {
                Toggle("Oefenmodus", isOn: $state.paperMode).toggleStyle(.switch).controlSize(.small)
                Text("Nepgeld, live koersen. Geen account nodig.").font(.system(size: 11)).foregroundStyle(Theme.dim)
            }
            .padding(14)
        }
    }
}

struct AccountRow: View {
    let account: ExchangeAccount
    let active: Bool
    var body: some View {
        HStack(spacing: 10) {
            ExchangeIcon(kind: account.exchange).frame(width: 28, height: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(account.label).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                HStack(spacing: 5) {
                    NetworkPill(network: account.network)
                    Text(account.canTrade ? "Handelen" : "Alleen-lezen").font(.system(size: 10.5)).foregroundStyle(Theme.muted)
                }
            }
            Spacer()
            if active { Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.green).help("Actief account") }
            StatusDot(ok: account.lastCheckOK)
        }
        .padding(.horizontal, 10).padding(.vertical, 8)
    }
}

struct SidebarButtonStyle: ButtonStyle {
    var selected: Bool
    func makeBody(configuration: Configuration) -> some View { SidebarBody(configuration: configuration, selected: selected) }
    private struct SidebarBody: View {
        let configuration: ButtonStyleConfiguration
        let selected: Bool
        @State private var hovering = false
        var body: some View {
            configuration.label
                .foregroundStyle(Theme.text)
                .background(RoundedRectangle(cornerRadius: 8).fill(selected ? Theme.accent.opacity(0.25) : Color.white.opacity(hovering ? 0.06 : 0)))
                .contentShape(Rectangle())
                .onHover { hovering = $0 }
        }
    }
}

struct ExchangeIcon: View {
    let kind: ExchangeKind
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 7).fill(Color(hex: "#97FCE4").opacity(0.15))
            Text(String(kind.name.prefix(1))).font(.system(size: 14, weight: .bold)).foregroundStyle(Color(hex: "#97FCE4"))
        }
    }
}

struct NetworkPill: View {
    let network: HLNetwork
    var body: some View {
        Text(network.isMainnet ? "MAINNET" : "TESTNET")
            .font(.system(size: 9.5, weight: .bold))
            .padding(.horizontal, 5).padding(.vertical, 1.5)
            .background(RoundedRectangle(cornerRadius: 4).fill((network.isMainnet ? Theme.red : Theme.orange).opacity(0.15)))
            .foregroundStyle(network.isMainnet ? Theme.red : Theme.orange)
    }
}

struct StatusDot: View {
    let ok: Bool?
    var body: some View {
        Circle().fill(ok == true ? Theme.green : (ok == false ? Theme.red : Theme.dim)).frame(width: 8, height: 8)
            .help(ok == true ? "Laatste test geslaagd" : (ok == false ? "Laatste test mislukt" : "Nog niet getest"))
    }
}

// MARK: - Connection test UI

@MainActor
final class ConnectionTestModel: ObservableObject {
    @Published var steps: [CheckStep] = []
    @Published var report: ConnectionReport?
    @Published var running = false

    func run(_ work: @escaping (@escaping @Sendable ([CheckStep]) async -> Void) async -> ConnectionReport?) {
        running = true
        report = nil
        Task {
            let r = await work { [weak self] steps in
                await MainActor.run { withAnimation(.easeOut(duration: 0.2)) { self?.steps = steps } }
            }
            report = r
            if let r { steps = r.steps }
            running = false
        }
    }
}

struct ChecklistView: View {
    let steps: [CheckStep]
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(steps) { s in
                HStack(alignment: .top, spacing: 10) {
                    icon(s.status).frame(width: 18, height: 18)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(s.title).font(.system(size: 13, weight: .medium)).foregroundStyle(s.status == .skipped ? Theme.dim : Theme.text)
                        if !s.detail.isEmpty {
                            Text(s.detail).font(.system(size: 11.5)).foregroundStyle(color(s.status)).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .transition(.opacity)
            }
        }
    }

    @ViewBuilder private func icon(_ st: CheckStep.Status) -> some View {
        switch st {
        case .pending: Image(systemName: "circle").foregroundStyle(Theme.dim)
        case .running: ProgressView().controlSize(.small)
        case .ok: Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.green)
        case .warning: Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Theme.orange)
        case .failed: Image(systemName: "xmark.octagon.fill").foregroundStyle(Theme.red)
        case .skipped: Image(systemName: "minus.circle").foregroundStyle(Theme.dim)
        }
    }

    private func color(_ st: CheckStep.Status) -> Color {
        switch st {
        case .failed: return Theme.red
        case .warning: return Theme.orange
        case .ok: return Theme.muted
        default: return Theme.dim
        }
    }
}

// MARK: - Add account

struct AddAccountView: View {
    @EnvironmentObject var state: AppState
    var onSaved: (UUID) -> Void

    @State private var network: HLNetwork = .testnet
    @State private var address = ""
    @State private var key = ""
    @State private var label = ""
    @State private var addressNotice: String?
    @State private var saveError: String?
    @StateObject private var test = ConnectionTestModel()

    private var addressKind: CredentialKind { Credentials.classify(address) }
    private var keyAddress: String? { (try? EthSigner(privateKeyHex: key.trimmingCharacters(in: .whitespacesAndNewlines)))?.address }
    private var apiURL: URL { URL(string: network.isMainnet ? "https://app.hyperliquid.xyz/API" : "https://app.hyperliquid-testnet.xyz/API")! }
    private var defaultLabel: String { "Hyperliquid \(network.isMainnet ? "Mainnet" : "Testnet")" }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Account koppelen").font(.system(size: 22, weight: .bold))
                    Text("Grip test de verbinding voordat je opslaat. Je sleutel komt alleen in de macOS-sleutelhanger.")
                        .foregroundStyle(Theme.muted)
                }

                StepSection(n: 1, title: "Exchange") {
                    HStack(spacing: 10) {
                        ExchangeCard(name: "Hyperliquid", subtitle: "Perpetuals", selected: true, enabled: true)
                        ExchangeCard(name: "Meer exchanges", subtitle: "Binnenkort", selected: false, enabled: false)
                    }
                }

                StepSection(n: 2, title: "Netwerk") {
                    Picker("", selection: $network) {
                        Text("Testnet (oefenen)").tag(HLNetwork.testnet)
                        Text("Mainnet (echt geld)").tag(HLNetwork.mainnet)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(maxWidth: 360)
                    if network == .mainnet {
                        Label("Op Mainnet handel je met echt geld.", systemImage: "exclamationmark.triangle.fill")
                            .font(.system(size: 12)).foregroundStyle(Theme.orange)
                    }
                }

                StepSection(n: 3, title: "Adres van je hoofdwallet") {
                    Text("Het publieke adres waarmee je op Hyperliquid inlogt (begint met 0x). Daarmee ziet Grip je saldo, posities en historie.")
                        .font(.system(size: 12)).foregroundStyle(Theme.muted).fixedSize(horizontal: false, vertical: true)
                    HStack {
                        TextField("0x…", text: $address)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(.body, design: .monospaced))
                            .onChange(of: address) { _, new in
                                if case .privateKey = Credentials.classify(new) {
                                    // Never keep a private key in a visible field.
                                    address = ""
                                    addressNotice = "Dat was een private key, geen adres. Hij is uit dit veld gehaald. Een private key hoort alleen bij stap 4, en dan alléén die van een API-wallet."
                                } else if !new.isEmpty {
                                    addressNotice = nil
                                }
                            }
                        Button("Plak") { address = NSPasteboard.general.string(forType: .string) ?? "" }
                        validity
                    }
                    if let n = addressNotice {
                        Label(n, systemImage: "hand.raised.fill").font(.system(size: 12)).foregroundStyle(Theme.orange)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                StepSection(n: 4, title: "API-wallet (om te kunnen handelen)") {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Maak op Hyperliquid een API-wallet aan: **More → API → Generate**, kies een naam (bijv. Grip), klik **Authorize** en kopieer de **private key**. Een API-wallet kan handelen, maar **nooit geld opnemen**.")
                            .font(.system(size: 12)).foregroundStyle(Theme.muted).fixedSize(horizontal: false, vertical: true)
                        Link(destination: apiURL) {
                            Label("Open de API-pagina op Hyperliquid \(network.isMainnet ? "" : "Testnet")", systemImage: "arrow.up.right.square")
                                .font(.system(size: 12, weight: .medium))
                        }
                    }
                    SecureField("Private key van de API-wallet (laat leeg voor alleen-lezen)", text: $key)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.body, design: .monospaced))
                    if !key.isEmpty {
                        if let a = keyAddress {
                            Label("Hoort bij API-wallet \(Credentials.mask(a))", systemImage: "key.fill").font(.system(size: 12)).foregroundStyle(Theme.green)
                        } else {
                            Label("Dit is geen geldige private key (64 tekens, eventueel met 0x).", systemImage: "xmark.octagon.fill").font(.system(size: 12)).foregroundStyle(Theme.red)
                        }
                    } else {
                        Text("Zonder sleutel: alleen-lezen. Je kunt de sleutel later toevoegen.").font(.system(size: 11.5)).foregroundStyle(Theme.dim)
                    }
                }

                StepSection(n: 5, title: "Naam") {
                    TextField(defaultLabel, text: $label).textFieldStyle(.roundedBorder).frame(maxWidth: 360)
                }

                Divider().overlay(Theme.line)

                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 10) {
                        Button {
                            saveError = nil
                            let net = network, addr = address, k = key.isEmpty ? nil : key
                            test.run { progress in await state.testConnection(network: net, address: addr, key: k, progress: progress) }
                        } label: {
                            Label(test.running ? "Bezig met testen…" : "Test verbinding", systemImage: "bolt.horizontal.circle")
                                .frame(minWidth: 170)
                        }
                        .buttonStyle(BigButtonStyle(color: Theme.card, textColor: Theme.text))
                        .disabled(test.running || address.isEmpty)

                        Button {
                            save()
                        } label: {
                            Label("Opslaan en gebruiken", systemImage: "checkmark").frame(minWidth: 190)
                        }
                        .buttonStyle(BigButtonStyle(color: Theme.green))
                        .disabled(!(test.report?.passed ?? false) || test.running)
                        .help(test.report == nil ? "Test eerst de verbinding" : "")
                    }

                    if !test.steps.isEmpty {
                        ChecklistView(steps: test.steps)
                            .padding(16)
                            .background(RoundedRectangle(cornerRadius: 12).fill(Theme.card))
                            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.line))
                    }

                    if let r = test.report {
                        summary(r)
                    }
                    if let e = saveError { Text(e).foregroundStyle(Theme.red).font(.system(size: 12)) }
                }
            }
            .padding(28)
            .frame(maxWidth: 680, alignment: .leading)
        }
        .onChange(of: network) { _, _ in test.steps = []; test.report = nil }
        .onChange(of: address) { _, _ in test.report = nil }
        .onChange(of: key) { _, _ in test.report = nil }
    }

    @ViewBuilder private var validity: some View {
        switch addressKind {
        case .address: Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.green).help("Geldig adres")
        case .invalid: Image(systemName: "xmark.circle.fill").foregroundStyle(Theme.red).help("Geen geldig adres")
        default: EmptyView()
        }
    }

    @ViewBuilder private func summary(_ r: ConnectionReport) -> some View {
        if let s = r.suggestedAddress {
            HStack {
                Text("Je hoofdadres is \(Credentials.mask(s)).").font(.system(size: 12.5))
                Button("Gebruik dit adres") { address = s }
            }
        }
        if let n = r.suggestedNetwork {
            HStack {
                Text("De API-wallet is goedgekeurd op \(n.isMainnet ? "Mainnet" : "Testnet").").font(.system(size: 12.5))
                Button("Wissel naar \(n.isMainnet ? "Mainnet" : "Testnet")") { network = n }
            }
        }
        if r.passed {
            Label(r.canTrade ? "Alles werkt. Je kunt opslaan en direct handelen." : "Verbonden (alleen-lezen). Je kunt opslaan; voeg later een API-wallet toe om te handelen.",
                  systemImage: "checkmark.seal.fill")
                .font(.system(size: 13, weight: .medium)).foregroundStyle(Theme.green)
        }
    }

    private func save() {
        guard case .address(let addr) = addressKind, let r = test.report, r.passed else { return }
        var acct = ExchangeAccount(network: network, label: label.trimmingCharacters(in: .whitespaces).isEmpty ? defaultLabel : label, address: addr)
        acct.lastCheck = Date()
        acct.lastCheckOK = true
        acct.agentName = r.agentName
        acct.agentValidUntil = r.agentValidUntil
        do {
            try state.saveAccount(acct, key: key.isEmpty ? "" : key)
            key = ""
            onSaved(acct.id)
        } catch {
            saveError = error.localizedDescription
        }
    }
}

struct StepSection<Content: View>: View {
    let n: Int
    let title: String
    @ViewBuilder var content: Content
    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Text("\(n)")
                .font(.system(size: 12, weight: .bold))
                .frame(width: 24, height: 24)
                .background(Circle().fill(Theme.accent.opacity(0.3)))
            VStack(alignment: .leading, spacing: 8) {
                Text(title).font(.system(size: 14, weight: .semibold))
                content
            }
        }
    }
}

struct ExchangeCard: View {
    let name: String
    let subtitle: String
    let selected: Bool
    let enabled: Bool
    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 7).fill(enabled ? Color(hex: "#97FCE4").opacity(0.15) : Theme.card)
                Image(systemName: enabled ? "h.square.fill" : "ellipsis").foregroundStyle(enabled ? Color(hex: "#97FCE4") : Theme.dim)
            }
            .frame(width: 30, height: 30)
            VStack(alignment: .leading, spacing: 1) {
                Text(name).font(.system(size: 13, weight: .semibold))
                Text(subtitle).font(.system(size: 11)).foregroundStyle(Theme.muted)
            }
            Spacer()
            if selected { Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.accent) }
        }
        .padding(12)
        .frame(width: 210)
        .background(RoundedRectangle(cornerRadius: 10).fill(Theme.card))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(selected ? Theme.accent : Theme.line, lineWidth: selected ? 1.5 : 1))
        .opacity(enabled ? 1 : 0.5)
    }
}

// MARK: - Account detail

struct AccountDetailView: View {
    @EnvironmentObject var state: AppState
    let account: ExchangeAccount
    var onDeleted: () -> Void

    @StateObject private var test = ConnectionTestModel()
    @State private var revealAddress = false
    @State private var editingKey = false
    @State private var newKey = ""
    @State private var keyError: String?
    @State private var confirmDelete = false
    @State private var label = ""

    private var isActive: Bool { state.activeAccountID == account.id }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack(spacing: 14) {
                    ExchangeIcon(kind: account.exchange).frame(width: 44, height: 44)
                    VStack(alignment: .leading, spacing: 4) {
                        TextField("Naam", text: $label, onCommit: { state.renameAccount(account.id, to: label) })
                            .textFieldStyle(.plain)
                            .font(.system(size: 22, weight: .bold))
                        HStack(spacing: 6) {
                            NetworkPill(network: account.network)
                            Text(account.exchange.name).font(.system(size: 12)).foregroundStyle(Theme.muted)
                        }
                    }
                    Spacer()
                    if isActive {
                        Label("Actief", systemImage: "checkmark.circle.fill").foregroundStyle(Theme.green).font(.system(size: 13, weight: .semibold))
                    } else {
                        Button("Gebruik dit account") { state.activate(account.id) }
                            .buttonStyle(BigButtonStyle(color: Theme.green))
                    }
                }

                Card(title: "Gegevens") {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("Hoofdadres").foregroundStyle(Theme.muted).frame(width: 110, alignment: .leading)
                            Text(revealAddress ? account.address : Credentials.mask(account.address))
                                .font(.system(.body, design: .monospaced)).textSelection(.enabled)
                            Button { revealAddress.toggle() } label: { Image(systemName: revealAddress ? "eye.slash" : "eye") }
                                .buttonStyle(HoverButtonStyle(active: false)).help(revealAddress ? "Verbergen" : "Volledig tonen")
                            Button {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(account.address, forType: .string)
                                state.toast("Adres gekopieerd", .info)
                            } label: { Image(systemName: "doc.on.doc") }
                                .buttonStyle(HoverButtonStyle(active: false)).help("Kopiëren")
                        }
                        HStack(alignment: .top) {
                            Text("API-wallet").foregroundStyle(Theme.muted).frame(width: 110, alignment: .leading)
                            VStack(alignment: .leading, spacing: 4) {
                                if let agent = account.agentAddress {
                                    Text("\(Credentials.mask(agent))\(account.agentName.map { $0.isEmpty ? "" : "  ·  “\($0)”" } ?? "")")
                                        .font(.system(.body, design: .monospaced))
                                    Text("Sleutel: ••••••••  (in de sleutelhanger, nooit zichtbaar)").font(.system(size: 11.5)).foregroundStyle(Theme.dim)
                                    if let until = account.agentValidUntil {
                                        Text("Geldig tot \(until.formatted(date: .abbreviated, time: .omitted))").font(.system(size: 11.5)).foregroundStyle(Theme.dim)
                                    }
                                } else {
                                    Text("Geen: alleen-lezen").foregroundStyle(Theme.orange)
                                }
                                if editingKey {
                                    SecureField("Private key van de nieuwe API-wallet", text: $newKey)
                                        .textFieldStyle(.roundedBorder).font(.system(.body, design: .monospaced))
                                    HStack {
                                        Button("Opslaan en testen") { replaceKey() }.disabled(newKey.isEmpty)
                                        Button("Annuleer") { editingKey = false; newKey = ""; keyError = nil }
                                    }
                                    if let e = keyError { Text(e).font(.system(size: 11.5)).foregroundStyle(Theme.red) }
                                } else {
                                    HStack {
                                        Button(account.agentAddress == nil ? "API-wallet toevoegen" : "Sleutel vervangen") { editingKey = true }
                                        if account.agentAddress != nil {
                                            Button("Sleutel verwijderen", role: .destructive) {
                                                try? state.saveAccount(account, key: "")
                                                runTest()
                                            }
                                        }
                                    }
                                    .controlSize(.small)
                                }
                            }
                        }
                    }
                    .font(.system(size: 13))
                }

                Card(title: "Verbinding") {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack {
                            if let r = test.report {
                                Label(r.passed ? (r.canTrade ? "Verbonden · handelen werkt" : "Verbonden · alleen-lezen") : "Er is een probleem",
                                      systemImage: r.passed ? "checkmark.seal.fill" : "exclamationmark.octagon.fill")
                                    .foregroundStyle(r.passed ? Theme.green : Theme.red).font(.system(size: 13, weight: .semibold))
                                if let v = r.accountValue {
                                    Text(balanceText(v, r)).foregroundStyle(Theme.muted).font(.system(size: 13))
                                }
                            } else if test.running {
                                Text("Bezig met testen…").foregroundStyle(Theme.muted)
                            }
                            Spacer()
                            Button { runTest() } label: { Label("Test opnieuw", systemImage: "arrow.clockwise") }
                                .disabled(test.running)
                        }
                        if !test.steps.isEmpty { ChecklistView(steps: test.steps) }
                        if let d = account.lastCheck {
                            Text("Laatst getest: \(d.formatted(date: .abbreviated, time: .shortened))").font(.system(size: 11)).foregroundStyle(Theme.dim)
                        }
                    }
                }

                HStack {
                    Spacer()
                    Button(role: .destructive) { confirmDelete = true } label: { Label("Account verwijderen", systemImage: "trash") }
                }
            }
            .padding(28)
            .frame(maxWidth: 680, alignment: .leading)
        }
        .onAppear {
            label = account.label
            runTest()
        }
        .confirmationDialog("“\(account.label)” verwijderen?", isPresented: $confirmDelete) {
            Button("Verwijderen", role: .destructive) { state.removeAccount(account.id); onDeleted() }
        } message: {
            Text("Het account en de API-wallet-sleutel worden uit Grip en de sleutelhanger verwijderd. Op Hyperliquid blijft de API-wallet bestaan; die kun je daar intrekken.")
        }
    }

    private func balanceText(_ v: Double, _ r: ConnectionReport) -> String {
        let f = state.fmt
        let mode = r.mode.map { " · \($0.label)" } ?? ""
        if let m = r.mode, !m.balancesOnSpot, let spot = r.spotValue, spot > 0.005 {
            return "· perps \(f.usd(v, decimals: 2)) + spot \(f.usd(spot, decimals: 2))\(mode)"
        }
        return "· saldo \(f.usd(v, decimals: 2))\(mode)"
    }

    private func runTest() {
        let id = account.id
        test.run { progress in await state.testAccount(id, progress: progress) }
    }

    private func replaceKey() {
        keyError = nil
        do {
            try state.saveAccount(account, key: newKey)
            newKey = ""
            editingKey = false
            runTest()
        } catch {
            keyError = error.localizedDescription
        }
    }
}
#endif
