# The `sessions` tool and the `sessions` graph: design plan

Status: proposal. This file is a plan. It changes no code.

Language: ASD-STE100 Simplified Technical English.

Revision 2. The user answered Q-S1: UIs use the session directory through a GraphQL endpoint with the name `sessions`. There are no `_sah/sessions/*` ACP methods or notifications. This revision also applies D61: a session is an agent plus a working folder.

Revision 3. The user answered Q-S3 to Q-S7 (D72). `read inbox` consumes the messages. A message to a recorded session restores it, but an archived session refuses it. The tool and the graph can archive any session that the caller can see. Router owns the record of past sessions (`SessionIndex`, `ProjectRegistry`), and the `RecordedSessionCatalog` port is gone. There is no limit on the number of sessions or subagents that work at the same time. Only the loop guards stay.

Revision 4. D74: `SessionsGraph` is in the Multitool library target, next to the `sessions` tool (MT-10). It replaces ROUTER-10. Router does not link GraphQL. GraphQL and Graphiti come through the GraphQL toolkit of Extras (EXTRAS-6), and the pins are only in Extras.

Revision 5. D75: the `sessions` tool stays an op tool for the model, and it also gives `SessionsGraph` for use in code. It conforms to `GraphQLEndpointTool` of the core Extras library target (EXTRAS-7). The app asks each tool of its composition for its endpoint and registers what it finds, so the app does not register the `sessions` endpoint by hand. Q35 is answered.

Revision 6. D76: `SessionsTool` is its own public struct that holds an `OperationTool<SessionsToolContext>` and conforms to `GraphQLEndpointTool`, the same shape as `AgentsTool` and `SkillsCatalogTool` (Q-S10 is answered). It is a top-level tool of the session, like `skills` and `agents`. The same instance is also in the Multitool registry, so a snippet calls `tools.sessions.*`. The rules and the risk check apply only in `runCode`: a direct call of the top-level tool does not go through them. The app finds the endpoints in the top-level tool list of the session, not in the Multitool registry.

Revision 7. D81: the client side of the tunnel is `SAHGraphQLClient` of FoundationModelsACPClient (ACPC-6), over the `SAH` wire types of FoundationModelsACP (ACP-5). It replaces `ACPGraphQLEndpoint` and is not a `GraphQLEndpoint`. The client does not link GraphQL (D79).

Revision 8. D82: a tool gives a list of endpoints. The requirement of `GraphQLEndpointTool` (EXTRAS-7) is `var graphQLEndpoints: [any GraphQLEndpoint] { get }`, and the `sessions` tool gives a list of one, `SessionsGraph`. The top-level `MultiTool` tool (`runCode`) also conforms and gives the endpoints of its capabilities. The first one is `FilesGraph`, the `files` endpoint (TestudoApp MT-11), next to `FilesCapability`, over the same root set and `PathGuard`. The app registers no endpoint by hand.

## 1. Purpose and scope

This plan adds two front ends to one session directory:

1. A `sessions` operation tool in FoundationModelsMultitool, for the model.
2. A `sessions` GraphQL endpoint in FoundationModelsMultitool, for the UIs. It uses the same pattern as the `kanban` endpoint (D55, D74).

With the tool, an agent can:

- find the sessions on this server,
- start a new root session with an agent and an optional working folder, with a first message,
- add tags to a session and remove tags from a session,
- send a message to a session id, to an agent, to a folder, or to a tag,
- reply to a message,
- read the messages that it did not read yet (its inbox),
- get the state and the last summary of a session,
- archive a session.

The UI can do the same through queries, mutations and a subscription of the `sessions` endpoint. A new root session comes to the UI on the subscription, and the app opens a tab.

The tool and the endpoint use the same directory and the same rules. Only the model calls also go through the AI risk check (MT-1).

The plan covers these packages: FoundationModelsExtras, FoundationModelsRouter, FoundationModelsMultitool, FoundationModelsAgents, FoundationModelsACPAgent and FoundationModelsACPClient. It refers to FoundationModelsACP and to the app (APP-16), but it adds no change IDs for them.

Out of scope:

- Messages between servers (Q1, D17).
- The views of the app (the Sessions window, the tab bar).
- A `delete session` operation. `archive session` ends a session, and its transcript stays on disk (D68, D72).

## 2. Constraints

These are the rules of the user. The plan must obey all of them.

1. **ACP does not go into Multitool.** Multitool has no FoundationModelsACP type and no FoundationModelsACPAgent type. Multitool has no ACP concept (no ACP session id type, no `session/update`, no `_meta`, no owner client).
2. **ACPAgent does not go into Router or Extras.** FoundationModelsRouter and FoundationModelsExtras have no ACPAgent type and no ACP concept.
3. **ACP carries. ACP does not operate.** Find, start, tag and message are operations of the session layer. They are not ACP methods. UIs reach the session layer through the `sessions` GraphQL endpoint and the existing `_sah/graphql/*` tunnel. ACPAgent only carries the tunnel. There are no `_sah/sessions/*` messages.
4. **The dependency direction is a decision of this plan.** Section 5 compares the options and gives a recommendation, the module graph before and after, and the proof that there is no cycle and no forbidden edge.

Rules from the code and from the design that also apply:

- The library target of Multitool does not link FoundationModelsRouter. `FoundationModelsMultitool/Package.swift:551-565` states this, and `Tests/FoundationModelsMultitoolTests/PackageManifestTests.swift:4-14` fails when Router comes back.
- Each `runCode` snippet goes through the AI risk check one time, in `MultiTool.runSnippet`, before it runs (MT-1, D64). The check can only deny.
- A session has one owner client at a time (D11).
- Server state gets to a UI only through ACP (D54). The GraphQL tunnel is part of ACP (D55).
- A session is an agent plus a working folder (D19, D61). The agents come from the catalog of FoundationModelsAgents. The catalog includes the optional extra agent folders (`agentFolders: [URL]`, AG-4). The app gives its iCloud `Agents/` folder. `Agents/AGENT.md` is the agent with the id `default`.

## 3. Current state in the code

### 3.1 FoundationModelsMultitool

- The library target links FoundationModelsExtras and the metadata registry. It does not link Router (`Package.swift:557-565`). It does not link the `Operations` product of Extras either.
- The file capability says: "this package has no operation machinery, thus the verb is a plain `FoundationModels.Tool`" (`Sources/FoundationModelsMultitool/Capabilities/Files/Read.swift:3-8`).
- But the registry can mount an operation tool. An `OperationDescribing` tool becomes one `OperationVerbTool` for each operation (`Surface/RegistrySource.swift:315-350`, `Surface/OperationVerbTool.swift:36`). The verb name is the camelCase form of the op string (`OperationVerbTool.swift:99`). Thus the op `list sessions` of a tool named `sessions` becomes `tools.sessions.listSessions`.
- `MultiTool.Builder.register(noun:tool:)` mounts a tool under a noun (`Surface/MultiToolBuilder.swift:189`). A `Capability` owns one noun (`Surface/Capability.swift:33`).
- `makeSessionToolsAndStaging(selection:embedder:sampleModel:)` makes the session tools (`MultiTool.swift:202`).
- `runSnippet` (`MultiTool.swift:542`) runs each snippet, and each `tools.*` call of a snippet goes through `performInvocation` (`MultiTool.swift:1461-1472`). There is no risk check yet (MT-1 is not built).

### 3.2 FoundationModelsExtras

- `Operations` target: the `@Operation(verb:noun:description:mount:)` macro (`Sources/Operations/Operations.swift:45`) and `OperationTool<Context>` (`Sources/Operations/OperationTool.swift:61`). The `Operations` target links the `FoundationModelsExtras` target (`Package.swift:202-208`).
- `OperationDescribing` is in the core module (`Sources/FoundationModelsExtras/OperationEvents/OperationDescribing.swift:7`).
- Mail is already in Extras: `Mail` (`Mail/Mail.swift:7`), `MailSender` with `.session(ULID)` (`Mail/MailSender.swift:4-17`), `MailBody` with `.agentMessage(from: ULID, content: String)` (`Mail/MailBody.swift:9-22`), and `MailSink` (`Mail/MailSink.swift:5`).
- `ToolContext` gives the session of a tool call: `ToolContext.sessionID` (`Hosting/ToolContext.swift:12, 55`).
- The `GraphQLEndpoint` protocol is agreed (EXTRAS-2) but is not in the code yet. No Swift file has the name `GraphQLEndpoint`.

These facts show a pattern: Extras holds the small shared contracts. Other packages implement them and use them.

### 3.3 FoundationModelsRouter

- `Router` is an actor (`Router.swift:36`). Its public surface is `init`, `resolve` and `useLogger` (`Router.swift:120-219`). **It holds no list of live sessions.**
- A session comes from `RoutedLLM.makeSession(configuration:)` (`RoutedLLM.swift:101`). `SessionConfiguration` has `workingDirectory` and `agentSpawn` (`Session/SessionConfiguration.swift:14, 34`). It has no agent id, no tags and no title.
- `RoutedSession` is an actor and a `MailSink` (`Session/RoutedSession.swift:47`).
- `SessionSidecar` records `workingDirectory` (`Recording/SessionSidecar.swift:86`) and `agentSpawn` (`:43-54, 90`). **The sidecar is write-once** (`:225-235`, `.withoutOverwriting`).
- `SessionEvent` has `elicitationRequested`, `mailDelivered`, `submissionStarted`, `submissionEnded` and `answered` (`Session/SessionEvent.swift:184-339`).
- Router has no GraphQL dependency.
- Router has no record of past sessions. ACPAgent keeps it (section 3.6).

### 3.4 FoundationModelsKanban

- It is the model for an endpoint. It links the `GraphQL` package (GraphQLSwift, `from: "4.3.0"`) and `Graphiti` (`from: "3.1.0"`) (`FoundationModelsKanban/Package.swift:15-23, 80-81, 94`). It has a change subscription (`Sources/FoundationModelsKanban/Observe/ChangeSubscription.swift`).
- KANBAN-5 makes `KanbanGraph` conform to `GraphQLEndpoint`. It has no dependency on ACP.

### 3.5 FoundationModelsAgents

