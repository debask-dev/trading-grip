#if os(macOS)
import AppKit
import GripCore

/// Custom-drawn candlestick chart with draggable order lines, a drag-to-close handle and trendlines.
///
/// Mouse:   drag empty area = pan · drag price axis = scale · double-click axis = auto-scale
///          scroll vertical = zoom · scroll horizontal = pan · pinch = zoom
/// Lines:   drag any order/TP/SL line · drag the ✕ on the position line to place a partial close
/// Drawing: trendline tool → click-drag (or click, click). Hold ⌘ to snap to candle open/high/low/close.
///          Click a line to select, drag its ends or body, ⌫ to delete, right-click for options.
final class ChartCanvas: NSView {
    // MARK: Inputs
    var candles: [Candle] = []
    var timeframe: Timeframe = .m15
    var lastPrice: Double = 0
    var lines: [ChartLine] = []
    var trendlines: [Trendline] = []
    var selectedTrendline: UUID?
    var tool: ChartTool = .cursor { didSet { if tool != .trendline { pendingTrendStart = nil; trendDraft = nil } } }
    var hasPosition = false
    var isLoading = false
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

    // MARK: Layout
    private let axisWidth: CGFloat = 78
    private let timeHeight: CGFloat = 26
    private var plot: NSRect { NSRect(x: 0, y: 0, width: max(10, bounds.width - axisWidth), height: max(10, bounds.height - timeHeight)) }

    // MARK: Viewport
    private var spacing: CGFloat = 9
    private var rightOffset: CGFloat = 10
    private var autoScale = true
    private var manualRange: (lo: Double, hi: Double) = (0, 1)
    private var range: (lo: Double, hi: Double) = (0, 1)

    // MARK: Interaction
    private enum Hover: Equatable {
        case line(LineID), closeHandle, trendline(UUID), endpoint(UUID, Bool), axis
    }
    private enum Drag {
        case none
        case pan(startX: CGFloat, startOffset: CGFloat, startY: CGFloat, startRange: (lo: Double, hi: Double))
        case axis(startY: CGFloat, startRange: (lo: Double, hi: Double))
        case line(LineID)
        case close
        case trendNew(ChartPoint)
        case endpoint(UUID, isA: Bool)
        case trendMove(Trendline, anchor: ChartPoint)
    }
    private var drag: Drag = .none
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

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    func resetView() {
        spacing = 9
        rightOffset = 10
        autoScale = true
        drag = .none
        pendingTrendStart = nil
        trendDraft = nil
        needsDisplay = true
    }

    // MARK: Coordinates

    private func x(index i: Double) -> CGFloat {
        plot.maxX - (CGFloat(Double(candles.count - 1) - i) + rightOffset) * spacing - spacing / 2
    }

    private func index(x: CGFloat) -> Double {
        Double(candles.count - 1) + Double(rightOffset) - Double((plot.maxX - spacing / 2 - x) / spacing)
    }

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

    private func visibleIndices() -> ClosedRange<Int>? {
        guard !candles.isEmpty else { return nil }
        let a = max(0, Int(index(x: plot.minX).rounded(.down)))
        let b = min(candles.count - 1, Int(index(x: plot.maxX).rounded(.up)))
        return a <= b ? a...b : nil
    }

    private func computeRange() {
        if !autoScale { range = manualRange; return }
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
        range = (lo - pad, hi + pad)
        manualRange = range
    }

    private func chartPoint(at p: CGPoint, snap: Bool) -> ChartPoint {
        let t = time(index: index(x: p.x))
        let pr = price(y: p.y)
        if snap, let s = Snap.snap(time: t, price: pr, candles: candles, timeframe: timeframe) { return s }
        return ChartPoint(time: t, price: pr)
    }

    private func screen(_ cp: ChartPoint) -> CGPoint { CGPoint(x: x(index: index(time: cp.time)), y: y(cp.price)) }

    // MARK: Drawing

    override func draw(_ dirtyRect: NSRect) {
        computeRange()
        labelRects = [:]
        closeHandleRect = nil
        Palette.chartBg.setFill()
        bounds.fill()

        drawGridAndAxes()
        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(rect: plot).addClip()
        drawVolume()
        drawCandles()
        drawTrendlines()
        NSGraphicsContext.restoreGraphicsState()

        drawLastPrice()
        drawOrderLines()
        drawCrosshair()

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
            let yy = y(p).rounded() + 0.5
            if yy > plot.minY + 4 && yy < plot.maxY - 4 {
                Palette.grid.setStroke()
                hline(yy, from: plot.minX, to: plot.maxX, width: 1)
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
            let xx = x(index: Double(i)).rounded() + 0.5
            Palette.grid.setStroke()
            let gl = NSBezierPath()
            gl.move(to: CGPoint(x: xx, y: plot.minY)); gl.line(to: CGPoint(x: xx, y: plot.maxY))
            gl.lineWidth = 1
            gl.stroke()
            text(timeFormatter.string(from: date), at: CGPoint(x: xx, y: plot.maxY + timeHeight / 2), font: font, color: Palette.dim, align: .center)
        }
    }

