#if os(macOS)
import SwiftUI
import GripCore

/// Small settings popover for one indicator (opened with ⚙ on its chip).
struct IndicatorSettingsView: View {
    @EnvironmentObject var state: AppState
    let id: UUID

    private let swatches = ["#E5B84C", "#5AA2FF", "#FF8A65", "#81C784", "#C17CFF", "#4FC3F7", "#F06292", "#B39DDB", "#8A94A6", "#E7EBF2"]

    var body: some View {
        if let c = state.indicators.first(where: { $0.id == id }) {
            VStack(alignment: .leading, spacing: 12) {
                Text(T(c.kind.title)).font(.system(size: 13, weight: .semibold))
                if c.kind.hasLength && !c.kind.hasLines {
                    HStack {
                        Text(T("Lengte")).foregroundStyle(Theme.muted)
                        Spacer()
                        Stepper(value: Binding(get: { c.length }, set: { var n = c; n.length = max(1, min($0, 500)); state.updateIndicator(n) }), in: 1...500) {
                            TextField("", value: Binding(get: { c.length }, set: { var n = c; n.length = max(1, min($0, 500)); state.updateIndicator(n) }), format: .number)
                                .frame(width: 50)
                                .multilineTextAlignment(.trailing)
                        }
                    }
                    HStack(spacing: 6) {
                        ForEach(presets(c.kind), id: \.self) { n in
                            Button("\(n)") { var m = c; m.length = n; state.updateIndicator(m) }
                                .buttonStyle(ChipStyle(active: c.length == n))
                        }
                    }
                }
                if c.kind.hasLines {
                    // Every line has its own length and color (click the dot for the next color).
                    ForEach(Array(c.allLines.enumerated()), id: \.offset) { i, l in
                        HStack(spacing: 8) {
                            Circle().fill(Color(hex: l.color)).frame(width: 14, height: 14)
                                .onTapGesture {
                                    var n = c; var lines = c.allLines
                                    let k = (swatches.firstIndex(of: l.color) ?? -1) + 1
                                    lines[i].color = swatches[k % swatches.count]
                                    n.lines = lines; state.updateIndicator(n)
                                }
                                .help(T("Klik voor een andere kleur"))
                            Text(T("Lengte")).foregroundStyle(Theme.muted)
                            Spacer()
                            TextField("", value: Binding(get: { l.length }, set: { v in
                                var n = c; var lines = c.allLines
                                lines[i].length = max(1, min(v, 500))
                                n.lines = lines; state.updateIndicator(n)
                            }), format: .number)
                                .frame(width: 50).multilineTextAlignment(.trailing)
                            Button { state.removeIndicatorLine(c.kind, length: l.length) } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(Theme.dim) }
                                .buttonStyle(.plain)
                        }
                    }
                    Button(T("+ lijn")) {
                        let next = [9, 21, 50, 100, 200].first { n in !c.allLines.contains { $0.length == n } } ?? ((c.allLines.map(\.length).max() ?? 50) + 50)
                        state.addIndicator(c.kind, length: next)
                    }
                    .buttonStyle(ChipStyle(active: false))
                    .disabled(c.allLines.count >= 6)
                }
                if c.kind == .smc {
                    let o = c.smc ?? SMCOptions()
                    smcToggle(T("Marktstructuur (BOS / CHoCH)"), c, \.structure)
                    smcToggle(T("Order blocks"), c, \.orderBlocks)
                    smcToggle(T("Fair value gaps"), c, \.fairValueGaps)
                    smcToggle(T("Liquiditeit (gelijke highs / lows)"), c, \.liquidity)
                    smcToggle(T("Premium / discount"), c, \.premiumDiscount)
                    Stepper(value: Binding(get: { o.swing }, set: { v in var n = c; var x = o; x.swing = v; n.smc = x; state.updateIndicator(n) }), in: 2...20) {
                        HStack { Text(T("Gevoeligheid swings")).foregroundStyle(Theme.muted); Spacer(); Text("\(o.swing)").monospacedDigit() }
                    }
                    .help(T("Aantal candles links en rechts dat lager (hoger) moet zijn. Hoger = minder, grotere swings."))
                }
                if c.kind != .volume && !c.kind.hasLines && c.kind != .smc {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(T("Kleur")).foregroundStyle(Theme.muted)
                        HStack(spacing: 6) {
                            ForEach(swatches, id: \.self) { hex in
                                Circle().fill(Color(hex: hex)).frame(width: 16, height: 16)
                                    .overlay(Circle().stroke(Color.white, lineWidth: c.color == hex ? 2 : 0))
                                    .onTapGesture { var n = c; n.color = hex; state.updateIndicator(n) }
                            }
                        }
                    }
                }
                if c.kind != .volume && c.kind != .smc {
                    Picker(T("Dikte"), selection: Binding(get: { c.width }, set: { var n = c; n.width = $0; state.updateIndicator(n) })) {
                        ForEach([0.5, 1.0, 1.5, 2.0, 3.0], id: \.self) { Text(T("\(Fmt.number($0, decimals: $0 == $0.rounded() ? 0 : 1)) pt")).tag($0) }
                    }
                }
                HStack {
                    Button(c.visible ? T("Verbergen") : T("Tonen")) { state.toggleIndicator(id) }
                    Spacer()
                    Button(T("Verwijderen"), role: .destructive) { state.removeIndicator(id) }
                }
            }
            .font(.system(size: 12))
            .padding(14)
            .frame(width: 260)
        } else {
            Text(T("Indicator verwijderd")).padding(14)
        }
    }

    private func smcToggle(_ title: String, _ c: IndicatorConfig, _ kp: WritableKeyPath<SMCOptions, Bool>) -> some View {
        Toggle(title, isOn: Binding(get: { (c.smc ?? SMCOptions())[keyPath: kp] }, set: { v in
            var n = c
            var o = c.smc ?? SMCOptions()
            o[keyPath: kp] = v
            n.smc = o
            state.updateIndicator(n)
        }))
    }

    private func presets(_ k: IndicatorKind) -> [Int] {
        switch k {
        case .ema, .sma: return [9, 21, 50, 100, 200]
        case .rsi: return [7, 14, 21]
        case .bollinger: return [10, 20, 50]
        default: return []
        }
    }
}
#endif
