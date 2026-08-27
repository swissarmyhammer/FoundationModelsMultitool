import Foundation
import FoundationModels
import Testing

import FoundationModelsMultitool

/// The bare-session scenario: the files verbs mounted on a plain
/// `LanguageModelSession` with no Router at all.
///
/// Each files verb holds the `FileContext` its capability made and reads no
/// ambient `ToolContext`, so a bare session answers exactly as a routed one
/// does. The root package's `PlainToolContractTests` holds that contract
/// with no model; this suite drives it through a real one. The scenario seeds
/// one file, asks the model to read it through `tools.files.read`, and
/// expects the answer to carry the file's own text. `runBareSessionScenario`
/// carries the model guard, the session, and the assertion; this suite
/// supplies the tools and the prompt.
///
/// Serialized exactly like the other gated suites, and unreachable from the
/// root `swift test`, which declares no target for this nested
/// `IntegrationTests` package.
@Suite(
    "A file read on a bare LanguageModelSession",
    .serialized,
    .timeLimit(.minutes(bareSessionTimeLimitMinutes))
)
struct FilesBareSessionTests {

    @Test("read answers a seeded file on a bare session, and the answer carries its content")
    func readAnswersASeededFileOnABareSession() async throws {
        let root = LiveRouterFixture.makeTempDir()
        let fileURL = root.appendingPathComponent(filesBareSessionFileName, isDirectory: false)
        try Data(filesBareSessionFileText.utf8).write(to: fileURL)
        let capability = FilesCapability(root: root)

        try await runBareSessionScenario(
            named: filesBareSessionScenarioName,
            tools: capability.tools,
            prompt: filesBareSessionPrompt(path: fileURL.path),
            marker: filesBareSessionMarker)
    }
}

/// The label the printed result and skip lines carry.
private let filesBareSessionScenarioName = "bareSessionFileRead"

/// The name of the seeded file.
private let filesBareSessionFileName = "seed.txt"

/// The text the seeded file holds, and the text the answer must carry.
private let filesBareSessionMarker = "pelican"

/// The whole content of the seeded file: the marker and one line break.
private let filesBareSessionFileText = "\(filesBareSessionMarker)\n"

/// The request the model is given.
///
/// It names the file and asks for its text word for word, so an answer that
/// carries the marker is one the tool's result supplied.
///
/// - Parameter path: the absolute path of the seeded file.
/// - Returns: the prompt.
private func filesBareSessionPrompt(path: String) -> String {
    "Use the read tool to read the file at \(path), then reply with exactly the text the file holds."
}
