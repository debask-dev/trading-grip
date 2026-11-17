#if os(macOS)
import SwiftUI
import AppKit
import GripCore
import UniformTypeIdentifiers

// MARK: - Take-profit ladder, break-even, chart ✕ buttons, price menu

extension AppState {
    /// After a take-profit: move the stop-loss to break-even (when chosen in the ticket).
    func moveStopToBreakEven(coin c: String, force: Bool = false) async {
        guard force || breakEvenAfterTP.contains(c), let pos = account.position(for: c),
              let sl = account.openOrders.first(where: { $0.coin == c && $0.isStop }),
              let a = assets.first(where: { $0.name == c }) else { return }
        let o = analysis.open[c]
        guard let be = PositionMath.breakEven(entry: pos.entryPx, size: pos.size, feesPaid: o?.feesPaid ?? 0, realized: force ? (o?.realized ?? 0) : 0,
                                        funding: o?.funding ?? 0, takerRate: feeRates.taker) else { return }
        let px = HLFormat.roundPrice(be, szDecimals: a.szDecimals)
        // Only ever move the stop in the safe direction.
        guard pos.isLong ? px > sl.displayPx : px < sl.displayPx else { breakEvenAfterTP.remove(c); return }
        // One stop: it covers the whole position. Several (a ladder that is not complete yet): each keeps its size.
        let single = stopOrders(c).count <= 1
        let req = OrderRequest(asset: a, isBuy: !pos.isLong, size: single ? abs(pos.size) : (sl.size > 0 ? sl.size : abs(pos.size)), limitPx: px, reduceOnly: true,
                               kind: .trigger(triggerPx: px, isMarket: true, tpsl: .sl))
        do {
            try await execModify(oid: sl.oid, req)
            managed[c]?.stop = px
            try await moveOtherStops(coin: c, asset: a, to: px, except: sl.oid)
            breakEvenAfterTP.remove(c)
            toast(T("Stop-loss naar break-even: \(Fmt.price(px))"), .success)
        } catch {
            toast(T("Stop niet verplaatst: \(error.localizedDescription)"), .error)
        }
        await refreshAccount()
    }

    /// ✕ on a chart line.
    func lineClosed(_ id: LineID) {
        switch id {
        case .ticketEntry(let i): removeTicketEntry(i)
        case .ticketSL: if ticket?.riskSized == false { setUseStop(false) }
        case .ticketLiq, .pendingTP, .plan, .averageTP: break
        case .draftTP(let i): removeDraftTP(i)
        case .ticketTP(let i): removeTicketTP(i)
        case .order(let oid):
            Task { await cancelOrder(oid) }
        case .position: requestClose(fraction: 1)
        case .breakEven, .liquidation: break
        }
    }

    /// Right-click on the chart.
    func priceMenu(at raw: Double) -> [(String, @MainActor () -> Void)] {
        let px = roundToTick(raw)
        let p = price
        var items: [(String, @MainActor () -> Void)] = []
        if let t = ticket {
            items.append((t.entries.count > 1 ? T("E1 hier") : T("Entry hier"), { [weak self] in self?.ticket?.entry = px; self?.ticket?.isMarket = false }))
            items.append((T("Extra entry hier"), { [weak self] in self?.addTicketEntry(at: px) }))
            if !t.reduceOnly {
                if t.isLong ? px < t.entry : px > t.entry {
                    items.append((T("Stop-loss hier"), { [weak self] in self?.ticket?.stopLoss = px; self?.ticket?.useStopLoss = true }))
                } else {
                    items.append((T("Take-profit hier"), { [weak self] in self?.addTicketTP(at: px) }))
                }
            }
            items.append(("-", {}))
        }
        if let pos = position, ticket == nil {
            items.append((T("Bijkopen hier (\(pos.isLong ? "long" : "short"))"), { [weak self] in self?.newTicket(long: pos.isLong, entry: px) }))
        } else if p > 0 && ticket == nil {
            items.append((px < p ? T("Limit long hier") : T("Limit short hier"), { [weak self] in self?.newTicket(long: px < p, entry: px) }))
        }
        if position != nil {
            items.append(("-", {}))
            items.append((T("Positie deels sluiten hier (\(Int(dragCloseFraction * 100))%)"), { [weak self] in Task { await self?.closeAtLimit(price: px) } }))
        }
        return items
    }

    // MARK: Quick panel

