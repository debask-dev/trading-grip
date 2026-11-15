import Foundation

/// Horizontal viewport of the chart: how wide a bar is and how far the newest bar sits from the right edge.
/// Behaviour follows TradingView's Lightweight Charts (zoom per wheel event capped at 10%, zoom anchored
/// under the cursor, time-axis drag scaling anchored to the right edge, at least 2 bars always visible).
public struct ChartViewport: Equatable, Sendable {
    public static let defaultSpacing = 9.0
    public static let defaultRightOffset = 8.0
    public static let minSpacing = 1.5

    /// Pixels per bar.
    public var barSpacing: Double = ChartViewport.defaultSpacing
    /// Empty bars right of the newest candle (negative = scrolled back into history).
    public var rightOffset: Double = ChartViewport.defaultRightOffset
    /// Width of the plot area in points.
    public var width: Double = 600
    public var barCount: Int = 0

    public init() {}

    public var maxSpacing: Double { max(Self.minSpacing, width * 0.5) }

    public func x(index i: Double) -> Double {
        width - (Double(barCount - 1) - i + rightOffset) * barSpacing - barSpacing / 2
    }

    public func index(x: Double) -> Double {
        Double(barCount - 1) + rightOffset - (width - barSpacing / 2 - x) / barSpacing
    }

    /// Range of bar indices that are (partly) visible.
    public var visibleRange: ClosedRange<Int>? {
        guard barCount > 0 else { return nil }
        let a = max(0, Int(index(x: 0).rounded(.down)))
        let b = min(barCount - 1, Int(index(x: width).rounded(.up)))
        return a <= b ? a...b : nil
    }

    public mutating func clamp() {
        barSpacing = min(max(barSpacing, Self.minSpacing), maxSpacing)
        // Keep at least two bars on screen in both directions.
        let maxOffset = width / barSpacing - 2
        let minOffset = -(Double(max(barCount, 2)) - 2)
        rightOffset = min(max(rightOffset, minOffset), max(minOffset, maxOffset))
    }

    public mutating func reset() {
        barSpacing = Self.defaultSpacing
        rightOffset = Self.defaultRightOffset
        clamp()
    }

    /// Mouse wheel / trackpad zoom. `delta` in points, positive = zoom in. Anchored at `anchorX`.
    public mutating func zoom(wheelDelta delta: Double, anchorX: Double) {
        guard delta != 0, barCount > 0 else { return }
        let scale = (delta > 0 ? 1.0 : -1.0) * min(1, abs(delta) / 100)
        zoom(scale: scale, anchorX: anchorX)
    }

    /// Changes bar spacing by `scale` × 10% (scale in -1...1), keeping the bar under `anchorX` in place.
    public mutating func zoom(scale: Double, anchorX: Double) {
        let anchor = min(max(anchorX, 0), width)
        let before = index(x: anchor)
        barSpacing = min(max(barSpacing + scale * barSpacing / 10, Self.minSpacing), maxSpacing)
        rightOffset += before - index(x: anchor)
        clamp()
    }

    /// Sets the bar spacing while keeping bar `idx` at x-position `x` (used for smooth, animated zooming).
    public mutating func setSpacing(_ s: Double, keepingIndex idx: Double, atX x: Double) {
        guard barCount > 0 else { barSpacing = min(max(s, Self.minSpacing), maxSpacing); return }
        barSpacing = min(max(s, Self.minSpacing), maxSpacing)
        rightOffset = idx - Double(barCount - 1) + (width - barSpacing / 2 - x) / barSpacing
        clamp()
    }

    /// Continuous zoom by a factor (trackpad), anchored at `anchorX`. No per-event cap, so fast gestures follow the fingers.
    public mutating func zoom(factor: Double, anchorX: Double) {
        guard factor.isFinite, factor > 0 else { return }
        let a = min(max(anchorX, 0), width)
        setSpacing(barSpacing * factor, keepingIndex: index(x: a), atX: a)
    }

