---
assignees:
- claude-code
depends_on:
- 01M48V7FH0DA0YA7D28TJV0B4Z
position_column: todo
position_ordinal: '8680'
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