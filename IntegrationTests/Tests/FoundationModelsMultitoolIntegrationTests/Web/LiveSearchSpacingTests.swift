import Foundation
import Testing

/// The offline checks of ``LiveSearchSpacing``: the turns that keep the live
/// search requests of the test process apart (card `^kghyac5`).
///
/// Each check gives the instants to the spacing. No check waits on the
/// clock, and no check sends a request. Thus each check always runs, and it
/// is fast.
@Suite("LiveSearchSpacing: live search requests start an interval apart")
struct LiveSearchSpacingTests {
    /// The interval of each spacing in this suite.
    private static let interval = Duration.seconds(2)

    /// The gap between two requests of the failed run: the second Brave
    /// request came this long after the first, and got HTTP 429.
    private static let observedGap = Duration.milliseconds(600)

    /// A gap that is longer than ``interval``.
    private static let longGap = Duration.seconds(5)

    @Test("the first turn starts at once")
    func firstTurnStartsAtOnce() async {
        let spacing = LiveSearchSpacing(interval: Self.interval)
        let now = ContinuousClock.now
        #expect(await spacing.reserveTurn(at: now) == now)
    }

    @Test("a turn that comes before the interval ends starts one interval after the previous turn")
    func earlyTurnWaitsForTheInterval() async {
        let spacing = LiveSearchSpacing(interval: Self.interval)
        let first = ContinuousClock.now
        _ = await spacing.reserveTurn(at: first)
        let second = await spacing.reserveTurn(at: first.advanced(by: Self.observedGap))
        #expect(second == first.advanced(by: Self.interval))
    }

    @Test("a turn that comes after the interval ends starts at once")
    func lateTurnStartsAtOnce() async {
        let spacing = LiveSearchSpacing(interval: Self.interval)
        let first = ContinuousClock.now
        _ = await spacing.reserveTurn(at: first)
        let late = first.advanced(by: Self.longGap)
        #expect(await spacing.reserveTurn(at: late) == late)
    }

    @Test("turns that come together start one interval apart, in the order of the reservations")
    func turnsThatComeTogetherQueue() async {
        let spacing = LiveSearchSpacing(interval: Self.interval)
        let now = ContinuousClock.now
        _ = await spacing.reserveTurn(at: now)
        _ = await spacing.reserveTurn(at: now)
        let third = await spacing.reserveTurn(at: now)
        #expect(third == now.advanced(by: Self.interval).advanced(by: Self.interval))
    }
}