    /// Pinch zoom (magnification, e.g. 0.05 = 5% larger).
    public mutating func pinch(magnification m: Double, anchorX: Double) {
        let anchor = min(max(anchorX, 0), width)
        let before = index(x: anchor)
        barSpacing = min(max(barSpacing * (1 + m), Self.minSpacing), maxSpacing)
        rightOffset += before - index(x: anchor)
        clamp()
    }

    /// Scroll by pixels (positive = content moves right, i.e. back in time).
    public mutating func pan(pixels dx: Double) {
        rightOffset -= dx / barSpacing
        clamp()
    }

    /// Dragging the time axis from `startX` to `x`: scales bar spacing, right edge stays put.
    public mutating func scaleTimeAxis(startSpacing: Double, startX: Double, x: Double) {
        let current = min(max(width - x, 0), width)
        let start = min(max(width - startX, 0), width)
        guard current > 0, start > 0 else { return }
        barSpacing = startSpacing * current / start
        clamp()
    }
}

/// Momentum after releasing a drag (same model as Lightweight Charts: exponential damping per millisecond).
public struct KineticScroll: Sendable {
    public static let damping = 0.997          // speed multiplier per ms
    public static let minSpeed = 0.2           // px/ms
    public static let maxSpeed = 7.0           // px/ms
    public static let minMove = 15.0           // px over the sampled window

    private var samples: [(pos: Double, t: Double)] = []

    public init() {}

    public mutating func add(position: Double, timeMs: Double) {
        samples.append((position, timeMs))
        samples.removeAll { timeMs - $0.t > 100 }
    }

    /// Initial speed (px/ms) for a fling, or nil when the release was not a fling.
    public func releaseSpeed(atMs now: Double) -> Double? {
        guard let last = samples.last, let first = samples.first, last.t - first.t > 5, now - last.t < 60 else { return nil }
        let distance = last.pos - first.pos
        guard abs(distance) >= Self.minMove else { return nil }
        let v = distance / (last.t - first.t)
        guard abs(v) >= Self.minSpeed else { return nil }
        return (v > 0 ? 1 : -1) * min(abs(v), Self.maxSpeed)
    }

    /// Distance travelled `t` ms after release with initial speed `v`.
    public static func offset(speed v: Double, afterMs t: Double) -> Double {
        let ln = log(damping)
        return v * (pow(damping, t) - 1) / ln
    }

    /// How long the fling lasts until it moves less than half a pixel.
    public static func duration(speed v: Double) -> Double {
        let ln = log(damping)
        return max(0, log(0.5 * ln / -abs(v)) / ln)
    }
}

/// Result of measuring between two points (⇧ + click).
public struct MeasureResult: Equatable, Sendable {
    public var priceChange: Double
    public var percent: Double
    public var bars: Int
    public var durationMs: Int64
    public var volume: Double
}

public enum ChartMath {
    public static func measure(from a: ChartPoint, to b: ChartPoint, candles: [Candle], timeframe: Timeframe) -> MeasureResult {
        let change = b.price - a.price
        let pct = a.price != 0 ? change / a.price : 0
        let lo = min(a.time, b.time), hi = max(a.time, b.time)
        var bars = Int((Double(hi - lo) / Double(timeframe.milliseconds)).rounded())
        if let i = Snap.nearestIndex(time: lo, candles: candles), let j = Snap.nearestIndex(time: hi, candles: candles),
           hi <= (candles.last?.time ?? 0), lo >= (candles.first?.time ?? 0) {
            bars = j - i
        }
        let volume = candles.filter { $0.time >= lo && $0.time <= hi }.reduce(0) { $0 + $1.volume }
        return MeasureResult(priceChange: change, percent: pct, bars: (b.time >= a.time ? 1 : -1) * bars, durationMs: b.time - a.time, volume: volume)
    }

