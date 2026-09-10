// `LargeCatalogToolKit` — the many-verb servers a large-surface test mounts.
//
// Test support — see the header of `ScriptedServer.swift`.
//
// Every other tool kit here serves one scenario of a few verbs. This one
// serves a size: a host that connects four ordinary platform servers holds a
// catalog of forty verbs, and the assembled selection prefix over such a
// catalog stands above `SelectionConfig.defaultCapacityCharacterLimit`. That
// is the surface where `SelectionTier` stops prompting once over the whole
// catalog and starts splitting the catalog into slices, one prompt each.
//
// The verbs are a stub server's, and the descriptions are the length real
// platform servers write: what the verb does, then the operating notes of
// the server it belongs to. Nothing here lowers a budget or pads a string to
// reach a size — the size is what forty ordinary verb descriptions weigh.

import MCP

/// One connected server's worth of verbs in the large catalog: the server
/// noun a host mounts them under, its operating notes, and its verbs.
///
/// Four servers, ten verbs each. A host that connects an issue tracker, a
/// database, an observability stack and a delivery pipeline holds exactly
/// this shape of catalog, and that catalog is over the selection budget.
public enum LargeCatalogDomain: String, CaseIterable, Sendable {
    /// An issue tracker: search, file, comment on and move work items.
    case issues

    /// A SQL database: read the schema, run and explain statements.
    case database

    /// An observability stack: logs, metrics, traces and alerts.
    case observability

    /// A delivery pipeline: runs, artifacts, environments and releases.
    case deploy

    /// The name a host connects this domain's server under, and so the noun
    /// its verbs render below — `tools.<serverName>.<verb>`.
    public var serverName: String { rawValue }

    /// The operating notes every verb of this domain carries at the end of
    /// its description.
    ///
    /// Real platform servers repeat their own access, paging and failure
    /// rules on each verb, because a model reads one verb at a time and
    /// never the server's front page. These say the same kind of thing for
    /// the same reason, and they are what makes a verb description the
    /// length a real one is.
    var operatingNotes: String {
        switch self {
        case .issues:
            return """
                The caller is the account the server holds a token for, and a project the token cannot \
                read answers as if it were empty rather than as an error. Results are paged: read \
                nextCursor from the result and pass it back as cursor until it is absent. Every \
                timestamp is UTC in RFC 3339, and every issue key is of the form PROJECT-123.
                """
        case .database:
            return """
                Statements run on the read replica unless the caller names a writable connection, and \
                a statement that would write on the replica is refused rather than routed. Rows come \
                back paged with a nextCursor, and a result above the row budget is truncated with \
                truncated set to true. Identifiers are case-folded the way the server is configured, \
                so quote them to keep the case.
                """
        case .observability:
            return """
                A query reads the retention window the workspace is configured for, and a range \
                outside it answers empty rather than failing. Times are UTC in RFC 3339, and a \
                relative range such as -15m is resolved against the server clock. Results are paged \
                with a nextCursor, and a query that would scan above the workspace budget is refused \
                with the scanned byte count reported.
                """
        case .deploy:
            return """
                Every call names the pipeline by its slug, and a slug the token cannot reach answers \
                as not found rather than as forbidden. A call that starts work answers as soon as the \
                work is queued and never waits for it to finish, so read the run id back and poll it. \
                Results are paged with a nextCursor, and every timestamp is UTC in RFC 3339.
                """
        }
    }

    /// This domain's verbs, in the order the server registers them.
    var verbs: [LargeCatalogVerb] {
        switch self {
        case .issues: return Self.issueVerbs
        case .database: return Self.databaseVerbs
        case .observability: return Self.observabilityVerbs
        case .deploy: return Self.deployVerbs
        }
    }

