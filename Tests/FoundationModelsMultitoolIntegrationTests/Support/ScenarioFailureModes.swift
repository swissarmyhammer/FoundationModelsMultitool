import Foundation

/// Everything one gated scenario run produced that a failure mode is read
/// off — the raw evidence, before any interpretation.
///
/// Separating the evidence from the derivation is what makes the modes
/// checkable: `ScenarioFailureModeTests` builds these by hand and asserts
/// the rules, so a gated run's `MODES` line rests on a derivation that has
/// itself been tested rather than on a live sample nobody can reproduce.
///
/// Every field is `var` so a test can vary one at a time against a
/// known-clean run.
struct ScenarioObservation {
    /// The model's final reply text.
    var reply: String

    /// How many tool calls the turn made, of any tool.
    var toolCallCount: Int

    /// The `tools.*` paths the model's `runCode` snippets **wrote**.
    ///
    /// This is a lexical scan of the snippet source, not a record of what
    /// resolved — see `NativeTranscript.invokedToolPaths(in:)` and the open
    /// defect `0981ar3`. It is the right evidence for `inventedPath`, whose
    /// question is precisely what the model reached for, and it is the
    /// wrong evidence for "did data come back", which
    /// `returnedValues` answers instead.
    var invokedPaths: Set<String>

    /// Every `tools.*` path the mounted catalog actually defines.
    var catalogPaths: Set<String>

    /// Whether a `findAPIs` call preceded the first `runCode` call.
    var findAPIsFirst: Bool

    /// The scalar values the tools genuinely returned to the model this
    /// turn — see `NativeTranscript.returnedValues(in:)`.
    var returnedValues: Set<String>

    /// Whether the reply carried the form the scenario grades on.
    var validAnswer: Bool
}

/// The fewest tool calls any scenario this runner drives can be answered
/// in: one `findAPIs` to learn the catalog's real names, then one `runCode`
/// to call them.
///
/// A host mounts `MultiTool` with the catalog behind `findAPIs` rather than
/// in the session instructions, so a model that has not searched does not
/// know a single real name — which is why the floor is two rather than one,
/// and why it is the same floor for all four scenarios.
let scenarioMinimumToolCalls = 2

/// How far past `scenarioMinimumToolCalls` a turn may go before it counts
/// as thrashing.
///
/// Doubling the floor leaves room for the repair loop the scenarios
/// deliberately provoke — a mis-called tool, its repairable error, and the
/// corrected call — while still separating "repaired once" from a turn
/// going around the same loop over and over.
let scenarioThrashFactor = 2

/// The shortest returned value that counts as evidence the reply carries
/// tool data.
///
/// A one-character value shares too much with ordinary prose: a reply that
/// happens to contain the digit a tool returned is not thereby grounded in
/// that tool's answer.
private let scenarioGroundingValueMinimumLength = 2

/// The failure modes one gated scenario run exhibited.
///
/// The gated suite grades four scenarios pass/fail, which is four bits per
/// run — too little signal for any experiment to answer its own question at
/// the sample sizes live inference allows. These modes are the observations
/// the same run already produces and used to discard: each is counted
/// alongside the existing grade, never in place of it, so a run yields many
/// signals instead of one.
struct ScenarioFailureModes {
    /// The reply denied access or capability and the turn called nothing at
    /// all.
    let overRefusal: Bool

    /// The reply answered substantively while no snippet invoked any
    /// `tools.*` path.
    let answeredWithoutCalling: Bool

    /// The reply announced what the model was about to do, and the turn
    /// then ended without doing it.
    let announceThenStop: Bool

    /// The `tools.*` paths a snippet wrote that the mounted catalog does
    /// not define, sorted.
    ///
    /// Sorted rather than a set so a run's line is byte-comparable with the
    /// next run's.
    let inventedPaths: [String]

    /// A `findAPIs` call preceded the first `runCode` call.
    let searchedFirst: Bool

    /// The turn made more calls than `scenarioThrashFactor` times the
    /// minimum the scenario needs.
    let thrash: Bool

