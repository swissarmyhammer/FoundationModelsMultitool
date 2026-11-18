---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m7qgr53y73fjeexxbcgybbma
  text: 'Extras shape (from foundationmodelsextras-9e, 2026-11-18, Extras task ^ehms1m8): no change to the `GraphQLRunContext` protocol. Use `ResolverRewrites`, the same pattern as `ResolverWarnings`: `public final class ResolverRewrites: Sendable` with `@TaskLocal public static var current: ResolverRewrites?`. `API.respond` binds a new collector for the run. The resolver calls `ResolverRewrites.current?.add(NameRewrite(from: "@agent:/path", to: "@agent", path: ["sendMessage", "input", "to"]))`. The response gives the name rewrites first, then the resolver rewrites in the order of the adds, with no repeats. A subscription keeps only the name rewrites. Put the lookup folder in the `to` text, the same text as the tool answer. Start when the Extras sha is on origin/main.'
  timestamp: 2026-11-18T14:25:08.734770+00:00
- actor: claude-code
  id: 01m7qhtvagde9zw8q038ss870y
  text: 'Extras landed (2026-11-18): ^ehms1m8 `ResolverRewrites` is on Extras origin/main 92660bf34155cd9e5dc46658428318bb8f56b4cc. Run `swift package update FoundationModelsExtras` first. Use `ResolverRewrites.current?.add(NameRewrite(from:to:path:))` from the resolver, sync or async. The rewrites are also in a response with GraphQL errors; a document that does not parse has no resolver rewrites; a subscription has only the name rewrites. `GraphQLRunContext` did not change. Change the assertion of the test `aSendToAnAliasGivesNoRewriteReportYet` (SessionsGraphMutationTests) to expect the rewrite, and rename it.'
  timestamp: 2026-11-18T14:44:05.584080+00:00
- actor: claude-code
  id: 01m7qkeh096w7m1nsjs6rf3307
  text: |-
    Implementation notes (2026-11-18):
    - `swift package update FoundationModelsExtras` moved the pin to 92660bf34155cd9e5dc46658428318bb8f56b4cc (Package.resolved, not tracked). The build needed no other sibling move.
    - `SessionsAddressReading.rewrite` is now a `SessionsAddressRewrite?` (alias, canonical, report) in place of a `String?`. The tool answer uses `rewrite?.report`. The text of the tool answer did not change.
    - `SessionsToolText.agentAliasCanonical(name:folder:)` and `folderAliasCanonical(folder:)` give the canonical form. `agentAliasRewrite` and `folderAliasRewrite` now use them, so the `to` text is the same text as the tool answer: `"@travel", with the lookup in /work/trips first` (with the quotes, as the tool sentence has them) and `the newest root session in /work/other`.
    - `sendMessage` adds `NameRewrite(from: <alias as written>, to: <canonical>, path: ["sendMessage", "input", "to"])` with `ResolverRewrites.current?.add` before the owner check, so a REFUSED receipt to an alias also reports the rewrite. The TODO is removed.
    - Other paths of the reader: the tag form (`#tag`), a full id, a short id and `@<slug>`/`@<name>` give `rewrite: nil`. They are not aliases, and the tool reports no rewrite for them. Thus they add no resolver rewrite. A test covers `@<slug>`.
    - Test `aSendToAnAliasGivesNoRewriteReportYet` is renamed to `aSendToAnAliasGivesARewriteReport`. It now expects the rewrite with from, to and path (new helper `GraphQLReply.rewrote(_:to:at:)`). New test `aSendToASlugGivesNoRewriteReport`.
    - The EXTRAS-11 conformance kit (`GraphQLEndpointConformance` in SessionsGraphQueryTests) is green in both runs. I did not tick that box because I did not write that test.
  timestamp: 2026-11-18T15:12:18.953216+00:00
- actor: claude-code
  id: 01m7qkekztd1zg0c61q8sq66gb
  text: |-
    ### implement — changed
    - evidence: 6 files — Sources/FoundationModelsMultitool/Capabilities/Sessions/{SessionsGraphMutations,SessionsAddressReader,SessionsToolText+Messages,SessionsToolMessageOperations}.swift, Tests/FoundationModelsMultitoolTests/{SessionsGraphMutationTests,Fixtures/GraphQLReply}.swift. Pin moved: FoundationModelsExtras -> 92660bf (no other sibling). RED: alias test failed 2/2 cases (no rewrite). `swift build` clean. `swift test --filter "SessionsGraph|SessionsTool"`: 198 tests in 10 suites passed. Full `swift test`: 3035 tests in 271 suites passed, exit 0.
    - next: /review
  timestamp: 2026-11-18T15:12:22.010411+00:00
