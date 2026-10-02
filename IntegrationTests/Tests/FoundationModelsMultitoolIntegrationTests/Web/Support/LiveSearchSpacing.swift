// `LiveSearchSpacing` — the turns that keep the live search requests of the
// test process apart (card `^kghyac5`).
//
// Two live requests to the Brave results page 0.6 s apart gave HTTP 429 to
// the second one. web.md § "Fallback" makes a 429 a skip of the provider, and
// a suite with one provider then gets a correction. That is correct product
// behavior, thus the test support code, not the product, keeps the requests
// apart. A turn does not retry and does not change a time limit: each test
// still sends one request, and a 429 that comes with the spacing still fails.

/// One spacing between the starts of live search requests.
///
/// A caller takes a turn before each request. A turn starts at least
/// ``interval`` after the start of the previous turn. The turns start in the
/// order of their reservations.
actor LiveSearchSpacing {
    /// The shortest time between the starts of two turns.
    let interval: Duration

    /// The start of the latest reserved turn, or `nil` before the first turn.
    private var latestStart: ContinuousClock.Instant?

    /// Creates a spacing with no reserved turn.
    ///
    /// - Parameter interval: The shortest time between the starts of two turns.
    init(interval: Duration) {
        self.interval = interval
    }

    /// Reserves the next turn.
    ///
    /// The reservation is a pure function of the instants, thus a test gives
    /// the instants and does not wait.
    ///
    /// - Parameter now: The instant of the request for the turn.
    /// - Returns: The instant at which the turn starts: `now`, or ``interval``
    ///   after the start of the previous turn, whichever is later.
    func reserveTurn(at now: ContinuousClock.Instant) -> ContinuousClock.Instant {
        let start = latestStart.map { max(now, $0.advanced(by: interval)) } ?? now
        latestStart = start
        return start
    }

    /// Reserves the next turn on the continuous clock, and waits until it
    /// starts.
    ///
    /// - Throws: `CancellationError` when the calling task is cancelled
    ///   during the wait.
    func waitForTurn() async throws {
        let clock = ContinuousClock()
        let start = reserveTurn(at: clock.now)
        try await clock.sleep(until: start)
    }
}
