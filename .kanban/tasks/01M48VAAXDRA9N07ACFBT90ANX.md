---
assignees:
- claude-code
depends_on:
- 01M48V9SN2MNFZGXZ9R6DGD0H1
position_column: todo
position_ordinal: 8a80
title: 'git semantic: Fortran, Elixir, and Bash'
---
## Goal

Add the last group of languages to the code plugin (git.md decision 7). These grammars are the most likely to have no SwiftPM package; read the result of the spike first.

## Source

`../swissarmyhammer/crates/swissarmyhammer-sem/src/parser/plugins/code/languages.rs`: the entries for Fortran, Elixir, and Bash.

## Work

1. Add the grammar packages to `Package.swift` (the spike recorded the URLs). Write a doc comment for each dependency.
2. Add a language table entry for each language. Register each extension that `languages.rs` lists (for example `.f90`, `.f`, `.ex`, `.exs`, `.sh`, `.bash`).
3. If the spike recorded a grammar as a GAP and the user has not yet decided how to close it, do not guess: add the tag `stuck` to this task and stop.

## Golden tests

Make fixtures with the sah tool `git` op `get diff` (inline mode), in the same form as the task for Swift, Rust, and Go. Cover for each language: a function added, deleted, modified, renamed, moved; for Fortran, a module and a subroutine; for Elixir, a module with `def` and `defp`.

## Acceptance

- `swift build` and `swift test` pass with no new warnings.
- Each golden of the group passes. #git