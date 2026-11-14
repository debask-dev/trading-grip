import XCTest
@testable import GripCore

/// Hits the real Hyperliquid API. Only runs with GRIP_LIVE=1 (not in CI).
final class LiveTests: XCTestCase {
    func testLiveAccountState() async throws {
        guard ProcessInfo.processInfo.environment["GRIP_LIVE"] == "1" else { throw XCTSkip("set GRIP_LIVE=1") }
        let c = HLClient(network: .mainnet)
        let s = try await c.accountState(user: "0xf5d81a135f756ca16544e53c20fc20643ec3ad53")
        print("LIVE mode=\(s.mode) perps=\(s.perpsValue) spot=\(s.spotValue) value=\(s.accountValue) balances=\(s.spotBalances.map { "\($0.coin):\($0.total)=$\($0.usdValue)" })")
        XCTAssertGreaterThan(s.spotValue, 0)
        let prices = try await c.spotPrices()
        print("LIVE PURR price=\(prices[1] ?? -1) tokens=\(prices.count)")
        XCTAssertGreaterThan(prices[1] ?? 0, 0)
    }
}
