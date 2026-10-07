---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m49wjg02wq7vvt1331tz8gkx
  text: |-
    Research done.
    - json.rs does NOT use serde_json: it scans the text by hand (a character state machine). The port is a hand scanner too; Foundation JSONSerialization is not used (it would lose the key order and the source text).
    - csv_plugin.rs, markdown.rs (regex `^(#{1,6})\s+(.+)`), fallback.rs (chunks of 20 lines) are plain text. Line numbers of csv count only the non-blank lines (a Rust quirk, ported as is). `file_path.ends_with(".tsv")` is case-sensitive.
    - yaml.rs: keys come from a line scan; the content hash of each key is `content_hash` of the serde_yaml_ng value text (`to_string(value).trim()` for a mapping/sequence, the scalar text else, `{:?}` for a tagged scalar). serde_yaml_ng 0.10.0 uses unsafe-libyaml 0.2.11 (libyaml 0.2.5) for the parser and the emitter (unicode on, width -1). Yams 6.2.2 (already in the graph through FoundationModelsExtras, exact 6.2.2, the newest tag) carries the same libyaml as its C module `CYaml`. A probe package showed that `import CYaml` compiles with only the `Yams` product. The port uses the libyaml events of CYaml directly, so the loader (anchors, aliases, tags, duplicate keys, the 128 depth limit) and the emitter (tags, scalar styles) follow serde_yaml_ng exactly. Yams' own Node API is not enough: its emitter always marks a scalar tag implicit (a `!Ref x` tag is lost) and its duplicate-key test differs.
    - toml_plugin.rs: toml 1.1.2+spec-1.1.0 without `preserve_order` (also in the sah workspace), so a table is a BTreeMap (keys in byte order). A section value is `serde_json::to_string_pretty`; a datetime serializes as `{"$__toml_private_datetime": "<Display>"}`; NaN/inf become `null`; floats use ryu. A top-level scalar uses the Rust `Display` (f64 Display has no exponent).
    - TOML parser: dduan/TOMLDecoder 0.4.5 (newest tag, July 2026, TOML 1.1.0, pure Swift, no dependency). It parses lazily; `Dictionary(table)` validates every value. Its LocalTime loses two facts that toml_datetime displays (seconds omitted in TOML 1.1, and a zero fraction `.000` shown as `.0`); the port reads the time spelling from the source text for these. Known acceptance gap: toml accepts a leap second `:60`, TOMLDecoder refuses it.
    - Rust `create_default_registry` order: json, code, vue, yaml, toml, csv, markdown, fallback.
  timestamp: 2026-10-07T00:35:18.658627+00:00
- actor: claude-code
  id: 01m49z9tyj2kcesn8pzjna9r9y
  text: |-
    ### Discoveries

    - `json.rs`, `csv_plugin.rs`, `markdown.rs`, and `fallback.rs` use no parser crate. They scan the text. The port does the same, with no new dependency.
    - YAML: Yams 6.2.2 (already in the graph through FoundationModelsExtras). The plugin uses only its `CYaml` module (libyaml 0.2.5) and ports the loader and the serializer of serde_yaml_ng 0.10. One difference: unsafe-libyaml 0.2.11 reads a scalar above U+FFFF as printable, the C libyaml does not. Local work-around: `YAMLWideScalarMask` in `YAMLEmitter.swift`.
    - TOML: TOMLDecoder 0.4.5 (new, exact pin). Gaps with local work-arounds in `TOMLSourceScanner.swift`: the time spelling (`07:32`, `07:32:00.000`) and an integer out of the `i64` range (TOMLDecoder reads it as a float; Rust refuses the file).
    - Known gaps that stay (git.md "Data plugin gaps"): a leap second (TOMLDecoder refuses it), and one TOML file that writes the same time in two spellings (the first spelling is used for both).
    - The data plugins in Rust build each id with no parent, also for a Markdown heading that has a parent. `SemanticEntity.init(filePath:entityType:name:parentID:...)` does the same.
    - serde_json writes a float exponent with `+` (`1e+300`). `RustFloatText.serdeJSON` does this.
    - The old test `CodeParserPluginTests` "selects no plugin for another extension" changed: `.txt` now goes to the fallback plugin.
  timestamp: 2026-10-07T01:23:00.690886+00:00
