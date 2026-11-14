import XCTest
@testable import GripCore

final class PlannerTests: XCTestCase {
    private func input(_ entries: [TPTarget], stop: Double?, risk: Double? = 1) -> PlanInput {
        var i = PlanInput(accountValue: 10_000, riskPercent: risk, isLong: true, entries: entries, stopLoss: stop, maxLeverage: 40, szDecimals: 5)
        i.takerFeeRate = 0; i.entryFeeRate = 0
        return i
    }

    func testEntryLadderUsesAverageEntry() throws {
        let i = input([TPTarget(price: 65_300, fraction: 0.5), TPTarget(price: 65_000, fraction: 0.3), TPTarget(price: 64_700, fraction: 0.2)], stop: 64_400)
        let p = try XCTUnwrap(OrderPlanner.plan(i))
        XCTAssertEqual(p.avgEntry, 65_090, accuracy: 0.01)
        XCTAssertEqual(p.riskUsd ?? 0, 100, accuracy: 0.1)
        XCTAssertEqual(p.entrySizes.reduce(0, +), p.size, accuracy: 1e-9)
        XCTAssertLessThan(p.riskFirstEntryOnly ?? 999, 100)
    }

    func testAddUsesRemainingRiskBudget() throws {
        var i = input([TPTarget(price: 65_300, fraction: 1)], stop: 64_200)
        i.existing = ExistingPosition(size: 0.1, entryPx: 64_800, isLong: true, leverage: 3)
        let p = try XCTUnwrap(OrderPlanner.plan(i))
        XCTAssertTrue(p.isAdd)
        XCTAssertEqual(p.existingRiskUsd ?? 0, 60, accuracy: 0.01)
        XCTAssertEqual(p.size, 0.03636, accuracy: 0.00001)          // (100 - 60) / 1100
        XCTAssertEqual(p.riskUsd ?? 0, 100, accuracy: 0.05)
        XCTAssertEqual(p.after.size, 0.13636, accuracy: 0.00001)
        XCTAssertEqual(p.leverage, 3)                              // keeps current leverage
    }

    func testAddWithoutRoomWarns() throws {
        var i = input([TPTarget(price: 65_300, fraction: 1)], stop: 60_000)
        i.existing = ExistingPosition(size: 0.1, entryPx: 64_800, isLong: true, leverage: 3)
        let p = try XCTUnwrap(OrderPlanner.plan(i))
        XCTAssertEqual(p.size, 0)
        XCTAssertTrue(p.warnings.contains { $0.contains("Geen risicoruimte") })
    }

    func testManualFreeSizingWithoutStop() throws {
        var i = input([TPTarget(price: 65_000, fraction: 1)], stop: nil, risk: nil)
        i.sizeOverride = 0.2
        i.leverageOverride = 10
        let p = try XCTUnwrap(OrderPlanner.plan(i))
        XCTAssertEqual(p.size, 0.2)
        XCTAssertNil(p.riskUsd)
        XCTAssertEqual(p.leverage, 10)
        XCTAssertEqual(p.marginRequired, 1_300, accuracy: 0.01)
    }

    func testLowerLeverageThanCurrentWarns() throws {
        var i = input([TPTarget(price: 65_000, fraction: 1)], stop: nil, risk: nil)
        i.sizeOverride = 0.01
        i.leverageOverride = 2
        i.existing = ExistingPosition(size: 0.1, entryPx: 64_800, isLong: true, leverage: 5)
        let p = try XCTUnwrap(OrderPlanner.plan(i))
        XCTAssertTrue(p.warnings.contains { $0.contains("huidige hefboom") })
    }

    func testReduceIsCappedAtPosition() throws {
        var i = input([TPTarget(price: 66_000, fraction: 1)], stop: nil, risk: nil)
        i.isLong = false
        i.sizeOverride = 0.5
        i.existing = ExistingPosition(size: 0.1, entryPx: 65_000, isLong: true, leverage: 3)
        let p = try XCTUnwrap(OrderPlanner.plan(i))
        XCTAssertTrue(p.isReduce)
        XCTAssertEqual(p.size, 0.1)
        XCTAssertEqual(p.reducePnl ?? 0, 100, accuracy: 0.01)
        XCTAssertEqual(p.after.size, 0, accuracy: 1e-12)
    }

    func testCrossLiquidationUsesAccountValue() throws {
        // $10k account, 0.2 BTC long at 65k ($13k): cross liquidation far below; leverage does not move it.
        var i = input([TPTarget(price: 65_000, fraction: 1)], stop: nil, risk: nil)
        i.sizeOverride = 0.2
        i.isCross = true
        i.leverageOverride = 3
        let a = try XCTUnwrap(OrderPlanner.plan(i))
        i.leverageOverride = 20
        let b = try XCTUnwrap(OrderPlanner.plan(i))
        XCTAssertEqual(a.estLiquidationPx, b.estLiquidationPx, accuracy: 0.01)
        // 0.2 × (65000 − liq) ≈ 10000 − maintenance → liq ≈ 15.2k
        XCTAssertEqual(a.estLiquidationPx, (0.2 * 65_000 - 10_000) / (0.2 * (1 - 1.0 / 80)), accuracy: 0.01)
        // Isolated at 20× is much closer.
        i.isCross = false
        let c = try XCTUnwrap(OrderPlanner.plan(i))
        XCTAssertGreaterThan(c.estLiquidationPx, 60_000)
    }
}
