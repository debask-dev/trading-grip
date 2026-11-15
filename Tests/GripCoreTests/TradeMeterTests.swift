import XCTest
@testable import GripCore

final class TradeMeterTests: XCTestCase {
    let maker = 0.00015, taker = 0.00045

    /// Long 1,2 ETH @ 3.120, stop 3.080, TP 3.200 (½) and 3.240 (½), price 3.168.
    func testOneEntryTwoTakeProfits() {
        let m = TradeMeter.compute(.init(isLong: true, size: 1.2, entry: 3120, locked: -1.2 * 3120 * maker, stop: 3080,
                                         takeProfits: [TPTarget(price: 3240, fraction: 0.5), TPTarget(price: 3200, fraction: 0.5)],
                                         maker: maker, taker: taker), price: 3168)
        XCTAssertEqual(m.now, 55.33, accuracy: 0.01)
        XCTAssertEqual(m.oneR ?? 0, 50.22, accuracy: 0.01)
        XCTAssertEqual(m.low ?? 0, -50.22, accuracy: 0.01)
        XCTAssertEqual(m.high ?? 0, 118.86, accuracy: 0.01)
        XCTAssertEqual(m.highNow ?? 0, 118.86, accuracy: 0.01)
        XCTAssertEqual(m.r(m.now) ?? 0, 1.1, accuracy: 0.01)
        XCTAssertEqual(m.averageTP ?? 0, 3220, accuracy: 1e-9)
        XCTAssertEqual(m.marks.count, 1)                       // TP1 only; TP2 is the right end
        XCTAssertEqual(m.marks[0], 48 - 0.288 + 0.6 * 80 - 0.6 * 3200 * taker - 0.5616, accuracy: 0.01)
        XCTAssertFalse(m.openEnded)
    }

    func testTakeProfitsUnderHundredPercentAreOpenEnded() {
        let m = TradeMeter.compute(.init(isLong: true, size: 1.2, entry: 3120, stop: 3080,
                                         takeProfits: [TPTarget(price: 3200, fraction: 0.4), TPTarget(price: 3240, fraction: 0.3)],
                                         maker: maker, taker: taker), price: 3168)
        XCTAssertTrue(m.openEnded)
        // 70% closed by the TPs, 30% valued at the last TP.
        let expected = 0.48 * 80 - 0.48 * 3200 * maker + 0.36 * 120 - 0.36 * 3240 * maker + 0.36 * 120 - 0.36 * 3240 * maker
        XCTAssertEqual(m.high ?? 0, expected, accuracy: 0.01)
    }

    /// Three entries of 0,4 (3.130 / 3.110 / 3.090), stop 3.060: before and after the first fill 1R stays the same.
    func testWaitingEntriesCountForTheStopAndTheTargets() {
        let rest: [(price: Double, size: Double)] = [(3130, 0.4), (3110, 0.4), (3090, 0.4)]
        let tps = [TPTarget(price: 3170, fraction: 0.5), TPTarget(price: 3210, fraction: 0.5)]
        let before = TradeMeter.compute(.init(isLong: true, size: 0, entry: 0, restingEntries: rest, stop: 3060, takeProfits: tps,
                                              maker: maker, taker: taker), price: 3140)
        XCTAssertFalse(before.hasPosition)
        XCTAssertEqual(before.now, 0)
        XCTAssertEqual(before.plannedEntry, 3110, accuracy: 1e-9)
        XCTAssertEqual(before.entriesTotal, 3)
        let risk = 1.2 * 50 + 1.2 * 3110 * maker + 1.2 * 3060 * taker
        XCTAssertEqual(before.oneR ?? 0, risk, accuracy: 0.01)
        XCTAssertEqual(before.low ?? 0, -risk, accuracy: 0.01)
        XCTAssertEqual(before.highNow ?? -1, 0)

        let after = TradeMeter.compute(.init(isLong: true, size: 0.4, entry: 3130, locked: -0.4 * 3130 * maker, restingEntries: Array(rest.dropFirst()),
                                             stop: 3060, takeProfits: tps, maker: maker, taker: taker), price: 3120, filledEntries: 1)
        XCTAssertEqual(after.oneR ?? 0, risk, accuracy: 0.01)
        XCTAssertEqual(after.low ?? 0, -risk, accuracy: 0.01)
        XCTAssertEqual(after.high ?? 0, before.high ?? 0, accuracy: 0.01)
        XCTAssertLessThan(after.highNow ?? 0, (after.high ?? 0) / 2)   // only a third filled
        XCTAssertEqual(after.entriesFilled, 1)
        XCTAssertEqual(after.entriesTotal, 3)
    }

    func testShortAndPlannedRisk() {
        let m = TradeMeter.compute(.init(isLong: false, size: 1, entry: 100, stop: 105, takeProfits: [TPTarget(price: 90, fraction: 1)],
                                         plannedRisk: 4, maker: 0, taker: 0), price: 95)
        XCTAssertEqual(m.now, 5, accuracy: 1e-9)
        XCTAssertEqual(m.low ?? 0, -5, accuracy: 1e-9)
        XCTAssertEqual(m.high ?? 0, 10, accuracy: 1e-9)
        XCTAssertEqual(m.r(m.now) ?? 0, 1.25, accuracy: 1e-9)  // against the risk as planned
    }

    func testNoStopUsesLiquidationAndHasNoR() {
        let m = TradeMeter.compute(.init(isLong: true, size: 1, entry: 100, stop: nil, liquidation: 80, takeProfits: [],
                                         maker: 0, taker: 0), price: 101)
        XCTAssertNil(m.oneR)
        XCTAssertNil(m.high)
        XCTAssertTrue(m.lowIsLiquidation)
        XCTAssertEqual(m.low ?? 0, -20, accuracy: 1e-9)
    }
}
