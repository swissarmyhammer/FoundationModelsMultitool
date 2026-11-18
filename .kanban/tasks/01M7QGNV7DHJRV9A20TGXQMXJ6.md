---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m7qgr53y73fjeexxbcgybbma
  text: 'Extras shape (from foundationmodelsextras-9e, 2026-11-18, Extras task ^ehms1m8): no change to the `GraphQLRunContext` protocol. Use `ResolverRewrites`, the same pattern as `ResolverWarnings`: `public final class ResolverRewrites: Sendable` with `@TaskLocal public static var current: ResolverRewrites?`. `API.respond` binds a new collector for the run. The resolver calls `ResolverRewrites.current?.add(NameRewrite(from: "@agent:/path", to: "@agent", path: ["sendMessage", "input", "to"]))`. The response gives the name rewrites first, then the resolver rewrites in the order of the adds, with no repeats. A subscription keeps only the name rewrites. Put the lookup folder in the `to` text, the same text as the tool answer. Start when the Extras sha is on origin/main.'
  timestamp: 2026-11-18T14:25:08.734770+00:00
depends_on:
- 01M7NQMS04V5B1WKXMY6XZNEGM
position_column: todo
position_ordinal: 8a80
title: sendMessage reports the alias rewrite of the address in extensions.rewrites (D199, D86)
---
Decision: D199 (e) and D86 in TestudoApp/features/decisions.md. Split from ^6xznegm, which does all the other work of the address reader.

Precondition (FoundationModelsExtras): a resolver must be able to add a rewrite report to `extensions.rewrites`. Today it cannot: `GraphQLResponse` takes `rewrites` only from `RewrittenDocument.rewrites` (the name rewrite of the document), it removes a `rewrites` key from `responseExtensions()`, and `API.result(of:...)` is private. Proposed Extras change: a `ResponseRewrites` collector on `GraphQLRunContext`, as `ResponseWarnings`, whose items `respond` appends to `rewritten.rewrites`. Before you start, examine origin/main of ../FoundationModelsExtras.

## Work

- In `SessionsGraphResolver.sendMessage` (see the `TODO` that names this task), add the rewrite report of the address reader to `extensions.rewrites`: `@agent:/path` becomes `@agent` with the lookup folder `/path`, and a folder path alone becomes the newest root session in that folder.
- The text of the report is the same as in the tool answer.
- Remove the `TODO`.

## Tests

- [ ] `sendMessage(input: {to: "@agent:/path", ...})` gives a rewrite report in `extensions.rewrites`.
- [ ] A folder path alone gives a rewrite report in `extensions.rewrites`.
- [ ] A send with `@<slug>` gives no rewrite report.
- [ ] The test kit of the conventions (EXTRAS-11) stays green. #sessions #at-sessions #graphql #blocked-external