---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m497528jysfhcpdxfnsq636j
  text: |-
    Research done.
    - Rust code plugin uses the default `compute_similarity` (`default_similarity`). Thus the Swift plugin uses the protocol default.
    - "moved" cannot come from `get diff` inline mode or file mode: the matcher sets `moved` only when the file path differs, and the tool always uses one path (inline: `inline.<ext>`; file mode: `old_file_path: None`). The moved goldens come from `compute_semantic_diff` with `old_file_path = old/inline.<ext>`.
    - Golden generator: a throwaway Rust program in the scratch folder (path dependency on swissarmyhammer-sem, the Cargo.lock of the workspace: tree-sitter 0.26.9, tree-sitter-rust 0.24.2, tree-sitter-go 0.25.0, tree-sitter-swift 0.7.2). For each case it runs `compute_semantic_diff`, writes the `DiffResponse` shape of the tool with camelCase names, and for each case with one path it also runs the inline-mode path (`get_plugin`, `extract_entities`, `match_entities`, files 1) and asserts equal JSON. All 18 non-moved cases passed that assert. A manual `get diff` inline call with the sah tool on swift/type-with-methods gave the same values.
    - Phase 1 of the Rust matcher walks a HashMap, thus two `modified` changes come in a random order. A nested change modifies the parent too. Each golden has at most one `modified` change (the generator asserts it). "Type with methods" adds a method (parent modified + method added).
    - Go `type_declaration` gives no entity in Rust: it has no `name` field, and its named child is `type_spec`, not an identifier. The Go golden shows this (the type change makes no change row).
    - tree-sitter-swift `multiline_comment` is not in the comment kinds of `structural_hash`, thus a `/* */` change is structural in Rust too. The Swift golden uses a `//` comment.
    - SwiftTreeSitter `Parser.parse(_ String)` parses UTF-16; byte offsets are then UTF-16. The port parses UTF-8 through `parse(tree:encoding:readBlock:)` with `TSInputEncodingUTF8`, which needs `import TreeSitter`. Thus `Package.swift` declares the runtime package `tree-sitter/tree-sitter` too (exact 0.25.10, the version that SwiftTreeSitter 0.25.0 resolves).
    - The later language tasks only add entries, thus the whole `entity_extractor.rs` is ported (declaring calls of Elixir, export statements, C declarators, Python decorated definitions, C++ templates). The extractor reads a node protocol, thus fake trees test the branches whose grammar is not in the package yet.
    - Not ported: `extract_entity_nodes` pairs (only `public_surface` reads the nodes), `extensions_for_language`, `is_code_file` (no Swift reader).
  timestamp: 2026-10-06T18:20:58.514924+00:00
