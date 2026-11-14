import XCTest
@testable import GripCore

final class IndicatorTests: XCTestCase {
    func testSMAandEMA() {
        let v: [Double] = [1, 2, 3, 4, 5, 6]
        XCTAssertEqual(IndicatorMath.sma(v, length: 3).compactMap { $0 }, [2, 3, 4, 5])
        let e = IndicatorMath.ema(v, length: 3)
        XCTAssertNil(e[1])
        XCTAssertEqual(e[2] ?? 0, 2, accuracy: 1e-12)            // seeded with SMA
        XCTAssertEqual(e[3] ?? 0, 4 * 0.5 + 2 * 0.5, accuracy: 1e-12)
    }

    func testRSIBounds() {
        let up = (0..<30).map { Double($0) }
        XCTAssertEqual((IndicatorMath.rsi(up, length: 14).last ?? nil) ?? 0, 100, accuracy: 1e-9)
        let zigzag = (0..<60).map { $0 % 2 == 0 ? 100.0 : 101.0 }
        XCTAssertEqual((IndicatorMath.rsi(zigzag, length: 14).last ?? nil) ?? 0, 50, accuracy: 5)
    }

    func testVWAPRestartsEachDay() {
        let day: Int64 = 86_400_000
        let c = [Candle(time: 0, open: 10, high: 10, low: 10, close: 10, volume: 1),
                 Candle(time: 3_600_000, open: 20, high: 20, low: 20, close: 20, volume: 3),
                 Candle(time: day, open: 50, high: 50, low: 50, close: 50, volume: 2)]
        let v = IndicatorMath.vwap(c)
        XCTAssertEqual(v[1] ?? 0, (10 + 60) / 4, accuracy: 1e-9)
        XCTAssertEqual(v[2] ?? 0, 50, accuracy: 1e-9)
    }

    func testBollingerWidth() {
        let flat = [Double](repeating: 5, count: 25)
        let b = IndicatorMath.bollinger(flat, length: 20)
        XCTAssertEqual((b.upper.last ?? nil) ?? 0, 5, accuracy: 1e-12)
        XCTAssertEqual((b.lower.last ?? nil) ?? 0, 5, accuracy: 1e-12)
    }

    func testConfigCodable() throws {
        let c = IndicatorConfig(kind: .ema, length: 200)
        let d = try JSONDecoder().decode(IndicatorConfig.self, from: JSONEncoder().encode(c))
        XCTAssertEqual(d, c)
        XCTAssertEqual(d.shortName, "EMA 200")
    }
}
