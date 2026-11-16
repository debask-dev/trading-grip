#if os(macOS)
import SwiftUI
import AppKit
import GripCore

/// Two tabs. Order: one form for a new order, sized by your max loss, by an amount or by a share of the account.
/// Positie: everything after you're in.
struct TradePanel: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                AccountCard()
                Picker("", selection: Binding(get: { state.panelMode == .position },
                                              set: { state.panelMode = $0 ? .position : state.lastOrderMode })) {
                    Text(T("Order")).tag(false)
                    Text(state.position != nil ? T("Positie") + " ●" : T("Positie")).tag(true)
                }
                .pickerStyle(.segmented)
                .labelsHidden()

                if state.panelMode != .position {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(T("GROOTTE VIA")).font(.system(size: 9.5, weight: .semibold)).tracking(0.6).foregroundStyle(Theme.dim)
                        Picker("", selection: $state.panelMode) {
                            ForEach(PanelMode.sizing) { m in Text(m.label).tag(m) }
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        .help(T("Max verlies: Grip rekent de grootte uit je stop. Bedrag: je kiest zelf marge en hefboom. % account: een vast deel van je account, stop daarna."))
                    }
                }

                switch state.panelMode {
                case .fast:
                    QuickCard()
                    if state.position != nil { PositionSummary() }
                case .risk, .amount:
                    if state.ticket != nil && state.ticket?.reduceOnly != true {
                        TicketCard()
                    } else {
                        NewTradeButtons()
                    }
                    if state.position != nil { PositionSummary() }
                case .position:
                    PositionTab()
                }
                if state.panelMode != .position { OrdersCard() }
                if let err = state.accountError {
                    Text(err).font(.system(size: 11)).foregroundStyle(Theme.red).frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(16)
        }
        .onAppear { state.ensureDraftTicket() }
        .onChange(of: state.ticket == nil) { state.ensureDraftTicket() }
        .onChange(of: state.coin) { state.ensureDraftTicket() }
        .onChange(of: state.panelMode) { state.ensureDraftTicket() }
        .onChange(of: state.position == nil) { state.ensureDraftTicket() }
    }
}

struct AccountCard: View {
    @EnvironmentObject var state: AppState
    var body: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 3) {
                Text(state.account.mode.balancesOnSpot || state.paperMode ? T("Portfolio") : T("Perps-saldo")).font(.system(size: 11.5)).foregroundStyle(Theme.muted)
                    .help(state.paperMode ? T("Oefenaccount") : T(state.account.mode.label))
                Text(state.hasAccount ? state.fmt.usd(state.account.accountValue) : "–").mono(17, .semibold)
                if !state.paperMode && !state.account.mode.balancesOnSpot && state.account.spotValue > 0.005 {
                    Text(T("+ spot \(state.fmt.usd(state.account.spotValue, decimals: 2))")).mono(11).foregroundStyle(Theme.muted)
                        .help(T("Je spot-saldo telt in een standaard account niet mee als marge voor perps. Zet het over naar perps, of zet Unified account aan op Hyperliquid."))
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 3) {
                Text(T("Open PnL")).font(.system(size: 11.5)).foregroundStyle(Theme.muted)
                let u = state.account.positions.reduce(0) { $0 + $1.unrealizedPnl }
                Text(state.hasAccount ? state.fmt.signedUsd(u) : "–").mono(17, .semibold).foregroundStyle(state.hasAccount ? Theme.pnl(u) : Theme.muted)
            }
        }
        .padding(.horizontal, 2)
    }
}


struct NewTradeButtons: View {
    @EnvironmentObject var state: AppState
    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                Button { state.newTicket(long: true) } label: { Label(T("Long"), systemImage: "arrow.up.right").frame(maxWidth: .infinity) }
                    .buttonStyle(BigButtonStyle(color: Theme.green))
                    .help(T("Nieuwe long (⌥L)"))
                    .demoAnchor("btn-long")
                Button { state.newTicket(long: false) } label: { Label(T("Short"), systemImage: "arrow.down.right").frame(maxWidth: .infinity) }
                    .buttonStyle(BigButtonStyle(color: Theme.red))
                    .help(T("Nieuwe short (⌥S)"))
            }
            Text(state.panelMode == .risk
                 ? T("Je kiest je max verlies en waar je stop staat; Grip rekent uit hoe groot de positie wordt.")
                 : T("Je kiest zelf hoeveel en met welke hefboom. Stop en take-profit zijn optioneel."))
                .font(.system(size: 11)).foregroundStyle(Theme.dim).multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - Snel

/// Snel: long or short, market or limit, % of the account as margin, place. Stop and TPs come afterwards.
struct QuickCard: View {
    @EnvironmentObject var state: AppState
    private var priceDecimals: Int { max(0, -Int(floor(log10(state.priceTick) + 1e-9))) }

    var body: some View {
        let pl = state.ticket != nil ? state.plan : nil
        let long = state.quickLong
        let sideColor = long ? Theme.green : Theme.red
        let maxLev = Double(state.asset?.maxLeverage ?? 50)
        VStack(alignment: .leading, spacing: 11) {
            HStack(spacing: 6) {
                sideButton(true)
                sideButton(false)
            }
            HStack(spacing: 8) {
                Picker("", selection: $state.quickMarket) {
                    Text(T("Market")).tag(true)
                    Text(T("Limit")).tag(false)
                }
                .pickerStyle(.segmented).labelsHidden().frame(width: 130)
                Spacer(minLength: 4)
                if state.quickMarket {
                    Text("≈ " + Fmt.price(state.price)).mono(12).foregroundStyle(Theme.muted)
                } else if let e = state.ticket?.entry {
                    NumberField(value: e, step: state.priceTick, decimals: priceDecimals, grouping: true, color: Theme.blue,
                                range: state.priceTick...1e12) { v in state.ticket?.entry = state.roundToTick(v) }
                        .help(T("Limietprijs. Je kunt ook de lijn in de chart slepen."))
                }
            }
            chipRow(T("Marge: % van je portfolio")) {
                ForEach([5.0, 10, 25, 50], id: \.self) { p in
                    Button("\(Int(p))%") { state.quickPct = p }.buttonStyle(ChipStyle(active: state.quickPct == p))
                }
                NumberField(value: state.quickPct, step: 1, decimals: 0, range: 1...100, suffix: "%", width: 36) { state.quickPct = $0 }
            }
            chipRow(T("Hefboom")) {
                ForEach([3, 5, 10, 20].filter { Double($0) <= maxLev }, id: \.self) { l in
                    Button("\(l)×") { state.fastLev = l }.buttonStyle(ChipStyle(active: state.quickLeverage == l))
                }
                NumberField(value: Double(state.quickLeverage), step: 1, decimals: 0, range: 1...maxLev, suffix: T("×"), width: 36) {
                    state.fastLev = Int($0.rounded())
                }
            }
            if let pos = state.position, pos.leverage > state.fastLev {
                Text(T("Hefboom blijft \(pos.leverage)× zolang je positie open is."))
                    .font(.system(size: 10.5)).foregroundStyle(Theme.dim)
            }
            VStack(spacing: 3) {
                KV(T("Marge"), state.fmt.usd(state.quickMargin, decimals: 2) + " · \(state.quickLeverage)×")
                    .help(state.isExampleEquity ? T("Voorbeeld met $10.000: koppel je account voor echte bedragen.") : "")
                if let pl {
                    KV(T("Positie"), state.fmt.size(pl.size, coin: state.coin, decimals: state.szDecimals) + " · " + state.fmt.usd(pl.size * pl.avgEntry))
                    if pl.estLiquidationPx > 0 { KV(T("Liquidatie"), Fmt.price(pl.estLiquidationPx), color: Theme.red) }
                }
            }
            if let why = state.quickBlocked {
                Label(why, systemImage: "exclamationmark.triangle.fill").font(.system(size: 11)).foregroundStyle(Theme.orange)
            } else if let w = pl?.warnings.first {
                Label(T(w), systemImage: "exclamationmark.triangle.fill").font(.system(size: 11)).foregroundStyle(Theme.orange)
            }
            let quickTitle = T("\(long ? "Long" : "Short") \(Int(state.quickPct))% · \(state.quickMarket ? "market" : "limit " + Fmt.price(state.ticket?.entry ?? state.price))")
            let quickOff = state.busy || state.quickBlocked != nil || (pl?.size ?? 0) <= 0 || !(pl?.blockers.isEmpty ?? true)
            if state.quickMarket {
                HoldButton(title: quickTitle, color: sideColor, textColor: long ? Color(nsColor: NSColor(hex: 0x04150E)) : .white, disabled: quickOff) { state.placeQuick() }
            } else {
                Button { state.placeQuick() } label: { Text(quickTitle).frame(maxWidth: .infinity) }
                    .buttonStyle(BigButtonStyle(color: sideColor, textColor: long ? Color(nsColor: NSColor(hex: 0x04150E)) : .white))
                    .disabled(quickOff)
            }
            Text(state.quickMarket ? T("Houd de knop even ingedrukt: market zonder stop. Stop en take-profit zet je daarna in Positie.")
                                   : T("De limit staat als lijn in de chart; sleep om de prijs te kiezen. Stop en take-profit daarna."))
                .font(.system(size: 10.5)).foregroundStyle(Theme.dim).multilineTextAlignment(.center).frame(maxWidth: .infinity)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 10).fill(Theme.card))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.line))
        .onAppear { state.syncQuickTicket() }
        .onChange(of: state.coin) { state.syncQuickTicket() }
        .onChange(of: state.ticket == nil) { state.syncQuickTicket() }
        .onChange(of: state.price > 0) { state.syncQuickTicket() }
    }

    private func chipRow<C: View>(_ label: String, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label).font(.system(size: 11.5)).foregroundStyle(Theme.muted)
            HStack(spacing: 4) { content() }
        }
    }

    private func sideButton(_ long: Bool) -> some View {
        let on = state.quickLong == long
        let c = long ? Theme.green : Theme.red
        return Button { state.quickLong = long } label: {
            Label(long ? T("Long") : T("Short"), systemImage: long ? "arrow.up.right" : "arrow.down.right")
                .font(.system(size: 13, weight: .semibold))
                .frame(maxWidth: .infinity).padding(.vertical, 8)
                .foregroundStyle(on ? c : Theme.muted)
                .background(RoundedRectangle(cornerRadius: 8).fill(on ? c.opacity(0.16) : Color.clear))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(on ? c.opacity(0.6) : Theme.line))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(long ? T("Long (⌥L)") : T("Short (⌥S)"))
    }
}

