#if os(macOS)
import SwiftUI
import GripCore

/// One line under the chart with all positions and orders; ⌘J unfolds it into an overview.
struct StatusDock: View {
    @EnvironmentObject var state: AppState
    @State private var dragStart: Double?

    var body: some View {
        VStack(spacing: 0) {
            StatusStrip()
            if state.dockExpanded {
                VStack(spacing: 0) {
                    HStack(spacing: 4) {
                        dockTab(T("Posities \(state.account.positions.count)"), 0)
                        dockTab(T("Orders \(state.account.openOrders.count)"), 1)
                        Spacer()
                        Text(state.dockTab == 1 ? T("gesorteerd op afstand tot de koers") : T("klik een regel om naar die markt te gaan"))
                            .font(.system(size: 10.5)).foregroundStyle(Theme.dim)
                    }
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    Divider().overlay(Theme.line)
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            if state.dockTab == 0 {
                                if state.account.positions.isEmpty { empty(T("Geen open posities")) }
                                ForEach(state.account.positions) { PositionRow(pos: $0) }
                            } else {
                                if state.account.openOrders.isEmpty { empty(T("Geen open orders")) }
                                ForEach(state.ordersByDistance) { OrderRow(order: $0) }
                            }
                        }
                    }
                }
                .frame(height: CGFloat(state.dockHeight))
                .background(Theme.panel)
            }
        }
        .overlay(alignment: .top) {
            // Drag the top edge to resize the open overview.
            if state.dockExpanded {
                Color.clear.frame(height: 6).contentShape(Rectangle())
                    .onHover { h in if h { NSCursor.resizeUpDown.push() } else { NSCursor.pop() } }
                    .gesture(DragGesture(minimumDistance: 1)
                        .onChanged { g in
                            if dragStart == nil { dragStart = state.dockHeight }
                            state.dockHeight = min(max((dragStart ?? 220) - g.translation.height, 90), 600)
                        }
                        .onEnded { _ in dragStart = nil })
            }
        }
    }

    private func dockTab(_ title: String, _ i: Int) -> some View {
        Button(title) { state.dockTab = i }
            .buttonStyle(.plain)
            .font(.system(size: 11.5, weight: state.dockTab == i ? .semibold : .regular))
            .foregroundStyle(state.dockTab == i ? Theme.text : Theme.muted)
            .padding(.horizontal, 9).padding(.vertical, 3)
            .background(RoundedRectangle(cornerRadius: 6).fill(state.dockTab == i ? Theme.card : Color.clear))
    }

    private func empty(_ s: String) -> some View {
        Text(s).font(.system(size: 12)).foregroundStyle(Theme.dim).frame(maxWidth: .infinity).padding(.vertical, 18)
    }
}

/// The single line: positions with result, warnings, orders and the nearest one, margin.
struct StatusStrip: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        HStack(spacing: 14) {
            label(T("POSITIES"))
            if state.account.positions.isEmpty {
                Text(T("geen")).foregroundStyle(Theme.dim)
            }
            ForEach(state.account.positions) { p in
                let net = state.net(for: p)
                Button { state.coin = p.coin } label: {
                    HStack(spacing: 5) {
                        Text("\(p.isLong ? "▲" : "▼") \(p.coin)").fontWeight(.semibold).foregroundStyle(p.isLong ? Theme.green : Theme.red)
                        Text(state.fmt.signedUsd(net)).mono(11).foregroundStyle(Theme.pnl(net))
                        if state.stopOrder(p.coin) == nil {
                            Text(T("geen stop")).font(.system(size: 10.5, weight: .semibold)).foregroundStyle(Theme.orange)
                        }
                    }
                }
                .buttonStyle(.plain)
                .help(T("Naar \(p.coin)"))
            }
            Divider().frame(height: 14)
            label(T("ORDERS"))
            Text(T("\(state.account.openOrders.count) open")).foregroundStyle(state.account.openOrders.isEmpty ? Theme.dim : Theme.text)
            if let o = state.ordersByDistance.first, let d = state.distance(o) {
                Button { state.coin = o.coin } label: {
                    Text(T("· \(o.coin) \(state.orderName(o).lowercased()) op \(Fmt.number(d * 100, decimals: d < 0.01 ? 2 : 1))%"))
                        .foregroundStyle(d < 0.005 ? Theme.orange : Theme.muted)
                }
                .buttonStyle(.plain)
            }
            MarginBudgetView()
            Spacer(minLength: 0)
            Button {
                state.dockExpanded.toggle()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: state.dockExpanded ? "chevron.down" : "chevron.up").font(.system(size: 9, weight: .bold))
                    Text(T("⌘J")).font(.system(size: 10)).foregroundStyle(Theme.dim)
                }
            }
            .buttonStyle(.plain)
            .foregroundStyle(Theme.muted)
            .help(state.dockExpanded ? T("Overzicht inklappen (⌘J)") : T("Overzicht van alle posities en orders (⌘J)"))
        }
        .font(.system(size: 11.5))
        .lineLimit(1)
        .padding(.horizontal, 12)
        .frame(height: 28)
        .background(Theme.panel)
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { state.dockExpanded.toggle() }
        .overlay(alignment: .top) { Divider().overlay(Theme.line) }
    }

    private func label(_ s: String) -> some View {
        Text(s).font(.system(size: 9.5, weight: .semibold)).tracking(0.6).foregroundStyle(Theme.dim)
    }
}


