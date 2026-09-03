# Upstream asks — FoundationModelsMultitool

Requests from FoundationModelsACPAgent. Each ask names its motivation, its source task on the ACPAgent board, and the file:line evidence at the pinned Multitool revision e8c91a6. The numbering continues the shared list in `../FoundationModelsRouter/UPSTREAM_ASKS.md` (Asks 1-3 and 5 are Router-owned).

## Ask 4 (answered) — make the per-call file-change record public and drain it at the end of each call

From: FoundationModelsACPAgent, task ^9jfmhh0.

The structured record of touched file paths exists but is trapped:

- The mutating file verbs record one `FileChange` per touched file into `FileChangeJournal` (Sources/FoundationModelsMultitool/Capabilities/Files/FileChangeJournal.swift:96-99).
- The journal is internal (FileChangeJournal.swift:35), and `drain()` (:107) has no caller in the package.
- `FileChange` and `FileChangeSet` are internal (Capabilities/Files/FileChangeSet.swift:66, :118).
- `FilesCapability` exposes only `noun`, `tools`, and `init` publicly (Capabilities/Files/FilesCapability.swift:56-94), and `FileContext.changes` is internal (FileContext.swift:57).

Please: (1) make `FileChange`/`FileChangeSet` public; (2) drain the journal at the end of each tool call and hand the set to the host — as a structured field beside the run's terminal `OperationEvent`, or through a public callback on `withFiles`. A confirmed fix shape from the survey: drain the journal at the end of `MultiTool.call` through the captured `RunBinding`, and post the encoded `FileChangeSet` on an `OperationEvent` — `OperationEvent.detail` is the public tool-owned JSON slot, and `SandboxNoticeOutbox.swift:35` is a working precedent for posting an event from inside Multitool.

Motivation: the ACP agent must fill `tool_call_update.locations` (its plan.md §11.5/§11.6, §20.1 proof 3). At revision e8c91a6 no live event carried the touched paths, and the model-facing rendered string is not a permitted source. The Router-side half of this ask (carry the record on the live event surface) is in the Router file.

**Answer:** Both halves are complete.

Part (1). Multitool commit 9ec33f6 makes `FileChange`, `FileChangeKind` and `FileChangeSet` public and `Codable`, in `Sources/FoundationModelsMultitool/Capabilities/Files/FileChangeSet.swift`. `FileChangeJournal` and `FileContext.changes` stay internal. A host reads the record as values, and never reads the journal.

Part (2). The change set goes to the host one time for each mutating verb call. The ask named a drain at the end of the `runCode` call through the captured `RunBinding`. That is not the shape that landed; see the reason below. Two carriers leave from `FileChangeJournal.commit(_:through:)`, and both carry the same `fileChanges` envelope text:

- Multitool commit 021f973 posts a `.progress` `OperationEvent` whose `detail` is the envelope. The session records this event, so this carrier is the durable half.
- Multitool commit f98a76f (task ^n313gma) attaches the same envelope as a `ToolCallAttachment` through the Router's `ToolContext.attach(_:)`. The attachment reaches a host live as `SessionEvent.toolCallReport`, under the run's own correlation id, so this carrier is the live half. It also satisfies the "Known limit" on the Router half of this ask.

A host reads the record by these public names:

- `FileChangeSet` — the record. It holds `root`, `changes`, and the rendered `patch`.
- `FileChangeSet.operationEventDetailKey` — the value `fileChanges`. It is the one top-level key of the envelope, and it is also the `schemaName` of the attachment. One name answers both carriers, so a host matches on it and not on a literal of its own.
- `FileChangeSet.encodedOperationEventDetail()` — the JSON text of the envelope.
- `FileChangeSet.init(operationEventDetail:)` — reads the set back from either carrier. It gives `nil` for text that is not the envelope, and it does not throw, so a host can try each `detail` it receives.
- `recordsChanges` on `FilesCapability.init(root:additionalRoots:readOnly:allowSymlinks:recordsChanges:)` and on `MultiTool.Builder.withFiles(root:additionalRoots:readOnly:allowSymlinks:recordsChanges:)`. Recording is opt in. Give `true` to get the change sets. The default, `false`, records nothing, because the capture of the old text costs each write verb one more read.

Why each verb delivers its own changes, and why no drain at the end of `runCode` does: `FilesCapability.init` makes one `FileContext`, and thus one journal, for the whole registry. `MultiToolConfiguration.liveContextLimit` lets several `runCode` calls run at the same time over that registry. A drain at the end of call A would take the changes that call B recorded, and post them under A's correlation id. So each verb posts through the `ToolContext` that the engine bound around its own inner call, and `ToolContext.post(_:)` re-stamps that event with the outer `runCode` run's `tool`, `op` and `completionToken`. The head comment of `FileChangeJournal.swift` carries this reasoning.

The suites `FileChangeSetTests`, `FileChangeSetPublicSurfaceTests`, `FileChangeEventTests`, `FileChangeAttachmentTests`, `FileChangeEventAbsenceTests` and `FileChangeRunCodeTests` in `Tests/FoundationModelsMultitoolTests` show this.

Known limit: a change is delivered or kept, never both. `drain()` keeps only the changes of a verb call that had no ambient `ToolContext` — a verb on a bare `LanguageModelSession`, or a direct call in a test. The journal stays internal, so a host cannot call `drain()`. A host under a session reads each change set from one of the two carriers.

## Ask 6 — a default working directory for the shell composition

From: FoundationModelsACPAgent, task ^fzx2r16.

A `tools.shell.execute` call that omits `workingDirectory` runs in the agent PROCESS current directory, which the sandbox refuses in band — so each plain command without an explicit `workingDirectory` fails. The cause at revision e8c91a6:

- `MultiTool.Builder.withShell(storeDirectory:sandbox:outputChunkStream:)` is the only overload; it has no working-directory parameter (Surface/MultiToolBuilder.swift:235-239). `ShellCapability.init` is the same (Capabilities/Shell/ShellCapability.swift:99).
- The execute verb and its arguments are internal (Capabilities/Shell/Execute.swift:75, :772); `workingDirectory: String?` passes through with no change (:93, :244).
- `ShellRunner` is internal (Capabilities/Shell/ShellRunner.swift:71); the fallback is `request.workingDirectory ?? FileManager.default.currentDirectoryPath` (:485), and the spawned `Configuration` gets `nil` (:458), so the child inherits the process directory.
- `SeatbeltSandbox.Options` shapes the write grant only (Capabilities/Shell/SeatbeltSandbox.swift:146). `CommandSandbox.wrap` cannot set the run directory (Capabilities/Shell/CommandSandbox.swift:113; ShellRunner.swift:447-458).

Please supply a default working directory for the shell composition — for example a `defaultWorkingDirectory` parameter on `withShell` and `ShellCapability.init`, or a field on a public shell options struct — so a run that omits `workingDirectory` lands in that default instead of the process directory.

Motivation: the agent process's current directory has no relation to the session working directory. A model that follows the verb description ("Omit it to run in the current directory") gets a refused run on every plain command. The session root is the only sensible default.
