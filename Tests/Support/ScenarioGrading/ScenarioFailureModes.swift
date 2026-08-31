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
public struct ScenarioObservation {
    /// The model's final reply text.
    public var reply: String

    /// How many tool calls the turn made, of any tool.
    public var toolCallCount: Int

    /// The `tools.*` paths the model's `runCode` snippets **wrote**.
    ///
    /// A lexical scan of the snippet source, not a record of what resolved —
    /// see `NativeTranscript.typedToolPaths(in:)`. It is the right evidence
    /// for `inventedPath`, whose question is precisely what the model reached
    /// for, and it is the wrong evidence for anything about what happened.
    public var typedPaths: Set<String>

    /// The `tools.*` paths a fixture tool actually **entered**.
    ///
    /// Recorded by the fixture tools themselves as they ran — see
    /// `ScenarioCallLog`. A path here genuinely executed, whether its call
    /// then returned a value or threw. Which of them handed data back is a
    /// third question, answered by `returnedValues`.
    public var invokedPaths: Set<String>

    /// Every `tools.*` path the mounted catalog actually defines.
    public var catalogPaths: Set<String>

    /// Whether a `searchTools` call preceded the first `runCode` call.
    public var searchedToolsFirst: Bool

    /// Whether this run could observe the turn's *route* at all — the ordered
    /// tool calls, their typed paths, and their outputs.
    ///
    /// `false` on the `respond(to:)` path, which returns only the final answer:
    /// no events, so no call order and no snippet text. Four of the seven
    /// failure modes are derived purely from the route, and with nothing to
    /// derive from they compute to `0` — indistinguishable from a measured
    /// clean run. They print `n/a` instead. This is the same defect class as a
    /// `priming=ok` printed when priming was never requested.
    public var routeObservable: Bool

    /// The scalar values the tools genuinely returned to the model this
    /// turn — see `NativeTranscript.returnedValues(in:)`.
    public var returnedValues: Set<String>

    /// Whether the reply carried the form the scenario grades on.
    public var isValidAnswer: Bool

    /// Records one run's raw evidence.
    ///
    /// Explicit because a `public` struct's synthesized memberwise initializer
    /// is `internal` only. `routeObservable` keeps the default the stored
    /// property used to carry.
    ///
    /// - Parameters:
    ///   - reply: the model's final reply text.
    ///   - toolCallCount: how many tool calls the turn made.
    ///   - typedPaths: the `tools.*` paths the snippets wrote.
    ///   - invokedPaths: the `tools.*` paths a fixture tool entered.
    ///   - catalogPaths: every `tools.*` path the mounted catalog defines.
    ///   - searchedToolsFirst: whether discovery came before the first snippet.
    ///   - routeObservable: whether this run could observe the turn's route.
    ///   - returnedValues: the scalars the tools returned to the model.
    ///   - isValidAnswer: whether the reply carried the form the scenario grades on.
    public init(
        reply: String,
        toolCallCount: Int,
        typedPaths: Set<String>,
        invokedPaths: Set<String>,
        catalogPaths: Set<String>,
        searchedToolsFirst: Bool,
        routeObservable: Bool = true,
        returnedValues: Set<String>,
        isValidAnswer: Bool
    ) {
        self.reply = reply
        self.toolCallCount = toolCallCount
        self.typedPaths = typedPaths
        self.invokedPaths = invokedPaths
        self.catalogPaths = catalogPaths
        self.searchedToolsFirst = searchedToolsFirst
        self.routeObservable = routeObservable
        self.returnedValues = returnedValues
        self.isValidAnswer = isValidAnswer
    }
}

/// The fewest tool calls any scenario this runner drives can be answered
/// in: one `searchTools` to learn the catalog's real names, then one `runCode`
/// to call them.
///
/// A host mounts `MultiTool` with the catalog behind `searchTools` rather than
/// in the session instructions, so a model that has not searched does not
/// know a single real name — which is why the floor is two rather than one,
/// and why it is the same floor for all four scenarios.
public let scenarioMinimumToolCalls = 2

/// How far past `scenarioMinimumToolCalls` a turn may go before it counts
/// as thrashing.
///
/// Doubling the floor leaves room for the repair loop the scenarios
/// deliberately provoke — a mis-called tool, its repairable error, and the
/// corrected call — while still separating "repaired once" from a turn
/// going around the same loop over and over.
public let scenarioThrashFactor = 2

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
public struct ScenarioFailureModes {
    /// The reply denied access or capability and the turn called nothing at
    /// all.
    public let isOverRefusal: Bool

