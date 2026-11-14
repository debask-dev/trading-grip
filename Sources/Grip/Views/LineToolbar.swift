#if os(macOS)
import SwiftUI
import AppKit
import GripCore

extension Color {
    init(hex: String) {
        let c = RGBA(hex: hex) ?? RGBA(r: 1, g: 1, b: 1)
        self.init(.sRGB, red: c.r, green: c.g, blue: c.b, opacity: c.a)
    }

    var hexString: String {
        guard let c = NSColor(self).usingColorSpace(.sRGB) else { return "#FFFFFF" }
        return RGBA(r: Double(c.redComponent), g: Double(c.greenComponent), b: Double(c.blueComponent), a: Double(c.alphaComponent)).hex
    }
}

/// Binding to a hex color string, for SwiftUI's ColorPicker.
func hexBinding(_ get: @escaping () -> String, _ set: @escaping (String) -> Void) -> Binding<Color> {
    Binding(get: { Color(hex: get()) }, set: { set($0.hexString) })
}

/// Floating toolbar for the selected trendline (like TradingView): color, width, style, extend, delete.
struct LineToolbar: View {
    @EnvironmentObject var state: AppState
    let line: Trendline

    var body: some View {
        HStack(spacing: 10) {
            HStack(spacing: 5) {
                ForEach(LineSwatches.all, id: \.self) { hex in
                    Button { state.styleSelectedLine { $0.color = hex } } label: {
                        Circle().fill(Color(hex: hex)).frame(width: 16, height: 16)
                            .overlay(Circle().stroke(Color.white, lineWidth: line.color.uppercased() == hex ? 2 : 0))
                            .frame(width: 22, height: 24)
                    }
                    .buttonStyle(HoverButtonStyle(active: false))
                    .demoAnchor("lt-\(hex)")
                }
                ColorPicker("", selection: hexBinding({ line.color }, { hex in state.styleSelectedLine { $0.color = hex } }), supportsOpacity: true)
                    .labelsHidden()
                    .frame(width: 26)
                    .help(T("Eigen kleur"))
            }
            divider
            HStack(spacing: 2) {
                ForEach([0.5, 1.0, 2.0, 3.0, 4.0], id: \.self) { w in
                    toggleButton(active: line.width == w, help: T("Dikte \(Fmt.number(w, decimals: w < 1 ? 1 : 0)) pt")) {
                        Capsule().fill(Theme.text.opacity(w < 1 ? 0.8 : 1)).frame(width: 16, height: max(w, 0.75))
                    } action: { state.styleSelectedLine { $0.width = w } }
                    .demoAnchor("lt-width-\(w)")
                }
            }
            divider
            HStack(spacing: 2) {
                ForEach(LineDash.allCases, id: \.self) { d in
                    toggleButton(active: line.dash == d, help: dashName(d)) {
                        DashSample(dash: d).frame(width: 18, height: 2)
                    } action: { state.styleSelectedLine { $0.dash = d } }
                    .demoAnchor("lt-dash-\(d.rawValue)")
                }
            }
            divider
            HStack(spacing: 2) {
                toggleButton(active: line.extendLeft, help: T("Verleng naar links")) {
                    Image(systemName: "arrow.left.to.line").font(.system(size: 11, weight: .semibold))
                } action: { state.styleSelectedLine { $0.extendLeft.toggle() } }
                toggleButton(active: line.extendRight, help: T("Verleng naar rechts (de toekomst in)")) {
                    Image(systemName: "arrow.right.to.line").font(.system(size: 11, weight: .semibold))
                } action: { state.styleSelectedLine { $0.extendRight.toggle() } }
                .demoAnchor("lt-extend-right")
            }
            divider
            Button { state.deleteSelectedTrendline() } label: {
                Image(systemName: "trash").font(.system(size: 12)).frame(width: 26, height: 24)
            }
            .buttonStyle(HoverButtonStyle(active: false))
            .help(T("Verwijderen (⌫)"))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(RoundedRectangle(cornerRadius: 10).fill(Theme.card.opacity(0.97)))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.line))
        .shadow(color: .black.opacity(0.4), radius: 12, y: 6)
    }

    private var divider: some View { Rectangle().fill(Theme.line).frame(width: 1, height: 18) }

    private func toggleButton<Label: View>(active: Bool, help: String, @ViewBuilder label: () -> Label, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            label().frame(width: 26, height: 24)
        }
        .buttonStyle(HoverButtonStyle(active: active))
        .help(help)
    }

    private func dashName(_ d: LineDash) -> String {
        switch d {
        case .solid: return T("Doorgetrokken")
        case .dashed: return T("Gestreept")
        case .dotted: return T("Gestippeld")
        }
    }
}