    /// The verbs of ``issues``.
    private static let issueVerbs: [LargeCatalogVerb] = [
        LargeCatalogVerb(
            name: "search_issues",
            purpose: """
                Finds issues by a full-text query over the title, the body and every comment, narrowed \
                by project, label, assignee, state and the range a field was last changed in. Sorts by \
                relevance by default, or by the named field when one is given. Use it to find the work \
                item a request is about before reading or changing anything.
                """,
            arguments: ["query", "project", "state", "cursor"]
        ),
        LargeCatalogVerb(
            name: "get_issue",
            purpose: """
                Reads one issue whole: its title, body, state, labels, assignee, parent, children, \
                links and every comment in the order they were written. The body and the comments come \
                back as the markdown they were written in, never as rendered HTML. Use it once a search \
                has named the issue you need.
                """,
            arguments: ["key"]
        ),
        LargeCatalogVerb(
            name: "create_issue",
            purpose: """
                Files a new issue in one project, with a title, a markdown body, labels and an optional \
                parent. The state is the project's own first state, and the reporter is the calling \
                account. Answers the new issue key, which every later call names the issue by.
                """,
            arguments: ["project", "title", "body"]
        ),
        LargeCatalogVerb(
            name: "update_issue",
            purpose: """
                Changes the title, the body, the labels or the parent of one issue. Each field given is \
                replaced whole and each field left out is untouched, so read the issue first when you \
                mean to add a label rather than to replace the set. The state moves through \
                transition_issue and never through this verb.
                """,
            arguments: ["key", "title", "body"]
        ),
        LargeCatalogVerb(
            name: "comment_on_issue",
            purpose: """
                Adds one markdown comment to an issue, as the calling account. A comment notifies every \
                watcher of the issue, so write it as the message a person reads. Answers the comment \
                id, which edit_comment and delete_comment name it by.
                """,
            arguments: ["key", "body"]
        ),
        LargeCatalogVerb(
            name: "transition_issue",
            purpose: """
                Moves one issue to another state, along a transition the project's workflow permits. A \
                transition the workflow does not permit is refused, and the refusal lists the \
                transitions that are open from the current state. Some transitions require a resolution \
                or a comment, and the refusal says which.
                """,
            arguments: ["key", "state", "resolution"]
        ),
        LargeCatalogVerb(
            name: "assign_issue",
            purpose: """
                Sets or clears the assignee of one issue. The assignee must be a member of the project, \
                and an account that is not is refused rather than silently ignored. Pass no account to \
                clear the assignee and put the issue back in the unassigned queue.
                """,
            arguments: ["key", "account"]
        ),
        LargeCatalogVerb(
            name: "link_issues",
            purpose: """
                Records a typed link between two issues — blocks, is blocked by, duplicates, relates \
                to. The reverse link is written at the same time, so a link made in one direction reads \
                from both ends. A link that already stands is left as it is.
                """,
            arguments: ["from", "to", "type"]
        ),
        LargeCatalogVerb(
            name: "list_projects",
            purpose: """
                Lists every project the calling token can read, with its key, its name, its workflow \
                and its default assignee. Use it to turn a project name a person wrote into the project \
                key every other verb of this server takes. The list is small enough that it is rarely \
                paged.
                """,
            arguments: ["cursor"]
        ),
        LargeCatalogVerb(
            name: "list_sprints",
            purpose: """
                Lists the sprints of one project, with their state, their dates and the issues in each. \
                A closed sprint keeps the issues that were in it when it closed, so a report over a \
                past sprint reads the same however the issues moved afterward. Use it to answer what a \
                team committed to and what it finished.
                """,
            arguments: ["project", "state", "cursor"]
        ),
    ]

