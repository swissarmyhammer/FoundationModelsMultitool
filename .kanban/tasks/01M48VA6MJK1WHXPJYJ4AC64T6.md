---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m499hs203ada1rg3geh7d8tf
  text: |-
    Research done.
    - `languages.rs` entries: JAVA (.java), C (.c, .h), CPP (.cpp, .cc, .cxx, .hpp, .hh, .hxx), RUBY (.rb), CSHARP (.cs), PHP (.php, grammar `LANGUAGE_PHP`). ALL_CONFIGS order: go, rust, java, c, cpp, ruby, csharp, php, ..., swift. C comes before C++, thus `.h` goes to C. The Swift table keeps that order.
    - The port of ^6dgd0h1 already has all name readers (C declarators, C++ templates) and the full `map_node_type` table. Thus this task adds only table entries, grammars, and goldens.
    - Rust Cargo.lock grammar versions: java 0.23.5, c 0.24.2, cpp 0.23.4, c-sharp 0.23.5, ruby 0.23.1, php 0.24.2. The Swift package uses php 0.25.0 (git.md table). Thus PHP is the one grammar with a different version. The other five are equal.
    - Golden generator: the throwaway program `semdiffgolden` of ^6dgd0h1 (scratch folder) takes the language list from its code; I extend it for the new languages.
  timestamp: 2026-10-06T19:02:52.224785+00:00
- actor: claude-code
  id: 01m49a10gg7hwjf18naj6zwegs
  text: |-
    Implementation landed (tdd: RED was one run of `swift test --filter CodeParserPlugin` with 69 issues: 44 new golden cases and 25 routing and table cases; GREEN was one run of the same filter, all pass).
    - Package.swift: six grammar packages with the exact versions of the git.md table (java 0.23.5, c 0.24.2, cpp 0.23.4, ruby 0.23.1, c-sharp 0.23.5, php 0.25.0) through `treeSitterGrammarPackage(name:version:)`, each with a doc comment. Six products in `codeParserProducts`.
    - CodeLanguageConfig.swift: entries java, c, cpp, ruby, csharp, php in the order of ALL_CONFIGS (go, rust, java, c, cpp, ruby, csharp, php, swift). `.h` goes to C, because C comes before C++, as in Rust. PHP uses `tree_sitter_php()` (Rust `LANGUAGE_PHP`), not `tree_sitter_php_only()`.
    - Goldens: 44 new cases under GitSemanticGoldens/{java,c,cpp,csharp,ruby,php}/: the 7 common cases for each language, plus cpp/namespace and csharp/property. The golden suite now takes extra case names for each language.
    - How the expected JSON was made: the throwaway program `semdiffgolden` of ^6dgd0h1 (scratch folder, path dependency on swissarmyhammer-sem, Cargo.lock grammars java 0.23.5, c 0.24.2, cpp 0.23.4, c-sharp 0.23.5, ruby 0.23.1, php 0.24.2). It now takes `<folder>:<ext>` arguments and also asserts that each before and after file parses with no error node. For each case with one path it asserts that the inline-mode path gives the same JSON. A manual sah `git` `get diff` inline call on csharp/property gave the same values.
    - Design point: Java and C# have no method outside a type, and a method change modifies the class too (two `modified` changes, unstable order in Rust). Thus java and csharp `function-modified` and `whitespace-and-comments` put the methods in a `record`. A record is not an entity in Rust, thus the method is the one `modified` change. Each golden has at most one `modified` change (the generator asserts it).
    - Grammar version: the Rust crate uses tree-sitter-php 0.24.2; the Swift package uses 0.25.0. All 7 PHP goldens pass, thus these fixtures show no difference. The other five grammars have equal versions on both sides.
    - Not mine: git.md has an uncommitted change in the work tree (decision 12, grammar versions for JavaScript and Python), made at 14:02 by another session or the user. I did not touch it. The stale git.md sentence from ^6dgd0h1 ("The tree-sitter packages are not in Package.swift") is still there.
  timestamp: 2026-10-06T19:11:11.376404+00:00
