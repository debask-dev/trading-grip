#if os(macOS)
import AppKit
import SwiftUI
import GripCore

/// Scripted walkthrough used to record the demo video (launch with -GripDemoVideo YES).
/// Chart interactions go through the chart's real mouse handlers; buttons are pointed at and clicked
/// with synthesized events (with a direct fallback so the script never stalls). A transparent overlay
/// window draws the cursor, click ripples and captions.
@MainActor
final class DemoDirector {
    private unowned let state: AppState
    private var overlay: DemoOverlay?
    private var cursor = CGPoint.zero        // screen coordinates
    private var log: [[String: Any]] = []
    private let started = Date()

    init(state: AppState) { self.state = state }

    func run() {
        Task { @MainActor in
            do {
                if UserDefaults.standard.string(forKey: "GripDemoScript") == "full" { try await script() } else { try await featureScript() }
            } catch { note("demo stopped: \(error)") }
            writeLog()
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            NSApp.terminate(nil)
        }
    }

    // MARK: Script

    private func script() async throws {
        // Wait for the chart and live data.
        for _ in 0..<100 where state.candles.isEmpty || state.chartCanvas?.window == nil || state.price <= 0 { try await sleep(0.2) }
        guard let window = state.chartCanvas?.window, let screen = window.screen ?? NSScreen.main else { note("no window"); return }
        window.setFrame(screen.visibleFrame, display: true)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        CGDisplayHideCursor(CGMainDisplayID())
        overlay = DemoOverlay(screen: screen)
        cursor = CGPoint(x: screen.frame.midX, y: screen.frame.midY)
        overlay?.set(cursor: cursor)
        try await sleep(2.5)
        note("ready")

        // 1. Live chart + timeframes
        caption("Grip – native macOS-app voor Hyperliquid · live koersen")
        try await hoverChart(from: 0.25, to: 0.75, price: state.price, seconds: 2.2)
        caption("Timeframes 1m t/m 1w · ⌘1 – ⌘7")
        for tf in [Timeframe.h1, .h4, .m15] {
            try await click(anchor: "tf-\(tf.rawValue)", fallback: { self.state.timeframe = tf }, done: { self.state.timeframe == tf })
            for _ in 0..<40 where state.loadingCandles { try await sleep(0.1) }
            try await sleep(1.1)
        }

        // 2. Trendlines with ⌘-snap
        caption("Trendlijnen tekenen · houd ⌘ ingedrukt = snap op candle en wick")
        try await click(anchor: "tool-trend", fallback: { self.state.tool = .trendline }, done: { self.state.tool == .trendline })
        try await sleep(0.4)
        let vis = state.chartCanvas?.demoVisibleBars ?? 50
        if let canvas = state.chartCanvas, let lowA = canvas.demoExtreme(from: vis * 55 / 100, to: vis * 92 / 100, high: false),
           let lowB = canvas.demoExtreme(from: vis * 8 / 100, to: vis * 40 / 100, high: false),
           let a = canvas.demoCandlePoint(fromEnd: lowA, high: false), let b = canvas.demoCandlePoint(fromEnd: lowB, high: false) {
            try await drawTrendline(from: a, to: b, canvas: canvas)
        }
        try await sleep(0.8)
        try await click(anchor: "tool-trend", fallback: { self.state.tool = .trendline }, done: { self.state.tool == .trendline })
        if let canvas = state.chartCanvas, let hiA = canvas.demoExtreme(from: vis * 55 / 100, to: vis * 92 / 100, high: true),
           let hiB = canvas.demoExtreme(from: vis * 8 / 100, to: vis * 40 / 100, high: true),
           let a = canvas.demoCandlePoint(fromEnd: hiA, high: true), let b = canvas.demoCandlePoint(fromEnd: hiB, high: true) {
            try await drawTrendline(from: a, to: b, canvas: canvas)
        }
        try await sleep(1.2)
        state.tool = .cursor
        state.selectedTrendline = nil

        // 3. Risk
        caption("Kies je risico: maximaal verlies als % van je portfolio")
        try await click(anchor: "risk-0.5", fallback: { self.state.riskPercent = 0.5 }, done: { self.state.riskPercent == 0.5 })
        try await sleep(0.9)
        try await click(anchor: "risk-1.0", fallback: { self.state.riskPercent = 1.0 }, done: { self.state.riskPercent == 1.0 })
        try await sleep(1.2)

        // 4. Ticket: drag entry / stop / target in the chart
        caption("Long: zet entry, stop-loss en take-profit en sleep ze in de chart")
        try await click(anchor: "btn-long", fallback: { self.state.newTicket(long: true) }, done: { self.state.ticket != nil })
        try await sleep(1.0)
        let p = state.price
        try await dragLine(.ticketSL, toPrice: p * 0.9925)
        try await sleep(0.6)
        try await dragLine(.ticketTP, toPrice: p * 1.017)
        try await sleep(0.6)
        caption("Grip rekent direct je positiegrootte en hefboom uit")
        try await dragLine(.ticketEntry, toPrice: p * 0.9985)
        try await sleep(1.4)

        // 5. Place at market (fills immediately in oefenmodus)
        caption("Plaatsen – hier als market order (oefenmodus, live koersen)")
        if let f = DemoAnchors.shared.frames["ticket-type"] {
            try await click(global: CGPoint(x: f.maxX - f.width / 4, y: f.midY), fallback: { self.state.ticket?.isMarket = true }, done: { self.state.ticket?.isMarket == true })
        } else { state.ticket?.isMarket = true }
        try await sleep(1.0)
        try await click(anchor: "btn-place", fallback: { Task { await self.state.placeTicket() } }, done: { self.state.ticket == nil || self.state.busy })
        for _ in 0..<40 where state.position == nil { try await sleep(0.1) }
        try await sleep(1.8)

        // 6. Move TP / SL of the position
        caption("TP en SL van je positie? Gewoon verslepen")
        if let tp = state.coinOrders.first(where: { $0.tpsl == .tp }) { try await dragLine(.order(tp.oid), toPrice: state.price * 1.012) }
        try await sleep(1.0)
        if let sl = state.coinOrders.first(where: { $0.tpsl == .sl }) { try await dragLine(.order(sl.oid), toPrice: state.price * 0.995) }
        try await sleep(1.5)

        // 7. Partial close
        caption("Deels sluiten met één klik")
        let before = abs(state.position?.size ?? 0)
        try await click(anchor: "close-0.25", fallback: { Task { await self.state.closePosition(fraction: 0.25) } },
                        done: { abs(self.state.position?.size ?? 0) < before - 1e-12 })
        try await sleep(2.6)

        caption("Of sleep ✕ naar een prijs: limit close voor een deel")
        if let canvas = state.chartCanvas, let h = canvas.demoCloseHandle {
            let target = canvas.demoPoint(price: state.price * 1.006, xFraction: 0.6)
            try await drag(fromWindow: h, toWindow: CGPoint(x: h.x - 60, y: target.y), canvas: canvas, seconds: 1.6)
        }
        try await sleep(2.4)

        // 8. Privacy
        caption("Privacymodus: bedragen verbergen voor screenshots · ⇧⌘H")
        try await clickToolbar(fromRight: 72) { self.state.hideAmounts = true }
        try await sleep(3.2)
        try await clickToolbar(fromRight: 72) { self.state.hideAmounts = false }
        try await sleep(1.0)

        // 9. Close the rest → trade appears in history
        caption("Rest sluiten – de trade komt in je historie")
        try await click(anchor: "close-1.0", fallback: { Task { await self.state.closePosition(fraction: 1.0) } }, done: { self.state.position == nil })
        for _ in 0..<30 where state.position != nil { try await sleep(0.1) }
        try await sleep(1.8)

        caption("Historie: netto PnL na fees, R-multiple, winrate en meer")
        try await clickTab(1) { self.state.tab = .history }
        try await sleep(4.5)

        caption("Portfolio: winst/verlies en accountwaarde in de tijd")
        try await clickTab(2) { self.state.tab = .portfolio }
        try await sleep(4.5)

        try await clickTab(0) { self.state.tab = .trade }
        try await sleep(1.0)
        caption("Grip · grip op je trades, grip op je risico")
        try await moveCursor(to: CGPoint(x: screen.frame.midX, y: screen.frame.midY + 120), seconds: 1.0)
        try await sleep(3.0)
        caption(nil)
        note("done")
    }

