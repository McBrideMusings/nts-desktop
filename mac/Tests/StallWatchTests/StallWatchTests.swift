import XCTest
@testable import StallWatch

final class StallWatchTests: XCTestCase {
    let silent = StallWatch.Player(playing: true, rendering: false, reloadable: true)
    let rendering = StallWatch.Player(playing: true, rendering: true, reloadable: true)
    let paused = StallWatch.Player(playing: false, rendering: false, reloadable: true)

    /// A watch on a stream that has been playing cleanly.
    func playing() -> StallWatch {
        var watch = StallWatch()
        XCTAssertEqual(watch.changed(rendering), .disarm)
        return watch
    }

    func testStreamThatNeverReturnsBacksOffTo30s() {
        var watch = playing()
        XCTAssertEqual(watch.changed(silent), .arm(.grace, .seconds(15)))
        var checks: [Duration] = []
        var timer = StallWatch.Timer.grace
        for _ in 0..<6 {
            guard case .reload(_, let check) = watch.fired(timer, silent) else {
                return XCTFail("expected a reload")
            }
            checks.append(check)
            timer = .retry
        }
        XCTAssertEqual(checks, [5, 10, 20, 30, 30, 30].map { .seconds($0) })
        XCTAssertEqual(watch.attempts, 6)
    }

    /// The bead's case: each reload plays for a moment and drops. The streak
    /// keeps counting, the gap before each reload grows, and no blip counts
    /// as a recovery.
    func testStreamThatKeepsDroppingBacksOff() {
        var watch = playing()
        var gaps: [Duration] = []
        guard case .arm(.grace, let first) = watch.changed(silent) else { return XCTFail() }
        gaps.append(first)
        for attempt in 1...6 {
            XCTAssertEqual(watch.fired(.grace, silent),
                           .reload(attempt: attempt, check: StallWatch.backoff(after: attempt)))
            XCTAssertEqual(watch.changed(rendering), .arm(.settle, .seconds(60)))
            guard case .arm(.grace, let gap) = watch.changed(silent) else { return XCTFail() }
            gaps.append(gap)
        }
        XCTAssertEqual(gaps, [15, 20, 25, 35, 45, 45, 45].map { .seconds($0) })
        XCTAssertEqual(watch.attempts, 6)
        XCTAssertEqual(watch.recoveries, 0)
    }

    func testReloadThatHoldsForTheSettleEndsTheStreak() {
        var watch = playing()
        _ = watch.changed(silent)
        _ = watch.fired(.grace, silent)
        _ = watch.fired(.retry, silent)
        XCTAssertEqual(watch.changed(rendering), .arm(.settle, .seconds(60)))
        XCTAssertEqual(watch.fired(.settle, rendering), .recovered(after: 2))
        XCTAssertEqual(watch.attempts, 0)
        XCTAssertEqual(watch.recoveries, 1)
        XCTAssertNil(watch.pending)
        // A later drop starts a fresh streak at the plain grace.
        XCTAssertEqual(watch.changed(silent), .arm(.grace, .seconds(15)))
    }

    func testFailureReloadsAtOnceOnlyOutsideAStreak() {
        var watch = playing()
        XCTAssertEqual(watch.failed(rendering), .reload(attempt: 1, check: .seconds(5)))
        XCTAssertEqual(watch.changed(rendering), .arm(.settle, .seconds(60)))
        // Dying again inside the settle waits for the silence timer instead.
        XCTAssertEqual(watch.failed(rendering), StallWatch.Step.none)
        XCTAssertEqual(watch.changed(silent), .arm(.grace, .seconds(20)))
    }

    func testRetryPendingIsNotReplacedByGrace() {
        var watch = playing()
        _ = watch.changed(silent)
        _ = watch.fired(.grace, silent)
        XCTAssertEqual(watch.pending, .retry)
        XCTAssertEqual(watch.changed(silent), StallWatch.Step.none)
    }

    func testWakeWhileRenderingDuringSettleChangesNothing() {
        var watch = playing()
        _ = watch.changed(silent)
        _ = watch.fired(.grace, silent)
        _ = watch.changed(rendering)
        XCTAssertEqual(watch.stalled(rendering), .skip)
        XCTAssertEqual(watch.pending, .settle)
        XCTAssertEqual(watch.attempts, 1)
    }

    func testPausingMidStreakDropsIt() {
        var watch = playing()
        _ = watch.changed(silent)
        _ = watch.fired(.grace, silent)
        _ = watch.changed(rendering)
        XCTAssertEqual(watch.changed(paused), .dropped(after: 1))
        XCTAssertEqual(watch.attempts, 0)
        XCTAssertEqual(watch.recoveries, 0)
    }

    func testPauseBeforeRenderingCatchesUpIsNotARecovery() {
        var watch = playing()
        _ = watch.changed(silent)
        _ = watch.fired(.grace, silent)
        _ = watch.changed(rendering)
        let stale = StallWatch.Player(playing: false, rendering: true, reloadable: true)
        XCTAssertEqual(watch.changed(stale), .dropped(after: 1))
        XCTAssertEqual(watch.recoveries, 0)
    }

    func testEpisodeIsNeverReloaded() {
        var watch = StallWatch()
        let episode = StallWatch.Player(playing: true, rendering: false, reloadable: false)
        XCTAssertEqual(watch.changed(episode), .disarm)
        XCTAssertEqual(watch.stalled(episode), .skip)
        XCTAssertEqual(watch.failed(episode), .skip)
        XCTAssertEqual(watch.attempts, 0)
    }
}
