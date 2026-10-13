import FoundationModelsRouter

@testable import MultitoolTestSupport

/// Tells when the three model handles of one resolved profile are free.
///
/// **Why it exists.** A handle of a resolved profile keeps the holds of its
/// resolve, and each hold keeps the session bytes of that resolve in the pool
/// (`RoutedModel.residencyHolds`). Router prices each later resolve against
/// the footprint of the pool. Thus the next scenario can resolve its profile
/// only after the handles of the last scenario are free.
///
/// The end of the body of a scenario does not make the handles free. A
/// session keeps its profile, and Router can keep a closed session for some
/// time after `RoutedSession.close()` returns. CI run `38390871184` shows
/// this: the shell background scenario cancels its background `runCode` run
/// after the turn. The terminal event of that run starts a new answer, and
/// `close()` cancels that answer. The generation of the cancelled answer then
/// continues on the model and keeps the session, thus also the profile. The
/// next two resolves found a budget of 144789 bytes and failed with
/// `ResolutionFailure`.
///
/// The fixture thus gives the turnstile back only when this value tells that
/// the handles are free (see `LiveRouterFixture.tearDown(awaiting:)`). A
/// scenario that never frees its handles records an issue in its own test,
/// and not in the test after it.
///
/// The value keeps weak references only, thus it does not keep a handle
/// itself.
struct LiveProfileRelease: Sendable {

    /// One weak reference to one object, with the name that an issue gives
    /// for it.
    private struct WeakReference: Sendable {
        /// The name of the object, for example the slot of a handle.
        let name: String

        /// The object, or `nil` when it is free.
        weak var object: (any AnyObject & Sendable)?
    }

    /// The weak reference to each object.
    private let references: [WeakReference]

    /// Makes a release for the three model handles of `profile`.
    ///
    /// - Parameter profile: the resolved profile of a fixture.
    init(of profile: LanguageModelProfile) {
        self.init(
            watching: [
                ("standard", profile.standard),
                ("flash", profile.flash),
                ("embedding", profile.embedding),
            ]
        )
    }

    /// Makes a release for each object in `objects`.
    ///
    /// - Parameter objects: each object, with the name that an issue gives
    ///   for it.
    init(watching objects: [(name: String, object: any AnyObject & Sendable)]) {
        references = objects.map { WeakReference(name: $0.name, object: $0.object) }
    }

    /// The name of each object that is not free, in the order of the init.
    var heldNames: [String] {
        references.filter { $0.object != nil }.map(\.name)
    }

    /// Tells if each object is free.
    var isReleased: Bool {
        heldNames.isEmpty
    }

    /// Waits until each object is free, or until `deadline` passes.
    ///
    /// - Parameter deadline: how long to wait. The default is the one hang
    ///   guard of the polls of this target, `IntegrationPoll.deadline`.
    /// - Returns: `true` when each object is free.
    func awaitRelease(before deadline: Duration = IntegrationPoll.deadline) async -> Bool {
        await TestPoll.holds(before: deadline, every: IntegrationPoll.interval) { isReleased }
    }
}
