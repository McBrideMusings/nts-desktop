import XCTest
@testable import TrackHold

final class TrackHoldTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    /// NTS's push lands ~11s after the track's `start_time`.
    var started: Date { now.addingTimeInterval(-11) }

    func push(_ hold: inout TrackHold<String>, _ payload: String = "B", key: String? = "B",
              startedAt: Date? = nil, shown: String? = "A", playing: Bool = true,
              buffered: TimeInterval, at: Date? = nil) -> TrackHold<String>.Step {
        hold.receive(payload, key: key, startedAt: startedAt ?? started, shownKey: shown,
                     playing: playing, buffered: buffered, now: at ?? now)
    }

    func testChannelBufferOf5sHasPassedByThePushSoItShowsAtOnce() {
        var hold = TrackHold<String>()
        XCTAssertEqual(push(&hold, buffered: 5), .show)
        XCTAssertNil(hold.held)
    }

    func testMixtapeBufferOf29sHoldsTheRemaining18s() {
        var hold = TrackHold<String>()
        XCTAssertEqual(push(&hold, buffered: 29), .hold(until: now.addingTimeInterval(18)))
        XCTAssertEqual(hold.held?.payload, "B")
    }

    func testHoldNeverRunsPast60sFromArrival() {
        var hold = TrackHold<String>()
        XCTAssertEqual(push(&hold, buffered: 900), .hold(until: now.addingTimeInterval(60)))
        var skewed = TrackHold<String>()
        XCTAssertEqual(push(&skewed, startedAt: now.addingTimeInterval(3600), buffered: 5),
                       .hold(until: now.addingTimeInterval(60)))
    }

    func testRevisedRepushOfTheHeldTrackKeepsItsDeadlineAndTakesTheNewContents() {
        var hold = TrackHold<String>()
        XCTAssertEqual(push(&hold, buffered: 29), .hold(until: now.addingTimeInterval(18)))
        let later = now.addingTimeInterval(10)
        XCTAssertEqual(push(&hold, "B revised", buffered: 29, at: later),
                       .hold(until: now.addingTimeInterval(18)))
        XCTAssertEqual(hold.held?.payload, "B revised")
    }

    func testNothingToStayBehindShowsAtOnceAndDropsTheHold() {
        var hold = TrackHold<String>()
        _ = push(&hold, buffered: 29)
        XCTAssertEqual(push(&hold, "C", key: "C", playing: false, buffered: 29), .show, "paused")
        XCTAssertNil(hold.held)
        XCTAssertEqual(push(&hold, shown: nil, buffered: 29), .show, "empty list on screen")
        XCTAssertEqual(push(&hold, key: "A", buffered: 29), .show, "same top row")
    }

    func testMissingStartTimeCountsTheBufferFromArrival() {
        var hold = TrackHold<String>()
        let step = hold.receive("B", key: "B", startedAt: nil, shownKey: "A",
                                playing: true, buffered: 5, now: now)
        XCTAssertEqual(step, .hold(until: now.addingTimeInterval(5)))
    }

    func testEmptyPushOverAShownListIsHeldLikeAnyNewTopRow() {
        var hold = TrackHold<String>()
        XCTAssertEqual(push(&hold, "", key: nil, buffered: 29), .hold(until: now.addingTimeInterval(18)))
        hold.clear()
        XCTAssertNil(hold.held)
    }
}
