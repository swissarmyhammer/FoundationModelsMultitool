---
assignees:
- claude-code
depends_on:
- 01M48V90Q7SZFS78K85W0YEYA3
- 01M48V8EHPNDZGYRJEJBCK92PN
- 01M48V9SN2MNFZGXZ9R6DGD0H1
- 01M48VAGF2ZD5J4G0FNP9B4CM5
position_column: todo
position_ordinal: 8c80
title: 'git: tools.git.diff with three modes over the semantic engine'
---
## Goal

Port the `get diff` operation of the sah MCP tool `git` (git.md, "Layer 1", item 2) as the `tools.git.diff` verb, over the semantic engine.

## Source

`../swissarmyhammer/crates/swissarmyhammer-tools/src/mcp/tools/git/diff/mod.rs`: `language_to_extension` (line 33), `parse_file_ref` (74), `DiffResponse` / `ChangeEntry` (88-157), `execute_inline_diff` (211), `execute_file_diff` (286), `execute_auto_diff`, and the tests of that file. Dispatch: `changes/mod.rs` `execute_diff` (148-213).

## Work

1. `Diff` verb (`name = "diff"`). Arguments: `left: String?`, `right: String?`, `leftText: String?`, `rightText: String?`, `language: String?`.
2. Three modes, the same as the source:
   - Inline: `leftText` and `rightText` and `language`. A missing part is a `correction` that names the missing argument.
   - File: `left` and `right`, each a path or `path@ref`. Read a ref side with the blob reader of `tools.git.show`. Read a side with no ref from the working tree through the `PathGuard`.
   - Automatic: no argument. Diff each dirty or staged file (reuse the status code) against `HEAD`.
3. Result: `summary` (`files`, `added`, `modified`, `deleted`, `moved`, `renamed`), `changes` (each: `changeType`, `entityType`, `entityName`, `filePath`, `oldFilePath?`, `structuralChange?`, `entityId`, `beforeContent?`, `afterContent?`), `correction: String?`. Keep the field order of the source (what changed, where, how, then the content).
4. Keep a size cap on `beforeContent` and `afterContent` for the model, and report when the cap cut a field. Decide the cap with the result renderer (`Rendering/ResultRenderer.swift`).
5. Port `parse_file_ref` exactly (the last `@`, and `@` at position 0 is not a ref).
6. Add the verb to `GitCapability.tools`.

## Tests

- Port the tests of `diff/mod.rs` that apply.
- Inline mode with a missing argument, an unknown language (fallback).
- File mode: `a.swift@HEAD~1` against `a.swift`; a path outside the root; an unknown ref.
- Automatic mode: a clean tree (empty result), one staged and one unstaged file.

## Acceptance

- `swift build` and `swift test` pass with no new warnings. #git