- actor: claude-code
  id: 01m49z9x16rhwkertm4bk9rp47
  text: |-
    ### implement — changed
    - evidence: `swift build --build-tests` has no error and no new warning (one SwiftPM "missing creator" note for the mlx-swift bundle, not from this code). `swift test`: 2186 tests in 189 suites pass. `DataPluginEntityGoldenTests` (6 formats, Rust `pluginentities` output) and 34 new diff goldens in `CodeParserPluginGoldenTests` (json, yaml, toml, csv, markdown, text; Rust `semdiffgolden`, which also checked the inline mode of the tool for each case with one path) pass. Each golden has at most one `modified` change.
    - next: /review. Not committed and not pushed.
  timestamp: 2026-10-07T01:23:02.822946+00:00
- actor: claude-code
  id: 01m49zkrt18jjbz6fqnnh0dgrh
  text: |-
    ### test — green
    - evidence: swift build --build-tests OK. swift test: 2186 tests in 189 suites passed, 0 failed, 0 skipped. Fresh build of TOMLDecoder, Yams, FoundationModelsMultitool and test target (intermediates removed): no compiler warning, no resource warning for the golden folders. IntegrationTests swift build --build-tests OK (TOMLDecoder and FoundationModelsMultitool built fresh): no new warning.
    - only warning: "missing creator for mutated node" for mlx-swift_Cmlx.bundle. It is a known dependency warning. It is not counted as red.
    - next: review
  timestamp: 2026-10-07T01:28:26.177839+00:00
- actor: claude-code
  id: 01m49zmd3zrqjfagm81scczvps
  text: |-
    ### commit — changed
    - evidence: one local commit "feat: add JSON, YAML, TOML, CSV, Markdown, and fallback plugins to git semantic". It holds Package.swift, the plugin sources, the tests, the golden files, git.md, and all .kanban changes. No build product is staged. The sha is in the git log. No amend was done and no push was done.
    - next: none for this step
  timestamp: 2026-10-07T01:28:46.975106+00:00
- actor: claude-code
  id: 01m4a1aqfcq8epksbk3as0n9pe
  text: |-
    ### review — findings
    - evidence: `review sha HEAD~1..HEAD` (commit 6410c1b). The commit has no renames, so no file-scoped review was necessary. Counts: 12 findings, 16 confirmed, 4 refuted, 28 attempted, 0 failed. Findings: JSONParserPlugin.swift:200, JSONParserPlugin.swift:259, RustText.swift:96, TOMLSourceScanner.swift:51, TOMLSourceScanner.swift:187, TOMLValue.swift:196, YAMLEmitter.swift:75, YAMLEmitter.swift:100, YAMLParserPlugin.swift:98, YAMLScalarRules.swift:79, YAMLValue.swift:157, YAMLValue.swift:186.
    - next: Correct each finding in the "Review Findings (2026-10-06 20:29)" section. Remove each cause from the full file. Then run the review again.
  timestamp: 2026-10-07T01:58:27.052528+00:00
- actor: claude-code
  id: 01m4a1ber76xjab289jxcs2khn
  text: |-
    ### finish iteration 1 — findings
    - implement: changed — Package.swift, six data plugins and helpers in Git/Semantic/, test files, 34 diff goldens and entity goldens, git.md
    - test: green — swift test, 2186 passed in 189 suites; fresh build of TOMLDecoder and Yams has no warning; IntegrationTests build complete
    - commit: 6410c1b
    - review: findings — JSONParserPlugin.swift:200, JSONParserPlugin.swift:259, RustText.swift:96, TOMLSourceScanner.swift:51, TOMLSourceScanner.swift:187, TOMLValue.swift:196, YAMLEmitter.swift:75, YAMLEmitter.swift:100, YAMLParserPlugin.swift:98, YAMLScalarRules.swift:79, YAMLValue.swift:157, YAMLValue.swift:186 (all in Sources/FoundationModelsMultitool/Capabilities/Git/Semantic/)
  timestamp: 2026-10-07T01:58:50.887449+00:00
