import FoundationModelsRouter

@testable import MultitoolTestSupport

/// Tells if the three model handles of one resolved profile are free.
///
/// **Why it exists.** A handle of a resolved profile keeps the holds of its
/// resolve, and each hold keeps the session bytes of that resolve in the pool
/// (`RoutedModel.residencyHolds`). Router prices each later resolve against
/// the footprint of the pool. Thus the next scenario can resolve its profile
/// only after the handles of the last scenario are free.
///
/// CI run `38390871184` shows what occurs when a handle stays held: the shell
/// background scenario cancels its background `runCode` run after the
/// answer. The terminal event of that run starts a new answer, and `close()`
/// cancels that answer. In Router before `7fbcf9b7`, `close()` returned while
/// the generation of the cancelled answer continued on the model. That
/// generation kept the session, thus also the profile. The next two resolves
/// found a budget of 144789 bytes and failed with `ResolutionFailure`.
///
/// Router `7fbcf9b7` makes `RoutedSession.close()` wait for the generation
/// pass and for its helper tasks. Thus, when `close()` returned and the
/// scenario dropped its session and its fixture, each handle is free at
/// once. The fixture checks this value one time, with no wait, before it
/// gives the turnstile back (see `LiveRouterFixture.tearDown(checking:)`). A
/// scenario that keeps a handle records an issue in its own test, and not in
/// the test after it.
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

    /// Tells if each object is free now. This check does not wait.
    var isReleased: Bool {
        heldNames.isEmpty
    }
}
