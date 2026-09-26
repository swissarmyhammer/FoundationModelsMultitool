import Testing

@testable import FoundationModelsMultitool
@testable import MultitoolTestSupport

/// The live tests of the address guard, with the real DNS resolver (web.md
/// § "Testing", Level 2, the `GuardLiveTests` row).
///
/// `localtest.me` is a public DNS name that resolves to `127.0.0.1`. Its name
/// is on no blocklist, thus only the check of the resolved address can refuse
/// it. The refusal proves that the guard checks the resolved address, and not
/// only the host name. The guard refuses each URL of this suite before a
/// request, thus no HTTP request leaves the computer. A test does not retry.
@Suite(
    "Live: the address guard refuses loopback and metadata addresses",
    .serialized,
    .timeLimit(.minutes(LiveSearch.timeLimitMinutes))
)
struct GuardLiveTests {
    /// A public DNS name that resolves to the loopback address.
    private static let loopbackNameURL = "http://localtest.me/"

    /// The correction of the guard for ``loopbackNameURL``.
    private static let loopbackCorrection =
        "The address is not allowed: localtest.me resolves to 127.0.0.1, a loopback address."

    /// The URL of the cloud metadata service.
    private static let metadataURL = "http://169.254.169.254/latest/meta-data/"

    /// The correction of the guard for ``metadataURL``.
    private static let metadataCorrection =
        "The address is not allowed: the host 169.254.169.254 is on the blocklist."

    @Test("localtest.me gives the correction that names its loopback address")
    func loopbackNameIsRefused() async throws {
        let result = try await WebVerbCall.fetch(Self.loopbackNameURL, context: LiveFetch.makeContext())

        #expect(result.correction == Self.loopbackCorrection)
    }

    @Test("the cloud metadata address gives a correction")
    func metadataAddressIsRefused() async throws {
        let result = try await WebVerbCall.fetch(Self.metadataURL, context: LiveFetch.makeContext())

        #expect(result.correction == Self.metadataCorrection)
    }
}
