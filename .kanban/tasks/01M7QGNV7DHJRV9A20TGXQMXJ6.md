---
assignees:
- claude-code
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