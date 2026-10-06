---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m49hba7nmc0t4x9x0aktwjej
  text: |-
    Research done.
    - `languages.rs` entries: FORTRAN (.f90, .f95, .f03, .f08, .f, .for; entity kinds function, subroutine, module, program, interface, type_declaration; no container), ELIXIR (.ex, .exs; no entity kind; container do_block; call identifiers defmodule, def, defp, defmacro, defmacrop, defguard, defguardp, defprotocol, defimpl, defstruct, defexception, defdelegate), BASH (.sh only; function_definition). ALL_CONFIGS order: ..., php, fortran, swift, elixir, bash. Thus the Swift table order is go, rust, java, c, cpp, ruby, csharp, php, fortran, swift, elixir, bash.
    - The card names `.bash` as an example, but `languages.rs` lists only `.sh` for Bash. The card says "Register each extension that languages.rs lists", thus `.bash` is not registered (same as Rust).
    - Rust Cargo.lock grammar versions: tree-sitter-fortran 0.6.0, tree-sitter-elixir 0.3.5, tree-sitter-bash 0.25.1. These are equal to the git.md table, thus no workaround (decision 12) is necessary.
    - The port of ^6dgd0h1 already has the Elixir declaring-call reader and the `module`/`subroutine`/`function` kinds in the type table. Thus this task adds only table entries, grammars, and goldens.
    - An Elixir `def` is always in a `defmodule`, thus a change to a `def` modifies the module too (two `modified` changes, unstable order in Rust). The walk passes through a call that is not a declaring call, thus a `def` in a `quote do ... end` block that is not in a module has no parent. The Elixir `function-modified` and `whitespace-and-comments` cases use that form (`Module.create` with a quoted body), the same as the `record` form of Java and C#.
  timestamp: 2026-10-06T21:19:09.045206+00:00
- actor: claude-code
  id: 01m49j19avax1ej72sxftd6ca9
  text: |-
    Implementation landed (tdd: RED was one run of `swift test --filter CodeParserPlugin` with 33 issues: 14 Elixir and Bash golden cases, 9 routing cases, 9 table cases, 1 extension list; GREEN was one run of the same filter, all pass).
    - Package.swift: stadelmanma/tree-sitter-fortran exact 0.6.0, elixir-lang/tree-sitter-elixir exact 0.3.5 (their own URLs, as the Swift grammar), tree-sitter-bash exact 0.25.1 (through `treeSitterGrammarPackage(name:version:)`). Each has a doc comment. Products TreeSitterFortran, TreeSitterElixir, TreeSitterBash in `codeParserProducts`, in the order of ALL_CONFIGS. The versions are the versions of the Rust Cargo.lock and of the git.md table, thus no local C target was necessary.
    - CodeLanguageConfig.swift: entries fortran, elixir, bash; `all` is go, rust, java, c, cpp, ruby, csharp, php, fortran, swift, elixir, bash.
    - Goldens: 23 new cases under GitSemanticGoldens/{fortran,elixir,bash}/. Fortran: the 7 common cases plus `module` and `subroutine`. Elixir: the 7 common cases plus `private-function` (a module with `def` and `defp`). Bash: the 6 function cases only (Bash has no types, thus no `type-with-methods`). The golden suite now gives each language its own case list (`functionCaseNames`, `typeCaseNames`).
    - How the expected JSON was made: the throwaway program `semdiffgolden` of ^6dgd0h1 (scratch folder, path dependency on swissarmyhammer-sem). It asserts that each before and after file parses with no error node, that each case has at most one `modified` change, and that the inline-mode path gives the same changes.
    - DISCOVERY (latent defect in the Rust crate): with tree-sitter-fortran 0.6.0, the Rust crate reads NO Fortran entity. The grammar keeps each name in a `*_statement` child; the `function`/`subroutine`/`module` node has no `name` field and no identifier child, thus `extract_name` gives `None`. `type_declaration` is not a node kind of this grammar. Thus each Fortran golden has no change (`files` 0). The port does the same (git.md decision 6: follow the Rust crate). I made task ^q102ags for the user decision (correct Rust first, then port). Consequence for RED: the Fortran goldens pass with no Fortran entry too (no plugin and no entity give the same empty result); the routing and table tests cover Fortran in RED, and with the entry the goldens load and run the Fortran grammar.
    - Generator change: the inline mode of the tool always writes `files: 1`, but the differ writes `files: 0` for a file with no change row. For a case with no change the generator compares the change rows only. The golden JSON is the differ result, as the Swift test reads it.
    - Elixir form: the Elixir `function-modified` and `whitespace-and-comments` cases put the `def`s in a `quote do ... end` block that `Module.create` reads, thus the one `modified` change is the function (a `defmodule` would add a second `modified` change with an unstable order in Rust).
    - git.md "Spike result": one paragraph that records this task and the Fortran fact.
    - Not done: a manual sah `git get diff` inline call. The sah tool read `left` and `right` as file paths; the generator already runs the inline-mode code path for each case.
  timestamp: 2026-10-06T21:31:09.019532+00:00
- actor: claude-code
  id: 01m49j1chdysgpjz69b3grkt33
  text: |-
    ### implement — changed
    - evidence: 5 files and 23 golden cases — Package.swift; Sources/FoundationModelsMultitool/Capabilities/Git/Semantic/CodeLanguageConfig.swift; Tests/FoundationModelsMultitoolTests/{CodeParserPluginTests,CodeParserPluginGoldenTests}.swift; git.md; Tests/FoundationModelsMultitoolTests/GitSemanticGoldens/{fortran,elixir,bash}/ (69 files: 23 cases x before.txt, after.txt, expected.json). `swift package update`: everything up to date; the new grammars resolved at fortran 0.6.0, elixir 0.3.5, bash 0.25.1. `swift test`: 2104 tests in 181 suites passed, 0 failed (golden test: 88 cases). `swift build --build-tests --package-path IntegrationTests`: Build complete. Only warning: the known mlx-swift_Cmlx.bundle "missing creator" line. New task ^q102ags (Fortran gives no entity in Rust and Swift).
    - next: /review
  timestamp: 2026-10-06T21:31:12.301038+00:00
- actor: claude-code
  id: 01m49j9xh14dpz6tdn3bevxzxj
  text: |-
    ### test - green
    - evidence: swift build --build-tests - complete, 0 new warnings. Fortran, Elixir, and Bash grammar targets were cleaned and built again from zero - 0 warnings. No resource warning for the golden folder.
    - evidence: swift test - 2104 tests in 181 suites passed, 0 failed, 0 skipped.
    - evidence: IntegrationTests swift build --build-tests - complete, 0 new warnings.
    - note: The only warning is the known "missing creator for mutated node" for mlx-swift_Cmlx.bundle. It comes from the mlx-swift dependency and was there before this change.
    - next: review.
  timestamp: 2026-10-06T21:35:51.841211+00:00
- actor: claude-code
  id: 01m49jan8ezrcnrjs3252edd58
  text: |-
    ### commit — changed
    - evidence: one local commit "feat: add Fortran, Elixir, and Bash to git semantic". The sha is in git log. The commit includes this comment.
    - next: review. No push was done.
  timestamp: 2026-10-06T21:36:16.142979+00:00
depends_on:
- 01M48V9SN2MNFZGXZ9R6DGD0H1
position_column: doing
position_ordinal: '80'
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