    /// The verbs of ``database``.
    private static let databaseVerbs: [LargeCatalogVerb] = [
        LargeCatalogVerb(
            name: "list_schemas",
            purpose: """
                Lists the schemas of one connection, with the table count and the owner of each. The \
                system schemas are left out unless they are asked for by name. Use it as the first step \
                of reading a database whose shape you do not know.
                """,
            arguments: ["connection", "cursor"]
        ),
        LargeCatalogVerb(
            name: "describe_table",
            purpose: """
                Reads the shape of one table: every column with its type, its nullability and its \
                default, then the primary key, the foreign keys, the indexes and the constraints. Use \
                it before writing a statement against a table, so the column names in the statement are \
                the ones the table really has.
                """,
            arguments: ["connection", "schema", "table"]
        ),
        LargeCatalogVerb(
            name: "run_query",
            purpose: """
                Runs one SQL statement and answers its rows, with the column names and types beside \
                them. A statement that reads runs on the replica; a statement that writes needs a \
                writable connection and is refused on the replica. Bind values through the parameters \
                argument rather than pasting them into the text.
                """,
            arguments: ["connection", "sql", "parameters"]
        ),
        LargeCatalogVerb(
            name: "explain_query",
            purpose: """
                Answers the planner's plan for one statement, with the estimated rows and cost of each \
                node, and the real timings when the statement is run to collect them. Use it when a \
                statement is slow, or before running a statement over a table whose size you do not \
                know.
                """,
            arguments: ["connection", "sql", "analyze"]
        ),
        LargeCatalogVerb(
            name: "list_indexes",
            purpose: """
                Lists the indexes of one table or one schema, with the columns of each, its size, its \
                uniqueness and how often the planner has chosen it. An index no statement has used \
                since the counters were reset is reported with a zero count rather than left out.
                """,
            arguments: ["connection", "schema", "table"]
        ),
        LargeCatalogVerb(
            name: "create_index",
            purpose: """
                Creates one index over the named columns of one table, concurrently by default so that \
                writers are not blocked while it is built. Needs a writable connection. A build that \
                fails leaves an invalid index behind, and the answer names it so that it can be \
                dropped.
                """,
            arguments: ["connection", "schema", "table", "columns"]
        ),
        LargeCatalogVerb(
            name: "list_connections",
            purpose: """
                Lists the connections this server holds, with the database each reaches, whether it is \
                writable, and the replica lag when it is a replica. Use it to turn a database name a \
                person wrote into the connection name every other verb of this server takes.
                """,
            arguments: ["cursor"]
        ),
        LargeCatalogVerb(
            name: "cancel_query",
            purpose: """
                Cancels one statement that is still running, by the backend id list_connections reports \
                for it. A cancel asks the backend to stop and does not terminate it, so a statement \
                inside an uninterruptible step keeps running until that step ends. Answers whether the \
                backend acknowledged.
                """,
            arguments: ["connection", "backend"]
        ),
        LargeCatalogVerb(
            name: "export_table",
            purpose: """
                Writes one table, or the rows one statement answers, to a file in the workspace as CSV \
                or as newline-delimited JSON. The export streams and never holds the whole result in \
                memory, so it is the way to move a table larger than the row budget of run_query. \
                Answers the path written and the row count.
                """,
            arguments: ["connection", "schema", "table", "format"]
        ),
        LargeCatalogVerb(
            name: "table_statistics",
            purpose: """
                Answers the collected statistics of one table: the live and dead row estimates, the \
                on-disk size, the last time it was vacuumed and analyzed, and the per-column \
                distinctness the planner reads. Use it to tell a table that is genuinely large from one \
                whose estimates are merely stale.
                """,
            arguments: ["connection", "schema", "table"]
        ),
    ]

