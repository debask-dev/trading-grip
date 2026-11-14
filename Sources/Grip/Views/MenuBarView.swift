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
            HStack {
                Text(T("Grip")).font(.system(size: 13, weight: .bold))
                Spacer()
                Text(state.paperMode ? T("OEFENEN") : (state.network.isMainnet ? T("MAINNET") : T("TESTNET")))
                    .font(.system(size: 10, weight: .bold)).foregroundStyle(Theme.muted)
            }
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
            Divider()
            HStack {
                Button(T("Open Grip")) {
                    NSApp.activate(ignoringOtherApps: true)
                    openWindow(id: "main")
                }
                Spacer()
                Button(T("Stop")) { NSApp.terminate(nil) }.foregroundStyle(Theme.muted)
            }
            .buttonStyle(.borderless)
        }
        .padding(14)
        .frame(width: 290)
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
#endif