- actor: claude-code
  id: 01m7qkk2caedhjnffcanefgvsp
  text: |-
    ### review — findings
    - evidence: review sha HEAD~1..HEAD (dc1ab0c8): 1 finding (1 confirmed, 2 refuted) — Tests/FoundationModelsMultitoolTests/Fixtures/GraphQLReply.swift:79
    - next: implement the open finding in the 2026-11-18 09:13 Review Findings section, then review again.
  timestamp: 2026-11-18T15:14:47.818362+00:00
- actor: claude-code
  id: 01m7qkkd45xwgj1wa7q262fhmw
  text: |-
    ### finish iteration 1 — findings
    - implement: changed — SessionsGraphMutations, SessionsAddressReader, SessionsToolText+Messages, SessionsToolMessageOperations, SessionsGraphMutationTests, Fixtures/GraphQLReply; local pin Extras 92660bf3
    - test: green — swift test, 3035 passed (run in the implement step)
    - commit: dc1ab0c8
    - review: findings — Tests/FoundationModelsMultitoolTests/Fixtures/GraphQLReply.swift:79
  timestamp: 2026-11-18T15:14:58.821129+00:00
- actor: claude-code
  id: 01m7qknys4zz1bydta45rv4jy3
  text: |-
    Finding fixed. `GraphQLReply.rewrote(_:to:at:)` is now one function with `at path: [String]? = nil`. The path clause applies only when `path` is not nil. The overload is deleted. The one call site in SessionsGraphMutationTests.swift that passes `at: Self.sendAddressPath` keeps the same text, because the merged signature takes the same labels. The other 20 call sites (in 6 test files) use the default `nil`. GraphQLReply.swift has no other near-copy of the loop: `list`, `object` and `isNull` read `data`, not `rewrites`.

    ### implement — changed
    - evidence: 1 file — Tests/FoundationModelsMultitoolTests/Fixtures/GraphQLReply.swift; `swift build --build-tests` complete, no source warnings; `swift test --filter "SessionsGraph"` 112 tests in 5 suites passed
    - next: review
  timestamp: 2026-11-18T15:16:22.436027+00:00
depends_on:
- 01M7NQMS04V5B1WKXMY6XZNEGM
position_column: doing
position_ordinal: '80'
title: sendMessage reports the alias rewrite of the address in extensions.rewrites (D199, D86)
---
Decision: D199 (e) and D86 in TestudoApp/features/decisions.md. Split from ^6xznegm, which does all the other work of the address reader.

Precondition (FoundationModelsExtras): a resolver must be able to add a rewrite report to `extensions.rewrites`. Today it cannot: `GraphQLResponse` takes `rewrites` only from `RewrittenDocument.rewrites` (the name rewrite of the document), it removes a `rewrites` key from `responseExtensions()`, and `API.result(of:...)` is private. Proposed Extras change: a `ResponseRewrites` collector on `GraphQLRunContext`, as `ResponseWarnings`, whose items `respond` appends to `rewritten.rewrites`. Before you start, examine origin/main of ../FoundationModelsExtras.

## Work

- In `SessionsGraphResolver.sendMessage` (see the `TODO` that names this task), add the rewrite report of the address reader to `extensions.rewrites`: `@agent:/path` becomes `@agent` with the lookup folder `/path`, and a folder path alone becomes the newest root session in that folder.
- The text of the report is the same as in the tool answer.
- Remove the `TODO`.

## Tests

- [x] `sendMessage(input: {to: "@agent:/path", ...})` gives a rewrite report in `extensions.rewrites`.
- [x] A folder path alone gives a rewrite report in `extensions.rewrites`.
- [x] A send with `@<slug>` gives no rewrite report.
- [ ] The test kit of the conventions (EXTRAS-11) stays green. #sessions #at-sessions #graphql

## Review Findings (2026-11-18 09:13)

> Scope: `review sha HEAD~1..HEAD` — reviewed the diffs only — lines this change added or modified. 6 file(s) reviewed, 2 not reviewed.

> 2 file(s) not reviewed — excluded by an ignore rule:
> - `.kanban/ (from .reviewignore)` — 2 file(s)

- [x] `Tests/FoundationModelsMultitoolTests/Fixtures/GraphQLReply.swift:79` `reuse/reuse` — The new overload `rewrote(_:to:at:)` repeats the body of the existing `rewrote(_:to:)` at line 67 and adds only one clause for the path. The near-match was not generalized, so the same loop over `rewrites` now exists twice and the two can diverge. Extend the existing `rewrote(_:to:)` with an optional parameter, `at path: [String]? = nil`, and add the path clause only when `path` is non-nil. Delete the new overload and update the call sites in SessionsGraphMutationTests.swift that pass `at: Self.sendAddressPath`.