    /// The verbs of ``observability``.
    private static let observabilityVerbs: [LargeCatalogVerb] = [
        LargeCatalogVerb(
            name: "search_logs",
            purpose: """
                Searches the log store over a time range, filtered by service, severity, and a query \
                over the message and the structured fields. Answers the matching lines newest first, \
                each with its service, its severity, its trace id and its fields. Use it to find what a \
                service reported around the moment something went wrong.
                """,
            arguments: ["query", "service", "range", "cursor"]
        ),
        LargeCatalogVerb(
            name: "tail_logs",
            purpose: """
                Reads the newest lines of one service as they arrive, up to the line count asked for, \
                then returns. It is a bounded read and never an open stream, so call it again to read \
                on. Use it to watch a change reach a running service.
                """,
            arguments: ["service", "lines"]
        ),
        LargeCatalogVerb(
            name: "list_metrics",
            purpose: """
                Lists the metric names the workspace holds, with the kind of each — counter, gauge, \
                histogram — its unit and its label keys. Use it to turn a measure a person named in \
                prose into the metric name and labels query_metric takes.
                """,
            arguments: ["prefix", "cursor"]
        ),
        LargeCatalogVerb(
            name: "query_metric",
            purpose: """
                Evaluates one metric query over a time range and answers the series it produced, each \
                with its labels and its points. The step is chosen from the range when none is given, \
                so a wide range answers coarse points rather than refusing. Use it to answer how a \
                measure moved.
                """,
            arguments: ["query", "range", "step"]
        ),
        LargeCatalogVerb(
            name: "list_alerts",
            purpose: """
                Lists the alert rules of the workspace and the state of each — firing, pending, silenced \
                or normal — with the query behind it and the last time it changed state. Use it to \
                answer what is wrong right now before reading any single service.
                """,
            arguments: ["state", "service", "cursor"]
        ),
        LargeCatalogVerb(
            name: "silence_alert",
            purpose: """
                Silences one alert rule for a bounded period, with a reason that is recorded beside the \
                silence. A silence never changes the rule and never hides the underlying data; it stops \
                the notification alone. A silence with no end is refused.
                """,
            arguments: ["rule", "duration", "reason"]
        ),
        LargeCatalogVerb(
            name: "get_trace",
            purpose: """
                Reads one distributed trace whole: every span with its service, its operation, its \
                timing, its status and its parent. Answers the spans in start order, so the tree can be \
                rebuilt from the parent ids. Use it to see which hop of a request was slow or failed.
                """,
            arguments: ["trace"]
        ),
        LargeCatalogVerb(
            name: "list_dashboards",
            purpose: """
                Lists the dashboards of the workspace, with the panels of each and the queries behind \
                those panels. Use it to find the query a team already trusts for a measure, rather than \
                writing a new one that answers something slightly different.
                """,
            arguments: ["query", "cursor"]
        ),
        LargeCatalogVerb(
            name: "incident_timeline",
            purpose: """
                Answers the recorded timeline of one incident: every state change, every note, every \
                deploy and every alert that fired inside its window, in time order. Use it to write \
                what happened without reading four other systems.
                """,
            arguments: ["incident"]
        ),
        LargeCatalogVerb(
            name: "service_dependencies",
            purpose: """
                Answers which services call the named service and which services it calls, as measured \
                from the traces of the range asked for, with the call rate and error rate of each edge. \
                An edge no trace carried in that range is absent rather than reported as zero.
                """,
            arguments: ["service", "range"]
        ),
    ]

    /// The verbs of ``deploy``.
    private static let deployVerbs: [LargeCatalogVerb] = [
        LargeCatalogVerb(
            name: "list_pipelines",
            purpose: """
                Lists the pipelines of the workspace, with the repository each builds, its trigger, and \
                the state of its newest run. Use it to turn a pipeline name a person wrote into the \
                slug every other verb of this server takes.
                """,
            arguments: ["query", "cursor"]
        ),
        LargeCatalogVerb(
            name: "trigger_pipeline",
            purpose: """
                Queues one run of a pipeline on the named ref, with the parameters that pipeline \
                declares. Answers as soon as the run is queued, with the run id to poll; it never waits \
                for the run to finish. A parameter the pipeline does not declare is refused rather than \
                ignored.
                """,
            arguments: ["pipeline", "ref", "parameters"]
        ),
        LargeCatalogVerb(
            name: "get_run",
            purpose: """
                Reads one run whole: its state, its ref, its parameters, every stage with its timing \
                and outcome, and the failure of the first stage that failed. Use it to poll a run \
                trigger_pipeline queued, and to answer why a run failed.
                """,
            arguments: ["run"]
        ),
        LargeCatalogVerb(
            name: "cancel_run",
            purpose: """
                Asks one running run to stop, and answers whether the request was accepted. A stage \
                already inside an uninterruptible step finishes that step first, so a cancel is not \
                instant. A run that has already ended is left as it is.
                """,
            arguments: ["run", "reason"]
        ),
        LargeCatalogVerb(
            name: "list_artifacts",
            purpose: """
                Lists the artifacts one run produced, with the name, the size, the digest and the \
                retention date of each. An artifact past its retention is listed with its metadata and \
                answers as gone when it is downloaded.
                """,
            arguments: ["run", "cursor"]
        ),
        LargeCatalogVerb(
            name: "download_artifact",
            purpose: """
                Writes one artifact of one run into the workspace and answers the path it wrote. The \
                download is verified against the digest the run recorded, and a mismatch is an error \
                rather than a file. Use it to read a build output a later step needs.
                """,
            arguments: ["run", "artifact", "path"]
        ),
        LargeCatalogVerb(
            name: "list_environments",
            purpose: """
                Lists the environments of one pipeline, with the release each currently holds, its \
                approval rule and the time of its last change. Use it to answer what is running where \
                before promoting or rolling anything back.
                """,
            arguments: ["pipeline", "cursor"]
        ),
        LargeCatalogVerb(
            name: "promote_release",
            purpose: """
                Moves one release into the named environment, along a path the pipeline permits. An \
                environment that requires an approval is refused until the approval stands, and the \
                refusal names who may give it. Answers the deployment id to poll.
                """,
            arguments: ["pipeline", "release", "environment"]
        ),
        LargeCatalogVerb(
            name: "rollback_release",
            purpose: """
                Puts the previous release of one environment back, or the release named when one is \
                given. A rollback is recorded as a deployment of its own, so the history keeps both the \
                release that failed and the one that replaced it. Answers the deployment id to poll.
                """,
            arguments: ["pipeline", "environment", "release"]
        ),
        LargeCatalogVerb(
            name: "deployment_status",
            purpose: """
                Reads one deployment: its state, its release, its environment, the health checks it is \
                waiting on and the failure of the first check that failed. Use it to poll a promotion \
                or a rollback through to its end.
                """,
            arguments: ["deployment"]
        ),
    ]
}