- actor: claude-code
  id: 01m497xcf6sf27hc71bhe4g85b
  text: |-
    Implementation landed (tdd: the test target failed to compile first on the missing `CodeSyntaxNode`; then one fixture defect in a fake tree, then all green).
    - Package.swift: SwiftTreeSitter exact 0.25.0, the runtime tree-sitter/tree-sitter exact 0.25.10 (product `TreeSitter`, for `TSInputEncodingUTF8`; same URL as SwiftTreeSitter writes, no `.git`), tree-sitter-rust exact 0.24.2 and tree-sitter-go exact 0.25.0 (helper `treeSitterGrammarPackage(name:version:)`), alex-pinkus/tree-sitter-swift exact "0.7.4-with-generated-files". Each has a doc comment. Products are grouped in `codeParserProducts`. New resource `.copy("GitSemanticGoldens")`.
    - Sources (Git/Semantic): `CodeEntityExtractor.swift` (protocol `CodeSyntaxNode`, `EntityVocabulary`, the walk, the `map_node_type` table as a dictionary), `EntityNameReader.swift` (all name readers of entity_extractor.rs, also C declarators, Python decorators, C++ templates, Elixir declaring calls), `CodeLanguageConfig.swift` (Go, Rust, Swift entries in the order of ALL_CONFIGS), `CodeParserPlugin.swift` (plugin + `TreeSitterSyntaxNode` adapter, UTF-8 parse). `ParserRegistry.makeDefault()` ports `create_default_registry` with the code plugin only; `ParserRegistry.fileExtension(of:)` is now internal (the code plugin reads it, as Rust `dotted_lowercase_extension`).
    - Goldens: 21 cases (7 for each of rust, go, swift) under Tests/FoundationModelsMultitoolTests/GitSemanticGoldens/<lang>/<case>/{before.txt,after.txt,expected.json}. The fixture files use `.txt` so no Swift/Rust validator or compiler reads them. All 21 pass.
    - Grammar version: the Rust crate parses Swift with tree-sitter-swift 0.7.2, the Swift package with 0.7.4-with-generated-files. No Swift golden differs. Go and Rust grammar versions are equal on both sides.
    - Divergence from Rust, on purpose: a grammar that the runtime refuses (`set_language` failure) is a `preconditionFailure` (Rust: warning + no entities). The grammars are fixed at build time and the golden suite loads each one, thus a refusal is a build defect (swift/error-handling: programmer error).
    - Doc drift (not changed, outside the card): git.md "libgit2 C API" says "The tree-sitter packages are not in Package.swift: the language tasks add them." That is now stale for SwiftTreeSitter, the runtime, Rust, Go, and Swift.
    - Environment note: the IntegrationTests build printed one SwiftPM fetch warning "'tree-sitter': skipping cache due to an error: The file “maintenance.lock” doesn’t exist." It comes from the SwiftPM repository cache at resolve time, not from the code.
  timestamp: 2026-10-06T18:34:15.398751+00:00
- actor: claude-code
  id: 01m497xg5vhcxbr75ntvrbsvs0
  text: |-
    ### implement — changed
    - evidence: 13 paths — Package.swift; Sources/FoundationModelsMultitool/Capabilities/Git/Semantic/{CodeEntityExtractor,EntityNameReader,CodeLanguageConfig,CodeParserPlugin,ParserRegistry}.swift; Tests/FoundationModelsMultitoolTests/{CodeEntityExtractorTests,CodeParserPluginTests,CodeParserPluginGoldenTests}.swift; Tests/FoundationModelsMultitoolTests/Support/FakeSyntaxTree.swift; Tests/FoundationModelsMultitoolTests/GitSemanticGoldens/ (63 files: 21 cases x before.txt, after.txt, expected.json). `swift build --build-tests`: no new warning (only the known mlx-swift_Cmlx.bundle "missing creator" line). `swift test`: 2041 tests in 173 suites passed (29 new tests in 3 suites, 21 golden cases). `swift build --build-tests --package-path IntegrationTests`: Build complete.
    - next: /review
  timestamp: 2026-10-06T18:34:19.195144+00:00
- actor: claude-code
  id: 01m4989wa89kf0r19x4cdhyn7c
  text: |-
    ### test - green
    - evidence: swift build --build-tests clean. swift test: 2041 tests in 173 suites passed, 0 failed, 0 skipped. IntegrationTests swift build --build-tests clean.
    - SwiftPM: no unhandled file or resource warning. A fresh manifest load (swift package describe) shows GitSemanticGoldens as a resource. A fresh build of the SwiftTreeSitter, TreeSitter, TreeSitterRust, TreeSitterGo and TreeSitterSwift targets gives no compiler warning.
    - Touched Semantic sources and the new tests, then rebuilt: no new warning.
    - Only warning: missing creator for mutated node for mlx-swift_Cmlx.bundle. It is a known dependency warning. It is not red.
    - next: review
  timestamp: 2026-10-06T18:41:04.840461+00:00
- actor: claude-code
  id: 01m498aftes15rhg92j6ex01ah
  text: |-
    ### commit — changed
    - evidence: one local commit "feat: add the code parser plugin core with Swift, Rust, and Go to git semantic". The sha is in the git log, not here, so the commit stays unchanged.
    - next: review
  timestamp: 2026-10-06T18:41:24.814279+00:00
