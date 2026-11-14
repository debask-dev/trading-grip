import XCTest
@testable import GripCore

/// End-to-end order flows against the practice exchange: what the app sends, then what the keeper does after fills.
final class OrderFlowTests: XCTestCase {
    let btc = AssetInfo(name: "BTC", index: 0, szDecimals: 5, maxLeverage: 40)
    var marks: [String: Double] = ["BTC": 65_000]

    private func state(_ p: PaperExchange) -> AccountState { p.accountState(marks: marks, assets: [btc]) }

    /// Runs the keeper like the app does after every refresh, applying its actions to the practice exchange.
    @discardableResult
    private func keep(_ p: PaperExchange, _ m: inout ManagedTrade?) throws -> [KeeperAction] {
        guard let cur = m else { return [] }
        let st = state(p)
        let step = TradeKeeper.step(cur, position: st.position(for: "BTC"), orders: st.orders(for: "BTC"), szDecimals: btc.szDecimals)
        for a in step.actions {
            switch a {
            case .cancel(let oid): try p.cancel(oid: oid)
            case .placeStop(let size, let px):
                let r = try p.place([OrderRequest(asset: btc, isBuy: !cur.isLong, size: size, limitPx: px, reduceOnly: true,
                                                  kind: .trigger(triggerPx: px, isMarket: true, tpsl: .sl))], grouping: "na", marks: marks)
                XCTAssertFalse(r.contains { if case .error = $0 { return true }; return false })
            case .resizeStop(let oid, let size, let px):
                try p.modify(oid: oid, to: OrderRequest(asset: btc, isBuy: !cur.isLong, size: size, limitPx: px, reduceOnly: true,
                                                        kind: .trigger(triggerPx: px, isMarket: true, tpsl: .sl)))
            case .placeTakeProfits(let tps):
                let r = try p.place(tps.map { OrderRequest(asset: btc, isBuy: !cur.isLong, size: $0.size, limitPx: $0.price, reduceOnly: true, kind: .limit(tif: "Gtc")) },
                                    grouping: "na", marks: marks)
                XCTAssertFalse(r.contains { if case .error = $0 { return true }; return false })
            case .resizeTakeProfit(let oid, let size, let px, _):
                try p.modify(oid: oid, to: OrderRequest(asset: btc, isBuy: !cur.isLong, size: size, limitPx: px, reduceOnly: true, kind: .limit(tif: "Gtc")))
            }
        }
        m = step.next
        return step.actions
    }

    private func move(_ p: PaperExchange, to px: Double) { marks["BTC"] = px; p.onPrices(marks) }

    private func stops(_ p: PaperExchange) -> [OpenOrder] { state(p).orders(for: "BTC").filter { $0.isTrigger && $0.tpsl == .sl } }
    private func tps(_ p: PaperExchange) -> [OpenOrder] { state(p).orders(for: "BTC").filter { $0.reduceOnly && !$0.isTrigger } }

    func testMarketEntryWithStopAndTPLadder() throws {
        let p = PaperExchange(balance: 10_000)
        p.updateLeverage(coin: "BTC", isCross: true, leverage: 3)
        let size = 0.1
        _ = try p.place([
            OrderRequest(asset: btc, isBuy: true, size: size, limitPx: 65_650, reduceOnly: false, kind: .limit(tif: "Ioc")),
            OrderRequest(asset: btc, isBuy: false, size: size, limitPx: 64_400, reduceOnly: true, kind: .trigger(triggerPx: 64_400, isMarket: true, tpsl: .sl)),
        ], grouping: "normalTpsl", marks: marks)
        var m: ManagedTrade? = ManagedTrade(isLong: true, stop: 64_400, lastSize: 0,
                                            tps: PendingTPs(isLong: true, prices: [65_500, 66_000, 66_500], fractions: [0.5, 0.3, 0.2]))
        try keep(p, &m)
        XCTAssertEqual(stops(p).count, 1)
        XCTAssertEqual(stops(p).first?.size ?? 0, 0.1, accuracy: 1e-9)
        XCTAssertEqual(tps(p).map(\.size), [0.05, 0.03, 0.02])
        XCTAssertNil(m?.tps)
        // Nothing more to do on the next refresh.
        XCTAssertTrue(try keep(p, &m).isEmpty)
    }

