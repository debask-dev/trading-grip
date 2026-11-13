import XCTest
@testable import GripCore

final class RiskTests: XCTestCase {
    func testOnePercentRiskSizing() throws {
        // $25k account, 1% risk, entry 96,950, stop 96,750 → $250 / ($200 + fees)
        let r = try XCTUnwrap(RiskCalculator.calculate(RiskInput(accountValue: 25_000, riskPercent: 1, entry: 96_950, stopLoss: 96_750,
                                                                  takeProfit: 98_400, maxLeverage: 40, szDecimals: 5, takerFeeRate: 0)))
        XCTAssertTrue(r.isLong)
        XCTAssertEqual(r.riskUsd, 250, accuracy: 0.001)
        XCTAssertEqual(r.size, 1.25, accuracy: 1e-9)
        XCTAssertEqual(r.leverage, 5)
        XCTAssertEqual(try XCTUnwrap(r.rewardRisk), 7.25, accuracy: 1e-9)
        XCTAssertTrue(r.warnings.isEmpty)
    }

    func testFeesReduceSize() throws {
        let noFee = try XCTUnwrap(RiskCalculator.calculate(RiskInput(accountValue: 10_000, riskPercent: 1, entry: 100, stopLoss: 99, takeProfit: nil, maxLeverage: 20, szDecimals: 2, takerFeeRate: 0)))
        let fee = try XCTUnwrap(RiskCalculator.calculate(RiskInput(accountValue: 10_000, riskPercent: 1, entry: 100, stopLoss: 99, takeProfit: nil, maxLeverage: 20, szDecimals: 2)))
        XCTAssertLessThan(fee.size, noFee.size)
        // Loss at the stop including fees never exceeds the chosen risk.
        XCTAssertLessThanOrEqual(fee.size * (1 + 0.00045 * 199), 100.0001)
    }

    func testShortAndLeverageCap() throws {
        let r = try XCTUnwrap(RiskCalculator.calculate(RiskInput(accountValue: 1_000, riskPercent: 2, entry: 50, stopLoss: 50.05, takeProfit: 49, maxLeverage: 10, szDecimals: 1, takerFeeRate: 0)))
        XCTAssertFalse(r.isLong)
        XCTAssertEqual(r.leverage, 10)
        XCTAssertFalse(r.warnings.isEmpty)
    }

    func testPriceRounding() {
        XCTAssertEqual(HLFormat.roundPrice(97_253.7, szDecimals: 5), 97_254)
        XCTAssertEqual(HLFormat.roundPrice(3_456.789, szDecimals: 4), 3_456.8)
        XCTAssertEqual(HLFormat.roundPrice(0.123456, szDecimals: 0), 0.12346)
        XCTAssertEqual(HLFormat.roundPrice(1.234567, szDecimals: 2), 1.2346)
        XCTAssertEqual(HLFormat.roundSize(0.123456, szDecimals: 3, down: true), 0.123)
    }
}

final class TradeBuilderTests: XCTestCase {
    func fill(_ coin: String = "BTC", px: Double, sz: Double, buy: Bool, t: Int64, start: Double, dir: String, pnl: Double = 0, fee: Double = 1) -> Fill {
        Fill(coin: coin, px: px, sz: sz, isBuy: buy, time: t, startPosition: start, dir: dir, closedPnl: pnl, fee: fee, oid: t, tid: t)
    }

    func testRoundTripWithPartialCloses() {
        let fills = [
            fill(px: 100, sz: 2, buy: true, t: 1, start: 0, dir: "Open Long"),
            fill(px: 110, sz: 0.5, buy: false, t: 2, start: 2, dir: "Close Long", pnl: 5),
            fill(px: 120, sz: 1.5, buy: false, t: 3, start: 1.5, dir: "Close Long", pnl: 30),
        ]
        let plan = TradePlan(coin: "BTC", isLong: true, entry: 100, stopLoss: 95, takeProfit: 120, riskUsd: 10, riskPercent: 1,
                             createdAt: Date(timeIntervalSince1970: 0))
        let trades = TradeBuilder.build(fills: fills, plans: [plan])
        XCTAssertEqual(trades.count, 1)
        let t = trades[0]
        XCTAssertTrue(t.isLong)
        XCTAssertEqual(t.size, 2)
        XCTAssertEqual(t.avgEntry, 100)
        XCTAssertEqual(t.avgExit, (110 * 0.5 + 120 * 1.5) / 2, accuracy: 1e-9)
        XCTAssertEqual(t.netPnl, 35 - 3, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(t.rMultiple), 3.2, accuracy: 1e-9)
    }