    // MARK: Feature tour (new chart features)

    private func featureScript() async throws {
        for _ in 0..<100 where state.candles.isEmpty || state.chartCanvas?.window == nil || state.price <= 0 { try await sleep(0.2) }
        guard let window = state.chartCanvas?.window, let screen = window.screen ?? NSScreen.main, let canvas = state.chartCanvas else { note("no window"); return }
        window.setFrame(screen.visibleFrame, display: true)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        CGDisplayHideCursor(CGMainDisplayID())
        overlay = DemoOverlay(screen: screen)
        cursor = CGPoint(x: screen.frame.midX, y: screen.frame.midY)
        overlay?.set(cursor: cursor)
        try await sleep(2.0)
        note("ready")

        // 1. OHLC legend
        caption("OHLC-waarden van de candle onder je muis, linksboven")
        try await hoverChart(from: 0.15, to: 0.85, price: state.price, seconds: 4.2)
        try await sleep(0.6)

        // 2. Countdown
        caption("Aftelklok tot de volgende candle, onder de koers")
        let label = screenPoint(window: canvas.demoPriceLabelPoint)
        try await moveCursor(to: CGPoint(x: label.x - 70, y: label.y + 36), seconds: 0.8)
        try await sleep(3.4)

        // 3. Wheel zoom
        caption("Zoomen zoals TradingView: soepel en rond de cursor")
        let zoomAt = screenPoint(window: canvas.demoPoint(price: state.price, xFraction: 0.72))
        try await moveCursor(to: zoomAt, seconds: 0.6) { [weak self] sp in self?.hover(canvas, sp) }
        for _ in 0..<45 {
            if let e = scrollEvent(dy: 7, at: cursor) { canvas.scrollWheel(with: e) }
            try await sleep(1.0 / 60)
        }
        try await sleep(0.7)
        for _ in 0..<80 {
            if let e = scrollEvent(dy: -7, at: cursor) { canvas.scrollWheel(with: e) }
            try await sleep(1.0 / 60)
        }
        try await sleep(0.8)

        // 4. Momentum
        caption("Slepen met momentum: loslaten en de chart glijdt uit")
        let a = screenPoint(window: canvas.demoPoint(price: state.price, xFraction: 0.25))
        try await fling(from: a, to: CGPoint(x: a.x + 280, y: a.y), seconds: 0.22, canvas: canvas)
        try await sleep(2.2)
        let b = screenPoint(window: canvas.demoPoint(price: state.price, xFraction: 0.8))
        try await fling(from: b, to: CGPoint(x: b.x - 300, y: b.y), seconds: 0.22, canvas: canvas)
        try await sleep(2.2)

        // 5. Time axis
        caption("Tijd-as slepen = in- en uitzoomen · dubbelklik = terug naar standaard")
        try await drag(fromWindow: canvas.demoTimeAxisPoint(xFraction: 0.6), toWindow: canvas.demoTimeAxisPoint(xFraction: 0.3), canvas: canvas, seconds: 1.2)
        try await sleep(0.8)
        try await drag(fromWindow: canvas.demoTimeAxisPoint(xFraction: 0.3), toWindow: canvas.demoTimeAxisPoint(xFraction: 0.75), canvas: canvas, seconds: 1.2)
        try await sleep(0.6)
        let reset = screenPoint(window: canvas.demoTimeAxisPoint(xFraction: 0.5))
        try await moveCursor(to: reset, seconds: 0.5)
        overlay?.ripple(at: reset)
        if let d = event(.leftMouseDown, screen: reset, clicks: 2) { canvas.mouseDown(with: d) }
        if let u = event(.leftMouseUp, screen: reset, clicks: 2) { canvas.mouseUp(with: u) }
        try await sleep(1.4)

        // 6. Measure
        caption("⇧ + klik: meten · % omhoog of omlaag, aantal candles en tijd")
        let vis = canvas.demoVisibleBars
        if let lo = canvas.demoExtreme(from: vis * 45 / 100, to: vis * 85 / 100, high: false),
           let hi = canvas.demoExtreme(from: 2, to: max(3, lo - 3), high: true),
           let pLo = canvas.demoCandlePoint(fromEnd: lo, high: false), let pHi = canvas.demoCandlePoint(fromEnd: hi, high: true) {
            let s0 = screenPoint(window: pLo), s1 = screenPoint(window: pHi)
            try await moveCursor(to: s0, seconds: 0.8) { [weak self] sp in self?.hover(canvas, sp) }
            overlay?.keycap = "⇧"
            try await sleep(0.5)
            overlay?.ripple(at: s0)
            if let d = event(.leftMouseDown, screen: s0, flags: .shift) { canvas.mouseDown(with: d) }
            if let u = event(.leftMouseUp, screen: s0, flags: .shift) { canvas.mouseUp(with: u) }
            overlay?.keycap = nil
            try await moveCursor(to: s1, seconds: 1.8) { [weak self] sp in self?.hover(canvas, sp) }
            overlay?.ripple(at: s1)
            if let d = event(.leftMouseDown, screen: s1) { canvas.mouseDown(with: d) }
            if let u = event(.leftMouseUp, screen: s1) { canvas.mouseUp(with: u) }
            try await sleep(3.6)
            try await moveCursor(to: CGPoint(x: s1.x - 40, y: s1.y - 80), seconds: 0.5)
            overlay?.ripple(at: cursor)
            if let d = event(.leftMouseDown, screen: cursor) { canvas.mouseDown(with: d) }
            if let u = event(.leftMouseUp, screen: cursor) { canvas.mouseUp(with: u) }
        } else { note("measure targets missing") }
        try await sleep(0.8)

        // 7. Magnet + trendline + toolbar
        caption("Magneet aan: lijnen snappen vanzelf op candle en wick")
        try await click(anchor: "tool-magnet", fallback: { self.state.magnet = true }, done: { self.state.magnet })
        try await sleep(0.5)
        try await click(anchor: "tool-trend", fallback: { self.state.tool = .trendline }, done: { self.state.tool == .trendline })
        try await sleep(0.4)
        let vis2 = canvas.demoVisibleBars
        if let la = canvas.demoExtreme(from: vis2 * 55 / 100, to: vis2 * 92 / 100, high: false),
           let lb = canvas.demoExtreme(from: vis2 * 10 / 100, to: vis2 * 40 / 100, high: false),
           let pa = canvas.demoCandlePoint(fromEnd: la, high: false), let pb = canvas.demoCandlePoint(fromEnd: lb, high: false) {
            try await drag(fromWindow: CGPoint(x: pa.x + 3, y: pa.y + 9), toWindow: CGPoint(x: pb.x - 3, y: pb.y + 9), canvas: canvas, seconds: 1.4)
        }
        note("lines: \(state.trendlines.count)")
        try await sleep(1.0)

        caption("Lijn aanpassen: kleur, dikte, stijl en verlengen de toekomst in")
        try await click(anchor: "lt-#FFB547", fallback: { self.state.styleSelectedLine { $0.color = "#FFB547" } }, done: { self.state.selectedLine?.color == "#FFB547" })
        try await sleep(0.6)
        try await click(anchor: "lt-width-3", fallback: { self.state.styleSelectedLine { $0.width = 3 } }, done: { self.state.selectedLine?.width == 3 })
        try await sleep(0.6)
        try await click(anchor: "lt-dash-dashed", fallback: { self.state.styleSelectedLine { $0.dash = .dashed } }, done: { self.state.selectedLine?.dash == .dashed })
        try await sleep(0.6)
        try await click(anchor: "lt-extend-right", fallback: { self.state.styleSelectedLine { $0.extendRight = true } }, done: { self.state.selectedLine?.extendRight == true })
        try await sleep(2.4)
        state.selectedTrendline = nil
        state.magnet = false

        // 8. Candle styles
        caption("Candle-stijl naar keuze: kleuren, wicks, randen, holle candles")
        try await moveCursor(to: CGPoint(x: screen.frame.midX, y: screen.frame.midY + 140), seconds: 0.6)
        for style in [ChartStyle.hollow, .classic, .blueOrange, .monochrome] {
            state.chartStyle = style
            try await sleep(1.8)
        }
        state.chartStyle = .grip
        try await sleep(1.0)

        caption("Grip · grip op je trades, grip op je risico")
        try await sleep(3.0)
        caption(nil)
        note("done")
    }

