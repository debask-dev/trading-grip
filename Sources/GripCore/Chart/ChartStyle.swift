import Foundation

/// How candles and the chart background look. Colors are hex strings ("#RRGGBB" or "#RRGGBBAA").
public struct ChartStyle: Codable, Equatable, Sendable {
    public var upBody: String
    public var downBody: String
    public var upBorder: String
    public var downBorder: String
    public var upWick: String
    public var downWick: String
    public var showBorders: Bool
    public var showWicks: Bool
    public var hollowUp: Bool
    public var showGrid: Bool
    public var showVolume: Bool

    public init(upBody: String, downBody: String, upBorder: String, downBorder: String, upWick: String, downWick: String,
                showBorders: Bool = false, showWicks: Bool = true, hollowUp: Bool = false, showGrid: Bool = true, showVolume: Bool = true) {
        self.upBody = upBody; self.downBody = downBody; self.upBorder = upBorder; self.downBorder = downBorder
        self.upWick = upWick; self.downWick = downWick; self.showBorders = showBorders; self.showWicks = showWicks
        self.hollowUp = hollowUp; self.showGrid = showGrid; self.showVolume = showVolume
    }

    public static let grip = ChartStyle(upBody: "#2FD394", downBody: "#FF5C6C", upBorder: "#2FD394", downBorder: "#FF5C6C",
                                        upWick: "#2FD394", downWick: "#FF5C6C")
    public static let classic = ChartStyle(upBody: "#26A69A", downBody: "#EF5350", upBorder: "#26A69A", downBorder: "#EF5350",
                                           upWick: "#26A69A", downWick: "#EF5350")
    public static let hollow = ChartStyle(upBody: "#2FD394", downBody: "#FF5C6C", upBorder: "#2FD394", downBorder: "#FF5C6C",
                                          upWick: "#2FD394", downWick: "#FF5C6C", showBorders: true, hollowUp: true)
    public static let monochrome = ChartStyle(upBody: "#E7EBF2", downBody: "#5D6676", upBorder: "#E7EBF2", downBorder: "#8A94A6",
                                              upWick: "#C9CFDA", downWick: "#8A94A6", showBorders: true, hollowUp: true)
    public static let blueOrange = ChartStyle(upBody: "#5AA2FF", downBody: "#FFB547", upBorder: "#5AA2FF", downBorder: "#FFB547",
                                              upWick: "#5AA2FF", downWick: "#FFB547")

    public static let presets: [(name: String, style: ChartStyle)] = [
        ("Grip", .grip), ("Klassiek", .classic), ("Hol", .hollow), ("Monochroom", .monochrome), ("Blauw/oranje", .blueOrange),
    ]

    public var presetName: String? { Self.presets.first { $0.style == self }?.name }

    /// Quick colors offered for candles (first one: the orange the user uses in TradingView).
    public static let swatches = ["#E68538", "#2FD394", "#26A69A", "#089981", "#FF5C6C", "#EF5350", "#F23645", "#5AA2FF", "#E7EBF2", "#5D6676"]

    /// Sets body, border and wick color for rising or falling candles at once.
    public mutating func setColor(_ hex: String, up: Bool) {
        if up { upBody = hex; upBorder = hex; upWick = hex } else { downBody = hex; downBorder = hex; downWick = hex }
    }
}

public struct RGBA: Equatable, Sendable {
    public var r: Double, g: Double, b: Double, a: Double

    public init(r: Double, g: Double, b: Double, a: Double = 1) { self.r = r; self.g = g; self.b = b; self.a = a }

    public init?(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6 || s.count == 8, let v = UInt64(s, radix: 16) else { return nil }
        if s.count == 6 {
            r = Double((v >> 16) & 0xFF) / 255; g = Double((v >> 8) & 0xFF) / 255; b = Double(v & 0xFF) / 255; a = 1
        } else {
            r = Double((v >> 24) & 0xFF) / 255; g = Double((v >> 16) & 0xFF) / 255; b = Double((v >> 8) & 0xFF) / 255; a = Double(v & 0xFF) / 255
        }
    }

    public var hex: String {
        let c = { (x: Double) in Int((min(max(x, 0), 1) * 255).rounded()) }
        return a >= 0.999 ? String(format: "#%02X%02X%02X", c(r), c(g), c(b)) : String(format: "#%02X%02X%02X%02X", c(r), c(g), c(b), c(a))
    }
}
