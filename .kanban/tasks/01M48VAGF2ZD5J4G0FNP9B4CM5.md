---
assignees:
- claude-code
depends_on:
- 01M48V9CB973V4MPTJV8GEXZCT
position_column: todo
position_ordinal: 8b80
title: 'git semantic: JSON, YAML, TOML, CSV, Markdown, and fallback plugins'
---
## Goal

Port the data-format plugins and the fallback plugin of `swissarmyhammer-sem` (git.md decisions 6 and 7).

## Source

`../swissarmyhammer/crates/swissarmyhammer-sem/src/parser/plugins/`: `json.rs` (564 lines), `yaml.rs`, `toml_plugin.rs`, `csv_plugin.rs`, `markdown.rs`, `fallback.rs`.

## Work

1. Find out how each Rust plugin parses its format (tree-sitter, a Rust crate such as `serde_json`, or plain text). Use the same method in Swift if it is available with no new dependency (for example `JSONSerialization` for JSON). If a plugin needs a new dependency, record it in a comment and use the package that the spike found.
2. The entity of each format must be the same as in the source (for example a JSON key path, a Markdown heading section, a CSV row). Keep the entity names and the entity ids identical.
3. Port `fallback.rs`, and register it as the plugin for each extension that no other plugin owns.
4. Register each plugin for its extensions.

## Golden tests

Make fixtures with the sah tool `git` op `get diff` (inline mode, `language` = `json`, `yaml`, `toml`, `csv`, `markdown`, and an unknown language for the fallback). Cover: a key or section added, deleted, modified, renamed, moved.

## Acceptance

- `swift build` and `swift test` pass with no new warnings.
- Each golden passes. #git