struct DashSample: View {
    var dash: LineDash
    var color: Color = Theme.text
    var body: some View {
        GeometryReader { g in
            Path { p in
                p.move(to: CGPoint(x: 0, y: g.size.height / 2))
                p.addLine(to: CGPoint(x: g.size.width, y: g.size.height / 2))
            }
            .stroke(color, style: StrokeStyle(lineWidth: 2, lineCap: dash == .dotted ? .round : .butt,
                                              dash: dash == .solid ? [] : (dash == .dashed ? [5, 3] : [0.1, 4])))
        }
    }
}

// MARK: - Settings: Chart tab

struct ChartSettingsView: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        Form {
            Section(T("Stijl")) {
                Picker(T("Voorinstelling"), selection: Binding(get: { state.chartStyle.presetName ?? T("Eigen") }, set: { name in
                    if let p = ChartStyle.presets.first(where: { $0.name == name }) { state.chartStyle = p.style }
                })) {
                    ForEach(ChartStyle.presets, id: \.name) { Text($0.name).tag($0.name) }
                    if state.chartStyle.presetName == nil { Text(T("Eigen")).tag(T("Eigen")) }
                }
                CandlePreview(style: state.chartStyle).frame(height: 70)
            }

            Section(T("Candles")) {
                colorRow(T("Stijgend"), body: \.upBody, border: \.upBorder, wick: \.upWick)
                colorRow(T("Dalend"), body: \.downBody, border: \.downBorder, wick: \.downWick)
                Toggle(T("Wicks tonen"), isOn: $state.chartStyle.showWicks)
                Toggle(T("Randen tonen"), isOn: $state.chartStyle.showBorders)
                Toggle(T("Stijgende candles hol"), isOn: $state.chartStyle.hollowUp)
            }

            Section(T("Chart")) {
                Toggle(T("Rasterlijnen"), isOn: $state.chartStyle.showGrid)
                Toggle(T("Volume"), isOn: Binding(
                    get: { state.indicators.contains { $0.kind == .volume && $0.visible } },
                    set: { on in
                        if let i = state.indicators.firstIndex(where: { $0.kind == .volume }) { state.indicators[i].visible = on }
                        else if on { state.addIndicator(.volume) }
                    }))
                Picker(T("Koop/verkoop-markeringen"), selection: $state.markerDays) {
                    Text(T("Uit")).tag(0)
                    Text(T("Alleen huidige trade")).tag(-1)
                    Text(T("Laatste 7 dagen")).tag(7)
                    Text(T("Laatste 30 dagen")).tag(30)
                    Text(T("Alles")).tag(3650)
                }
            }

            Section(T("Screenshots (⇧⌘S)")) {
                LabeledContent(T("Map")) {
                    HStack {
                        Text((state.screenshotFolder as NSString).abbreviatingWithTildeInPath)
                            .lineLimit(1).truncationMode(.middle).foregroundStyle(.secondary)
                        Button(T("Kies…")) { state.chooseScreenshotFolder() }
                        Button(T("Open")) { state.revealScreenshotFolder() }
                    }
                }
                Toggle(T("Ook naar het klembord kopiëren"), isOn: $state.screenshotToClipboard)
            }

            Section {
                LabeledContent(T("Kleur")) {
                    ColorPicker("", selection: hexBinding({ state.lineAppearance.color }, { state.lineAppearance.color = $0 }), supportsOpacity: true).labelsHidden()
                }
                Picker(T("Dikte"), selection: $state.lineAppearance.width) {
                    ForEach([0.5, 1.0, 2.0, 3.0, 4.0], id: \.self) { Text(T("\(Fmt.number($0, decimals: $0 < 1 ? 1 : 0)) pt")).tag($0) }
                }
                Picker(T("Stijl"), selection: $state.lineAppearance.dash) {
                    Text(T("Doorgetrokken")).tag(LineDash.solid)
                    Text(T("Gestreept")).tag(LineDash.dashed)
                    Text(T("Gestippeld")).tag(LineDash.dotted)
                }
                Toggle(T("Nieuwe lijnen naar rechts verlengen (de toekomst in)"), isOn: $state.lineAppearance.extendRight)
                Toggle(T("Magneet: altijd snappen op open/high/low/close"), isOn: $state.magnet)
            } header: {
                Text(T("Trendlijnen"))
            } footer: {
                Text(T("Met ⌘ ingedrukt zet je de magneet tijdelijk om. Klik een lijn aan voor de werkbalk met kleur, dikte, stijl en verlengen."))
            }

