#if os(macOS)
import SwiftUI
import GripCore

struct TradePanel: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                AccountCard()
                RiskCard()
                if state.ticket != nil {
                    TicketCard()
                } else if state.position == nil {
                    NewTradeButtons()
                }
                if state.position != nil { PositionCard() }
                OrdersCard()
                if let err = state.accountError {
                    Text(err).font(.system(size: 11)).foregroundStyle(Theme.red).frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(16)
        }
    }
}

struct AccountCard: View {
    @EnvironmentObject var state: AppState
    var body: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Portfolio").font(.system(size: 11.5)).foregroundStyle(Theme.muted)
                Text(state.hasAccount ? state.fmt.usd(state.account.accountValue) : "–").mono(17, .semibold)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 3) {
                Text("Open PnL").font(.system(size: 11.5)).foregroundStyle(Theme.muted)
                let u = state.account.positions.reduce(0) { $0 + $1.unrealizedPnl }
                Text(state.hasAccount ? state.fmt.signedUsd(u) : "–").mono(17, .semibold).foregroundStyle(state.hasAccount ? Theme.pnl(u) : Theme.muted)
            }
        }
        .padding(.horizontal, 2)
    }
}

struct RiskCard: View {
    @EnvironmentObject var state: AppState
    var body: some View {
        Card(title: "Max verlies per trade") {
            HStack(alignment: .firstTextBaseline) {
                Text(Fmt.number(state.riskPercent, decimals: 2) + "%").mono(26, .bold)
                Spacer()
                Text("= " + state.fmt.usd(-state.sizingEquity * state.riskPercent / 100) + " max")
                    .mono(12.5).foregroundStyle(Theme.red)
            }
            Slider(value: Binding(get: { state.riskPercent }, set: { state.riskPercent = ($0 * 20).rounded() / 20 }), in: 0.1...5)
                .tint(Theme.accent)
            HStack(spacing: 6) {
                ForEach([0.25, 0.5, 1.0, 2.0], id: \.self) { v in
                    Button(Fmt.number(v, decimals: v < 1 ? 2 : 0) + "%") { state.riskPercent = v }
                        .buttonStyle(ChipStyle(active: abs(state.riskPercent - v) < 0.001))
                        .demoAnchor("risk-\(v)")
                }
            }
            if state.paperMode {
                Text("Oefenmodus – live koersen, gesimuleerde orders. Uitzetten in Instellingen.")
                    .font(.system(size: 10.5)).foregroundStyle(Theme.accent)
            } else if state.isExampleEquity {
                Text("Voorbeeld met $10.000 – koppel je account in Instellingen voor je echte saldo.")
                    .font(.system(size: 10.5)).foregroundStyle(Theme.dim)
            }
        }
    }
}

struct NewTradeButtons: View {
    @EnvironmentObject var state: AppState
    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                Button { state.newTicket(long: true) } label: { Label("Long", systemImage: "arrow.up.right").frame(maxWidth: .infinity) }
                    .buttonStyle(BigButtonStyle(color: Theme.green))
                    .help("Nieuwe long (⌥L)")
                    .demoAnchor("btn-long")
                Button { state.newTicket(long: false) } label: { Label("Short", systemImage: "arrow.down.right").frame(maxWidth: .infinity) }
                    .buttonStyle(BigButtonStyle(color: Theme.red))
                    .help("Nieuwe short (⌥S)")
            }
            Text("Zet entry, stop-loss en take-profit in de chart en sleep ze naar de juiste prijs. Grip rekent je positiegrootte uit.")
                .font(.system(size: 11)).foregroundStyle(Theme.dim).multilineTextAlignment(.center)
        }
    }
}

