#if os(macOS)
import AppKit
import QuartzCore
import GripCore

/// Custom-drawn candlestick chart with draggable order lines, a drag-to-close handle, trendlines and a measure tool.
///
/// Mouse:   drag chart = pan (with momentum) · drag price axis = scale price · drag time axis = zoom time
///          double-click an axis = reset · "A" button = auto-scale price
///          scroll vertical / pinch = zoom (max 10% per step, anchored under the cursor) · scroll horizontal = pan
/// Lines:   drag any order/TP/SL line · drag the ✕ on the position line to place a partial close
/// Drawing: trendline tool → click-drag (or click, click). Snap to candle open/high/low/close with the magnet,
///          or temporarily by holding ⌘. Click a line to select it, drag its ends or body, ⌫ to delete.
/// Measure: ⇧ + click, move, click (or ⇧ + drag). Esc or a click clears it.
final class ChartCanvas: NSView {
    // MARK: Inputs
    var candles: [Candle] = [] { didSet { if pendingFocus != nil, oldValue.count != candles.count { applyFocusIfPossible() } } }
    var timeframe: Timeframe = .m15
    var coin = ""
    var lastPrice: Double = 0
    var lines: [ChartLine] = []
    var trendlines: [Trendline] = []
    var selectedTrendline: UUID?
    var tool: ChartTool = .cursor { didSet { if tool != .trendline { pendingTrendStart = nil; trendDraft = nil } } }
    var hasPosition = false
    var isLoading = false
    var magnet = false
    var style: ChartStyle = .grip { didSet { if oldValue != style { colorCache = [:] } } }
    var newLineAppearance = LineAppearance()
    var markers: [ChartMarker] = []
    var tradeLinks: [ChartTradeLink] = []
    var highlightTradeID: String?
    var focus: ChartFocus? { didSet { if focus?.token != oldValue?.token { pendingFocus = focus; applyFocusIfPossible() } } }
    private var pendingFocus: ChartFocus?
    private var hoveredMarker: String?
    var resetKey: String = "" { didSet { if oldValue != resetKey { resetView() } } }

    // MARK: Callbacks
    var labelFor: (@MainActor (LineID, Double) -> String)?
    var closeLabelFor: (@MainActor (Double) -> String)?
    var onLineDrag: (@MainActor (LineID, Double, Bool) -> Void)?
    var onCloseDrag: (@MainActor (Double) -> Void)?
    var onCancelOrder: (@MainActor (Int64) -> Void)?
    var onTrendlineCreate: (@MainActor (ChartPoint, ChartPoint) -> Void)?
    var onTrendlineUpdate: (@MainActor (Trendline) -> Void)?
    var onTrendlineSelect: (@MainActor (UUID?) -> Void)?
    var onTrendlineDelete: (@MainActor (UUID) -> Void)?
    var onToolFinished: (@MainActor () -> Void)?
    var onHorizontalCreate: (@MainActor (ChartPoint) -> Void)?
    var onTimeframeTyped: (@MainActor (Timeframe) -> Void)?

    // MARK: Layout
    private let axisWidth: CGFloat = 78
    private let timeHeight: CGFloat = 26
    private var plot: NSRect { NSRect(x: 0, y: 0, width: max(10, bounds.width - axisWidth), height: max(10, bounds.height - timeHeight)) }
    private var autoButtonRect: NSRect { NSRect(x: plot.maxX + (axisWidth - 26) / 2, y: plot.maxY + 3, width: 26, height: timeHeight - 6) }
    private var pixelRatio: CGFloat { window?.backingScaleFactor ?? 2 }

    // MARK: Viewport
    private var vp = ChartViewport()
    private var autoScale = true
    private var manualRange: (lo: Double, hi: Double) = (0, 1)
    private var range: (lo: Double, hi: Double) = (0, 1)
    private var kinetic = KineticScroll()
    private var clockTimer: Timer?

    // Display-synced animation (momentum, smooth mouse-wheel zoom/pan, soft price auto-scale)
    private var link: CADisplayLink?
    private var lastFrameTime: CFTimeInterval = 0
    private var lastDrawTime: CFTimeInterval = 0
    private var targetRange: (lo: Double, hi: Double) = (0, 1)
    private var shownRange: (lo: Double, hi: Double)?
    private var rangeAnimating = false
    private var fling: (speed: Double, startOffset: Double, began: CFTimeInterval, duration: Double)?
    private var zoomTarget: (spacing: Double, anchorX: Double, anchorIndex: Double)?
    private var panRemaining: Double = 0
    private var typed = ""
    private var typedClear: Timer?

    // MARK: Interaction
    private enum Hover: Equatable {
        case line(LineID), closeHandle, trendline(UUID), endpoint(UUID, Bool), priceAxis, timeAxis, autoButton
    }
    private enum Drag {
        case none
        case pan(startX: CGFloat, startOffset: Double, startY: CGFloat, startRange: (lo: Double, hi: Double))
        case priceAxis(startY: CGFloat, startRange: (lo: Double, hi: Double))
        case timeAxis(startX: CGFloat, startSpacing: Double)
        case line(LineID)
        case close
        case trendNew(ChartPoint)
        case endpoint(UUID, isA: Bool)
        case trendMove(Trendline, anchor: ChartPoint)
        case measure(ChartPoint, startScreen: CGPoint)
    }
    private enum Measure {
        case none
        case active(ChartPoint)                 // following the mouse
        case fixed(ChartPoint, ChartPoint)
    }
    private var drag: Drag = .none
    private var measure: Measure = .none
    private var dragPrice: Double?
    private var closeGhost: Double?
    private var mouse: CGPoint?
    private var hover: Hover?
    private var commandDown = false
    private var pendingTrendStart: ChartPoint?
    private var trendDraft: ChartPoint?
    private var snapMarker: ChartPoint?
    private var labelRects: [LineID: NSRect] = [:]
    private var closeHandleRect: NSRect?
    private var trackingArea: NSTrackingArea?
    private var colorCache: [String: NSColor] = [:]

    /// Snapping is on when the magnet is on, or temporarily while holding ⌘ (⌘ inverts the magnet).
    private var snapActive: Bool { magnet != commandDown }

    private var draftStart: ChartPoint? {
        if let p = pendingTrendStart { return p }
        if case .trendNew(let s) = drag { return s }
        return nil
    }

    private var isDraggingClose: Bool {
        if case .close = drag { return true }
        return false
    }

    private func isDraggingLine(_ id: LineID) -> Bool {
        if case .line(let d) = drag { return d == id }
        return false
    }

    private func isHovering(trendline id: UUID) -> Bool {
        switch hover {
        case .trendline(let h)?: return h == id
        case .endpoint(let h, _)?: return h == id
        default: return false
        }
    }