    /// The reply answered substantively while no `tools.*` path ever ran.
    public let answeredWithoutCalling: Bool

    /// The reply announced what the model was about to do, and the turn
    /// then ended without doing it.
    public let didAnnounceThenStop: Bool

    /// The `tools.*` paths a snippet wrote that the mounted catalog does
    /// not define, sorted.
    ///
    /// Sorted rather than a set so a run's line is byte-comparable with the
    /// next run's.
    public let inventedPaths: [String]

    /// A `searchTools` call preceded the first `runCode` call.
    public let searchedToolsFirst: Bool

    /// Whether the route-derived modes were measurable — see
    /// ``ScenarioObservation/routeObservable``.
    public let routeObservable: Bool

    /// The turn made more calls than `scenarioThrashFactor` times the
    /// minimum the scenario needs.
    public let didThrash: Bool

    /// The reply carried a value the tools genuinely returned, but not in
    /// the form the scenario grades on.
    public let isGroundedButWrongForm: Bool

    /// How many tool calls the turn made — the denominator `didThrash` is read
    /// against, carried so a reader need not recompute it.
    public let toolCallCount: Int

    /// Derives every mode from one run's evidence.
    ///
    /// - Parameter observation: the run's raw evidence.
    public init(_ observation: ScenarioObservation) {
        let deniesAccess = observation.reply.containsAnyPhrase(of: Self.refusalPhrases)
        let announcesIntent = observation.reply.containsAnyPhrase(of: Self.announcementPhrases)
        let isSubstantive =
            !observation.reply.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !deniesAccess && !announcesIntent

        isOverRefusal = deniesAccess && observation.toolCallCount == 0
        // `invokedPaths`, not `typedPaths`: the question is whether the model
        // reached a tool at all, and a tool that ran and then threw was
        // reached. Writing a call site that never resolved is not calling
        // anything — reading this off the snippet source is the false pass
        // task `0981ar3` removed. Not `returnedValues` either: a tool that
        // refused a bad argument was still called, and the reply that follows
        // is not an uncalled answer.
        answeredWithoutCalling = observation.invokedPaths.isEmpty && isSubstantive
        didAnnounceThenStop = announcesIntent && observation.toolCallCount == 0
        // `typedPaths`, deliberately: an invented path by definition never
        // reaches a tool, so no recorder can ever see it and only the snippet
        // source can report it.
        inventedPaths = observation.typedPaths.subtracting(observation.catalogPaths).sorted()
        searchedToolsFirst = observation.searchedToolsFirst
        routeObservable = observation.routeObservable
        didThrash = observation.toolCallCount > scenarioMinimumToolCalls * scenarioThrashFactor
        isGroundedButWrongForm =
            !observation.isValidAnswer
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
    public func line(scenario: String) -> String {
        // The reply-derived modes are measurable on every path; the
        // route-derived four are not. Printing `0` for a mode this run could
        // not observe reads as a measured clean result, which is how a
        // `priming=ok` on an unprimed run misled a whole A/B.
        let replyModes = [
            ("overRefusal", isOverRefusal),
            ("answeredWithoutCalling", answeredWithoutCalling),
            ("announceThenStop", didAnnounceThenStop),
        ]
        let routeModes = [
            ("inventedPath", !inventedPaths.isEmpty),
            ("searchedToolsFirst", searchedToolsFirst),
            ("thrash", didThrash),
            ("groundedButWrongForm", isGroundedButWrongForm),
        ]
        let flags = (replyModes.map { name, held in "\(name)=\(held ? 1 : 0)" }
            + routeModes.map { name, held in
                routeObservable ? "\(name)=\(held ? 1 : 0)" : "\(name)=n/a"
            })
            .joined(separator: " ")
        let invented = routeObservable ? inventedPaths.joined(separator: ",") : "n/a"
        return "MODES [\(scenario)] \(flags) invented=[\(invented)] "
            + "toolCalls=\(routeObservable ? String(toolCallCount) : "n/a")"
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
    /// ends there — see `runBackgroundIntegrationScenario`'s note that a turn
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