    func testEntryLadderStopGrowsAndUnfilledEntriesAreCancelled() throws {
        let p = PaperExchange(balance: 10_000)
        p.updateLeverage(coin: "BTC", isCross: true, leverage: 5)
        let st = try p.place([
            OrderRequest(asset: btc, isBuy: true, size: 0.05, limitPx: 64_800, reduceOnly: false, kind: .limit(tif: "Gtc")),
            OrderRequest(asset: btc, isBuy: true, size: 0.03, limitPx: 64_500, reduceOnly: false, kind: .limit(tif: "Gtc")),
            OrderRequest(asset: btc, isBuy: true, size: 0.02, limitPx: 64_200, reduceOnly: false, kind: .limit(tif: "Gtc")),
        ], grouping: "na", marks: marks)
        let oids = st.compactMap { if case .resting(let o) = $0 { return o }; return nil }
        XCTAssertEqual(oids.count, 3)
        var m: ManagedTrade? = ManagedTrade(isLong: true, stop: 63_900, entryOids: oids, lastSize: 0,
                                            tps: PendingTPs(isLong: true, prices: [65_500, 66_000], fractions: [0.5, 0.5]))
        XCTAssertTrue(try keep(p, &m).isEmpty)          // nothing filled yet

        move(p, to: 64_790)                               // E1 fills
        try keep(p, &m)
        XCTAssertEqual(stops(p).first?.size ?? 0, 0.05, accuracy: 1e-9)
        XCTAssertEqual(tps(p).map(\.size).reduce(0, +), 0.05, accuracy: 1e-9)

        move(p, to: 64_490)                               // E2 fills
        try keep(p, &m)
        XCTAssertEqual(stops(p).first?.size ?? 0, 0.08, accuracy: 1e-9)
        XCTAssertEqual(tps(p).map(\.size).reduce(0, +), 0.08, accuracy: 1e-9)

        move(p, to: 63_850)                               // E3 fills and the stop is hit in one move: 0.02 left over
        XCTAssertEqual(state(p).position(for: "BTC")?.size ?? 0, 0.02, accuracy: 1e-9)
        XCTAssertEqual(try keep(p, &m), [.placeStop(size: 0.02, price: 63_900)])   // Grip puts a stop on the rest
        move(p, to: 63_840)
        try keep(p, &m)
        XCTAssertNil(state(p).position(for: "BTC"))
        XCTAssertNil(m)
        XCTAssertTrue(state(p).orders(for: "BTC").isEmpty)
    }

    func testStopHitCancelsRemainingEntries() throws {
        let p = PaperExchange(balance: 10_000)
        p.updateLeverage(coin: "BTC", isCross: true, leverage: 5)
        let st = try p.place([
            OrderRequest(asset: btc, isBuy: true, size: 0.05, limitPx: 64_800, reduceOnly: false, kind: .limit(tif: "Gtc")),
            OrderRequest(asset: btc, isBuy: true, size: 0.05, limitPx: 63_000, reduceOnly: false, kind: .limit(tif: "Gtc")),
        ], grouping: "na", marks: marks)
        let oids = st.compactMap { if case .resting(let o) = $0 { return o }; return nil }
        var m: ManagedTrade? = ManagedTrade(isLong: true, stop: 64_000, entryOids: oids, lastSize: 0)
        move(p, to: 64_790)
        try keep(p, &m)
        move(p, to: 63_990)                               // stop hit before E2
        let actions = try keep(p, &m)
        XCTAssertEqual(actions, [.cancel(oid: oids[1])])
        XCTAssertTrue(state(p).orders(for: "BTC").isEmpty)
    }

    func testAddingResizesStopAndScalesTakeProfits() throws {
        let p = PaperExchange(balance: 10_000)
        p.updateLeverage(coin: "BTC", isCross: true, leverage: 3)
        _ = try p.place([OrderRequest(asset: btc, isBuy: true, size: 0.1, limitPx: 65_500, reduceOnly: false, kind: .limit(tif: "Ioc"))], grouping: "na", marks: marks)
        _ = try p.place([
            OrderRequest(asset: btc, isBuy: false, size: 0.1, limitPx: 64_000, reduceOnly: true, kind: .trigger(triggerPx: 64_000, isMarket: true, tpsl: .sl)),
            OrderRequest(asset: btc, isBuy: false, size: 0.05, limitPx: 66_000, reduceOnly: true, kind: .limit(tif: "Gtc")),
            OrderRequest(asset: btc, isBuy: false, size: 0.05, limitPx: 66_500, reduceOnly: true, kind: .limit(tif: "Gtc")),
        ], grouping: "na", marks: marks)
        // Add 0.05 at market, stop stays where it is.
        var m: ManagedTrade? = ManagedTrade(isLong: true, stop: 64_000, lastSize: 0.1)
        _ = try p.place([OrderRequest(asset: btc, isBuy: true, size: 0.05, limitPx: 65_500, reduceOnly: false, kind: .limit(tif: "Ioc"))], grouping: "na", marks: marks)
        try keep(p, &m)
        XCTAssertEqual(stops(p).first?.size ?? 0, 0.15, accuracy: 1e-9)
        XCTAssertEqual(tps(p).map(\.size), [0.075, 0.075])
    }