    /// The reply carried a value the tools genuinely returned, but not in
    /// the form the scenario grades on.
    let groundedButWrongForm: Bool

    /// How many tool calls the turn made — the denominator `thrash` is read
    /// against, carried so a reader need not recompute it.
    let toolCallCount: Int

    /// Derives every mode from one run's evidence.
    ///
    /// - Parameter observation: the run's raw evidence.
    init(_ observation: ScenarioObservation) {
        let deniesAccess = observation.reply.containsAnyPhrase(of: Self.refusalPhrases)
        let announcesIntent = observation.reply.containsAnyPhrase(of: Self.announcementPhrases)
        let isSubstantive =
            !observation.reply.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !deniesAccess && !announcesIntent

        overRefusal = deniesAccess && observation.toolCallCount == 0
        answeredWithoutCalling = observation.invokedPaths.isEmpty && isSubstantive
        announceThenStop = announcesIntent && observation.toolCallCount == 0
        inventedPaths = observation.invokedPaths.subtracting(observation.catalogPaths).sorted()
        searchedFirst = observation.findAPIsFirst
        thrash = observation.toolCallCount > scenarioMinimumToolCalls * scenarioThrashFactor
        groundedButWrongForm =
            !observation.validAnswer
            && observation.returnedValues.contains { value in
                value.count >= scenarioGroundingValueMinimumLength
                    && observation.reply.localizedCaseInsensitiveContains(value)
            }
        toolCallCount = observation.toolCallCount
    }

    /// Renders this run's modes as one line a later script can count.
    ///
    /// The shape is a parsing contract, not prose: a fixed leading token,
    /// the scenario in brackets, then every mode as a `name=0`/`name=1`
    /// flag in a fixed order, then the supporting detail. Summing a flag
    /// over a run's worth of lines gives that mode's rate directly, per
    /// scenario, which is the whole point of the instrument.
    ///
    /// - Parameter scenario: the scenario label.
    /// - Returns: the `MODES` line to print.
    func line(scenario: String) -> String {
        let flags = [
            ("overRefusal", overRefusal),
            ("answeredWithoutCalling", answeredWithoutCalling),
            ("announceThenStop", announceThenStop),
            ("inventedPath", !inventedPaths.isEmpty),
            ("searchedFirst", searchedFirst),
            ("thrash", thrash),
            ("groundedButWrongForm", groundedButWrongForm),
        ]
        .map { name, held in "\(name)=\(held ? 1 : 0)" }
        .joined(separator: " ")
        return "MODES [\(scenario)] \(flags) invented=[\(inventedPaths.joined(separator: ","))] "
            + "toolCalls=\(toolCallCount)"
    }

    /// The phrasings that count as denying access or capability.
    ///
    /// Every entry is a family of the refusals these scenarios actually
    /// recorded — task `tkrdwb8` logged, among others, "I don't have access
    /// to your trip details or current weather data." from a run that
    /// called nothing. The list is deliberately short and literal: a mode
    /// counted from a broad paraphrase list would measure the list rather
    /// than the model.
    private static let refusalPhrases = [
        "don't have access",
        "do not have access",
        "don't have the ability",
        "do not have the ability",
        "can't access",
        "cannot access",
        "can't check",
        "cannot check",
        "not able to",
        "unable to",
    ]

    /// The phrasings that count as announcing a next step rather than
    /// taking it.
    ///
    /// The recorded shape is a turn that opens "Let me first find…" and
    /// ends there — see `runElevationIntegrationScenario`'s note that a turn
    /// asked only to start a job "gets an announcement and no `runCode` call
    /// at all".
    private static let announcementPhrases = [
        "let me ",
        "let's ",
        "i'll first",
        "i will first",
        "i'm going to",
        "i am going to",
        "first, i",
    ]
}

extension String {
    /// Whether this string contains any of `phrases`, ignoring case.
    ///
    /// - Parameter phrases: the phrasings to look for.
    /// - Returns: `true` when at least one is present.
    fileprivate func containsAnyPhrase(of phrases: [String]) -> Bool {
        phrases.contains { localizedCaseInsensitiveContains($0) }
    }
}