// MARK: - Rows

struct PositionRow: View {
    @EnvironmentObject var state: AppState
    let pos: Position
    @State private var hovering = false

    var body: some View {
        let net = state.net(for: pos)
        let px = state.livePrice(pos.coin) ?? pos.entryPx
        let sl = state.stopOrder(pos.coin)
        let tp = state.takeProfits(pos.coin).map(\.displayPx).sorted(by: { pos.isLong ? $0 > $1 : $0 < $1 }).first
        let be = state.breakEven(for: pos)
        HStack(spacing: 10) {
            HStack(spacing: 6) {
                SidePill(isLong: pos.isLong)
                Text(pos.coin).fontWeight(.semibold)
                Text(T("\(pos.leverage)×")).foregroundStyle(Theme.dim)
            }
            .frame(width: 130, alignment: .leading)
            Text(state.fmt.size(pos.size, coin: "", decimals: 4)).mono(11.5).frame(width: 80, alignment: .trailing)
            Text("\(Fmt.price(pos.entryPx)) → \(Fmt.price(px))").mono(11.5).frame(width: 150, alignment: .trailing)
            Text(state.fmt.signedUsd(net, decimals: 2)).mono(11.5, .semibold).foregroundStyle(Theme.pnl(net)).frame(width: 90, alignment: .trailing)
            Group {
                if sl == nil {
                    HStack(spacing: 6) {
                        Text(T("⚠ geen stop")).font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.orange)
                        Button(T("+ Stop")) { state.goToPosition(pos.coin) }.buttonStyle(MiniButtonStyle())
                    }
                } else {
                    TradeProgressBar(isLong: pos.isLong, stop: sl?.displayPx, breakEven: be, target: tp, price: px)
                }
            }
            .frame(width: 170, alignment: .leading)
            Group {
                if let r = state.resultAtStop(pos) {
                    Text(state.fmt.signedUsd(r)).mono(11).foregroundStyle(Theme.pnl(r))
                        .help(T("Hele trade bij stop: \(state.fmt.signedUsd(r, decimals: 2)) (\(Fmt.percent(r / max(state.account.accountValue, 1), decimals: 2)) van je account), fees en al gerealiseerde delen meegerekend"))
                } else {
                    Text("–").foregroundStyle(Theme.dim)
                }
            }
            .frame(width: 70, alignment: .trailing)
            Text(pos.liquidationPx.map { Fmt.price($0) } ?? "–").mono(11).foregroundStyle(Theme.dim).frame(width: 70, alignment: .trailing)
            Spacer(minLength: 4)
            HStack(spacing: 4) {
                Button("½") { state.requestClose(fraction: 0.5, coin: pos.coin) }.buttonStyle(MiniButtonStyle()).help(T("Helft sluiten (market)"))
                Button(T("Sluit")) { state.requestClose(fraction: 1, coin: pos.coin) }.buttonStyle(MiniButtonStyle()).help(T("Hele positie sluiten (market)"))
                Button("⇅") { state.requestReverse(coin: pos.coin) }.buttonStyle(MiniButtonStyle()).help(T("Omkeren: long ↔ short, zelfde grootte"))
                if let sl, let be, pos.isLong ? be > sl.displayPx : be < sl.displayPx {
                    Button(T("BE")) { Task { await state.moveStopToBreakEven(coin: pos.coin, force: true) } }
                        .buttonStyle(MiniButtonStyle()).help(T("Stop naar break-even (\(Fmt.price(be)))"))
                }
            }
            .disabled(state.busy)
        }
        .font(.system(size: 12))
        .padding(.horizontal, 12).padding(.vertical, 7)
        .background(hovering ? Color.white.opacity(0.03) : (pos.coin == state.coin ? Theme.card.opacity(0.6) : Color.clear))
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture(count: 2) { state.goToPosition(pos.coin) }
        .onTapGesture { state.coin = pos.coin }
        .overlay(alignment: .bottom) { Divider().overlay(Theme.line) }
    }
}

