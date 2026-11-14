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

    func testSizeOverrideAndLadder() throws {
        var input = RiskInput(accountValue: 10_000, riskPercent: 1, entry: 100, stopLoss: 98, takeProfit: nil, maxLeverage: 20, szDecimals: 2, takerFeeRate: 0, entryFeeRate: 0)
        input.sizeOverride = 75                                   // 75 × $2 = $150 → 1.5% (over the 1% max)
        input.leverageOverride = 3
        input.takeProfits = [TPTarget(price: 104, fraction: 0.5), TPTarget(price: 110, fraction: 0.5)]
        let r = try XCTUnwrap(RiskCalculator.calculate(input))
        XCTAssertEqual(r.size, 75)
        XCTAssertEqual(r.riskUsd, 150, accuracy: 1e-9)
        XCTAssertEqual(r.riskPercentActual, 1.5, accuracy: 1e-9)
        XCTAssertTrue(r.warnings.contains { $0.contains("meer dan je max") })
        XCTAssertEqual(r.leverage, 3)
        XCTAssertEqual(r.minLeverage, 1)
        XCTAssertEqual(try XCTUnwrap(r.rewardRisk), 3.5, accuracy: 1e-9)   // avg move 7 / risk 2
        XCTAssertEqual(try XCTUnwrap(r.potentialProfit), 75 * 0.5 * 4 + 75 * 0.5 * 10, accuracy: 1e-9)
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

final class ExecutionTests: XCTestCase {
    func f(_ oid: Int64, px: Double, sz: Double, buy: Bool, t: Int64, start: Double, dir: String, pnl: Double = 0, fee: Double = 0.1, tid: Int64? = nil) -> Fill {
        Fill(coin: "BTC", px: px, sz: sz, isBuy: buy, time: t, startPosition: start, dir: dir, closedPnl: pnl, fee: fee, oid: oid, tid: tid ?? t)
    }

    func testScaledInAndOutWithLabelsFeesAndFunding() {
        let fills = [
            f(1, px: 100, sz: 1, buy: true, t: 1, start: 0, dir: "Open Long"),
            f(1, px: 102, sz: 1, buy: true, t: 2, start: 1, dir: "Open Long"),        // same order, partial fill
            f(2, px: 98, sz: 2, buy: true, t: 3, start: 2, dir: "Open Long"),         // second entry
            f(3, px: 110, sz: 2, buy: false, t: 4, start: 4, dir: "Close Long", pnl: 18),
            f(4, px: 120, sz: 1, buy: false, t: 5, start: 2, dir: "Close Long", pnl: 21),
            f(5, px: 95, sz: 1, buy: false, t: 6, start: 1, dir: "Close Long", pnl: -4),
        ]
        let kinds: [Int64: OrderKindTag] = [1: .limit, 2: .limit, 3: .takeProfit, 4: .takeProfit, 5: .stopLoss]
        let funding = [FundingPayment(time: 3, coin: "BTC", usdc: -0.5), FundingPayment(time: 99, coin: "BTC", usdc: -9)]
        let a = TradeBuilder.analyze(fills: fills, funding: funding, orderKinds: kinds)
        XCTAssertEqual(a.closed.count, 1)
        let t = a.closed[0]
        XCTAssertEqual(t.executions.map(\.label), ["E1", "E2", "TP1", "TP2", "SL"])
        XCTAssertEqual(t.entries[0].size, 2)
        XCTAssertEqual(t.entries[0].price, 101, accuracy: 1e-9)          // VWAP of the two partial fills
        XCTAssertEqual(t.avgEntry, 99.5, accuracy: 1e-9)
        XCTAssertEqual(t.avgExit, (110 * 2 + 120 + 95) / 4, accuracy: 1e-9)
        XCTAssertEqual(t.funding, -0.5, accuracy: 1e-9)                 // only during the trade
        XCTAssertEqual(t.netPnl, 35 - 0.6 - 0.5, accuracy: 1e-9)       // gross − 6 fees + funding
        XCTAssertTrue(a.open.isEmpty)
    }

    func testOpenTradeAndBreakEven() {
        let fills = [
            f(1, px: 100, sz: 2, buy: true, t: 1, start: 0, dir: "Open Long", fee: 0.2),
            f(2, px: 110, sz: 1, buy: false, t: 2, start: 2, dir: "Close Long", pnl: 10, fee: 0.1),
        ]
        let a = TradeBuilder.analyze(fills: fills, funding: [FundingPayment(time: 2, coin: "BTC", usdc: -0.3)], orderKinds: [2: .takeProfit])
        let o = try! XCTUnwrap(a.open["BTC"])
        XCTAssertEqual(o.executions.map(\.label), ["E1", "TP1"])
        XCTAssertEqual(o.feesPaid, 0.3, accuracy: 1e-9)
        XCTAssertEqual(o.realized, 10)
        // Remaining 1 long from 100: break-even is below entry thanks to the realized TP.
        let be = try! XCTUnwrap(PositionMath.breakEven(entry: 100, size: 1, feesPaid: o.feesPaid, realized: o.realized, funding: o.funding, takerRate: 0.00045))
        XCTAssertEqual(PositionMath.net(price: be, entry: 100, size: 1, feesPaid: 0.3, realized: 10, funding: -0.3, takerRate: 0.00045), 0, accuracy: 1e-9)
        XCTAssertLessThan(be, 100)
        // Short: break-even above... below entry when costs only
        let beShort = try! XCTUnwrap(PositionMath.breakEven(entry: 100, size: -1, feesPaid: 0.1, realized: 0, funding: 0, takerRate: 0.00045))
        XCTAssertLessThan(beShort, 100)
        XCTAssertEqual(PositionMath.net(price: beShort, entry: 100, size: -1, feesPaid: 0.1, realized: 0, funding: 0, takerRate: 0.00045), 0, accuracy: 1e-9)
    }

    func testOrderKindMapping() {
        XCTAssertEqual(OrderKindTag.from(orderType: "Take Profit Market", reduceOnly: true, tif: nil), .takeProfit)
        XCTAssertEqual(OrderKindTag.from(orderType: "Stop Market", reduceOnly: true, tif: nil), .stopLoss)
        XCTAssertEqual(OrderKindTag.from(orderType: "Limit", reduceOnly: true, tif: "Gtc"), .takeProfit)
        XCTAssertEqual(OrderKindTag.from(orderType: "Limit", reduceOnly: true, tif: "Ioc"), .market)
        XCTAssertEqual(OrderKindTag.from(orderType: "Limit", reduceOnly: false, tif: "Alo"), .limit)
    }

    func testMakerEntryFeesInRisk() throws {
        let maker = try XCTUnwrap(RiskCalculator.calculate(RiskInput(accountValue: 10_000, riskPercent: 1, entry: 100, stopLoss: 99, takeProfit: nil, maxLeverage: 20, szDecimals: 3, takerFeeRate: 0.00045, entryFeeRate: 0.00015)))
        let taker = try XCTUnwrap(RiskCalculator.calculate(RiskInput(accountValue: 10_000, riskPercent: 1, entry: 100, stopLoss: 99, takeProfit: nil, maxLeverage: 20, szDecimals: 3)))
        XCTAssertGreaterThan(maker.size, taker.size)
        XCTAssertGreaterThan(maker.estFees, 0)
        XCTAssertLessThanOrEqual(maker.size * 1 + maker.estFees, 100.0001)
    }
}
