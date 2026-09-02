---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m1h6s8qzgddx61b195p2dff4
  text: |-
    ### implement — research
    - `FileWalker.canonicalDirectory(_:)` (FileWalker.swift:183) gives `URL(fileURLWithPath:isDirectory: true)`. The decode of `root` must use the same initializer, and the encode must write `root.path`.
    - `EditOutcomeProjection.encodedText(_:)` (EditOutcomeProjection.swift:369) already encodes one `Encodable` value with `.sortedKeys` and never throws. `encodedOperationEventDetail()` calls it. No second encoder.
    - The envelope is a `[String: FileChangeSet]` with the one key `operationEventDetailKey`. A decode of `{}` gives an empty dictionary, so `nil`. A decode of `{"fileChanges": 1}` fails, so `nil`. Plain text is not JSON, so `nil`.
    - `SandboxSurfaceTests.swift` is the model for a test file with a plain `import FoundationModelsMultitool`.
    - `FileChangeSetTests.swift` uses `@testable import`, so its new tests can call `FileWalker.canonicalDirectory(_:)` directly.
    - The callers of `FileChange.init` (Write.swift, Edit.swift, Patch.swift) and of `FileChangeSet.init` (FileChangeJournal.swift) keep the same argument labels. No caller changes.
  timestamp: 2026-09-02T14:01:21.919257+00:00
- actor: claude-code
  id: 01m1h77kerjgh2txm5srnd1671
  text: |-
    ### implement — discovery: the local dependency pins were stale
    - The first `swift build --build-tests` failed in `Sources/FoundationModelsMultitool/Discovery/SearchToolsTool.swift:293`, a file this task does not touch. The local `Package.resolved` (gitignored) pinned `FoundationModelsRanker` at 18f8a80 (2026-07-17) and `FoundationModelsMetadataRegistry` at 576d84f (2026-07-18). Commit cdeed67 (2026-08-30) of this package takes the Ranker API of 5ab7b1a (2026-08-30). The SwiftPM mirror under `.build/repositories` was also stale, so a `git fetch` inside the checkout showed the old head.
    - Fix: `swift package update FoundationModelsRanker FoundationModelsMetadataRegistry`. The pins are now Ranker 5ab7b1a and MetadataRegistry 9e196cd, the heads of `main`. No file of this repository changed for this. The next agent with the same failure runs the same command.
    - `swift build` prints one warning, `missing creator for mutated node: (.../mlx-swift_Cmlx.bundle/Contents/MacOS)`. It comes from the build system, not from a source file of this package, and it is present with or without this change.
  timestamp: 2026-09-02T14:09:11.640072+00:00
- actor: claude-code
  id: 01m1h77r1g486ses81kfwckwh6
  text: |-
    ### implement — changed
    - evidence: 5 files — Sources/FoundationModelsMultitool/Capabilities/Files/FileChangeSet.swift (public `FileChangeKind`, `FileChange`, `FileChangeSet`; `Codable`; `operationEventDetailKey`, `encodedOperationEventDetail()`, `init?(operationEventDetail:)`; header comment), Sources/FoundationModelsMultitool/Capabilities/Files/FileChangeJournal.swift (header comment), Sources/FoundationModelsMultitool/Capabilities/Files/EditOutcomeProjection.swift (doc comment of `encodedText(_:)`, which the envelope reuses), Tests/FoundationModelsMultitoolTests/FileChangeSetTests.swift (three envelope tests and two helpers), Tests/FoundationModelsMultitoolTests/FileChangeSetPublicSurfaceTests.swift (new, plain `import`). TDD: the tests were written first and failed to compile; then the implementation made `swift test --filter FileChangeSet` pass — 30 tests in 3 suites.
    - next: `/test`, then `/commit`, then `/review`.
  timestamp: 2026-09-02T14:09:16.336276+00:00
