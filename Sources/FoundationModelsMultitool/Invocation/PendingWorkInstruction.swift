// `PendingWorkInstruction` — the one text that tells the model what to do
// while work it started is still pending.
//
// Five places hand the model this instruction: the `next` sentence of a
// pending `runCode` envelope, the `next` sentence of a pending
// `tools.shell.execute` run, the description of `runCode`, the description of
// `tools.shell.execute`, and the repair text of the removed `wait()` global.
// When each place had its own words, the five texts did not agree, and the
// model did not obey them. In SWE-bench run no-otel-1011 a model made 73 no-op
// `runCode` calls while one run was pending (task `^1dzf1za`). Thus the text is
// here one time, and each place adds only the completion token or the
// commandID that it must name.
//
// The text does not tell the model to end its answer or its turn. A session
// has no turns. The settled run comes back as a new message, and that message
// starts the model again. Parallel tool calls stay free: the model can do
// other work that does not need the result. When no other work can be done,
// the model does nothing.
//
// A snippet that settles inside `inlineSettleGrace` answers with its own
// result, and this text does not show.

/// The instruction that the model gets each time that work it started is
/// still pending.
enum PendingWorkInstruction {
    /// The text of the instruction, as the model reads it.
    ///
    /// Each place that uses it puts the completion token or the commandID of
    /// the pending run in front of it, so the model can match the run to the
    /// message that brings its result.
    static let text = """
        This is not the result. When the work finishes, the session injects its result into \
        this conversation as a new message. That message starts you working again, so you do \
        not need to wait, to check, or to ask for it. Do not call a tool to wait or to check. \
        If you have other work that does not need this result, do that work now. If no other \
        work can be done until the result comes back, do nothing: write no text and call no \
        tool. When the injected result arrives, continue the task from it.
        """
}
