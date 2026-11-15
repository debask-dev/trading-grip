#if os(macOS)
import SwiftUI
import AppKit
import GripCore

/// Three tabs: Risico (size from your max loss), Bedrag (size you choose), Positie (everything after you're in).
struct TradePanel: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                AccountCard()
                Picker("", selection: $state.panelMode) {
                    ForEach(PanelMode.allCases) { m in
                        Text(m == .position && state.position != nil ? "\(m.label) ●" : m.label).tag(m)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()

                switch state.panelMode {
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
        }
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
        let more = state.showMoreOptions || (t?.entries.count ?? 1) > 1 || (t?.tps.count ?? 0) > 1
        Card(title: title(t, adding: adding), trailing: AnyView(pill(t, adding: adding))) {
            if !reduce && !adding, let t {
                HStack(spacing: 6) {
                    sideButton(T("Long"), on: t.isLong, color: Theme.green) { if !t.isLong { state.newTicket(long: true, entry: t.entry) } }
                    sideButton(T("Short"), on: !t.isLong, color: Theme.red) { if t.isLong { state.newTicket(long: false, entry: t.entry) } }
                }
            }
            Picker("", selection: Binding(get: { state.ticket?.isMarket ?? false }, set: { state.ticket?.isMarket = $0 })) {
                Text(T("Limit")).tag(false)
                Text(more && (t?.entries.count ?? 1) > 1 ? T("E1 market") : T("Market")).tag(true)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .demoAnchor("ticket-type")

            sizeSection(t, pl, byRisk: byRisk, reduce: reduce)

            Divider().overlay(Theme.line)

            entrySection(t, more: more, reduce: reduce)
            if !reduce {
                stopSection(t, pl, byRisk: byRisk)
                if adding && (t?.tps.isEmpty ?? true) && !state.existingTPOrders.isEmpty {
                    ExistingTPsView(plan: pl)
                } else {
                    tpSection(t, pl, more: more, byRisk: byRisk)
                }
            }
            if !reduce {
                Button {
                    state.showMoreOptions.toggle()
                } label: {
                    HStack(spacing: 4) {
                        Text(more ? T("Minder ▾") : T("Meer ▸")).fontWeight(.semibold)
                        if !more { Text(T("gespreid instappen · meerdere TP's")).foregroundStyle(Theme.dim) }
                    }
                    .font(.system(size: 11.5))
                    .foregroundStyle(Theme.accent)
                }
                .buttonStyle(.plain)
                .disabled((t?.entries.count ?? 1) > 1 || (t?.tps.count ?? 0) > 1)
            }

            Divider().overlay(Theme.line)

            if let pl {
                if let before = pl.before, adding { BeforeAfterView(before: before, after: pl.after, plan: pl) }
                summary(t, pl, reduce: reduce, adding: adding)
                ForEach(pl.warnings + state.budgetWarnings(pl), id: \.self) { w in
                    Label(T(w), systemImage: "exclamationmark.triangle.fill")
                        .font(.system(size: 11)).foregroundStyle(Theme.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            HStack(spacing: 8) {
                Button(T("Annuleer")) { state.ticket = nil }
                    .buttonStyle(BigButtonStyle(color: Theme.card, textColor: Theme.text))
                    .frame(width: 92)
                    .keyboardShortcut(.cancelAction)
                Button {
                    state.requestPlaceTicket()
                } label: {
                    HStack {
                        if state.busy { ProgressView().controlSize(.small) }
                        Text(placeTitle(t, adding: adding))
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(BigButtonStyle(color: reduce ? Theme.orange : ((t?.isLong ?? true) ? Theme.green : Theme.red)))
                .disabled(pl == nil || state.busy || (pl?.size ?? 0) <= 0)
                .demoAnchor("btn-place")
                .keyboardShortcut(.return, modifiers: .command)
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
    private func entrySection(_ t: Ticket?, more: Bool, reduce: Bool) -> some View {
        let entries = t?.entries ?? []
        let tick = state.priceTick
        ForEach(Array(entries.enumerated()), id: \.element.id) { i, e in
            if i == 0 || more {
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
                    }
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
                    unitToggle(state.stopInPct) { state.stopInPct.toggle() }
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
            if t.useStopLoss || byRisk {
                Text(state.stopInPct ? "= \(Fmt.price(t.stopLoss))" : T("\(Fmt.number(-abs(pct), decimals: 2))% vanaf \((t.entries.count > 1) ? "gem. entry" : "entry")"))
                    .font(.system(size: 10)).foregroundStyle(Theme.dim).frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
    }

    @ViewBuilder
    private func tpSection(_ t: Ticket?, _ pl: Plan?, more: Bool, byRisk: Bool) -> some View {
        if let t {
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
                if i == 0 || more {
                    let pct = entry > 0 ? dir * (tp.price - entry) / entry * 100 : 0
                    HStack(spacing: 6) {
                        if i == 0 && t.tps.count == 1 {
                            Toggle("", isOn: Binding(get: { true }, set: { state.setUseTP($0) })).toggleStyle(.checkbox).labelsHidden()
                        }
                        Text(t.tps.count > 1 ? "TP\(i + 1)" : T("Take-profit")).font(.system(size: 12.5)).foregroundStyle(Theme.muted)
                        Spacer(minLength: 4)
                        if i == 0 { unitToggle(state.tpInPct) { state.tpInPct.toggle() } }
                        if state.tpInPct {
                            NumberField(value: pct, step: 0.05, decimals: 2, color: Theme.green, range: 0.01...1000, suffix: "%", width: t.tps.count > 1 ? 64 : 96) { v in
                                state.setTicketTP(i, entry * (1 + dir * v / 100))
                            }
                        } else {
                            NumberField(value: tp.price, step: state.priceTick, decimals: priceDecimals, grouping: true, color: Theme.green,
                                        range: state.priceTick...1e12, width: t.tps.count > 1 ? 64 : 96) { state.setTicketTP(i, $0) }
                        }
                        if t.tps.count > 1 {
                            NumberField(value: tp.pct, step: 5, decimals: 0, range: 5...95, suffix: "%", width: 34) { state.setTPPct(i, $0) }
                            RemoveButton(help: T("Take-profit weghalen")) { state.removeTicketTP(i) }
                        }
                    }
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
                if t?.riskSized == true && !adding {
                    KV(T("Grootte"), "\(state.fmt.size(pl.size, coin: state.coin, decimals: state.szDecimals)) · \(state.fmt.usd(pl.notional))")
                    KV(T("Hefboom · marge"), T("\(t?.leverage ?? pl.leverage)× · \(state.fmt.usd(pl.marginRequired))"))
                }
                if (t?.entries.count ?? 1) > 1 { KV(adding ? T("Gem. entry bijkoop") : T("Gem. entry als alles vult"), Fmt.price(pl.avgEntry), color: Theme.blue) }
                if let risk = pl.riskUsd {
                    KV(adding ? T("Risico hele trade") : T("Risico tot stop"), "\(state.fmt.usd(-risk, decimals: 2)) · \(Fmt.number(pl.riskPercentActual ?? 0, decimals: 2))%", color: Theme.red)
                } else {
                    KV(T("Risico"), T("geen stop-loss"), color: Theme.orange)
                }
                if let first = pl.riskFirstEntryOnly { KV(T("Als alleen E1 vult"), state.fmt.usd(-first, decimals: 2), color: Theme.red) }
                if let p = pl.potentialProfit {
                    KV(T("Winst · R:R"), "\(state.fmt.signedUsd(p, decimals: 2))\(pl.rewardRisk.map { " · " + Fmt.number($0, decimals: 1) + "R" } ?? "")", color: Theme.green)
                }
                KV(T("Fees ≈"), state.fmt.usd(pl.estFees, decimals: 2), color: Theme.muted)
                if !adding { KV(T("Liquidatie ≈"), Fmt.price(pl.estLiquidationPx), color: Theme.orange) }
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

    var body: some View {
        if let pos = state.position {
            let u = state.net(for: pos)
            let eq = max(state.account.accountValue, 1)
            let ot = state.openTrade
            let sl = state.existingStopOrder
            let tps = state.existingTPOrders
            Card(title: T("Open positie"), trailing: AnyView(SidePill(isLong: pos.isLong))) {
                HStack(alignment: .firstTextBaseline) {
                    Text(state.fmt.signedUsd(u)).mono(24, .bold).foregroundStyle(Theme.pnl(u))
                    Spacer()
                    Text(Fmt.percent(u / eq) + T(" van portfolio")).mono(10.5).foregroundStyle(Theme.muted)
                }
                Text(T("netto na fees\((ot?.funding ?? 0) != 0 ? " en funding" : "")")).font(.system(size: 10.5)).foregroundStyle(Theme.dim)
                VStack(spacing: 5) {
                    KV(T("Grootte · hefboom"), T("\(state.fmt.size(pos.size, coin: state.coin, decimals: state.szDecimals)) · \(pos.leverage)× \(pos.isCross ? "cross" : "isolated")"))
                    KV(T("Gem. entry"), Fmt.price(pos.entryPx), color: Theme.blue)
                    if let be = state.breakEven { KV(T("Break-even"), Fmt.price(be), color: Theme.muted) }
                    KV(T("Stop-loss"), sl.map { Fmt.price($0.displayPx) } ?? T("geen"), color: sl == nil ? Theme.orange : Theme.red)
                    if let r = state.resultAtStop(pos) {
                        KV(T("Hele trade bij stop"), "\(state.fmt.signedUsd(r, decimals: 2)) · \(Fmt.percent(r / eq, decimals: 2))", color: Theme.pnl(r))
                    }
                    KV(T("Take-profit"), tps.isEmpty ? T("geen") : tps.map { Fmt.price($0.displayPx) }.joined(separator: " · "), color: tps.isEmpty ? Theme.muted : Theme.green)
                    if let liq = pos.liquidationPx { KV(T("Liquidatie"), Fmt.price(liq), color: Theme.orange) }
                    if let ot, ot.realized != 0 { KV(T("Al gerealiseerd"), state.fmt.signedUsd(ot.realized, decimals: 2), color: Theme.pnl(ot.realized)) }
                }
                HStack(spacing: 6) {
                    if sl == nil { Button(T("+ Stop-loss")) { Task { await state.addPositionTpSl(.sl) } }.buttonStyle(ChipStyle(active: false, large: true)) }
                    if tps.isEmpty { Button(T("+ Take-profit")) { Task { await state.addPositionTpSl(.tp) } }.buttonStyle(ChipStyle(active: false, large: true)) }
                    if let sl, let be = state.breakEven, pos.isLong ? be > sl.displayPx : be < sl.displayPx {
                        Button(T("Stop → break-even")) { Task { await state.moveStopToBreakEven(coin: pos.coin, force: true) } }
                            .buttonStyle(ChipStyle(active: false, large: true))
                            .help(T("Zet de stop-loss op \(Fmt.price(be)): deze trade kan dan niet meer verliezen (na fees)."))
                    }
                }
                if state.breakEvenAfterTP.contains(pos.coin) {
                    Label(T("Stop gaat naar break-even na de eerste TP"), systemImage: "arrow.right.to.line")
                        .font(.system(size: 10.5)).foregroundStyle(Theme.accent)
                }
            }

            if state.ticket != nil {
                TicketCard()
            } else {
                Card(title: T("Bijkopen")) {
                    Text(T("Extra entry op deze positie. Je stop en take-profits groeien mee.")).font(.system(size: 11)).foregroundStyle(Theme.dim)
                    Button { state.newTicket(long: pos.isLong) } label: { Text(T("Bijkopen…")).frame(maxWidth: .infinity) }
                        .buttonStyle(BigButtonStyle(color: Theme.card, textColor: Theme.text))
                }
                Card(title: T("Verkleinen")) {
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
                }
            }
            OrdersCard()
        } else {
            VStack(spacing: 8) {
                Image(systemName: "tray").font(.system(size: 22)).foregroundStyle(Theme.dim)
                Text(T("Geen open positie in \(state.coin).")).font(.system(size: 12.5)).foregroundStyle(Theme.muted)
                Text(T("Open een trade via Risico of Bedrag. Hier beheer je hem daarna: bijkopen, verkleinen, stop verplaatsen."))
                    .font(.system(size: 11)).foregroundStyle(Theme.dim).multilineTextAlignment(.center)
            }
            .padding(.vertical, 24)
            .frame(maxWidth: .infinity)
            OrdersCard()
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
        if !orders.isEmpty {
            Card(title: T("Open orders \(state.coin)")) {
                ForEach(orders) { o in
                    HStack(spacing: 8) {
                        Circle().fill(color(o)).frame(width: 7, height: 7)
                        Text(state.orderName(o)).font(.system(size: 12))
                        Spacer()
                        if let pnl = state.setupOutcome(o) {
                            Text(state.fmt.signedUsd(pnl)).mono(11).foregroundStyle(pnl < 0 ? Theme.red : Theme.green)
                        }
                        Text(Fmt.price(state.pendingOrderPrices[o.oid] ?? o.displayPx)).mono(12)
                        Button {
                            Task { await state.cancelOrder(o.oid) }
                        } label: {
                            Image(systemName: "xmark.circle.fill").foregroundStyle(Theme.dim)
                        }
                        .buttonStyle(.plain)
                        .help(T("Annuleer"))
                    }
                }
                Text(T("Tip: sleep een orderlijn in de chart om de prijs te wijzigen.")).font(.system(size: 10.5)).foregroundStyle(Theme.dim)
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
