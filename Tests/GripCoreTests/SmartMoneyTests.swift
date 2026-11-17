import XCTest
@testable import GripCore

final class SmartMoneyTests: XCTestCase {
    /// Candle with open, high, low, close; time is the index.
    private func k(_ i: Int, _ o: Double, _ h: Double, _ l: Double, _ c: Double) -> Candle {
        Candle(time: Int64(i) * 60_000, open: o, high: h, low: l, close: c, volume: 1)
    }

    func testSwingsNeedLowerCandlesOnBothSides() {
        // Highs: 10 11 15 11 10 → one swing high at index 2. Lows: 9 10 12 10 9 → no swing low inside.
        let c = [k(0, 9.5, 10, 9, 9.8), k(1, 10, 11, 10, 10.8), k(2, 11, 15, 12, 14), k(3, 11, 11, 10, 10.2), k(4, 10, 10, 9, 9.2)]
        let s = SmartMoney.swings(c, n: 2)
        XCTAssertEqual(s, [SMCResult.Swing(index: 2, price: 15, isHigh: true)])
    }

    func testBullishFairValueGapAndItsFill() {
        // Candle 0 tops at 10, candle 2 bottoms at 12: gap 10…12 around candle 1. Candle 4 trades back down to 9.5.
        let c = [k(0, 9, 10, 8, 9.8), k(1, 10, 13, 9.9, 12.8), k(2, 12.8, 14, 12, 13.5), k(3, 13.5, 14, 12.5, 13), k(4, 13, 13.2, 9.5, 10)]
        let g = SmartMoney.fairValueGaps(c)
        XCTAssertEqual(g.count, 1)
        XCTAssertEqual(g.first, SMCResult.Zone(start: 1, top: 12, bottom: 10, isBullish: true, end: 4))
    }

    func testCloseAboveSwingHighIsABreakWithAnOrderBlock() {
        // Up to a top at index 2 (high 15), down to index 5, then candle 7 closes above 15.
        let c = [k(0, 10, 11, 9.5, 10.8), k(1, 10.8, 13, 10.5, 12.8), k(2, 12.8, 15, 12.5, 14), k(3, 14, 14.2, 12, 12.2),
                 k(4, 12.2, 12.5, 11, 11.2), k(5, 11.2, 11.5, 10.6, 11.4), k(6, 11.4, 14.5, 11.3, 14.2), k(7, 14.2, 16.5, 14, 16.2),
                 k(8, 16.2, 17, 16, 16.8), k(9, 16.8, 17.5, 16.5, 17.2)]
        var o = SMCOptions()
        o.swing = 2
        let r = SmartMoney.compute(c, options: o)
        XCTAssertEqual(r.breaks.first, SMCResult.Break(from: 2, at: 7, price: 15, isBullish: true, isChange: false))
        // Last falling candle before the break is index 4 (index 5 and 6 rose).
        XCTAssertEqual(r.orderBlocks.first, SMCResult.Zone(start: 4, top: 12.5, bottom: 11, isBullish: true, end: nil))
    }
}

final class PortfolioFiguresTests: XCTestCase {
    private func trade(_ coin: String, long: Bool, pnl: Double, hour: Int, r: Double? = nil) -> ClosedTrade {
        let close = Date(timeIntervalSince1970: 1_700_000_000 + Double(hour) * 3600)
        return ClosedTrade(id: "\(coin)-\(hour)", coin: coin, isLong: long, openTime: close.addingTimeInterval(-600), closeTime: close,
                           size: 1, avgEntry: 100, avgExit: 100 + pnl, grossPnl: pnl, fees: 0, fills: 2, rMultiple: r)
    }

    func testKeyFigures() {
        // +100, −50, +30, −40 in this order: tops at 100, falls to 50 (drawdown 50), 80, then 40 (drawdown 60).
        let s = PortfolioFigures.compute([trade("BTC", long: true, pnl: 100, hour: 0, r: 2), trade("ETH", long: false, pnl: -50, hour: 1, r: -1),
                                    trade("BTC", long: true, pnl: 30, hour: 2), trade("ETH", long: true, pnl: -40, hour: 3)])
        XCTAssertEqual(s.count, 4)
        XCTAssertEqual(s.winRate, 0.5, accuracy: 1e-9)
        XCTAssertEqual(s.net, 40, accuracy: 1e-9)
        XCTAssertEqual(s.profitFactor ?? 0, 130.0 / 90.0, accuracy: 1e-9)
        XCTAssertEqual(s.maxDrawdown, 60, accuracy: 1e-9)
        XCTAssertEqual(s.avgWinR, 2)
        XCTAssertEqual(s.avgLossR, -1)
        XCTAssertEqual(s.byCoin.first?.name, "BTC")
        XCTAssertEqual(s.byCoin.first?.net ?? 0, 130, accuracy: 1e-9)
        XCTAssertEqual(s.bySide.map(\.count), [3, 1])
    }
}
