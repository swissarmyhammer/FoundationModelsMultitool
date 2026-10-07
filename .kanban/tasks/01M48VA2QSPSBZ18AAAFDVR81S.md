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
- actor: claude-code
  id: 01m499hd9ve5ftr5bz4v2bctaj
  text: |-
    ### decision — use the current grammar versions
    - The user decided (2026-10-06): use JavaScript 0.25 and Python 0.25, the same versions as the Rust crate. Do not use the older 0.23 tags. See git.md decision 12.
    - The 0.25 packages do not link as a SwiftPM dependency: their manifests add `src/scanner.c` only when `FileManager.default.fileExists(atPath: "src/scanner.c")` is true, and that path is relative to the build folder. This task must work around that bug.
    - The workaround must need no host step and must publish nothing (no GitHub fork) without the user's approval. A local C target that holds the 0.25 `parser.c`, `scanner.c`, and headers of each grammar, with its license file, is one workaround that fits.
    - The open question in the earlier comment is closed. Do not add the tag `stuck` for it.
  timestamp: 2026-10-06T19:02:40.187988+00:00
- actor: claude-code
  id: 01m49jtv5ab16chch53ewsay7b
  text: |-
    Research done.
    - Rust Cargo.lock grammar versions: tree-sitter-typescript 0.23.2 (equal to the git.md table, thus a normal SwiftPM dependency), tree-sitter-javascript 0.25.0, tree-sitter-python 0.25.0 (decision 12: local C targets).
    - The cargo crates javascript 0.25.0 and python 0.25.0 come from the upstream commits 44c892e0 and 293fdc02 (`.cargo_vcs_info.json`). These are the tags v0.25.0 of tree-sitter/tree-sitter-javascript and tree-sitter/tree-sitter-python. `src/parser.c`, `src/scanner.c`, `src/tree_sitter/*.h`, and `LICENSE` of each tag are byte-equal to the cargo crate. The Swift header is `bindings/swift/TreeSitterJavaScript/javascript.h` and `bindings/swift/TreeSitterPython/python.h` of the tag.
    - `languages.rs` ALL_CONFIGS order: typescript, tsx, javascript, python, go, rust, ... TypeScript and TSX come from one `typescript_family_config`. JavaScript claims `.js`, `.jsx`, `.mjs`, `.cjs`; Python claims `.py`.
    - The extractor port of ^6dgd0h1 already has `export_statement`, `lexical_declaration`, the variable declarator name, and the Python decorated definition. Thus the code plugin needs only the table entries.
    - `vue.rs`: the plugin splits the file into `template`, `script`, and `style` blocks by lines (each block is an `sfc_block` entity). It sends the inner text of a `<script>` block to the code plugin with the virtual path `<file>:script.ts` (lang ts or tsx) or `<file>:script.js`. It sets the parent of EACH inner entity to the block (also a method of a class), adds the block line offset, and builds the id again. Registry order in Rust: json, code, vue, ...
    - A change in a `<script>` block always modifies the block entity too. Thus the Vue script golden adds a function (block modified + function added), so that the golden has one `modified` change.
  timestamp: 2026-10-06T21:45:06.474304+00:00