- actor: claude-code
  id: 01m498w6hp7gearmxbzryrapdj
  text: |-
    ### review — findings
    - evidence: `review sha HEAD~1..HEAD` (commit 01a319c). The commit renames no file, thus no file-scoped review was necessary. Counts: 2 findings, 2 confirmed, 0 refuted. Findings: Tests/FoundationModelsMultitoolTests/Support/FakeSyntaxTree.swift:65, Tests/FoundationModelsMultitoolTests/Support/FakeSyntaxTree.swift:73 (`code-hygiene/idioms-swift` UseLetInEveryBoundCaseVariable).
    - next: Move each 'let' keyword inside the 'case' pattern in FakeSyntaxTree.swift. Do this for all bound case patterns in the file. Then review again.
  timestamp: 2026-10-06T18:51:05.142560+00:00
- actor: claude-code
  id: 01m498xs5zmr1aq1n6zgd6akaz
  text: |-
    ### finish iteration 1 — findings
    - implement: changed — 13 paths (Package.swift, 5 Semantic sources, 3 test suites, FakeSyntaxTree.swift, 21 golden cases)
    - test: green — swift test, 2041 passed in 173 suites; IntegrationTests build complete; no grammar warning
    - commit: 01a319c
    - review: findings — Tests/FoundationModelsMultitoolTests/Support/FakeSyntaxTree.swift:65, Tests/FoundationModelsMultitoolTests/Support/FakeSyntaxTree.swift:73 (code-hygiene/idioms-swift: UseLetInEveryBoundCaseVariable)
  timestamp: 2026-10-06T18:51:56.991236+00:00
- actor: claude-code
  id: 01m4995rj1c2hc3yk8yjpx52bp
  text: |-
    Review findings worked (code-hygiene/idioms-swift UseLetInEveryBoundCaseVariable).
    - FakeSyntaxTree.swift: `case let .leaf(kind, text, field, isNamed)` is now `case .leaf(let kind, let text, let field, let isNamed)`, and `case let .node(kind, children, field)` is now `case .node(let kind, let children, let field)`. These were the only two bound case patterns in the file.
    - Sweep: I searched each Swift file that commit 01a319c added or changed (Package.swift, the 5 Semantic sources, the 3 test suites, FakeSyntaxTree.swift) for `case let` / `case var`, which also finds `if case let` and `guard case let`. There was no other match. Outside the commit, `RepositoryFile.swift` has `for case let fileURL as URL`. It binds one value through a type cast, so the rule does not apply, and the file is not in the scope.
    - Both findings are now `- [x]`.
  timestamp: 2026-10-06T18:56:18.497407+00:00
- actor: claude-code
  id: 01m4995vtbdbjmp41yj06ytseb
  text: |-
    ### implement — changed
    - evidence: 1 file — Tests/FoundationModelsMultitoolTests/Support/FakeSyntaxTree.swift. `swift build --build-tests`: Build complete, no new warning (only the known mlx-swift_Cmlx.bundle "missing creator" line). `swift test`: 2041 tests in 173 suites passed, 0 failed.
    - next: /review
  timestamp: 2026-10-06T18:56:21.835778+00:00
- actor: claude-code
  id: 01m49992k3p2xptxzbn2asf2xm
  text: |-
    ### test - green
    - evidence: swift build --build-tests - Build complete. swift test - 2041 tests in 173 suites passed, 0 failed, 0 skipped. IntegrationTests: swift build --build-tests - Build complete.
    - dependency warning only: "missing creator for mutated node" for mlx-swift_Cmlx.bundle (known, before this change). No other warning.
    - next: review
  timestamp: 2026-10-06T18:58:07.075002+00:00