/// One verb of a ``LargeCatalogDomain``: the name it is called by, what it
/// does, and the arguments it takes.
///
/// The description a server publishes for the verb is the ``purpose`` and
/// the domain's operating notes together — see
/// ``ScriptedServer/addLargeCatalogTools(of:describing:)``.
struct LargeCatalogVerb: Sendable {
    /// The tool name, and so the last segment of the rendered call path.
    let name: String

    /// What the verb does and when to reach for it, in the shape a platform
    /// server writes it.
    let purpose: String

    /// The argument names, the first of which the verb requires.
    let arguments: [String]
}

extension ScriptedServer {
    /// The text a large-catalog verb answers a call with.
    ///
    /// The kit exists to give a catalog its size, and no test of it calls a
    /// verb for a result. A call still answers, and it answers the name it
    /// was called by, so a call that reaches the wrong verb is readable.
    ///
    /// - Parameter name: the verb that was called.
    /// - Returns: the answer text.
    private static func largeCatalogAnswer(for name: String) -> String {
        "\(name) is a catalog stub: it declares a surface and answers nothing else."
    }

    /// Registers every verb of `domain` on this server.
    ///
    /// Each verb's published description is its own purpose followed by the
    /// operating notes of its domain, which is how a platform server writes
    /// one: the model reads a verb alone, never the server's front page.
    ///
    /// A server is permitted to publish no description at all, and
    /// `describing: false` builds that server: every verb keeps its name and
    /// its schema, and each one declares the empty description. It is the
    /// surface `NoDescriptionSurfaceDiscoveryTests` measures, because the
    /// rule under measurement reads what a summary block holds when the
    /// description is gone.
    ///
    /// - Parameters:
    ///   - domain: the server's worth of verbs to register.
    ///   - describing: whether each verb publishes a description. `true`, the
    ///     default, keeps the purpose and the operating notes every other
    ///     caller reads.
    public func addLargeCatalogTools(of domain: LargeCatalogDomain, describing: Bool = true) {
        for verb in domain.verbs {
            addScriptedTool(
                name: verb.name,
                description: describing ? "\(verb.purpose)\n\n\(domain.operatingNotes)" : "",
                inputSchema: Self.largeCatalogSchema(for: verb)
            ) { params in
                CallTool.Result(
                    content: [
                        .text(
                            text: Self.largeCatalogAnswer(for: params.name),
                            annotations: nil,
                            _meta: nil)
                    ]
                )
            }
        }
    }

    /// The input schema of one large-catalog verb: every argument a string,
    /// the first of them required.
    ///
    /// - Parameter verb: the verb to build a schema for.
    /// - Returns: the JSON Schema of its arguments.
    private static func largeCatalogSchema(for verb: LargeCatalogVerb) -> Value {
        let properties = verb.arguments.reduce(into: [String: Value]()) { properties, argument in
            properties[argument] = JSONSchemaBuilder.string()
        }
        return JSONSchemaBuilder.object(
            properties: properties,
            required: Array(verb.arguments.prefix(1))
        )
    }
}
