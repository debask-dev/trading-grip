#if os(macOS)
import SwiftUI
import GripCore

struct TradePanel: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                AccountCard()
                PanelModePicker()
                if state.panelMode == .quick {
                    QuickCard()
                } else if state.ticket != nil {
                    TicketCard()
                } else {
                    if state.panelMode == .risk { RiskCard() }
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

struct PanelModePicker: View {
    @EnvironmentObject var state: AppState
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Picker("", selection: $state.panelMode) {
                ForEach(PanelMode.allCases) { m in Text(m.label).tag(m) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            Text(state.panelMode.hint).font(.system(size: 10.5)).foregroundStyle(Theme.dim)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

struct AccountCard: View {
    @EnvironmentObject var state: AppState
    var body: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 3) {
                Text(state.account.mode.balancesOnSpot || state.paperMode ? "Portfolio" : "Perps-saldo").font(.system(size: 11.5)).foregroundStyle(Theme.muted)
                    .help(state.paperMode ? "Oefenaccount" : state.account.mode.label)
                Text(state.hasAccount ? state.fmt.usd(state.account.accountValue) : "–").mono(17, .semibold)
                if !state.paperMode && !state.account.mode.balancesOnSpot && state.account.spotValue > 0.005 {
                    Text("+ spot \(state.fmt.usd(state.account.spotValue, decimals: 2))").mono(11).foregroundStyle(Theme.muted)
                        .help("Je spot-saldo telt in een standaard account niet mee als marge voor perps. Zet het over naar perps, of zet Unified account aan op Hyperliquid.")
                }
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
                Text("Voorbeeld met $10.000 – koppel je account (⇧⌘A) voor je echte saldo.")
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
            Text("Zet entry, stop-loss en take-profits in de chart en sleep ze naar de juiste prijs. Rechtsklik in de chart voor een order op die prijs.")
                .font(.system(size: 11)).foregroundStyle(Theme.dim).multilineTextAlignment(.center)
        }
    }
}

// MARK: - Scrub field

/// A number you change by dragging left/right (⌥ fine, ⇧ coarse). Double-click to type.
struct ScrubField: View {
    var label: String
    var value: Double
    var step: Double
    var display: (Double) -> String
    var color: Color = Theme.text
    var range: ClosedRange<Double>? = nil
    /// nil = no lock; true/false = locked/unlocked.
    var locked: Bool? = nil
    var onLock: (() -> Void)? = nil
    var onChange: (Double) -> Void

    @State private var dragStart: Double?
    @State private var editing = false
    @State private var text = ""
    @State private var hovering = false
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 6) {
            Text(label).font(.system(size: 12.5)).foregroundStyle(Theme.muted)
            if let locked {
                Button { onLock?() } label: {
                    Image(systemName: locked ? "lock.fill" : "lock.open").font(.system(size: 10.5))
                        .foregroundStyle(locked ? Theme.accent : Theme.dim)
                }
                .buttonStyle(.plain)
                .help(locked ? "Vast: dit bepaalt de rest" : "Volgt uit de rest – klik om vast te zetten")
            }
            Spacer()
            if editing {
                TextField("", text: $text)
                    .focused($focused)
                    .multilineTextAlignment(.trailing)
                    .textFieldStyle(.plain)
                    .mono(13, .semibold)
                    .frame(width: 112)
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(RoundedRectangle(cornerRadius: 6).fill(Color.black.opacity(0.35)))
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(Theme.accent.opacity(0.6)))
                    .onSubmit { commit() }
                    .onExitCommand { editing = false }
                    .onChange(of: focused) { _, f in if !f { commit() } }
            } else {
                Text(display(value))
                    .mono(13, .semibold)
                    .foregroundStyle(color)
                    .frame(width: 112, alignment: .trailing)
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(RoundedRectangle(cornerRadius: 6).fill(Color.black.opacity(hovering || dragStart != nil ? 0.4 : 0.25)))
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(dragStart != nil ? Theme.accent.opacity(0.6) : Color.clear))
                    .contentShape(Rectangle())
                    .onHover { h in
                        hovering = h
                        if h { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() }
                    }
                    .gesture(
                        DragGesture(minimumDistance: 2)
                            .onChanged { g in
                                if dragStart == nil { dragStart = value }
                                let m = NSEvent.modifierFlags
                                let mult = m.contains(.option) ? 0.1 : (m.contains(.shift) ? 10 : 1)
                                onChange(clamp((dragStart ?? value) + Double(g.translation.width / 4).rounded() * step * mult))
                            }
                            .onEnded { _ in dragStart = nil }
                    )
                    .simultaneousGesture(TapGesture(count: 2).onEnded {
                        text = plain(value)
                        editing = true
                        focused = true
                    })
                    .help("Sleep links/rechts (⌥ fijn, ⇧ grof) · dubbelklik om te typen")
            }
        }
    }

    private func clamp(_ v: Double) -> Double {
        guard let r = range else { return v }
        return min(max(v, r.lowerBound), r.upperBound)
    }

    private func plain(_ v: Double) -> String {
        var s = String(format: "%.6f", v)
        while s.hasSuffix("0") { s.removeLast() }
        if s.hasSuffix(".") { s.removeLast() }
        return s
    }

    private func commit() {
        guard editing else { return }
        editing = false
        let cleaned = text.replacingOccurrences(of: ",", with: ".").filter { "0123456789.-".contains($0) }
        if let v = Double(cleaned) { onChange(clamp(v)) }
    }
}