            Section {
                Button(T("Standaardstijl herstellen")) {
                    state.chartStyle = .grip
                    state.lineAppearance = LineAppearance()
                }
            }
        }
        .formStyle(.grouped)
    }

    private func colorRow(_ title: String, body: WritableKeyPath<ChartStyle, String>, border: WritableKeyPath<ChartStyle, String>, wick: WritableKeyPath<ChartStyle, String>) -> some View {
        let up = title == "Stijgend"
        return VStack(alignment: .leading, spacing: 8) {
            LabeledContent(title) {
                HStack(spacing: 14) {
                    picker(T("Body"), body)
                    picker(T("Rand"), border)
                    picker(T("Wick"), wick)
                }
            }
            HStack(spacing: 6) {
                Text(T("Snel:")).font(.caption).foregroundStyle(Theme.muted)
                ForEach(ChartStyle.swatches, id: \.self) { hex in
                    Button { state.chartStyle.setColor(hex, up: up) } label: {
                        RoundedRectangle(cornerRadius: 4).fill(Color(hex: hex)).frame(width: 18, height: 18)
                            .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.white, lineWidth: state.chartStyle[keyPath: body] == hex ? 2 : 0))
                            .frame(width: 24, height: 24)
                    }
                    .buttonStyle(HoverButtonStyle(active: false))
                    .help(hex)
                }
            }
        }
    }

    private func picker(_ label: String, _ key: WritableKeyPath<ChartStyle, String>) -> some View {
        HStack(spacing: 4) {
            Text(label).font(.caption).foregroundStyle(Theme.muted)
            ColorPicker("", selection: hexBinding({ state.chartStyle[keyPath: key] }, { state.chartStyle[keyPath: key] = $0 }), supportsOpacity: true)
                .labelsHidden()
        }
    }
}

/// A few sample candles in the chosen style.
struct CandlePreview: View {
    var style: ChartStyle
    private let samples: [(o: Double, h: Double, l: Double, c: Double)] = [
        (40, 62, 30, 55), (55, 60, 35, 38), (38, 50, 20, 46), (46, 75, 44, 70), (70, 72, 48, 52), (52, 66, 45, 63), (63, 80, 58, 76),
    ]

    var body: some View {
        Canvas { ctx, size in
            let w = size.width / CGFloat(samples.count)
            func y(_ v: Double) -> CGFloat { size.height - CGFloat(v / 85) * size.height }
            for (i, s) in samples.enumerated() {
                let up = s.c >= s.o
                let cx = w * (CGFloat(i) + 0.5)
                let bw = w * 0.55
                if style.showWicks {
                    var wick = Path()
                    wick.move(to: CGPoint(x: cx, y: y(s.h))); wick.addLine(to: CGPoint(x: cx, y: y(s.l)))
                    ctx.stroke(wick, with: .color(Color(hex: up ? style.upWick : style.downWick)), lineWidth: 1.5)
                }
                let rect = CGRect(x: cx - bw / 2, y: y(max(s.o, s.c)), width: bw, height: max(2, y(min(s.o, s.c)) - y(max(s.o, s.c))))
                let hollow = up && style.hollowUp
                if hollow {
                    ctx.fill(Path(rect), with: .color(Color(nsColor: Palette.chartBg)))
                } else {
                    ctx.fill(Path(rect), with: .color(Color(hex: up ? style.upBody : style.downBody)))
                }
                if style.showBorders || hollow {
                    ctx.stroke(Path(rect), with: .color(Color(hex: up ? style.upBorder : style.downBorder)), lineWidth: hollow ? 2 : 1)
                }
            }
        }
        .background(RoundedRectangle(cornerRadius: 8).fill(Color(nsColor: Palette.chartBg)))
    }
}
#endif
