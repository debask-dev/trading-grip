import XCTest
@testable import GripCore

final class PaperTests: XCTestCase {
    let btc = AssetInfo(name: "BTC", index: 0, szDecimals: 5, maxLeverage: 40)

    func testLimitEntryWithTpSlChildren() throws {
        let ex = PaperExchange(balance: 10_000)
        let st = try ex.place([
            OrderRequest(asset: btc, isBuy: true, size: 0.1, limitPx: 99_000, reduceOnly: false, kind: .limit(tif: "Gtc")),
            OrderRequest(asset: btc, isBuy: false, size: 0.1, limitPx: 102_000, reduceOnly: true, kind: .trigger(triggerPx: 102_000, isMarket: true, tpsl: .tp)),
            OrderRequest(asset: btc, isBuy: false, size: 0.1, limitPx: 98_000, reduceOnly: true, kind: .trigger(triggerPx: 98_000, isMarket: true, tpsl: .sl)),
        ], grouping: "normalTpsl", marks: ["BTC": 100_000], time: 1)
        guard case .resting = st[0] else { return XCTFail("entry should rest") }
        // Children are hidden until the entry fills
        XCTAssertEqual(ex.accountState(marks: ["BTC": 100_000], assets: [btc]).openOrders.count, 1)

        ex.onPrices(["BTC": 98_990], time: 2)
        var acct = ex.accountState(marks: ["BTC": 98_990], assets: [btc])
        XCTAssertEqual(acct.positions.first?.size, 0.1)
        XCTAssertEqual(acct.positions.first?.entryPx, 99_000)
        XCTAssertEqual(acct.openOrders.count, 2)

        // Take-profit hits
        ex.onPrices(["BTC": 102_100], time: 3)
        acct = ex.accountState(marks: ["BTC": 102_100], assets: [btc])
        XCTAssertTrue(acct.positions.isEmpty)
        XCTAssertTrue(acct.openOrders.isEmpty, "SL is cancelled once flat")
        let pnl = (102_100 - 99_000) * 0.1
        let fees = 0.1 * 99_000 * PaperExchange.makerFee + 0.1 * 102_100 * PaperExchange.takerFee
        XCTAssertEqual(acct.accountValue, 10_000 + pnl - fees, accuracy: 1e-6)

        let trades = TradeBuilder.build(fills: ex.fills)
        XCTAssertEqual(trades.count, 1)
        XCTAssertEqual(trades[0].netPnl, pnl - fees, accuracy: 1e-6)
    }

    func testMarketEntryPartialCloseAndLimitClose() throws {
        let ex = PaperExchange(balance: 10_000)
        ex.updateLeverage(coin: "BTC", isCross: true, leverage: 5)
        _ = try ex.place([OrderRequest(asset: btc, isBuy: true, size: 0.2, limitPx: 101_000, reduceOnly: false, kind: .limit(tif: "Ioc"))],
                         grouping: "na", marks: ["BTC": 100_000], time: 1)
        XCTAssertEqual(ex.accountState(marks: ["BTC": 100_000], assets: [btc]).positions.first?.leverage, 5)

        // Close 25% at market
        _ = try ex.place([OrderRequest(asset: btc, isBuy: false, size: 0.05, limitPx: 99_000, reduceOnly: true, kind: .limit(tif: "Ioc"))],
                         grouping: "na", marks: ["BTC": 101_000], time: 2)
        XCTAssertEqual(ex.holdings["BTC"]?.size ?? 0, 0.15, accuracy: 1e-12)

        // Limit close of the rest above the market rests, then fills
        let st = try ex.place([OrderRequest(asset: btc, isBuy: false, size: 0.15, limitPx: 103_000, reduceOnly: true, kind: .limit(tif: "Gtc"))],
                              grouping: "na", marks: ["BTC": 101_000], time: 3)
        guard case .resting(let oid) = st[0] else { return XCTFail() }
        try ex.modify(oid: oid, to: OrderRequest(asset: btc, isBuy: false, size: 0.15, limitPx: 102_000, reduceOnly: true, kind: .limit(tif: "Gtc")))
        ex.onPrices(["BTC": 102_050], time: 4)
        XCTAssertNil(ex.holdings["BTC"])
        let trades = TradeBuilder.build(fills: ex.fills)
        XCTAssertEqual(trades.count, 1)
        XCTAssertGreaterThan(trades[0].netPnl, 0)
    }

    func testReduceOnlyCannotOpen() {
        let ex = PaperExchange()
        XCTAssertThrowsError(try ex.place([OrderRequest(asset: btc, isBuy: false, size: 0.1, limitPx: 90_000, reduceOnly: true, kind: .limit(tif: "Ioc"))],
                                          grouping: "na", marks: ["BTC": 100_000]))
    }

    func testSnapshotsAccumulate() {
        let ex = PaperExchange(balance: 1_000)
        for t in stride(from: Int64(0), through: 120_000, by: 4_000) { ex.recordSnapshot(marks: [:], assets: [], time: t) }
        // One point per ~30s plus the moving newest point
        XCTAssertGreaterThanOrEqual(ex.snapshots.count, 4)
        XCTAssertLessThanOrEqual(ex.snapshots.count, 7)
        XCTAssertEqual(ex.snapshots.last?.time, 120_000)
    }

    func testCodableRoundTrip() throws {
        let ex = PaperExchange(balance: 5_000)
        ex.updateLeverage(coin: "BTC", isCross: false, leverage: 3)
        _ = try ex.place([OrderRequest(asset: btc, isBuy: true, size: 0.01, limitPx: 99_000, reduceOnly: false, kind: .limit(tif: "Gtc"))],
                         grouping: "na", marks: ["BTC": 100_000])
        let data = try JSONEncoder().encode(ex)
        let back = try JSONDecoder().decode(PaperExchange.self, from: data)
        XCTAssertEqual(back.orders, ex.orders)
        XCTAssertEqual(back.balance, 5_000)
    }
}