    /// "45m", "3u 20m", "2d 4u", "5w 2d"
    public static func durationText(ms: Int64) -> String {
        let s = abs(ms) / 1000
        let m = s / 60, h = m / 60, d = h / 24
        if s < 60 { return "\(s)s" }
        if m < 60 { return "\(m)m" }
        if h < 24 { return m % 60 == 0 ? "\(h)u" : "\(h)u \(m % 60)m" }
        if d < 14 { return h % 24 == 0 ? "\(d)d" : "\(d)d \(h % 24)u" }
        return d % 7 == 0 ? "\(d / 7)w" : "\(d / 7)w \(d % 7)d"
    }

    /// Time left until the next candle opens, formatted like TradingView ("04:12", "1:04:12", "2d 03u").
    public static func countdown(lastCandleOpen open: Int64, timeframe: Timeframe, nowMs now: Int64) -> String {
        let tf = timeframe.milliseconds
        var close = open + tf
        if close <= now { close += ((now - close) / tf + 1) * tf }
        let left = max(0, (close - now) / 1000)
        let d = left / 86400, h = (left % 86400) / 3600, m = (left % 3600) / 60, s = left % 60
        if d > 0 { return String(format: "%dd %02du", d, h) }
        if h > 0 { return String(format: "%d:%02d:%02d", h, m, s) }
        return String(format: "%02d:%02d", m, s)
    }

    /// TradingView-style candle body width: about 80% of the spacing, snapped to device pixels.
    public static func candleBodyWidth(spacing: Double, pixelRatio: Double) -> Double {
        let specialFrom = 2.5, specialTo = 4.0
        let px: Double
        if spacing >= specialFrom && spacing <= specialTo {
            px = max(floor(pixelRatio), min(floor(3 * pixelRatio), floor(spacing * pixelRatio)))
        } else {
            let coeff = 1 - 0.2 * atan(max(specialTo, spacing) - specialTo) / (Double.pi * 0.5)
            px = max(floor(pixelRatio), min(floor(spacing * coeff * pixelRatio), floor(spacing * pixelRatio)))
        }
        return px / pixelRatio
    }
}

/// Labels on the time axis. They sit on round times (every 15 min, hour, 4 h, day …) in local time,
/// so the same candles keep their label while you scroll: nothing jumps or flickers.
public enum TimeAxis {
    static let minute: Int64 = 60_000
    static let hour: Int64 = 3_600_000
    static let day: Int64 = 86_400_000
    /// Candidate label spacings, smallest first.
    static let steps: [Int64] = [
        minute, 5 * minute, 15 * minute, 30 * minute,
        hour, 2 * hour, 3 * hour, 4 * hour, 6 * hour, 12 * hour,
        day, 2 * day, 7 * day, 14 * day, 28 * day, 91 * day, 182 * day, 364 * day,
    ]

    /// Smallest round step that leaves at least `minGap` points between labels.
    public static func step(timeframe: Timeframe, barSpacing: Double, minGap: Double = 110) -> Int64 {
        let tf = timeframe.milliseconds
        let needed = Double(tf) * minGap / max(barSpacing, 0.01)
        return steps.first { $0 >= tf && Double($0) >= needed } ?? steps.last!
    }

    /// True when a candle opening at `time` gets a label. `utcOffset` is the local offset in ms, so
    /// "every 4 hours" means 00:00, 04:00 … on your clock. Daily and weekly candles open at UTC midnight:
    /// those count whole candles instead.
    public static func isLabel(time: Int64, step: Int64, timeframe: Timeframe, utcOffset: Int64) -> Bool {
        func mod(_ a: Int64, _ b: Int64) -> Int64 { ((a % b) + b) % b }
        let tf = timeframe.milliseconds
        if tf >= day { return mod(time / tf, max(1, step / tf)) == 0 }
        let local = time + utcOffset
        if step < day { return mod(local, step) == 0 }
        guard mod(local, day) == 0 else { return false }
        let days = (local - mod(local, day)) / day - 4      // day 0 = Monday 5 Jan 1970
        return mod(days, step / day) == 0
    }
}
