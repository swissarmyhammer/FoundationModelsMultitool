---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m7qnzw7zgb7mhbhvb7xms0j6
  text: |-
    ### duplicate — archived
    - evidence: ^gxqmxj6 (01M7QGNV7DHJRV9A20TGXQMXJ6) did this work and is done: commits dc1ab0c8 and a79f7fa9 on origin/main. `sendMessage` reports the alias rewrite in `extensions.rewrites` through Extras `ResolverRewrites` (92660bf3).
    - cause: the orchestrator did not find this task file at 14:20 and made ^gxqmxj6 for the same work.
  timestamp: 2026-11-18T15:56:44.671691+00:00
depends_on:
- 01M7NQMS04V5B1WKXMY6XZNEGM
position_column: todo
position_ordinal: '8980'
title: Report the alias rewrite of sendMessage in extensions.rewrites (D199 (e), D86)
---
Found by ^6xznegm. The one address reader (`SessionsVisibility.messageAddress(_:from:)`, `Capabilities/Sessions/SessionsAddressReader.swift`) gives `SessionsAddressReading.rewrite` for the aliases `@agent:/path` and a folder path alone. The `send message` operation of the tool shows the report. `Mutation.sendMessage` cannot show it: `extensions.rewrites` belongs to the GraphQL toolkit of FoundationModelsExtras.

## Evidence

- `GraphQLResponse.init(result:rewrites:warnings:extensions:)` takes `rewrites` only from `RewrittenDocument.rewrites`, the name rewrite of the document (`GraphQLRun.swift`, `respond`).
- `GraphQLResponse` removes a `rewrites` key from `GraphQLRunContext.responseExtensions()`, because the toolkit owns that key.
- `API.result(of:operationName:context:)` is private, so an endpoint cannot build the response itself.

## Precondition (blocked-external)

FoundationModelsExtras gives a way for a resolver to add one `NameRewrite` to the response, for example a `ResponseRewrites` collector on `GraphQLRunContext`, the same as `ResponseWarnings`, whose items `respond` appends after `rewritten.rewrites`. Send this text to the Extras session. Do not start until origin/main of ../FoundationModelsExtras has it.

## Work

- [ ] `SessionsGraphContext` holds the collector. `sendMessage` adds `NameRewrite(from: <alias>, to: "@<name>" or the folder, path: ["sendMessage", "input", "to"])` when `reading.rewrite` is not nil.
- [ ] Remove the TODO in `SessionsGraphResolver.sendMessage`.

## Tests

- [ ] Graph: `sendMessage(input: {to: "@travel:~/trips", ...})` gives the rewrite in `extensions.rewrites`.
- [ ] Graph: `sendMessage` to a folder path gives the rewrite in `extensions.rewrites`. #sessions #at-sessions #graphql