    private func hover(_ canvas: ChartCanvas, _ sp: CGPoint) {
        if let e = event(.mouseMoved, screen: sp) { canvas.mouseMoved(with: e) }
    }

    /// A quick linear drag released while still moving, so the chart keeps gliding.
    private func fling(from a: CGPoint, to b: CGPoint, seconds: Double, canvas: ChartCanvas) async throws {
        try await moveCursor(to: a, seconds: 0.5) { [weak self] sp in self?.hover(canvas, sp) }
        try await sleep(0.2)
        overlay?.pressed = true
        if let d = event(.leftMouseDown, screen: a) { canvas.mouseDown(with: d) }
        let steps = max(6, Int(seconds * 60))
        for i in 1...steps {
            let k = CGFloat(i) / CGFloat(steps)
            cursor = CGPoint(x: a.x + (b.x - a.x) * k, y: a.y + (b.y - a.y) * k)
            overlay?.set(cursor: cursor)
            if let e = event(.leftMouseDragged, screen: cursor) { canvas.mouseDragged(with: e) }
            try await sleep(seconds / Double(steps))
        }
        if let u = event(.leftMouseUp, screen: b) { canvas.mouseUp(with: u) }
        overlay?.pressed = false
    }

    // MARK: Building blocks

    private func sleep(_ s: Double) async throws { try await Task.sleep(nanoseconds: UInt64(s * 1_000_000_000)) }