- actor: claude-code
  id: 01m4a1tjbv3txdmdqgy5shj9cj
  text: |-
    Review findings (2026-10-06 20:29) are corrected. What changed:
    - New `NumberRadix.swift` (Git/Semantic): `binary`, `octal`, `decimal`, `hexadecimal`. It replaces the radix numbers in RustText, TOMLValue (JSONText), TOMLSourceScanner, and YAMLScalarRules, and the local `decimalBase`/`decimalRadix` constants in those files.
    - JSONParserPlugin: for-in loop in place of `forEach`; `rootDepth`/`entryValueDepth` in place of the depth numbers; `extractEntities` is now a `compactMap` over a new helper `entity(of:lines:boundary:filePath:)` and gives no entity when one entry fails (same as the old early `return []`).
    - RustText.debugQuoted and JSONText.quoted: `map` + `joined` over a per-scalar helper, not a `var` accumulator.
    - TOMLSourceScanner: `escapeLength = 2` for the escape step.
    - TOMLTimeSpellings: `spellings` is a `let`, built with `Dictionary(_:uniquingKeysWith:)` that keeps the first spelling (same rule as before).
    - YAMLEmitter: `var used: Set<Unicode.Scalar> = []`; `masks`/`originals` are `let`, built from `zip(wide, free)` (zip stops when no free private use scalar is left, same as the old `break`); `replacing` uses `map`.
    - YAMLParserPlugin.valueTexts: `Dictionary(_:uniquingKeysWith: { _, later in later })` (a later key with the same text wins, as in the Rust `HashMap`), with a helper `keyText(of:)`. `uniqueKeysWithValues` is not correct here, because two keys can have the same text.
    - YAMLNumber: the unused `init(_ value: Int64)` is removed; `positiveHashKind`/`negativeHashKind`/`floatHashKind` name the hash numbers.
    Scan of every Swift file that 6410c1b added (sources and tests), with the tools of the rules: swiftlint `no_magic_numbers` (allowed 0, 1, -1, 100) gives 0; `swift format lint` with the 7 idiom rules gives 0; periphery 3.8.0 (index store `.build/out`, `--retain-public`, tests report-excluded) gives no finding in an added file.
    Not changed, on purpose: the `var` collections in the stateful scanners (TOMLSourceScanner.timeLiterals, TOMLParserPlugin.entries, MarkdownSection.sections, CSVParserPlugin.cells, YAMLLoader sequence/mapping/events). Each loop moves an index or a state that the next step reads, so a `map` over a collection cannot replace it.
    Discovery: periphery reports "Superfluous ignore comment" for `parentID` and `metadata` in SemanticEntity.swift (a file that 6410c1b changed, not added; the markers are older). Not changed in this pass.
  timestamp: 2026-10-07T02:07:06.107127+00:00
- actor: claude-code
  id: 01m4a1tn2zwqz8faajb1nq62n6
  text: |-
    ### implement — changed
    - evidence: 10 files — Git/Semantic/NumberRadix.swift (new), JSONParserPlugin.swift, RustText.swift, TOMLSourceScanner.swift, TOMLValue.swift, YAMLEmitter.swift, YAMLParserPlugin.swift, YAMLScalarRules.swift, YAMLValue.swift, and this task (12 of 12 findings checked). `swift build --build-tests`: Build complete, only the known mlx-swift "missing creator" note. `swift test`: 2186 tests in 189 suites passed, all goldens included.
    - next: /review. Not committed and not pushed.
  timestamp: 2026-10-07T02:07:08.895414+00:00
- actor: claude-code
  id: 01m4a1z4qd6n6vgmkb3wj5pjmp
  text: |-
    ### test — green
    - evidence: swift build --build-tests: Build complete, 0 errors. swift test: 2186 tests in 189 suites passed, 0 failed, 0 skipped. IntegrationTests swift build --build-tests: Build complete.
    - warnings: only the known "missing creator for mutated node" for mlx-swift_Cmlx.bundle (dependency warning, not from this change). No other warnings.
    - next: review
  timestamp: 2026-10-07T02:09:35.981512+00:00
- actor: claude-code
  id: 01m4a1zpv4pj44fdph0ezn5szc
  text: |-
    ### commit — changed
    - evidence: one local commit, subject "refactor: fix 12 review findings in git semantic parsers". It holds NumberRadix.swift, the changed files in Capabilities/Git/Semantic/, and the .kanban/ changes. No build product is staged. No push was done.
    - next: review. Read the sha with `git log -1`. The sha is not in this comment, because the comment is part of the commit.
  timestamp: 2026-10-07T02:09:54.532171+00:00