- actor: claude-code
  id: 01m49p5smkesmvynq89e5b607a
  text: |-
    Implementation landed (tdd: RED was one run of `swift test --filter "CodeParserPlugin|VueParserPlugin"` with 73 issues, after a compile failure on the missing `VueParserPlugin` and an empty stub; GREEN was one run of the same filter, 24 tests in 3 suites pass, golden test 129 cases).
    - Package.swift: tree-sitter/tree-sitter-typescript exact 0.23.2 through `treeSitterGrammarPackage` (product `TreeSitterTypeScript`, modules `TreeSitterTypeScript` and `TreeSitterTSX`). Two local C targets `TreeSitterJavaScript` and `TreeSitterPython` (helper `localGrammarTarget(name:includedSources:)`), each with a doc comment that names the upstream repository, the tag `v0.25.0`, and the reason (scanner manifest defect, git.md note 1, decision 12). Each target holds the upstream `src/parser.c`, `src/scanner.c`, `src/tree_sitter/*.h`, `bindings/swift/.../*.h` (as `include/`), and `LICENSE`, byte-equal to the cargo crates of the Rust crate. No host step, nothing published.
    - DISCOVERY: the C compiler of a root package enables `-Wshorten-64-to-32`, and the Python `src/scanner.c` gives 3 such warnings (remote packages hide them; the JavaScript files give none). Fix with no change to the upstream file: the target excludes `src/scanner.c` and compiles `scanner_build.c`, which has `#pragma clang diagnostic ignored "-Wshorten-64-to-32"` and `#include "src/scanner.c"`. Rejected: `unsafeFlags` (breaks use as a dependency), swift-tools-version 6.2 `disableWarning` (manifest-wide change).
    - CodeLanguageConfig.swift: `typeScriptFamily(id:extensions:language:)` (port of `typescript_family_config`), entries typescript, tsx, javascript (`.js .jsx .mjs .cjs`), python; `all` order is the Rust ALL_CONFIGS order.
    - VueParserPlugin.swift: port of `vue.rs` (blocks, `script setup`, `script:<n>`, `lang` in double or single quotes, script entities through the code plugin at `<file>:script.ts|js`, each script entity gets the block as parent, line offset, rebuilt id). Lines use the Rust `str::lines` model: `EditMatch.lines(of:)` changed from `private` to internal for reuse (no behavior change). Trim uses the Unicode `White_Space` property (Rust `str::trim`). `ParserRegistry.makeDefault()` registers code, then Vue (Rust order).
    - Tests: VueParserPluginTests (13 tests; the 3 Rust tests ported, plus block rules). The expected values of the extra tests come from a throwaway Rust bin `vuecheck` that runs the real `VueParserPlugin`. CodeParserPluginTests: routing, extension list, table mapping for the new languages.
    - Goldens: 41 cases under GitSemanticGoldens/{typescript (9), tsx (7), javascript (7), jsx (7), python (9), vue (2)}. Expected JSON from the throwaway generator `semdiffgolden` (tree-sitter-typescript 0.23.2, javascript 0.25.0, python 0.25.0 in its Cargo.lock); it asserts at most one `modified` change, no parse error node, and inline-mode equality. The generator now accepts a `.vue` case (no grammar).
    - .reviewignore: the upstream files of the two local targets (src/, include/, LICENSE) are out of review; `scanner_build.c` stays in review.
    - git.md: "Spike result" paragraph for this task, table rows for JavaScript/JSX/Python, note 1 updated.
    - Environment note: the first IntegrationTests build failed on a broken checkout `IntegrationTests/.build/checkouts/FoundationModelsExtras` (only an empty `IntegrationTests/.build/index-build` tree, EPERM on remove by SwiftPM). I removed that folder; the next build was complete.
  timestamp: 2026-10-06T22:43:31.091920+00:00
- actor: claude-code
  id: 01m49p60rs5vy7mbmvqbvgp843
  text: |-
    ### implement — changed
    - evidence: Package.swift; .reviewignore; git.md; Sources/FoundationModelsMultitool/Capabilities/Files/EditMatch.swift; Sources/FoundationModelsMultitool/Capabilities/Git/Semantic/{CodeLanguageConfig,ParserRegistry,VueParserPlugin}.swift; Sources/TreeSitterJavaScript/ (upstream v0.25.0 files); Sources/TreeSitterPython/ (upstream v0.25.0 files + scanner_build.c); Tests/FoundationModelsMultitoolTests/{CodeParserPluginTests,CodeParserPluginGoldenTests,VueParserPluginTests}.swift; GitSemanticGoldens/{typescript,tsx,javascript,jsx,python,vue}/ (123 files: 41 cases). `swift package update` first. `swift build --build-tests`: complete, only the known mlx-swift_Cmlx.bundle "missing creator" line. `swift test`: 2118 tests in 182 suites passed, 0 failed. `swift build --build-tests --package-path IntegrationTests`: complete; only mlx-swift dependency warnings. No commit, no push.
    - next: /review
  timestamp: 2026-10-06T22:43:38.393655+00:00
- actor: claude-code
  id: 01m49tmtpjgpjtwyq3tw8et5h6
  text: |-
    ### test - green
    - evidence: `swift package update` ran first (the mlx-swift submodule checkout was incomplete, so I ran `git submodule update --init --recursive` in `.build/checkouts/mlx-swift`). `swift build --build-tests` on a fresh `.build/out`: build complete, 0 warnings in this repo. `TreeSitterJavaScript` and `TreeSitterPython` compiled from clean (parser.o, scanner.o, scanner_build.o) with 0 warnings. 0 resource warnings for the golden folder. `swift test`: 2118 tests in 182 suites passed, 0 failed, 0 skipped. `IntegrationTests`: `swift build --build-tests` complete, 0 warnings in this repo.
    - dependency warning only (known, not red): `missing creator for mutated node` for mlx-swift_Cmlx.bundle.
    - next: review.
  timestamp: 2026-10-07T00:01:38.002826+00:00
- actor: claude-code
  id: 01m49tnj3kpppzrs2h5jt9h4sz
  text: |-
    ### commit — changed
    - evidence: one local commit "feat: add TypeScript, TSX, JavaScript, JSX, Python, and Vue to git semantic" (sha is in the git log; no amend after this comment)
    - next: review. The commit is local only. It is not pushed.
  timestamp: 2026-10-07T00:02:01.971778+00:00
depends_on:
- 01M48V9SN2MNFZGXZ9R6DGD0H1
position_column: doing
position_ordinal: '80'
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