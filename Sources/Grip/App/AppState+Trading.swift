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
              let sl = account.openOrders.first(where: { $0.coin == c && $0.isTrigger && $0.tpsl == .sl }),
              let a = assets.first(where: { $0.name == c }) else { return }
        let o = analysis.open[c]
        guard let be = PositionMath.breakEven(entry: pos.entryPx, size: pos.size, feesPaid: o?.feesPaid ?? 0, realized: force ? (o?.realized ?? 0) : 0,
                                        funding: o?.funding ?? 0, takerRate: feeRates.taker) else { return }
        let px = HLFormat.roundPrice(be, szDecimals: a.szDecimals)
        // Only ever move the stop in the safe direction.
        guard pos.isLong ? px > sl.displayPx : px < sl.displayPx else { breakEvenAfterTP.remove(c); return }
        let req = OrderRequest(asset: a, isBuy: !pos.isLong, size: abs(pos.size), limitPx: px, reduceOnly: true,
                               kind: .trigger(triggerPx: px, isMarket: true, tpsl: .sl))
        do {
            try await execModify(oid: sl.oid, req)
            managed[c]?.stop = px
            breakEvenAfterTP.remove(c)
            toast("Stop-loss naar break-even: \(Fmt.price(px))", .success)
        } catch {
            toast("Stop niet verplaatst: \(error.localizedDescription)", .error)
        }
        await refreshAccount()
    }

    /// ✕ on a chart line.
    func lineClosed(_ id: LineID) {
        switch id {
        case .ticketEntry(let i): removeTicketEntry(i)
        case .ticketSL: if panelMode == .manual { ticket?.useStopLoss = false }
        case .ticketLiq, .pendingTP: break
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
            items.append((t.entries.count > 1 ? "E1 hier" : "Entry hier", { [weak self] in self?.ticket?.entry = px; self?.ticket?.isMarket = false }))
            items.append(("Extra entry hier", { [weak self] in self?.addTicketEntry(at: px) }))
            if !t.reduceOnly {
                if t.isLong ? px < t.entry : px > t.entry {
                    items.append(("Stop-loss hier", { [weak self] in self?.ticket?.stopLoss = px; self?.ticket?.useStopLoss = true }))
                } else {
                    items.append(("Take-profit hier", { [weak self] in self?.addTicketTP(at: px) }))
                }
            }
            items.append(("-", {}))
        }
        if let pos = position, ticket == nil {
            items.append(("Bijkopen hier (\(pos.isLong ? "long" : "short"))", { [weak self] in self?.newTicket(long: pos.isLong, entry: px) }))
        } else if p > 0 && ticket == nil {
            items.append((px < p ? "Limit long hier" : "Limit short hier", { [weak self] in self?.newTicket(long: px < p, entry: px) }))
        }
        if position != nil {
            items.append(("-", {}))
            items.append(("Positie deels sluiten hier (\(Int(dragCloseFraction * 100))%)", { [weak self] in Task { await self?.closeAtLimit(price: px) } }))
        }
        return items
    }

    // MARK: Quick panel

    /// Market in with a fixed order value; SL and TP as a % of the price.
    func quickTrade(long: Bool) {
        guard let a = asset, price > 0 else { return }
        if let pos = position, pos.isLong != long {
            let side = pos.isLong ? "long" : "short"
            pendingConfirm = ConfirmRequest(
                title: "Je zit \(side) in \(coin)",
                message: "Een market \(long ? "long" : "short") zou je \(side) verkleinen in plaats van een nieuwe trade te openen. Wil je je positie sluiten?",
                confirmTitle: "Hele positie sluiten", destructive: true) { [weak self] in Task { await self?.closePosition(fraction: 1) } }
            return
        }
        let p = price
        let size = HLFormat.roundSize(quickUsd / p, szDecimals: a.szDecimals, down: true)
        let dir: Double = long ? 1 : -1
        let sl = HLFormat.roundPrice(p * (1 - dir * quickSLPct / 100), szDecimals: a.szDecimals)
        let tp = HLFormat.roundPrice(p * (1 + dir * quickTPPct / 100), szDecimals: a.szDecimals)
        let risk = size * (abs(p - sl) + feeRates.taker * (p + sl))
        let go = { [weak self] in Task { await self?.placeQuick(long: long, size: size, sl: sl, tp: tp) } }
        guard confirmMarketOrders else { go(); return }
        let side = long ? "long" : "short"
        pendingConfirm = ConfirmRequest(
            title: "Market \(side) \(coin)?",
            message: "\(fmt.size(size, coin: coin, decimals: a.szDecimals)) ≈ \(fmt.usd(size * p)) · \(quickLev)×\nSL \(Fmt.price(sl)) (\(fmt.signedUsd(-risk, decimals: 2))) · TP \(Fmt.price(tp))",
            confirmTitle: "Market \(side)", destructive: false) { go() }
    }

    private func placeQuick(long: Bool, size: Double, sl: Double, tp: Double) async {
        guard let a = asset else { return }
        guard size * price >= 10 else { toast("Hyperliquid vereist minimaal $10 per order.", .error); return }
        guard hasAccount else { toast("Koppel eerst een account (⇧⌘A), of zet de oefenmodus aan.", .error); return }
        busy = true
        defer { busy = false }
        do {
            let pos = position
            let lev = min(max(quickLev, 1), a.maxLeverage)
            if let pos {
                if lev > pos.leverage { try await execLeverage(a, isCross: pos.isCross, leverage: lev) }
            } else {
                try await execLeverage(a, isCross: useCrossMargin && !a.onlyIsolated, leverage: lev)
            }
            let px = HLFormat.slippagePrice(price, isBuy: long, slippage: slippagePercent / 100, szDecimals: a.szDecimals)
            var reqs = [OrderRequest(asset: a, isBuy: long, size: size, limitPx: px, reduceOnly: false, kind: .limit(tif: "Ioc"))]
            if pos == nil {
                reqs.append(OrderRequest(asset: a, isBuy: !long, size: size, limitPx: sl, reduceOnly: true, kind: .trigger(triggerPx: sl, isMarket: true, tpsl: .sl)))
            }
            // Adding: the existing stop and take-profits grow with the position.
            var m = managed[coin] ?? ManagedTrade(isLong: long, lastSize: 0)
            m.isLong = long
            m.lastSize = abs(pos?.size ?? 0)
            m.stop = pos == nil ? sl : (existingStopOrder?.displayPx ?? sl)
            if existingTPOrders.isEmpty { m.tps = PendingTPs(entryOid: 0, isLong: long, prices: [tp], fractions: [1]) }
            managed[coin] = m
            let st = try await execOrders(reqs, grouping: pos == nil ? "normalTpsl" : "na")
            try throwIfRejected(st)
            await refreshAccount()
            await refreshHistory()
        } catch {
            toast(error.localizedDescription, .error)
            notify(.orderProblem, "Order niet geplaatst", error.localizedDescription)
        }
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
        guard let canvas = chartCanvas, let chart = canvas.snapshotImage() else { toast("Geen chart om vast te leggen.", .error); return }
        let banner: CGFloat = 34
        let size = NSSize(width: chart.size.width, height: chart.size.height + banner)
        let img = NSImage(size: size)
        img.lockFocus()
        Palette.bg.setFill()
        NSRect(origin: .zero, size: size).fill()
        chart.draw(in: NSRect(x: 0, y: 0, width: chart.size.width, height: chart.size.height))
        let ch = change24h
        let title = "\(coin)-PERP · \(timeframe.label) · \(Fmt.price(price))  \(ch >= 0 ? "+" : "")\(Fmt.number(ch * 100, decimals: 2))%"
        let when = Date().formatted(date: .abbreviated, time: .shortened)
        (title as NSString).draw(at: NSPoint(x: 14, y: chart.size.height + 9),
                                 withAttributes: [.font: NSFont.systemFont(ofSize: 14, weight: .semibold), .foregroundColor: NSColor.white])
        let right = "Grip · \(when)" as NSString
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
            toast("Screenshot bewaard\(screenshotToClipboard ? " en gekopieerd" : "") · \(file.lastPathComponent)", .success)
        } catch {
            toast("Screenshot niet bewaard: \(error.localizedDescription)", .error)
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
        panel.prompt = "Kies map"
        panel.directoryURL = URL(fileURLWithPath: (screenshotFolder as NSString).expandingTildeInPath)
        if panel.runModal() == .OK, let u = panel.url { screenshotFolder = u.path }
    }
}
#endif