- actor: claude-code
  id: 01m4a2e3qphjz560fyn8fengee
  text: |-
    ### review — findings
    - evidence: `review sha HEAD~1..HEAD` (commit bb2d8f7). The commit renames no file. Counts: 5 findings, 5 confirmed, 1 refuted. All 12 items of the 2026-10-06 20:29 section are checked. New open items: RustText.swift:91, RustText.swift:97, TOMLValue.swift:191 (duplication), TOMLValue.swift:191 (idioms), TOMLValue.swift:239.
    - next: Fix the 5 items in the section "Review Findings (2026-10-06 21:10)". Then commit and review again. The task stays in `review`.
  timestamp: 2026-10-07T02:17:46.486369+00:00
- actor: claude-code
  id: 01m4a2ekac7ydnw8cvh3z296ga
  text: |-
    ### finish iteration 2 — findings
    - implement: changed — 9 source files (NumberRadix.swift new, 8 changed); 12 findings of 2026-10-06 20:29 checked
    - test: green — swift test, 2186 passed in 189 suites; IntegrationTests build complete
    - commit: bb2d8f7
    - review: findings — RustText.swift:91, RustText.swift:97, TOMLValue.swift:191 (duplication), TOMLValue.swift:191 (idioms), TOMLValue.swift:239 (all in Sources/FoundationModelsMultitool/Capabilities/Git/Semantic/)
  timestamp: 2026-10-07T02:18:02.444377+00:00
- actor: claude-code
  id: 01m4a2y2yre5jers3cnxk9rp7q
  text: |-
    The review findings of 2026-10-06 21:10 are corrected. Each cause is removed from every Swift file in Capabilities/Git/Semantic/.
    - Shared quote function: `RustText.quoted(_:escapingEach:)`. `RustText.debugQuoted` calls it with `Self.debugText(of:)`. `JSONText.quoted` calls it with `Self.escapedText(of:)`. No other copy of the quote-and-escape logic stays. New test file Tests/FoundationModelsMultitoolTests/RustTextTests.swift (4 tests: the shared function, the empty text, the Rust Debug escapes, the serde_json escapes). RED: "type 'RustText' has no member 'quoted'". GREEN: 4 of 4 pass.
    - Labeled function references: RustText (`isWhitespace(_:)` two times), TOMLValue (`Self.spelling(of:)`, `Self.nanoseconds(_:)`), VueParserPlugin (`tagNameTerminators.contains(_:)`), MarkdownParserPlugin (`RustText.isWhitespace(_:)`), YAMLEmitter (`Unicode.Scalar.init(_:)`), CodeParserPlugin (`TreeSitterSyntaxNode.init(node:)`, `Self.init(node:)` three times), YAMLScalarRules (`isDigit(_:)` three times).
    - Early-return `if let` changed to `guard let`: RustText.debugText (new helper `unicodeDebugText(of:)`), JSONText.escapedText (new helper `controlEscapedText(of:)`), YAMLScalarRules.integer (new helpers `signedInteger`, `wideInteger`) and the two radix loops (`else { continue }`), YAMLLoader `value(at:...)` (three switch cases) and `value(of:isTaggedAlready:)` (new helper `untaggedValue(of:)`), ParserRegistry.plugin(forFilePath:), EntityMatcher.defaultSimilarity (new helper `jaccardIndex`), EntityNameReader.name(of:), templateDeclarationName, and DeclaringCallReader.name(declaredBy:) (new helper `argumentName(declaredBy:...)`).
    - Not changed, on purpose: `first(where: isClosing)` in VueParserPlugin and `map(escapedText)` in the shared function. Each is a closure value (a local constant and a parameter), not a declared function, so it has no argument labels to write. `if let end = ... { index = end; continue }` in TOMLSourceScanner is a loop step, not an early return. The other `if let` in the folder do not return.
  timestamp: 2026-10-07T02:26:29.976480+00:00