    /// ⌥B / ⌥N: market order with the Bedrag tab's last values (amount, leverage, stop, TP), after confirmation.
    func quickTrade(long: Bool) {
        guard price > 0, asset != nil else { return }
        if let pos = position, pos.isLong != long {
            let side = pos.isLong ? "long" : "short"
            pendingConfirm = ConfirmRequest(
                title: T("Je zit \(side) in \(coin)"),
                message: T("Een market \(long ? "long" : "short") zou je \(side) verkleinen in plaats van een nieuwe trade te openen. Wil je je positie sluiten?"),
                confirmTitle: T("Hele positie sluiten"), destructive: true) { [weak self] in Task { await self?.closePosition(fraction: 1) } }
            return
        }
        if panelMode != .amount { panelMode = .amount }
        newTicket(long: long)
        ticket?.isMarket = true
        requestPlaceTicket()
    }

    /// Market close of everything on the current coin (quick panel / ⌥X).
    func quickClose() { requestClose(fraction: 1) }

    // MARK: Last hour

    /// 1m candles of the last 60 minutes → change, range and volume for the header strip.
    func refreshHourStats() async {
        let c = coin
        guard let cs = try? await client.candles(coin: c, timeframe: .m1, count: 60), c == coin, let first = cs.first, let last = cs.last else { return }
        let vol = cs.reduce(0) { $0 + $1.volume }
        let usd = cs.reduce(0) { $0 + $1.volume * ($1.high + $1.low + $1.close) / 3 }
        hourStats = HourStats(change: first.open > 0 ? (last.close - first.open) / first.open : 0,
                              high: cs.map(\.high).max() ?? 0, low: cs.map(\.low).min() ?? 0, volume: vol, volumeUsd: usd)
    }

    // MARK: Screenshot

    /// Saves the chart (with a title banner) to the screenshot folder and copies it to the clipboard.
    func takeScreenshot() {
        guard let canvas = chartCanvas, let chart = canvas.snapshotImage() else { toast(T("Geen chart om vast te leggen."), .error); return }
        let banner: CGFloat = 34
        let size = NSSize(width: chart.size.width, height: chart.size.height + banner)
        let img = NSImage(size: size)
        img.lockFocus()
        Palette.bg.setFill()
        NSRect(origin: .zero, size: size).fill()
        chart.draw(in: NSRect(x: 0, y: 0, width: chart.size.width, height: chart.size.height))
        let ch = change24h
        let title = T("\(coin)-PERP · \(timeframe.label) · \(Fmt.price(price))  \(ch >= 0 ? "+" : "")\(Fmt.number(ch * 100, decimals: 2))%")
        let when = Date().formatted(date: .abbreviated, time: .shortened)
        (title as NSString).draw(at: NSPoint(x: 14, y: chart.size.height + 9),
                                 withAttributes: [.font: NSFont.systemFont(ofSize: 14, weight: .semibold), .foregroundColor: NSColor.white])
        let right = T("Grip · \(when)") as NSString
        let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 12), .foregroundColor: NSColor.secondaryLabelColor]
        right.draw(at: NSPoint(x: size.width - right.size(withAttributes: attrs).width - 14, y: chart.size.height + 10), withAttributes: attrs)
        img.unlockFocus()

        guard let tiff = img.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else { return }
        if screenshotToClipboard {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.writeObjects([img])
        }
        let folder = URL(fileURLWithPath: (screenshotFolder as NSString).expandingTildeInPath, isDirectory: true)
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd HH.mm.ss"
        let stamp = df.string(from: Date())
        let file = folder.appendingPathComponent("Grip \(coin) \(timeframe.label) \(stamp).png")
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try png.write(to: file)
            Notifier.shared.playShutter()
            toast(T("Screenshot bewaard\(screenshotToClipboard ? " en gekopieerd" : "") · \(file.lastPathComponent)"), .success)
        } catch {
            toast(T("Screenshot niet bewaard: \(error.localizedDescription)"), .error)
        }
    }

    func revealScreenshotFolder() {
        let url = URL(fileURLWithPath: (screenshotFolder as NSString).expandingTildeInPath, isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        NSWorkspace.shared.open(url)
    }

    func chooseScreenshotFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = T("Kies map")
        panel.directoryURL = URL(fileURLWithPath: (screenshotFolder as NSString).expandingTildeInPath)
        if panel.runModal() == .OK, let u = panel.url { screenshotFolder = u.path }
    }
}
#endif