- The `agents` tool is an `OperationTool` with `list agents`, `start agent`, `check agent`, `cancel agent`, `send agent` and `send caller` (`Tool/AgentsToolOperations.swift:17, 49-52, 155, 184, 210, 299`). This is the style model for the new tool.
- `send agent` sends as `MailSender.session(ToolContext.current.sessionID)` (`AgentsToolOperations.swift:280`), through `AgentRun.deliver(_:from:)` (`Run/AgentRun.swift:453`) and `session.mail(_:)` (`AgentRun.swift:614`).
- `AgentCatalogBuilder` reads the agent folders (`Registry/AgentCatalogBuilder.swift:44, 123`). AG-4 adds `agentFolders: [URL]` and the `default` agent.
- Card `^jcnw05g` (`.kanban/tasks/01M52QKC1BWWGQKBM8FJCNW05G.md`) adds `find agents` to the `agents` tool: an embedding search over the descriptions, then a pick by a small model, with the parts of the skills selection.
- The package links Router, Extras and `Operations`. It does not link Multitool.

### 3.6 FoundationModelsACPAgent

- `RoutedACPAgent` is the ACP `Agent` (`RoutedACPAgent.swift:30`). It holds the live sessions of **one connection** in `sessions: [SessionId: ActiveSession]` (`:84-88`). "The ACP session id is the ULID of the root Router session" (`:84-85`).
- `bind(connection:)` keeps one connection (`:203-211`). A second bind replaces the first (ACPA-5 is a proposal).
- `session/new` composes the tools for the `cwd` and makes the Router session (`Agent/SessionSetup.swift:528-600`). The composition is `composeSession` (`:837, 870`). `activateSession` adds the table entry and the projector (`:621-728`).
- The composition mounts the Multitool registry and, after it, the standalone `skills` and `agents` tools (`Tools/ToolCatalog.swift:312-372`). The standalone tools are not in a snippet, so the risk check does not see them.
- `session/resume` closes a live entry first and restores the session from disk (`Agent/SessionResume.swift:130-137`). Thus a resume of a session that works now stops its work.
- ACPAgent keeps the record of past sessions: `SessionIndex` (`Transcripts/SessionIndex.swift`, the file `sessions.jsonl`) and `ProjectRegistry` (`Transcripts/ProjectRegistry.swift`, the file `projects.jsonl`). `TranscriptStore` (`Transcripts/TranscriptStore.swift`) uses them for `session/list` and `session/resume`. These types have no ACP type.
- There is no `_sah` code and no GraphQL tunnel yet.

### 3.7 FoundationModelsACP and FoundationModelsACPClient

- `Connection.notify(method:params:)` sends a notification with any method name (`FoundationModelsACP/Sources/FoundationModelsACP/Connection/Connection.swift:718`). The dispatch of `_` methods on the receive side is ACP-3 (agreed, not built).
- `ConnectionModel` is `@MainActor @Observable` (`FoundationModelsACPClient/Sources/FoundationModelsACPClient/Model/ConnectionModel.swift:27-28`). `openSessions` holds one `SessionModel` for each open session, and a view can "open one window for each new model" (`:33-41`).
- `resumeSession(_:)` makes and registers a `SessionModel` (`Model/ConnectionModel+Sessions.swift:129`).
- The client side of the tunnel is `SAHGraphQLClient` (ACPC-6, APP-16, D81). It is not a `GraphQLEndpoint`. It is not built yet.

## 4. Summary of the problem

Four facts make the dependency direction hard:

1. The tool is in Multitool. Multitool cannot link Router.
2. The session data (sidecar, transcript, mail, events) is in Router. But Router has no live list of sessions, and it cannot compose the tools of a new session. The composition (agent, tools, sandbox, MCP) is in ACPAgent.
3. The agent catalog is in FoundationModelsAgents. Multitool cannot link Agents, because Agents links Router.
4. The owner client of each session (D11) is known only in ACPAgent. But the GraphQL resolver, which is not in ACPAgent, must apply the owner rules.

## 5. Options for the dependency direction

### 5.1 Option A: a port in Extras, implemented by Router (recommended)

- Extras gets a `SessionDirectory` protocol, its value types and its event stream (EXTRAS-3).
- Router implements the protocol with `RouterSessionDirectory` (ROUTER-3).
- Router declares a second port, `SessionLauncher`, for the composition of a new root session (ROUTER-8). ACPAgent implements it with code that has no ACP concept (ACPA-9).
- Multitool uses only the Extras protocol (MT-2).
- `SessionsGraph`, in the existing Multitool library target next to the `sessions` tool, implements the `sessions` GraphQL endpoint over the Extras protocol (MT-10). Section 5.7 tells why it goes there.
- The `sessions` tool gives `SessionsGraph` in its `graphQLEndpoints` (`GraphQLEndpointTool`, EXTRAS-7, D75, D82). The server finds it in the tool list of the composition and registers it in its endpoint registry (APP-16). The registry is a named GraphQL service locator (TestudoApp D77). `sessions` has server scope, so it registers one time by name: the first session that gives it wins, and the registry ignores the endpoints of the subsequent sessions. All instances use one `SessionDirectory`, so the endpoint stays when that first session ends. ACPAgent only carries the tunnel.

Advantages:

- No forbidden edge. Multitool → Extras, Router → Extras and ACPAgent → Router and Extras exist today.
- It obeys the Router boundary of Multitool (`PackageManifestTests`).
- It follows the existing pattern: `Mail`, `MailSink`, `ToolContext`, `RunPlane` and `GraphQLEndpoint` are contracts in Extras.
- Agents (AG-1), the kanban trigger handler (APP-10, D60), the graph and the app use the same protocol. The model and the UI get the same rules.
- A test can use a fake directory. A Multitool test needs no model and no Router. A graph test needs no model and no `RouterSessionDirectory`.

Disadvantages:

- Extras gets bigger. The value types must use only `ULID`, `URL`, `String`, `Date` and Extras types.
- The real behavior is in Router, and the contract is in Extras. A change to the contract touches two packages.

### 5.2 Option B: the protocol in Router, and Multitool links Router

Rejected. It breaks a stated rule of Multitool (`Package.swift:551-556`) and its test. Multitool would pull the MLX packages through Router, and Kanban (which links Multitool) would too.

### 5.3 Option C1: the protocol in Multitool, and ACPAgent adapts Router to it

Rejected. Agents does not link Multitool, so AG-1 cannot use the port. The graph and the trigger handler would need a type of a tool package to talk about sessions.

### 5.4 Option C2: a new package `FoundationModelsSessions`

Not now. The types use `ULID`, `MailID` and `MailSender`, so the new package links Extras anyway. If Extras becomes too big, move `Sessions/` to its own package later. The graph shape stays the same.

### 5.5 Option C3: the directory in ACPAgent

Rejected. It is against D23, and it puts session operations in the ACP package (constraint 3).

### 5.6 Recommendation

Use Option A. The port and the values go in Extras. The implementation goes in Router. The composition of a new session comes in through a Router port that ACPAgent fills. The GraphQL endpoint goes in the existing Multitool library target, next to the tool, over the Extras port (D73, D74).

### 5.7 Where the GraphQL endpoint goes

The endpoint needs three things: the `SessionDirectory` protocol (Extras), the `GraphQLEndpoint` protocol (Extras, EXTRAS-2), and a GraphQL engine (GraphQLSwift and Graphiti, through the GraphQL toolkit of Extras, EXTRAS-6). It does not need a Router type.

| Place | Result |
|-------|--------|
| **In the Multitool library target, next to the `sessions` tool** | The model front end (the tool) and the UI front end (the graph) are in one package over one port, as `KanbanTool` and `KanbanGraph` are in Kanban. They share the visibility rules, the limits and the correctives. Multitool already links Extras, so there is no new edge. **Chosen** (D74). |
| In the Router library target | The resolvers would still use only the Extras protocol. But Router is the model runtime, and the graph is a UI concern. Not chosen (D74). |
| In Extras | Extras holds the contracts and the GraphQL toolkit (EXTRAS-6), not the endpoint of a package. Not chosen. |
| In ACPAgent | Against constraint 3: the resolver would be part of the ACP package. Not chosen. |
| In the app (APP-16) | It works for the app. But the CLI server `acp-agent` and the tests of other packages cannot use it, and the graph is then far from the directory. Not chosen. |
| A new target `FoundationModelsSessionsGraph` | It adds a target and a product to a package. Not chosen (D73). |

The pins of GraphQL and Graphiti are only in Extras (EXTRAS-6, D74). Multitool gets them through Extras, so the app resolves one copy.

The owner client rules (D11) need facts that only ACPAgent has. The tunnel gives them to the resolver as a neutral `GraphQLViewer` value of Extras (EXTRAS-5). Thus the resolver applies the rules with no ACP type.

### 5.8 `find agents`: which package owns it

Decision: **FoundationModelsAgents owns `find agents`**, in the `agents` tool (card `^jcnw05g`). The `sessions` tool and the `sessions` graph do not repeat it.

Reasons:

1. The catalog, its reload (`onReload`), the agent folders (AG-4) and the `description` of each agent are in Agents.
2. The selection uses the skills selection parts (embedding search, then a pick by the `flash` model). Agents already links FoundationModelsSkills. Multitool does not.
3. Multitool cannot link Agents (Agents links Router). A copy in the `sessions` tool would need one more port in Extras for the catalog and for the selection. That is a second door to the same data.
4. One implementation gives one result for one query.

Effects:

- `start session` takes an agent id. The tool description and its correctives tell the model to use `tools.agents.findAgents` or `tools.agents.listAgents` to get an id. (These are the verb names when the `agents` tool is in the registry. Today it is a standalone tool, so the model calls `agents` with the op `find agents`.)
- The launcher (ACPAgent, which links Agents) checks the agent id against the catalog. An unknown id gives a corrective with the near names.
- The UI gets the agent list from the `agents` GraphQL endpoint (D67). The `sessions` graph has no agent query.
- Q5 is answered: the agents that an agent can find are the agent catalog of FoundationModelsAgents.

### 5.9 Module graph before

Only the edges of the library targets. "A → B" means "A links B".

```
FoundationModelsACP          → (none of the family)
FoundationModelsExtras       → (none of the family)
FoundationModelsRanker       → Extras
FoundationModelsMetadataRegistry → Extras, Ranker
FoundationModelsCodeContext  → Extras, Ranker
FoundationModelsSkills       → Extras, MetadataRegistry
FoundationModelsRouter       → Extras
FoundationModelsMultitool    → Extras (core module only), MetadataRegistry, CodeContext
FoundationModelsKanban       → Extras, MetadataRegistry, Multitool   (+ GraphQL, Graphiti)
FoundationModelsAgents       → Router, Extras (+ Operations, Marketplace), Skills
FoundationModelsACPClient    → ACP, Extras
FoundationModelsACPAgent     → ACP, Router, Extras, Multitool, Skills, Agents, CodeContext, Ranker
TestudoApp                   → ACPAgent, ACPClient, Kanban, ...
```

