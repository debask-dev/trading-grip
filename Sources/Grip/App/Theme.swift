#if os(macOS)
import SwiftUI
import AppKit

extension NSColor {
    convenience init(hex: UInt32, alpha: CGFloat = 1) {
        self.init(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
    }
}

enum Palette {
    static let bg = NSColor(hex: 0x0B0E13)
    static let chartBg = NSColor(hex: 0x0E1218)
    static let panel = NSColor(hex: 0x141922)
    static let card = NSColor(hex: 0x1A202B)
    static let line = NSColor(hex: 0x232A36)
    static let grid = NSColor(hex: 0x171C25)
    static let text = NSColor(hex: 0xE7EBF2)
    static let muted = NSColor(hex: 0x8A94A6)
    static let dim = NSColor(hex: 0x5D6676)
    static let green = NSColor(hex: 0x2FD394)
    static let red = NSColor(hex: 0xFF5C6C)
    static let blue = NSColor(hex: 0x5AA2FF)
    static let orange = NSColor(hex: 0xFFB547)
    static let accent = NSColor(hex: 0x7C6CFF)
    static let yellow = NSColor(hex: 0xF5D547)
}

enum Theme {
    static let bg = Color(nsColor: Palette.bg)
    static let panel = Color(nsColor: Palette.panel)
    static let card = Color(nsColor: Palette.card)
    static let line = Color(nsColor: Palette.line)
    static let text = Color(nsColor: Palette.text)
    static let muted = Color(nsColor: Palette.muted)
    static let dim = Color(nsColor: Palette.dim)
    static let green = Color(nsColor: Palette.green)
    static let red = Color(nsColor: Palette.red)
    static let blue = Color(nsColor: Palette.blue)
    static let orange = Color(nsColor: Palette.orange)
    static let accent = Color(nsColor: Palette.accent)

    static func pnl(_ v: Double) -> Color { v >= 0 ? green : red }
}

struct Card<Content: View>: View {
    var title: String?
    var trailing: AnyView? = nil
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let title {
                HStack {
                    Text(title.uppercased())
                        .font(.system(size: 10.5, weight: .semibold))
                        .tracking(0.8)
                        .foregroundStyle(Theme.muted)
                    Spacer()
                    if let trailing { trailing }
                }
            }
            content
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12).fill(Theme.card))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.line, lineWidth: 1))
    }
}

struct SidePill: View {
    var isLong: Bool
    var body: some View {
        Text(isLong ? T("LONG") : T("SHORT"))
            .font(.system(size: 10.5, weight: .bold))
            .padding(.horizontal, 7).padding(.vertical, 3)
            .background(RoundedRectangle(cornerRadius: 5).fill((isLong ? Theme.green : Theme.red).opacity(0.15)))
            .foregroundStyle(isLong ? Theme.green : Theme.red)
    }
}

struct KV: View {
    var key_: String
    var value: String
    var color: Color = Theme.text
    init(_ key: String, _ value: String, color: Color = Theme.text) { key_ = key; self.value = value; self.color = color }
    var body: some View {
        HStack {
            Text(key_).foregroundStyle(Theme.muted)
            Spacer()
            Text(value).font(.system(.body, design: .monospaced).weight(.medium)).foregroundStyle(color)
        }
        .font(.system(size: 12.5))
    }
}

/// The same hover highlight as `HoverButtonStyle`, for menus (a Menu takes no button style of its own).
private struct HoverHighlight: ViewModifier {
    @State private var hovering = false
    func body(content: Content) -> some View {
        content
            .background(RoundedRectangle(cornerRadius: 6).fill(Color.white.opacity(hovering ? 0.09 : 0)))
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.white.opacity(hovering ? 0.08 : 0), lineWidth: 1))
            .contentShape(Rectangle())
            .onHover { hovering = $0 }
            .animation(.easeOut(duration: 0.12), value: hovering)
    }
}

extension View {
    func hoverHighlight() -> some View { modifier(HoverHighlight()) }
}

/// Button style for small header/toolbar buttons: hover highlight, pressed state and a full-size click area.
struct HoverButtonStyle: ButtonStyle {
    var active: Bool
    var activeFill: Color = Theme.accent.opacity(0.32)

    func makeBody(configuration: Configuration) -> some View {
        HoverBody(configuration: configuration, active: active, activeFill: activeFill)
    }

    private struct HoverBody: View {
        let configuration: ButtonStyleConfiguration
        let active: Bool
        let activeFill: Color
        @State private var hovering = false

        var body: some View {
            configuration.label
                .foregroundStyle(active || hovering ? Theme.text : Theme.muted)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(active ? activeFill : Color.white.opacity(configuration.isPressed ? 0.16 : (hovering ? 0.09 : 0)))
                )
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.white.opacity(hovering && !active ? 0.08 : 0), lineWidth: 1))
                .scaleEffect(configuration.isPressed ? 0.95 : 1)
                .contentShape(Rectangle())
                .onHover { hovering = $0 }
                .animation(.easeOut(duration: 0.12), value: hovering)
                .animation(.easeOut(duration: 0.08), value: configuration.isPressed)
        }
    }
}

extension View {
    func mono(_ size: CGFloat, _ weight: Font.Weight = .medium) -> some View {
        font(.system(size: size, weight: weight, design: .monospaced))
    }
}
#endif

#if os(macOS)
import SwiftUI

/// Colour labels for market tabs (right-click a tab).
enum TabColor {
    static let all: [(name: String, dot: String, color: Color)] = [
        ("Rood", "🔴", Theme.red), ("Oranje", "🟠", Theme.orange), ("Geel", "🟡", Color(nsColor: Palette.yellow)),
        ("Groen", "🟢", Theme.green), ("Blauw", "🔵", Theme.blue), ("Paars", "🟣", Theme.accent),
    ]
    static func color(_ i: Int?) -> Color? { i.flatMap { all.indices.contains($0) ? all[$0].color : nil } }
}
/// The "G" from the app icon, drawn in code so the menu bar gets a crisp template image.
enum GripLogo {
    static let menuBar: NSImage = {
        let size: CGFloat = 18
        let img = NSImage(size: NSSize(width: size, height: size), flipped: false) { _ in
            // App icon geometry (1024 canvas): ring radius 256, stroke 104, opening top-right, bar just below the middle.
            let s: CGFloat = 15.5 / 616
            let c = NSPoint(x: size / 2, y: size / 2)
            let r = 256 * s
            let path = NSBezierPath()
            path.appendArc(withCenter: c, radius: r, startAngle: 42, endAngle: 360, clockwise: false)
            path.line(to: NSPoint(x: c.x + 40 * s, y: c.y))
            path.lineWidth = 104 * s
            path.lineCapStyle = .round
            path.lineJoinStyle = .round
            NSColor.black.setStroke()
            path.stroke()
            return true
        }
        img.isTemplate = true
        img.accessibilityDescription = "Grip"
        return img
    }()
}
#endif
