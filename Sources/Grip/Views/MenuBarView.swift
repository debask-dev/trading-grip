#if os(macOS)
import SwiftUI
import AppKit
import GripCore

/// Menu bar mini: open positions with net result and quick close, also when Grip is in the background.
struct MenuBarView: View {
    @EnvironmentObject var state: AppState
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(nsImage: GripLogo.menuBar).renderingMode(.template).foregroundStyle(Theme.text)
                Text("Grip").font(.system(size: 13, weight: .bold))
                Spacer()
                Text(state.paperMode ? T("OEFENEN") : (state.network.isMainnet ? T("MAINNET") : T("TESTNET")))
                    .font(.system(size: 10, weight: .bold)).foregroundStyle(Theme.muted)
            }
            section(T("Posities"), count: state.account.positions.count)
            if state.account.positions.isEmpty {
                Text(T("Geen open posities")).foregroundStyle(Theme.muted).font(.system(size: 12))
            }
            ForEach(state.account.positions) { p in
                let net = state.net(for: p)
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        SidePill(isLong: p.isLong)
                        Text(p.coin).font(.system(size: 13, weight: .semibold))
                        Spacer()
                        Text(state.fmt.signedUsd(net, decimals: 2)).mono(13, .semibold).foregroundStyle(Theme.pnl(net))
                    }
                    Text(T("\(state.fmt.size(p.size, coin: p.coin, decimals: 4)) · gem. \(Fmt.price(p.entryPx)) · netto na fees"))
                        .font(.system(size: 11)).foregroundStyle(Theme.muted)
                    HStack(spacing: 6) {
                        Button(T("Sluit 50%")) { confirmClose(p, 0.5) }
                        Button(T("Sluit alles")) { confirmClose(p, 1) }
                    }
                    .controlSize(.small)
                }
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 8).fill(Theme.card))
            }
            orders
            Divider().overlay(Theme.line)
            HStack {
                Button(T("Open Grip")) {
                    NSApp.activate(ignoringOtherApps: true)
                    openWindow(id: "main")
                }
                .foregroundStyle(Theme.text)
                Spacer()
                Button(T("Stop")) { NSApp.terminate(nil) }.foregroundStyle(Theme.muted)
            }
            .buttonStyle(.borderless)
        }
        .padding(14)
        .frame(width: 310)
        .foregroundStyle(Theme.text)
        // Always dark, also in light mode: the menu bar window ignores preferredColorScheme.
        .background(Theme.bg)
        .background(DarkWindow())
        .environment(\.colorScheme, .dark)
    }

    private func section(_ title: String, count: Int) -> some View {
        HStack {
            Text(title.uppercased()).font(.system(size: 10, weight: .semibold)).tracking(0.8)
            Spacer()
            if count > 0 { Text("\(count)").mono(10, .semibold) }
        }
        .foregroundStyle(Theme.muted)
    }

    /// Waiting orders on every market, nearest to the price first, so none get forgotten.
    @ViewBuilder private var orders: some View {
        let all = state.ordersByDistance
        let shown = all.prefix(8)
        section(T("Open orders"), count: all.count)
        if all.isEmpty {
            Text(T("Geen open orders")).foregroundStyle(Theme.muted).font(.system(size: 12))
        } else {
            VStack(spacing: 0) {
                ForEach(Array(shown)) { o in
                    let d = state.distance(o)
                    let loose = !state.account.positions.contains { $0.coin == o.coin }
                    HStack(spacing: 6) {
                        Text(o.coin).font(.system(size: 12, weight: .semibold)).frame(width: 46, alignment: .leading).lineLimit(1)
                        Text(state.orderName(o) + (o.isTrigger || o.reduceOnly ? "" : (o.isBuy ? T(" long") : T(" short"))))
                            .font(.system(size: 11.5)).foregroundStyle(color(o)).lineLimit(1)
                        Spacer(minLength: 4)
                        Text(Fmt.price(o.displayPx)).mono(11.5)
                        Text(d.map { Fmt.number($0 * 100, decimals: $0 < 0.01 ? 2 : 1) + "%" } ?? "–")
                            .mono(10.5).foregroundStyle((d ?? 1) < 0.005 ? Theme.orange : Theme.muted)
                            .frame(width: 40, alignment: .trailing)
                        Button { Task { await state.cancelOrder(o.oid) } } label: {
                            Image(systemName: "xmark").font(.system(size: 9, weight: .bold))
                        }
                        .buttonStyle(.borderless).foregroundStyle(Theme.muted)
                        .help(T("Annuleer order"))
                    }
                    .padding(.horizontal, 8).padding(.vertical, 5)
                    // Orders without a position on that coin are the easiest to forget: mark them.
                    .background(loose ? Theme.orange.opacity(0.08) : Color.clear)
                    .help(loose ? T("Geen positie op \(o.coin): deze order staat los open") : "")
                }
            }
            .background(RoundedRectangle(cornerRadius: 8).fill(Theme.card))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            if all.count > shown.count {
                Text(T("+\(all.count - shown.count) meer, zie ⌘J in Grip")).font(.system(size: 11)).foregroundStyle(Theme.muted)
            }
        }
    }

    private func color(_ o: OpenOrder) -> Color {
        if o.isTrigger { return o.tpsl == .tp ? Theme.green : Theme.red }
        return o.reduceOnly ? Theme.orange : Theme.blue
    }

    /// The menu bar window cannot host the app's own alert, so ask with a standard dialog.
    private func confirmClose(_ p: Position, _ fraction: Double) {
        guard state.confirmMarketOrders else { Task { await state.closePosition(fraction: fraction, coin: p.coin) }; return }
        let alert = NSAlert()
        alert.messageText = fraction >= 1 ? T("Hele \(p.coin)-positie sluiten?") : T("\(Int(fraction * 100))% van je \(p.coin)-positie sluiten?")
        alert.informativeText = T("Market order · huidig netto resultaat \(state.fmt.signedUsd(state.net(for: p), decimals: 2)).")
        alert.addButton(withTitle: fraction >= 1 ? T("Alles sluiten") : T("Sluit \(Int(fraction * 100))%"))
        alert.addButton(withTitle: T("Annuleer"))
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn {
            Task { await state.closePosition(fraction: fraction, coin: p.coin) }
        }
    }
}

/// Gives the menu bar window a dark appearance, so system controls and the material match Grip.
private struct DarkWindow: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { Probe() }
    func updateNSView(_ nsView: NSView, context: Context) {}

    final class Probe: NSView {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            window?.appearance = NSAppearance(named: .darkAqua)
        }
    }
}
#endif