- actor: claude-code
  id: 01m4a2y7va8yp127734v29efe1
  text: |-
    ### implement — changed
    - evidence: 13 files — Git/Semantic/RustText.swift, TOMLValue.swift, YAMLScalarRules.swift, YAMLLoader.swift, EntityNameReader.swift, EntityMatcher.swift, ParserRegistry.swift, CodeParserPlugin.swift, VueParserPlugin.swift, MarkdownParserPlugin.swift, YAMLEmitter.swift, Tests/FoundationModelsMultitoolTests/RustTextTests.swift (new), and this task (5 of 5 findings of 2026-10-06 21:10 checked, 17 of 17 in total). `swift build --build-tests`: Build complete, only the known mlx-swift "missing creator" note. `swift test`: 2190 tests in 190 suites passed, all goldens included.
    - next: /review. Not committed and not pushed.
  timestamp: 2026-10-07T02:26:34.986634+00:00
- actor: claude-code
  id: 01m4a32d3zcs88453ff7thpfts
  text: |-
    ### test — green
    - evidence: swift build --build-tests: build complete. swift test: 2190 tests in 190 suites passed, 0 failed, 0 skipped. IntegrationTests swift build --build-tests: build complete.
    - warnings: only the known mlx-swift_Cmlx.bundle "missing creator for mutated node" warning. It is a dependency warning from before this change.
    - next: review
  timestamp: 2026-10-07T02:28:51.455485+00:00
- actor: claude-code
  id: 01m4a32y76b2766epfjh0enz55
  text: |-
    ### commit — changed
    - evidence: One commit holds the fixes for the 5 review findings of 2026-10-06 21:10. Subject: "refactor: fix 5 review findings in git semantic parsers". The sha is in git log. An amend would change it, so this comment does not name it.
    - files: 11 Swift files in Capabilities/Git/Semantic, new RustTextTests.swift, and .kanban changes. No build product is staged (.build is ignored).
    - next: review
  timestamp: 2026-10-07T02:29:08.966465+00:00
depends_on:
- 01M48V9CB973V4MPTJV8GEXZCT
position_column: doing
position_ordinal: '80'
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
- Each golden passes.

## Review Findings (2026-10-06 20:29)

> Scope: `review sha HEAD~1..HEAD` — reviewed the diffs only — lines this change added or modified. 29 file(s) reviewed, 125 not reviewed.

> 4 file(s) not reviewed — excluded by an ignore rule:
> - `.kanban/ (from .reviewignore)` — 4 file(s)

> 121 file(s) not reviewed — no validator matched:
> - `Tests/FoundationModelsMultitoolTests/GitSemanticGoldens/**` (golden fixtures: `after.txt`, `before.txt`, `expected.json`, `entities/*.json`) — 120 file(s), no validator matches these files
> - `git.md` — no validator matches this file

- [x] `Sources/FoundationModelsMultitool/Capabilities/Git/Semantic/JSONParserPlugin.swift:200` `code-hygiene/idioms-swift` — ReplaceForEachWithForLoop: replace use of '.forEach { ... }' with for-in loop.
- [x] `Sources/FoundationModelsMultitool/Capabilities/Git/Semantic/JSONParserPlugin.swift:259` `code-hygiene/magic-numbers-swift` — Magic numbers should be replaced by named constants.
- [x] `Sources/FoundationModelsMultitool/Capabilities/Git/Semantic/RustText.swift:96` `code-hygiene/magic-numbers-swift` — Magic numbers should be replaced by named constants.
- [x] `Sources/FoundationModelsMultitool/Capabilities/Git/Semantic/TOMLSourceScanner.swift:51` `code-hygiene/magic-numbers-swift` — Magic numbers should be replaced by named constants.
- [x] `Sources/FoundationModelsMultitool/Capabilities/Git/Semantic/TOMLSourceScanner.swift:187` `code-hygiene/magic-numbers-swift` — Magic numbers should be replaced by named constants.
- [x] `Sources/FoundationModelsMultitool/Capabilities/Git/Semantic/TOMLValue.swift:196` `code-hygiene/magic-numbers-swift` — Magic numbers should be replaced by named constants.
- [x] `Sources/FoundationModelsMultitool/Capabilities/Git/Semantic/YAMLEmitter.swift:75` `swift/idioms` — Empty-collection variables must use a literal with a type annotation, not a call. This code uses `var used = Set<Unicode.Scalar>()` which is the non-idiomatic form. Change to `var used: Set<Unicode.Scalar> = []`.
- [x] `Sources/FoundationModelsMultitool/Capabilities/Git/Semantic/YAMLEmitter.swift:100` `swift/immutability` — Building a collection through a mutable accumulator in a loop should be replaced with `map`/`compactMap`. This code uses `var result = String.UnicodeScalarView()` followed by a loop that appends to it. Rewrite to use functional composition: `let result = String(text.unicodeScalars.map { replacements[$0] ?? $0 })`.
- [x] `Sources/FoundationModelsMultitool/Capabilities/Git/Semantic/YAMLParserPlugin.swift:98` `swift/immutability` — Building a collection through a mutable accumulator in a loop should be replaced with `map`/`compactMap`. This code uses `var texts: [[UInt8]: (text: String, isSection: Bool)] = [:]` followed by a for loop that assigns to it. Rewrite using `Dictionary(uniqueKeysWithValues:)` with a map over `mapping.entries` instead of mutating a local dictionary in a loop.
- [x] `Sources/FoundationModelsMultitool/Capabilities/Git/Semantic/YAMLScalarRules.swift:79` `code-hygiene/magic-numbers-swift` — Magic numbers should be replaced by named constants.
- [x] `Sources/FoundationModelsMultitool/Capabilities/Git/Semantic/YAMLValue.swift:157` `code-hygiene/dead-code-swift` — function.constructor `init(_:)` is unused.
- [x] `Sources/FoundationModelsMultitool/Capabilities/Git/Semantic/YAMLValue.swift:186` `code-hygiene/magic-numbers-swift` — Magic numbers should be replaced by named constants.

