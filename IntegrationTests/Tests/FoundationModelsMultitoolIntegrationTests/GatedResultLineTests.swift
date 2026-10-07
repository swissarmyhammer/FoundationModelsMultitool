import Foundation
import ScenarioGrading
import Testing

@testable import FoundationModelsMultitool

/// The offline checks of the shared `RESULT` line of a gated turn:
/// `gatedResultLine(of:elapsed:readings:replyPreviewCharacters:)` and the
/// field readings that the gated suites give to it.
///
/// Each check makes a `StreamedTurn` by hand. No check loads a model. Thus
/// each check always runs, and a change to the order or to the text of a
/// field fails here before a live run prints a different line.
@Suite("Gated result line: the route, the readings of the scenario, then the start of the reply")
struct GatedResultLineTests {

    /// The snippet of the turn of each check. It calls one verb.
    private static let snippetArguments = #"{"code":"return await tools.git.diff({})"}"#

    /// The reply of the turn of each check.
    private static let reply = "The function area is now surface."

    /// How many characters of the reply each check shows.
    private static let replyPreviewCharacters = 12

    /// How long the turn of each check took, in seconds.
    private static let elapsed: TimeInterval = 2.5

    /// A turn with one `runCode` call, one failed call, a priming failure, and
    /// a reply.
    private static var turn: StreamedTurn {
        var turn = StreamedTurn()
        turn.answer = reply
        turn.toolCallCount = 1
        turn.calls = [
            NativeTranscript.StreamedCall(name: MultiTool.runCodePath, argumentsJSON: snippetArguments, output: nil)
        ]
        turn.failedCalls = ["runCode: refused"]
        turn.discoveryPrimingFailure = "busy"
        return turn
    }

    @Test("the line holds the route, then each reading in order, then the start of the reply")
    func theLineHoldsTheRouteTheReadingsAndTheReply() {
        let line = gatedResultLine(
            of: Self.turn,
            elapsed: Self.elapsed,
            readings: ["first=1", "second=2"],
            replyPreviewCharacters: Self.replyPreviewCharacters)
        #expect(line == #"elapsed=2.5s toolCalls=1 calls=["runCode"] first=1 second=2 reply="The function""#)
    }

    @Test("a line with no reading holds the route, then the start of the reply")
    func aLineWithNoReadingHoldsTheRouteAndTheReply() {
        let line = gatedResultLine(
            of: Self.turn, elapsed: Self.elapsed, readings: [], replyPreviewCharacters: Self.replyPreviewCharacters)
        #expect(line == #"elapsed=2.5s toolCalls=1 calls=["runCode"] reply="The function""#)
    }

    @Test("the typed reading names each verb that the snippets called")
    func theTypedReadingNamesTheSnippetVerbs() {
        #expect(typedPathsReading(of: Self.turn) == #"typed=["git.diff"]"#)
    }

    @Test("the priming reading names why the priming did not run")
    func thePrimingReadingNamesTheFailure() {
        #expect(primingReading(of: Self.turn) == "priming=FAILED(busy)")
    }

    @Test("the failed calls reading names each failed call")
    func theFailedCallsReadingNamesEachFailedCall() {
        #expect(failedCallsReading(of: Self.turn) == #"failedCalls=["runCode: refused"]"#)
    }
}