    private func caption(_ text: String?) {
        overlay?.caption = text
        if let text { note("caption: \(text)") }
    }

    private func note(_ s: String) {
        log.append(["t": Date().timeIntervalSince(started), "epoch": Date().timeIntervalSince1970, "event": s])
        writeLog()
    }

    private func writeLog() {
        let url = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("grip-demo-log.json")
        if let data = try? JSONSerialization.data(withJSONObject: log, options: [.prettyPrinted]) {
            try? data.write(to: url)
            try? data.write(to: URL(fileURLWithPath: "/tmp/grip-demo-log.json"))
        }
    }

    private var window: NSWindow? { state.chartCanvas?.window ?? NSApp.windows.first { $0.isVisible && !($0 is DemoOverlayWindow) } }

    private func screenPoint(window p: CGPoint) -> CGPoint { window?.convertPoint(toScreen: p) ?? p }

    /// SwiftUI `.global` frames are in the window's content coordinates (top-left origin).
    private func screenPoint(global p: CGPoint) -> CGPoint? {
        guard let w = window, let cv = w.contentView else { return nil }
        let local = cv.isFlipped ? p : CGPoint(x: p.x, y: cv.bounds.height - p.y)
        return w.convertPoint(toScreen: cv.convert(local, to: nil))
    }