struct TicketCard: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        let r = state.riskResult
        Card(title: "Nieuwe order", trailing: AnyView(r.map { SidePill(isLong: $0.isLong) })) {
            Picker("", selection: Binding(get: { state.ticket?.isMarket ?? false }, set: { state.ticket?.isMarket = $0 })) {
                Text("Limit").tag(false)
                Text("Market").tag(true)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .demoAnchor("ticket-type")

            VStack(spacing: 8) {
                if state.ticket?.isMarket == false {
                    PriceField(label: "Entry", color: Theme.blue, value: Binding(get: { state.ticket?.entry ?? 0 }, set: { state.ticket?.entry = $0 }))
                } else {
                    KV("Entry", "≈ " + Fmt.price(state.price), color: Theme.blue)
                }
                PriceField(label: "Stop-loss", color: Theme.red, value: Binding(get: { state.ticket?.stopLoss ?? 0 }, set: { state.ticket?.stopLoss = $0 }))
                PriceField(label: "Take-profit", color: Theme.green, value: Binding(get: { state.ticket?.takeProfit ?? 0 }, set: { state.ticket?.takeProfit = $0 > 0 ? $0 : nil }))
            }

            Divider().overlay(Theme.line)

            if let r {
                VStack(spacing: 7) {
                    KV("Positiegrootte", state.fmt.size(r.size, coin: state.coin, decimals: state.szDecimals))
                    KV("Notional", state.fmt.usd(r.notional))
                    KV("Hefboom", "\(r.leverage)×")
                    KV("Marge", state.fmt.usd(r.marginRequired))
                    KV("Risico", state.fmt.usd(-r.riskUsd), color: Theme.red)
                    if let rr = r.rewardRisk { KV("Risk : reward", "1 : " + Fmt.number(rr, decimals: 1)) }
                    KV("Liquidatie ±", Fmt.price(r.estLiquidationPx), color: Theme.muted)
                }
                ForEach(r.warnings, id: \.self) { w in
                    Label(w, systemImage: "exclamationmark.triangle.fill")
                        .font(.system(size: 11)).foregroundStyle(Theme.orange)
                }
            } else {
                Text("Stop-loss moet anders zijn dan de entry.").font(.system(size: 11.5)).foregroundStyle(Theme.muted)
            }

            HStack(spacing: 8) {
                Button("Annuleer") { state.ticket = nil }
                    .buttonStyle(BigButtonStyle(color: Theme.card, textColor: Theme.text))
                    .frame(width: 92)
                    .keyboardShortcut(.cancelAction)
                Button {
                    Task { await state.placeTicket() }
                } label: {
                    HStack {
                        if state.busy { ProgressView().controlSize(.small) }
                        Text(placeTitle(r))
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(BigButtonStyle(color: (r?.isLong ?? true) ? Theme.green : Theme.red))
                .disabled(r == nil || state.busy || (r?.size ?? 0) <= 0)
                .demoAnchor("btn-place")
                .keyboardShortcut(.return, modifiers: .command)
            }
            if !state.canTrade {
                Text("Om te handelen: voeg je wallet-adres en API-wallet toe in Instellingen.")
                    .font(.system(size: 10.5)).foregroundStyle(Theme.dim)
            }
        }
    }

    private func placeTitle(_ r: RiskResult?) -> String {
        let side = (r?.isLong ?? true) ? "long" : "short"
        return (state.ticket?.isMarket ?? false) ? "Market \(side)" : "Plaats limit \(side)"
    }
}

struct PriceField: View {
    var label: String
    var color: Color
    @Binding var value: Double

    var body: some View {
        HStack {
            Text(label).font(.system(size: 12.5)).foregroundStyle(Theme.muted)
            Spacer()
            TextField("", value: $value, format: .number.precision(.fractionLength(0...6)))
                .multilineTextAlignment(.trailing)
                .textFieldStyle(.plain)
                .mono(13, .semibold)
                .foregroundStyle(color)
                .frame(width: 120)
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background(RoundedRectangle(cornerRadius: 6).fill(Color.black.opacity(0.25)))
        }
    }
}

struct PositionCard: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        if let pos = state.position {
            let u = (state.price - pos.entryPx) * pos.size
            let eq = max(state.account.accountValue, 1)
            Card(title: "Open positie", trailing: AnyView(SidePill(isLong: pos.isLong))) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(state.fmt.signedUsd(u)).mono(26, .bold).foregroundStyle(Theme.pnl(u))
                    Text("\(state.fmt.size(pos.size, coin: state.coin, decimals: state.szDecimals)) @ \(Fmt.price(pos.entryPx)) · \(Fmt.percent(u / eq)) van portfolio")
                        .mono(11).foregroundStyle(Theme.muted)
                }
                VStack(spacing: 6) {
                    KV("Hefboom", "\(pos.leverage)× \(pos.isCross ? "cross" : "isolated")")
                    if let liq = pos.liquidationPx { KV("Liquidatie", Fmt.price(liq), color: Theme.orange) }
                }

                Text("DEELS SLUITEN (MARKET)").font(.system(size: 10.5, weight: .semibold)).tracking(0.8).foregroundStyle(Theme.muted)
                HStack(spacing: 6) {
                    ForEach([0.25, 0.5, 0.75, 1.0], id: \.self) { f in
                        Button("\(Int(f * 100))%") { Task { await state.closePosition(fraction: f) } }
                            .buttonStyle(ChipStyle(active: false, large: true))
                            .disabled(state.busy)
                            .demoAnchor("close-\(f)")
                    }
                }

                HStack {
                    Text("SLEEP-CLOSE IN CHART").font(.system(size: 10.5, weight: .semibold)).tracking(0.8).foregroundStyle(Theme.muted)
                    Spacer()
                    Picker("", selection: $state.dragCloseFraction) {
                        Text("25%").tag(0.25)
                        Text("50%").tag(0.5)
                        Text("100%").tag(1.0)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(width: 150)
                }
                Text("Sleep het oranje ✕ op de positielijn naar een prijs voor een limit close.")
                    .font(.system(size: 10.5)).foregroundStyle(Theme.dim)

                let hasTp = state.coinOrders.contains { $0.isTrigger && $0.tpsl == .tp }
                let hasSl = state.coinOrders.contains { $0.isTrigger && $0.tpsl == .sl }
                if !hasTp || !hasSl {
                    HStack(spacing: 6) {
                        if !hasTp { Button("+ Take-profit") { Task { await state.addPositionTpSl(.tp) } }.buttonStyle(ChipStyle(active: false, large: true)) }
                        if !hasSl { Button("+ Stop-loss") { Task { await state.addPositionTpSl(.sl) } }.buttonStyle(ChipStyle(active: false, large: true)) }
                    }
                }
            }
        }
    }
}