/// Where the price is between stop and target: red part = towards the stop, green = towards the target.
struct TradeProgressBar: View {
    let isLong: Bool
    let stop: Double?
    let breakEven: Double?
    let target: Double?
    let price: Double

    var body: some View {
        GeometryReader { g in
            let w = g.size.width
            let lo = stop ?? (isLong ? price * 0.98 : price * 1.02)
            let hi = target ?? (isLong ? price * 1.02 : price * 0.98)
            let f = { (p: Double) -> CGFloat in
                let span = hi - lo
                guard abs(span) > 1e-12 else { return 0.5 }
                return CGFloat(min(max((p - lo) / span, 0), 1))
            }
            let beX = breakEven.map { f($0) * w } ?? w * 0.3
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.red.opacity(0.45)).frame(width: max(beX, 0), height: 3).offset(y: 3)
                Capsule().fill(Theme.green.opacity(0.45)).frame(width: max(w - beX, 0), height: 3).offset(x: beX, y: 3)
                Rectangle().fill(Theme.muted).frame(width: 1.5, height: 10).offset(x: beX - 0.75, y: 3)
                Circle().fill(Theme.text).frame(width: 9, height: 9).overlay(Circle().stroke(Theme.bg, lineWidth: 2)).offset(x: f(price) * w - 4.5, y: 3)
                Text(T("SL")).font(.system(size: 8)).foregroundStyle(Theme.dim).offset(y: -7)
                Text(target == nil ? "–" : "TP").font(.system(size: 8)).foregroundStyle(Theme.dim).offset(x: w - 10, y: -7)
            }
        }
        .frame(height: 20)
        .help(T("Koers tussen je stop (links) en je doel (rechts); het streepje is break-even"))
    }
}

struct OrderRow: View {
    @EnvironmentObject var state: AppState
    let order: OpenOrder
    @State private var editing = false
    @State private var text = ""
    @State private var hovering = false

    var body: some View {
        let o = order
        let d = state.distance(o)
        HStack(spacing: 10) {
            Text(o.coin).fontWeight(.semibold).frame(width: 60, alignment: .leading)
            Text(state.orderName(o) + (o.isTrigger || o.reduceOnly ? "" : (o.isBuy ? T(" long") : T(" short"))))
                .foregroundStyle(color(o)).frame(width: 130, alignment: .leading)
            Group {
                if editing {
                    TextField("", text: $text)
                        .textFieldStyle(.plain).mono(11.5)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(RoundedRectangle(cornerRadius: 5).fill(Color.black.opacity(0.35)))
                        .onSubmit { save() }
                        .onExitCommand { editing = false }
                } else {
                    Text(Fmt.price(state.pendingOrderPrices[o.oid] ?? o.displayPx)).mono(11.5)
                }
            }
            .frame(width: 100, alignment: .trailing)
            HStack(spacing: 6) {
                let near = (d ?? 1) < 0.005
                GeometryReader { g in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.white.opacity(0.07))
                        Capsule().fill(near ? Theme.orange : Theme.blue).frame(width: g.size.width * CGFloat(max(0.04, 1 - min((d ?? 1) / 0.08, 1))))
                    }
                }
                .frame(width: 64, height: 5)
                Text(d.map { Fmt.number($0 * 100, decimals: $0 < 0.01 ? 2 : 1) + "%" } ?? "–").mono(11).foregroundStyle(near ? Theme.orange : Theme.muted)
            }
            .frame(width: 130, alignment: .leading)
            Text(o.size > 0 ? state.fmt.size(o.size, coin: "", decimals: 4) : T("hele positie")).mono(11).frame(width: 90, alignment: .trailing)
            Text(age(o.timestamp)).foregroundStyle(Theme.dim).frame(width: 80, alignment: .trailing)
            Spacer(minLength: 4)
            HStack(spacing: 4) {
                if editing {
                    Button(T("Opslaan")) { save() }.buttonStyle(MiniButtonStyle())
                } else {
                    Button(T("Wijzig")) { text = Fmt.price(o.displayPx).replacingOccurrences(of: L10n.isEnglish ? "," : ".", with: ""); editing = true }
                        .buttonStyle(MiniButtonStyle()).help(T("Prijs aanpassen (of sleep de lijn in de chart)"))
                }
                Button("↗") { state.coin = o.coin; state.tab = .trade }.buttonStyle(MiniButtonStyle()).help(T("Naar de chart van \(o.coin)"))
                Button("✕") { Task { await state.cancelOrder(o.oid) } }.buttonStyle(MiniButtonStyle(color: Theme.red)).help(T("Annuleren"))
            }
        }
        .font(.system(size: 12))
        .padding(.horizontal, 12).padding(.vertical, 7)
        .background(hovering ? Color.white.opacity(0.03) : Color.clear)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture { state.coin = o.coin }
        .contextMenu {
            Button(T("Alle orders in \(o.coin) annuleren"), role: .destructive) {
                Task { for x in state.account.orders(for: o.coin) { await state.cancelOrder(x.oid) } }
            }
        }
        .overlay(alignment: .bottom) { Divider().overlay(Theme.line) }
    }

    private func save() {
        editing = false
        var t = text.filter { "0123456789.,".contains($0) }
        if L10n.isEnglish { t = t.replacingOccurrences(of: ",", with: "") }
        else if t.range(of: #"^\d{1,3}(\.\d{3})+(,\d+)?$"#, options: .regularExpression) != nil { t = t.replacingOccurrences(of: ".", with: "") }
        if !L10n.isEnglish { t = t.replacingOccurrences(of: ",", with: ".") }
        guard let px = Double(t), px > 0 else { return }
        state.pendingOrderPrices[order.oid] = px
        Task { await state.moveOrder(oid: order.oid, to: px) }
    }

    private func color(_ o: OpenOrder) -> Color {
        if o.isTrigger { return o.tpsl == .tp ? Theme.green : Theme.red }
        return o.reduceOnly ? Theme.orange : Theme.blue
    }

    private func age(_ ms: Int64) -> String {
        let s = Date().timeIntervalSince1970 - Double(ms) / 1000
        if s < 3600 { return T("\(max(1, Int(s / 60))) min") }
        if s < 86_400 { return T("\(Int(s / 3600)) u") }
        if s < 172_800 { return T("gisteren") }
        return T("\(Int(s / 86_400)) dagen")
    }
}