    private func ease(_ t: Double) -> Double { t < 0.5 ? 4 * t * t * t : 1 - pow(-2 * t + 2, 3) / 2 }

    private func moveCursor(to target: CGPoint, seconds: Double, onStep: ((CGPoint) -> Void)? = nil) async throws {
        let start = cursor
        let steps = max(8, Int(seconds * 60))
        for i in 1...steps {
            let k = CGFloat(ease(Double(i) / Double(steps)))
            cursor = CGPoint(x: start.x + (target.x - start.x) * k, y: start.y + (target.y - start.y) * k)
            overlay?.set(cursor: cursor)
            onStep?(cursor)
            try await sleep(seconds / Double(steps))
        }
    }

    private func event(_ type: NSEvent.EventType, screen sp: CGPoint, flags: NSEvent.ModifierFlags = [], clicks: Int = 1) -> NSEvent? {
        guard let w = window else { return nil }
        return NSEvent.mouseEvent(with: type, location: w.convertPoint(fromScreen: sp), modifierFlags: flags,
                                  timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: w.windowNumber,
                                  context: nil, eventNumber: 0, clickCount: clicks, pressure: type == .leftMouseUp ? 0 : 1)
    }

    /// A pixel-precise scroll event (like a trackpad) at a screen point.
    private func scrollEvent(dy: Int32, dx: Int32 = 0, at sp: CGPoint) -> NSEvent? {
        guard let cg = CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 2, wheel1: dy, wheel2: dx, wheel3: 0) else { return nil }
        let mainHeight = NSScreen.screens.first?.frame.height ?? 0
        cg.location = CGPoint(x: sp.x, y: mainHeight - sp.y)
        return NSEvent(cgEvent: cg)
    }

    private func flagsEvent(_ flags: NSEvent.ModifierFlags) -> NSEvent? {
        guard let w = window else { return nil }
        return NSEvent.keyEvent(with: .flagsChanged, location: w.convertPoint(fromScreen: cursor), modifierFlags: flags,
                                timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: w.windowNumber, context: nil,
                                characters: "", charactersIgnoringModifiers: "", isARepeat: false, keyCode: 55)
    }

    /// Clicks a SwiftUI control with real mouse events; if that didn't take effect, performs the action directly.
    private func click(anchor: String, fallback: @escaping () -> Void, done: @escaping () -> Bool) async throws {
        guard let f = DemoAnchors.shared.frames[anchor] else { note("anchor missing: \(anchor)"); fallback(); return }
        try await click(global: CGPoint(x: f.midX, y: f.midY), fallback: fallback, done: done)
    }

    private func click(global p: CGPoint, fallback: @escaping () -> Void, done: @escaping () -> Bool) async throws {
        guard let sp = screenPoint(global: p) else { fallback(); return }
        try await clickScreen(sp, fallback: fallback, done: done)
    }

    private func clickScreen(_ sp: CGPoint, fallback: @escaping () -> Void, done: @escaping () -> Bool) async throws {
        try await moveCursor(to: sp, seconds: 0.55)
        try await sleep(0.12)
        overlay?.ripple(at: sp)
        overlay?.pressed = true
        // Queue the mouse-up first: native controls run their own tracking loop on mouse-down
        // and would otherwise wait forever for the release.
        if let u = event(.leftMouseUp, screen: sp) { NSApp.postEvent(u, atStart: false) }
        if let d = event(.leftMouseDown, screen: sp) { window?.sendEvent(d) }
        try await sleep(0.08)
        overlay?.pressed = false
        try await sleep(0.25)
        if !done() { fallback(); note("fallback used") } else { note("clicked") }
    }

    private func clickToolbar(fromRight dx: CGFloat, action: @escaping () -> Void) async throws {
        guard let w = window else { action(); return }
        let toolbarH = w.frame.height - w.contentLayoutRect.height
        let sp = CGPoint(x: w.frame.maxX - dx, y: w.frame.maxY - toolbarH / 2)
        try await moveCursor(to: sp, seconds: 0.6)
        overlay?.ripple(at: sp)
        action()
        try await sleep(0.3)
    }

    private func clickTab(_ index: Int, action: @escaping () -> Void) async throws {
        guard let w = window else { action(); return }
        let toolbarH = w.frame.height - w.contentLayoutRect.height
        let sp = CGPoint(x: w.frame.midX + CGFloat(index - 1) * 90, y: w.frame.maxY - toolbarH / 2)
        try await moveCursor(to: sp, seconds: 0.6)
        overlay?.ripple(at: sp)
        action()
        try await sleep(0.3)
    }

    private func hoverChart(from a: CGFloat, to b: CGFloat, price: Double, seconds: Double) async throws {
        guard let canvas = state.chartCanvas else { return }
        let p0 = screenPoint(window: canvas.demoPoint(price: price, xFraction: a))
        try await moveCursor(to: p0, seconds: 0.8)
        let p1 = screenPoint(window: canvas.demoPoint(price: price * 1.002, xFraction: b))
        try await moveCursor(to: p1, seconds: seconds) { [weak self] sp in
            guard let self, let e = self.event(.mouseMoved, screen: sp) else { return }
            canvas.mouseMoved(with: e)
        }
    }

    private func drawTrendline(from a: CGPoint, to b: CGPoint, canvas: ChartCanvas) async throws {
        // Aim slightly off the wick, then let ⌘-snap pull it onto the exact low/high.
        let sa = screenPoint(window: CGPoint(x: a.x + 3, y: a.y + 9))
        let sb = screenPoint(window: CGPoint(x: b.x - 3, y: b.y + 9))
        try await moveCursor(to: sa, seconds: 0.7) { [weak self] sp in
            guard let self, let e = self.event(.mouseMoved, screen: sp) else { return }
            canvas.mouseMoved(with: e)
        }
        overlay?.keycap = "⌘"
        if let f = flagsEvent(.command) { canvas.flagsChanged(with: f) }
        try await sleep(0.5)
        let countBefore = state.trendlines.count
        let snappedA = canvas.demoChartPoint(window: CGPoint(x: a.x + 3, y: a.y + 9), snap: true)
        overlay?.pressed = true
        if let d = event(.leftMouseDown, screen: sa, flags: .command) { canvas.mouseDown(with: d) } else { note("no mouseDown event") }
        note("after mouseDown: \(canvas.demoDebug)")
        try await moveCursor(to: sb, seconds: 1.3) { [weak self] sp in
            guard let self, let e = self.event(.leftMouseDragged, screen: sp, flags: .command) else { return }
            canvas.mouseDragged(with: e)
        }
        try await sleep(0.35)
        note("before mouseUp: \(canvas.demoDebug)")
        if let u = event(.leftMouseUp, screen: sb, flags: .command) { canvas.mouseUp(with: u) }
        overlay?.pressed = false
        if let f = flagsEvent([]) { canvas.flagsChanged(with: f) }
        overlay?.keycap = nil
        if state.trendlines.count == countBefore {
            let snappedB = canvas.demoChartPoint(window: CGPoint(x: b.x - 3, y: b.y + 9), snap: true)
            state.addTrendline(snappedA, snappedB)
            state.tool = .cursor
            note("trendline fallback used")
        }
        note("trendline drawn, total \(state.trendlines.count)")
    }

    private func dragLine(_ id: LineID, toPrice price: Double) async throws {
        guard let canvas = state.chartCanvas else { return }
        guard let from = canvas.demoLinePoint(id) else { note("line missing: \(id)"); return }
        let to = canvas.demoPoint(price: price, xFraction: 0.5)
        try await drag(fromWindow: from, toWindow: CGPoint(x: from.x, y: to.y), canvas: canvas, seconds: 1.2)
    }

    private func drag(fromWindow a: CGPoint, toWindow b: CGPoint, canvas: ChartCanvas, seconds: Double) async throws {
        let sa = screenPoint(window: a), sb = screenPoint(window: b)
        try await moveCursor(to: sa, seconds: 0.6) { [weak self] sp in
            guard let self, let e = self.event(.mouseMoved, screen: sp) else { return }
            canvas.mouseMoved(with: e)
        }
        try await sleep(0.2)
        overlay?.pressed = true
        if let d = event(.leftMouseDown, screen: sa) { canvas.mouseDown(with: d) }
        try await moveCursor(to: sb, seconds: seconds) { [weak self] sp in
            guard let self, let e = self.event(.leftMouseDragged, screen: sp) else { return }
            canvas.mouseDragged(with: e)
        }
        try await sleep(0.25)
        if let u = event(.leftMouseUp, screen: sb) { canvas.mouseUp(with: u) }
        overlay?.pressed = false
    }
}