### 5.10 Module graph after

New edges have the mark `(new)`.

```
FoundationModelsACP          → (none of the family)
FoundationModelsExtras       → (none of the family), GraphQL (new), Graphiti (new)   [Sessions/ port: EXTRAS-3; GraphQLViewer: EXTRAS-5; GraphQL toolkit: EXTRAS-6]
FoundationModelsRouter       → Extras                     [implements SessionDirectory: ROUTER-3; no GraphQL]
FoundationModelsMultitool    → Extras (core + Operations (new)), MetadataRegistry, CodeContext   [SessionsGraph: MT-10]
FoundationModelsKanban       → Extras, MetadataRegistry, Multitool   [GraphQL and Graphiti through Extras: KANBAN-5]
FoundationModelsAgents       → Router, Extras (+ Operations, Marketplace), Skills   [no new edge]
FoundationModelsACPClient    → ACP, Extras                [no new edge]
FoundationModelsACPAgent     → ACP, Router, Extras, Multitool, Skills, Agents, ...  [no new edge]
TestudoApp                   → ACPAgent, ACPClient, Kanban, Router, ...   [no new edge: the app has Router through ACPAgent]
```

### 5.11 Proof: no cycle and no forbidden edge

Give each target a level. An edge must go from a higher level to a lower level.

| Level | Targets |
|------:|---------|
| 0 | ACP, Extras |
| 1 | Ranker, Router |
| 2 | MetadataRegistry, CodeContext |
| 3 | Skills, Multitool |
| 4 | Kanban, Agents |
| 5 | ACPClient (links level 0 only) |
| 6 | ACPAgent |
| 7 | App |

- Each edge of section 5.10 goes to a lower level. Thus the graph has no cycle.
- Multitool → Router: no edge. Rule of `PackageManifestTests`: kept.
- Multitool → ACP, ACPAgent or Agents: no edge. Constraint 1: kept.
- Router or Extras → ACP or ACPAgent: no edge. Constraint 2: kept. GraphQL and Graphiti are outside the family.
- The `SessionLauncher` port is in Router. ACPAgent implements it. This is a dependency inversion. The type edge goes from ACPAgent to Router, as today.
- The `GraphQLViewer` is in Extras. ACPAgent (or the app server, APP-16) fills it from the owner registry. The edge goes from ACPAgent to Extras, as today.
- At run time, the directory holds the launcher, and the launcher makes surfaces that hold the directory. This is a reference loop at run time, not a module cycle. The host gives the launcher to the directory after it makes both (`directory.useLauncher(_:)`), and it releases it at shutdown. See ROUTER-8.
- Constraint 3: the operations are on the Extras protocol. The tool and the graph call them. ACP only carries GraphQL text through `_sah/graphql/*`.

## 6. The protocol and the value types (Extras)

Location: `FoundationModelsExtras/Sources/FoundationModelsExtras/Sessions/`, next to `Mail/`.

All types are `Sendable` and `Codable`. They use no Router type and no ACP type.

```swift
import Foundation
import ULID

/// The kind of a session.
public enum SessionKind: String, Sendable, Codable, CaseIterable {
    /// A client started it, or another session, a message or a trigger started it.
    case root
    /// The `agents` tool started it. It works in the folder of its parent.
    case subagent
    /// A user forked another session.
    case fork
}

/// The work state of a session.
public enum SessionState: String, Sendable, Codable, CaseIterable {
    case working
    /// The session waits for an answer: an elicitation or a permission request.
    case needsInput
    case idle
    /// Session > Archive or `archive session` ended the session (D68, D72).
    /// Its transcript stays on disk. It takes no message.
    case archived
}

/// How a root session started. The graph uses it for the tab rule.
public enum SessionOrigin: String, Sendable, Codable {
    case client          // session/new, or the `start` mutation of a UI
    case tool            // `start session` of the sessions tool
    case message         // a message to an agent with no live root session
    case trigger         // a kanban column trigger (D60)
    case fork
}

/// The facts of one session that the directory knows.
public struct SessionSummary: Sendable, Codable, Equatable, Identifiable {
    public let id: ULID
    /// The id of the agent in the agent catalog (D61). `default` for the
    /// root `Agents/AGENT.md`. For a folder agent that is not in the catalog
    /// (D71), `folder:` plus the absolute path of its folder.
    public var agentID: String
    /// The display name of the agent, from the `name` key of its `AGENT.md`.
    public var agentName: String?
    /// The working folder (the cwd). With no folder at the start, it is the
    /// folder of the session that started it (AG-5).
    public var workingDirectory: URL
    public var title: String?
    public var tags: Set<String>
    public var kind: SessionKind
    public var state: SessionState
    /// Subagent: the parent session (agentSpawn). Fork: the original session.
    public var parentID: ULID?
    /// Root session that another session started (tool, message, trigger).
    /// It is not a parent: the session is not a subagent.
    public var startedBy: ULID?
    public var origin: SessionOrigin
    public var createdAt: Date
    public var updatedAt: Date
    /// The last final message of the session, cut to a fixed length.
    public var lastSummary: String?
    /// True when the session is in memory now.
    public var isLive: Bool
}

/// A filter for `sessions(matching:)`. Each field that is not nil must match.
public struct SessionQuery: Sendable, Codable, Equatable {
    public var workingDirectory: URL?
    public var agentID: String?
    public var tag: String?
    public var kind: SessionKind?
    public var state: SessionState?
    public var parentID: ULID?
    public var startedBy: ULID?
    public var includesRecorded: Bool
    public var limit: Int
}

/// A target of a message.
public enum SessionAddress: Sendable, Codable, Hashable {
    case session(ULID)
    /// The newest live root session of the agent, in `folder` when it is
    /// given, else in the folder of the sender. If there is none, the
    /// directory starts one (origin `.message`).
    case agent(id: String, folder: URL?)
    /// The newest live root session with this working folder, of any agent.
    /// If there is none, the send is refused. A folder alone does not name
    /// an agent (D61).
    case folder(URL)
    /// Each live session that has the tag, but not the sender.
    case tag(String)
}

/// Who sends a message.
public enum SessionMessageSender: Sendable, Codable, Hashable {
    /// A session (the tool).
    case session(ULID)
    /// A person through a UI (the graph). The client id is for the audit.
    case user(clientID: String)
}

/// A message to send.
public struct OutgoingSessionMessage: Sendable, Codable, Equatable {
    public var from: SessionMessageSender
    public var to: SessionAddress
    public var text: String
    public var inReplyTo: MailID?
}

/// A message that the directory delivered to one session.
public struct SessionMessage: Sendable, Codable, Equatable, Identifiable {
    /// The id of the mail that carried it. A reply names this id.
    public let id: MailID
    public let from: SessionMessageSender
    public let to: ULID
    public let text: String
    public let inReplyTo: MailID?
    public let sentAt: Date
    /// 1 for a message from a turn that a user started, or from a UI.
    /// Plus 1 for each message in the chain. The limit is in ROUTER-5.
    public let chainDepth: Int
    public var isRead: Bool
}

/// The result of one send: one receipt for each target session.
public struct SessionSendReceipt: Sendable, Codable, Equatable {
    public enum Outcome: String, Sendable, Codable {
        case delivered      // the target was idle: the message starts a turn
        case queued         // the target works: the message waits for the turn end
        case started        // an agent address started a new root session
        case refused        // a loop guard, an archived target or no match refused it
    }
    public let messageID: MailID?
    public let target: ULID?
    public let outcome: Outcome
    public let reason: String?
}

/// A request to start a new root session: an agent plus a working folder.
public struct SessionStartRequest: Sendable, Codable, Equatable {
    /// Nil: the `AGENT.md` of the working folder, else the default agent
    /// (D71). The launcher resolves it.
    public var agentID: String?
    /// Nil: the folder of `startedBy` (AG-5). The launcher resolves it.
    public var workingDirectory: URL?
    public var firstMessage: String
    public var tags: Set<String>
    public var title: String?
    public var startedBy: ULID?
    /// The UI client that asked for the start, for the tab rule. Nil for a
    /// start by a session or a trigger.
    public var requestedByClient: String?
    public var origin: SessionOrigin
}

/// One change in the directory.
public enum SessionDirectoryEvent: Sendable, Codable, Equatable {
    case started(SessionSummary, requestedByClient: String?)
    /// Tags or title changed.
    case factsChanged(SessionSummary)
    case stateChanged(id: ULID, state: SessionState, lastSummary: String?)
    case messageDelivered(SessionMessage)
    /// The session is archived (ROUTER-11).
    case archived(id: ULID)
}

/// The session directory: find, start, tag and message sessions.
///
/// The Router implements it. The `sessions` tool, the `sessions` graph and
/// the trigger handler use it. It has no ACP concept.
public protocol SessionDirectory: Sendable {
    func sessions(matching query: SessionQuery) async throws -> [SessionSummary]
    func summary(of id: ULID) async throws -> SessionSummary?
    func start(_ request: SessionStartRequest) async throws -> SessionSummary
    func addTags(_ tags: Set<String>, to id: ULID) async throws -> SessionSummary
    func removeTags(_ tags: Set<String>, from id: ULID) async throws -> SessionSummary
    func send(_ message: OutgoingSessionMessage) async throws -> [SessionSendReceipt]
    /// The messages to `id` that are not read. With `markRead`, they become
    /// read, and a queued message does not start a turn later.
    func inbox(of id: ULID, markRead: Bool) async throws -> [SessionMessage]
    /// Ends the session `id` (D68): stops a running turn, removes it from the
    /// live list, marks it archived in its facts, and sends `archived`.
    /// `by` is the session or the user that archives it, for the audit.
    func archive(_ id: ULID, by: SessionMessageSender) async throws -> SessionSummary
    /// A new stream for each call. Each stream gets each event after the call.
    func events() -> AsyncStream<SessionDirectoryEvent>
}

/// The errors that the directory throws. The tool turns each one into a
/// corrective text. The graph turns each one into a GraphQL error.
public enum SessionDirectoryError: Error, Sendable, Equatable {
    case unknownSession(ULID)
    case unknownAgent(String, nearNames: [String])
    case notADirectory(URL)
    case chainTooDeep(limit: Int)
    case messageTooLong(limit: Int)
    case invalidTag(String)
    case noLauncher
}
```

