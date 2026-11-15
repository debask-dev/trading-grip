#if os(macOS)
import SwiftUI
import GripCore

struct ChartView: NSViewRepresentable {
    @ObservedObject var state: AppState

    func makeNSView(context: Context) -> ChartCanvas {
        let v = ChartCanvas()
        state.chartCanvas = v
        configure(v)
        return v
    }

    func updateNSView(_ v: ChartCanvas, context: Context) {
        configure(v)
    }

    /// Only redraw when something visible changed (SwiftUI calls this on every state change).
    private func configure(_ v: ChartCanvas) {
        let s = state
        var dirty = false
        func set<T: Equatable>(_ kp: ReferenceWritableKeyPath<ChartCanvas, T>, _ value: T) {
            if v[keyPath: kp] != value { v[keyPath: kp] = value; dirty = true }
        }
        set(\.resetKey, "\(s.network.rawValue)-\(s.coin)-\(s.timeframe.rawValue)-\(s.chartResetToken)")
        set(\.candles, s.candles)
        set(\.timeframe, s.timeframe)
        set(\.coin, s.coin)
        set(\.magnet, s.magnet)
        set(\.style, s.chartStyle)
        set(\.newLineAppearance, s.lineAppearance)
        set(\.markers, s.chartMarkers)
        set(\.tradeLinks, s.chartTradeLinks)
        set(\.highlightTradeID, s.highlightTradeID)
        set(\.focus, s.chartFocus)
        set(\.lines, s.chartLines)
        set(\.meter, s.chartMeter)
        set(\.breakEvenPrice, s.breakEven)
        set(\.words, ChartWords(noStop: T("⚠ geen stop"), fromPrice: T("vanaf koers")))
        set(\.trendlines, s.coinTrendlines)
        set(\.selectedTrendline, s.selectedTrendline)
        set(\.tool, s.tool)
        set(\.hasPosition, s.position != nil)
        set(\.isLoading, s.loadingCandles)
        set(\.indicators, s.indicators)
        set(\.legendCollapsed, s.legendCollapsed)
        if v.lastPrice <= 0 { v.lastPrice = s.price }
        let labelKey = "\(s.chartResetLabels)|\(s.hideAmounts)|\(s.ticket.map { "\($0)" } ?? "")|\(s.position.map { "\($0.size)|\($0.entryPx)" } ?? "")|\(s.riskPercent)|\(s.account.accountValue)|\(s.tpDraft.map { "\($0.levels.map(\.pct))" } ?? "")|\(s.coinOrders.map { "\($0.oid):\($0.size)" })"
        set(\.labelKey, labelKey)

        v.labelFor = { id, px in s.lineLabel(id, at: px) }
        v.closeLabelFor = { px in s.closeGhostLabel(at: px) }
        v.onLineDrag = { id, px, ended in s.chartLineDragged(id, price: px, ended: ended) }
        v.onCloseDrag = { px in Task { await s.closeAtLimit(price: px) } }
        v.onCancelOrder = { oid in Task { await s.cancelOrder(oid) } }
        v.onTrendlineCreate = { a, b in s.addTrendline(a, b) }
        v.onTrendlineUpdate = { l in s.updateTrendline(l) }
        v.onTrendlineSelect = { id in s.selectedTrendline = id }
        v.onTrendlineDelete = { id in s.deleteTrendline(id) }
        v.onToolFinished = { s.tool = .cursor }
        v.onHorizontalCreate = { p in s.addHorizontal(p) }
        v.onTimeframeTyped = { tf in s.timeframe = tf }
        v.onLineClose = { id in s.lineClosed(id) }
        v.onTradeSelect = { id in s.highlightTradeID = id }
        v.priceMenuItems = { px in s.priceMenu(at: px) }
        v.onIndicatorToggle = { id in s.toggleIndicator(id) }
        v.onIndicatorRemove = { id in s.removeIndicator(id) }
        v.onPaneCollapse = { id in s.togglePaneCollapsed(id) }
        v.onLegendCollapse = { c in s.legendCollapsed = c }
        v.makeIndicatorSettings = { id in
            NSHostingController(rootView: IndicatorSettingsView(id: id).environmentObject(s).preferredColorScheme(.dark))
        }
        if dirty { v.needsDisplay = true }
    }
}
#endif