// MARK: - Overlay (cursor, ripples, captions)

final class DemoOverlayWindow: NSWindow {}

@MainActor
final class DemoOverlay {
    private let window: DemoOverlayWindow
    private let view: DemoOverlayView

    var caption: String? { didSet { view.caption = caption; view.needsDisplay = true } }
    var keycap: String? { didSet { view.keycap = keycap; view.needsDisplay = true } }
    var pressed = false { didSet { view.pressed = pressed; view.needsDisplay = true } }

    init(screen: NSScreen) {
        window = DemoOverlayWindow(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.level = .screenSaver
        window.ignoresMouseEvents = true
        window.hasShadow = false
        window.collectionBehavior = [.canJoinAllSpaces, .stationary]
        view = DemoOverlayView(frame: NSRect(origin: .zero, size: screen.frame.size))
        view.screenOrigin = screen.frame.origin
        window.contentView = view
        window.orderFrontRegardless()
    }

    func set(cursor: CGPoint) {
        view.cursor = cursor
        view.needsDisplay = true
    }

    func ripple(at p: CGPoint) {
        view.ripples.append((p, Date()))
        view.animate()
    }
}

final class DemoOverlayView: NSView {
    var screenOrigin = CGPoint.zero
    var cursor = CGPoint.zero
    var pressed = false
    var caption: String?
    var keycap: String?
    var ripples: [(CGPoint, Date)] = []
    private var timer: Timer?