Notes:

- `SessionMessage` is a public type in Extras. Router has a file `Session/SessionMessage.swift`, but no type of that name. Thus there is no clash.
- A message from a session goes as `Mail(sender: .session(from), body: .agentMessage(from:content:))`. A message from a UI goes as `Mail(sender: .user, body: .agentMessage…)` with the client id in the record. These types exist in Extras today.
- `ULID` is the session id. It is also the ACP session id (`RoutedACPAgent.swift:84-85`).

## 7. The event stream

The directory sends one event for each change. The sources in Router:

| Event | Source in Router |
|-------|------------------|
| `started` | A session is vended (new, restored or forked) and registered in the directory. A start through the launcher also gives it. |
| `factsChanged` | `addTags`, `removeTags`, a title change. |
| `stateChanged` | `SessionEvent.submissionStarted` (working), `elicitationRequested` (needsInput), `submissionEnded` and `answered` (idle, plus the last summary). A rule never asks (D64), so a rule denial does not give `needsInput`. |
| `messageDelivered` | The directory put a mail in the queue of the target, and the target recorded it. |
| `archived` | `archive(_:by:)` ended the session (ROUTER-11). |

Rules:

1. Each `events()` call makes one new `AsyncStream` with the `.bufferingNewest(256)` policy. A slow reader loses old events, not new ones. After a loss, the reader calls `sessions(matching:)` again.
2. The events of one session come in order.
3. The directory sends `started` before the first `stateChanged` of that session.
4. Subagent sessions also give events. Their `kind` is `subagent`.
5. An event holds no message text that is longer than the limit of ROUTER-5.

The `sessionChanges` subscription of the graph reads this stream (section 11).

## 8. The operations of the tool

### 8.1 Names

The tool is `SessionsTool`, a public struct that holds an `OperationTool<SessionsToolContext>`, with the name `sessions` (D76). It has the same shape as `AgentsTool` and `SkillsCatalogTool`. It follows the style of the `agents` tool (`AgentsToolOperations.swift`) and of the code context tools: `@Generable` plus `@Operation(verb:noun:description:)`, an `execute(in:)` that gives a `CorrectiveOutcome<String>`, and no thrown error for a model error.

Each op becomes one verb under `tools.sessions` (`OperationVerbTool.verbName(for:)`).

| Op string | Verb in code mode | Kind | Doc name (category 15) |
|-----------|-------------------|------|------------------------|
| `list sessions` | `tools.sessions.listSessions` | read | `list` |
| `check session` | `tools.sessions.checkSession` | read | `status` |
| `read inbox` | `tools.sessions.readInbox` | read (marks messages read) | `inbox` |
| `start session` | `tools.sessions.startSession` | changes, delegates work | `start` |
| `tag session` | `tools.sessions.tagSession` | changes facts | new |
| `untag session` | `tools.sessions.untagSession` | changes facts | new |
| `send message` | `tools.sessions.sendMessage` | sends to another agent | `send` |
| `reply message` | `tools.sessions.replyMessage` | sends to another agent | `reply` |
| `archive session` | `tools.sessions.archiveSession` | changes, ends a session | new |

There is no `find agents` op here. See section 5.8.

Why these names:

- `list`, `check`, `start` and `send` are the verbs of the `agents` tool. The same verb means the same action in both tools.
- `tag` and `untag` are the verbs that the kanban tool uses for tasks.
- `check session` mirrors `check agent`: it gives the state at once and never waits.
- The noun of `send` and `reply` is `message`, because the target can be an agent, a folder or a tag.
- `archive` is the name of the Session > Archive command of the app (D68).

### 8.2 Parameters and results

The caller session is `ToolContext.current?.sessionID`. A call with no `ToolContext` (outside a Router session) can only read. `start`, `send`, `reply`, `tag`, `untag`, `archive` and `read inbox` then give a corrective text.

**`list sessions`**

| Parameter | Type | Note |
|-----------|------|------|
| `cwd` | `String?` | An absolute path. `~` expands. |
| `agent` | `String?` | An agent id. |
| `tag` | `String?` | |
| `kind` | `String?` | `root`, `subagent` or `fork` (`allowedValues`). |
| `state` | `String?` | `working`, `needsInput`, `idle` or `archived`. An archived session is not live, so `archived` needs `includeRecorded`. |
| `parent` | `String?` | A session id. Matches `parentID`. |
| `startedBy` | `String?` | A session id. |
| `includeRecorded` | `Bool?` | Default `false`: only live sessions. |
| `limit` | `Int?` | Default 20, maximum 100. |

Result: one line for each session: id, kind, state, agent id and name, folder, title, tags, and "started by" or "parent". The caller session has the mark "(you)". An empty result says "No sessions match."

**`check session`**

| Parameter | Type | Note |
|-----------|------|------|
| `id` | `String` | A session id. |

Result: the state, the agent, the folder, the tags, the last summary, and the count of unread messages from that session to the caller.

**`read inbox`**

| Parameter | Type | Note |
|-----------|------|------|
| `limit` | `Int?` | Default 10. |

Result: each unread message to the caller: the message id, the sender (a session id, title, agent and folder, or "the user"), `inReplyTo`, and the text in a fence with the label "untrusted message". The call marks them read.

**`start session`**

| Parameter | Type | Note |
|-----------|------|------|
| `agent` | `String?` | An agent id from the agent catalog. `default` is the default agent. Use `find agents` of the `agents` tool to get an id. With no `agent`, the agent is the `AGENT.md` of the working folder, else the default agent (D71). |
| `cwd` | `String?` | An absolute path to an existing folder. With no `cwd`, the session works in the folder of the session that started it (AG-5). A start from the UI always gives a folder (APP-5, D70). |
| `message` | `String` | The first message. The new agent sees only this text. |
| `tags` | `[String]?` | |
| `title` | `String?` | |

Result: the new session id, the agent, the folder, and the sentence "The session works in the background. Its reply comes to you as a message." The caller is `startedBy`. The origin is `tool`.

**`tag session` and `untag session`**

| Parameter | Type | Note |
|-----------|------|------|
| `id` | `String?` | Default: the caller session. |
| `tags` | `[String]` | Each tag: 1 to 64 characters, letters, digits, `-`, `_`, `:` and `.`. |

Result: the new tag set.

**`send message`**

| Parameter | Type | Note |
|-----------|------|------|
| `to` | `String` | A session id, `@agent`, `@agent:/path`, an absolute folder path, or `#tag`. The tool reads the form: a ULID; a text that starts with `@`; a path that starts with `/` or `~`; a text that starts with `#`. |
| `message` | `String` | The full text. The target sees only this text. |

Result: one line for each receipt: delivered, queued, started (with the new id) or refused (with the reason).

**`reply message`**

| Parameter | Type | Note |
|-----------|------|------|
| `inReplyTo` | `String` | The id of a message that the caller got. |
| `message` | `String` | |

Result: as `send message`. The target is the sender of the original message. A reply to a message from a user gives a corrective: the session answers a user in its own transcript.

**`archive session`**

| Parameter | Type | Note |
|-----------|------|------|
| `id` | `String` | The id of the session to archive. The caller can archive any session that it can see. |

Result: the session id, the agent, the folder, and the sentence "The session is archived. Its work stopped, and it takes no more messages." The call stops a running turn of the session. There is no built-in limit. Only a deny rule can stop the call (section 8.3).

### 8.3 Risk facts and risk descriptions (MT-1, MT-7)

Each operation declares its risk facts (MT-7). The judge (MT-6) reads them and a plain description of the call. Only model calls go through this check. A UI mutation is an action of the user (section 11.4).

| Op | Risk facts | Description for the judge |
|----|-----------|---------------------------|
| `list sessions` | reads | "List the sessions on this server." |
| `check session` | reads | "Read the state of session S." |
| `read inbox` | reads | "Read the messages to this session." |
| `tag session` | changes (local facts) | "Add tags T to session S." |
| `untag session` | changes (local facts) | "Remove tags T from session S." |
| `start session` | changes, delegates work to another agent | "Start agent A in folder F (or in the folder of this session) with this first message: …" |
| `send message` | sends to another agent | "Send this message to S (or to agent A, which can start a new session, or to each session with tag T): …" |
| `reply message` | sends to another agent | "Reply to message M from S: …" |
| `archive session` | changes, ends the work of a session | "Archive session S: stop its turn and end the session." |

The risk check (D64, MT-1):

- The check can only deny. A `start session`, a `send message` or an `archive session` runs unless a rule denies it. There are no built-in rules for the `sessions` tool, and there are no prompts.
- A denial is the error result of `runCode`, with `sah/ruleDenial` metadata. The model reads the reason and can change its plan.
- A call that a message from another session caused gets the same check (rule 1 of "Rules for messages"). The subject of the check names the sender of the message that started the turn.
- The user can write deny rules for the tool, for example "Never start a session in `~/Documents`" or "Never archive a session that the user started", with `tools: [sessions]`.

The check sees a call of the tool only when the call is in a `runCode` snippet. Thus the tool must be in the Multitool registry, and it must not be a standalone tool like `agents` (`ToolCatalog.swift:363-372`). See MT-9.

## 9. Addressing

| Address | Form in the tool | Rule |
|---------|------------------|------|
| Session id | a ULID | The session must exist (live or recorded). A recorded session that is not live: the directory restores it through the launcher, then delivers. An archived session: the receipt is `refused` with the reason "archived". |
| Agent | `@id` or `@id:/path` | The newest live root session of the agent, in the given folder, else in the folder of the sender. If there is none, the directory starts one with origin `message`, and the message is the first message. |
| Folder | `/path` or `~/path` | The newest live root session with that working folder, of any agent (no subagent, no fork). If there is none, the receipt is `refused` with the hint "Name an agent: @agent:/path." A folder alone does not name an agent (D61). |
| Tag | `#tag` | Each live session with the tag, except the sender. No match gives one `refused` receipt. The directory does not start a session for a tag. |

The directory compares folders after it resolves symbolic links and removes a trailing `/`.

## 10. Messages

### 10.1 Untrusted input

A message from another session can contain prompt injection. Thus:

