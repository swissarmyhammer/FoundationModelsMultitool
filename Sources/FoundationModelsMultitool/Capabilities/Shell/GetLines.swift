// `GetLines` — the `tools.shell.getLines` verb.
//
// A behavioral port of `../FoundationModelsShelltool/Sources/ShellTool/
// Operations/GetLines.swift`. The sibling is an `@Operation` that takes a
// `ShellContext`; this package has neither, thus the verb is a plain
// `FoundationModels.Tool` that holds the store it reads.
//
// eventplan.md § "Consolidation of the siblings": "Captured content lives in
// the store of the capability that owns it. Shell output stays in the
// per-session dotfolder. `tools.shell.getLines` and `tools.shell.grepHistory`
// read it as usual surface operations. They apply to a live background run
// (`OutputBuffer` reads while the child runs) and to a completed run (the store
// stays after the run)."
//
// This verb is the CONTENT plane, and it is no run-plane surface. It reads what
// a run has written up to now, and it never waits for a run to write more. The
// sibling carries a `waitSeconds` long-poll for that; here the shared elevation
// engine owns the wait, through `WaitTool` and the `wait(token, seconds)`
// sandbox global. Thus one design answers "when is this run done", and one
// answers "what did this run write".
//
// The identifier is the completion-token `String` of the run — the one string
// that is also the `commandID` of `ShellState` and the `correlationID` of the
// Router mailbox (see `ShellState.startCommand(_:commandID:)`). The verb mints
// nothing.
//
// The buffer of a run is private to `ShellRunner.consume`, which writes the
// lines each chunk completes into `ShellState` as the chunks arrive. Thus a
// read of the store IS the read of the capture, and a run that is still going
// answers with the output it wrote before this read.
//
// A read the store cannot make stays IN BAND, as a `correction` beside an empty
// range. It is never thrown: a token no command ran under, and a line range
// that reads nothing, are each a mistake the model corrects inside the turn,
// and a thrown error would end the turn instead.

import FoundationModels

/// The arguments of `tools.shell.getLines`: which run to read, and which lines
/// of it.
@Generable
struct GetLinesArguments {

    /// The completion token of the run whose output to read.
    @Guide(
        description:
            "The completion token of the run whose output to read — the identifier shell.execute "
            + "answered with.")
    var commandID: String

    /// The first line number to read, or `nil` for the first stored line.
    @Guide(description: "The first line number to read. Omit it to read from the first line.")
    var start: Int?

    /// The last line number to read, or `nil` for the last stored line.
    @Guide(description: "The last line number to read. Omit it to read to the last line.")
    var end: Int?
}

/// The result of `tools.shell.getLines`: the lines the read covered, or the
/// correction that says why it covered none.
///
/// `correction` and the lines are exclusive. A read that answers lines carries
/// no correction, and a correction carries no line, no bound and no status.
@Generable(description: "the lines of one run, or the correction that says why there are none.")
struct GetLinesResult {

    /// The completion token of the run these lines came from.
    var commandID: String

    /// The first line number the read covered, or `0` when it covered none.
    var first: Int

    /// The last line number the read covered, or `0` when it covered none.
    var last: Int

    /// The lines the read covered, each one formatted `"{lineNumber}: {text}"`.
    var lines: [String]

    /// The status of the run now — `running`, `completed`, `killed` or
    /// `timed_out` — or `nil` when the read carries a correction instead.
    ///
    /// This is how the model learns whether more output is still to come:
    /// `running` says to read again later, and any other value says the run
    /// wrote everything it is going to write.
    var status: String?

    /// Why the read covered no line, or `nil` when the read was made.
    var correction: String?
}

extension GetLines {

    /// The number the store counts the lines of one command from.
    private static let firstLineNumber = 1

    /// The bound each end of an empty range carries, because no line number
    /// stands there.
    private static let emptyRangeBound = 0