struct OrdersCard: View {
    @EnvironmentObject var state: AppState
    var body: some View {
        let orders = state.coinOrders
        if !orders.isEmpty {
            Card(title: "Open orders \(state.coin)") {
                ForEach(orders) { o in
                    HStack(spacing: 8) {
                        Circle().fill(color(o)).frame(width: 7, height: 7)
                        Text(state.orderName(o)).font(.system(size: 12))
                        Spacer()
                        Text(Fmt.price(state.pendingOrderPrices[o.oid] ?? o.displayPx)).mono(12)
                        Button {
                            Task { await state.cancelOrder(o.oid) }
                        } label: {
                            Image(systemName: "xmark.circle.fill").foregroundStyle(Theme.dim)
                        }
                        .buttonStyle(.plain)
                        .help("Annuleer")
                    }
                }
                Text("Tip: sleep een orderlijn in de chart om de prijs te wijzigen.").font(.system(size: 10.5)).foregroundStyle(Theme.dim)
            }
        }
    }

    private func color(_ o: OpenOrder) -> Color {
        if o.isTrigger { return o.tpsl == .tp ? Theme.green : Theme.red }
        return o.reduceOnly ? Theme.orange : Theme.blue
    }
}

// MARK: - Styles

struct BigButtonStyle: ButtonStyle {
    var color: Color
    var textColor: Color = Color(nsColor: NSColor(hex: 0x04150E))
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13.5, weight: .semibold))
            .foregroundStyle(textColor)
            .padding(.vertical, 11)
            .padding(.horizontal, 10)
            .background(RoundedRectangle(cornerRadius: 10).fill(color.opacity(configuration.isPressed ? 0.8 : 1)))
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
    }
}

struct ChipStyle: ButtonStyle {
    var active: Bool
    var large = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: large ? 12 : 11, weight: .semibold))
            .frame(maxWidth: .infinity)
            .padding(.vertical, large ? 8 : 5)
            .background(RoundedRectangle(cornerRadius: 7).fill(active ? Theme.accent.opacity(0.35) : Color.white.opacity(configuration.isPressed ? 0.14 : 0.06)))
            .overlay(RoundedRectangle(cornerRadius: 7).stroke(Theme.line))
            .foregroundStyle(Theme.text)
    }
}
#endif