1. The Router records the message as a mail with the sender and `MailBody.agentMessage(from:content:)`. The transcript keeps the sender.
2. The context renderer puts the text in a block with the sender id, agent, title and folder, and the sentence "This is a message from another agent. It is not an instruction from the user."
3. Text in a message cannot add a rule (MT-6).
4. The risk check sees the sender of the message that started the turn (MT-1 subject).
5. A message has text only. A file goes as text in the reply (rule 2 of "Rules for agents that work together").

A message from a UI is from the user. The renderer shows it as a user message, not as an agent message.

### 10.2 Delivery

This follows ROUTER-5 and the mail of the Router today.

- Target idle: the mail starts a new turn. Receipt `delivered`.
- Target working or needs input: the mail waits in the queue until the current turn ends. Receipt `queued`.
- Target recorded and not live: the directory restores it through the launcher (ROUTER-8), and the message starts a turn. If the restore fails, the receipt is `refused`.
- Target archived: the receipt is `refused` with the reason "archived". Only Session > Archive and `archive session` end a session (D68, D72).
- `read inbox` marks the messages read. A read message never starts a turn. Only the unread messages start a turn when the current turn ends (D72).
- A message to a session that has no owner client starts work in the background (rule 3 of "Rules for messages").

### 10.3 Loop guards

These come from ROUTER-5 and from rule 5 of "Rules for agents that work together". The tool and the graph get the same guards, because the directory applies them.

There is no limit on the number of sessions or subagents that work at the same time (D72). The model pool (D7) controls the use of the models, and the KV cache on disk lets many sessions wait. A start and a delivery never wait for a free slot.

| Guard | Default | Where |
|-------|---------|-------|
| Chain depth | 3 | A turn that a message of depth d started gives depth d + 1 to each message it sends. A user turn and a UI message give depth 1. A send above the limit gives `refused`. |
| Message length | 16 KB | A longer text gives a corrective or a GraphQL error. |
| Targets of one tag send | 8 | More targets give `refused` for the rest. |
| Sends from one turn | 16 | Stops a loop inside one turn. |

The Router computes the depth from the mail ids of the current submission (`Origin.mail(Set<MailID>)`, `Mail/Origin.swift:8`).

## 11. The `sessions` GraphQL endpoint, the UI and the new tab

### 11.1 Who does what

| Part | Package | Does |
|------|---------|------|
| Directory and events | Router (through the Extras port) | Holds the sessions, tags and messages, and the record of past sessions. Applies the loop guards. Archives sessions. Sends events. |
| Launcher | ACPAgent, in a file with no ACP import (ACPA-9) | Resolves the agent in the catalog of Agents. Composes the tools of a new root session for the agent and the folder. |
| `sessions` endpoint | `SessionsGraph` in the Multitool library target (MT-10) | Schema, resolvers, visibility and owner rules, the subscription. |
| Endpoint registry | Server (APP-16) | Registers `sessions` next to `kanban`: one time by name for server scope, one time for each `(name, cwd)` for folder scope (D77). |
| Owner registry and viewer | ACPAgent (ACPA-5, ACPA-13) | Knows the owner connection of each session (D11). Gives a `GraphQLViewer` to each tunnel call. |
| Tunnel | ACP-3, ACPC-4, APP-16 | Carries `_sah/graphql/*`. |
| Client | `SAHGraphQLClient` with the endpoint `sessions` (ACPC-6, APP-16) | Sends queries and the subscription through the tunnel. |
| Tab rule | App | Opens a tab. Tabs are client state (D54). |

### 11.2 Schema sketch

The scope of the endpoint is the server, not the session folder. The version starts at 1.

```graphql
scalar DateTime
scalar ID            # a session id (ULID) or a message id (MailID)

enum SessionKind { ROOT SUBAGENT FORK }
enum SessionState { WORKING NEEDS_INPUT IDLE ARCHIVED }
enum SessionOrigin { CLIENT TOOL MESSAGE TRIGGER FORK }
enum SendOutcome { DELIVERED QUEUED STARTED REFUSED }
enum SessionChangeKind { STARTED FACTS_CHANGED STATE_CHANGED MESSAGE_DELIVERED ARCHIVED }

type Session {
  id: ID!
  agentId: String!
  agentName: String
  cwd: String!
  title: String
  tags: [String!]!
  kind: SessionKind!
  state: SessionState!
  origin: SessionOrigin!
  parent: Session            # subagent: its parent; fork: the original
  startedBy: Session         # root session that another session started
  children: [Session!]!      # subagents of this session
  createdAt: DateTime!
  updatedAt: DateTime!
  lastSummary: String
  isLive: Boolean!
  ownedByViewer: Boolean!    # D11: this client owns the session now
  hasOwner: Boolean!
  unreadCount: Int!          # unread messages to this session
}

type Sender {
  session: Session           # null for a message from a user
  clientId: String           # set for a message from a user
}

type Message {
  id: ID!
  from: Sender!
  to: Session!
  text: String!
  inReplyTo: ID
  sentAt: DateTime!
  chainDepth: Int!
  isRead: Boolean!
}

type SendReceipt {
  messageId: ID
  target: Session
  outcome: SendOutcome!
  reason: String
}

input SessionFilter {
  cwd: String
  agentId: String
  tag: String
  kind: SessionKind
  state: SessionState
  parentId: ID
  startedById: ID
  includeRecorded: Boolean = false
  limit: Int = 50
}

input StartSessionInput {
  agentId: String!
  cwd: String                # null: the folder of the session that starts it (AG-5)
  message: String!
  tags: [String!]
  title: String
  openInTab: Boolean = true
}

input SendMessageInput {
  to: AddressInput!
  text: String!
}

input AddressInput {         # exactly one field
  sessionId: ID
  agentId: String
  agentCwd: String           # only with agentId
  cwd: String
  tag: String
}

type SessionChange {
  kind: SessionChangeKind!
  session: Session           # null for MESSAGE_DELIVERED on a hidden target
  message: Message           # only for MESSAGE_DELIVERED
  openInTab: Boolean!        # only true for STARTED, see 11.5
}

type Query {
  sessions(filter: SessionFilter): [Session!]!
  session(id: ID!): Session
  inbox(sessionId: ID!, limit: Int = 50): [Message!]!
}

type Mutation {
  start(input: StartSessionInput!): Session!
  tag(sessionId: ID!, tags: [String!]!): Session!
  untag(sessionId: ID!, tags: [String!]!): Session!
  send(input: SendMessageInput!): [SendReceipt!]!
  reply(inReplyTo: ID!, text: String!): [SendReceipt!]!
  archive(sessionId: ID!): Session!   # Session > Archive (D68)
}

type Subscription {
  sessionChanges(filter: SessionFilter): SessionChange!
}
```

Notes:

- The `inbox` query does not mark messages read. Only the `read inbox` op of the model marks them read, because only the target session reads its inbox to act on it.
- `archive` is the UI path of Session > Archive. It calls `SessionDirectory.archive(_:by:)` with the sender `user(clientID)`.
- `start` is the UI path to start a session with an agent and a folder. The ACP `session/new` path stays for clients that do not use the graph. Both end in the same launcher.
- The resolvers call only the `SessionDirectory` protocol. They do not call Router types.

### 11.3 The viewer and the resolver rules

The tunnel gives each call a `GraphQLViewer` (EXTRAS-5). ACPAgent fills it from its owner registry (ACPA-13).

```swift
/// The client that makes a GraphQL call. Neutral: no ACP type.
public struct GraphQLViewer: Sendable {
    public enum Trust: String, Sendable, Codable {
        /// The in-process UI, or a device of the same Apple ID (D14 to D17).
        case userDevice
        /// Another ACP client on localhost with the bearer token.
        case external
    }
    public let clientID: String
    public let trust: Trust
    /// The session ids that this client owns now (D11).
    public let ownedSessions: @Sendable () async -> Set<ULID>
    /// The session ids that have an owner now, of any client.
    public let ownedByAnyClient: @Sendable () async -> Set<ULID>
}
```

Visibility (which sessions a client can see):

| Trust | Sees |
|-------|------|
| `userDevice` | All sessions on this server. One person uses all these devices (D14). |
| `external` | The sessions that it owns, their subagents, and the sessions that they started (`startedBy`), to any depth. It does not see other sessions. |

A field or a list never shows a session that the viewer cannot see. `parent` or `startedBy` of a hidden session is `null`. A message on a hidden session does not come on the subscription.

Mutation rules:

- `start`: `userDevice` only. The new session has `origin = client` and `requestedByClient = clientID`. The tab rule (11.5) opens it on this client.
- `tag`, `untag`: `userDevice`, or `external` on a session that it owns.
- `send`, `reply`: the sender is `user(clientID)`. The target must be visible. An `external` client can send only to sessions that it owns.
- `archive`: any session that the viewer can see. There is no built-in limit (D72).
- The directory applies the same loop guards as for the tool (section 10.3). The MT-1 risk check does not apply: this is an action of the user, not of a model. The audit records the client id.
- A mutation does not change the owner of a session. Ownership changes only with `session/new`, `session/resume` and `session/close` (D11).

### 11.4 The model and the UI share one directory

- The tool and the graph call the same `SessionDirectory` instance (`router.sessionDirectory`). A tag that the model adds shows in the UI at once, through `FACTS_CHANGED`. A message that a user sends shows in the inbox of the session.
- The rules that are in the directory (address resolution, loop guards, untrusted marking, delivery, archive) are the same for both.
- The rules that differ: the model goes through MT-1, and the UI goes through the visibility and owner rules of 11.3.

### 11.5 The flow of a start, end to end