## Review Findings (2026-10-06 21:10)

> Scope: `review sha HEAD~1..HEAD` — reviewed the diffs only — lines this change added or modified. 9 file(s) reviewed, 2 not reviewed.

> 2 file(s) not reviewed — excluded by an ignore rule:
> - `.kanban/ (from .reviewignore)` — 2 file(s)

- [x] `Sources/FoundationModelsMultitool/Capabilities/Git/Semantic/RustText.swift:91` `swift/idioms` — Function reference passed to `map` does not match the labeled parameter syntax. The function `debugText(of:)` defined at line 96 has a labeled parameter `of`, but the call `map(debugText)` omits the label and partial application syntax required for labeled parameters. Use `map { Self.debugText(of: $0) }` or `map(Self.debugText(of:))` to correctly pass the labeled function to map.
- [x] `Sources/FoundationModelsMultitool/Capabilities/Git/Semantic/RustText.swift:97` `swift/optionals` — Early-return optional binding uses `if let` instead of `guard let`. The pattern at lines 97-99 binds an optional and returns early; this should use `guard let` to keep the happy path unindented and state the requirement at the head of the scope. Refactor to `guard let escape = debugShortEscapes[scalar] else { /* handle the rest of the logic */ }` followed by `return escape`.
- [x] `Sources/FoundationModelsMultitool/Capabilities/Git/Semantic/TOMLValue.swift:191` `duplication/duplication` — Changed-set duplicate of `RustText.debugQuoted`: identical function body except for the name of the escaping helper passed to map. This is one function with an argument waiting to be extracted. Extract a generic function (e.g. `quotedWith`) that takes the text and a callback for escaping each scalar, call it from both `RustText.debugQuoted` and `TOMLValue.quoted`, and delete the duplicate body. This eliminates the risk of the two diverging if one copy is updated and the other is not.
- [x] `Sources/FoundationModelsMultitool/Capabilities/Git/Semantic/TOMLValue.swift:191` `swift/idioms` — Function reference passed to `map` does not match the labeled parameter syntax. The function `escapedText(of:)` defined at line 196 has a labeled parameter `of`, but the call `map(escapedText)` omits the label and partial application syntax required for labeled parameters. Use `map { escapedText(of: $0) }` or `map(escapedText(of:))` to correctly pass the labeled function to map.
- [x] `Sources/FoundationModelsMultitool/Capabilities/Git/Semantic/TOMLValue.swift:239` `swift/idioms` — Function reference passed to `map` does not match the labeled parameter syntax. The function `spelling(of:)` defined at line 244 has a labeled parameter `of`, but the call `map(Self.spelling)` omits the label and partial application syntax required for labeled parameters. Use `map { Self.spelling(of: $0) }` or `map(Self.spelling(of:))` to correctly pass the labeled function to map. #git