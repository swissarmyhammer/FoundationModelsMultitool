---
assignees:
- claude-code
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