    private func drawVolume() {
        guard let vis = visibleIndices() else { return }
        let maxVol = vis.map { candles[$0].volume }.max() ?? 0
        guard maxVol > 0 else { return }
        let h = plot.height * 0.16
        let w = max(1, spacing * 0.7)
        for i in vis {
            let c = candles[i]
            let vh = CGFloat(c.volume / maxVol) * h
            let color = c.close >= c.open ? Palette.green : Palette.red
            color.withAlphaComponent(0.16).setFill()
            NSRect(x: x(index: Double(i)) - w / 2, y: plot.maxY - vh, width: w, height: vh).fill()
        }
    }

    private func drawCandles() {
        guard let vis = visibleIndices() else { return }
        let w = max(1, (spacing * 0.72).rounded())
        for i in vis {
            let c = candles[i]
            let up = c.close >= c.open
            let color = up ? Palette.green : Palette.red
            let cx = x(index: Double(i)).rounded() + 0.5
            color.setStroke()
            let wick = NSBezierPath()
            wick.move(to: CGPoint(x: cx, y: y(c.high))); wick.line(to: CGPoint(x: cx, y: y(c.low)))
            wick.lineWidth = 1
            wick.stroke()
            let top = y(max(c.open, c.close)), bot = y(min(c.open, c.close))
            color.setFill()
            NSRect(x: cx - w / 2, y: top, width: w, height: max(1, bot - top)).fill()
        }
    }

    private func color(_ c: DrawingColor) -> NSColor {
        switch c {
        case .yellow: return Palette.yellow
        case .blue: return Palette.blue
        case .purple: return Palette.accent
        case .white: return Palette.text
        case .green: return Palette.green
        case .red: return Palette.red
        }
    }