struct MiniButtonStyle: ButtonStyle {
    var color: Color = Theme.text
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(color)
            .padding(.horizontal, 7).padding(.vertical, 2)
            .background(RoundedRectangle(cornerRadius: 5).fill(Color.white.opacity(configuration.isPressed ? 0.14 : 0.05)))
            .overlay(RoundedRectangle(cornerRadius: 5).stroke(Theme.line))
            .contentShape(Rectangle())
    }
}

// MARK: - Market tabs

struct MarketTabs: View {
    @EnvironmentObject var state: AppState
    var body: some View {
        HStack(spacing: 2) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 3) {
                    ForEach(state.marketTabs, id: \.self) { MarketTab(market: $0) }
                }
            }
            .frame(maxWidth: 620)
            .fixedSize(horizontal: true, vertical: false)
            CoinPicker()
        }
    }
}

struct MarketTab: View {
    @EnvironmentObject var state: AppState
    let market: String
    @State private var hovering = false

    var body: some View {
        let on = market == state.coin
        let pos = state.account.position(for: market)
        let orders = state.account.orders(for: market).count
        let near = (state.nearestDistance(market) ?? 1) < 0.005
        HStack(spacing: 6) {
            Text(market).font(.system(size: 12, weight: .semibold)).foregroundStyle(on ? Theme.text : Theme.muted)
            if let p = state.livePrice(market) { Text(Fmt.price(p)).mono(11).foregroundStyle(on ? Theme.text : Theme.muted) }
            if let pos {
                let net = state.net(for: pos)
                Text(state.fmt.signedUsd(net))
                    .mono(10.5).foregroundStyle(Theme.pnl(net))
                    .padding(.horizontal, 5).padding(.vertical, 1)
                    .background(RoundedRectangle(cornerRadius: 4).fill(Theme.pnl(net).opacity(0.14)))
            }
            if orders > 0 {
                HStack(spacing: 2) {
                    Circle().fill(near ? Theme.orange : Theme.blue).frame(width: 6, height: 6)
                    Text("\(orders)").font(.system(size: 10)).foregroundStyle(Theme.muted)
                }
                .help(near ? T("Een order ligt dichtbij de koers") : T("\(orders) open order\(orders == 1 ? "" : "s")"))
            }
            if hovering && !state.isPinned(market) && state.marketTabs.count > 1 {
                Button { state.closeTab(market) } label: { Image(systemName: "xmark").font(.system(size: 8, weight: .bold)) }
                    .buttonStyle(.plain).foregroundStyle(Theme.muted).help(T("Tab sluiten"))
            }
        }
        .padding(.horizontal, 9).padding(.vertical, 4)
        .background(RoundedRectangle(cornerRadius: 7).fill(on ? Theme.card : (hovering ? Color.white.opacity(0.04) : Color.clear)))
        .overlay(RoundedRectangle(cornerRadius: 7).stroke(on ? Theme.line : Color.clear))
        .contentShape(Rectangle())
        .onTapGesture { state.coin = market }
        .onHover { hovering = $0 }
    }
}
#endif