1. The model in session P (owner client C, agent `app`, folder `~/code/app`) runs `tools.sessions.startSession({agent: "api", cwd: "~/code/api", message: "Add the orders endpoint"})`.
2. Before the snippet runs, `MultiTool.runSnippet` checks it one time (MT-1). The checker reads the code, the scanned call `sessions.startSession` with its literal arguments, session P and the risk facts. No rule denies it, so the snippet runs. A denial would be the `runCode` error result with `sah/ruleDenial` (section 8.3).
3. The tool calls `directory.start(SessionStartRequest(agentID: "api", workingDirectory: ~/code/api, firstMessage: …, startedBy: P, origin: .tool))`.
4. `RouterSessionDirectory` checks the loop guards of the first message. It calls `launcher.launchRootSession(…)`. No limit on the number of working sessions applies (D72).
5. The ACPAgent launcher (ACPA-9) resolves the folder (with no `cwd`, the folder of `startedBy`, AG-5). Then it resolves the agent (D71): an `agent` id is found in the agent catalog, and an unknown id throws `unknownAgent` with the near names. With no `agent`, the agent is the `AGENT.md` of the folder, else the default agent. Here it finds `api` in the catalog. The launcher loads the configuration of the folder, and composes the surface. The surface includes the `sessions` tool over the same directory. It makes the Router session.
6. Router vends the session. The directory registers it, writes its facts (agent, `startedBy`, `origin`, tags), and sends `started(summary, requestedByClient: nil)`.
7. The directory puts the first message in the queue as a mail. The new session starts its first turn with no owner client. It works in the background.
8. The tool answers the model with the new session id.
9. Each client that has a `sessionChanges` subscription gets the change through `_sah/graphql/next`. The resolver of the subscription computes `openInTab` for each viewer:
   - `requestedByClient` is set: `true` only for that client.
   - Else, for the origins `tool` and `message`: the resolver follows `startedBy`, then `parentID`, to the first session with an owner (rule 4 of "Rules for agents that work together"). `true` only for the client that owns that session (here C).
   - For the origin `trigger`: `false` (11.8).
   - For a subagent: `false` (11.7).
10. The app on C gets `STARTED` with `openInTab: true`. It calls `connection.resumeSession(ResumeSessionRequest(sessionId:, cwd:))`.
11. ACPAgent handles `session/resume`. The session is live in the directory, so it attaches the live session to this connection (ACPA-11). It does not close the session and does not restore it from disk. It replays the history so far, and C becomes the owner (D11).
12. `ConnectionModel.register` adds the `SessionModel` to `openSessions` (`ConnectionModel.swift:33-41`). The app opens a tab for it. The tab does not take the focus.
13. The next `STATE_CHANGED` and `FACTS_CHANGED` changes show `ownedByViewer: true` on C.

The start also shows as a tool call card in session P (the normal tool call path).

A start from the UI is the same from step 3, with `origin: .client` and `requestedByClient: C`. The UI does not need a separate `session/new`.

### 11.6 Owner client rules (D11)

- A new root session has no owner until a client attaches it (step 11).
- Only the owner gets the `session/update` stream and the requests for input of the session.
- While no client owns the session, its requests for input go to the owner of the first session with an owner in the `startedBy` chain, then in the `parentID` chain (rule 4). The request names the session that needs the input. If no session has an owner, the request waits, and the session state is `needsInput`. The Sessions window shows it.
- A second client that resumes the session takes the ownership. ACPA-5 defines the hand-over. The first client sees `ownedByViewer: false` on the next change and closes its tab.
- An archive ends the session (ROUTER-11). ACPAgent removes it from the table of its owner connection. The owner client gets the `ARCHIVED` change and closes its tab.

### 11.7 Subagent sessions

- The `agents` tool starts subagents. Router vends them with `agentSpawn`. The directory registers them with `kind = subagent` and `parentID = agentSpawn.parentSessionId`.
- They come on the subscription with `openInTab: false`. The app shows them in the subagent tree of the tab of the parent (D32) through `Session.children`, and as tool call cards (ACPA-4). It does not open a tab.
- A message to a subagent and from a subagent uses the same directory. `send caller` becomes `send message` to the parent (AG-1).

### 11.8 Sessions that kanban triggers start (D60)

- The trigger handler of the app (APP-10) calls `directory.start` with the agent of the task, the target folder, `origin: .trigger`, `startedBy:` the coordinator session, and the tag `kanban:<task id>`.
- The session is a root session in the target folder. It is not a subagent (D60 (a)). Its `parentID` is nil. Its `startedBy` is the coordinator. This keeps the kinds table of category 15 true (`agentSpawn == nil` for a root).
- It comes on the subscription with `openInTab: false`. The card links to the session, and the Sessions window shows it (D60 rule 3).
- Requests for input of the task session go to its owner. If it has none, they go to the owner of the coordinator (D60 rule 2). This is the rule of 11.6.

### 11.9 Remote clients

- A remote client (iPad, D16) uses the same endpoint through the tunnel over HTTP (D10, D54, D55).
- If the owner of P is the iPad, the iPad gets `openInTab: true` and opens the tab. The Mac UI gets `openInTab: false`. It shows the new session in the Sessions window, but it does not open a tab.
- A client that connects later runs the `sessions` query to get the full list, and then subscribes.
- An `external` client sees only the sessions of 11.3.

## 12. Interaction with the `agents` tool (AG-1, D61)

- `send agent` and `send caller` move to the `sessions` tool. `send message` to a subagent id replaces `send agent`. `send message` to the parent id replaces `send caller`.
- For one release, `send agent` and `send caller` stay as thin aliases. They call `SessionDirectory.send`. They give a short note: "Use `tools.sessions.sendMessage`." Then they go.
- The `agents` tool keeps `list agents`, `find agents` (card `^jcnw05g`), `start agent`, `check agent` and `cancel agent`.
- `find agents` gives agent ids. The model uses an id in `start session` (a root session in a folder) or in `start agent` (a subagent in the folder of the parent). Both use the same catalog (AG-4).
- The final message of a subagent still comes to the parent as mail. That is the result of a tool call, not a session message.
- The `agents` tool is a standalone tool today, so MT-1 does not see it (ACPA-2 handles it). The `sessions` tool is in the registry, so MT-1 sees it.
- `AgentsToolContext` gets an optional `SessionDirectory`. Agents links Router and Extras already, so this adds no edge.

## 13. Testing

All tests are automated. No test needs a person.

### 13.1 Extras (EXTRAS-4)

- A public fake: `InMemorySessionDirectory`, a public test double in the existing Extras library target (no test-support product, D73). Its doc comment marks it as a test double. It holds sessions, tags and messages in memory, applies the loop guards of section 10.3 and the archive rules (ROUTER-11), and sends events. A fake launcher option gives it a list of known agent ids.
- Tests: `Codable` round trip of each value type. The event order rule. The buffer rule of the stream.

### 13.2 Multitool (MT-2)

Use the fake directory. No model and no Router.

- Each op: a good call, and each corrective text (unknown session, unknown agent with near names, relative path, missing folder, empty message, invalid tag, no `ToolContext`).
- `start session` with no `cwd` sends a request with a nil folder.
- `send message` parses each address form (ULID, `@agent`, `@agent:/path`, `/path`, `~/path`, `#tag`).
- `archive session`: a good call, and an unknown id.
- The registry mounts `tools.sessions.*` with the nine verb names of section 8.1. A golden file pins the rendered surface.
- A risk check fake records each snippet subject. A snippet that calls a mutating op of `sessions` gives the scanned call and its risk facts, and a denial stops the snippet before the directory sees a call.
- `PackageManifestTests` still passes: the library target links no Router.

### 13.3 Router (ROUTER-3, ROUTER-4, ROUTER-5, ROUTER-8, ROUTER-9, ROUTER-11)

Use the test support of Router (scripted models, no real model).

- A vended session is in the directory. A subagent has `kind = subagent`. A fork has `kind = fork`.
- Tags: add, remove, persist to the facts file, and read back after a restore.
- `start` calls a fake launcher with the agent id and the folder. It sends `started`, and the first message starts a turn.
- `send` to an idle session starts a turn. `send` to a working session waits until the turn ends. `read inbox` with `markRead` stops a later turn.
- Agent address: newest live root session of the agent; a new session when there is none. Folder address: refused when there is no session.
- Tag address: all but the sender; the target limit.
- Loop guards: the chain depth, the length limit, the sends of one turn, the targets of one tag send. A UI sender and a session sender get the same guards.
- No cap: many sessions start and work at the same time, and no start or delivery waits for a slot.
- State events: working, needsInput (elicitation), idle with the last summary, archived. A rule denial does not give needsInput.
- Recorded sessions: `includesRecorded` finds sessions on disk after a new process, through `SessionIndex`. A send to a recorded session restores it, and the message starts a turn.
- Archive: a working session stops its turn, leaves the live list, sends `archived`, and has `archivedAt` in its facts after a restart. A send to it gives `refused` with the reason "archived". The launcher does not restore it.

### 13.4 The `sessions` graph (MT-10)

In the existing `FoundationModelsMultitoolTests` target. Use the fake directory and fake viewers. No ACP, no model and no Router.

- The SDL of the endpoint matches a golden file.
- Each query, each mutation and the subscription, with a `userDevice` viewer.
- Visibility: an `external` viewer sees only its own sessions, their subagents and the sessions that they started. `parent` of a hidden session is `null`.
- Mutation rules: an `external` viewer cannot `start`, and cannot send to a session that it does not own.
- `archive`: each viewer can archive each session that it can see, and no other session.
- `openInTab`: true only for the requesting client (UI start); true only for the owner of the first owned session in the chain (tool start); false for a trigger and a subagent.
- A mutation does not change the owner.
- The endpoint conformance tests of the Extras test kit (EXTRAS-6) pass.
- A source scan checks that the files of `SessionsGraph` use only the Extras `SessionDirectory` protocol. `PackageManifestTests` still passes: the library target links no Router.

### 13.5 ACPAgent (ACPA-9, ACPA-11, ACPA-13)

Use the in-memory transport of FoundationModelsACP and the existing `FoundationModelsACPClient` product. ACPAgent tests already link it. There is no new test product (D73).

- The launcher resolves an agent id from a fixture catalog, with and without a folder. With no folder, the cwd is the folder of `startedBy`. The `default` id gives the root agent folder.
- With no agent id, the launcher uses the `AGENT.md` of the folder (the summary has the id `folder:<path>` when the folder is not in the catalog), and the default agent when the folder has no `AGENT.md` (D71). With an agent id, an `AGENT.md` in the folder is project instructions.
- The launcher file imports no FoundationModelsACP symbol.
- `session/resume` of a live session that works now attaches it. The turn does not stop. The replay holds the first message. The client becomes the owner.
- The viewer of a tunnel call holds the owned sessions of its connection, and the trust of the connection.
- `session/list` and `session/resume` read the record of past sessions from Router (ACPA-14). ACPAgent has no `SessionIndex` and no `ProjectRegistry`.
- An `archived` event removes the session from the table of its connection.
- No `_sah/sessions/*` method or notification exists. A test checks the list of methods that `initialize` advertises.

