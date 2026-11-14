import Foundation

/// Indicators Grip can draw. Overlays sit on the price, panes get their own strip under the chart.
public enum IndicatorKind: String, Codable, CaseIterable, Sendable {
    case volume, ema, sma, vwap, bollinger, rsi

    public enum Placement: Sendable { case volume, overlay, pane }

    public var placement: Placement {
        switch self {
        case .volume: return .volume
        case .ema, .sma, .vwap, .bollinger: return .overlay
        case .rsi: return .pane
        }
    }

    public var title: String {
        switch self {
        case .volume: return "Volume"
        case .ema: return "EMA (exponentieel gemiddelde)"
        case .sma: return "SMA (gewoon gemiddelde)"
        case .vwap: return "VWAP (volume-gewogen, per dag)"
        case .bollinger: return "Bollinger Bands"
        case .rsi: return "RSI"
        }
    }

    public var hasLength: Bool { self != .volume && self != .vwap }

    public var defaultLength: Int {
        switch self {
        case .ema: return 50
        case .sma: return 20
        case .bollinger: return 20
        case .rsi: return 14
        case .volume, .vwap: return 0
        }
    }

    public var defaultColor: String {
        switch self {
        case .volume: return "#8A94A6"
        case .ema: return "#E5B84C"
        case .sma: return "#5AA2FF"
        case .vwap: return "#C17CFF"
        case .bollinger: return "#4FC3F7"
        case .rsi: return "#B39DDB"
        }
    }
}

public struct IndicatorConfig: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var kind: IndicatorKind
    public var length: Int
    public var color: String
    public var width: Double
    public var visible: Bool
    /// Pane indicators: folded to a thin strip with only the name.
    public var collapsed: Bool

    public init(id: UUID = UUID(), kind: IndicatorKind, length: Int? = nil, color: String? = nil, width: Double = 1.5, visible: Bool = true, collapsed: Bool = false) {
        self.id = id; self.kind = kind; self.length = length ?? kind.defaultLength; self.color = color ?? kind.defaultColor
        self.width = width; self.visible = visible; self.collapsed = collapsed
    }

    /// Short name for the legend chip: "EMA 50", "RSI 14", "Vol".
    public var shortName: String {
        switch kind {
        case .volume: return "Vol"
        case .vwap: return "VWAP"
        case .ema: return "EMA \(length)"
        case .sma: return "SMA \(length)"
        case .bollinger: return "BB \(length)"
        case .rsi: return "RSI \(length)"
        }
    }

    public static let defaults: [IndicatorConfig] = [IndicatorConfig(kind: .volume)]
}

/// The calculations (one value per candle, nil where there is not enough history yet).
public enum IndicatorMath {
    public static func sma(_ v: [Double], length n: Int) -> [Double?] {
        guard n > 0, v.count >= n else { return Array(repeating: nil, count: v.count) }
        var out = [Double?](repeating: nil, count: v.count)
        var sum = v[0..<n].reduce(0, +)
        out[n - 1] = sum / Double(n)
        for i in n..<v.count {
            sum += v[i] - v[i - n]
            out[i] = sum / Double(n)
        }
        return out
    }

    /// Seeded with the SMA of the first `n` values, like TradingView.
    public static func ema(_ v: [Double], length n: Int) -> [Double?] {
        guard n > 0, v.count >= n else { return Array(repeating: nil, count: v.count) }
        var out = [Double?](repeating: nil, count: v.count)
        let k = 2.0 / Double(n + 1)
        var e = v[0..<n].reduce(0, +) / Double(n)
        out[n - 1] = e
        for i in n..<v.count {
            e = v[i] * k + e * (1 - k)
            out[i] = e
        }
        return out
    }

    /// Wilder's RSI.
    public static func rsi(_ closes: [Double], length n: Int) -> [Double?] {
        guard n > 0, closes.count > n else { return Array(repeating: nil, count: closes.count) }
        var out = [Double?](repeating: nil, count: closes.count)
        var gain = 0.0, loss = 0.0
        for i in 1...n {
            let d = closes[i] - closes[i - 1]
            if d > 0 { gain += d } else { loss -= d }
        }
        gain /= Double(n); loss /= Double(n)
        func value() -> Double { loss == 0 ? 100 : 100 - 100 / (1 + gain / loss) }
        out[n] = value()
        if closes.count > n + 1 {
            for i in (n + 1)..<closes.count {
                let d = closes[i] - closes[i - 1]
                gain = (gain * Double(n - 1) + max(d, 0)) / Double(n)
                loss = (loss * Double(n - 1) + max(-d, 0)) / Double(n)
                out[i] = value()
            }
        }
        return out
    }

    /// Volume-weighted average price of (high+low+close)/3, restarting every UTC day.
    public static func vwap(_ candles: [Candle]) -> [Double?] {
        var out = [Double?](repeating: nil, count: candles.count)
        var day: Int64 = -1
        var pv = 0.0, vol = 0.0
        for (i, c) in candles.enumerated() {
            let d = c.time / 86_400_000
            if d != day { day = d; pv = 0; vol = 0 }
            let tp = (c.high + c.low + c.close) / 3
            pv += tp * c.volume
            vol += c.volume
            out[i] = vol > 0 ? pv / vol : tp
        }
        return out
    }

    /// Middle (SMA), upper and lower band at `k` standard deviations.
    public static func bollinger(_ closes: [Double], length n: Int, k: Double = 2) -> (mid: [Double?], upper: [Double?], lower: [Double?]) {
        let mid = sma(closes, length: n)
        var up = [Double?](repeating: nil, count: closes.count)
        var lo = up
        if n > 0 && closes.count >= n {
            for i in (n - 1)..<closes.count {
                guard let m = mid[i] else { continue }
                let window = closes[(i - n + 1)...i]
                let sd = (window.reduce(0) { $0 + ($1 - m) * ($1 - m) } / Double(n)).squareRoot()
                up[i] = m + k * sd
                lo[i] = m - k * sd
            }
        }
        return (mid, up, lo)
    }
}
