---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m48x8ndetjm5jt3m6pj9ys3q
  text: |-
    ### open question before work starts
    - JavaScript links only at 0.23.1 and Python only at 0.23.6 (the newest tags do not compile the scanner when used as a dependency). The Rust crate uses 0.25 for both. See git.md "Open questions after the spike".
    - A person must decide whether the older versions are acceptable before this task starts. If no decision is recorded here when the task starts, add the tag `stuck` and stop.
    - Vue needs no tree-sitter grammar: `vue.rs` splits the blocks itself (git.md decision 11).
  timestamp: 2026-10-06T15:28:10.670990+00:00
depends_on:
- 01M48V9SN2MNFZGXZ9R6DGD0H1
position_column: todo
position_ordinal: '8880'
title: 'git semantic: TypeScript, TSX, JavaScript, JSX, Python, and Vue'
---
## Goal

Add the second group of languages to the code plugin (git.md decision 7).

## Source

- `../swissarmyhammer/crates/swissarmyhammer-sem/src/parser/plugins/code/languages.rs`: the entries for TypeScript, TSX, JavaScript, JSX, and Python.
- `../swissarmyhammer/crates/swissarmyhammer-sem/src/parser/plugins/vue.rs`: the Vue plugin. It uses the script block of a `.vue` file; check how it calls the TypeScript and JavaScript extraction.

## Work

1. Add the grammar packages to `Package.swift` (the spike recorded the URLs). Write a doc comment for each dependency.
2. Add a language table entry for each language. Register the extensions (`.ts`, `.tsx`, `.js`, `.jsx`, `.mjs`, `.cjs`, `.py`, and the others that `languages.rs` lists).
3. Port `vue.rs` and register it for `.vue`.

## Golden tests

Make fixtures with the sah tool `git` op `get diff` (inline mode), in the same form as the task for Swift, Rust, and Go. Cover for each language: a function added, deleted, modified, renamed, moved; a class with methods; for TS, an interface and a type alias; for Python, a decorated function and a nested function. For Vue: a change in the script block and a change in the template only.

## Acceptance

- `swift build` and `swift test` pass with no new warnings.
- Each golden of the group passes. #git