    func testFlipCreatesTwoTrades() {
        let fills = [
            fill(px: 100, sz: 1, buy: true, t: 1, start: 0, dir: "Open Long", fee: 0),
            fill(px: 90, sz: 3, buy: false, t: 2, start: 1, dir: "Long > Short", pnl: -10, fee: 0),
            fill(px: 80, sz: 2, buy: true, t: 3, start: -2, dir: "Close Short", pnl: 20, fee: 0),
        ]
        let trades = TradeBuilder.build(fills: fills).sorted { $0.openTime < $1.openTime }
        XCTAssertEqual(trades.count, 2)
        XCTAssertTrue(trades[0].isLong)
        XCTAssertEqual(trades[0].netPnl, -10)
        XCTAssertFalse(trades[1].isLong)
        XCTAssertEqual(trades[1].size, 2)
        XCTAssertEqual(trades[1].netPnl, 20)
    }

    func testSkipsPositionOpenedBeforeHistory() {
        let fills = [
            fill(px: 100, sz: 1, buy: false, t: 1, start: 1, dir: "Close Long", pnl: 5),
            fill(px: 100, sz: 1, buy: false, t: 2, start: 0, dir: "Open Short"),
            fill(px: 95, sz: 1, buy: true, t: 3, start: -1, dir: "Close Short", pnl: 5),
        ]
        let trades = TradeBuilder.build(fills: fills)
        XCTAssertEqual(trades.count, 1)
        XCTAssertFalse(trades[0].isLong)
    }

    func testStats() {
        let fills = [
            fill(px: 100, sz: 1, buy: true, t: 1, start: 0, dir: "Open Long", fee: 0),
            fill(px: 110, sz: 1, buy: false, t: 2, start: 1, dir: "Close Long", pnl: 10, fee: 0),
            fill(px: 100, sz: 1, buy: true, t: 3, start: 0, dir: "Open Long", fee: 0),
            fill(px: 95, sz: 1, buy: false, t: 4, start: 1, dir: "Close Long", pnl: -5, fee: 0),
        ]
        let s = TradeStats.from(TradeBuilder.build(fills: fills))
        XCTAssertEqual(s.count, 2)
        XCTAssertEqual(s.winRate, 0.5)
        XCTAssertEqual(try XCTUnwrap(s.profitFactor), 2)
        XCTAssertEqual(TradeBuilder.equityCurve(TradeBuilder.build(fills: fills)).last?.value, 5)
    }
}

final class DrawingTests: XCTestCase {
    func testSnapToNearestOHLC() {
        let candles = (0..<10).map { i in
            Candle(time: Int64(i) * 60_000, open: 100, high: 110, low: 90, close: 105)
        }
        let p = Snap.snap(time: 3 * 60_000 + 10_000, price: 108.5, candles: candles, timeframe: .m1)
        XCTAssertEqual(p, ChartPoint(time: 180_000, price: 110))
        let q = Snap.snap(time: 7 * 60_000, price: 91, candles: candles, timeframe: .m1)
        XCTAssertEqual(q?.price, 90)
        XCTAssertNil(Snap.snap(time: 60 * 60_000, price: 100, candles: candles, timeframe: .m1))
    }

    func testTrendlinePersistence() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store = JSONStore(directory: dir)
        let line = Trendline(coin: "ETH", a: ChartPoint(time: 0, price: 3000), b: ChartPoint(time: 3_600_000, price: 3100), extendRight: true)
        try store.saveNow([line], to: "trendlines")
        let loaded = store.load([Trendline].self, from: "trendlines")
        XCTAssertEqual(loaded?.first?.id, line.id)
        XCTAssertEqual(loaded?.first?.price(at: 1_800_000) ?? 0, 3050, accuracy: 1e-9)
    }

    func testPrivacyMasking() {
        XCTAssertEqual(Fmt(hidden: true).usd(1234), "$•••")
        XCTAssertEqual(Fmt(hidden: true).signedUsd(-5), "−$•••")
        XCTAssertEqual(Fmt(hidden: false).signedUsd(1234.5), "+$1.235")
        XCTAssertEqual(Fmt(hidden: true).size(1.25, coin: "BTC", decimals: 3), "••• BTC")
        XCTAssertEqual(Fmt.percent(0.0258), "+2,58%")
    }
}