### 13.6 One end-to-end test

In the ACPAgent test target, with the tunnel and the `sessions` endpoint registered: a scripted model in session P calls `tools.sessions.startSession`. The test client has a `sessionChanges` subscription. It gets `STARTED` with `openInTab: true`, calls `resumeSession`, and `openSessions` has two models. This test covers section 11.5 steps 1 to 13 with no real model.

## 14. Planned changes

Each change has a spec, a reason (Why) and its dependencies. New IDs continue the numbers of the design documents. Changes to existing IDs are marked "refines".

### EXTRAS

#### EXTRAS-3 Session directory port

- **Spec:** Add `Sources/FoundationModelsExtras/Sessions/` with the types of section 6. No Router type, no ACP type. All `Sendable` and `Codable`.
- **Why:** D23, D35, D61, user constraints 1 to 3. Multitool cannot link Router. Extras is the shared base (as for `Mail` and EXTRAS-2).
- **Depends on:** —

#### EXTRAS-4 In-memory session directory for tests

- **Spec:** `InMemorySessionDirectory`, a public test double in the existing `FoundationModelsExtras` library target (no test-support product, D73), which conforms to `SessionDirectory` and applies the loop guards of section 10.3 and the archive rules.
- **Why:** Multitool, Agents, the graph and ACPAgent tests need a directory with no Router and no model.
- **Depends on:** EXTRAS-3

#### EXTRAS-5 Viewer of a GraphQL call

- **Spec:** Add `GraphQLViewer` (section 11.3) and give it to `execute` and `subscribe` of the `GraphQLEndpoint` protocol (EXTRAS-2). An endpoint that does not need it (for example `kanban`) ignores it.
- **Why:** D11. The resolver of the `sessions` endpoint must know the client and its owned sessions, with no ACP type (constraint 2).
- **Depends on:** EXTRAS-2

### ROUTER

#### ROUTER-1 Session facts (refines)

- **Spec:** `workingDirectory` and `agentSpawn` are already in the sidecar (`SessionSidecar.swift:86, 90`). Add a second, mutable file `facts.json` in the recording directory of each session, with `agentID`, `agentName`, `tags`, `title`, `startedBy`, `origin` and `archivedAt` (nil until an archive). Write it atomically. The sidecar stays write-once. `SessionConfiguration` gets the same fields.
- **Why:** D23, D61. The sidecar is write-once (`SessionSidecar.swift:225-235`), and tags change later. A session is an agent plus a folder, so the agent id is a fact of the session.
- **Depends on:** —

#### ROUTER-2 Session tags (refines)

- **Spec:** Tags at creation (`SessionConfiguration.tags`). Later changes only through `SessionDirectory.addTags` and `removeTags`. Each change sends `factsChanged`.
- **Why:** D23. One path for each change, so that each change gives an event.
- **Depends on:** ROUTER-1, ROUTER-3

#### ROUTER-3 Session directory (refines)

- **Spec:** `RouterSessionDirectory`, an actor that conforms to the Extras `SessionDirectory`. The `Router` actor holds one (`router.sessionDirectory`). Each session that a profile of this router vends (new, restored, forked, subagent) registers itself. The directory holds weak references to live sessions and reads `SessionEvent` for the state. Router owns the record of past sessions: `SessionIndex` and `ProjectRegistry` move from ACPAgent `Transcripts/` into Router `Recording/`, and the directory reads recorded sessions through them. There is no `RecordedSessionCatalog` port.
- **Why:** D23, D72. Router has no live list today (`Router.swift:36-219`). The live list is per connection in ACPAgent (`RoutedACPAgent.swift:84-88`). `SessionIndex` and `ProjectRegistry` have no ACP concept, so one package owns the live list and the record.
- **Depends on:** EXTRAS-3, ROUTER-1

#### ROUTER-4 Messages between sessions (refines)

- **Spec:** `send` resolves the address (section 9) and delivers each message as a `Mail` with `MailBody.agentMessage(from:content:)` through `MailSink.mail(_:)`. The sender is a session or a user. The record keeps `inReplyTo`, the chain depth and, for a user, the client id. `inbox(of:markRead:)` reads the queue. A `messageDelivered` event follows each delivery.
- **Why:** D22, D23. The mail types already exist in Extras (`MailBody.swift:22`, `MailSender.swift:17`).
- **Depends on:** ROUTER-3, ROUTER-8 (an agent address can start a session)

#### ROUTER-5 Message delivery and loop guards (refines)

- **Spec:** The delivery rules of section 10.2 (an idle target starts a turn, a working target queues, a recorded target restores, an archived target refuses, a read message never starts a turn) and the loop guards of section 10.3, for each sender. The depth comes from the mail ids of the current submission. There is no limit on the number of sessions that work at the same time.
- **Why:** D22, D72, rule 5 of "Rules for agents that work together". The model pool (D7) controls the load.
- **Depends on:** ROUTER-4, ROUTER-8

#### ROUTER-8 Session launcher port

- **Spec:** `public protocol SessionLauncher: Sendable { func launchRootSession(_ request: SessionStartRequest) async throws -> any RoutedSession; func restoreSession(_ id: ULID) async throws -> any RoutedSession }`. The launcher resolves the agent id and the folder. The host sets it with `directory.useLauncher(_:)`. The directory releases it at shutdown, to break the run-time reference loop. With no launcher, `start` and an agent send throw `noLauncher`.
- **Why:** The Router cannot compose the tools of a session and does not know the agent catalog. A port keeps ACPAgent and Agents out of Router (constraint 2).
- **Depends on:** ROUTER-3

#### ROUTER-9 Session state and last summary

- **Spec:** The directory maps `SessionEvent` to `SessionState` (section 7) and keeps the last final message, cut to 500 characters, as `lastSummary`.
- **Why:** `check session`, the `Session.state` field and the Sessions window (D32) need the state and the summary.
- **Depends on:** ROUTER-3

#### ROUTER-11 Archive a session

- **Spec:** `RouterSessionDirectory.archive(_:by:)`. It stops a running turn of the session, removes the session from the live list, writes `archivedAt` to `facts.json`, and sends `archived(id:)`. A later send to the session gives `refused` with the reason "archived", and the directory does not restore it. The tool (`archive session`) and the graph (`archive`) call it for any session that the caller can see. There is no built-in limit. Only a deny rule (D64) stops a model call, through the risk check of the `runCode` snippet.
- **Why:** D68 (only Session > Archive ends a session), D72.
- **Depends on:** ROUTER-1, ROUTER-3, ROUTER-5 (the archived refusal is a delivery rule)

### MT

#### MT-2 `sessions` tool (refines)

- **Spec:** `SessionsTool`, a public struct that holds an `OperationTool<SessionsToolContext>`, with the name `sessions` and the nine operations of section 8. `start session` takes `agent` and an optional `cwd`. `SessionsToolContext` holds `any SessionDirectory`. Correctives, never thrown model errors. Risk facts of section 8.3 (MT-7). No `find agents` op (section 5.8). The tool is an op tool, and the model does not send GraphQL text to it. It conforms to `GraphQLEndpointTool` (EXTRAS-7), and its `graphQLEndpoints` is a list of one, `SessionsGraph` over the same directory (MT-10, D75, D82). The struct conforms, and `OperationTool` does not change (D76). The tool is a top-level tool of the session, like `skills` and `agents`. The same instance is also in the registry (MT-9). The rules apply only in `runCode`, so a direct call of the top-level tool does not go through them.
- **Why:** D35, D21, D22, D61, D72, D75, D76.
- **Depends on:** EXTRAS-3, MT-9, MT-1, MT-7

#### MT-9 Mount operation tools in the library, and `withSessions`

- **Spec:** The library target links the `Operations` product of Extras. `MultiTool.Builder.withSessions(_ tool: SessionsTool)` registers the `SessionsTool` instance of the session under the noun `sessions`, so a snippet calls each verb as `tools.sessions.*`, and the snippet check sees it. It is the same instance that is also a top-level tool of the session (D76). Update the header comment of `Capabilities/Files/Read.swift:3-8`, which says the package has no operation machinery. `PackageManifestTests` stays as it is.
- **Why:** The tool uses `@Operation` (the style of the existing operation tools). The risk check (MT-1) sees only the tools in the registry. The rules apply only in `runCode` (D76).
- **Depends on:** —

#### MT-10 The `sessions` GraphQL endpoint

- **Spec:** `SessionsGraph` in the existing `FoundationModelsMultitool` library target, next to `SessionsTool`. No new target and no new product (D73). GraphQL and Graphiti come through the GraphQL toolkit of Extras (EXTRAS-6). Multitool adds no pin of its own. The resolvers use only the Extras `SessionDirectory` protocol. `SessionsGraph(directory: any SessionDirectory)` conforms to `GraphQLEndpoint`: name `sessions`, version 1, scope server, the SDL of section 11.2. Queries: `sessions`, `session` and `inbox`. Mutations: `start`, `tag`, `untag`, `send`, `reply` and `archive`. Subscription: `sessionChanges`, which reads `directory.events()`. The resolvers apply the visibility and mutation rules of section 11.3, and the `openInTab` rule of section 11.5 step 9. The errors, the warnings and the rewrites use the conventions of the toolkit (`extensions.code`, `extensions.warnings`, `extensions.rewrites`). The tool and the graph share the visibility rules, the limits and the correctives. The `sessions` tool gives the graph in its `graphQLEndpoints` (EXTRAS-7), and the app registers the endpoint that it gets from the tool. Thus MT-10 comes after MT-2.
- **Why:** Q-S1 (the user decision): UIs use the directory through a GraphQL endpoint, the same pattern as `kanban` (D55). D73: no new target in a package. D74: each package owns its endpoint, and the tool and the graph are two front ends over one port. D75: the tool gives its endpoint. Section 5.7 tells why the graph goes in the Multitool library target.
- **Depends on:** EXTRAS-2, EXTRAS-3, EXTRAS-5, EXTRAS-6, EXTRAS-7, MT-2 (the tool and the shared rules). At run time it uses the behavior of ROUTER-3 to ROUTER-11.

### AG

#### AG-1 Move messages to the `sessions` tool (refines)

- **Spec:** `send agent` and `send caller` call `SessionDirectory.send` and give a note that names `tools.sessions.sendMessage`. Remove them one release later. `AgentsToolContext` gets an optional directory.
- **Why:** D22, D35.
- **Depends on:** MT-2, ROUTER-4