    func animate() {
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60, repeats: true) { [weak self] t in
            MainActor.assumeIsolated {
                guard let self else { t.invalidate(); return }
                self.ripples.removeAll { Date().timeIntervalSince($0.1) > 0.6 }
                self.needsDisplay = true
                if self.ripples.isEmpty { t.invalidate(); self.timer = nil }
            }
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.clear.set()
        bounds.fill()

        for (p, start) in ripples {
            let age = CGFloat(Date().timeIntervalSince(start) / 0.6)
            let r = 10 + 26 * age
            let lp = CGPoint(x: p.x - screenOrigin.x, y: p.y - screenOrigin.y)
            let path = NSBezierPath(ovalIn: NSRect(x: lp.x - r, y: lp.y - r, width: 2 * r, height: 2 * r))
            NSColor.white.withAlphaComponent(0.85 * (1 - age)).setStroke()
            path.lineWidth = 2.5
            path.stroke()
        }

        if let caption {
            let font = NSFont.systemFont(ofSize: 20, weight: .semibold)
            let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.white]
            let size = (caption as NSString).size(withAttributes: attrs)
            let box = NSRect(x: bounds.midX - size.width / 2 - 22, y: 92, width: size.width + 44, height: size.height + 22)
            NSColor(srgbRed: 0.07, green: 0.08, blue: 0.11, alpha: 0.92).setFill()
            NSBezierPath(roundedRect: box, xRadius: 14, yRadius: 14).fill()
            NSColor(srgbRed: 0.49, green: 0.42, blue: 1, alpha: 0.9).setStroke()
            let border = NSBezierPath(roundedRect: box.insetBy(dx: 0.5, dy: 0.5), xRadius: 14, yRadius: 14)
            border.lineWidth = 1.5
            border.stroke()
            (caption as NSString).draw(at: CGPoint(x: box.minX + 22, y: box.minY + 11), withAttributes: attrs)
        }