    /// Reads the requested lines of one run out of the store.
    ///
    /// The order of the two guards is what keeps each corrective answer in
    /// band. The range is examined first, because a range that reads nothing is
    /// wrong for a known token and for an unknown one alike. The record is read
    /// second, because `ShellState.getLines` THROWS for a token no command ran
    /// under, and this verb must answer that token with a correction instead.
    ///
    /// - Parameter arguments: The run to read, and the lines of it.
    /// - Returns: The lines the read covered, or the correction that says why
    ///   it covered none.
    /// - Throws: What `ShellState.getLines` throws for a log file that does not
    ///   read. A token no command ran under does not reach it.
    func call(arguments: GetLinesArguments) async throws -> GetLinesResult {
        let start = arguments.start ?? Self.firstLineNumber
        if let correction = Self.rangeCorrection(start: start, end: arguments.end) {
            return Self.corrected(correction, commandID: arguments.commandID)
        }

        guard let record = await state.record(commandID: arguments.commandID) else {
            return Self.corrected(
                Self.unknownTokenCorrection(arguments.commandID), commandID: arguments.commandID)
        }

        let lines = try await state.getLines(
            commandID: arguments.commandID, start: start, end: arguments.end)
        return GetLinesResult(
            commandID: arguments.commandID,
            first: lines.first?.lineNumber ?? Self.emptyRangeBound,
            last: lines.last?.lineNumber ?? Self.emptyRangeBound,
            lines: lines.map { "\($0.lineNumber): \($0.text)" },
            status: record.status.rawValue,
            correction: nil
        )
    }

    /// Why a `start...end` range reads nothing, or `nil` when the range is
    /// readable.
    ///
    /// - Parameters:
    ///   - start: The first line number the read asks for.
    ///   - end: The last line number the read asks for, or `nil` for no upper
    ///     bound.
    /// - Returns: The correction, or `nil`.
    private static func rangeCorrection(start: Int, end: Int?) -> String? {
        if start < firstLineNumber {
            return "The store counts the lines of one command from \(firstLineNumber), thus a "
                + "start of \(start) reads nothing. Ask for a start of \(firstLineNumber) or more."
        }
        if let end, end < start {
            return "The end \(end) stands before the start \(start), thus the range reads nothing. "
                + "Ask for an end of \(start) or more."
        }
        return nil
    }

    /// What a token no command of this session ran under says to the model.
    ///
    /// - Parameter commandID: The token the read named.
    /// - Returns: The correction.
    private static func unknownTokenCorrection(_ commandID: String) -> String {
        "No command of this session ran under the completion token \(commandID). Read the token "
            + "from the run that started the command."
    }

    /// The empty range one correction stands in place of.
    ///
    /// - Parameters:
    ///   - message: Why the read covered no line.
    ///   - commandID: The token the read named.
    /// - Returns: The corrective result.
    private static func corrected(_ message: String, commandID: String) -> GetLinesResult {
        GetLinesResult(
            commandID: commandID,
            first: emptyRangeBound,
            last: emptyRangeBound,
            lines: [],
            status: nil,
            correction: message
        )
    }
}

/// Reads the captured output of one shell run by line number.
///
/// ```swift
/// // In a snippet the model writes:
/// //   const tail = await tools.shell.getLines({ commandID: token, start: 40 });
/// ```
///
/// The store it reads is the store the capability owns, thus each verb of one
/// capability answers for the same session.
struct GetLines: Tool {

    /// The verb this tool renders as, which the shell noun stands in front of:
    /// `tools.shell.getLines`.
    let name = "getLines"

    /// The usage instructions, as the model reads them.
    let description = """
        getLines reads the captured output of one shell run, by line number. commandID is the \
        completion token the run answered with. It reads a run that is still going and a run that \
        ended alike: the status field says which, and `running` means more output is still to \
        come. Omit start and end to read the whole output. A token no run of this session ran \
        under, and a range that reads nothing, each come back as a correction rather than as an \
        error — read it, correct the call, and ask again.
        """

    /// The store this verb reads, which the shell capability owns.
    let state: ShellState

    /// Makes the verb over one store.
    ///
    /// - Parameter state: The history and output store of the shell capability.
    init(state: ShellState) {
        self.state = state
    }
}
