// `FileChangeAttachmentTests` — a mutating file verb attaches its change set as
// a `ToolCallAttachment`, thus the set reaches a host LIVE.
//
// UPSTREAM_ASKS.md, ask 4, part 4. `FileChangeEventTests` and
// `FileChangeRunCodeTests` prove the `.progress` `OperationEvent` half of the
// delivery. That event is the model-facing preamble and the durable recording,
// and the Router does not put a `.progress` event on a live stream at all. The
// live carrier is `ToolContext.attach(_:)`: a call that closes with at least one
// record makes ONE `SessionEvent.toolCallReport`, and this suite reads that
// event off the stream of that answer.
//
// **Why the ground is a tool that runs the snippet itself.** The report of a
// call reaches a host only through `SessionEvent`, and a record attached after
// its call closed belongs to no settlement. The captured `ToolContext` of
// `makeStubRun()` belongs to a call that has already returned, so no suite over
// that ground can observe an attachment. `SnippetRunningTool` runs the snippet
// from inside its OWN live session call instead, which is the shape a host
// really drives: `RunBinding.invoke` mounts each inner `tools.*` call on the
// ambient context, and the attachments of a mounted call ride the MOUNTING
// run's report.

import Foundation
import FoundationModels
import FoundationModelsRouter
import Testing

@testable import FoundationModelsMultitool

/// A tool that runs one fixed `runCode` snippet from inside its own session call.
///
/// It takes ``CaptureArguments`` because that is how `ToolCallingBackend`
/// recognizes the tool to call, and it answers the rendered `runCode` output
/// unchanged.
private struct SnippetRunningTool: Tool {
    let name = "runSnippet"
    let description = "Runs one fixed runCode snippet over the tools registry."

    /// The tool each `tools.*` call of the snippet dispatches through.
    let multiTool: MultiTool

    /// The snippet to run.
    let code: String

    func call(arguments: CaptureArguments) async throws -> String {
        try await multiTool.call(arguments: RunCodeArguments(code: code))
    }
}

/// Behavioral tests for the attachment a mutating verb call makes.
@Suite("FileChangeAttachmentTests", .ownsTemporaryDirectories)
struct FileChangeAttachmentTests {

    /// The name of the temporary directory of one test. Thus a leaked
    /// directory is traceable to this suite.
    private static let testDirectoryName = "FileChangeAttachmentTests"

    /// The file the write snippet writes.
    private static let writtenFileName = "new.txt"

    /// The content the write snippet writes.
    private static let writtenContent = "hello\n"

    /// How many reports one snippet that writes one file makes.
    private static let reportsPerCall = 1

    /// How many records one mutating verb call attaches.
    private static let attachmentsPerCall = 1

    /// How many tool calls the host sees this answer make.
    ///
    /// One: the mounted `runSnippet` call. `ToolContext.mount(_:op:as:)`
    /// swallows the invocation records of each verb call the snippet makes
    /// inside it, so the outer call is the one call a host can join against.
    private static let callsPerAnswer = 1

    /// The prompt the stub backend answers by calling the mounted tool. It is
    /// unread — the backend calls the tool whatever the prompt says.
    private static let prompt = "write the file"

    // MARK: - The ground of one test

    /// One answer of a session that mounts a snippet-running tool: the files
    /// ground the snippet ran over, and every event the answer delivered.
    private struct Answer {
        /// The files registry and the change journal the snippet ran over.
        let ground: FilesRun

        /// Every event the answer delivered, in arrival order.
        let events: [SessionEvent]

        /// The reports the answer delivered, in arrival order.
        var reports: [ToolCallReport] {
            events.compactMap { event in
                if case .toolCallReport(let report) = event { return report }
                return nil
            }
        }

        /// The close invocation record of each call the answer made, in arrival order.
        var closeRecords: [ToolInvocationRecord] {
            events.compactMap { event in
                if case .toolInvocation(let record, _) = event, record.closedAt != nil { return record }
                return nil
            }
        }
    }

    /// Runs one snippet inside a live session call and reads the stream of the answer.
    ///
    /// The function reads the stream to its end, and then closes the two
    /// sessions it made, on every path. The answer keeps the files ground,
    /// and a test reads only its registry, its root and its journal.
    ///
    /// - Parameter code: the snippet to run.
    /// - Returns: the answer.
    /// - Throws: whatever standing up the session, or the answer itself, throws.
    private static func runAnswer(_ code: String) async throws -> Answer {
        try await withFilesRun(named: testDirectoryName, recordsChanges: true) { ground in
            try await withStubSession(
                mounting: [SnippetRunningTool(multiTool: MultiTool(registry: ground.registry), code: code)]
            ) { session, _ in
                var events: [SessionEvent] = []
                for try await event in await session.streamEvents(to: prompt) {
                    events.append(event)
                }
                return Answer(ground: ground, events: events)
            }
        }
    }

    /// Runs the write snippet of this suite inside a live session call.
    ///
    /// - Returns: the answer.
    /// - Throws: whatever ``runAnswer(_:)`` throws.
    private static func runWriteAnswer() async throws -> Answer {
        try await runAnswer(writeVerbSnippet(writing: writtenFileName, content: writtenContent))
    }

    // MARK: - The attached record

    @Test("a mutating verb call attaches one record whose document decodes back to the change set")
    func aMutatingVerbCallAttachesOneRecord() async throws {
        let answer = try await Self.runWriteAnswer()
        let report = try #require(answer.reports.first, "the answer delivered no report")
        let attachment = try #require(report.attachments.first)
        let decoded = try #require(FileChangeSet(operationEventDetail: attachment.contentJSON))

        #expect(answer.reports.count == Self.reportsPerCall, "reports were: \(answer.reports)")
        #expect(
            report.attachments.count == Self.attachmentsPerCall,
            "attachments were: \(report.attachments)")
        #expect(attachment.schemaName == FileChangeSet.operationEventDetailKey)
        #expect(
            decoded
                == FileChangeSet(
                    root: answer.ground.journal.root,
                    changes: [
                        FileChange(
                            kind: .add,
                            path: TestSupport.path(Self.writtenFileName, in: answer.ground.root),
                            newContent: Self.writtenContent)
                    ]))
    }

    // MARK: - The call the record belongs to

    @Test("the report of the attached record carries the identity of the call the host sees")
    func theReportCarriesTheIdentityOfTheCallTheHostSees() async throws {
        let answer = try await Self.runWriteAnswer()
        let report = try #require(answer.reports.first, "the answer delivered no report")
        let close = try #require(answer.closeRecords.first)

        // The join a host makes: the report and the close record of one call
        // name the same call, so a host that has already opened a tool call on
        // the record can fill that call's touched paths from the report.
        #expect(answer.closeRecords.count == Self.callsPerAnswer, "close records were: \(answer.closeRecords)")
        #expect(report.correlationID == close.correlationID)
        #expect(report.tool == close.tool)
        #expect(report.op == close.op)
        #expect(report.sessionID == close.sessionID)
    }
}