        let c = CGPoint(x: cursor.x - screenOrigin.x, y: cursor.y - screenOrigin.y)

        if let keycap {
            let font = NSFont.systemFont(ofSize: 18, weight: .bold)
            let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.black]
            let box = NSRect(x: c.x + 22, y: c.y - 52, width: 36, height: 32)
            NSColor.white.setFill()
            NSBezierPath(roundedRect: box, xRadius: 7, yRadius: 7).fill()
            let s = (keycap as NSString).size(withAttributes: attrs)
            (keycap as NSString).draw(at: CGPoint(x: box.midX - s.width / 2, y: box.midY - s.height / 2), withAttributes: attrs)
        }

        if pressed {
            NSColor(srgbRed: 1, green: 0.71, blue: 0.28, alpha: 0.35).setFill()
            NSBezierPath(ovalIn: NSRect(x: c.x - 13, y: c.y - 13, width: 26, height: 26)).fill()
        }
        // Arrow cursor (tip at c; view coordinates are bottom-left based)
        let arrow = NSBezierPath()
        arrow.move(to: c)
        arrow.line(to: CGPoint(x: c.x, y: c.y - 22))
        arrow.line(to: CGPoint(x: c.x + 5.5, y: c.y - 17))
        arrow.line(to: CGPoint(x: c.x + 9.5, y: c.y - 26))
        arrow.line(to: CGPoint(x: c.x + 13, y: c.y - 24.5))
        arrow.line(to: CGPoint(x: c.x + 9, y: c.y - 15.5))
        arrow.line(to: CGPoint(x: c.x + 16, y: c.y - 15.5))
        arrow.close()
        NSColor.white.setFill()
        arrow.fill()
        NSColor.black.setStroke()
        arrow.lineWidth = 1.4
        arrow.stroke()
    }
}
#endif
