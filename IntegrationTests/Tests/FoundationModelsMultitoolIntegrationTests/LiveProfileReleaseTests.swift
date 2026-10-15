import Testing

/// The offline checks of `LiveProfileRelease`, the check that keeps the
/// turnstile of this target until the model handles of the last live profile
/// are free.
///
/// CI run `38390871184` is the reason. A task of Router kept the closed
/// session of the shell background scenario, thus also its profile, after the
/// scenario returned. The fixture gave the turnstile back at that moment, and
/// the next two resolves were priced against the session bytes of the old
/// profile and failed. Router `7fbcf9b7` makes `RoutedSession.close()` wait
/// for that task, thus the fixture now checks the handles one time, with no
/// wait. Each check here gives plain objects in place of model handles. No
/// check loads a model, thus each check always runs, and it is fast.
///
/// Each handle that a check lets go stands in a `do` block of its own: a
/// local value lives until the end of its scope, and the end of the block is
/// the moment the check lets the handle go.
@Suite("The fixture checks that the handles of a live profile are free")
struct LiveProfileReleaseTests {

    /// An object in place of one model handle.
    private final class Handle: Sendable {}

    @Test("a handle that a task keeps is free when the task ended and nothing keeps the task")
    func freeWhenTheTaskThatKeepsAHandleEnded() async {
        let (letGo, letGoContinuation) = AsyncStream.makeStream(of: Void.self)
        let release: LiveProfileRelease
        do {
            let holder: Task<Void, Never>
            do {
                let standard = Handle()
                release = LiveProfileRelease(watching: [("standard", standard)])
                holder = Task {
                    for await _ in letGo {}
                    withExtendedLifetime(standard) {}
                }
            }

            #expect(!release.isReleased)
            #expect(release.heldNames == ["standard"])

            letGoContinuation.finish()
            await holder.value
        }

        #expect(release.isReleased)
        #expect(release.heldNames.isEmpty)
    }

    @Test("a handle that stays held makes the check false, and the release names it")
    func namesAHandleThatStaysHeld() {
        let standard = Handle()
        let flash = Handle()
        let release: LiveProfileRelease
        do {
            let embedding = Handle()
            release = LiveProfileRelease(watching: [("standard", standard), ("flash", flash), ("embedding", embedding)])
        }

        #expect(!release.isReleased)
        #expect(release.heldNames == ["standard", "flash"])
        withExtendedLifetime((standard, flash)) {}
    }

    @Test("the release keeps no handle itself")
    func keepsNoHandle() {
        let release: LiveProfileRelease
        do {
            let embedding = Handle()
            release = LiveProfileRelease(watching: [("embedding", embedding)])
        }

        #expect(release.isReleased)
        #expect(release.heldNames.isEmpty)
    }
}