position_column: doing
position_ordinal: '80'
title: Make FileChange, FileChangeKind and FileChangeSet public and Codable
---
## What
Ask 4, part 1 (UPSTREAM_ASKS.md). The host (FoundationModelsACPAgent) must read the file-change record as values. Today the three types are internal.

Change `Sources/FoundationModelsMultitool/Capabilities/Files/FileChangeSet.swift`:
- Make `FileChangeKind`, `FileChange` and `FileChangeSet` `public`. Make each stored property and the `FileChange.init` public. Add a public `FileChangeSet.init(root:changes:)`.
- Add `Codable` to the three types. `FileChangeKind` is a `String` raw-value enum, so its conformance is synthesized. `FileChangeSet` needs a custom `Codable`: encode `root` as an absolute path string (key `root`), `changes` (key `changes`), and the rendered `patch` (key `patch`). On decode, read `root` and `changes` and ignore `patch` (it is a computed property).
- **The root round trip must keep `Equatable`.** `FileChangeJournal.root` comes from `FileWalker.canonicalDirectory(_:)`, which gives `URL(fileURLWithPath:isDirectory: true)`, a URL with a trailing separator. Decode `root` with `URL(fileURLWithPath: path, isDirectory: true)`, and encode it with `root.path` (no trailing separator). A decode with the two-argument `URL(fileURLWithPath:)` gives a different URL string and breaks `==`.
- Add the envelope the host reads off an `OperationEvent.detail`:
  - `public static let operationEventDetailKey = "fileChanges"` on `FileChangeSet`.
  - `public func encodedOperationEventDetail() -> String`: JSON text of the object `{"fileChanges": <encoded FileChangeSet>}`. Use `JSONEncoder` with `.sortedKeys` so the text is stable.
  - `public init?(operationEventDetail: String)`: decodes that envelope. Returns `nil` for text that is not this envelope (a plain `notify()` detail, for example). Never throws.
- Update the header comment of `FileChangeSet.swift` and of `FileChangeJournal.swift`: the sentence "this package keeps them internal" is no longer true.

Do not make `FileChangeJournal` or `FileContext` public. The host reads the change set off the event (task "Post each mutating file verb's change set through the ambient ToolContext"), not the journal.

## Acceptance Criteria
- [ ] A file outside the module (a test file without `@testable`) can name `FileChangeKind`, `FileChange`, `FileChangeSet` and build a `FileChange` and a `FileChangeSet`.
- [ ] `FileChangeSet.encodedOperationEventDetail()` gives JSON with one top-level key `fileChanges`, and `FileChangeSet(operationEventDetail:)` on that text gives back an equal `FileChangeSet` (same root, same changes), for a root made by `FileWalker.canonicalDirectory(_:)`.
- [ ] `FileChangeSet(operationEventDetail: "starting the sweep")`, `FileChangeSet(operationEventDetail: "{}")` and `FileChangeSet(operationEventDetail: "{\"fileChanges\": 1}")` give `nil`.
- [ ] The encoded text carries the `patch` text, and a decode ignores it.
- [ ] `swift build` gives no new warning.

## Tests
- [ ] Add to `Tests/FoundationModelsMultitoolTests/FileChangeSetTests.swift`: `encodedOperationEventDetailRoundTrips` (a set with an add, a modify and a move, root from `FileWalker.canonicalDirectory(_:)`; encode, decode, compare with `==`), `operationEventDetailRejectsForeignText` (the three foreign texts give `nil`), `encodedOperationEventDetailCarriesThePatch` (the decoded JSON object has a `patch` string equal to `set.patch`).
- [ ] Add one test file that does NOT use `@testable import` (`Tests/FoundationModelsMultitoolTests/FileChangeSetPublicSurfaceTests.swift` with a plain `import FoundationModelsMultitool`) and that builds a `FileChange` and a `FileChangeSet`. This proves the public surface at compile time.
- [ ] Run `swift test --filter FileChangeSet` and expect every test to pass.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass. #upstream-asks #ask-4