// MARK: - Number field

/// A number you type. ↑ ↓ change it a step (⇧ ×10, ⌥ ×0.1). Optional list of preset values behind ▾.
struct NumberField: View {
    var value: Double
    var step: Double
    var decimals: Int
    /// Price fields: "64.350" means 64350 (Dutch thousands separator).
    var grouping = false
    var color: Color = Theme.text
    var range: ClosedRange<Double>? = nil
    var suffix: String? = nil
    var presets: [(String, Double)] = []
    var width: CGFloat = 96
    var onChange: (Double) -> Void

    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 3) {
            TextField("", text: $text)
                .focused($focused)
                .textFieldStyle(.plain)
                .multilineTextAlignment(.trailing)
                .mono(12.5, .semibold)
                .foregroundStyle(color)
                .onSubmit { commit() }
                .onKeyPress(keys: [.upArrow, .downArrow]) { press in
                    let dir: Double = press.key == .upArrow ? 1 : -1
                    let mult = press.modifiers.contains(.shift) ? 10.0 : (press.modifiers.contains(.option) ? 0.1 : 1.0)
                    let v = clamp((parse(text) ?? value) + dir * step * mult)
                    onChange(v)
                    text = show(v)
                    return .handled
                }
            if let suffix { Text(suffix).font(.system(size: 10.5)).foregroundStyle(Theme.muted).fixedSize() }
            if !presets.isEmpty {
                Menu {
                    ForEach(presets.indices, id: \.self) { i in
                        Button(presets[i].0) { onChange(presets[i].1) }
                    }
                } label: {
                    Image(systemName: "chevron.down").font(.system(size: 9, weight: .bold))
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
            }
        }
        .frame(width: width)
        .padding(.horizontal, 7).padding(.vertical, 4)
        .background(RoundedRectangle(cornerRadius: 6).fill(Color.black.opacity(0.3)))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(focused ? Theme.accent.opacity(0.6) : Color.clear))
        .onAppear { text = show(value) }
        .onChange(of: value) { _, v in if !focused { text = show(v) } }
        .onChange(of: focused) { _, f in if !f { commit() } }
    }

    private func clamp(_ v: Double) -> Double {
        guard let r = range else { return v }
        return min(max(v, r.lowerBound), r.upperBound)
    }

    private func show(_ v: Double) -> String {
        let s = String(format: "%.\(max(decimals, 0))f", v)
        return L10n.isEnglish ? s : s.replacingOccurrences(of: ".", with: ",")
    }

    private func parse(_ raw: String) -> Double? {
        var t = raw.trimmingCharacters(in: .whitespaces).filter { "0123456789.,-".contains($0) }
        if L10n.isEnglish {
            // English: "," groups thousands, "." is the decimal point.
            t = t.replacingOccurrences(of: ",", with: "")
            return Double(t)
        }
        if grouping, t.range(of: #"^-?\d{1,3}(\.\d{3})+(,\d+)?$"#, options: .regularExpression) != nil {
            // "64.350" is 64350 for BTC, but "2.345" typed with a point is 2,345 for a coin of a few dollars.
            // Without a comma both readings are possible: take the one nearest to what the field shows now.
            if !t.contains(","), let asDecimal = Double(t), let asThousands = Double(t.replacingOccurrences(of: ".", with: "")),
               value > 0, asDecimal > 0, abs(log(asDecimal / value)) < abs(log(asThousands / value)) {
                return asDecimal
            }
            t = t.replacingOccurrences(of: ".", with: "")
        }
        if t.contains(",") { t = t.replacingOccurrences(of: ".", with: "").replacingOccurrences(of: ",", with: ".") }
        return Double(t)
    }

    private func commit() {
        if let v = parse(text) {
            let c = clamp(v)
            if abs(c - value) > 1e-12 { onChange(c) }
            text = show(c)
        } else {
            text = show(value)
        }
    }
}

/// Small label above a field (for two fields side by side).
struct LabeledField<Content: View>: View {
    var label: String
    var accessory: AnyView? = nil
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 4) {
                Text(label).font(.system(size: 10.5)).foregroundStyle(Theme.muted)
                if let accessory { accessory }
            }
            content
        }
    }
}

/// Label left, field right.
struct FieldRow<Content: View>: View {
    var label: String
    var color: Color = Theme.muted
    @ViewBuilder var content: Content
    var body: some View {
        HStack(spacing: 6) {
            Text(label).font(.system(size: 12.5)).foregroundStyle(color)
            Spacer(minLength: 4)
            content
        }
    }
}

// MARK: - Order (Risico, Bedrag, adding and reducing in Positie)

struct TicketCard: View {
    @EnvironmentObject var state: AppState

    private var priceDecimals: Int { max(0, -Int(floor(log10(state.priceTick) + 1e-9))) }

