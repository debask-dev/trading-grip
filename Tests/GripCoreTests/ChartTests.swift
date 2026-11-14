import XCTest
@testable import GripCore

final class ViewportTests: XCTestCase {
    func viewport(count: Int = 500) -> ChartViewport {
        var v = ChartViewport()
        v.width = 800
        v.barCount = count
        v.clamp()
        return v
    }

    func testIndexAndXAreInverse() {
        let v = viewport()
        for i in [0.0, 120.5, 499] { XCTAssertEqual(v.index(x: v.x(index: i)), i, accuracy: 1e-9) }
    }

    func testWheelZoomIsCappedAtTenPercentPerEvent() {
        var v = viewport()
        let s = v.barSpacing
        v.zoom(wheelDelta: 5000, anchorX: 400)       // a huge trackpad flick
        XCTAssertEqual(v.barSpacing, s * 1.1, accuracy: 1e-9)
        v.zoom(wheelDelta: 4, anchorX: 400)          // a gentle one
        XCTAssertEqual(v.barSpacing, s * 1.1 * 1.004, accuracy: 1e-9)
    }

    func testZoomKeepsBarUnderCursor() {
        var v = viewport()
        let anchor = 300.0
        let before = v.index(x: anchor)
        for _ in 0..<10 { v.zoom(wheelDelta: 60, anchorX: anchor) }
        XCTAssertEqual(v.index(x: anchor), before, accuracy: 1e-6)
        for _ in 0..<10 { v.zoom(wheelDelta: -80, anchorX: anchor) }
        XCTAssertEqual(v.index(x: anchor), before, accuracy: 1e-6)
    }

    func testLimits() {
        var v = viewport(count: 50)
        for _ in 0..<500 { v.zoom(wheelDelta: 100, anchorX: 400) }
        XCTAssertEqual(v.barSpacing, 400)
        for _ in 0..<500 { v.zoom(wheelDelta: -100, anchorX: 400) }
        XCTAssertEqual(v.barSpacing, ChartViewport.minSpacing)
        v.reset()
        v.pan(pixels: 1_000_000)                     // far into the past
        XCTAssertNotNil(v.visibleRange)
        XCTAssertGreaterThanOrEqual(v.visibleRange!.count, 2)
        v.pan(pixels: -1_000_000)                    // far into the future
        XCTAssertNotNil(v.visibleRange)
        XCTAssertGreaterThanOrEqual(v.visibleRange!.count, 2)
    }

    func testTimeAxisScaleKeepsRightEdge() {
        var v = viewport()
        let lastX = v.x(index: 499)
        let s = v.barSpacing
        v.scaleTimeAxis(startSpacing: s, startX: 600, x: 400)   // drag left → zoom in
        XCTAssertGreaterThan(v.barSpacing, s)
        XCTAssertEqual(v.barSpacing, s * 400 / 200, accuracy: 1e-9)
        // The newest bar stays the same number of bars from the right edge.
        XCTAssertEqual((800 - v.x(index: 499)) / v.barSpacing, (800 - lastX) / s, accuracy: 1e-9)
    }

    func testKineticFling() {
        var k = KineticScroll()
        for i in 0...6 { k.add(position: Double(i) * 12, timeMs: Double(i) * 10) }   // 1.2 px/ms
        let v = k.releaseSpeed(atMs: 65)
        XCTAssertEqual(v ?? 0, 1.2, accuracy: 1e-9)
        let total = KineticScroll.offset(speed: 1.2, afterMs: KineticScroll.duration(speed: 1.2))
        XCTAssertGreaterThan(total, 100)
        XCTAssertLessThan(total, 400)
        // A slow release is not a fling
        var slow = KineticScroll()
        for i in 0...6 { slow.add(position: Double(i), timeMs: Double(i) * 10) }
        XCTAssertNil(slow.releaseSpeed(atMs: 65))
    }
}

final class ChartMathTests: XCTestCase {
    func testMeasure() {
        let candles = (0..<20).map { Candle(time: Int64($0) * 900_000, open: 100, high: 101, low: 99, close: 100, volume: 2) }
        let r = ChartMath.measure(from: ChartPoint(time: 900_000 * 2, price: 100), to: ChartPoint(time: 900_000 * 14, price: 112), candles: candles, timeframe: .m15)
        XCTAssertEqual(r.percent, 0.12, accuracy: 1e-12)
        XCTAssertEqual(r.priceChange, 12)
        XCTAssertEqual(r.bars, 12)
        XCTAssertEqual(r.durationMs, 12 * 900_000)
        XCTAssertEqual(r.volume, 26)
        XCTAssertEqual(ChartMath.durationText(ms: r.durationMs), "3u")
    }

    func testDurationText() {
        XCTAssertEqual(ChartMath.durationText(ms: 45 * 60_000), "45m")
        XCTAssertEqual(ChartMath.durationText(ms: 200 * 60_000), "3u 20m")
        XCTAssertEqual(ChartMath.durationText(ms: 52 * 3_600_000), "2d 4u")
        XCTAssertEqual(ChartMath.durationText(ms: 37 * 86_400_000), "5w 2d")
    }

    func testCountdown() {
        // 15m candle opened at 12:00:00, now 12:10:48 → 04:12 left
        let open: Int64 = 12 * 3_600_000
        XCTAssertEqual(ChartMath.countdown(lastCandleOpen: open, timeframe: .m15, nowMs: open + 648_000), "04:12")
        XCTAssertEqual(ChartMath.countdown(lastCandleOpen: open, timeframe: .h4, nowMs: open + 600_000), "3:50:00")
        XCTAssertEqual(ChartMath.countdown(lastCandleOpen: 0, timeframe: .w1, nowMs: 86_400_000 * 4 + 3_600_000 * 3), "2d 21u")
        // Stale last candle (no trade yet in the new period) still counts down to the next boundary
        XCTAssertEqual(ChartMath.countdown(lastCandleOpen: open, timeframe: .m1, nowMs: open + 150_000), "00:30")
    }

    func testCandleWidthIsPixelAligned() {
        for spacing in stride(from: 2.0, through: 40, by: 0.7) {
            let w = ChartMath.candleBodyWidth(spacing: spacing, pixelRatio: 2)
            XCTAssertEqual((w * 2).rounded(), w * 2)          // whole device pixels
            XCTAssertLessThanOrEqual(w, spacing)
            XCTAssertGreaterThanOrEqual(w, 1)
        }
    }
}

final class StyleTests: XCTestCase {
    func testHexRoundTrip() {
        XCTAssertEqual(RGBA(hex: "#2FD394")?.hex, "#2FD394")
        XCTAssertEqual(RGBA(hex: "2fd39480")?.hex, "#2FD39480")
        XCTAssertNil(RGBA(hex: "#xyz"))
        XCTAssertEqual(ChartStyle.classic.presetName, "Klassiek")
    }

    func testLegacyTrendlineDecoding() throws {
        let json = #"{"id":"5D6A1F2C-1111-2222-3333-444455556666","coin":"BTC","a":{"time":0,"price":1},"b":{"time":60000,"price":2},"color":"blue","extendRight":true,"createdAt":"2026-11-13T10:00:00Z"}"#
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        let l = try dec.decode(Trendline.self, from: Data(json.utf8))
        XCTAssertEqual(l.color, "#5AA2FF")
        XCTAssertEqual(l.width, 2)
        XCTAssertEqual(l.dash, .solid)
        XCTAssertTrue(l.extendRight)
        XCTAssertFalse(l.extendLeft)
    }
}
