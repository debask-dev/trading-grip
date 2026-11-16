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

    func testContinuousZoomFollowsFastGestures() {
        var v = viewport()
        let anchor = 500.0
        let before = v.index(x: anchor)
        v.zoom(factor: 1.6, anchorX: anchor)              // one fast trackpad event: not capped at 10%
        XCTAssertEqual(v.barSpacing, ChartViewport.defaultSpacing * 1.6, accuracy: 1e-9)
        XCTAssertEqual(v.index(x: anchor), before, accuracy: 1e-9)
        v.setSpacing(4, keepingIndex: before, atX: anchor)  // animated step towards a target
        XCTAssertEqual(v.index(x: anchor), before, accuracy: 1e-9)
    }

    func testTypedTimeframes() {
        XCTAssertEqual(Timeframe.parse("15"), .m15)
        XCTAssertEqual(Timeframe.parse("60"), .h1)
        XCTAssertEqual(Timeframe.parse("4H"), .h4)
        XCTAssertEqual(Timeframe.parse("d"), .d1)
        XCTAssertEqual(Timeframe.parse("1w"), .w1)
        XCTAssertNil(Timeframe.parse("7"))
        XCTAssertEqual(Timeframe.parse("30"), .m30)
        XCTAssertEqual(Timeframe.parse("12h"), .h12)
        XCTAssertEqual(Timeframe.parse("3d"), .d3)
        XCTAssertEqual(Timeframe.m15.next, .m30)
        XCTAssertNil(Timeframe.w1.next)
        XCTAssertEqual(Timeframe.m5.previous, .m3)
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
        var st = ChartStyle.grip
        st.setColor("#E68538", up: true)
        XCTAssertEqual([st.upBody, st.upBorder, st.upWick], ["#E68538", "#E68538", "#E68538"])
        XCTAssertNil(st.presetName)
        XCTAssertEqual(LineAppearance().color, "#D55C26")
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

final class TimeAxisTests: XCTestCase {
    func testMarkerSitsOnTheCandleThatContainsTheFill() {
        let candles = (0..<4).map { Candle(time: Int64($0) * 900_000, open: 100, high: 101, low: 99, close: 100, volume: 1) }
        // 12 minutes into the first candle: nearest open time is the second candle, but the fill belongs to the first.
        XCTAssertEqual(Snap.nearestIndex(time: 720_000, candles: candles), 1)
        XCTAssertEqual(Snap.containingIndex(time: 720_000, candles: candles, timeframe: .m15), 0)
        XCTAssertEqual(Snap.containingIndex(time: 900_000, candles: candles, timeframe: .m15), 1)
        XCTAssertEqual(Snap.containingIndex(time: 3 * 900_000 + 899_999, candles: candles, timeframe: .m15), 3)
        XCTAssertNil(Snap.containingIndex(time: 4 * 900_000, candles: candles, timeframe: .m15))
        XCTAssertNil(Snap.containingIndex(time: -1, candles: candles, timeframe: .m15))
    }

    func testStepIsRoundAndWideEnough() {
        // 15m bars at 9 pt: 110 pt ≈ 12.2 bars, just over 3 h → 4 h step.
        XCTAssertEqual(TimeAxis.step(timeframe: .m15, barSpacing: 9), 4 * 3_600_000)
        XCTAssertEqual(TimeAxis.step(timeframe: .m15, barSpacing: 200), 15 * 60_000)
        XCTAssertEqual(TimeAxis.step(timeframe: .d1, barSpacing: 9), 14 * 86_400_000)
    }

    func testLabelsStayOnRoundLocalTimes() {
        let hour: Int64 = 3_600_000
        let cet = hour   // UTC+1
        // 23:00 UTC is midnight in CET: a 4h step labels it.
        XCTAssertTrue(TimeAxis.isLabel(time: 23 * hour, step: 4 * hour, timeframe: .m15, utcOffset: cet))
        XCTAssertFalse(TimeAxis.isLabel(time: 0, step: 4 * hour, timeframe: .m15, utcOffset: cet))
        XCTAssertTrue(TimeAxis.isLabel(time: 3 * hour, step: 4 * hour, timeframe: .m15, utcOffset: cet))
        // Day step on an hourly chart: local midnight only.
        XCTAssertTrue(TimeAxis.isLabel(time: 23 * hour, step: 24 * hour, timeframe: .h1, utcOffset: cet))
        XCTAssertFalse(TimeAxis.isLabel(time: 22 * hour, step: 24 * hour, timeframe: .h1, utcOffset: cet))
        // Daily candles (UTC midnight) still get labels in any time zone.
        let day = 24 * hour
        let labelled = (0..<28).filter { TimeAxis.isLabel(time: Int64($0) * day, step: 7 * day, timeframe: .d1, utcOffset: cet) }
        XCTAssertEqual(labelled.count, 4)
    }
}