    private func drawTrendlines() {
        for l in trendlines {
            let a = screen(l.a), b0 = screen(l.b)
            var b = b0
            if l.extendRight, abs(b0.x - a.x) > 0.01 {
                let slope = (b0.y - a.y) / (b0.x - a.x)
                let ex = b0.x >= a.x ? plot.maxX : plot.minX
                b = CGPoint(x: ex, y: a.y + slope * (ex - a.x))
            }
            let selected = l.id == selectedTrendline
            let hovered = isHovering(trendline: l.id)
            let path = NSBezierPath()
            path.move(to: a); path.line(to: b)
            path.lineWidth = selected || hovered ? 2.2 : 1.6
            path.lineCapStyle = .round
            color(l.color).setStroke()
            path.stroke()
            if selected || hovered {
                for p in [a, b0] {
                    let r = NSRect(x: p.x - 4.5, y: p.y - 4.5, width: 9, height: 9)
                    Palette.chartBg.setFill(); NSBezierPath(ovalIn: r).fill()
                    color(l.color).setStroke()
                    let o = NSBezierPath(ovalIn: r); o.lineWidth = 1.8; o.stroke()
                }
            }
        }
        // Line being drawn
        if let start = draftStart,
           let end = trendDraft ?? mouse.map({ chartPoint(at: $0, snap: commandDown) }) {
            let path = NSBezierPath()
            path.move(to: screen(start)); path.line(to: screen(end))
            path.lineWidth = 1.8
            path.setLineDash([5, 4], count: 2, phase: 0)
            Palette.yellow.setStroke()
            path.stroke()
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

    private func drawLastPrice() {
        guard lastPrice > 0 else { return }
        let yy = y(lastPrice).rounded() + 0.5
        guard yy >= plot.minY, yy <= plot.maxY else { return }
        let up = (candles.last.map { $0.close >= $0.open }) ?? true
        let col = up ? Palette.green : Palette.red
        col.withAlphaComponent(0.55).setStroke()
        hline(yy, from: plot.minX, to: plot.maxX, width: 1, dash: [2, 3])
        axisTag(lastPrice, at: yy, bg: col, fg: Palette.bg)
    }

    private func drawOrderLines() {
        for line in lines {
            let isDragging = isDraggingLine(line.id)
            let px = isDragging ? (dragPrice ?? line.price) : line.price
            let rawY = y(px)
            let offscreen = rawY < plot.minY + 12 || rawY > plot.maxY - 12
            let yy = min(max(rawY, plot.minY + 12), plot.maxY - 12).rounded() + 0.5
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
            let yy = y(g).rounded() + 0.5
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
        guard let m = mouse, plot.contains(m), case .none = drag else { return }
        Palette.muted.withAlphaComponent(0.45).setStroke()
        hline(m.y.rounded() + 0.5, from: plot.minX, to: plot.maxX, width: 1, dash: [3, 3])
        let v = NSBezierPath()
        v.move(to: CGPoint(x: m.x.rounded() + 0.5, y: plot.minY)); v.line(to: CGPoint(x: m.x.rounded() + 0.5, y: plot.maxY))
        v.lineWidth = 1; v.setLineDash([3, 3], count: 2, phase: 0); v.stroke()
        axisTag(price(y: m.y), at: m.y, bg: Palette.card, fg: Palette.text)
        guard !candles.isEmpty else { return }
        let t = time(index: index(x: m.x).rounded())
        timeFormatter.dateFormat = timeframe.milliseconds < 86_400_000 ? "EEE d MMM HH:mm" : "EEE d MMM yyyy"
        let s = timeFormatter.string(from: Date(timeIntervalSince1970: Double(t) / 1000))
        let font = NSFont.monospacedDigitSystemFont(ofSize: 10.5, weight: .medium)
        let w = (s as NSString).size(withAttributes: [.font: font]).width + 14
        let r = NSRect(x: m.x - w / 2, y: plot.maxY + 3, width: w, height: timeHeight - 6)
        Palette.card.setFill(); NSBezierPath(roundedRect: r, xRadius: 4, yRadius: 4).fill()
        text(s, at: CGPoint(x: m.x, y: r.midY), font: font, color: Palette.text, align: .center)
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
        if p.x > plot.maxX && p.y < plot.maxY { return .axis }
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
            var b = screen(l.b)
            let a = screen(l.a)
            if l.extendRight, abs(b.x - a.x) > 0.01 {
                let ex = b.x >= a.x ? plot.maxX : plot.minX
                b = CGPoint(x: ex, y: a.y + (b.y - a.y) / (b.x - a.x) * (ex - a.x))
            }
            if distance(p, toSegment: a, b) < 5 { return .trendline(l.id) }
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
        guard commandDown, let m = mouse, plot.contains(m) else { snapMarker = nil; return }
        let drawing = tool == .trendline || pendingTrendStart != nil
        var editing = false
        switch drag {
        case .trendNew, .endpoint: editing = true
        default: break
        }
        snapMarker = (drawing || editing) ? Snap.snap(time: time(index: index(x: m.x)), price: price(y: m.y), candles: candles, timeframe: timeframe) : nil
    }

    private func updateCursor() {
        if tool == .trendline { NSCursor.crosshair.set(); return }
        switch hover {
        case .line?, .closeHandle?: NSCursor.openHand.set()
        case .endpoint?: NSCursor.pointingHand.set()
        case .trendline?: NSCursor.pointingHand.set()
        case .axis?: NSCursor.resizeUpDown.set()
        case nil: NSCursor.crosshair.set()
        }
    }

    override func mouseMoved(with e: NSEvent) {
        mouse = location(e)
        commandDown = e.modifierFlags.contains(.command)
        hover = tool == .trendline ? nil : hitTarget(mouse!)
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
        let p = location(e)
        mouse = p
        commandDown = e.modifierFlags.contains(.command)
        computeRange()

        if e.clickCount == 2 && p.x > plot.maxX {
            autoScale = true
            needsDisplay = true
            return
        }

        if tool == .trendline {
            guard plot.contains(p) else { return }
            let pt = chartPoint(at: p, snap: commandDown)
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
        case .axis?:
            drag = .axis(startY: p.y, startRange: range)
        case nil:
            if selectedTrendline != nil { onTrendlineSelect?(nil) }
            drag = .pan(startX: p.x, startOffset: rightOffset, startY: p.y, startRange: range)
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
            let maxOffset = CGFloat(max(candles.count, 20))
            rightOffset = min(max(so - (p.x - sx) / spacing, -maxOffset + 5), plot.width / spacing - 5)
            if !autoScale {
                let dp = Double(p.y - sy) / Double(plot.height - 20) * (sr.hi - sr.lo)
                manualRange = (sr.lo + dp, sr.hi + dp)
            }
        case .axis(let sy, let sr):
            let factor = exp(Double(p.y - sy) / 180)
            let mid = (sr.lo + sr.hi) / 2, half = (sr.hi - sr.lo) / 2 * factor
            manualRange = (mid - half, mid + half)
            autoScale = false
        case .line(let id):
            dragPrice = price(y: p.y)
            onLineDrag?(id, dragPrice!, false)
        case .close:
            closeGhost = price(y: p.y)
        case .trendNew:
            trendDraft = chartPoint(at: p, snap: commandDown)
        case .endpoint(let id, let isA):
            guard var l = trendlines.first(where: { $0.id == id }) else { break }
            let pt = chartPoint(at: p, snap: commandDown)
            if isA { l.a = pt } else { l.b = pt }
            onTrendlineUpdate?(l)
        case .trendMove(let orig, let anchor):
            let cur = chartPoint(at: p, snap: false)
            var l = orig
            let dt = cur.time - anchor.time, dp = cur.price - anchor.price
            l.a = ChartPoint(time: orig.a.time + dt, price: orig.a.price + dp)
            l.b = ChartPoint(time: orig.b.time + dt, price: orig.b.price + dp)
            onTrendlineUpdate?(l)
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
        default:
            break
        }
        drag = .none
        dragPrice = nil
        closeGhost = nil
        trendDraft = nil
        mouse = p
        hover = tool == .trendline ? nil : hitTarget(p)
        updateCursor()
        needsDisplay = true
    }

    override func scrollWheel(with e: NSEvent) {
        let precise = e.hasPreciseScrollingDeltas
        let dx = e.scrollingDeltaX * (precise ? 1 : 8)
        let dy = e.scrollingDeltaY * (precise ? 1 : 8)
        if abs(dx) > abs(dy) {
            let maxOffset = CGFloat(max(candles.count, 20))
            rightOffset = min(max(rightOffset - dx / spacing, -maxOffset + 5), plot.width / spacing - 5)
        } else {
            zoom(by: 1 + dy * 0.008, anchorX: location(e).x)
        }
        needsDisplay = true
    }

    override func magnify(with e: NSEvent) {
        zoom(by: 1 + e.magnification, anchorX: location(e).x)
        needsDisplay = true
    }

    private func zoom(by factor: CGFloat, anchorX: CGFloat) {
        guard factor.isFinite, factor > 0 else { return }
        let ax = min(max(anchorX, plot.minX), plot.maxX)
        let idx = index(x: ax)
        spacing = min(max(spacing * factor, 2), 48)
        rightOffset = (plot.maxX - spacing / 2 - ax) / spacing - CGFloat(Double(candles.count - 1) - idx)
    }

    // MARK: Keyboard & context menu

    override func keyDown(with e: NSEvent) {
        switch e.keyCode {
        case 51, 117: // delete, forward delete
            if let id = selectedTrendline { onTrendlineDelete?(id) } else { super.keyDown(with: e) }
        case 53: // escape
            pendingTrendStart = nil
            trendDraft = nil
            if tool == .trendline { onToolFinished?() } else if selectedTrendline != nil { onTrendlineSelect?(nil) }
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
            menu.addItem(ClosureMenuItem(title: l.extendRight ? "Niet meer verlengen" : "Verleng naar rechts") { [weak self] in
                var n = l; n.extendRight.toggle(); self?.onTrendlineUpdate?(n)
            })
            let colors = NSMenuItem(title: "Kleur", action: nil, keyEquivalent: "")
            let sub = NSMenu()
            for c in DrawingColor.allCases {
                let item = ClosureMenuItem(title: colorName(c)) { [weak self] in var n = l; n.color = c; self?.onTrendlineUpdate?(n) }
                item.state = l.color == c ? .on : .off
                sub.addItem(item)
            }
            colors.submenu = sub
            menu.addItem(colors)
            menu.addItem(.separator())
            menu.addItem(ClosureMenuItem(title: "Verwijderen") { [weak self] in self?.onTrendlineDelete?(id) })
        case .line(.order(let oid))?:
            menu.addItem(ClosureMenuItem(title: "Annuleer order") { [weak self] in self?.onCancelOrder?(oid) })
        default:
            return nil
        }
        return menu
    }

    private func colorName(_ c: DrawingColor) -> String {
        switch c {
        case .yellow: return "Geel"
        case .blue: return "Blauw"
        case .purple: return "Paars"
        case .white: return "Wit"
        case .green: return "Groen"
        case .red: return "Rood"
        }
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

    /// Number of bars currently visible left of the newest candle.
    var demoVisibleBars: Int { max(10, Int(plot.width / spacing - rightOffset) - 2) }

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