    var body: some View {
        let pl = state.plan
        let t = state.ticket
        let reduce = t?.reduceOnly == true
        let adding = pl?.isAdd == true
        let byRisk = t?.riskSized == true
        let hold = state.ticketNeedsHold && t?.linesHidden != true
        Card(title: title(t, adding: adding), trailing: AnyView(pill(t, adding: adding))) {
            if !reduce && !adding, let t {
                HStack(spacing: 6) {
                    sideButton(T("Long"), on: t.isLong, color: Theme.green) { if !t.isLong { state.newTicket(long: true, entry: t.entry) } }
                    sideButton(T("Short"), on: !t.isLong, color: Theme.red) { if t.isLong { state.newTicket(long: false, entry: t.entry) } }
                }
            }
            Picker("", selection: Binding(get: { state.ticket?.isMarket ?? false }, set: { state.ticket?.isMarket = $0 })) {
                Text(T("Limit")).tag(false)
                Text((t?.entries.count ?? 1) > 1 ? T("E1 market") : T("Market")).tag(true)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .demoAnchor("ticket-type")

            sizeSection(t, pl, byRisk: byRisk, reduce: reduce)

            Divider().overlay(Theme.line)

            entrySection(t, reduce: reduce)
            if !reduce {
                stopSection(t, pl, byRisk: byRisk)
                if adding && (t?.tps.isEmpty ?? true) && !state.existingTPOrders.isEmpty {
                    ExistingTPsView(plan: pl)
                } else {
                    tpSection(t, pl, byRisk: byRisk)
                }
            }

            Divider().overlay(Theme.line)

            if let pl {
                if let before = pl.before, adding { BeforeAfterView(before: before, after: pl.after, plan: pl) }
                summary(t, pl, reduce: reduce, adding: adding)
                ForEach(pl.warnings + state.budgetWarnings(pl), id: \.self) { w in
                    // Red stops the order, orange only tells.
                    let blocks = pl.blockers.contains(w)
                    Label(T(w), systemImage: blocks ? "xmark.octagon.fill" : "exclamationmark.triangle.fill")
                        .font(.system(size: 11)).foregroundStyle(blocks ? Theme.red : Theme.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            HStack(spacing: 8) {
                if t?.linesHidden != true {
                    // Without a position the form stays; this only takes its lines out of the chart again.
                    Button(state.position == nil && t?.replacesSetup != true && !reduce ? T("Lijnen uit") : T("Annuleer")) { state.ticket = nil }
                        .buttonStyle(BigButtonStyle(color: Theme.card, textColor: Theme.text))
                        .frame(width: 92)
                        .keyboardShortcut(.cancelAction)
                }
                let off = pl == nil || state.busy || (pl?.size ?? 0) <= 0 || !(pl?.blockers.isEmpty ?? true)
                let sideColor = reduce ? Theme.orange : ((t?.isLong ?? true) ? Theme.green : Theme.red)
                if hold {
                    // Market without a stop: hold the button. ⌘↩ asks first.
                    HoldButton(title: placeTitle(t, adding: adding), color: sideColor, disabled: off) { Task { await state.placeTicket() } }
                        .demoAnchor("btn-place")
                        .background(Button("") { state.requestPlaceTicket() }.keyboardShortcut(.return, modifiers: .command).opacity(0).disabled(off))
                } else {
                    Button {
                        state.requestPlaceTicket()
                    } label: {
                        HStack {
                            if state.busy { ProgressView().controlSize(.small) }
                            Text(placeTitle(t, adding: adding))
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(BigButtonStyle(color: sideColor))
                    .disabled(off)
                    .demoAnchor("btn-place")
                    .keyboardShortcut(.return, modifiers: .command)
                }
            }
            if hold {
                Text(T("Market zonder stop: houd de knop even ingedrukt.")).font(.system(size: 10.5)).foregroundStyle(Theme.orange)
            }
            if t?.replacesSetup == true {
                Text(T("Je wachtende orders worden geannuleerd en opnieuw geplaatst met deze waarden."))
                    .font(.system(size: 10.5)).foregroundStyle(Theme.dim).fixedSize(horizontal: false, vertical: true)
            } else if t?.linesHidden == true {
                Text(T("De lijnen komen in de chart zodra je iets invult of op de knop klikt."))
                    .font(.system(size: 10.5)).foregroundStyle(Theme.dim).fixedSize(horizontal: false, vertical: true)
            }
            if !state.canTrade {
                Text(T("Om te handelen: koppel een account met API-wallet (⇧⌘A)."))
                    .font(.system(size: 10.5)).foregroundStyle(Theme.dim)
            }
        }
    }

    // MARK: Sections

    @ViewBuilder
    private func sizeSection(_ t: Ticket?, _ pl: Plan?, byRisk: Bool, reduce: Bool) -> some View {
        let maxLev = Double(state.asset?.maxLeverage ?? 50)
        let levValues: [Double] = [2, 3, 5, 10, 20].filter { $0 < maxLev }
        let levPresets: [(String, Double)] = levValues.map { v in (T("\(Int(v))×"), v) } + [(T("\(Int(maxLev))× (max)"), maxLev)]
        let riskPresets: [(String, Double)] = [("0,25%", 0.25), ("0,5%", 0.5), ("1%", 1), ("2%", 2)]
        if reduce, let t, let pos = state.position {
            let fractions: [Double] = [0.25, 0.5, 0.75, 1]
            let reducePresets: [(String, Double)] = fractions.map { f in ("\(Int(f * 100))%", HLFormat.roundSize(abs(pos.size) * f, szDecimals: state.szDecimals)) }
            FieldRow(label: T("Verkleinen met")) {
                NumberField(value: t.amount, step: pow(10, -Double(state.szDecimals)), decimals: state.szDecimals, suffix: state.coin,
                            presets: reducePresets, width: 120) { state.setTicketAmount($0) }
            }
        } else if byRisk {
            HStack(alignment: .top, spacing: 8) {
                LabeledField(label: pl?.isAdd == true ? T("Max verlies trade") : T("Max verlies")) {
                    NumberField(value: state.riskPercent, step: 0.05, decimals: 2, color: Theme.red, range: 0.05...10, suffix: "%",
                                presets: riskPresets, width: 82) { state.setTicketRisk($0) }
                }
                LabeledField(label: T("Hefboom")) {
                    NumberField(value: Double(t?.leverage ?? pl?.leverage ?? 1), step: 1, decimals: 0, range: 1...maxLev,
                                suffix: t?.leverage == nil ? T("× auto") : T("×"), presets: [(T("Auto"), 0)] + levPresets, width: 82) { v in
                        state.setTicketLeverage(v < 1 ? nil : Int(v.rounded()))
                    }
                }
            }
        } else if let t {
            let free = max(state.account.withdrawable, 0)
            let lev = Double(state.ticketLeverage(t))
            let avg = max(state.averageEntry(t), 1e-9)
            let unit = t.amountUnit
            let base: Double = unit == .margin ? free : (unit == .notional ? free * lev : free * lev / avg)
            let shares: [Double] = [0.1, 0.25, 0.5, 1]
            let slotBase: Double = unit == .margin ? state.slotMargin : (unit == .notional ? state.slotMargin * lev : state.slotMargin * lev / avg)
            let slotPreset: [(String, Double)] = state.budgetActive ? [(T("1 vak (1/\(state.maxPositions) van je account)"), unit == .coin ? HLFormat.roundSize(slotBase, szDecimals: state.szDecimals, down: true) : (slotBase * 100).rounded(.down) / 100)] : []
            let amountPresets: [(String, Double)] = state.isExampleEquity ? [] : slotPreset + shares.map { f in
                (T("\(Int(f * 100))% van vrije marge"), unit == .coin ? HLFormat.roundSize(base * f, szDecimals: state.szDecimals, down: true) : (base * f * 100).rounded(.down) / 100)
            }
            HStack(alignment: .top, spacing: 8) {
                LabeledField(label: unit == .margin ? T("Marge") : (unit == .notional ? T("Positiewaarde") : T("Grootte")),
                             accessory: AnyView(Button(unit.label(coin: state.coin) + " ⇄") { state.cycleAmountUnit() }
                                .buttonStyle(.plain).font(.system(size: 10, weight: .semibold)).foregroundStyle(Theme.accent)
                                .help(T("Invullen als marge, positiewaarde of aantal \(state.coin)")))) {
                    NumberField(value: t.amount, step: unit == .coin ? pow(10, -Double(state.szDecimals)) : 1, decimals: unit == .coin ? state.szDecimals : 2,
                                range: 0...1e12, suffix: unit == .coin ? nil : "$", presets: amountPresets, width: 90) { state.setTicketAmount($0) }
                }
                LabeledField(label: T("Hefboom")) {
                    NumberField(value: lev, step: 1, decimals: 0, range: 1...maxLev, suffix: T("×"), presets: levPresets, width: 70) {
                        state.setTicketLeverage(Int($0.rounded()))
                    }
                }
            }
            if let pl {
                Text(T("= positie \(state.fmt.usd(pl.size * pl.avgEntry)) · \(state.fmt.size(pl.size, coin: state.coin, decimals: state.szDecimals)) · marge \(state.fmt.usd(pl.size * pl.avgEntry / lev, decimals: 2))"))
                    .font(.system(size: 10.5)).foregroundStyle(Theme.muted)
            }
        }
    }

    @ViewBuilder
    private func entrySection(_ t: Ticket?, reduce: Bool) -> some View {
        let entries = t?.entries ?? []
        let tick = state.priceTick
        let more = entries.count > 1
        ForEach(Array(entries.enumerated()), id: \.element.id) { i, e in
                HStack(spacing: 6) {
                    let label = entries.count > 1 ? "E\(i + 1)" : (reduce ? T("Prijs") : T("Entry"))
                    if t?.isMarket == true && i == 0 {
                        KV(label, T("market ≈ ") + Fmt.price(state.price), color: Theme.blue)
                    } else {
                        FieldRow(label: label) {
                            NumberField(value: e.price, step: tick, decimals: priceDecimals, grouping: true, color: reduce ? Theme.orange : Theme.blue,
                                        range: tick...1e12) { v in
                                if state.ticket?.entries.indices.contains(i) == true { state.ticket?.entries[i].price = state.roundToTick(v) }
                            }
                        }
                    }
                    if entries.count > 1 {
                        NumberField(value: e.pct, step: 5, decimals: 0, range: 5...95, suffix: "%", width: 34) { state.setEntryPct(i, $0) }
                        RemoveButton(help: T("Entry weghalen")) { state.removeTicketEntry(i) }
                    } else if !reduce {
                        PlusButton(help: T("Gespreid instappen: nog een entry")) { state.addTicketEntry() }
                    }
                }
        }
        if more {
            HStack(spacing: 6) {
                Button(T("+ Entry")) { state.addTicketEntry() }
                    .buttonStyle(ChipStyle(active: false))
                    .disabled(entries.count >= 5)
                if entries.count > 1 {
                    Button(T("Gelijk")) { state.applyEntrySplit(state.defaultSplit(entries.count)) }.buttonStyle(ChipStyle(active: false))
                    if entries.count == 2 { Button("60/40") { state.applyEntrySplit([60, 40]) }.buttonStyle(ChipStyle(active: entries.map(\.pct) == [60, 40])) }
                    if entries.count == 3 { Button("50/30/20") { state.applyEntrySplit([50, 30, 20]) }.buttonStyle(ChipStyle(active: entries.map(\.pct) == [50, 30, 20])) }
                }
            }
        }
    }

    @ViewBuilder
    private func stopSection(_ t: Ticket?, _ pl: Plan?, byRisk: Bool) -> some View {
        if let t {
            let entry = state.averageEntry(t)
            let dir: Double = t.isLong ? 1 : -1
            let pct = entry > 0 ? dir * (entry - t.stopLoss) / entry * 100 : 0
            HStack(spacing: 6) {
                if !byRisk {
                    Toggle("", isOn: Binding(get: { t.useStopLoss }, set: { state.setUseStop($0) })).toggleStyle(.checkbox).labelsHidden()
                }
                Text(pl?.isAdd == true ? T("Stop (hele positie)") : T("Stop-loss")).font(.system(size: 12.5)).foregroundStyle(Theme.muted)
                Spacer(minLength: 4)
                if t.useStopLoss || byRisk {
                    Button(state.stopInPct ? Fmt.price(t.stopLoss) : "−" + Fmt.number(abs(pct), decimals: 2) + "%") { state.stopInPct.toggle() }
                        .buttonStyle(.plain).font(.system(size: 10.5, design: .monospaced)).foregroundStyle(Theme.dim)
                        .help(T("Afstand vanaf de \((t.entries.count > 1) ? "gem. entry" : "entry"). Klik om prijs of % in te vullen."))
                    if state.stopInPct {
                        NumberField(value: pct, step: 0.05, decimals: 2, color: Theme.red, range: 0.01...99, suffix: "%") { v in
                            state.setTicketStop(entry * (1 - dir * v / 100))
                        }
                    } else {
                        NumberField(value: t.stopLoss, step: state.priceTick, decimals: priceDecimals, grouping: true, color: Theme.red, range: state.priceTick...1e12) {
                            state.setTicketStop($0)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func tpSection(_ t: Ticket?, _ pl: Plan?, byRisk: Bool) -> some View {
        if let t {
            let more = t.tps.count > 1
            let entry = state.averageEntry(t)
            let dir: Double = t.isLong ? 1 : -1
            if t.tps.isEmpty {
                HStack(spacing: 6) {
                    Toggle("", isOn: Binding(get: { false }, set: { state.setUseTP($0) })).toggleStyle(.checkbox).labelsHidden()
                    Text(T("Take-profit")).font(.system(size: 12.5)).foregroundStyle(Theme.muted)
                    Spacer()
                }
            }
            ForEach(Array(t.tps.enumerated()), id: \.element.id) { i, tp in
                    let pct = entry > 0 ? dir * (tp.price - entry) / entry * 100 : 0
                    HStack(spacing: 6) {
                        if i == 0 && t.tps.count == 1 {
                            Toggle("", isOn: Binding(get: { true }, set: { state.setUseTP($0) })).toggleStyle(.checkbox).labelsHidden()
                        }
                        Text(t.tps.count > 1 ? "TP\(i + 1)" : T("Take-profit")).font(.system(size: 12.5)).foregroundStyle(Theme.muted)
                        Spacer(minLength: 4)
                        if t.tps.count == 1 {
                            Button(state.tpInPct ? Fmt.price(tp.price) : "+" + Fmt.number(abs(pct), decimals: 2) + "%") { state.tpInPct.toggle() }
                                .buttonStyle(.plain).font(.system(size: 10.5, design: .monospaced)).foregroundStyle(Theme.dim)
                                .help(T("Wissel tussen prijs en % vanaf de entry"))
                        } else if i == 0 { unitToggle(state.tpInPct) { state.tpInPct.toggle() } }
                        if state.tpInPct {
                            NumberField(value: pct, step: 0.05, decimals: 2, color: Theme.green, range: 0.01...1000, suffix: "%", width: t.tps.count > 1 ? 64 : 96) { v in
                                state.setTicketTP(i, entry * (1 + dir * v / 100))
                            }
                        } else {
                            NumberField(value: tp.price, step: state.priceTick, decimals: priceDecimals, grouping: true, color: Theme.green,
                                        range: state.priceTick...1e12, width: t.tps.count > 1 ? 64 : 96) { state.setTicketTP(i, $0) }
                        }
                        if t.tps.count > 1 || tp.pct < 99.5 {
                            NumberField(value: tp.pct, step: 5, decimals: 0, range: 1...100, suffix: "%", width: 34) { state.setTPPct(i, $0) }
                        }
                        if t.tps.count > 1 {
                            RemoveButton(help: T("Take-profit weghalen")) { state.removeTicketTP(i) }
                        } else {
                            Menu {
                                Button(T("Nog een take-profit")) { state.addTicketTP() }
                                Button(T("Alleen de helft sluiten (rest loopt tot je stop)")) { state.setTPPct(0, 50) }
                            } label: {
                                Image(systemName: "plus.circle.fill").foregroundStyle(Theme.accent)
                            }
                            .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                            .help(T("Meerdere take-profits, of maar een deel sluiten"))
                        }
                    }
            }
            if !t.tps.isEmpty && state.ticketTPCover < 99.5 {
                CoverageBar(levels: t.tps.map(\.pct))
                HStack {
                    Text(T("\(Int((100 - state.ticketTPCover).rounded()))% zonder TP · loopt tot je stop")).font(.system(size: 11)).foregroundStyle(Theme.orange)
                    Spacer()
                    Button(T("+ TP voor rest")) { state.addTicketTP() }.buttonStyle(ChipStyle(active: false))
                        .disabled(t.tps.count >= 5)
                }
            }
            if more {
                HStack(spacing: 6) {
                    Button(T("+ TP")) { state.addTicketTP() }
                        .buttonStyle(ChipStyle(active: false))
                        .disabled(t.tps.count >= 5)
                    if t.tps.count > 1 {
                        Button(T("Gelijk")) { state.applySplitPreset(state.defaultSplit(t.tps.count)) }.buttonStyle(ChipStyle(active: false))
                        if t.tps.count == 2 { Button("70/30") { state.applySplitPreset([70, 30]) }.buttonStyle(ChipStyle(active: t.tps.map(\.pct) == [70, 30])) }
                        if t.tps.count == 3 { Button("50/30/20") { state.applySplitPreset([50, 30, 20]) }.buttonStyle(ChipStyle(active: t.tps.map(\.pct) == [50, 30, 20])) }
                    }
                }
                if t.tps.count > 1 && t.useStopLoss {
                    Toggle(isOn: Binding(get: { state.ticket?.moveSLToBreakEven ?? false }, set: { state.ticket?.moveSLToBreakEven = $0 })) {
                        Text(T("Stop naar break-even na TP1")).font(.system(size: 11.5))
                    }
                    .toggleStyle(.checkbox)
                }
            }
        }
    }

    @ViewBuilder
    private func summary(_ t: Ticket?, _ pl: Plan, reduce: Bool, adding: Bool) -> some View {
        VStack(spacing: 5) {
            if reduce {
                KV(T("Resultaat van dit deel ≈"), state.fmt.signedUsd(pl.reducePnl ?? 0, decimals: 2), color: Theme.pnl(pl.reducePnl ?? 0))
                KV(T("Positie na"), state.fmt.size(pl.after.size, coin: state.coin, decimals: state.szDecimals))
            } else {
                // One bar: what the stop costs against what the take-profits bring (whole trade when adding).
                RiskRewardBar(loss: pl.riskUsd.map { state.fmt.usd(-$0, decimals: 2) + " · " + Fmt.number(pl.riskPercentActual ?? 0, decimals: 2) + "%" },
                              win: pl.potentialProfit.map { state.fmt.signedUsd($0, decimals: 2) + (pl.rewardRisk.map { " · " + Fmt.number($0, decimals: 1) + "R" } ?? "") },
                              ratio: pl.rewardRisk)
                    .help(adding ? T("Risico en winst van de hele trade, na fees") : T("Risico tot je stop en winst bij je take-profits, na fees"))
                if t?.riskSized == true && !adding {
                    Text("\(state.fmt.size(pl.size, coin: state.coin, decimals: state.szDecimals)) · \(state.fmt.usd(pl.notional)) · \(t?.leverage ?? pl.leverage)× · " + T("marge \(state.fmt.usd(pl.marginRequired))"))
                        .mono(10.5).foregroundStyle(Theme.muted).frame(maxWidth: .infinity, alignment: .trailing)
                }
                if (t?.entries.count ?? 1) > 1 { KV(adding ? T("Gem. entry bijkoop") : T("Gem. entry als alles vult"), Fmt.price(pl.avgEntry), color: Theme.blue) }
                if let first = pl.riskFirstEntryOnly { KV(T("Als alleen E1 vult"), state.fmt.usd(-first, decimals: 2), color: Theme.red) }
                Text((adding ? "" : T("liquidatie ≈ \(Fmt.price(pl.estLiquidationPx))") + " · ") + T("fees ≈ \(state.fmt.usd(pl.estFees, decimals: 2))"))
                    .mono(10.5).foregroundStyle(Theme.dim).frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
    }

    // MARK: Bits

    private func unitToggle(_ pct: Bool, _ action: @escaping () -> Void) -> some View {
        Button(pct ? "% ⇄" : T("prijs ⇄"), action: action)
            .buttonStyle(.plain)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(Theme.accent)
            .help(T("Wissel tussen prijs en % vanaf de entry"))
    }

    private func sideButton(_ title: String, on: Bool, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12.5, weight: .semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
                .foregroundStyle(on ? color : Theme.muted)
                .background(RoundedRectangle(cornerRadius: 8).fill(on ? color.opacity(0.18) : Color.clear))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(on ? color.opacity(0.5) : Theme.line))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func title(_ t: Ticket?, adding: Bool) -> String {
        guard let t else { return T("Nieuwe order") }
        if t.replacesSetup { return T("Setup aanpassen · \(state.coin)") }
        if t.reduceOnly { return T("Verkleinen · \(state.coin)") }
        if adding { return T("Bijkopen · \(state.coin) \(t.isLong ? "long" : "short")") }
        return T("Nieuwe order")
    }

    @ViewBuilder
    private func pill(_ t: Ticket?, adding: Bool) -> some View {
        if t?.reduceOnly == true {
            Text(T("REDUCE")).font(.system(size: 10.5, weight: .bold)).foregroundStyle(Theme.orange)
                .padding(.horizontal, 7).padding(.vertical, 2)
                .background(RoundedRectangle(cornerRadius: 5).fill(Theme.orange.opacity(0.15)))
        } else if adding {
            Text(T("+ BIJ")).font(.system(size: 10.5, weight: .bold)).foregroundStyle(Theme.accent)
                .padding(.horizontal, 7).padding(.vertical, 2)
                .background(RoundedRectangle(cornerRadius: 5).fill(Theme.accent.opacity(0.2)))
        } else if let t {
            SidePill(isLong: t.isLong)
        }
    }

    private func placeTitle(_ t: Ticket?, adding: Bool) -> String {
        guard let t else { return T("Plaats") }
        if t.linesHidden { return T("Toon in chart") }
        if t.replacesSetup { return T("Wijzig setup") }
        let side = t.isLong ? "long" : "short"
        let n = t.entries.count
        if t.reduceOnly { return t.isMarket && n == 1 ? T("Verklein (market)") : T("Verklein") }
        if adding { return t.isMarket ? T("Koop bij (market)") : (n > 1 ? T("Plaats \(n) bijkoop-orders") : T("Koop bij")) }
        if n > 1 { return T("Plaats \(n) entries") }
        return t.isMarket ? T("Market \(side)") : T("Plaats limit \(side)")
    }
}

// MARK: - Positie tab

/// One line about the open position in the other tabs.
struct PositionSummary: View {
    @EnvironmentObject var state: AppState
    var body: some View {
        if let pos = state.position {
            let u = state.net(for: pos)
            Button { state.panelMode = .position } label: {
                HStack {
                    SidePill(isLong: pos.isLong)
                    Text(state.fmt.size(pos.size, coin: state.coin, decimals: state.szDecimals)).mono(11.5)
                    Text(T("marge \(state.fmt.usd(pos.marginUsed, decimals: pos.marginUsed < 100 ? 2 : 0))")).mono(10.5).foregroundStyle(Theme.dim)
                        .help(T("Marge die deze positie vastzet"))
                    Spacer()
                    Text(state.fmt.signedUsd(u)).mono(13, .semibold).foregroundStyle(Theme.pnl(u))
                    Image(systemName: "chevron.right").font(.system(size: 10, weight: .semibold)).foregroundStyle(Theme.dim)
                }
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 10).fill(Theme.card))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.line))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(T("Open positie: naar het tabblad Positie"))
        }
    }
}

struct PositionTab: View {
    @EnvironmentObject var state: AppState
    @State private var fraction = 0.5
    /// What the action block shows: 0 = reduce, 1 = add, 2 = reverse.
    @State private var action = 0
    private var priceDecimals: Int { max(0, -Int(floor(log10(state.priceTick) + 1e-9))) }

    var body: some View {
        // More than one position: pick which one you are looking at.
        if state.account.positions.count > 1 {
            HStack(spacing: 4) {
                ForEach(state.account.positions) { p in
                    Button { state.coin = p.coin } label: {
                        HStack(spacing: 4) {
                            Circle().fill(p.isLong ? Theme.green : Theme.red).frame(width: 6, height: 6)
                            Text(p.coin)
                        }
                    }
                    .buttonStyle(ChipStyle(active: p.coin == state.coin))
                }
            }
        }
        if let pos = state.position {
            let u = state.net(for: pos)
            let eq = max(state.account.accountValue, 1)
            let ot = state.openTrade
            let sl = state.existingStopOrder
            let tps = state.existingTPOrders
            Card(title: state.coin, trailing: AnyView(SidePill(isLong: pos.isLong))) {
                HStack(alignment: .firstTextBaseline) {
                    Text(state.fmt.signedUsd(u)).mono(22, .bold).foregroundStyle(Theme.pnl(u))
                    Spacer()
                    Text(T("\(state.fmt.size(pos.size, coin: state.coin, decimals: state.szDecimals)) · \(pos.leverage)× \(pos.isCross ? "cross" : "isolated")"))
                        .mono(10.5).foregroundStyle(Theme.muted)
                }
                .help(T("Netto na fees\((ot?.funding ?? 0) != 0 ? " en funding" : "") · \(Fmt.percent(u / eq)) van je portfolio"))
                // The whole trade as in the chart: stop on the left, take-profits on the right, the marker is now.
                if let cm = state.chartMeter { TradeBar(meter: cm.meter, fmt: state.fmt) }

                // Stop and a single take-profit are typed right here; the line in the chart moves along.
                HStack(spacing: 6) {
                    Text(T("Stop")).font(.system(size: 12.5)).foregroundStyle(Theme.muted)
                    Spacer(minLength: 4)
                    if let sl {
                        if let be = state.breakEven, pos.isLong ? be > sl.displayPx : be < sl.displayPx {
                            Button(T("→ BE")) { Task { await state.moveStopToBreakEven(coin: pos.coin, force: true) } }
                                .buttonStyle(.plain).font(.system(size: 10.5, weight: .semibold)).foregroundStyle(Theme.accent)
                                .help(T("Zet de stop-loss op \(Fmt.price(be)): deze trade kan dan niet meer verliezen (na fees)."))
                        }
                        NumberField(value: state.pendingOrderPrices[sl.oid] ?? sl.displayPx, step: state.priceTick, decimals: priceDecimals, grouping: true,
                                    color: Theme.red, range: state.priceTick...1e12) { state.scheduleMove(oid: sl.oid, to: $0) }
                    } else {
                        Text(T("geen")).font(.system(size: 12)).foregroundStyle(Theme.orange)
                        Button(T("+ Stop-loss")) { Task { await state.addPositionTpSl(.sl) } }.buttonStyle(ChipStyle(active: false)).fixedSize()
                    }
                }
                let cover = TPEditor.coverage(state.currentTPs)
                HStack(spacing: 6) {
                    Text(T("Doel") + (!tps.isEmpty && cover < 0.995 ? " (\(Int((cover * 100).rounded()))%)" : "")).font(.system(size: 12.5)).foregroundStyle(Theme.muted)
                    Spacer(minLength: 4)
                    if tps.count == 1, let tp = tps.first {
                        NumberField(value: state.pendingOrderPrices[tp.oid] ?? tp.displayPx, step: state.priceTick, decimals: priceDecimals, grouping: true,
                                    color: Theme.green, range: state.priceTick...1e12) { state.scheduleMove(oid: tp.oid, to: $0) }
                        PlusButton(help: T("Meerdere take-profits of een andere verdeling")) { state.startTPEdit() }
                    } else if tps.isEmpty {
                        Text(T("geen")).font(.system(size: 12)).foregroundStyle(Theme.muted)
                        Button(T("+ Take-profit")) { Task { await state.addPositionTpSl(.tp) } }.buttonStyle(ChipStyle(active: false)).fixedSize()
                    } else {
                        Button(tps.map { Fmt.price($0.displayPx) }.joined(separator: " · ")) { state.startTPEdit() }
                            .buttonStyle(.plain).font(.system(size: 11.5, design: .monospaced)).foregroundStyle(cover < 0.995 ? Theme.orange : Theme.green)
                            .help(T("Klik om je take-profits aan te passen"))
                    }
                }
                // Everything else in one quiet line.
                let details: [String?] = [T("entry \(Fmt.price(pos.entryPx))"),
                      state.breakEven.map { "BE " + Fmt.price($0) },
                      pos.liquidationPx.map { "liq " + Fmt.price($0) },
                      T("marge \(state.fmt.usd(pos.marginUsed))"),
                      (ot?.realized ?? 0) != 0 ? T("gerealiseerd \(state.fmt.signedUsd(ot?.realized ?? 0, decimals: 2))") : nil]
                Text(details.compactMap { $0 }.joined(separator: " · "))
                    .mono(10.5).foregroundStyle(Theme.dim).fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if state.breakEvenAfterTP.contains(pos.coin) {
                    Label(T("Stop gaat naar break-even na de eerste TP"), systemImage: "arrow.right.to.line")
                        .font(.system(size: 10.5)).foregroundStyle(Theme.accent)
                }
            }

            if state.ticket != nil {
                TicketCard()
            } else {
                // One block for what you can do with the position; only the chosen one opens up.
                VStack(alignment: .leading, spacing: 10) {
                    Picker("", selection: $action) {
                        Text(T("Verkleinen")).tag(0)
                        Text(T("Bijkopen")).tag(1)
                        Text(T("Omkeren")).tag(2)
                    }
                    .pickerStyle(.segmented).labelsHidden()
                    if action == 0 {
                        HStack(spacing: 6) {
                            ForEach([0.25, 0.5, 0.75, 1.0], id: \.self) { f in
                                Button("\(Int(f * 100))%") { fraction = f }
                                    .buttonStyle(ChipStyle(active: fraction == f, large: true))
                                    .demoAnchor("close-\(f)")
                            }
                        }
                        HStack(spacing: 8) {
                            Button { state.requestClose(fraction: fraction) } label: { Text(T("Nu (market)")).frame(maxWidth: .infinity) }
                                .buttonStyle(BigButtonStyle(color: Theme.orange))
                                .disabled(state.busy)
                            Button { state.startReduce(fraction: fraction) } label: { Text(T("Op prijs…")).frame(maxWidth: .infinity) }
                                .buttonStyle(BigButtonStyle(color: Theme.card, textColor: Theme.text))
                                .help(T("Limit-order die je positie kleiner maakt; de lijn staat in de chart"))
                        }
                    } else if action == 1 {
                        Text(T("Extra entry op deze positie. Je stop en take-profits groeien mee.")).font(.system(size: 11)).foregroundStyle(Theme.dim)
                        Button { state.newTicket(long: pos.isLong) } label: { Text(T("Bijkopen…")).frame(maxWidth: .infinity) }
                            .buttonStyle(BigButtonStyle(color: Theme.card, textColor: Theme.text))
                    } else {
                        Text(T("Sluit deze positie en opent dezelfde grootte de andere kant op (market). Je stop en take-profits vervallen."))
                            .font(.system(size: 11)).foregroundStyle(Theme.dim).fixedSize(horizontal: false, vertical: true)
                        Button { state.requestReverse(coin: pos.coin) } label: { Text(T("Omkeren…")).frame(maxWidth: .infinity) }
                            .buttonStyle(BigButtonStyle(color: Theme.card, textColor: Theme.text))
                            .disabled(state.busy)
                    }
                }
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 10).fill(Theme.card))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.line))
            }
            OrdersCard()
        } else {
            VStack(spacing: 8) {
                Image(systemName: "tray").font(.system(size: 22)).foregroundStyle(Theme.dim)
                Text(T("Geen open positie in \(state.coin).")).font(.system(size: 12.5)).foregroundStyle(Theme.muted)
                Text(T("Open een trade in het tabblad Order. Hier beheer je hem daarna: bijkopen, verkleinen, stop verplaatsen."))
                    .font(.system(size: 11)).foregroundStyle(Theme.dim).multilineTextAlignment(.center)
            }
            .padding(.vertical, 24)
            .frame(maxWidth: .infinity)
            OrdersCard()
        }
    }
}

/// Margin the position ties up: in dollars, as part of the account and, with a margin budget, of one slot.
struct MarginRow: View {
    @EnvironmentObject var state: AppState
    let pos: Position
    var body: some View {
        let eq = max(state.account.accountValue, 1e-9)
        let slot = state.budgetActive ? pos.marginUsed / max(state.slotMargin, 1e-9) : nil
        var text = "\(state.fmt.usd(pos.marginUsed, decimals: 2)) · \(Fmt.percent(pos.marginUsed / eq, decimals: 1, signed: false))"
        if let slot { text += T(" · \(Int((slot * 100).rounded()))% van vak") }
        let slotNote = slot != nil ? T("; een vak is \(state.fmt.usd(state.slotMargin)) (1/\(state.maxPositions) van je account)") : ""
        return KV(T("Marge"), text, color: (slot ?? 0) > 1 ? Theme.orange : Theme.text)
            .help(T("Marge die deze positie vastzet (positiewaarde ÷ hefboom\(pos.isCross ? ", cross" : ", isolated")). Het percentage is van je portfolio\(slotNote)."))
    }
}

/// Risk against reward in one glance: red for what the stop costs, green for what the take-profits bring.
struct RiskRewardBar: View {
    var loss: String?
    var win: String?
    var ratio: Double?
    var body: some View {
        GeometryReader { g in
            // The split follows R:R, kept between a third and three quarters so both texts fit.
            let share = win == nil ? 1.0 : min(max(1 / (1 + (ratio ?? 1)), 0.34), 0.6)
            HStack(spacing: 2) {
                Text(loss ?? T("geen stop-loss")).lineLimit(1).minimumScaleFactor(0.7)
                    .padding(.horizontal, 7).frame(width: max(g.size.width * share - 1, 0), height: 24, alignment: .leading)
                    .foregroundStyle(loss == nil ? Theme.orange : Theme.red)
                    .background((loss == nil ? Theme.orange : Theme.red).opacity(0.16))
                if let win {
                    Text(win).lineLimit(1).minimumScaleFactor(0.7)
                        .padding(.horizontal, 7).frame(width: max(g.size.width * (1 - share) - 1, 0), height: 24, alignment: .trailing)
                        .foregroundStyle(Theme.green)
                        .background(Theme.green.opacity(0.16))
                }
            }
            .font(.system(size: 11.5, weight: .semibold, design: .monospaced))
        }
        .frame(height: 24)
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}

/// A button you hold for a moment (market order without a stop): it fills while you hold and fires when full.
struct HoldButton: View {
    var title: String
    var color: Color
    var textColor: Color = Color(nsColor: NSColor(hex: 0x04150E))
    var disabled = false
    var action: () -> Void
    @State private var pressing = false

    var body: some View {
        Text(title)
            .font(.system(size: 13.5, weight: .semibold))
            .foregroundStyle(textColor)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 11).padding(.horizontal, 10)
            .background(
                GeometryReader { g in
                    ZStack(alignment: .leading) {
                        color.opacity(0.55)
                        color.frame(width: pressing ? g.size.width : 0)
                    }
                }
            )
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .opacity(disabled ? 0.5 : 1)
            .contentShape(Rectangle())
            .onLongPressGesture(minimumDuration: 0.6, maximumDistance: 40, perform: {
                pressing = false
                if !disabled { action() }
            }, onPressingChanged: { down in
                withAnimation(down ? .linear(duration: 0.6) : .easeOut(duration: 0.15)) { pressing = down && !disabled }
            })
            .help(T("Houd ingedrukt om te plaatsen"))
    }
}

struct PlusButton: View {
    var help: String
    var action: () -> Void
    var body: some View {
        Button(action: action) { Image(systemName: "plus.circle.fill").foregroundStyle(Theme.accent) }
            .buttonStyle(.plain)
            .help(help)
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
                Text(T("NU")).font(.system(size: 9.5, weight: .semibold)).foregroundStyle(Theme.dim)
                Text("")
                Text(T("NA")).font(.system(size: 9.5, weight: .semibold)).foregroundStyle(Theme.dim)
            }
            row(T("Grootte"), f.size(before.size, coin: "", decimals: d), f.size(after.size, coin: state.coin, decimals: d))
            row(T("Gem. entry"), Fmt.price(before.avgEntry), Fmt.price(after.avgEntry))
            row(T("Break-even"), Fmt.price(state.breakEven ?? before.breakEven), Fmt.price(after.breakEven))
            if let r = after.riskUsd {
                row(T("Risico tot stop"), before.riskUsd.map { f.usd(-max($0, 0), decimals: 0) } ?? "–", f.usd(-r, decimals: 2), color: Theme.red)
            }
            row(T("Marge"), f.usd(before.margin, decimals: 0), f.usd(after.margin, decimals: 0))
            row(T("Liquidatie ≈"), Fmt.price(state.position?.liquidationPx ?? before.estLiquidationPx), Fmt.price(after.estLiquidationPx), color: Theme.orange)
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
            Text(T("TAKE-PROFITS GROEIEN MEE")).font(.system(size: 10, weight: .semibold)).tracking(0.6).foregroundStyle(Theme.muted)
            ForEach(state.existingTPOrders) { o in
                HStack {
                    Text(T("TP \(Fmt.price(o.displayPx))")).mono(11.5).foregroundStyle(Theme.green)
                    Spacer()
                    if o.size > 0 {
                        Text("\(state.fmt.size(o.size, coin: "", decimals: state.szDecimals)) → \(state.fmt.size(o.size * factor, coin: state.coin, decimals: state.szDecimals))").mono(11)
                    } else {
                        Text(T("hele positie")).font(.system(size: 11)).foregroundStyle(Theme.muted)
                    }
                }
            }
            Button(T("Nieuwe TP-ladder in plaats hiervan")) { state.addTicketTP() }
                .buttonStyle(ChipStyle(active: false))
        }
    }
}

struct OrdersCard: View {
    @EnvironmentObject var state: AppState
    var body: some View {
        let orders = state.coinOrders
        let draft = state.tpDraft.flatMap { $0.coin == state.coin ? $0 : nil }
        let pending = state.position == nil ? state.managed[state.coin]?.tps : nil
        if !orders.isEmpty || draft != nil {
            Card(title: T("Open orders \(state.coin)"), trailing: draft == nil && state.canEditTPs ? AnyView(
                HStack(spacing: 4) {
                    if state.position == nil {
                        Button(T("Setup aanpassen")) { state.startSetupEdit() }
                            .buttonStyle(ChipStyle(active: false))
                            .help(T("De hele wachtende setup terug in het formulier: hefboom, grootte, entry, stop en take-profits"))
                    }
                    Button(T("TP's aanpassen")) { state.startTPEdit() }
                        .buttonStyle(ChipStyle(active: false))
                        .help(T("Prijs, aantal en verdeling van je take-profits wijzigen, ook voordat de entry gevuld is"))
                }
                .fixedSize()
            ) : nil) {
                if let draft { TPEditorView(draft: draft) }
                ForEach(orders) { o in
                    let editing = state.orderEdit?.oid == o.oid
                    if draft != nil && o.reduceOnly && (!o.isTrigger || o.tpsl == .tp) {
                        EmptyView()
                    } else {
                        Button {
                            if editing { state.orderEdit = nil } else { state.startOrderEdit(o) }
                        } label: {
                            HStack(spacing: 8) {
                                Circle().fill(color(o)).frame(width: 7, height: 7)
                                Text(state.orderName(o)).font(.system(size: 12))
                                if o.reduceOnly && !(o.isTrigger && o.tpsl == .sl), let share = share(o) {
                                    Text(share).mono(10.5).foregroundStyle(Theme.dim)
                                }
                                Spacer()
                                if let pnl = state.setupOutcome(o) {
                                    Text(state.fmt.signedUsd(pnl)).mono(11).foregroundStyle(pnl < 0 ? Theme.red : Theme.green)
                                }
                                Text(Fmt.price(state.pendingOrderPrices[o.oid] ?? o.displayPx)).mono(12)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .help(T("Klik om prijs en hoeveelheid te wijzigen"))
                        .contextMenu { Button(T("Annuleer order")) { Task { await state.cancelOrder(o.oid) } } }
                        if editing, let e = state.orderEdit { OrderEditView(order: o, edit: e) }
                    }
                }
                if draft == nil, let pending {
                    ForEach(Array(pending.prices.enumerated()), id: \.offset) { i, px in
                        HStack(spacing: 8) {
                            Circle().stroke(Theme.green, lineWidth: 1.5).frame(width: 7, height: 7)
                            Text(T("Take-profit")).font(.system(size: 12))
                            Text("\(Int(((pending.fractions[safe: i] ?? 0) * 100).rounded()))%").mono(10.5).foregroundStyle(Theme.dim)
                            Spacer()
                            Text(T("wacht op entry")).font(.system(size: 10.5)).foregroundStyle(Theme.dim)
                            Text(Fmt.price(px)).mono(12)
                        }
                    }
                }
                Text(T("Klik een order om prijs of hoeveelheid te wijzigen; slepen in de chart kan ook.")).font(.system(size: 10.5)).foregroundStyle(Theme.dim)
            }
        }
    }

    /// Share of the position (or of the waiting entry) a reduce-only order closes.
    private func share(_ o: OpenOrder) -> String? {
        let base = state.orderBaseSize(o)
        guard base > 0, o.size > 0 else { return nil }
        return "\(Int((min(o.size / base, 1) * 100).rounded()))%"
    }

    private func color(_ o: OpenOrder) -> Color {
        if o.isTrigger { return o.tpsl == .tp ? Theme.green : Theme.red }
        return o.reduceOnly ? Theme.green : Theme.blue
    }
}

/// Changing the take-profits after placing: price and share per level, a share under 100% is allowed.
struct TPEditorView: View {
    @EnvironmentObject var state: AppState
    let draft: TPDraft
    private var priceDecimals: Int { max(0, -Int(floor(log10(state.priceTick) + 1e-9))) }

    var body: some View {
        let total = min(draft.total, 100)
        let full = total >= 99.5
        let issue = state.draftIssue
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(T("Take-profits aanpassen")).font(.system(size: 12, weight: .semibold))
                Spacer()
                Text(T("dekt \(Int(total.rounded()))%")).mono(11, .semibold).foregroundStyle(full ? Theme.green : Theme.orange)
            }
            ForEach(Array(draft.levels.enumerated()), id: \.element.id) { i, l in
                HStack(spacing: 6) {
                    Text("TP\(i + 1)").font(.system(size: 12.5)).foregroundStyle(Theme.muted).fixedSize()
                    Spacer(minLength: 2)
                    NumberField(value: l.price, step: state.priceTick, decimals: priceDecimals, grouping: true, color: Theme.green,
                                range: state.priceTick...1e12, width: 66) { state.setDraftPrice(i, $0) }
                    NumberField(value: l.pct, step: 5, decimals: 0, range: 1...100, suffix: "%", width: 30) { state.setDraftPct(i, $0) }
                    Text(state.fmt.signedUsd(state.draftProfit(l, isLong: draft.isLong))).mono(10.5).foregroundStyle(Theme.green)
                        .lineLimit(1).minimumScaleFactor(0.7).frame(width: 40, alignment: .trailing)
                    RemoveButton(help: T("Take-profit weghalen")) { state.removeDraftTP(i) }
                }
            }
            CoverageBar(levels: draft.levels.map(\.pct))
            if !full && !draft.levels.isEmpty {
                HStack {
                    Text(T("\(Int((100 - total).rounded()))% zonder TP · loopt tot je stop")).font(.system(size: 11)).foregroundStyle(Theme.orange)
                    Spacer()
                    Button(T("+ TP voor rest")) { state.addDraftRest() }.buttonStyle(ChipStyle(active: false))
                        .disabled(draft.levels.count >= 5)
                }
            }
            HStack(spacing: 6) {
                Button(T("+ TP")) { state.addDraftTP() }.buttonStyle(ChipStyle(active: false)).disabled(draft.levels.count >= 5)
                let n = draft.levels.count
                if n > 1 {
                    Button(T("Gelijk")) { state.applyDraftSplit(state.defaultSplit(n)) }.buttonStyle(ChipStyle(active: false))
                    if n == 2 { Button("40/60") { state.applyDraftSplit([40, 60]) }.buttonStyle(ChipStyle(active: draft.levels.map(\.pct) == [40, 60])) }
                    if n == 3 { Button("50/30/20") { state.applyDraftSplit([50, 30, 20]) }.buttonStyle(ChipStyle(active: draft.levels.map(\.pct) == [50, 30, 20])) }
                }
            }
            if let issue {
                Text(issue.text).font(.system(size: 11)).foregroundStyle(issue.blocks ? Theme.red : Theme.orange)
            }
            if state.position == nil {
                Text(T("Je entry is nog niet gevuld. Eén TP voor alles blijft aan de entry gekoppeld; meerdere TP's plaatst Grip zodra de entry vult (Grip moet dan open zijn)."))
                    .font(.system(size: 10.5)).foregroundStyle(Theme.dim).fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 8) {
                Button { state.tpDraft = nil } label: { Text(T("Annuleer")).frame(maxWidth: .infinity) }
                    .buttonStyle(BigButtonStyle(color: Theme.card, textColor: Theme.text))
                Button { Task { await state.applyTPDraft() } } label: { Text(T("Toepassen")).frame(maxWidth: .infinity) }
                    .buttonStyle(BigButtonStyle(color: Theme.green))
                    .disabled(state.busy || issue?.blocks == true)
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 8).fill(Theme.bg.opacity(0.5)))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.line))
    }
}

/// Bar that shows how much of the position the take-profits close; the uncovered part is orange.
struct CoverageBar: View {
    let levels: [Double]
    var body: some View {
        GeometryReader { g in
            HStack(spacing: 2) {
                ForEach(Array(levels.enumerated()), id: \.offset) { _, p in
                    Rectangle().fill(Theme.green).frame(width: max(g.size.width * min(p, 100) / 100 - 2, 1))
                }
                let rest = max(100 - levels.reduce(0, +), 0)
                if rest > 0.5 { Rectangle().fill(Theme.orange.opacity(0.45)).frame(width: max(g.size.width * rest / 100 - 2, 1)) }
            }
        }
        .frame(height: 5)
        .clipShape(RoundedRectangle(cornerRadius: 2.5))
    }
}

/// One open order opened up in the list: price, and size (share for take-profits and close orders, coins for entries).
struct OrderEditView: View {
    @EnvironmentObject var state: AppState
    let order: OpenOrder
    let edit: OrderEdit
    private var priceDecimals: Int { max(0, -Int(floor(log10(state.priceTick) + 1e-9))) }

    var body: some View {
        let isStop = order.isTrigger && order.tpsl == .sl
        let base = state.orderBaseSize(order)
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(T("Prijs")).font(.system(size: 12)).foregroundStyle(Theme.muted)
                Spacer()
                NumberField(value: edit.price, step: state.priceTick, decimals: priceDecimals, grouping: true, color: color,
                            range: state.priceTick...1e12, width: 96) { state.orderEdit?.price = state.roundToTick($0) }
            }
            if isStop {
                Text(T("De stop dekt altijd je hele positie; alleen de prijs is aan te passen.")).font(.system(size: 10.5)).foregroundStyle(Theme.dim)
            } else if order.reduceOnly && base > 0 {
                HStack {
                    Text(T("Deel")).font(.system(size: 12)).foregroundStyle(Theme.muted)
                    Text(state.fmt.size(edit.size, coin: state.coin, decimals: state.szDecimals)).mono(10.5).foregroundStyle(Theme.dim)
                    Spacer()
                    NumberField(value: (edit.size / base * 100).rounded(), step: 5, decimals: 0, range: 1...100, suffix: "%", width: 40) {
                        state.orderEdit?.size = base * $0 / 100
                    }
                }
                HStack(spacing: 6) {
                    ForEach([25.0, 50, 75, 100], id: \.self) { p in
                        Button("\(Int(p))%") { state.orderEdit?.size = base * p / 100 }
                            .buttonStyle(ChipStyle(active: abs(edit.size / base * 100 - p) < 0.5))
                    }
                }
            } else {
                let step = pow(10, -Double(state.szDecimals))
                HStack {
                    Text(T("Grootte")).font(.system(size: 12)).foregroundStyle(Theme.muted)
                    Spacer()
                    NumberField(value: edit.size, step: step, decimals: state.szDecimals, range: step...1e12, suffix: state.coin, width: 96) {
                        state.orderEdit?.size = $0
                    }
                }
                if state.position == nil {
                    Text(T("Gekoppelde stop en take-profit groeien of krimpen mee.")).font(.system(size: 10.5)).foregroundStyle(Theme.dim)
                }
            }
            HStack(spacing: 8) {
                Button { state.orderEdit = nil } label: { Text(T("Annuleer")).frame(maxWidth: .infinity) }
                    .buttonStyle(BigButtonStyle(color: Theme.card, textColor: Theme.text))
                Button { Task { await state.applyOrderEdit() } } label: { Text(T("Opslaan")).frame(maxWidth: .infinity) }
                    .buttonStyle(BigButtonStyle(color: color))
                    .disabled(state.busy)
                Button { Task { await state.cancelOrder(order.oid); state.orderEdit = nil } } label: { Image(systemName: "trash") }
                    .buttonStyle(.plain).foregroundStyle(Theme.dim)
                    .help(T("Annuleer order"))
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 8).fill(Theme.bg.opacity(0.5)))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.line))
    }

    private var color: Color {
        if order.isTrigger { return order.tpsl == .tp ? Theme.green : Theme.red }
        return order.reduceOnly ? Theme.orange : Theme.blue
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