// MARK: - Ticket (risk + manual panels)

struct TicketCard: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        let pl = state.plan
        let t = state.ticket
        let tick = state.priceTick
        let manual = state.panelMode == .manual
        let reduce = t?.reduceOnly == true
        Card(title: title(pl, t), trailing: AnyView(pill(pl, t))) {
            Picker("", selection: Binding(get: { state.ticket?.isMarket ?? false }, set: { state.ticket?.isMarket = $0 })) {
                Text("Limit").tag(false)
                Text(t.map { $0.entries.count > 1 } == true ? "E1 market" : "Market").tag(true)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .demoAnchor("ticket-type")

            // Size and leverage
            VStack(spacing: 7) {
                if !manual {
                    ScrubField(label: pl?.isAdd == true ? "Max verlies hele trade" : "Max verlies", value: state.riskPercent, step: 0.05,
                               display: { "\(Fmt.number($0, decimals: 2))% · \(state.fmt.usd(state.sizingEquity * $0 / 100, decimals: 2))" },
                               color: Theme.red, range: 0.05...10, locked: t?.lock == .risk, onLock: { state.toggleLock() }) { state.setTicketRisk($0) }
                }
                SizeField(plan: pl)
                if !reduce {
                    LeverageField(plan: pl)
                }
            }

            Divider().overlay(Theme.line)

            // Entries
            VStack(alignment: .leading, spacing: 7) {
                let entries = t?.entries ?? []
                ForEach(Array(entries.enumerated()), id: \.element.id) { i, e in
                    HStack(spacing: 6) {
                        if t?.isMarket == true && i == 0 {
                            KV(entries.count > 1 ? "E1" : (reduce ? "Prijs" : "Entry"), "market ≈ " + Fmt.price(state.price), color: Theme.blue)
                        } else {
                            ScrubField(label: entries.count > 1 ? "E\(i + 1)" : (reduce ? "Prijs" : "Entry"), value: e.price, step: tick, display: { Fmt.price($0) },
                                       color: reduce ? Theme.orange : Theme.blue, range: tick...1e12) {
                                if state.ticket?.entries.indices.contains(i) == true { state.ticket?.entries[i].price = state.roundToTick($0) }
                            }
                        }
                        if entries.count > 1 {
                            ScrubPct(value: e.pct) { state.setEntryPct(i, $0) }
                            RemoveButton(help: "Entry weghalen") { state.removeTicketEntry(i) }
                        }
                    }
                }
                HStack(spacing: 6) {
                    Button("+ Entry") { state.addTicketEntry() }
                        .buttonStyle(ChipStyle(active: false))
                        .disabled(entries.count >= 5)
                        .help("Gespreid \(reduce ? "verkleinen" : "instappen"): extra limit-order op een andere prijs")
                    if entries.count > 1 {
                        Button("Gelijk") { state.applyEntrySplit(state.defaultSplit(entries.count)) }.buttonStyle(ChipStyle(active: false))
                        if entries.count == 2 { Button("60/40") { state.applyEntrySplit([60, 40]) }.buttonStyle(ChipStyle(active: entries.map(\.pct) == [60, 40])) }
                        if entries.count == 3 { Button("50/30/20") { state.applyEntrySplit([50, 30, 20]) }.buttonStyle(ChipStyle(active: entries.map(\.pct) == [50, 30, 20])) }
                    }
                }
            }

            // Stop-loss
            if !reduce {
                if manual {
                    Toggle(isOn: Binding(get: { state.ticket?.useStopLoss ?? true }, set: { state.ticket?.useStopLoss = $0 })) {
                        Text(pl?.isAdd == true ? "Stop-loss (hele positie)" : "Stop-loss").font(.system(size: 12))
                    }
                    .toggleStyle(.checkbox)
                }
                if t?.useStopLoss != false {
                    ScrubField(label: manual ? "  Prijs" : (pl?.isAdd == true ? "Stop-loss (hele positie)" : "Stop-loss"), value: t?.stopLoss ?? 0, step: tick,
                               display: { Fmt.price($0) }, color: Theme.red, range: tick...1e12) {
                        state.ticket?.stopLoss = state.roundToTick($0)
                    }
                }
            }

            // Take-profits
            if !reduce {
                if pl?.isAdd == true && (t?.tps.isEmpty ?? true) && !state.existingTPOrders.isEmpty {
                    ExistingTPsView(plan: pl)
                } else {
                    TPLadder(optional: manual)
                }
            }

            Divider().overlay(Theme.line)

            if let pl {
                if let before = pl.before, !reduce {
                    BeforeAfterView(before: before, after: pl.after, plan: pl)
                }
                VStack(spacing: 6) {
                    if reduce {
                        KV("Resultaat van dit deel ≈", state.fmt.signedUsd(pl.reducePnl ?? 0, decimals: 2), color: Theme.pnl(pl.reducePnl ?? 0))
                        KV("Positie na", state.fmt.size(pl.after.size, coin: state.coin, decimals: state.szDecimals))
                    } else {
                        if pl.before == nil {
                            KV("Notional", state.fmt.usd(pl.notional))
                            KV("Marge", state.fmt.usd(pl.marginRequired))
                        }
                        if (t?.entries.count ?? 1) > 1 { KV(pl.isAdd ? "Gem. entry bijkoop" : "Gem. entry als alles vult", Fmt.price(pl.avgEntry), color: Theme.blue) }
                        if let risk = pl.riskUsd {
                            KV(pl.isAdd ? "Risico hele trade" : "Risico tot stop", "\(state.fmt.usd(-risk, decimals: 2)) · \(Fmt.number(pl.riskPercentActual ?? 0, decimals: 2))%", color: Theme.red)
                        } else {
                            KV("Risico", "geen stop-loss", color: Theme.orange)
                        }
                        if let first = pl.riskFirstEntryOnly { KV("Als alleen E1 vult", state.fmt.usd(-first, decimals: 2), color: Theme.red) }
                        KV("Fees (in\(t?.useStopLoss == false ? "" : " + stop"))", state.fmt.usd(pl.estFees, decimals: 2), color: Theme.muted)
                        if let rr = pl.rewardRisk { KV("Risk : reward", "1 : " + Fmt.number(rr, decimals: 1)) }
                        if let p = pl.potentialProfit { KV("Winst alle TP's", state.fmt.signedUsd(p, decimals: 2), color: Theme.green) }
                        if pl.before == nil { KV("Liquidatie ±", Fmt.price(pl.estLiquidationPx), color: Theme.orange) }
                    }
                }
                ForEach(pl.warnings, id: \.self) { w in
                    Label(w, systemImage: "exclamationmark.triangle.fill")
                        .font(.system(size: 11)).foregroundStyle(Theme.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else {
                Text("Vul een entry in.").font(.system(size: 11.5)).foregroundStyle(Theme.muted)
            }

            HStack(spacing: 8) {
                Button("Annuleer") { state.ticket = nil }
                    .buttonStyle(BigButtonStyle(color: Theme.card, textColor: Theme.text))
                    .frame(width: 92)
                    .keyboardShortcut(.cancelAction)
                Button {
                    state.requestPlaceTicket()
                } label: {
                    HStack {
                        if state.busy { ProgressView().controlSize(.small) }
                        Text(placeTitle(pl, t))
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(BigButtonStyle(color: reduce ? Theme.orange : ((t?.isLong ?? true) ? Theme.green : Theme.red)))
                .disabled(pl == nil || state.busy || (pl?.size ?? 0) <= 0)
                .demoAnchor("btn-place")
                .keyboardShortcut(.return, modifiers: .command)
            }
            if !state.canTrade {
                Text("Om te handelen: koppel een account met API-wallet (⇧⌘A).")
                    .font(.system(size: 10.5)).foregroundStyle(Theme.dim)
            }
        }
    }

    private func title(_ pl: Plan?, _ t: Ticket?) -> String {
        guard let t else { return "Nieuwe order" }
        if t.reduceOnly { return "Verkleinen · \(state.coin)" }
        if pl?.isAdd == true { return "Bijkopen · \(state.coin) \(t.isLong ? "long" : "short")" }
        return "Nieuwe order"
    }

    private func pill(_ pl: Plan?, _ t: Ticket?) -> some View {
        Group {
            if t?.reduceOnly == true {
                Text("REDUCE").font(.system(size: 10.5, weight: .bold)).foregroundStyle(Theme.orange)
                    .padding(.horizontal, 7).padding(.vertical, 2)
                    .background(RoundedRectangle(cornerRadius: 5).fill(Theme.orange.opacity(0.15)))
            } else if pl?.isAdd == true {
                Text("+ BIJ").font(.system(size: 10.5, weight: .bold)).foregroundStyle(Theme.accent)
                    .padding(.horizontal, 7).padding(.vertical, 2)
                    .background(RoundedRectangle(cornerRadius: 5).fill(Theme.accent.opacity(0.2)))
            } else if let t {
                SidePill(isLong: t.isLong)
            }
        }
    }

    private func placeTitle(_ pl: Plan?, _ t: Ticket?) -> String {
        guard let t else { return "Plaats" }
        let side = t.isLong ? "long" : "short"
        let n = t.entries.count
        if t.reduceOnly { return t.isMarket && n == 1 ? "Verklein (market)" : "Verklein" }
        if pl?.isAdd == true { return t.isMarket ? "Koop bij (market)" : (n > 1 ? "Plaats \(n) bijkoop-orders" : "Koop bij") }
        if n > 1 { return "Plaats \(n) entries" }
        return t.isMarket ? "Market \(side)" : "Plaats limit \(side)"
    }
}

/// Size in coins, or in dollars (manual panel).
struct SizeField: View {
    @EnvironmentObject var state: AppState
    let plan: Plan?

    var body: some View {
        let t = state.ticket
        let manual = state.panelMode == .manual
        let fixed = manual || t?.lock == .size || t?.reduceOnly == true
        let coins = fixed ? (t?.size ?? plan?.size ?? 0) : (plan?.size ?? 0)
        let px = max(plan?.avgEntry ?? state.price, 1e-9)
        let usd = t?.sizeInUsd == true
        HStack(spacing: 6) {
            ScrubField(label: t?.reduceOnly == true ? "Verkleinen met" : (plan?.isAdd == true ? "Erbij" : "Grootte"),
                       value: usd ? coins * px : coins,
                       step: usd ? max(5, coins * px / 200) : max(pow(10, -Double(state.szDecimals)), coins / 200),
                       display: { usd ? state.fmt.usd($0) : state.fmt.size($0, coin: state.coin, decimals: state.szDecimals) },
                       range: 0...1e12,
                       locked: state.panelMode == .risk ? (t?.lock == .size) : nil, onLock: { state.toggleLock() }) { v in
                state.setTicketSize(usd ? v / px : v)
            }
            if manual {
                Button(usd ? "$" : state.coin) { state.ticket?.sizeInUsd.toggle() }
                    .buttonStyle(.plain)
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(Theme.accent)
                    .frame(width: 34)
                    .help("Grootte in \(usd ? state.coin : "dollars") invullen")
            }
        }
        if t?.reduceOnly == true, let pos = state.position {
            HStack(spacing: 6) {
                ForEach([0.25, 0.5, 0.75, 1.0], id: \.self) { f in
                    Button("\(Int(f * 100))%") { state.setTicketSize(HLFormat.roundSize(abs(pos.size) * f, szDecimals: state.szDecimals)) }
                        .buttonStyle(ChipStyle(active: false))
                }
            }
        }
    }
}

struct LeverageField: View {
    @EnvironmentObject var state: AppState
    let plan: Plan?

    var body: some View {
        let t = state.ticket
        let current = state.position?.leverage
        HStack(spacing: 6) {
            ScrubField(label: current.map { "Hefboom (nu \($0)×)" } ?? "Hefboom", value: Double(t?.leverage ?? plan?.leverage ?? 1), step: 1,
                       display: { "\(Int($0))×\(t?.leverage == nil ? " auto" : "")" },
                       range: 1...Double(state.asset?.maxLeverage ?? 50)) { state.setTicketLeverage(Int($0.rounded())) }
            if t?.leverage != nil {
                Button("auto") { state.setTicketLeverage(nil) }
                    .buttonStyle(.plain)
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(Theme.accent)
                    .help("Automatisch: wat nodig is, nooit lager dan je huidige hefboom")
            }
        }
    }
}

struct RemoveButton: View {
    var help: String
    var action: () -> Void
    var body: some View {
        Button(action: action) { Image(systemName: "xmark.circle.fill").foregroundStyle(Theme.dim) }
            .buttonStyle(.plain)
            .help(help)
    }
}

/// Position now → after adding.
struct BeforeAfterView: View {
    @EnvironmentObject var state: AppState
    let before: PositionSnapshot
    let after: PositionSnapshot
    let plan: Plan

    var body: some View {
        let f = state.fmt
        let d = state.szDecimals
        Grid(alignment: .trailing, horizontalSpacing: 8, verticalSpacing: 4) {
            GridRow {
                Text("").gridColumnAlignment(.leading)
                Text("NU").font(.system(size: 9.5, weight: .semibold)).foregroundStyle(Theme.dim)
                Text("")
                Text("NA").font(.system(size: 9.5, weight: .semibold)).foregroundStyle(Theme.dim)
            }
            row("Grootte", f.size(before.size, coin: "", decimals: d), f.size(after.size, coin: state.coin, decimals: d))
            row("Gem. entry", Fmt.price(before.avgEntry), Fmt.price(after.avgEntry))
            row("Break-even", Fmt.price(state.breakEven ?? before.breakEven), Fmt.price(after.breakEven))
            if let r = after.riskUsd {
                row("Risico tot stop", before.riskUsd.map { f.usd(-max($0, 0), decimals: 0) } ?? "–", f.usd(-r, decimals: 2), color: Theme.red)
            }
            row("Marge", f.usd(before.margin, decimals: 0), f.usd(after.margin, decimals: 0))
            row("Liquidatie ≈", Fmt.price(state.position?.liquidationPx ?? before.estLiquidationPx), Fmt.price(after.estLiquidationPx), color: Theme.orange)
        }
        .font(.system(size: 11.5))
    }

    private func row(_ k: String, _ a: String, _ b: String, color: Color = Theme.text) -> some View {
        GridRow {
            Text(k).foregroundStyle(Theme.muted).gridColumnAlignment(.leading)
            Text(a).mono(11).foregroundStyle(Theme.muted)
            Text("→").foregroundStyle(Theme.dim)
            Text(b).mono(11, .semibold).foregroundStyle(color)
        }
    }
}

/// While adding: the take-profits already on the position, and how big they become.
struct ExistingTPsView: View {
    @EnvironmentObject var state: AppState
    let plan: Plan?

    var body: some View {
        let pos = state.position
        let factor = (plan?.after.size ?? 0) / max(abs(pos?.size ?? 1), 1e-12)
        VStack(alignment: .leading, spacing: 5) {
            Text("TAKE-PROFITS GROEIEN MEE").font(.system(size: 10, weight: .semibold)).tracking(0.6).foregroundStyle(Theme.muted)
            ForEach(state.existingTPOrders) { o in
                HStack {
                    Text("TP \(Fmt.price(o.displayPx))").mono(11.5).foregroundStyle(Theme.green)
                    Spacer()
                    if o.size > 0 {
                        Text("\(state.fmt.size(o.size, coin: "", decimals: state.szDecimals)) → \(state.fmt.size(o.size * factor, coin: state.coin, decimals: state.szDecimals))").mono(11)
                    } else {
                        Text("hele positie").font(.system(size: 11)).foregroundStyle(Theme.muted)
                    }
                }
            }
            Button("Nieuwe TP-ladder in plaats hiervan") { state.addTicketTP() }
                .buttonStyle(ChipStyle(active: false))
        }
    }
}

/// Take-profit ladder: price and share per level, presets, break-even option.
struct TPLadder: View {
    @EnvironmentObject var state: AppState
    var optional = false

    var body: some View {
        let tps = state.ticket?.tps ?? []
        let tick = state.priceTick
        VStack(alignment: .leading, spacing: 7) {
            ForEach(Array(tps.enumerated()), id: \.element.id) { i, tp in
                HStack(spacing: 6) {
                    ScrubField(label: "TP\(i + 1)", value: tp.price, step: tick, display: { Fmt.price($0) }, color: Theme.green, range: tick...1e12) {
                        if state.ticket?.tps.indices.contains(i) == true { state.ticket?.tps[i].price = state.roundToTick($0) }
                    }
                    if tps.count > 1 { ScrubPct(value: tp.pct) { state.setTPPct(i, $0) } }
                    if tps.count > 1 || optional { RemoveButton(help: "Take-profit weghalen") { state.removeTicketTP(i) } }
                }
            }
            HStack(spacing: 6) {
                Button("+ TP") { state.addTicketTP() }
                    .buttonStyle(ChipStyle(active: false))
                    .disabled(tps.count >= 5)
                if tps.count > 1 {
                    Button("Gelijk") { state.applySplitPreset(state.defaultSplit(tps.count)) }
                        .buttonStyle(ChipStyle(active: false))
                    if tps.count == 2 { Button("70/30") { state.applySplitPreset([70, 30]) }.buttonStyle(ChipStyle(active: tps.map(\.pct) == [70, 30])) }
                    if tps.count == 3 { Button("50/30/20") { state.applySplitPreset([50, 30, 20]) }.buttonStyle(ChipStyle(active: tps.map(\.pct) == [50, 30, 20])) }
                }
            }
            if tps.count > 1 && state.ticket?.useStopLoss != false {
                Toggle(isOn: Binding(get: { state.ticket?.moveSLToBreakEven ?? false }, set: { state.ticket?.moveSLToBreakEven = $0 })) {
                    Text("Stop naar break-even na TP1").font(.system(size: 11.5))
                }
                .toggleStyle(.checkbox)
            }
            if !tps.isEmpty {
                Text("TP's zijn limit-orders (reduce-only). Grip plaatst ze zodra er een positie is, en laat ze meegroeien als er meer entries vullen.")
                    .font(.system(size: 10)).foregroundStyle(Theme.dim).fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// Small percentage scrubber for the TP ladder.
struct ScrubPct: View {
    var value: Double
    var onChange: (Double) -> Void
    @State private var start: Double?
    var body: some View {
        Text("\(Int(value))%")
            .mono(11.5, .semibold)
            .frame(width: 40)
            .padding(.vertical, 4)
            .background(RoundedRectangle(cornerRadius: 6).fill(Color.white.opacity(start == nil ? 0.06 : 0.14)))
            .contentShape(Rectangle())
            .onHover { h in if h { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() } }
            .gesture(DragGesture(minimumDistance: 2)
                .onChanged { g in
                    if start == nil { start = value }
                    onChange((start ?? value) + Double(g.translation.width / 6).rounded() * 5)
                }
                .onEnded { _ in start = nil })
            .help("Deel van de positie – sleep links/rechts")
    }
}

// MARK: - Quick panel

struct QuickCard: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        let p = state.price
        let size = p > 0 ? state.quickUsd / p : 0
        let riskUsd = size * p * state.quickSLPct / 100
        Card(title: "Snel traden") {
            VStack(spacing: 7) {
                ScrubField(label: "Orderwaarde", value: state.quickUsd, step: 10, display: { state.fmt.usd($0) }, range: 10...10_000_000) { state.quickUsd = $0.rounded() }
                ScrubField(label: "Hefboom", value: Double(state.quickLev), step: 1, display: { "\(Int($0))×" },
                           range: 1...Double(state.asset?.maxLeverage ?? 50)) { state.quickLev = Int($0.rounded()) }
                ScrubField(label: "Stop-loss", value: state.quickSLPct, step: 0.05, display: { "\(Fmt.number($0, decimals: 2))%" }, color: Theme.red, range: 0.05...50) { state.quickSLPct = $0 }
                ScrubField(label: "Take-profit", value: state.quickTPPct, step: 0.05, display: { "\(Fmt.number($0, decimals: 2))%" }, color: Theme.green, range: 0.05...200) { state.quickTPPct = $0 }
            }
            VStack(spacing: 5) {
                KV("Grootte", state.fmt.size(size, coin: state.coin, decimals: state.szDecimals))
                KV("Marge", state.fmt.usd(state.quickUsd / Double(max(state.quickLev, 1))))
                KV("Risico tot stop ≈", "\(state.fmt.usd(-riskUsd, decimals: 2)) · \(Fmt.number(riskUsd / max(state.sizingEquity, 1) * 100, decimals: 2))%", color: Theme.red)
            }
            HStack(spacing: 8) {
                Button { state.quickTrade(long: true) } label: { Text("Market long").frame(maxWidth: .infinity) }
                    .buttonStyle(BigButtonStyle(color: Theme.green))
                    .help("⌥B")
                Button { state.quickTrade(long: false) } label: { Text("Market short").frame(maxWidth: .infinity) }
                    .buttonStyle(BigButtonStyle(color: Theme.red))
                    .help("⌥N")
            }
            .disabled(state.busy)
            if state.position != nil {
                Button { state.quickClose() } label: { Text("Sluit \(state.coin)-positie").frame(maxWidth: .infinity) }
                    .buttonStyle(BigButtonStyle(color: Theme.card, textColor: Theme.text))
                    .help("⌥X")
            }
            Text("⌥B long · ⌥N short · ⌥X sluiten")
                .font(.system(size: 10.5)).foregroundStyle(Theme.dim)
        }
    }
}

struct PositionCard: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        if let pos = state.position {
            let u = state.net(for: pos)
            let eq = max(state.account.accountValue, 1)
            let ot = state.openTrade
            Card(title: "Open positie", trailing: AnyView(SidePill(isLong: pos.isLong))) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(state.fmt.signedUsd(u)).mono(26, .bold).foregroundStyle(Theme.pnl(u))
                    Text("netto na fees · \(Fmt.percent(u / eq)) van portfolio")
                        .mono(11).foregroundStyle(Theme.muted)
                }
                VStack(spacing: 6) {
                    KV("Gem. entry", Fmt.price(pos.entryPx), color: Theme.blue)
                    if let be = state.breakEven { KV("Break-even", Fmt.price(be), color: Theme.muted) }
                    if let ot {
                        if ot.realized != 0 { KV("Al gerealiseerd", state.fmt.signedUsd(ot.realized, decimals: 2), color: Theme.pnl(ot.realized)) }
                        KV("Fees betaald", state.fmt.usd(-ot.feesPaid, decimals: 2), color: Theme.muted)
                        if ot.funding != 0 { KV("Funding", state.fmt.signedUsd(ot.funding, decimals: 2), color: Theme.pnl(ot.funding)) }
                    }
                    KV("Hefboom", "\(pos.leverage)× \(pos.isCross ? "cross" : "isolated")")
                    if let liq = pos.liquidationPx { KV("Liquidatie", Fmt.price(liq), color: Theme.orange) }
                }

                HStack(spacing: 6) {
                    Button("+ Bijkopen") { state.newTicket(long: pos.isLong) }
                        .buttonStyle(ChipStyle(active: false, large: true))
                        .help("Extra entry op deze positie. Stop en take-profits groeien mee.")
                    Button("Verkleinen…") { state.panelMode = .manual; state.newTicket(long: !pos.isLong) }
                        .buttonStyle(ChipStyle(active: false, large: true))
                        .help("Limit-order die je positie kleiner maakt (reduce-only)")
                }
                Text("DEELS SLUITEN (MARKET)").font(.system(size: 10.5, weight: .semibold)).tracking(0.8).foregroundStyle(Theme.muted)
                HStack(spacing: 6) {
                    ForEach([0.25, 0.5, 0.75, 1.0], id: \.self) { f in
                        Button("\(Int(f * 100))%") { state.requestClose(fraction: f) }
                            .buttonStyle(ChipStyle(active: false, large: true))
                            .disabled(state.busy)
                            .demoAnchor("close-\(f)")
                    }
                }
                Text("Rechtsklik in de chart om een deel op een prijs te sluiten, of ✕ op de positielijn om alles te sluiten.")
                    .font(.system(size: 10.5)).foregroundStyle(Theme.dim).fixedSize(horizontal: false, vertical: true)

                let hasTp = state.coinOrders.contains { ($0.isTrigger && $0.tpsl == .tp) || (!$0.isTrigger && $0.reduceOnly) }
                let sl = state.coinOrders.first { $0.isTrigger && $0.tpsl == .sl }
                HStack(spacing: 6) {
                    if !hasTp { Button("+ Take-profit") { Task { await state.addPositionTpSl(.tp) } }.buttonStyle(ChipStyle(active: false, large: true)) }
                    if sl == nil { Button("+ Stop-loss") { Task { await state.addPositionTpSl(.sl) } }.buttonStyle(ChipStyle(active: false, large: true)) }
                    if let sl, let be = state.breakEven, pos.isLong ? be > sl.displayPx : be < sl.displayPx {
                        Button("Stop → break-even") { Task { await state.moveStopToBreakEven(coin: pos.coin, force: true) } }
                            .buttonStyle(ChipStyle(active: false, large: true))
                            .help("Zet de stop-loss op \(Fmt.price(be)): deze trade kan dan niet meer verliezen (na fees).")
                    }
                }
                if state.breakEvenAfterTP.contains(pos.coin) {
                    Label("Stop gaat naar break-even na de eerste TP", systemImage: "arrow.right.to.line")
                        .font(.system(size: 10.5)).foregroundStyle(Theme.accent)
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
    func makeBody(configuration: Configuration) -> some View { BigBody(configuration: configuration, color: color, textColor: textColor) }

    private struct BigBody: View {
        let configuration: ButtonStyleConfiguration
        let color: Color
        let textColor: Color
        @State private var hovering = false
        @Environment(\.isEnabled) private var enabled
        var body: some View {
            configuration.label
                .font(.system(size: 13.5, weight: .semibold))
                .foregroundStyle(textColor)
                .padding(.vertical, 11)
                .padding(.horizontal, 10)
                .background(RoundedRectangle(cornerRadius: 10).fill(color.opacity(configuration.isPressed ? 0.8 : 1)))
                .brightness(hovering && enabled ? 0.07 : 0)
                .opacity(enabled ? 1 : 0.5)
                .scaleEffect(configuration.isPressed ? 0.98 : 1)
                .contentShape(Rectangle())
                .onHover { hovering = $0 }
                .animation(.easeOut(duration: 0.12), value: hovering)
        }
    }
}

struct ChipStyle: ButtonStyle {
    var active: Bool
    var large = false
    func makeBody(configuration: Configuration) -> some View { ChipBody(configuration: configuration, active: active, large: large) }

    private struct ChipBody: View {
        let configuration: ButtonStyleConfiguration
        let active: Bool
        let large: Bool
        @State private var hovering = false
        var body: some View {
            configuration.label
                .font(.system(size: large ? 12 : 11, weight: .semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, large ? 8 : 5)
                .background(RoundedRectangle(cornerRadius: 7).fill(active ? Theme.accent.opacity(0.35) : Color.white.opacity(configuration.isPressed ? 0.16 : (hovering ? 0.11 : 0.06))))
                .overlay(RoundedRectangle(cornerRadius: 7).stroke(hovering ? Theme.muted.opacity(0.5) : Theme.line))
                .foregroundStyle(Theme.text)
                .contentShape(Rectangle())
                .onHover { hovering = $0 }
                .animation(.easeOut(duration: 0.12), value: hovering)
        }
    }
}
#endif