- actor: claude-code
  id: 01m4999jk5zemn01krepfykew4
  text: |-
    ### commit — changed
    - evidence: refactor: move let inside each case pattern in FakeSyntaxTree (the sha is the commit that holds this comment; read it with git log)
    - next: review
  timestamp: 2026-10-06T18:58:23.461943+00:00
depends_on:
- 01M48V9CB973V4MPTJV8GEXZCT
position_column: doing
position_ordinal: '80'
title: 'git semantic: code plugin core, with Swift, Rust, and Go'
---
## Goal

Port the tree-sitter code plugin of `swissarmyhammer-sem`, and the first three languages (git.md decisions 6 and 7).

## Source

`../swissarmyhammer/crates/swissarmyhammer-sem/src/parser/plugins/code/`:
- `entity_extractor.rs`
- `languages.rs` (the table of each language: grammar, node kinds, extensions)
- `mod.rs`: ONLY the parts that `extract_entities` and `compute_similarity` use. Do not port the parts for duplication, commented code, test census, or public surface.

## Work

1. The code plugin over the tree-sitter Swift package that the spike selected. One language table entry for each language, in the same form as `languages.rs`, thus the next language tasks only add entries and grammars.
2. Add the grammar packages for Swift, Rust, and Go to `Package.swift` (the spike recorded the URLs). Write a doc comment for each dependency.
3. Register the plugin for `.swift`, `.rs`, `.go` in the registry.

## Golden tests

The Rust code is the reference. For each language, make fixtures with the sah tool `git` op `get diff` in inline mode (`left_text`, `right_text`, `language`). Each fixture is a before file, an after file, and the expected JSON. Cover: a function added, deleted, modified, renamed, moved; a type with methods; a change that is only in whitespace or comments. Commit the fixtures under a new test resource folder (declare it in `Package.swift`, as `FilesGoldens` is). The Swift output must equal the expected JSON (after the change to camelCase field names).

## Acceptance

- `swift build` and `swift test` pass with no new warnings.
- Each golden of the three languages passes.

## Review Findings (2026-10-06 13:41)

> Scope: `review sha HEAD~1..HEAD` — reviewed the diffs only — lines this change added or modified. 10 file(s) reviewed, 68 not reviewed.

> 4 file(s) not reviewed — excluded by an ignore rule:
> - `.kanban/ (from .reviewignore)` — 4 file(s)

