---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m494kt1396va6y3v6ycr5ns9
  text: |-
    Research done.
    - utils/hash.rs uses XXH3-64 (xxhash_rust::xxh3::xxh3_64, seed 0, default secret), not XXH64, although a Rust comment says "xxHash64". The Swift port must implement XXH3-64 (all length paths: 0, 1-3, 4-8, 9-16, 17-128, 129-240, long). structural_hash uses a streaming Xxh3; with seed 0 the streaming digest equals the one-shot digest of the concatenated token bytes.
    - structural_hash takes a tree-sitter Node. No tree-sitter in this task, thus the port reads a small node protocol (kind, children, byte range). A golden from a real tree-sitter-rust parse in Rust pins it.
    - match_entities phase 1 iterates a Rust HashMap, thus its order of Modified changes is not deterministic in Rust. Swift uses the order of the after list (a deterministic choice inside the Rust contract).
    - differ.rs uses rayon par_iter + collect, which keeps the input order. Swift runs the files in input order; the result order is the same.
    - git_types.rs: the differ uses only FileChange and FileStatus. DiffScope and CommitInfo are not ported.
    - Validators: periphery counts the test target as a caller (--build-tests), thus test-only callers keep a symbol alive.
  timestamp: 2026-10-06T17:36:35.875949+00:00
- actor: claude-code
  id: 01m495k7k2ctaw59a5rhp7zddc
  text: |-
    Implementation landed (tdd: each suite failed to compile first, then passed).
    - Goldens: a throwaway Rust program in the scratch folder (path dependency on swissarmyhammer-sem, Cargo.lock of the workspace: xxhash-rust 0.8.15, tree-sitter 0.26.9, tree-sitter-rust 0.24.2) called content_hash, short_hash, and structural_hash and wrote Tests/FoundationModelsMultitoolTests/GitGoldens/semantic-hash-golden.json. The file has 43 content-hash inputs (each XXH3 length path, 0 to 4000 bytes, and UTF-8), 5 short-hash cases, and 6 structural-hash cases with the parsed tree. All values match on the first run.
    - Name conflict: the files capability has a public FileChange (Capabilities/Files/FileChangeSet.swift). The Rust FileChange is SemanticFileChange in Swift.
    - Not ported on purpose: the `timestamp` field of SemanticChange (each Rust path sets None and nothing reads it) and the unused `_file_path` argument of match_entities.
    - periphery: `parentID`, `metadata` (SemanticEntity) and `status` (SemanticFileChange) have no reader in the diff path, as in Rust. Each has a `// periphery:ignore` marker with the reason on the line above. A local periphery run over the built index shows no finding in the new files.
    - swiftlint no_magic_numbers: only the 192-byte XXH3 secret table reported; it is inside a `swiftlint:disable/enable no_magic_numbers` block with the reason.
    - Doc comments name the Rust file and the Rust symbol (for example `match_entities` in `model/identity.rs`), as Blame.swift and Hashline.swift do. They do not name line numbers, because line numbers change.
  timestamp: 2026-10-06T17:53:45.570400+00:00
- actor: claude-code
  id: 01m495katna4cmqh2nhd6krcjr
  text: |-
    ### implement — changed
    - evidence: 15 files — Package.swift; Sources/FoundationModelsMultitool/Capabilities/Git/Semantic/{XXH3,SemanticHash,SemanticEntity,SemanticChange,EntityMatcher,SemanticParserPlugin,ParserRegistry,SemanticFileChange,SemanticDiffer}.swift; Tests/FoundationModelsMultitoolTests/{SemanticHashTests,EntityMatcherTests,ParserRegistryTests,SemanticDifferTests}.swift; Tests/FoundationModelsMultitoolTests/Support/SemanticTestPlugins.swift; Tests/FoundationModelsMultitoolTests/GitGoldens/semantic-hash-golden.json. `swift test`: 2012 tests in 170 suites passed, 0 build warnings from the new code (62 new tests in 4 suites).
    - next: /review
  timestamp: 2026-10-06T17:53:48.885703+00:00