    private let timeFormatter: DateFormatter = { let f = DateFormatter(); f.locale = Locale(identifier: "nl_NL"); return f }()

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layerContentsRedrawPolicy = .onSetNeedsDisplay
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        wantsLayer = true
        layerContentsRedrawPolicy = .onSetNeedsDisplay
    }

    override var isOpaque: Bool { true }
    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        clockTimer?.invalidate()
        clockTimer = nil
        guard window != nil else { return }
        // Redraw once a second for the candle countdown.
        clockTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.needsDisplay = true }
        }
        // Take keyboard focus so shortcuts like typing "15⏎" work right away.
        DispatchQueue.main.async { [weak self] in
            guard let self, let w = self.window else { return }
            if w.firstResponder == nil || w.firstResponder === w { w.makeFirstResponder(self) }
        }
    }

    func resetView() {
        stopKinetic()
        zoomTarget = nil
        panRemaining = 0
        shownRange = nil
        vp.reset()
        autoScale = true
        drag = .none
        measure = .none
        pendingTrendStart = nil
        trendDraft = nil
        needsDisplay = true
    }

    // MARK: Coordinates

    private func syncViewport() {
        vp.width = Double(plot.width)
        vp.barCount = candles.count
        vp.clamp()
    }

    private var spacing: CGFloat { CGFloat(vp.barSpacing) }

    private func x(index i: Double) -> CGFloat { plot.minX + CGFloat(vp.x(index: i)) }

    private func index(x: CGFloat) -> Double { vp.index(x: Double(x - plot.minX)) }

    private func index(time t: Int64) -> Double {
        guard let first = candles.first, let last = candles.last else { return 0 }
        let tf = Double(timeframe.milliseconds)
        if t <= first.time { return Double(t - first.time) / tf }
        if t >= last.time { return Double(candles.count - 1) + Double(t - last.time) / tf }
        var lo = 0, hi = candles.count - 1
        while hi - lo > 1 {
            let mid = (lo + hi) / 2
            if candles[mid].time <= t { lo = mid } else { hi = mid }
        }
        let span = Double(candles[hi].time - candles[lo].time)
        return Double(lo) + (span > 0 ? Double(t - candles[lo].time) / span : 0)
    }

    private func time(index i: Double) -> Int64 {
        guard let first = candles.first, let last = candles.last else { return 0 }
        let tf = Double(timeframe.milliseconds)
        let n = Double(candles.count - 1)
        if i <= 0 { return first.time + Int64(i * tf) }
        if i >= n { return last.time + Int64((i - n) * tf) }
        let lo = Int(i.rounded(.down))
        let frac = i - Double(lo)
        return candles[lo].time + Int64(frac * Double(candles[lo + 1].time - candles[lo].time))
    }

    private func y(_ p: Double) -> CGFloat {
        let r = range
        let h = plot.height - 20
        return plot.minY + 10 + CGFloat((r.hi - p) / max(r.hi - r.lo, 1e-12)) * h
    }

    private func price(y yy: CGFloat) -> Double {
        let r = range
        let h = plot.height - 20
        return r.hi - Double((yy - plot.minY - 10) / h) * (r.hi - r.lo)
    }

    private func visibleIndices() -> ClosedRange<Int>? { vp.visibleRange }

    /// Computes the auto-scale target. While auto-scaling, `draw` eases the shown range towards it.
    private func computeRange() {
        syncViewport()
        if !autoScale { range = manualRange; shownRange = manualRange; return }
        targetRange = autoRange()
        if shownRange == nil { shownRange = targetRange; range = targetRange }
    }

    private func autoRange() -> (lo: Double, hi: Double) {
        var lo = Double.greatestFiniteMagnitude, hi = -Double.greatestFiniteMagnitude
        if let vis = visibleIndices() {
            for i in vis { lo = min(lo, candles[i].low); hi = max(hi, candles[i].high) }
        }
        if lo > hi {
            let p = lastPrice > 0 ? lastPrice : 1
            lo = p * 0.99; hi = p * 1.01
        }
        if hi - lo < hi * 0.0005 { let m = (hi + lo) / 2; lo = m * 0.9995; hi = m * 1.0005 }
        let pad = (hi - lo) * 0.08
        return (lo - pad, hi + pad)
    }

    private func easeRange() {
        guard autoScale, var sr = shownRange else { return }
        let now = CACurrentMediaTime()
        let dt = min(0.05, max(0.001, now - lastDrawTime))
        lastDrawTime = now
        let a = 1 - exp(-dt / 0.09)
        sr.lo += (targetRange.lo - sr.lo) * a
        sr.hi += (targetRange.hi - sr.hi) * a
        let eps = (targetRange.hi - targetRange.lo) * 0.0004
        if abs(sr.lo - targetRange.lo) < eps && abs(sr.hi - targetRange.hi) < eps { sr = targetRange; rangeAnimating = false }
        else { rangeAnimating = true; startAnimating() }
        shownRange = sr
        range = sr
    }

    private func chartPoint(at p: CGPoint, snap: Bool) -> ChartPoint {
        let t = time(index: index(x: p.x))
        let pr = price(y: p.y)
        if snap, let s = Snap.snap(time: t, price: pr, candles: candles, timeframe: timeframe) { return s }
        return ChartPoint(time: t, price: pr)
    }

    private func screen(_ cp: ChartPoint) -> CGPoint { CGPoint(x: x(index: index(time: cp.time)), y: y(cp.price)) }

    private func align(_ v: CGFloat) -> CGFloat { (v * pixelRatio).rounded() / pixelRatio }

    private func color(_ hex: String) -> NSColor {
        if let c = colorCache[hex] { return c }
        let rgba = RGBA(hex: hex) ?? RGBA(r: 1, g: 1, b: 1)
        let c = NSColor(srgbRed: rgba.r, green: rgba.g, blue: rgba.b, alpha: rgba.a)
        colorCache[hex] = c
        return c
    }

    /// The visible segment of a trendline, including extensions to the chart edges.
    private func segment(_ l: Trendline) -> (CGPoint, CGPoint) {
        var a = screen(l.a), b = screen(l.b)
        guard abs(b.x - a.x) > 0.01 else { return (a, b) }
        let slope = (b.y - a.y) / (b.x - a.x)
        let (left, right) = a.x <= b.x ? (a, b) : (b, a)
        var l2 = left, r2 = right
        if l.extendLeft { l2 = CGPoint(x: plot.minX, y: left.y + slope * (plot.minX - left.x)) }
        if l.extendRight { r2 = CGPoint(x: plot.maxX, y: right.y + slope * (plot.maxX - right.x)) }
        a = l2; b = r2
        return (a, b)
    }

    // MARK: Drawing

    override func draw(_ dirtyRect: NSRect) {
        computeRange()
        easeRange()
        labelRects = [:]
        closeHandleRect = nil
        Palette.chartBg.setFill()
        bounds.fill()

        drawGridAndAxes()
        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(rect: plot).addClip()
        if style.showVolume { drawVolume() }
        drawPositionZone()
        drawCandles()
        drawTradeLinks()
        drawTrendlines()
        drawMarkers()
        drawMeasure()
        NSGraphicsContext.restoreGraphicsState()

        drawLastPrice()
        drawOrderLines()
        drawCrosshair()
        drawLegend()
        drawAutoButton()
        drawMarkerTooltip()
        drawTyped()

        if candles.isEmpty {
            text(isLoading ? "Koersen laden…" : "Geen koersdata", at: CGPoint(x: plot.midX, y: plot.midY), font: .systemFont(ofSize: 14), color: Palette.dim, align: .center)
        }
    }

    private func niceStep(_ rough: Double) -> Double {
        guard rough > 0, rough.isFinite else { return 1 }
        let mag = pow(10, floor(log10(rough)))
        for m in [1.0, 2.0, 2.5, 5.0, 10.0] where m * mag >= rough { return m * mag }
        return 10 * mag
    }

    private func drawGridAndAxes() {
        let step = niceStep((range.hi - range.lo) / Double(max(plot.height / 56, 2)))
        var p = (range.lo / step).rounded(.up) * step
        let font = NSFont.monospacedDigitSystemFont(ofSize: 10.5, weight: .regular)
        while p <= range.hi {
            let yy = align(y(p)) + 0.5 / pixelRatio
            if yy > plot.minY + 4 && yy < plot.maxY - 4 {
                if style.showGrid {
                    Palette.grid.setStroke()
                    hline(yy, from: plot.minX, to: plot.maxX, width: 1)
                }
                text(Fmt.price(p), at: CGPoint(x: plot.maxX + 9, y: yy), font: font, color: Palette.dim, align: .left)
            }
            p += step
        }
        // Axis separators
        Palette.line.setStroke()
        let v = NSBezierPath()
        v.move(to: CGPoint(x: plot.maxX + 0.5, y: 0)); v.line(to: CGPoint(x: plot.maxX + 0.5, y: bounds.maxY))
        v.move(to: CGPoint(x: 0, y: plot.maxY + 0.5)); v.line(to: CGPoint(x: bounds.maxX, y: plot.maxY + 0.5))
        v.lineWidth = 1
        v.stroke()

        // Time labels
        guard let vis = visibleIndices() else { return }
        let barsPerLabel = max(1, Int((110 / spacing).rounded(.up)))
        let tfIntraday = timeframe.milliseconds < 86_400_000
        var lastDay = -1
        for i in vis {
            let c = candles[i]
            let slot = c.time / timeframe.milliseconds
            guard slot % Int64(barsPerLabel) == 0 else { continue }
            let date = Date(timeIntervalSince1970: Double(c.time) / 1000)
            let day = Calendar.current.component(.day, from: date)
            if tfIntraday {
                timeFormatter.dateFormat = (day != lastDay && Calendar.current.component(.hour, from: date) < 2) ? "d MMM" : "HH:mm"
            } else {
                timeFormatter.dateFormat = timeframe == .w1 ? "d MMM ''yy" : "d MMM"
            }
            lastDay = day
            let xx = align(x(index: Double(i))) + 0.5 / pixelRatio
            if style.showGrid {
                Palette.grid.setStroke()
                let gl = NSBezierPath()
                gl.move(to: CGPoint(x: xx, y: plot.minY)); gl.line(to: CGPoint(x: xx, y: plot.maxY))
                gl.lineWidth = 1
                gl.stroke()
            }
            text(timeFormatter.string(from: date), at: CGPoint(x: xx, y: plot.maxY + timeHeight / 2), font: font, color: Palette.dim, align: .center)
        }
    }

    private func drawVolume() {
        guard let vis = visibleIndices() else { return }
        let maxVol = vis.map { candles[$0].volume }.max() ?? 0
        guard maxVol > 0 else { return }
        let h = plot.height * 0.16
        let w = CGFloat(ChartMath.candleBodyWidth(spacing: Double(spacing), pixelRatio: Double(pixelRatio)))
        for i in vis {
            let c = candles[i]
            let vh = align(CGFloat(c.volume / maxVol) * h)
            color(c.close >= c.open ? style.upBody : style.downBody).withAlphaComponent(0.18).setFill()
            NSRect(x: align(x(index: Double(i)) - w / 2), y: plot.maxY - vh, width: w, height: vh).fill()
        }
    }

    private func drawCandles() {
        guard let vis = visibleIndices() else { return }
        let pr = pixelRatio
        let bodyW = CGFloat(ChartMath.candleBodyWidth(spacing: Double(spacing), pixelRatio: Double(pr)))
        let wickW = bodyW >= 3 ? max(1, pr.rounded(.down)) / pr : 1 / pr
        let thin = bodyW < 2.5            // too narrow for borders/hollow bodies
        for i in vis {
            let c = candles[i]
            let up = c.close >= c.open
            let left = align(x(index: Double(i)) - bodyW / 2)
            let top = align(y(max(c.open, c.close)))
            let bottom = max(top + 1 / pr, align(y(min(c.open, c.close))))
            let body = NSRect(x: left, y: top, width: bodyW, height: bottom - top)
            let wickX = left + ((bodyW - wickW) / 2 * pr).rounded(.down) / pr

            if style.showWicks {
                color(up ? style.upWick : style.downWick).setFill()
                let hi = align(y(c.high)), lo = align(y(c.low))
                NSRect(x: wickX, y: hi, width: wickW, height: max(0, top - hi)).fill()
                NSRect(x: wickX, y: bottom, width: wickW, height: max(0, lo - bottom)).fill()
            }
            let hollow = up && style.hollowUp && !thin
            if !hollow {
                color(up ? style.upBody : style.downBody).setFill()
                body.fill()
            }
            if (style.showBorders || hollow) && !thin {
                color(up ? style.upBorder : style.downBorder).setFill()
                body.frame(withWidth: 1 / pr * (hollow ? 2 : 1), using: .sourceOver)
            }
        }
    }

    private func dashPattern(_ dash: LineDash, width: CGFloat) -> [CGFloat]? {
        switch dash {
        case .solid: return nil
        case .dashed: return [6 + width * 2, 4 + width]
        case .dotted: return [0.01, width * 2.6]
        }
    }

    private func drawTrendlines() {
        for l in trendlines {
            let (a, b) = segment(l)
            let selected = l.id == selectedTrendline
            let hovered = isHovering(trendline: l.id)
            let path = NSBezierPath()
            path.move(to: a); path.line(to: b)
            let w = CGFloat(l.width) + (selected || hovered ? 0.6 : 0)
            path.lineWidth = w
            path.lineCapStyle = .round
            if let d = dashPattern(l.dash, width: w) { path.setLineDash(d, count: d.count, phase: 0) }
            color(l.color).setStroke()
            path.stroke()
            if selected || hovered {
                for p in [screen(l.a), screen(l.b)] {
                    let r = NSRect(x: p.x - 4.5, y: p.y - 4.5, width: 9, height: 9)
                    Palette.chartBg.setFill(); NSBezierPath(ovalIn: r).fill()
                    color(l.color).setStroke()
                    let o = NSBezierPath(ovalIn: r); o.lineWidth = 1.8; o.stroke()
                }
            }
        }
        // Line being drawn
        if let start = draftStart,
           let end = trendDraft ?? mouse.map({ chartPoint(at: $0, snap: snapActive) }) {
            let draft = Trendline(coin: coin, a: start, b: end, appearance: newLineAppearance)
            let (a, b) = segment(draft)
            let path = NSBezierPath()
            path.move(to: a); path.line(to: b)
            path.lineWidth = CGFloat(newLineAppearance.width)
            path.lineCapStyle = .round
            path.setLineDash([5, 4], count: 2, phase: 0)
            color(newLineAppearance.color).setStroke()
            path.stroke()
        }
        // Horizontal line tool preview
        if tool == .horizontal, let m = mouse, plot.contains(m) {
            let p = chartPoint(at: m, snap: snapActive)
            let yy = y(p.price)
            color(newLineAppearance.color).withAlphaComponent(0.8).setStroke()
            hline(yy, from: plot.minX, to: plot.maxX, width: CGFloat(newLineAppearance.width), dash: [5, 4])
        }
        // Snap marker
        if let s = snapMarker {
            let p = screen(s)
            let r = NSRect(x: p.x - 6, y: p.y - 6, width: 12, height: 12)
            Palette.yellow.withAlphaComponent(0.25).setFill()
            NSBezierPath(ovalIn: r).fill()
            Palette.yellow.setStroke()
            let o = NSBezierPath(ovalIn: r); o.lineWidth = 1.5; o.stroke()
        }
    }

    private func drawMeasure() {
        let pair: (ChartPoint, ChartPoint)?
        switch measure {
        case .none: pair = nil
        case .active(let a): pair = mouse.map { (a, chartPoint(at: $0, snap: snapActive)) }
        case .fixed(let a, let b): pair = (a, b)
        }
        guard let (a, b) = pair else { return }
        let r = ChartMath.measure(from: a, to: b, candles: candles, timeframe: timeframe)
        let pa = screen(a), pb = screen(b)
        let up = r.priceChange >= 0
        let col = up ? Palette.blue : Palette.red
        let rect = NSRect(x: min(pa.x, pb.x), y: min(pa.y, pb.y), width: abs(pb.x - pa.x), height: abs(pb.y - pa.y))
        col.withAlphaComponent(0.14).setFill()
        rect.fill()
        col.withAlphaComponent(0.7).setStroke()
        // Arrows through the middle
        let midX = rect.midX, midY = rect.midY
        let arrows = NSBezierPath()
        arrows.move(to: CGPoint(x: midX, y: pa.y)); arrows.line(to: CGPoint(x: midX, y: pb.y))
        arrows.move(to: CGPoint(x: pa.x, y: midY)); arrows.line(to: CGPoint(x: pb.x, y: midY))
        let tipDir: CGFloat = pb.y < pa.y ? 1 : -1
        arrows.move(to: CGPoint(x: midX - 5, y: pb.y + 6 * tipDir)); arrows.line(to: CGPoint(x: midX, y: pb.y)); arrows.line(to: CGPoint(x: midX + 5, y: pb.y + 6 * tipDir))
        let tipH: CGFloat = pb.x > pa.x ? -1 : 1
        arrows.move(to: CGPoint(x: pb.x + 6 * tipH, y: midY - 5)); arrows.line(to: CGPoint(x: pb.x, y: midY)); arrows.line(to: CGPoint(x: pb.x + 6 * tipH, y: midY + 5))
        arrows.lineWidth = 1.4
        arrows.stroke()

        // Label box under (or above, when measuring down) the rectangle
        let sign = up ? "+" : "−"
        let line1 = "\(sign)\(Fmt.price(abs(r.priceChange)))  (\(Fmt.percent(r.percent)))"
        let line2 = "\(abs(r.bars)) candles · \(ChartMath.durationText(ms: r.durationMs))"
        let line3 = r.volume > 0 ? "Vol \(compact(r.volume))" : ""
        let font = NSFont.monospacedDigitSystemFont(ofSize: 11.5, weight: .semibold)
        let attrs: [NSAttributedString.Key: Any] = [.font: font]
        let w = [line1, line2, line3].map { ($0 as NSString).size(withAttributes: attrs).width }.max()! + 20
        let h: CGFloat = line3.isEmpty ? 40 : 56
        var box = NSRect(x: midX - w / 2, y: up ? rect.minY - h - 8 : rect.maxY + 8, width: w, height: h)
        box.origin.x = min(max(box.minX, plot.minX + 4), plot.maxX - w - 4)
        box.origin.y = min(max(box.minY, plot.minY + 4), plot.maxY - h - 4)
        col.setFill()
        NSBezierPath(roundedRect: box, xRadius: 6, yRadius: 6).fill()
        text(line1, at: CGPoint(x: box.midX, y: box.minY + 12), font: font, color: .white, align: .center)
        text(line2, at: CGPoint(x: box.midX, y: box.minY + 28), font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular), color: .white, align: .center)
        if !line3.isEmpty { text(line3, at: CGPoint(x: box.midX, y: box.minY + 44), font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular), color: .white.withAlphaComponent(0.85), align: .center) }
    }

    private func compact(_ v: Double) -> String {
        let a = abs(v)
        if a >= 1e9 { return Fmt.number(v / 1e9, decimals: 2) + "B" }
        if a >= 1e6 { return Fmt.number(v / 1e6, decimals: 2) + "M" }
        if a >= 1e3 { return Fmt.number(v / 1e3, decimals: 1) + "K" }
        return Fmt.number(v, decimals: a < 10 ? 2 : 0)
    }

    private func drawLastPrice() {
        guard lastPrice > 0 else { return }
        let yy = align(y(lastPrice)) + 0.5 / pixelRatio
        guard yy >= plot.minY, yy <= plot.maxY else { return }
        let up = (candles.last.map { $0.close >= $0.open }) ?? true
        let col = color(up ? style.upBody : style.downBody)
        col.withAlphaComponent(0.55).setStroke()
        hline(yy, from: plot.minX, to: plot.maxX, width: 1, dash: [2, 3])
        // Price label with the countdown to the next candle underneath (like TradingView)
        let r = NSRect(x: plot.maxX + 3, y: yy - 10, width: axisWidth - 7, height: candles.isEmpty ? 20 : 34)
        col.setFill()
        NSBezierPath(roundedRect: r, xRadius: 4, yRadius: 4).fill()
        text(Fmt.price(lastPrice), at: CGPoint(x: r.minX + 6, y: yy), font: .monospacedDigitSystemFont(ofSize: 10.5, weight: .semibold), color: Palette.bg, align: .left)
        if let last = candles.last {
            let left = ChartMath.countdown(lastCandleOpen: last.time, timeframe: timeframe, nowMs: Int64(Date().timeIntervalSince1970 * 1000))
            text(left, at: CGPoint(x: r.minX + 6, y: yy + 14), font: .monospacedDigitSystemFont(ofSize: 10, weight: .medium), color: Palette.bg.withAlphaComponent(0.75), align: .left)
        }
    }

    private func drawOrderLines() {
        for line in lines {
            let isDragging = isDraggingLine(line.id)
            let px = isDragging ? (dragPrice ?? line.price) : line.price
            let rawY = y(px)
            let offscreen = rawY < plot.minY + 12 || rawY > plot.maxY - 12
            let yy = align(min(max(rawY, plot.minY + 12), plot.maxY - 12)) + 0.5 / pixelRatio
            let hot = isDragging || hover == .line(line.id)

            if !offscreen {
                line.color.setStroke()
                hline(yy, from: plot.minX, to: plot.maxX, width: line.emphasized ? 2 : (hot ? 2 : 1.4), dash: line.dashed ? [6, 4] : nil)
                axisTag(px, at: yy, bg: line.color, fg: Palette.bg)
            }

            var label = labelFor?(line.id, px) ?? ""
            if offscreen { label = (rawY < plot.minY ? "▲ " : "▼ ") + label }
            let font = NSFont.systemFont(ofSize: 11.5, weight: .semibold)
            let size = (label as NSString).size(withAttributes: [.font: font])
            let gripW: CGFloat = line.draggable ? 14 : 0
            let w = size.width + 20 + gripW
            let rect = NSRect(x: plot.maxX - 14 - w, y: yy - 11.5, width: w, height: 23)
            let path = NSBezierPath(roundedRect: rect, xRadius: 6, yRadius: 6)
            if line.emphasized || hot {
                line.color.setFill(); path.fill()
            } else {
                Palette.panel.withAlphaComponent(0.95).setFill(); path.fill()
                line.color.setStroke(); path.lineWidth = 1.2; path.stroke()
            }
            let fg = (line.emphasized || hot) ? Palette.bg : line.color
            if line.draggable {
                fg.setFill()
                for k in 0..<3 { NSRect(x: rect.minX + 9, y: yy - 4 + CGFloat(k) * 3.5, width: 8, height: 1.4).fill() }
            }
            text(label, at: CGPoint(x: rect.minX + 10 + gripW, y: yy), font: font, color: fg, align: .left)
            if line.draggable { labelRects[line.id] = rect }

            // Drag-to-close handle on the position line
            if line.id == .position && !offscreen {
                let h = NSRect(x: rect.minX - 30, y: yy - 12, width: 24, height: 24)
                let hp = NSBezierPath(roundedRect: h, xRadius: 6, yRadius: 6)
                let handleHot = hover == .closeHandle || isDraggingClose
                (handleHot ? (Palette.orange.highlight(withLevel: 0.2) ?? Palette.orange) : Palette.orange).setFill()
                hp.fill()
                let xp = NSBezierPath()
                xp.move(to: CGPoint(x: h.minX + 8, y: h.minY + 8)); xp.line(to: CGPoint(x: h.maxX - 8, y: h.maxY - 8))
                xp.move(to: CGPoint(x: h.maxX - 8, y: h.minY + 8)); xp.line(to: CGPoint(x: h.minX + 8, y: h.maxY - 8))
                xp.lineWidth = 2; xp.lineCapStyle = .round
                NSColor(hex: 0x1B1203).setStroke(); xp.stroke()
                closeHandleRect = h
            }
        }

        // Ghost line while dragging the close handle
        if let g = closeGhost {
            let yy = align(y(g)) + 0.5 / pixelRatio
            Palette.orange.setStroke()
            hline(yy, from: plot.minX, to: plot.maxX, width: 1.6, dash: [4, 3])
            axisTag(g, at: yy, bg: Palette.orange, fg: Palette.bg)
            let label = closeLabelFor?(g) ?? ""
            let font = NSFont.systemFont(ofSize: 11.5, weight: .semibold)
            let w = (label as NSString).size(withAttributes: [.font: font]).width + 20
            let rect = NSRect(x: plot.maxX - 14 - w, y: yy - 11.5, width: w, height: 23)
            let p = NSBezierPath(roundedRect: rect, xRadius: 6, yRadius: 6)
            NSColor(hex: 0x2A2110).setFill(); p.fill()
            Palette.orange.setStroke(); p.lineWidth = 1.2; p.stroke()
            text(label, at: CGPoint(x: rect.minX + 10, y: yy), font: font, color: Palette.orange, align: .left)
        }
    }

    private func drawCrosshair() {
        guard let m = mouse, plot.contains(m) else { return }
        switch drag {
        case .none, .measure: break
        default: return
        }
        Palette.muted.withAlphaComponent(0.45).setStroke()
        hline(align(m.y) + 0.5 / pixelRatio, from: plot.minX, to: plot.maxX, width: 1, dash: [3, 3])
        // The vertical line sits on the hovered candle, like TradingView.
        let idx = candles.isEmpty ? index(x: m.x) : min(max(index(x: m.x).rounded(), 0), Double(candles.count - 1))
        let cx = align(candles.isEmpty ? m.x : x(index: idx)) + 0.5 / pixelRatio
        let v = NSBezierPath()
        v.move(to: CGPoint(x: cx, y: plot.minY)); v.line(to: CGPoint(x: cx, y: plot.maxY))
        v.lineWidth = 1; v.setLineDash([3, 3], count: 2, phase: 0); v.stroke()
        axisTag(price(y: m.y), at: m.y, bg: Palette.card, fg: Palette.text)
        guard !candles.isEmpty else { return }
        let t = time(index: idx)
        timeFormatter.dateFormat = timeframe.milliseconds < 86_400_000 ? "EEE d MMM HH:mm" : "EEE d MMM yyyy"
        let s = timeFormatter.string(from: Date(timeIntervalSince1970: Double(t) / 1000))
        let font = NSFont.monospacedDigitSystemFont(ofSize: 10.5, weight: .medium)
        let w = (s as NSString).size(withAttributes: [.font: font]).width + 14
        let r = NSRect(x: min(max(cx - w / 2, plot.minX), plot.maxX - w), y: plot.maxY + 3, width: w, height: timeHeight - 6)
        Palette.card.setFill(); NSBezierPath(roundedRect: r, xRadius: 4, yRadius: 4).fill()
        text(s, at: CGPoint(x: r.midX, y: r.midY), font: font, color: Palette.text, align: .center)
    }

    /// OHLC legend in the top-left corner: the hovered candle, or the newest one.
    private func drawLegend() {
        guard !candles.isEmpty else { return }
        var i = candles.count - 1
        if let m = mouse, plot.contains(m) { i = Int(min(max(index(x: m.x).rounded(), 0), Double(candles.count - 1))) }
        let c = candles[i]
        let up = c.close >= c.open
        let valueColor = color(up ? style.upBody : style.downBody)
        let change = c.open != 0 ? (c.close - c.open) / c.open : 0
        let title = NSFont.systemFont(ofSize: 12.5, weight: .semibold)
        let key = NSFont.systemFont(ofSize: 12, weight: .regular)
        let num = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium)

        var penX = plot.minX + 12
        let yy: CGFloat = 16
        func put(_ s: String, _ font: NSFont, _ col: NSColor, gap: CGFloat) {
            let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: col]
            let size = (s as NSString).size(withAttributes: attrs)
            (s as NSString).draw(at: CGPoint(x: penX, y: yy - size.height / 2), withAttributes: attrs)
            penX += size.width + gap
        }
        put("\(coin) · \(timeframe.label)", title, Palette.text, gap: 14)
        for (k, v) in [("O", c.open), ("H", c.high), ("L", c.low), ("C", c.close)] {
            put(k, key, Palette.muted, gap: 3)
            put(Fmt.price(v), num, valueColor, gap: 10)
        }
        put(Fmt.percent(change), num, valueColor, gap: 12)
        if c.volume > 0 {
            put("Vol", key, Palette.muted, gap: 3)
            put(compact(c.volume), num, Palette.text, gap: 0)
        }
    }

    // MARK: Executions

    /// Screen position of a marker: on its candle, at the fill price.
    private func markerPoint(_ m: ChartMarker) -> CGPoint? {
        guard let i = Snap.nearestIndex(time: m.time, candles: candles),
              abs(candles[i].time - m.time) <= timeframe.milliseconds else { return nil }
        return CGPoint(x: x(index: Double(i)), y: y(m.price))
    }

    private func drawMarkers() {
        guard !markers.isEmpty, let vis = visibleIndices() else { return }
        let lo = candles[vis.lowerBound].time, hi = candles[vis.upperBound].time + timeframe.milliseconds
        let font = NSFont.systemFont(ofSize: 9.5, weight: .bold)
        for m in markers where m.time >= lo - timeframe.milliseconds && m.time <= hi {
            guard let p = markerPoint(m) else { continue }
            let col = m.isBuy ? Palette.green : Palette.red
            let hot = hoveredMarker == m.id || highlightTradeID == m.tradeID
            // tick exactly at the fill price
            col.setFill()
            let w = max(6, spacing * 0.9)
            NSRect(x: p.x - w / 2, y: p.y - 1, width: w, height: 2).fill()
            // arrow: below the price for a buy (pointing up), above for a sell
            let dir: CGFloat = m.isBuy ? 1 : -1
            let tip = CGPoint(x: p.x, y: p.y + dir * 4)
            let size: CGFloat = hot ? 8 : 6.5
            let tri = NSBezierPath()
            tri.move(to: tip)
            tri.line(to: CGPoint(x: tip.x - size, y: tip.y + dir * size * 1.4))
            tri.line(to: CGPoint(x: tip.x + size, y: tip.y + dir * size * 1.4))
            tri.close()
            tri.fill()
            Palette.chartBg.setStroke(); tri.lineWidth = 1; tri.stroke()
            text(m.label, at: CGPoint(x: tip.x, y: tip.y + dir * (size * 1.4 + 8)), font: font, color: col, align: .center)
        }
    }

    private func drawTradeLinks() {
        for l in tradeLinks {
            let a = CGPoint(x: x(index: index(time: l.t0)), y: y(l.p0))
            let b = CGPoint(x: x(index: index(time: l.t1)), y: y(l.p1))
            guard max(a.x, b.x) >= plot.minX, min(a.x, b.x) <= plot.maxX else { continue }
            let col = l.isWin ? Palette.green : Palette.red
            let hot = highlightTradeID == l.id
            let path = NSBezierPath()
            path.move(to: a); path.line(to: b)
            path.lineWidth = hot ? 2 : 1.2
            path.setLineDash([4, 3], count: 2, phase: 0)
            col.withAlphaComponent(hot ? 0.95 : 0.6).setStroke()
            path.stroke()
            if hot {
                col.withAlphaComponent(0.08).setFill()
                NSRect(x: min(a.x, b.x), y: plot.minY, width: abs(b.x - a.x), height: plot.height).fill()
            }
            let font = NSFont.monospacedDigitSystemFont(ofSize: 10.5, weight: .semibold)
            let mid = CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2 - 10)
            let w = (l.label as NSString).size(withAttributes: [.font: font]).width + 12
            let r = NSRect(x: mid.x - w / 2, y: mid.y - 9, width: w, height: 18)
            Palette.panel.withAlphaComponent(0.92).setFill()
            NSBezierPath(roundedRect: r, xRadius: 4, yRadius: 4).fill()
            text(l.label, at: CGPoint(x: r.midX, y: r.midY), font: font, color: col, align: .center)
        }
    }

    /// Tinted area between the average entry and the current price (green in profit, red in loss).
    private func drawPositionZone() {
        guard let pos = lines.first(where: { $0.id == .position }), lastPrice > 0 else { return }
        let isLong = pos.color != Palette.accent
        let inProfit = isLong ? lastPrice >= pos.price : lastPrice <= pos.price
        (inProfit ? Palette.green : Palette.red).withAlphaComponent(0.07).setFill()
        let y0 = y(pos.price), y1 = y(lastPrice)
        NSRect(x: plot.minX, y: min(y0, y1), width: plot.width, height: abs(y1 - y0)).fill()
    }

    private func drawMarkerTooltip() {
        guard let id = hoveredMarker, let m = markers.first(where: { $0.id == id }), let p = markerPoint(m) else { return }
        let font = NSFont.systemFont(ofSize: 11.5, weight: .medium)
        let w = m.detail.map { ($0 as NSString).size(withAttributes: [.font: font]).width }.max()! + 20
        let h = CGFloat(m.detail.count) * 16 + 12
        var r = NSRect(x: p.x + 14, y: p.y - h / 2, width: w, height: h)
        if r.maxX > plot.maxX - 4 { r.origin.x = p.x - 14 - w }
        r.origin.y = min(max(r.minY, plot.minY + 4), plot.maxY - h - 4)
        Palette.card.withAlphaComponent(0.97).setFill()
        NSBezierPath(roundedRect: r, xRadius: 7, yRadius: 7).fill()
        (m.isBuy ? Palette.green : Palette.red).setStroke()
        let b = NSBezierPath(roundedRect: r.insetBy(dx: 0.5, dy: 0.5), xRadius: 7, yRadius: 7); b.lineWidth = 1; b.stroke()
        for (i, line) in m.detail.enumerated() {
            text(line, at: CGPoint(x: r.minX + 10, y: r.minY + 14 + CGFloat(i) * 16), font: i == 0 ? .systemFont(ofSize: 11.5, weight: .semibold) : font,
                 color: i == 0 ? Palette.text : Palette.muted, align: .left)
        }
    }

    private func markerAt(_ p: CGPoint) -> String? {
        var best: (String, CGFloat)?
        for m in markers {
            guard let q = markerPoint(m) else { continue }
            let d = min(hypot(p.x - q.x, p.y - q.y), hypot(p.x - q.x, p.y - (q.y + (m.isBuy ? 12 : -12))))
            if d < 10, d < (best?.1 ?? .infinity) { best = (m.id, d) }
        }
        return best?.0
    }

    /// Scrolls and zooms so a time range (a trade) fills the middle of the chart.
    private func applyFocusIfPossible() {
        guard let f = pendingFocus, let first = candles.first, first.time <= f.start else { return }
        syncViewport()
        let i0 = index(time: f.start), i1 = index(time: f.end)
        let bars = max(i1 - i0, 8)
        let s = min(max(Double(plot.width) * 0.6 / bars, ChartViewport.minSpacing), vp.maxSpacing)
        vp.setSpacing(s, keepingIndex: i1, atX: Double(plot.width) * 0.8)
        autoScale = true
        shownRange = nil
        pendingFocus = nil
        needsDisplay = true
    }

    /// TradingView-style interval entry: type "15" or "4h" and press ⏎.
    private func drawTyped() {
        guard !typed.isEmpty else { return }
        let tf = Timeframe.parse(typed)
        let font = NSFont.monospacedDigitSystemFont(ofSize: 22, weight: .bold)
        let hint = tf.map { "⏎  \($0.label)" } ?? "onbekend"
        let w = max((typed as NSString).size(withAttributes: [.font: font]).width + 40, 120)
        let box = NSRect(x: plot.midX - w / 2, y: plot.midY - 40, width: w, height: 72)
        Palette.card.withAlphaComponent(0.96).setFill()
        NSBezierPath(roundedRect: box, xRadius: 10, yRadius: 10).fill()
        Palette.accent.setStroke()
        let b = NSBezierPath(roundedRect: box.insetBy(dx: 0.5, dy: 0.5), xRadius: 10, yRadius: 10); b.lineWidth = 1.5; b.stroke()
        text(typed.uppercased(), at: CGPoint(x: box.midX, y: box.minY + 26), font: font, color: Palette.text, align: .center)
        text(hint, at: CGPoint(x: box.midX, y: box.minY + 54), font: .systemFont(ofSize: 11.5, weight: .medium), color: tf == nil ? Palette.red : Palette.muted, align: .center)
    }

    private func drawAutoButton() {
        let r = autoButtonRect
        let hot = hover == .autoButton
        (autoScale ? Palette.accent.withAlphaComponent(0.85) : (hot ? Palette.card : Palette.panel)).setFill()
        NSBezierPath(roundedRect: r, xRadius: 4, yRadius: 4).fill()
        text("A", at: CGPoint(x: r.midX, y: r.midY), font: .systemFont(ofSize: 11, weight: .bold), color: autoScale ? .white : Palette.muted, align: .center)
    }

    // MARK: Drawing helpers

    private func hline(_ yy: CGFloat, from x0: CGFloat, to x1: CGFloat, width: CGFloat, dash: [CGFloat]? = nil) {
        let p = NSBezierPath()
        p.move(to: CGPoint(x: x0, y: yy)); p.line(to: CGPoint(x: x1, y: yy))
        p.lineWidth = width
        if let dash { p.setLineDash(dash, count: dash.count, phase: 0) }
        p.stroke()
    }

    private func axisTag(_ p: Double, at yy: CGFloat, bg: NSColor, fg: NSColor) {
        let r = NSRect(x: plot.maxX + 3, y: yy - 10, width: axisWidth - 7, height: 20)
        bg.setFill()
        NSBezierPath(roundedRect: r, xRadius: 4, yRadius: 4).fill()
        text(Fmt.price(p), at: CGPoint(x: r.minX + 6, y: yy), font: .monospacedDigitSystemFont(ofSize: 10.5, weight: .semibold), color: fg, align: .left)
    }

    private enum Align { case left, center, right }

    private func text(_ s: String, at p: CGPoint, font: NSFont, color: NSColor, align: Align) {
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
        let size = (s as NSString).size(withAttributes: attrs)
        var origin = CGPoint(x: p.x, y: p.y - size.height / 2)
        switch align {
        case .left: break
        case .center: origin.x -= size.width / 2
        case .right: origin.x -= size.width
        }
        (s as NSString).draw(at: origin, withAttributes: attrs)
    }

    // MARK: Hit testing

    private func distance(_ p: CGPoint, toSegment a: CGPoint, _ b: CGPoint) -> CGFloat {
        let dx = b.x - a.x, dy = b.y - a.y
        let len2 = dx * dx + dy * dy
        guard len2 > 0 else { return hypot(p.x - a.x, p.y - a.y) }
        let t = max(0, min(1, ((p.x - a.x) * dx + (p.y - a.y) * dy) / len2))
        return hypot(p.x - (a.x + t * dx), p.y - (a.y + t * dy))
    }

    private func hitTarget(_ p: CGPoint) -> Hover? {
        if autoButtonRect.insetBy(dx: -2, dy: -2).contains(p) { return .autoButton }
        if p.x > plot.maxX && p.y < plot.maxY { return .priceAxis }
        if p.y > plot.maxY && p.x < plot.maxX { return .timeAxis }
        if let r = closeHandleRect, r.insetBy(dx: -4, dy: -4).contains(p) { return .closeHandle }
        for (id, r) in labelRects where r.insetBy(dx: -2, dy: -3).contains(p) { return .line(id) }
        // Trendline endpoints (selected first), then bodies
        let ordered = trendlines.filter { $0.id == selectedTrendline } + trendlines.filter { $0.id != selectedTrendline }
        for l in ordered {
            if hypot(p.x - screen(l.a).x, p.y - screen(l.a).y) < 8 { return .endpoint(l.id, true) }
            if hypot(p.x - screen(l.b).x, p.y - screen(l.b).y) < 8 { return .endpoint(l.id, false) }
        }
        var bestLine: (LineID, CGFloat)?
        for line in lines where line.draggable {
            let d = abs(y(line.price) - p.y)
            if d < 6, d < (bestLine?.1 ?? .infinity) { bestLine = (line.id, d) }
        }
        if let b = bestLine { return .line(b.0) }
        for l in trendlines {
            let (a, b) = segment(l)
            if distance(p, toSegment: a, b) < max(5, CGFloat(l.width) + 3) { return .trendline(l.id) }
        }
        return nil
    }

    // MARK: Mouse

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let t = trackingArea { removeTrackingArea(t) }
        let t = NSTrackingArea(rect: .zero, options: [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: self, userInfo: nil)
        addTrackingArea(t)
        trackingArea = t
    }

    private func location(_ e: NSEvent) -> CGPoint { convert(e.locationInWindow, from: nil) }

    private func updateSnapMarker() {
        guard snapActive, let m = mouse, plot.contains(m) else { snapMarker = nil; return }
        var using = tool != .cursor || pendingTrendStart != nil
        switch drag {
        case .trendNew, .endpoint, .measure: using = true
        default: break
        }
        if case .active = measure { using = true }
        snapMarker = using ? Snap.snap(time: time(index: index(x: m.x)), price: price(y: m.y), candles: candles, timeframe: timeframe) : nil
    }

    private func updateCursor() {
        if tool != .cursor { NSCursor.crosshair.set(); return }
        switch hover {
        case .line?, .closeHandle?: NSCursor.openHand.set()
        case .endpoint?, .trendline?, .autoButton?: NSCursor.pointingHand.set()
        case .priceAxis?: NSCursor.resizeUpDown.set()
        case .timeAxis?: NSCursor.resizeLeftRight.set()
        case nil: NSCursor.crosshair.set()
        }
    }

    override func mouseMoved(with e: NSEvent) {
        mouse = location(e)
        commandDown = e.modifierFlags.contains(.command)
        hoveredMarker = plot.contains(mouse!) ? markerAt(mouse!) : nil
        hover = tool != .cursor ? nil : hitTarget(mouse!)
        updateSnapMarker()
        updateCursor()
        needsDisplay = true
    }

    override func mouseExited(with e: NSEvent) {
        mouse = nil
        hover = nil
        snapMarker = nil
        NSCursor.arrow.set()
        needsDisplay = true
    }

    override func flagsChanged(with e: NSEvent) {
        commandDown = e.modifierFlags.contains(.command)
        updateSnapMarker()
        needsDisplay = true
    }

    override func mouseDown(with e: NSEvent) {
        window?.makeFirstResponder(self)
        stopKinetic()
        zoomTarget = nil
        panRemaining = 0
        let p = location(e)
        mouse = p
        commandDown = e.modifierFlags.contains(.command)
        computeRange()

        if e.clickCount == 2 {
            if p.x > plot.maxX && p.y < plot.maxY { autoScale = true; needsDisplay = true; return }
            if p.y > plot.maxY && p.x < plot.maxX { vp.reset(); needsDisplay = true; return }
        }

        // Measuring: ⇧ + click starts, the next click ends, a further click clears.
        if tool == .cursor && plot.contains(p) {
            let shift = e.modifierFlags.contains(.shift)
            switch measure {
            case .active(let a):
                measure = .fixed(a, chartPoint(at: p, snap: snapActive))
                needsDisplay = true
                return
            case .fixed:
                measure = .none
                if !shift { needsDisplay = true }
            case .none:
                break
            }
            if shift {
                let pt = chartPoint(at: p, snap: snapActive)
                measure = .active(pt)
                drag = .measure(pt, startScreen: p)
                needsDisplay = true
                return
            }
        }

        if tool == .horizontal {
            guard plot.contains(p) else { return }
            onHorizontalCreate?(chartPoint(at: p, snap: snapActive))
            onToolFinished?()
            needsDisplay = true
            return
        }

        if tool == .trendline {
            guard plot.contains(p) else { return }
            let pt = chartPoint(at: p, snap: snapActive)
            if let start = pendingTrendStart {
                onTrendlineCreate?(start, pt)
                pendingTrendStart = nil
                trendDraft = nil
                onToolFinished?()
            } else {
                drag = .trendNew(pt)
                trendDraft = pt
            }
            needsDisplay = true
            return
        }

        switch hitTarget(p) {
        case .autoButton?:
            autoScale.toggle()
            if !autoScale { manualRange = range } else { shownRange = range }
        case .closeHandle?:
            drag = .close
            closeGhost = lines.first { $0.id == .position }?.price
            NSCursor.closedHand.set()
        case .line(let id)?:
            drag = .line(id)
            dragPrice = lines.first { $0.id == id }?.price
            NSCursor.closedHand.set()
        case .endpoint(let id, let isA)?:
            onTrendlineSelect?(id)
            drag = .endpoint(id, isA: isA)
        case .trendline(let id)?:
            onTrendlineSelect?(id)
            if let l = trendlines.first(where: { $0.id == id }) { drag = .trendMove(l, anchor: chartPoint(at: p, snap: false)) }
        case .priceAxis?:
            drag = .priceAxis(startY: p.y, startRange: range)
        case .timeAxis?:
            drag = .timeAxis(startX: p.x, startSpacing: vp.barSpacing)
        case nil:
            if selectedTrendline != nil { onTrendlineSelect?(nil) }
            kinetic = KineticScroll()
            kinetic.add(position: Double(p.x), timeMs: e.timestamp * 1000)
            drag = .pan(startX: p.x, startOffset: vp.rightOffset, startY: p.y, startRange: range)
        }
        needsDisplay = true
    }

    override func mouseDragged(with e: NSEvent) {
        let p = location(e)
        mouse = p
        commandDown = e.modifierFlags.contains(.command)
        switch drag {
        case .none:
            break
        case .pan(let sx, let so, let sy, let sr):
            vp.rightOffset = so
            vp.pan(pixels: Double(p.x - sx))
            kinetic.add(position: Double(p.x), timeMs: e.timestamp * 1000)
            if !autoScale {
                let dp = Double(p.y - sy) / Double(plot.height - 20) * (sr.hi - sr.lo)
                manualRange = (sr.lo + dp, sr.hi + dp)
            }
        case .priceAxis(let sy, let sr):
            // TradingView's price-scale drag: dragging down zooms out, up zooms in, around the center.
            let h = Double(plot.height)
            let start = h - Double(sy), now = max(0, h - Double(p.y))
            let coeff = max(0.1, (start + (h - 1) * 0.2) / (now + (h - 1) * 0.2))
            let mid = (sr.lo + sr.hi) / 2, half = (sr.hi - sr.lo) / 2 * coeff
            manualRange = (mid - half, mid + half)
            autoScale = false
        case .timeAxis(let sx, let ss):
            vp.scaleTimeAxis(startSpacing: ss, startX: Double(sx - plot.minX), x: Double(p.x - plot.minX))
        case .line(let id):
            dragPrice = price(y: p.y)
            onLineDrag?(id, dragPrice!, false)
        case .close:
            closeGhost = price(y: p.y)
        case .trendNew:
            trendDraft = chartPoint(at: p, snap: snapActive)
        case .endpoint(let id, let isA):
            guard var l = trendlines.first(where: { $0.id == id }) else { break }
            let pt = chartPoint(at: p, snap: snapActive)
            if isA { l.a = pt } else { l.b = pt }
            onTrendlineUpdate?(l)
        case .trendMove(let orig, let anchor):
            let cur = chartPoint(at: p, snap: false)
            var l = orig
            let dt = cur.time - anchor.time, dp = cur.price - anchor.price
            l.a = ChartPoint(time: orig.a.time + dt, price: orig.a.price + dp)
            l.b = ChartPoint(time: orig.b.time + dt, price: orig.b.price + dp)
            onTrendlineUpdate?(l)
        case .measure:
            break   // the measure follows `mouse`
        }
        updateSnapMarker()
        needsDisplay = true
    }

    override func mouseUp(with e: NSEvent) {
        let p = location(e)
        switch drag {
        case .line(let id):
            if let px = dragPrice { onLineDrag?(id, px, true) }
        case .close:
            if let g = closeGhost { onCloseDrag?(g) }
        case .trendNew(let start):
            let end = trendDraft ?? start
            let a = screen(start), b = screen(end)
            if hypot(a.x - b.x, a.y - b.y) < 6 {
                pendingTrendStart = start   // click-click mode: wait for second click
            } else {
                onTrendlineCreate?(start, end)
                onToolFinished?()
            }
        case .measure(let start, let s0):
            // ⇧-drag: release fixes the measurement; a plain ⇧-click keeps following the mouse.
            if hypot(p.x - s0.x, p.y - s0.y) >= 6 { measure = .fixed(start, chartPoint(at: p, snap: snapActive)) }
        case .pan:
            kinetic.add(position: Double(p.x), timeMs: e.timestamp * 1000)
            if let v = kinetic.releaseSpeed(atMs: e.timestamp * 1000) { startKinetic(speed: v) }
        default:
            break
        }
        drag = .none
        dragPrice = nil
        closeGhost = nil
        trendDraft = nil
        mouse = p
        hover = tool != .cursor ? nil : hitTarget(p)
        updateCursor()
        needsDisplay = true
    }

    // MARK: Animation

    private func startKinetic(speed v: Double) {
        fling = (v, vp.rightOffset, CACurrentMediaTime(), KineticScroll.duration(speed: v))
        startAnimating()
    }

    private func stopKinetic() { fling = nil }

    private func startAnimating() {
        guard link == nil, window != nil else { return }
        let l = displayLink(target: self, selector: #selector(onFrame(_:)))
        l.add(to: .main, forMode: .common)
        link = l
        lastFrameTime = CACurrentMediaTime()
    }

    @objc private func onFrame(_ l: CADisplayLink) {
        let now = CACurrentMediaTime()
        let dt = min(0.05, max(0.001, now - lastFrameTime))
        lastFrameTime = now
        syncViewport()
        let a = 1 - exp(-dt / 0.07)
        if let f = fling {
            let ms = (now - f.began) * 1000
            vp.rightOffset = f.startOffset
            vp.pan(pixels: KineticScroll.offset(speed: f.speed, afterMs: min(ms, f.duration)))
            if ms >= f.duration { fling = nil }
        }
        if let z = zoomTarget {
            let s = vp.barSpacing + (z.spacing - vp.barSpacing) * a
            if abs(z.spacing - s) < z.spacing * 0.002 {
                vp.setSpacing(z.spacing, keepingIndex: z.anchorIndex, atX: z.anchorX)
                zoomTarget = nil
            } else {
                vp.setSpacing(s, keepingIndex: z.anchorIndex, atX: z.anchorX)
            }
        }
        if panRemaining != 0 {
            let d = abs(panRemaining) < 0.5 ? panRemaining : panRemaining * a
            vp.pan(pixels: d)
            panRemaining -= d
            if abs(panRemaining) < 0.01 { panRemaining = 0 }
        }
        needsDisplay = true
        if fling == nil && zoomTarget == nil && panRemaining == 0 && !rangeAnimating {
            link?.invalidate()
            link = nil
        }
    }

    /// Animated zoom (mouse wheel notches, arrow keys) around a fixed point.
    private func animateZoom(by factor: Double, anchorX: Double) {
        let base = zoomTarget?.spacing ?? vp.barSpacing
        let target = min(max(base * factor, ChartViewport.minSpacing), vp.maxSpacing)
        let ax = min(max(anchorX, 0), vp.width)
        zoomTarget = (target, ax, vp.index(x: ax))
        startAnimating()
    }

    // MARK: Wheel & pinch

    override func scrollWheel(with e: NSEvent) {
        syncViewport()
        let ax = Double(location(e).x - plot.minX)
        let dx = Double(e.scrollingDeltaX), dy = Double(e.scrollingDeltaY)
        if e.hasPreciseScrollingDeltas {
            // Trackpad / Magic Mouse: follow the fingers directly, including macOS's own momentum,
            // so a fast swipe glides out naturally instead of stopping dead.
            stopKinetic()
            zoomTarget = nil
            panRemaining = 0
            if abs(dx) > abs(dy) {
                vp.pan(pixels: dx)
            } else if dy != 0 {
                vp.zoom(factor: min(max(exp(dy * 0.0045), 0.75), 1.33), anchorX: ax)
            }
        } else {
            // Mouse wheel: every notch animates smoothly; quick notches add up.
            if abs(dx) > abs(dy) {
                panRemaining += dx * 36
                startAnimating()
            } else if dy != 0 {
                animateZoom(by: pow(1.14, dy), anchorX: ax)
            }
        }
        needsDisplay = true
    }

    override func magnify(with e: NSEvent) {
        syncViewport()
        stopKinetic()
        zoomTarget = nil
        vp.pinch(magnification: Double(e.magnification), anchorX: Double(location(e).x - plot.minX))
        needsDisplay = true
    }

    // MARK: Keyboard & context menu

    override func keyDown(with e: NSEvent) {
        let plain = e.modifierFlags.intersection([.command, .control, .option]).isEmpty
        if plain, let ch = e.charactersIgnoringModifiers?.lowercased(), ch.count == 1, "0123456789hdwm".contains(ch), typed.count < 4 {
            typed += ch
            typedClear?.invalidate()
            typedClear = Timer.scheduledTimer(withTimeInterval: 4, repeats: false) { [weak self] _ in
                MainActor.assumeIsolated { self?.typed = ""; self?.needsDisplay = true }
            }
            needsDisplay = true
            return
        }
        syncViewport()
        switch e.keyCode {
        case 36, 76: // return, enter
            guard !typed.isEmpty else { super.keyDown(with: e); return }
            if let tf = Timeframe.parse(typed) { onTimeframeTyped?(tf) } else { NSSound.beep() }
            typed = ""
            needsDisplay = true
        case 123: // ←  back in time
            panRemaining += vp.barSpacing * (e.modifierFlags.contains(.shift) ? 10 : 1)
            startAnimating()
        case 124: // →
            panRemaining -= vp.barSpacing * (e.modifierFlags.contains(.shift) ? 10 : 1)
            startAnimating()
        case 126: // ↑ zoom in (around the newest candle)
            animateZoom(by: 1.25, anchorX: vp.x(index: Double(max(candles.count - 1, 0))))
        case 125: // ↓ zoom out
            animateZoom(by: 0.8, anchorX: vp.x(index: Double(max(candles.count - 1, 0))))
        case 51, 117: // delete, forward delete
            if let id = selectedTrendline { onTrendlineDelete?(id) } else { super.keyDown(with: e) }
        case 53: // escape
            pendingTrendStart = nil
            trendDraft = nil
            if !typed.isEmpty { typed = ""; needsDisplay = true; return }
            if case .none = measure {
                if tool != .cursor { onToolFinished?() } else if selectedTrendline != nil { onTrendlineSelect?(nil) }
            } else {
                measure = .none
            }
            needsDisplay = true
        default:
            super.keyDown(with: e)
        }
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        let p = location(event)
        let menu = NSMenu()
        switch hitTarget(p) {
        case .trendline(let id)?, .endpoint(let id, _)?:
            guard let l = trendlines.first(where: { $0.id == id }) else { return nil }
            onTrendlineSelect?(id)
            let right = ClosureMenuItem(title: "Verleng naar rechts") { [weak self] in var n = l; n.extendRight.toggle(); self?.onTrendlineUpdate?(n) }
            right.state = l.extendRight ? .on : .off
            menu.addItem(right)
            let left = ClosureMenuItem(title: "Verleng naar links") { [weak self] in var n = l; n.extendLeft.toggle(); self?.onTrendlineUpdate?(n) }
            left.state = l.extendLeft ? .on : .off
            menu.addItem(left)
            menu.addItem(.separator())
            menu.addItem(ClosureMenuItem(title: "Verwijderen") { [weak self] in self?.onTrendlineDelete?(id) })
        case .line(.order(let oid))?:
            menu.addItem(ClosureMenuItem(title: "Annuleer order") { [weak self] in self?.onCancelOrder?(oid) })
        default:
            return nil
        }
        return menu
    }
}

