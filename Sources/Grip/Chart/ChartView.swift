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

    private func configure(_ v: ChartCanvas) {
        let s = state
        v.resetKey = "\(s.network.rawValue)-\(s.coin)-\(s.timeframe.rawValue)-\(s.chartResetToken)"
        v.candles = s.candles
        v.timeframe = s.timeframe
        v.coin = s.coin
        v.magnet = s.magnet
        v.style = s.chartStyle
        v.newLineAppearance = s.lineAppearance
        v.markers = s.chartMarkers
        v.tradeLinks = s.chartTradeLinks
        v.highlightTradeID = s.highlightTradeID
        v.focus = s.chartFocus
        v.lastPrice = s.price
        v.lines = s.chartLines
        v.trendlines = s.coinTrendlines
        v.selectedTrendline = s.selectedTrendline
        v.tool = s.tool
        v.hasPosition = s.position != nil
        v.isLoading = s.loadingCandles

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
        v.needsDisplay = true
    }
}
#endif