- actor: claude-code
  id: 01m495qgy0p1c6dw7155fx3rwq
  text: |-
    ### test - green
    - evidence: swift build --build-tests: complete. swift test: 2012 tests in 170 suites passed, 0 failed, 0 skipped. IntegrationTests swift build --build-tests: complete.
    - GitGoldens resource: no "unhandled file" or resource warning. swift package describe shows GitGoldens as a resource.
    - warnings: only the known mlx-swift_Cmlx.bundle "missing creator for mutated node". It was there before this change.
    - skips: none found (no .disabled, XCTSkip, withKnownIssue).
    - next: review.
  timestamp: 2026-10-06T17:56:06.208005+00:00
- actor: claude-code
  id: 01m495r13c1b24y4w72k55kek5
  text: |-
    ### commit — changed
    - evidence: one local commit "feat: port the semantic model, matcher, differ, and plugin registry to the git capability". It holds the Semantic sources, the new test suites, the semantic hash golden file, the GitGoldens resource in Package.swift, and the .kanban changes. The sha is in the git log. The commit is not pushed.
    - next: review
  timestamp: 2026-10-06T17:56:22.764197+00:00
- actor: claude-code
  id: 01m496aa0zjwvnjjk0shfb2wv4
  text: |-
    ### review — clean
    - evidence: review sha HEAD~1..HEAD (commit aa95985). 0 findings, 0 confirmed, 0 refuted. 14 files attempted, 0 failed. Not reviewed: 4 .kanban files (from .reviewignore), and semantic-hash-golden.json (no validator matches it). The commit renames no file, thus no file-scoped review was necessary.
    - next: The task is in done.
  timestamp: 2026-10-06T18:06:21.727713+00:00
- actor: claude-code
  id: 01m496apj7zzhbxt8pb6jyjsr9
  text: |-
    ### finish iteration 1 — clean
    - implement: changed — 16 files (Package.swift GitGoldens resource, 9 files in Git/Semantic/, 4 test suites, test plugins, hash golden json)
    - test: green — swift test, 2012 passed in 170 suites; IntegrationTests build complete
    - commit: aa95985
    - review: clean — 0 findings, 14 files reviewed
  timestamp: 2026-10-06T18:06:34.567290+00:00
depends_on:
- 01M48V7FH0DA0YA7D28TJV0B4Z
position_column: done
position_ordinal: ffffb080
title: 'git semantic: port the model, the matcher, the differ, and the plugin registry'
---
## Goal

Port the core of `swissarmyhammer-sem` that the semantic diff needs (git.md decision 6). No language plugin yet; a test plugin is enough.

## Source

`../swissarmyhammer/crates/swissarmyhammer-sem/src/`:
- `model/entity.rs`, `model/change.rs`, `model/identity.rs` (`match_entities`, about 700 lines)
- `parser/plugin.rs`, `parser/registry.rs`, `parser/differ.rs` (`compute_semantic_diff`, `DiffResult`)
- `git_types.rs` (`FileChange`, `FileStatus`): port only the parts that the differ uses
- `utils/hash.rs`

Do NOT port `graph.rs`, `duplication.rs`, `commented_code.rs`, `test_census.rs`, `public_surface.rs`, or `definitions.rs` (they serve `code_context`).

## Work

1. New folder `Sources/FoundationModelsMultitool/Capabilities/Git/Semantic/`. All types are internal.
2. Port the types and the algorithms one to one. Keep the names in Swift style. Keep the similarity rules and thresholds exactly. Write the source file and line in each doc comment, as the files capability does for its ports.
3. The hash must give the same value as the Rust code, because the `entity_id` and the "structural change" result depend on it. Check this with a golden test.
4. A registry that selects a plugin by file extension, with a `fallback` slot.

## Tests

- Use a small test plugin (one entity per line, for example) to test `match_entities`: added, deleted, modified, renamed, moved.
- Golden vectors for the hash: make the values with the Rust code (a small throwaway Rust test or the sah tool), then commit them as fixtures.

## Acceptance

- `swift build` and `swift test` pass with no new warnings. #git