#### `find agents` (card `^jcnw05g`, no new ID)

- **Spec:** As in the card: `find agents` in the `agents` tool. This plan adds one point: its result gives the agent id in the form that `start session` takes.
- **Why:** D61 (f). Section 5.8 tells why Agents owns it.
- **Depends on:** AG-4

### ACPA

#### ACPA-9 Session launcher with no ACP concept

- **Spec:** Move the composition of `session/new` (`SessionSetup.swift:546-600`, `composeSession` at `:837-918`) into a `SessionComposer` that has no connection and imports no FoundationModelsACP. `RoutedACPAgent.newSession` and the new `ComposedSessionLauncher` (which conforms to the Router `SessionLauncher`) both use it. The launcher resolves the folder first: with no folder, the folder of `startedBy` (AG-5). Then it resolves the agent (D71): an agent id in the catalog of FoundationModelsAgents (with the agent folders of AG-4), else the `AGENT.md` of the folder, else the default agent. It makes one `SessionsTool` for each session. It adds that instance as a top-level tool in `ToolCatalog.makeStandaloneTools` (`ToolCatalog.swift:363`), next to `skills` and `agents`, and it gives the same instance to `withSessions(_:)` in `ToolCatalog.makeRegistry` (`ToolCatalog.swift:403-470`) (D76).
- **Why:** The directory must start a session with the full surface of its agent and folder (D19, D21, D61) and with no client.
- **Depends on:** ROUTER-8, ACPA-1, MT-9, AG-4, AG-5

#### ACPA-5 One `RoutedACPAgent` for each connection (dependency)

- **Spec:** As in the design. Also: the shared registry maps each session id to its owner connection, and it knows the trust of each connection (in-process or Apple ID device, or external).
- **Why:** The viewer of each tunnel call needs the owner and the trust (D11, ACPA-13).
- **Depends on:** —

#### ACPA-11 Attach a live session on `session/resume`

- **Spec:** When the session id of `session/resume` names a live session in the directory that this connection does not hold, attach it: add the table entry and the projector, replay the history, and take the ownership. Do not close it and do not restore it from disk. Keep today's teardown and restore (`SessionResume.swift:130-137`) only for a session that is not live.
- **Why:** The app opens a tab with `session/resume` (section 11.5 step 10). Today a resume stops the work of a live session.
- **Depends on:** ROUTER-3, ACPA-5

#### ACPA-13 Viewer for the GraphQL tunnel

- **Spec:** Each `_sah/graphql/*` call that the tunnel carries gets a `GraphQLViewer` (EXTRAS-5) from the owner registry of ACPA-5: the client id, the trust, and the owned sessions. ACPAgent does nothing else for the `sessions` endpoint.
- **Why:** D11 and the visibility rules of section 11.3. The resolver cannot read ACP state (constraint 2).
- **Depends on:** ACPA-5, EXTRAS-5, ACP-3

#### ACPA-14 Read past sessions from Router

- **Spec:** Remove `Transcripts/SessionIndex.swift` and `Transcripts/ProjectRegistry.swift` from ACPAgent. `session/list` and `session/resume` read the record of past sessions from Router (ROUTER-3). `TranscriptStore` uses the Router types.
- **Why:** D72. Router owns the record of past sessions. ACPAgent only carries it over ACP.
- **Depends on:** ROUTER-3

#### ACPA-6 Messages from other sessions (refines)

- **Spec:** A delivered message shows in the transcript of the target as a standard `session/update` (a user message chunk) to the owner of the target, with `_meta.sah.message = { from, fromTitle, fromAgent, fromCwd, messageId, inReplyTo }`. This is the transcript, not a directory projection.
- **Why:** D22, rule 2 of "Rules for messages".
- **Depends on:** ROUTER-4

### ACPC

No new ACPC change for sessions. The client reaches the endpoint with `SAHGraphQLClient` (ACPC-6) and the endpoint name `sessions`, over the extension point of ACPC-4 (APP-16). The observable model of the sessions is a client model of APP-16 over that endpoint, the same as for the board.

#### ACPC-2 Subagent sessions and messages in the client model (refines)

- **Spec:** Read the subagent tree from `Session.children` of the `sessions` endpoint, not from a second source. Show `_meta.sah.message` as "From: <title> (<agent>, <folder>)".
- **Why:** One source of truth for the session tree.
- **Depends on:** MT-10, ACPA-6, ACPC-4

### Changes that this revision removes

- **ACPA-10 Directory projection to ACP**: removed. There are no `_sah/sessions/changed` and `_sah/sessions/started` notifications and no `_sah/sessions/snapshot` request.
- **ACPA-12 Session list metadata**: removed. The graph gives the tags, the kind and the state.
- **ACPC-5 Session directory model**: removed. The client model is over the `sessions` endpoint (APP-16).

## 15. Changes to the Testudo design

These are differences between the design documents and this plan. The plan does not edit those documents. A person must decide each item.

1. **Done (D72). ROUTER-1 said the sidecar has no `cwd`.** The code has `workingDirectory` in the sidecar (`SessionSidecar.swift:86`). The sidecar is write-once (`:225-235`), so tags, the title and the agent id need a separate mutable file.
2. **Done (D72). ROUTER-3 named `Router.sessions(matching:) -> [SessionSummary]`.** This plan puts the API on a `SessionDirectory` protocol in Extras, implemented by a Router actor. A method on the `Router` actor alone cannot be used by Multitool.
3. **Category 15, Addressing, says "the Router finds the newest root session in that folder, or the server starts a new root session there".** With D61, a folder does not name an agent. This plan adds the agent address and refuses a folder address with no live session. The start needs the `SessionLauncher` port of the host (ROUTER-8, ACPA-9).
4. **MT-2 lists `list`, `start`, `send`, `reply`, `inbox` and `status`.** This plan uses the op strings of section 8.1, adds `tag session` and `untag session`, and gives `start session` an agent and an optional folder. MT-2 must also say that the tool is in the Multitool registry, so MT-1 sees it.
5. **MT-2 needs MT-9.** The library target does not link `Operations` today, and `Read.swift:3-8` says the package has no operation machinery.
6. **D61 (f) says "the `sessions` tool `find agents` operation".** Card `^jcnw05g` puts `find agents` in the `agents` tool. This plan follows the card (section 5.8). D61 (f) must name the `agents` tool.
7. **D60 and APP-10 say "the parent is the coordinator session" for a root task session.** The kinds table of category 15 says a root session has `agentSpawn == nil`. This plan uses a new fact, `startedBy`. D60, APP-10 and the kinds table must use `startedBy`.
8. **Rule 4 of "Rules for agents that work together" names the session "that started the work".** This plan defines the chain: `startedBy` first, then `parentID`.
9. **The glossary says a subagent "is not a session".** Category 15 (kinds table) and ACPA-4 treat a subagent as a session. This plan follows category 15 and ACPA-4.
10. **Done (D67).** Category 17 and APP-16 now name the GraphQL tunnel with the endpoint `sessions`, and the session context is in that endpoint.
11. **EXTRAS-2 has no caller context.** The `sessions` endpoint needs the viewer (EXTRAS-5). KANBAN-5 must accept the new parameter.
12. **`session/resume` must attach a live session (ACPA-11).** The design does not say this today.
13. **Q5 is answered.** The agents that an agent can find are the agent catalog of FoundationModelsAgents (AG-4, card `^jcnw05g`).
14. **Done (D72).** The design has no cap on the sessions and subagents that work at the same time. ROUTER-5, category 15, category 09 and the glossary keep only the loop guards. AG-7 removes the subagent cap of FoundationModelsAgents. Q31 is closed. ROUTER-8 to ROUTER-11 and EXTRAS-3 to EXTRAS-5 are in the design.
15. **Done (D74).** `SessionsGraph` is in the Multitool library target (MT-10), not in Router (ROUTER-10 is removed). The GraphQL toolkit is in Extras (EXTRAS-6), and the pins are only in Extras.
16. **Done (D75).** The `sessions` tool stays an op tool and gives `SessionsGraph` through `GraphQLEndpointTool` (EXTRAS-7). The app gets the endpoint from the tool. Q35 is answered.

## 16. Open questions

- **Q-S1. Answered.** UIs use the `sessions` GraphQL endpoint through the `_sah/graphql/*` tunnel (section 11).
- **Q-S2. The tab rule.** Does each `start session` of a model open a tab? A coordinator can start many sessions. Proposal: `openInTab` is true for the first 3 starts of one turn, and false after that. The app can also have a setting.
- **Q-S3. Answered (D72).** `read inbox` marks the messages read, and a read message never starts a turn. Only unread messages start a turn when the current turn ends (section 10.2).
- **Q-S4. Answered (D72).** A message to a recorded session that is not live restores it through the launcher, and the message starts a turn. A message to an archived session gives `refused` with the reason "archived" (section 10.2).
- **Q-S5. Answered (D72).** The tool has `archive session`, and the graph has the `archive` mutation. Both archive any session that the caller can see. Only a deny rule can stop it (ROUTER-11).
- **Q-S6. Answered (D72).** `SessionIndex` and `ProjectRegistry` move into Router, and the `RecordedSessionCatalog` port goes away (ROUTER-3, ACPA-14).
- **Q-S7. Answered (D72).** There is no limit on the number of sessions or subagents that work at the same time. Only the loop guards stay (section 10.3). This also answers Q31.
- **Q-S8. Trust of an external client.** Is the visibility of section 11.3 correct for an `external` client? Can it see sessions that the user started on the Mac?
- **Q-S9. `find agents` when the `agents` tool is off.** A session whose configuration turns off the `agents` tool cannot find agents. Must `start session` then accept only `default` and the ids in its `AGENT.md`, or must the launcher accept any id of the catalog?
- **Q35 (design). Answered (D75).** The `sessions` tool stays an op tool (MT-2). It also gives `SessionsGraph` through `GraphQLEndpointTool` (EXTRAS-7). The tool and the graph are two front ends over one port, and they share the rules in Multitool.
- **Q-S10. Answered (D76).** `SessionsTool` is its own public struct that holds an `OperationTool<SessionsToolContext>` and conforms to `GraphQLEndpointTool`. `OperationTool` does not change.
- **Q12 (existing).** Is a `session/update` with `_meta` the correct way to show a message from another session in the transcript? ACPA-6 here assumes yes.
