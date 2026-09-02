# Upstream asks — FoundationModelsMultitool

Requests from FoundationModelsACPAgent. Each ask names its motivation, its source task on the ACPAgent board, and the file:line evidence at the pinned Multitool revision e8c91a6. The numbering continues the shared list in `../FoundationModelsRouter/UPSTREAM_ASKS.md` (Asks 1-3 and 5 are Router-owned).

## Ask 4 — make the per-call file-change record public and drain it at the end of each call

From: FoundationModelsACPAgent, task ^9jfmhh0.

The structured record of touched file paths exists but is trapped:

- The mutating file verbs record one `FileChange` per touched file into `FileChangeJournal` (Sources/FoundationModelsMultitool/Capabilities/Files/FileChangeJournal.swift:96-99).
- The journal is internal (FileChangeJournal.swift:35), and `drain()` (:107) has no caller in the package.
- `FileChange` and `FileChangeSet` are internal (Capabilities/Files/FileChangeSet.swift:66, :118).
- `FilesCapability` exposes only `noun`, `tools`, and `init` publicly (Capabilities/Files/FilesCapability.swift:56-94), and `FileContext.changes` is internal (FileContext.swift:57).

Please: (1) make `FileChange`/`FileChangeSet` public; (2) drain the journal at the end of each tool call and hand the set to the host — as a structured field beside the run's terminal `OperationEvent`, or through a public callback on `withFiles`. A confirmed fix shape from the survey: drain the journal at the end of `MultiTool.call` through the captured `RunBinding`, and post the encoded `FileChangeSet` on an `OperationEvent` — `OperationEvent.detail` is the public tool-owned JSON slot, and `SandboxNoticeOutbox.swift:35` is a working precedent for posting an event from inside Multitool.

Motivation: the ACP agent must fill `tool_call_update.locations` (its plan.md §11.5/§11.6, §20.1 proof 3). Today no live event carries the touched paths, and the model-facing rendered string is not a permitted source. The Router-side half of this ask (carry the record on the live event surface) is in the Router file.

## Ask 6 — a default working directory for the shell composition

From: FoundationModelsACPAgent, task ^fzx2r16.

A `tools.shell.execute` call that omits `workingDirectory` runs in the agent PROCESS current directory, which the sandbox refuses in band — so each plain command without an explicit `workingDirectory` fails. The cause at revision e8c91a6:

- `MultiTool.Builder.withShell(storeDirectory:sandbox:outputChunkStream:)` is the only overload; it has no working-directory parameter (Surface/MultiToolBuilder.swift:235-239). `ShellCapability.init` is the same (Capabilities/Shell/ShellCapability.swift:99).
- The execute verb and its arguments are internal (Capabilities/Shell/Execute.swift:75, :772); `workingDirectory: String?` passes through with no change (:93, :244).
- `ShellRunner` is internal (Capabilities/Shell/ShellRunner.swift:71); the fallback is `request.workingDirectory ?? FileManager.default.currentDirectoryPath` (:485), and the spawned `Configuration` gets `nil` (:458), so the child inherits the process directory.
- `SeatbeltSandbox.Options` shapes the write grant only (Capabilities/Shell/SeatbeltSandbox.swift:146). `CommandSandbox.wrap` cannot set the run directory (Capabilities/Shell/CommandSandbox.swift:113; ShellRunner.swift:447-458).

Please supply a default working directory for the shell composition — for example a `defaultWorkingDirectory` parameter on `withShell` and `ShellCapability.init`, or a field on a public shell options struct — so a run that omits `workingDirectory` lands in that default instead of the process directory.

Motivation: the agent process's current directory has no relation to the session working directory. A model that follows the verb description ("Omit it to run in the current directory") gets a refused run on every plain command. The session root is the only sensible default.
