#if os(macOS)
import SwiftUI
import GripCore

// MARK: - Margin budget ("room for N positions") and total risk of all stops

extension AppState {
    var budgetActive: Bool { maxPositions > 1 && account.accountValue > 0 }

    /// Margin one position may use: the account split over N positions.
    var slotMargin: Double { account.accountValue / Double(max(maxPositions, 1)) }

    /// Loss if every stop is hit, and the markets that have no stop (risk unknown).
    var openRisk: (usd: Double, unprotected: [String]) {
        var total = 0.0
        var none: [String] = []
        for p in account.positions {
            guard let sl = stopOrder(p.coin) else { none.append(p.coin); continue }
            let dir: Double = p.isLong ? 1 : -1
            total += max(0, abs(p.size) * (dir * (p.entryPx - sl.displayPx) + feeRates.taker * sl.displayPx))
        }
        return (total, none)
    }

    var openRiskPercent: Double { account.accountValue > 0 ? openRisk.usd / account.accountValue * 100 : 0 }

    /// Warnings for the order being prepared, on top of the plan's own.
    func budgetWarnings(_ pl: Plan) -> [String] {
        guard account.accountValue > 0, let t = ticket, !t.reduceOnly else { return [] }
        var w: [String] = []
        if budgetActive && !pl.isAdd {
            let open = account.positions.count
            if open >= maxPositions {
                w.append(T("Je hebt al \(open) posities open; je budget is \(maxPositions) (Instellingen → Risico)."))
            }
            let margin = pl.size * pl.avgEntry / Double(max(t.leverage ?? pl.leverage, 1))
            if margin > slotMargin * 1.01 {
                w.append(T("Gebruikt \(fmt.usd(margin)) marge, meer dan één vak (\(fmt.usd(slotMargin)) = 1/\(maxPositions) van je account)."))
            }
        }
        if maxTotalRiskPct > 0, let risk = pl.riskUsd {
            let added = risk - (pl.existingRiskUsd ?? 0)
            let total = (openRisk.usd + added) / account.accountValue * 100
            if total > maxTotalRiskPct + 0.001 {
                w.append(T("Totaal risico van al je stops wordt \(Fmt.number(total, decimals: 2))%, boven je max van \(Fmt.number(maxTotalRiskPct, decimals: 1))%."))
            }
        }
        return w
    }
}

/// In the status line: one block per position slot, filled by the margin it uses; and total risk of all stops.
struct MarginBudgetView: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        if state.budgetActive || state.maxTotalRiskPct > 0 {
            Divider().frame(height: 14)
            Text(T("BUDGET")).font(.system(size: 9.5, weight: .semibold)).tracking(0.6).foregroundStyle(Theme.dim)
            if state.budgetActive {
                let fills = state.account.positions.map { min($0.marginUsed / max(state.slotMargin, 1e-9), 1.5) }
                HStack(spacing: 3) {
                    ForEach(0..<state.maxPositions, id: \.self) { i in
                        let f = i < fills.count ? fills[i] : 0
                        GeometryReader { g in
                            ZStack(alignment: .leading) {
                                RoundedRectangle(cornerRadius: 2).stroke(f > 1 ? Theme.orange : Theme.line)
                                RoundedRectangle(cornerRadius: 2).fill(f > 1 ? Theme.orange : Theme.blue).frame(width: g.size.width * CGFloat(min(f, 1)))
                            }
                        }
                        .frame(width: 18, height: 8)
                    }
                }
                .help(T("Marge per positie: \(state.fmt.usd(state.slotMargin)) (1/\(state.maxPositions) van je account). \(state.account.positions.count) van \(state.maxPositions) in gebruik."))
            }
            if state.maxTotalRiskPct > 0 {
                let r = state.openRisk
                let pct = state.openRiskPercent
                Text(T("risico \(Fmt.number(pct, decimals: 1))%/\(Fmt.number(state.maxTotalRiskPct, decimals: 0))%\(r.unprotected.isEmpty ? "" : "+")"))
                    .foregroundStyle(pct > state.maxTotalRiskPct || !r.unprotected.isEmpty ? Theme.orange : Theme.muted)
                    .help(r.unprotected.isEmpty
                          ? T("Verlies als al je stops geraakt worden: \(state.fmt.usd(r.usd))")
                          : T("Verlies bij alle stops: \(state.fmt.usd(r.usd)), plus onbekend risico: \(r.unprotected.joined(separator: ", ")) zonder stop"))
            }
        }
    }
}

struct RiskSettingsView: View {
    @EnvironmentObject var state: AppState
    var body: some View {
        Form {
            Section {
                Stepper(value: $state.maxPositions, in: 1...10) {
                    HStack {
                        Text(T("Max. gelijktijdige posities"))
                        Spacer()
                        Text(state.maxPositions == 1 ? "uit" : "\(state.maxPositions)").monospacedDigit()
                    }
                }
            } header: {
                Text(T("Marge-budget"))
            } footer: {
                Text(T("Bij 3 posities mag één trade standaard hooguit ⅓ van je account als marge gebruiken. In Risico kiest Grip dan een hefboom die daarin past; in Bedrag staat \"1 vak\" in het lijstje. Grip waarschuwt als je erboven komt."))
            }
            Section {
                Picker(T("Max. totaal risico"), selection: $state.maxTotalRiskPct) {
                    Text(T("Uit")).tag(0.0)
                    ForEach([2.0, 3.0, 4.0, 5.0, 8.0, 10.0], id: \.self) { Text(T("\(Fmt.number($0, decimals: 0))% van je account")).tag($0) }
                }
            } header: {
                Text(T("Totaal risico"))
            } footer: {
                Text(T("Wat je verliest als al je stops tegelijk geraakt worden. Een positie zonder stop telt als onbekend risico en kleurt de statusbalk oranje."))
            }
        }
        .formStyle(.grouped)
    }
}
#endif