    func testSmallTakeProfitsAreMerged() {
        // $3.40 account at 8x: about $26 position split 50/30/20 → only levels of $10+ remain.
        let tps = TradeKeeper.split(total: 0.0004, prices: [66_000, 66_500, 67_000], fractions: [0.5, 0.3, 0.2], szDecimals: 5)
        XCTAssertEqual(tps.map(\.size).reduce(0, +), 0.0004, accuracy: 1e-9)
        XCTAssertTrue(tps.allSatisfy { $0.size * $0.price >= 10 })
        XCTAssertEqual(tps.count, 2)
    }

    func testAutoLeverageFitsFreeMargin() throws {
        // Small account: the order must fit in the free margin, not just the account value.
        var i = PlanInput(accountValue: 3.40, riskPercent: nil, isLong: true, entries: [TPTarget(price: 65_000, fraction: 1)], stopLoss: 64_000,
                          maxLeverage: 40, szDecimals: 5)
        i.sizeOverride = 0.0004               // $26
        i.availableMargin = 3.0
        let plan = try XCTUnwrap(OrderPlanner.plan(i))
        XCTAssertGreaterThanOrEqual(Double(plan.leverage), 26 / (3.0 * 0.95))
        // And the practice exchange agrees it fits at that leverage.
        let p = PaperExchange(balance: 3.40)
        p.updateLeverage(coin: "BTC", isCross: true, leverage: plan.leverage)
        XCTAssertNoThrow(try p.place([OrderRequest(asset: btc, isBuy: true, size: 0.0004, limitPx: 65_650, reduceOnly: false, kind: .limit(tif: "Ioc"))],
                                     grouping: "na", marks: marks))
        let p2 = PaperExchange(balance: 3.40)
        p2.updateLeverage(coin: "BTC", isCross: true, leverage: 3)
        XCTAssertThrowsError(try p2.place([OrderRequest(asset: btc, isBuy: true, size: 0.0004, limitPx: 65_650, reduceOnly: false, kind: .limit(tif: "Ioc"))],
                                          grouping: "na", marks: marks))
    }

    func testSingleLimitEntryWithLinkedStopAndTakeProfit() throws {
        let p = PaperExchange(balance: 10_000)
        p.updateLeverage(coin: "BTC", isCross: true, leverage: 3)
        _ = try p.place([
            OrderRequest(asset: btc, isBuy: true, size: 0.1, limitPx: 64_800, reduceOnly: false, kind: .limit(tif: "Gtc")),
            OrderRequest(asset: btc, isBuy: false, size: 0.1, limitPx: 64_300, reduceOnly: true, kind: .trigger(triggerPx: 64_300, isMarket: true, tpsl: .sl)),
            OrderRequest(asset: btc, isBuy: false, size: 0.1, limitPx: 65_600, reduceOnly: true, kind: .trigger(triggerPx: 65_600, isMarket: false, tpsl: .tp)),
        ], grouping: "normalTpsl", marks: marks)
        var m: ManagedTrade? = ManagedTrade(isLong: true, stop: 64_300, lastSize: 0)
        move(p, to: 64_790)                               // entry fills, stop and TP become active
        XCTAssertTrue(try keep(p, &m).isEmpty)          // nothing to add: both already there
        let orders = state(p).orders(for: "BTC")
        XCTAssertEqual(orders.filter { $0.tpsl == .sl }.count, 1)
        XCTAssertEqual(orders.filter { $0.tpsl == .tp }.count, 1)
        move(p, to: 65_610)                               // take-profit
        try keep(p, &m)
        XCTAssertNil(state(p).position(for: "BTC"))
        XCTAssertNil(m)
    }
}