/// NSMenuItem that runs a closure.
final class ClosureMenuItem: NSMenuItem {
    private let handler: @MainActor () -> Void
    init(title: String, handler: @escaping @MainActor () -> Void) {
        self.handler = handler
        super.init(title: title, action: #selector(run), keyEquivalent: "")
        target = self
    }
    required init(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    @objc private func run() { MainActor.assumeIsolated { handler() } }
}
#endif

#if os(macOS)
// MARK: - Geometry for the scripted demo recording (window coordinates)
extension ChartCanvas {
    func demoPoint(price: Double, xFraction: CGFloat) -> CGPoint {
        computeRange()
        return convert(CGPoint(x: plot.minX + plot.width * xFraction, y: y(price)), to: nil)
    }

    func demoLinePoint(_ id: LineID) -> CGPoint? {
        displayIfNeeded()
        guard let r = labelRects[id] else { return nil }
        return convert(CGPoint(x: r.minX + 13, y: r.midY), to: nil)
    }

    var demoCloseHandle: CGPoint? {
        displayIfNeeded()
        return closeHandleRect.map { convert(CGPoint(x: $0.midX, y: $0.midY), to: nil) }
    }

    /// A candle `k` bars back from the newest one, at its high or low.
    func demoCandlePoint(fromEnd k: Int, high: Bool) -> CGPoint? {
        computeRange()
        let i = candles.count - 1 - k
        guard i >= 0, i < candles.count else { return nil }
        let c = candles[i]
        return convert(CGPoint(x: x(index: Double(i)), y: y(high ? c.high : c.low)), to: nil)
    }

    /// Index (bars back from newest) of the lowest low / highest high within a window of bars.
    func demoExtreme(from a: Int, to b: Int, high: Bool) -> Int? {
        guard !candles.isEmpty else { return nil }
        let range = max(0, a)...min(candles.count - 1, b)
        return range.max { l, r in
            let cl = candles[candles.count - 1 - l], cr = candles[candles.count - 1 - r]
            return high ? cl.high < cr.high : cl.low > cr.low
        }
    }

    var demoPlotWindowRect: CGRect { convert(plot, to: nil) }

    var demoPriceLabelPoint: CGPoint {
        computeRange()
        return convert(CGPoint(x: plot.maxX + axisWidth / 2, y: y(lastPrice) + 7), to: nil)
    }

    func demoTimeAxisPoint(xFraction: CGFloat) -> CGPoint {
        convert(CGPoint(x: plot.minX + plot.width * xFraction, y: plot.maxY + timeHeight / 2), to: nil)
    }

    /// Number of bars currently visible left of the newest candle.
    var demoVisibleBars: Int { max(10, Int(Double(plot.width) / vp.barSpacing - vp.rightOffset) - 2) }

    var demoDebug: String {
        "tool=\(tool) drag=\(drag) mouse=\(String(describing: mouse)) plot=\(plot) lines=\(trendlines.count) pending=\(pendingTrendStart != nil) draft=\(trendDraft != nil)"
    }

    /// Converts a window point to the chart's (time, price), optionally snapped like ⌘-drawing does.
    func demoChartPoint(window p: CGPoint, snap: Bool) -> ChartPoint {
        computeRange()
        return chartPoint(at: convert(p, from: nil), snap: snap)
    }
}
#endif