> 64 file(s) not reviewed — no validator matched:
> - `Tests/FoundationModelsMultitoolTests/GitSemanticGoldens/go/function-added/after.txt` — no validator matches this file
> - `Tests/FoundationModelsMultitoolTests/GitSemanticGoldens/go/function-added/before.txt` — no validator matches this file
> - `Tests/FoundationModelsMultitoolTests/GitSemanticGoldens/go/function-added/expected.json` — no validator matches this file
> - `Tests/FoundationModelsMultitoolTests/GitSemanticGoldens/go/function-deleted/after.txt` — no validator matches this file
> - `Tests/FoundationModelsMultitoolTests/GitSemanticGoldens/go/function-deleted/before.txt` — no validator matches this file
> - `Tests/FoundationModelsMultitoolTests/GitSemanticGoldens/go/function-deleted/expected.json` — no validator matches this file
> - `Tests/FoundationModelsMultitoolTests/GitSemanticGoldens/go/function-modified/after.txt` — no validator matches this file
> - `Tests/FoundationModelsMultitoolTests/GitSemanticGoldens/go/function-modified/before.txt` — no validator matches this file
> - `Tests/FoundationModelsMultitoolTests/GitSemanticGoldens/go/function-modified/expected.json` — no validator matches this file
> - `Tests/FoundationModelsMultitoolTests/GitSemanticGoldens/go/function-moved/after.txt` — no validator matches this file
> - `Tests/FoundationModelsMultitoolTests/GitSemanticGoldens/go/function-moved/before.txt` — no validator matches this file
> - `Tests/FoundationModelsMultitoolTests/GitSemanticGoldens/go/function-moved/expected.json` — no validator matches this file
> - `Tests/FoundationModelsMultitoolTests/GitSemanticGoldens/go/function-renamed/after.txt` — no validator matches this file
> - `Tests/FoundationModelsMultitoolTests/GitSemanticGoldens/go/function-renamed/before.txt` — no validator matches this file
> - `Tests/FoundationModelsMultitoolTests/GitSemanticGoldens/go/function-renamed/expected.json` — no validator matches this file
> - `Tests/FoundationModelsMultitoolTests/GitSemanticGoldens/go/type-with-methods/after.txt` — no validator matches this file
> - `Tests/FoundationModelsMultitoolTests/GitSemanticGoldens/go/type-with-methods/before.txt` — no validator matches this file
> - `Tests/FoundationModelsMultitoolTests/GitSemanticGoldens/go/type-with-methods/expected.json` — no validator matches this file
> - `Tests/FoundationModelsMultitoolTests/GitSemanticGoldens/go/whitespace-and-comments/after.txt` — no validator matches this file
> - `Tests/FoundationModelsMultitoolTests/GitSemanticGoldens/go/whitespace-and-comments/before.txt` — no validator matches this file
> - `Tests/FoundationModelsMultitoolTests/GitSemanticGoldens/go/whitespace-and-comments/expected.json` — no validator matches this file
> - `Tests/FoundationModelsMultitoolTests/GitSemanticGoldens/rust/function-added/after.txt` — no validator matches this file
> - `Tests/FoundationModelsMultitoolTests/GitSemanticGoldens/rust/function-added/before.txt` — no validator matches this file
> - `Tests/FoundationModelsMultitoolTests/GitSemanticGoldens/rust/function-added/expected.json` — no validator matches this file
> - `Tests/FoundationModelsMultitoolTests/GitSemanticGoldens/rust/function-deleted/after.txt` — no validator matches this file
> - `Tests/FoundationModelsMultitoolTests/GitSemanticGoldens/rust/function-deleted/before.txt` — no validator matches this file
> - `Tests/FoundationModelsMultitoolTests/GitSemanticGoldens/rust/function-deleted/expected.json` — no validator matches this file
> - `Tests/FoundationModelsMultitoolTests/GitSemanticGoldens/rust/function-modified/after.txt` — no validator matches this file
> - `Tests/FoundationModelsMultitoolTests/GitSemanticGoldens/rust/function-modified/before.txt` — no validator matches this file
> - `Tests/FoundationModelsMultitoolTests/GitSemanticGoldens/rust/function-modified/expected.json` — no validator matches this file
> - `Tests/FoundationModelsMultitoolTests/GitSemanticGoldens/rust/function-moved/after.txt` — no validator matches this file
> - `Tests/FoundationModelsMultitoolTests/GitSemanticGoldens/rust/function-moved/before.txt` — no validator matches this file
> - `Tests/FoundationModelsMultitoolTests/GitSemanticGoldens/rust/function-moved/expected.json` — no validator matches this file
> - `Tests/FoundationModelsMultitoolTests/GitSemanticGoldens/rust/function-renamed/after.txt` — no validator matches this file
> - `Tests/FoundationModelsMultitoolTests/GitSemanticGoldens/rust/function-renamed/before.txt` — no validator matches this file
> - `Tests/FoundationModelsMultitoolTests/GitSemanticGoldens/rust/function-renamed/expected.json` — no validator matches this file
> - `Tests/FoundationModelsMultitoolTests/GitSemanticGoldens/rust/type-with-methods/after.txt` — no validator matches this file
> - `Tests/FoundationModelsMultitoolTests/GitSemanticGoldens/rust/type-with-methods/before.txt` — no validator matches this file
> - `Tests/FoundationModelsMultitoolTests/GitSemanticGoldens/rust/type-with-methods/expected.json` — no validator matches this file
> - `Tests/FoundationModelsMultitoolTests/GitSemanticGoldens/rust/whitespace-and-comments/after.txt` — no validator matches this file
> - `Tests/FoundationModelsMultitoolTests/GitSemanticGoldens/rust/whitespace-and-comments/before.txt` — no validator matches this file
> - `Tests/FoundationModelsMultitoolTests/GitSemanticGoldens/rust/whitespace-and-comments/expected.json` — no validator matches this file
> - `Tests/FoundationModelsMultitoolTests/GitSemanticGoldens/swift/function-added/after.txt` — no validator matches this file
> - `Tests/FoundationModelsMultitoolTests/GitSemanticGoldens/swift/function-added/before.txt` — no validator matches this file
> - `Tests/FoundationModelsMultitoolTests/GitSemanticGoldens/swift/function-added/expected.json` — no validator matches this file
> - `Tests/FoundationModelsMultitoolTests/GitSemanticGoldens/swift/function-deleted/after.txt` — no validator matches this file
> - `Tests/FoundationModelsMultitoolTests/GitSemanticGoldens/swift/function-deleted/before.txt` — no validator matches this file
> - `Tests/FoundationModelsMultitoolTests/GitSemanticGoldens/swift/function-deleted/expected.json` — no validator matches this file
> - `Tests/FoundationModelsMultitoolTests/GitSemanticGoldens/swift/function-modified/after.txt` — no validator matches this file
> - `Tests/FoundationModelsMultitoolTests/GitSemanticGoldens/swift/function-modified/before.txt` — no validator matches this file
> - `Tests/FoundationModelsMultitoolTests/GitSemanticGoldens/swift/function-modified/expected.json` — no validator matches this file
> - `Tests/FoundationModelsMultitoolTests/GitSemanticGoldens/swift/function-moved/after.txt` — no validator matches this file
> - `Tests/FoundationModelsMultitoolTests/GitSemanticGoldens/swift/function-moved/before.txt` — no validator matches this file
> - `Tests/FoundationModelsMultitoolTests/GitSemanticGoldens/swift/function-moved/expected.json` — no validator matches this file
> - `Tests/FoundationModelsMultitoolTests/GitSemanticGoldens/swift/function-renamed/after.txt` — no validator matches this file
> - `Tests/FoundationModelsMultitoolTests/GitSemanticGoldens/swift/function-renamed/before.txt` — no validator matches this file
> - `Tests/FoundationModelsMultitoolTests/GitSemanticGoldens/swift/function-renamed/expected.json` — no validator matches this file
> - `Tests/FoundationModelsMultitoolTests/GitSemanticGoldens/swift/type-with-methods/after.txt` — no validator matches this file
> - `Tests/FoundationModelsMultitoolTests/GitSemanticGoldens/swift/type-with-methods/before.txt` — no validator matches this file
> - `Tests/FoundationModelsMultitoolTests/GitSemanticGoldens/swift/type-with-methods/expected.json` — no validator matches this file
> - `Tests/FoundationModelsMultitoolTests/GitSemanticGoldens/swift/whitespace-and-comments/after.txt` — no validator matches this file
> - `Tests/FoundationModelsMultitoolTests/GitSemanticGoldens/swift/whitespace-and-comments/before.txt` — no validator matches this file
> - `Tests/FoundationModelsMultitoolTests/GitSemanticGoldens/swift/whitespace-and-comments/expected.json` — no validator matches this file
> - `git.md` — no validator matches this file

- [x] `Tests/FoundationModelsMultitoolTests/Support/FakeSyntaxTree.swift:65` `code-hygiene/idioms-swift` — UseLetInEveryBoundCaseVariable: move this 'let' keyword inside the 'case' pattern, before each of the bound variables.
- [x] `Tests/FoundationModelsMultitoolTests/Support/FakeSyntaxTree.swift:73` `code-hygiene/idioms-swift` — UseLetInEveryBoundCaseVariable: move this 'let' keyword inside the 'case' pattern, before each of the bound variables. #git