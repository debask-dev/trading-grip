#if os(macOS)
import SwiftUI
import AppKit
import GripCore
import UniformTypeIdentifiers

// MARK: - Take-profit ladder, break-even, chart ✕ buttons, price menu

extension AppState {
    /// Places the ladder as reduce-only GTC limit orders; the last level gets whatever is left.
    func placeTakeProfits(coin c: String, _ p: PendingTPs) async {
        guard let pos = account.position(for: c), let a = assets.first(where: { $0.name == c }) else { return }
        let total = abs(pos.size)
        var left = total
        var reqs: [OrderRequest] = []
        for (i, px) in p.prices.enumerated() {
            let isLast = i == p.prices.count - 1
            var sz = isLast ? left : HLFormat.roundSize(total * p.fractions[i], szDecimals: a.szDecimals, down: true)
            sz = min(sz, left)
            guard sz > 0 else { continue }
            left -= sz
            reqs.append(OrderRequest(asset: a, isBuy: !pos.isLong, size: HLFormat.roundSize(sz, szDecimals: a.szDecimals),
                                     limitPx: HLFormat.roundPrice(px, szDecimals: a.szDecimals), reduceOnly: true, kind: .limit(tif: "Gtc")))
        }
        guard !reqs.isEmpty else { return }
        do {
            let st = try await execOrders(reqs)
            for s in st { if case .resting(let oid) = s { orderKinds[oid] = .takeProfit } }
            pendingTPs[c] = nil
            toast("\(reqs.count) take-profit\(reqs.count > 1 ? "s" : "") geplaatst", .success)
        } catch {
            toast("Take-profits niet geplaatst: \(error.localizedDescription)", .error)
            notify(.orderProblem, "Take-profits niet geplaatst", error.localizedDescription)
        }
        await refreshAccount()
    }

    /// Called after every account refresh: a limit entry with a waiting TP ladder got filled → place it.
    func checkPendingTPs() async {
        for (c, p) in pendingTPs {
            let stillResting = account.openOrders.contains { $0.oid == p.entryOid }
            if let pos = account.position(for: c), pos.isLong == p.isLong {
                // Wait until the entry is completely filled, so the ladder matches the full size.
                if !stillResting { await placeTakeProfits(coin: c, p) }
            } else if !stillResting {
                pendingTPs[c] = nil       // cancelled without a fill
            }
        }
    }

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
        case .ticketEntry: ticket = nil
        case .ticketSL, .ticketLiq: break
        case .ticketTP(let i): removeTicketTP(i)
        case .order(let oid):
            if let o = account.openOrders.first(where: { $0.oid == oid }), !o.reduceOnly, !o.isTrigger, pendingTPs[o.coin]?.entryOid == oid {
                pendingTPs[o.coin] = nil
            }
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
            items.append(("Entry hier", { [weak self] in self?.ticket?.entry = px; self?.ticket?.isMarket = false }))
            let long = t.stopLoss < t.entry
            if long ? px < t.entry : px > t.entry {
                items.append(("Stop-loss hier", { [weak self] in self?.ticket?.stopLoss = px }))
            } else {
                items.append(("Take-profit hier", { [weak self] in self?.addTicketTP(at: px) }))
            }
            items.append(("-", {}))
        }
        if p > 0 {
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
            try await execLeverage(a, isCross: useCrossMargin && !a.onlyIsolated, leverage: min(max(quickLev, 1), a.maxLeverage))
            let px = HLFormat.slippagePrice(price, isBuy: long, slippage: slippagePercent / 100, szDecimals: a.szDecimals)
            let st = try await execOrders([
                OrderRequest(asset: a, isBuy: long, size: size, limitPx: px, reduceOnly: false, kind: .limit(tif: "Ioc")),
                OrderRequest(asset: a, isBuy: !long, size: size, limitPx: sl, reduceOnly: true, kind: .trigger(triggerPx: sl, isMarket: true, tpsl: .sl)),
            ], grouping: "normalTpsl")
            if case .filled? = st.first {
                await refreshAccount()
                await placeTakeProfits(coin: coin, PendingTPs(entryOid: 0, isLong: long, prices: [tp], fractions: [1]))
            }
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
