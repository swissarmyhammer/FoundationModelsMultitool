---
assignees:
- claude-code
depends_on:
- 01M48V9SN2MNFZGXZ9R6DGD0H1
position_column: todo
position_ordinal: '8980'
title: 'git semantic: Java, C, C++, C#, Ruby, and PHP'
---
## Goal

Add the third group of languages to the code plugin (git.md decision 7).

## Source

`../swissarmyhammer/crates/swissarmyhammer-sem/src/parser/plugins/code/languages.rs`: the entries for Java, C, C++, C#, Ruby, and PHP.

## Work

1. Add the grammar packages to `Package.swift` (the spike recorded the URLs). Write a doc comment for each dependency.
2. Add a language table entry for each language. Register each extension that `languages.rs` lists (for example `.java`, `.c`, `.h`, `.cpp`, `.cc`, `.hpp`, `.cs`, `.rb`, `.php`). Keep the same rule as the source for `.h` (C or C++).

## Golden tests

Make fixtures with the sah tool `git` op `get diff` (inline mode), in the same form as the task for Swift, Rust, and Go. Cover for each language: a function or method added, deleted, modified, renamed, moved; a class (or struct) with methods; for C++, a namespace; for C#, a property.

## Acceptance

- `swift build` and `swift test` pass with no new warnings.
- Each golden of the group passes. #git