- actor: claude-code
  id: 01m49a16562z78n4wa6w29h1f5
  text: |-
    ### implement — changed
    - evidence: 4 files and 44 golden cases — Package.swift; Sources/FoundationModelsMultitool/Capabilities/Git/Semantic/CodeLanguageConfig.swift; Tests/FoundationModelsMultitoolTests/{CodeParserPluginTests,CodeParserPluginGoldenTests}.swift; Tests/FoundationModelsMultitoolTests/GitSemanticGoldens/{java,c,cpp,csharp,ruby,php}/ (132 files: 44 cases x before.txt, after.txt, expected.json). `swift package update` resolved each grammar at its exact version. `swift build --build-tests`: no new warning (only the known mlx-swift_Cmlx.bundle "missing creator" line). `swift test`: 2041 tests in 173 suites passed (golden test: 65 cases). `swift build --build-tests --package-path IntegrationTests`: Build complete, the six grammars compile with no warning.
    - next: /review
  timestamp: 2026-10-06T19:11:17.158484+00:00
- actor: claude-code
  id: 01m49a6gp3cjf7gethec2r3q4y
  text: |-
    ### test - green
    - evidence: swift build --build-tests - complete, 0 new warnings. swift test - 2041 tests in 173 suites passed, 0 failed, 0 skipped. IntegrationTests swift build --build-tests - complete.
    - grammar check: I removed the build folders of the six new grammar targets (java, c, cpp, c-sharp, ruby, php) and the compilation cache. I built again from source. The compiler gave 0 warnings for them. The golden resource folder gave 0 resource warnings.
    - known dependency warning, not red: "missing creator for mutated node" for mlx-swift_Cmlx.bundle. It comes from the mlx-swift dependency and was there before this change.
    - Package.resolved was not stale. I did not run swift package update.
    - next: review. No commit made.
  timestamp: 2026-10-06T19:14:11.779598+00:00
- actor: claude-code
  id: 01m49a75d15j3x7yf4w6s02e8w
  text: |-
    ### commit — changed
    - evidence: one local commit "feat: add Java, C, C++, C#, Ruby, and PHP to git semantic". It holds Package.swift (six grammar packages), CodeLanguageConfig.swift, the changed tests, the new golden folders (java, c, cpp, csharp, ruby, php), git.md, and all .kanban/ changes. The sha is in the step block the commit step returns. It is not in this text, because this comment is part of the commit. No push.
    - next: review
  timestamp: 2026-10-06T19:14:32.993969+00:00
- actor: claude-code
  id: 01m49ad8zzxwd4x82q0a725mdd
  text: |-
    ### review — clean
    - evidence: review sha HEAD~1..HEAD (commit f05171e). Counts: 0 findings, 0 confirmed, 0 refuted; 7 attempted, 0 failed. The commit renames no file, thus no file-scoped review was necessary. The validators read 4 files. 133 golden fixture files and git.md had no matching validator. 6 .kanban files are ignored by .reviewignore.
    - next: The task is in done.
  timestamp: 2026-10-06T19:17:53.279952+00:00
- actor: claude-code
  id: 01m49adn6sn42bch0x08kn8kev
  text: |-
    ### finish iteration 1 — clean
    - implement: changed — 4 files and 44 golden cases (Package.swift, CodeLanguageConfig.swift, 2 test files, golden folders for java, c, cpp, csharp, ruby, php)
    - test: green — swift test, 2041 passed in 173 suites; fresh grammar build has no warning; IntegrationTests build complete
    - commit: f05171e
    - review: clean — 0 findings, 7 validators on 4 files
  timestamp: 2026-10-06T19:18:05.785383+00:00
depends_on:
- 01M48V9SN2MNFZGXZ9R6DGD0H1
position_column: done
position_ordinal: ffffb280
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