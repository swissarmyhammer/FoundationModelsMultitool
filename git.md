# git.md — The `git` capability: repository facts in code mode

Note: This document uses ASD-STE100 Simplified Technical English. Code
identifiers (for example `GitCapability`) and product names (for example
libgit2, tree-sitter) are technical names. They keep their usual form. Words
such as "mount", "render", "diff", and "blame" are technical verbs in this
project.

## Status of this document

This document was the design plan. The code of the capability has shipped.
When this document and the code or `README.md` are different, the code and
`README.md` are correct, and this document is the record of why.

## Goal

Add a `git` capability to MultiTool. The model can read the state of a git
repository from a `runCode` snippet, in the same way that it reads files with
`tools.files.*`:

```js
const changes = await tools.git.changes({});
const diffs = await Promise.all(
  changes.files.slice(0, 5).map(path => tools.git.diff({ left: `${path}@HEAD`, right: path })));
return { branch: changes.branch, parent: changes.parentBranch, diffs };
```

The verb names and the argument names in this example follow decision 9. The
fields of each result are not final.

## The source: what `swissarmyhammer` has

The source is in `../swissarmyhammer/crates/`. It has two layers.

### Layer 1: the MCP tool `git`

File: `swissarmyhammer-tools/src/mcp/tools/git/`. It is one MCP tool with an
`op` field. It has two operations.

1. `get changes` (`changes/mod.rs`). It lists the files that changed on a
   branch. The arguments are `branch` (optional, the default is the current
   branch) and `range` (optional, for example `HEAD~1..HEAD`). The result is
   `{ branch, parent_branch, range, files }`. The rules are:
   - When `range` is set, the tool uses the files of that range.
   - When the branch has a parent branch, the tool uses the files that changed
     since the merge-base with the parent. The parent comes from
     `find_merge_target_for_issue`.
   - When the branch has no parent and the tree is clean, the tool uses
     `HEAD~1..HEAD`. If that range fails (for example, a repository with one
     commit), the result is empty.
   - In all cases, the tool adds the uncommitted files: staged, unstaged,
     renamed, and untracked. It sorts the list and removes duplicates.
2. `get diff` (`diff/mod.rs`). It gives a semantic diff at the entity level
   (function, class, and other entities). It uses the `swissarmyhammer-sem`
   crate, which uses tree-sitter. It has three modes:
   - Inline text: `left_text`, `right_text`, and `language`.
   - File: `left` and `right`. Each one is a path or `path@ref`.
   - Automatic: no arguments. It finds the dirty and staged files and diffs
     them.

   The result is `{ summary: { files, added, modified, deleted, moved,
   renamed }, changes: [{ change_type, entity_type, entity_name, file_path,
   old_file_path?, structural_change?, entity_id, before_content?,
   after_content? }] }`.

### Layer 2: the crate `swissarmyhammer-git`

File: `swissarmyhammer-git/src/operations.rs` (about 2700 lines). It wraps
libgit2 (`git2`). The MCP tool uses only some of it. The public functions
include:

- Read: `get_current_branch`, `list_local_branches`, `branch_exists`,
  `get_status`, `is_working_directory_clean`, `get_latest_commit`,
  `get_changed_files_from_parent`, `get_changed_files_from_range`,
  `get_all_tracked_files`, `main_branch`, `find_merge_target_for_issue`,
  `blame_lines`.
- Write: `checkout_branch`, `delete_branch`, `commit`, `add_all`,
  `merge_branch`, `validate_branch_creation`.

## The target: how a capability looks in this package

The `files` capability is the model. See
`Sources/FoundationModelsMultitool/Capabilities/Files/FilesCapability.swift`
and `web.md`.

1. One noun (`files`) and a list of plain `FoundationModels.Tool` verbs. Each
   verb has a `@Generable` arguments struct and a `@Generable` result struct.
   The capability owns the whole `tools.<noun>` namespace.
2. One shared context (`FileContext`) goes to each verb. Thus the verbs are
   one session.
3. A builder short form (`MultiTool.Builder.withFiles(root:...)`). The
   capability is off by default.
4. A mistake that the model can correct does not throw. It comes back in band
   as a `correction` field in the result. A thrown error ends the turn.
5. A path goes through `PathGuard`. A path cannot go out of the session root.
6. `GitPatch.swift` already renders a `FileChangeSet` as a git-format patch.
   It is internal to the `files` capability.

## Proposed shape (draft)

- A new folder `Sources/FoundationModelsMultitool/Capabilities/Git/`.
- `GitCapability` with `noun = "git"`.
- `GitContext`: the root, the repository that contains the root, and the
  `PathGuard` boundary.
- `MultiTool.Builder.withGit(root:)`. Off by default.
- A new folder for the semantic diff engine (the port of
  `swissarmyhammer-sem`), for example
  `Sources/FoundationModelsMultitool/Capabilities/Git/Semantic/`.
- New dependencies in `Package.swift`: `swift-libgit2` (the same package and
  exact version as FoundationModelsExtras, decision 10), a tree-sitter Swift
  package, and one grammar package for each language. Each dependency gets a
  doc comment that says why, the same as the current dependencies. Decision
  15 replaces the tree-sitter packages with FoundationModelsCodeContext.
- Tests: unit tests make a temporary repository for each test. Golden tests
  compare the semantic diff of each language with the output of the Rust
  crate. Integration tests use the real model, and run in the 20-minute
  limit. A test does not assert a fixed model score.

### Verbs

| Path | Arguments | Result | Source |
|---|---|---|---|
| `tools.git.status` | none | staged, unstaged, untracked, and renamed files, and `branch` (the current branch; null for a detached HEAD) | `get_status`, `get_current_branch` |
| `tools.git.changes` | `branch?`, `range?` | `{ branch, parentBranch, range, files }` | `get changes` |
| `tools.git.diff` | `left?`, `right?`, `leftText?`, `rightText?`, `language?` | `{ summary, changes[] }` | `get diff` |
| `tools.git.log` | `ref?`, `path?`, `limit?` | commits: sha, author, date, subject | revwalk (new) |
| `tools.git.commit` | `ref?` | one commit: sha, author, date, full message, parents, changed files with +/- line counts | first-parent diff (new), the same as `git_show` of docker-agent |
| `tools.git.show` | `path`, `ref?` | the content of the file at the ref | blob read (new) |
| `tools.git.blame` | `path`, `startLine?`, `endLine?`, `rev?` | one row for each line: sha, author, date; at `rev`, or in the work folder when `rev` is omitted | `blame_lines` |
| `tools.git.branches` | none | local branches, the current branch, the main branch | `list_local_branches`, `main_branch` |

The fields of each result are not final. The first task for each verb
decides them.

### Proposed order of the tasks

1. Spike: add `swift-libgit2` (decision 10) and the tree-sitter packages.
   Build on macOS 27 with Swift 6. Prove that each C function and each grammar
   links.
2. `GitCapability`, `GitContext`, `withGit(root:)`, and a temporary-repository
   test helper.
3. `status` and `branches`.
4. `changes` (with the parent-branch rules of the source).
5. `show` and `log`.
6. `blame`.
7. The semantic engine: the model, the matcher, the differ, and the plugin
   registry.
8. The code plugin, one task for each group of languages.
9. The data plugins and the fallback plugin.
10. `diff` (the three modes) over the engine.
11. Integration tests with the real model, and the `README.md` section.

## Open questions

1. Scope of the verbs: only the two operations of the MCP tool (`changes`,
   `diff`), or also more of `swissarmyhammer-git` (for example `status`,
   `log`, `show`, `blame`, `branches`)?
2. Read-only, or also verbs that change the repository (`commit`, `add`,
   `checkout`)?
3. Engine: run the `git` command through `Subprocess`, link libgit2, or
   write pure Swift?
   - 3a. How to link libgit2: a vendored C target (libgit2 source in the
     package), a binary target (an `.xcframework` that we build), a system
     library target (Homebrew and `pkg-config`), or a Swift wrapper package?
   - 3b. Which Swift wrapper package? (Decided: see decision 5.)
4. Semantic diff: port the entity-level diff (needs a tree-sitter in Swift),
   or give a line diff (unified, in git format) only? (Decided: see
   decision 6.)
   - 4a. Which languages get an entity parser in the first release? The
     source has Rust, TypeScript, TSX, JavaScript, JSX, Python, Go, Java, C,
     C++, Ruby, C#, PHP, Fortran, Swift, Elixir, Bash, and the data formats
     JSON, YAML, TOML, CSV, Markdown, and Vue. (Decided: see decision 7.)
5. Relation to `files`: one shared root and `PathGuard`, or a separate root?
   (Decided: see decision 8.)
6. Names: verb names, argument names (`camelCase`), and result shapes.
   (Decided: see decision 9.)

All the open questions have a decision. The first run of the spike
(`^tjv0b4z`) found gaps in SwiftGitX and in the grammar packages. Decisions
10, 11, and 12 close them.

## Decisions

1. Scope of the verbs (question 1). The capability ports the two operations
   of the MCP tool (`changes` and `diff`). It also adds read verbs from
   `swissarmyhammer-git`: `status`, `log`, `show` (the content of a file at a
   ref, `path@ref`), `blame`, and `branches`. The verb list can change when
   we decide the names (question 6).
2. Read-only (question 2). The answer to question 1 did not select the write
   verbs. Thus the capability has no verb that changes the repository. The
   model changes files with `tools.files.*` and runs other git commands with
   `tools.shell.*`, when the host mounts those capabilities.
3. Engine (question 3). The capability links libgit2. This is the same engine
   that `swissarmyhammer-git` uses, thus the port can follow its logic step by
   step. The capability does not need the `git` command on the machine. The
   method to link libgit2 into this package is open question 3a.
4. Link method (question 3a). The package depends on a public Swift wrapper
   package for libgit2. We do not vendor libgit2 and we do not build a binary.
   The selection of the wrapper is open question 3b. The candidates are:
   - `ibrahimcetin/SwiftGitX`: a high-level Swift API with `async`/`await`.
     It hides all C types.
   - `swift-developer-tools/swift-libgit2`: memory-safe Swift bindings to the
     full libgit2 C API.
   - `SwiftGit2/SwiftGit2`: the older bindings.
   - `Formkunft/swift-libgit2`: a SwiftPM package of libgit2 itself.
   Before we select, a spike must make sure that the wrapper builds on macOS
   27 with Swift 6 strict concurrency, and that it gives status, merge-base,
   tree diff, revwalk (log), blob read at a ref, and blame.
5. Wrapper (question 3b). REPLACED by decision 10. The first choice was
   `ibrahimcetin/SwiftGitX`. The spike found that it cannot go into this
   package (a `libgit2` target-name conflict), and that it does not have five
   functions that the verbs need. See "Spike result".
6. Semantic diff (question 4). `tools.git.diff` ports the entity-level diff
   of `swissarmyhammer-sem` now. It does not give a line diff only.
   - The source crate `swissarmyhammer-sem` has about 13400 lines. The diff
     path needs only a part of it: `model/` (entity, change, identity match,
     about 800 lines), `parser/differ.rs`, `parser/registry.rs`,
     `parser/plugin.rs`, the code plugin (`entity_extractor.rs`,
     `languages.rs`, and the extraction part of `code/mod.rs`), and the data
     plugins (`json`, `yaml`, `toml`, `csv`, `markdown`, `vue`, `fallback`).
   - The diff does not need `duplication.rs`, `commented_code.rs`,
     `graph.rs`, `test_census.rs`, `public_surface.rs`, or `definitions.rs`.
     Those serve the `code_context` tool. We do not port them.
   - The parser in Swift is tree-sitter, through a Swift package (for example
     `ChimeHQ/SwiftTreeSitter`), and one grammar package for each language.
     The language set is open question 4a. Decision 15 moves the parse to
     FoundationModelsCodeContext: this package does not parse.
   - Each verb that reads a file at a ref (`diff` with `path@ref`, `show`,
     `blame` with `rev`) reads the blob through libgit2 (decision 10).
7. Languages (question 4a). The first release has the language set of
   `swissarmyhammer-sem`: Rust, TypeScript, TSX, JavaScript, JSX, Python, Go,
   Java, C, C++, Ruby, C#, PHP, Swift, Elixir, Bash, and the data formats
   JSON, YAML, TOML, CSV, Markdown, and Vue. Decision 13 removes one language
   of the Rust set. The `fallback` plugin is for all other files. The spike must find a SwiftPM package for each
   tree-sitter grammar, and must report each grammar that has no package.
   Result: each code grammar has a package that links. Three of them link
   only at an older tag. CSV and Vue have no usable package. See "Spike
   result".
8. Root (question 5). `MultiTool.Builder.withGit(root:)` takes its own root.
   It does not need the `files` capability. `GitContext` holds that root and
   one `PathGuard` with the same rules as `files`. Each path argument goes
   through the guard. The repository is the one that contains the root (the
   root can be a subfolder of the repository). Each path in a result is
   relative to the root. One exception (task `^5a8vaqk`): a path that reads
   history (`show`, `log`, `blame` with `rev` (task `^t9rh6bn`), and `diff`
   with `path@ref`) goes through the guard with `absentFolders: .accepted`.
   Thus a folder that a later commit removed is not refused. All the other
   guard checks stay the same, and a path still cannot go out of the root.
9. Names (question 6). Each verb uses the word of the git command. Each
   argument name and each result field name uses `camelCase`, the same as
   `tools.files.*`. `diff` is one verb with three modes, the same as the
   source. See "Verbs" for the list.
10. libgit2 (replaces decision 5). The capability uses the libgit2 that is
    already in the dependency graph: `danielctull-forks/swift-libgit2`, product
    `libgit2`, `exact: "1.9.7"`. FoundationModelsExtras declares the same
    package and the same exact version for its `Marketplace` target, thus
    SwiftPM resolves one copy and there is no name conflict. The package
    compiles libgit2 from C source, thus there is no binary and no host setup.
    - `Package.swift` declares the package with the same URL and the same
      exact version as FoundationModelsExtras, and the library target links
      the `libgit2` product. The doc comment says that the version must stay
      equal to the version in FoundationModelsExtras.
    - The code calls the C API directly (`import libgit2`). There is no
      SwiftGitX. All the functions that the verbs need are in the C API:
      `git_repository_discover` and `git_repository_open_ext`,
      `git_status_list_new`, `git_branch_iterator_*`, `git_merge_base`,
      `git_revparse_single` and `git_revparse` (ranges), `git_diff_tree_to_tree`,
      `git_revwalk_*` with a pathspec, `git_blob_lookup` through
      `git_object_lookup_bypath`, and `git_blame_file`.
    - One internal Swift layer in `Capabilities/Git/LibGit2/` holds all the C
      calls. It owns each C pointer (free in `deinit` or `defer`), changes each
      negative return code into a Swift error with the text of `git_error_last`,
      and calls `git_libgit2_init` one time. No verb calls the C API directly.
      `Marketplace/Git/LibGit2Transport.swift` in FoundationModelsExtras is a
      model for the init call and the error text.
    - A verb changes a libgit2 error into a `correction` in its result when the
      model can correct it (an unknown ref, an unknown path), and throws only
      for a fault that the model cannot correct.
    - The libgit2 objects are not `Sendable`. Each verb opens, uses, and frees
      them inside one call. `GitContext` holds the root and the path of the
      repository, not an open handle.
    - The same rule applies to the tree-sitter packages: one package of the
      family declares them. That package is FoundationModelsCodeContext, and
      this package links no tree-sitter package (decision 15).
11. Grammars after the spike (decision 7). CSV and Vue need no tree-sitter
    grammar: the Rust plugins `csv_plugin.rs` and `vue.rs` do not use one, and
    the port follows them. Swift uses the exact tag `0.7.4-with-generated-files`.
    JavaScript, Python, and YAML: see decision 12.

12. Grammar versions (2026-10-06, the user decided). Use the current grammar
    versions, the same as the Rust crate: JavaScript 0.25 and Python 0.25. Do
    not use the older 0.23 tags. The 0.25 packages do not link as a SwiftPM
    dependency (see note 1 of "Tree-sitter packages"), thus the task
    `^fdvr81s` must work around that bug. The workaround must not need a step
    on the host and must not publish anything (for example a GitHub fork)
    without the user's approval. A local C target that holds the 0.25
    `parser.c`, `scanner.c`, and headers of each grammar, with its license
    file, is an example of a workaround that fits. YAML needs no grammar,
    because the Rust `yaml.rs` uses none.
    Decision 15 moves these local targets to FoundationModelsCodeContext.
    This package has no grammar target now.

13. Fortran (2026-10-06, the user decided): drop Fortran. With grammar 0.6.0
    the Rust crate finds no Fortran entity (the grammar keeps each name in a
    `*_statement` child, where the Rust name reader does not look), thus
    Fortran support gave no value. The port removes the Fortran grammar
    dependency, the `fortran` table entry, and the Fortran goldens (task
    `^q102ags`). A `.f90` file then goes to the fallback plugin. This changes
    decision 7: the language set has no Fortran.

14. Data parsers (task `^p9b4cm5`). The JSON, CSV, Markdown, and fallback
    plugins need no parser package: the Rust plugins scan the text
    themselves (`json.rs` also does not use `serde_json`), and the port scans
    it in the same way with the Swift standard library. YAML and TOML need a
    parser that Foundation does not have:
    - YAML: Yams 6.2.2 (`https://github.com/jpsim/Yams`), product `Yams`. The
      plugin uses only its C module `CYaml`: libyaml 0.2.5, the same libyaml
      that serde_yaml_ng 0.10 runs through unsafe-libyaml 0.2.11. The Swift
      code ports the loader and the serializer of serde_yaml_ng on the libyaml
      events, thus the value, the scalar rules, and the written text are the
      same as in Rust.
    - TOML: TOMLDecoder 0.4.5 (`https://github.com/dduan/TOMLDecoder`),
      product `TOMLDecoder`. It is maintained, has no dependency, and reads
      TOML 1.1 (a time with no seconds), as the `toml` crate 1.1.2 does.
    The doc comments of `yamlPackage` and `tomlPackage` in `Package.swift`
    give the same reasons. No step on the host and no fork is necessary.

15. Code entities from FoundationModelsCodeContext (2026-10-07, the user
    decided, task `^jyv2we6`). FoundationModelsCodeContext owns all
    tree-sitter work: the runtime, the grammars, the parse, and the read of
    the entities of a source file. This package does not parse and links no
    tree-sitter package and no grammar. It does not get grammars from
    CodeContext. The code plugin calls the public API
    `CodeEntities.entities(in:filePath:)` and gives each `CodeEntity` to the
    diff as a `SemanticEntity` with the same values. Its extensions are
    `CodeEntities.supportedFileExtensions`. Each plugin hashes with
    `CodeEntities.contentHash(_:)`, thus the code entities and the data
    entities use one hash.
    - Reason: the two packages had two copies of the same grammars. The pins
      went out of step (tree-sitter-swift 0.7.3 against 0.7.4, PHP 0.25.0
      against 0.25.1), and the two packages declared the same target names
      `TreeSitterJavaScript` and `TreeSitterPython`. An ACP agent graph with
      both packages did not build.
    - CodeContext tests the parse (its `CodeEntitiesGoldenTests`). This
      package keeps `CodeParserPluginGoldenTests` and the
      `GitSemanticGoldens` diff goldens, with no change to a golden value.
    - `Package.swift` declares CodeContext through
      `swissArmyHammerPackage(name:)` on the `main` branch, the same as
      Router and Extras.

## Data plugin gaps

The data goldens (`GitSemanticGoldens/entities/` for the entities, and the
`json`, `yaml`, `toml`, `csv`, `markdown`, and `text` folders for the diff)
show the same result as the Rust crate. These differences stay, and each one
has a comment in the code:

1. TOML: TOMLDecoder refuses a leap second (`23:59:60`), which the `toml`
   crate accepts. For such a file the plugin gives no entity.
2. TOML: TOMLDecoder does not tell where a value is in the text. The plugin
   reads the spelling of each time (`07:32`, `07:32:00.000`) from the text
   (`TOMLSourceScanner`). When one file writes the same time in two
   spellings, the plugin uses the first spelling for both.
3. TOML: TOMLDecoder reads an integer out of the `i64` range as a float. The
   `toml` crate refuses it. `TOMLSourceScanner` finds such an integer in the
   text and the plugin refuses the file, as Rust does.
4. YAML: the C libyaml of Yams writes a scalar above U+FFFF (for example an
   emoji) with a `\U` escape; unsafe-libyaml writes it as it is. The
   emitter replaces each such scalar with a free private use scalar before
   libyaml reads it, and puts it back after (`YAMLWideScalarMask`).
5. YAML and the `Debug` text: Swift and Rust can use different Unicode
   versions. A scalar that only the newer version assigns can get a
   different escape.

## Open questions after the spike

None. Decision 12 closes the grammar-version question.

## Spike result

The spike (`^tjv0b4z`, 2026-10-06) used macOS 27, Swift 6.4, and
swift-tools-version 6.1. It ran two times.

- The first run tried SwiftGitX and the tree-sitter packages. SwiftGitX did
  not fit (see "First run: blocker" and "First run: SwiftGitX functions").
  The grammar table of the first run stays valid (see "Tree-sitter
  packages").
- The second run tried the C API of `swift-libgit2` (decision 10). Each C
  function works. There is no gap (see "libgit2 C API").

### libgit2 C API

`Package.swift` now declares `https://github.com/danielctull-forks/swift-libgit2.git`
with `exact: "1.9.7"`, the same URL and version as FoundationModelsExtras.
The library target links the product `libgit2` (`gitProducts`). The doc
comment of `libgit2Package` says that the version must stay equal to the
version in FoundationModelsExtras. SwiftPM resolves one copy of the package.
`swift build --build-tests` has no target-name conflict, no error, and no new
warning. The spike did not add the tree-sitter packages. The language tasks
add them: task `^6dgd0h1` added SwiftTreeSitter 0.25.0, the tree-sitter
runtime 0.25.10 (for UTF-8 byte offsets, the same as Rust), and the Rust, Go,
and Swift grammars. Task `^4ac64t6` added the Java, C, C++, C#, Ruby, and PHP
grammars. The Rust crate uses tree-sitter-php 0.24.2 and this package uses
0.25.0; the PHP goldens show no difference. Task `^bt90anx` added the
Elixir and Bash grammars, at the same versions as the Rust crate. That task
also added one more grammar, which decision 13 removes. Task `^fdvr81s`
added the TypeScript and TSX grammars (package 0.23.2), the
JavaScript and Python grammars at 0.25.0 (decision 12), and the Vue plugin,
all at the same versions as the Rust crate. The JavaScript and Python
grammars are local C targets, `Sources/TreeSitterJavaScript` and
`Sources/TreeSitterPython`: each holds the `src/` files, the Swift header,
and the license of the upstream tag `v0.25.0` with no change (the files are
byte-equal to the cargo crates of the Rust crate). The doc comments of
`treeSitterJavaScriptTargetName` and `treeSitterPythonTargetName` in
`Package.swift` give the reason (note 1 below). The C compiler of a root
package gives three `-Wshorten-64-to-32` warnings for the Python scanner,
thus the target compiles it through `scanner_build.c`, which stops that one
warning and includes the upstream file.

Task `^jyv2we6` removed all of these packages and the two local targets
from this package (decision 15). FoundationModelsCodeContext declares them
now.

A throwaway test (`import libgit2`, removed after the spike) made a temporary
repository with libgit2 only: commits c1, c2, c3 on `main` (c3 renames
`src/b.txt` to `src/c.txt`), commit c4 on `feature` from c2, a staged rename
`a.txt` to `a2.txt`, and an untracked file `u.txt`. All 9 tests passed.

| C function | Result | What the test saw |
|---|---|---|
| `git_libgit2_init` | Works | A start count above 0. |
| `git_repository_discover` from a subfolder | Works | From `src/`, the path `<root>/.git/`. |
| `git_repository_open_ext` from a subfolder | Works | `git_repository_workdir` is `<root>/`. |
| `git_status_list_new` with untracked files and rename detection | Works | `a.txt` to `a2.txt` as `GIT_STATUS_INDEX_RENAMED` (`head_to_index`), and `u.txt` as `GIT_STATUS_WT_NEW` (`index_to_workdir`). |
| `git_branch_iterator_new`, `git_branch_next`, `git_branch_name` | Works | `feature` and `main`. The loop stops at `GIT_ITEROVER`. |
| `git_repository_head`, `git_reference_shorthand` | Works | `main`. |
| `git_merge_base` | Works | The merge-base of c3 and c4 is c2. |
| `git_revparse_single` (`HEAD~1`, a short sha, a branch) | Works | c2, c1, and c4. |
| `git_revparse` (`HEAD~2..HEAD`) | Works | `GIT_REVSPEC_RANGE` is set. `from` is c1 and `to` is c3. |
| `git_diff_tree_to_tree` with `git_diff_find_similar` (`GIT_DIFF_FIND_RENAMES`) | Works | One delta, `GIT_DELTA_RENAMED`, `src/b.txt` to `src/c.txt`. |
| `git_revwalk_new`, `git_revwalk_push_head`, `git_revwalk_next` | Works | c3, c2, c1 with `GIT_SORT_TOPOLOGICAL`. |
| Log path filter: a tree diff to the first parent with `git_diff_options.pathspec` | Works | The path `a.txt` gives c2 and c1. |
| `git_object_lookup_bypath`, `git_blob_rawcontent`, `git_blob_rawsize` | Works | `a.txt` at `HEAD~2` is `one\ntwo\nthree\n`. |
| `git_blame_file` with `min_line` and `max_line` | Works | Lines 2 to 3: line 2 from c2, line 3 from c1 (`git_blame_hunkcount`, `git_blame_hunk_byindex`). |

How the `LibGit2` layer frees each C pointer:

| C value | Free call | Note |
|---|---|---|
| `git_repository *` | `git_repository_free` | |
| `git_buf` (from discover) | `git_buf_dispose` | |
| `git_status_list *` | `git_status_list_free` | Each entry and each `git_diff_delta` belong to the list. Copy the paths before the free. |
| `git_branch_iterator *` | `git_branch_iterator_free` | |
| `git_reference *` | `git_reference_free` | The text of `git_branch_name` and `git_reference_shorthand` belongs to the reference. |
| `git_object *` (revparse, peel, lookup by path) | `git_object_free` | The bytes of `git_blob_rawcontent` belong to the blob. Copy them before the free. |
| `git_revspec` | `git_object_free` on `from` and on `to` | |
| `git_diff *` | `git_diff_free` | Each `git_diff_delta` belongs to the diff. |
| `git_revwalk *` | `git_revwalk_free` | |
| `git_commit *`, `git_tree *` | `git_commit_free`, `git_tree_free` | |
| `git_blame *` | `git_blame_free` | Each `git_blame_hunk` belongs to the blame. |
| `git_oid` | none | It is a value. |

Error text: each call returns an `Int32`, and a value below 0 is an error.
`git_error_last()` is never NULL in libgit2 1.9. The layer reads its
`message` on the same thread, directly after the failed call, the same as
`LibGit2Transport.lastErrorMessage()` in FoundationModelsExtras. An iterator
ends with `GIT_ITEROVER`, which is not an error. Seen in the test:

- An unknown ref gives `GIT_ENOTFOUND` and "revspec 'no-such-ref' not found".
- An unknown path gives `GIT_ENOTFOUND` and "the path 'no' does not exist in
  the given tree". The text names only the first path component that is
  missing.

Facts for the next tasks:

1. libgit2 gives real paths, for example `/private/var/...`. On macOS,
   Foundation `URL.resolvingSymlinksInPath()` removes the `/private` prefix,
   thus a compare with a libgit2 path fails. `GitContext` must make the root
   canonical with `realpath`, or compare paths that are relative to the work
   folder.
2. `git_repository_init` named the first branch `main`, thus libgit2 read the
   user git configuration (`init.defaultBranch`). The temporary-repository
   helper must not depend on that name. It reads the name with
   `git_repository_head`, or it sets `HEAD` itself.
3. The header still has the deprecated `git_blame_get_hunk_count` and
   `git_blame_get_hunk_byindex`. Use the 1.9 names `git_blame_hunkcount` and
   `git_blame_hunk_byindex`.
4. Swift sees each libgit2 handle as `OpaquePointer`. Thus the object from
   `git_object_lookup_bypath` goes directly into `git_blob_rawcontent`.

### First run: blocker: two libgit2 packages in one graph

SwiftGitX 0.4.0 depends on `ibrahimcetin/libgit2` `exact: 1.9.2`.
FoundationModelsExtras depends on `danielctull-forks/swift-libgit2`
`exact: 1.9.7` for its `Marketplace` target. Both packages declare a target
with the name `libgit2`. With SwiftGitX in `Package.swift`, `swift build`
stops with this error:

```
error: multiple packages ('libgit2', 'swift-libgit2') declare targets with a
conflicting name: 'libgit2'; target names need to be unique across the
package graph
```

This package does not link `Marketplace`, but SwiftPM rejects the graph all
the same. Alone (in its own checkout), SwiftGitX 0.4.0 builds with zero
warnings and zero errors. Its manifest is swift-tools-version 6.0, thus it
builds in the Swift 6 language mode.

### First run: SwiftGitX functions

The blocker stopped the build before a test could call SwiftGitX in this
package. Thus each row below comes from the source of SwiftGitX 0.4.0, not
from a test run.

| Function | SwiftGitX 0.4.0 API | Result |
|---|---|---|
| status: staged, unstaged, untracked, renamed | `Repository.status(options:)` with `.includeUntracked`, `.renamesIndex`, `.renamesWorkingTree`. `StatusEntry.status` has `indexRenamed` and `workingTreeRenamed`. | Found |
| current branch | `repository.branch.current` | Found |
| local branches | `repository.branch.list(.local)` or `repository.branch.local` | Found |
| branch exists | `repository.branch[name, type: .local]` (returns `nil` when it does not exist) | Found |
| merge-base of two commits | None. The package does not call `git_merge_base`. | GAP |
| tree-to-tree diff (file list) for a range | `Repository.diff(from:to:)` over two commits. It has no diff options (no rename detection, no pathspec). A range text such as `HEAD~1..HEAD` cannot be resolved, because there is no public revparse (see "read a blob at a ref"). | GAP (partial) |
| tree-to-tree diff for merge-base..HEAD | Needs merge-base. | GAP |
| revwalk (log) with a limit | `Repository.log(from:sorting:)` gives a `Sequence`; `.prefix(n)` gives the limit. | Found |
| revwalk (log) with a path filter | None. No pathspec and no path filter on the walk. | GAP |
| read a blob at a ref (`path@ref`) | `git_revparse_single` is only in the internal `ObjectFactory`. There is no public revparse for `HEAD~1`, a tag, or a short sha, and no lookup of a tree entry by a path. `Tree.entries` has one level only. `Repository.show(id:)` reads a blob when the OID is known. | GAP |
| blame with a line range | None. The package does not call `git_blame_*`. | GAP |
| open a repository from a subfolder | `Repository.open(at:)` and `init(at:)` call `git_repository_open`, which does not search the parent folders. No `git_repository_discover`. | GAP |

Fact for the decision: the C headers of the `libgit2` product under SwiftGitX
(and of `swift-libgit2` under FoundationModelsExtras) have each missing
function (`git_merge_base`, `git_blame_file`, `git_repository_discover`,
`git_revparse_single`, `git_revwalk_*`, pathspec).

### Tree-sitter packages

This section is the record of the spike. This package does not link these
packages now: FoundationModelsCodeContext declares them (decision 15).

SwiftTreeSitter: `https://github.com/ChimeHQ/SwiftTreeSitter` `0.25.0`
(product `SwiftTreeSitter`). It resolves `tree-sitter/tree-sitter` at
`0.25.10`. Some grammar manifests name it as
`tree-sitter/swift-tree-sitter`, but only their test targets use it, and
SwiftPM does not resolve those. Thus there is no conflict.

The spike linked each package below into one throwaway test target and parsed
one small file of each language. All 21 parses had no error node. The
grammars added no new build warning. The table does not show one grammar that
the spike linked, because decision 13 removes it.

| Language | Package URL | Version | Product (module) | Result |
|---|---|---|---|---|
| Rust | `https://github.com/tree-sitter/tree-sitter-rust` | 0.24.2 | `TreeSitterRust` | Links and parses |
| TypeScript | `https://github.com/tree-sitter/tree-sitter-typescript` | 0.23.2 | `TreeSitterTypeScript` (module `TreeSitterTypeScript`) | Links and parses |
| TSX | same as TypeScript | 0.23.2 | `TreeSitterTypeScript` (module `TreeSitterTSX`) | Links and parses |
| JavaScript | `https://github.com/tree-sitter/tree-sitter-javascript` | 0.23.1 | `TreeSitterJavaScript` | Links and parses. See note 1: the package uses 0.25.0 as a local target. |
| JSX | same as JavaScript (the grammar has JSX) | 0.23.1 | `TreeSitterJavaScript` | Links and parses. See note 1: the package uses 0.25.0 as a local target. |
| Python | `https://github.com/tree-sitter/tree-sitter-python` | 0.23.6 | `TreeSitterPython` | Links and parses. See note 1: the package uses 0.25.0 as a local target. |
| Go | `https://github.com/tree-sitter/tree-sitter-go` | 0.25.0 | `TreeSitterGo` | Links and parses |
| Java | `https://github.com/tree-sitter/tree-sitter-java` | 0.23.5 | `TreeSitterJava` | Links and parses |
| C | `https://github.com/tree-sitter/tree-sitter-c` | 0.24.2 | `TreeSitterC` | Links and parses |
| C++ | `https://github.com/tree-sitter/tree-sitter-cpp` | 0.23.4 | `TreeSitterCPP` | Links and parses |
| Ruby | `https://github.com/tree-sitter/tree-sitter-ruby` | 0.23.1 | `TreeSitterRuby` | Links and parses |
| C# | `https://github.com/tree-sitter/tree-sitter-c-sharp` | 0.23.5 | `TreeSitterCSharp` | Links and parses |
| PHP | `https://github.com/tree-sitter/tree-sitter-php` | 0.25.0 | `TreeSitterPHP` | Links and parses |
| Swift | `https://github.com/alex-pinkus/tree-sitter-swift` | `0.7.4-with-generated-files` | `TreeSitterSwift` | Links and parses. See note 2. |
| Elixir | `https://github.com/elixir-lang/tree-sitter-elixir` | 0.3.5 | `TreeSitterElixir` | Links and parses |
| Bash | `https://github.com/tree-sitter/tree-sitter-bash` | 0.25.1 | `TreeSitterBash` | Links and parses |
| JSON | `https://github.com/tree-sitter/tree-sitter-json` | 0.24.8 | `TreeSitterJSON` | Links and parses. See note 3. |
| YAML | `https://github.com/tree-sitter-grammars/tree-sitter-yaml` | 0.7.0 | `TreeSitterYAML` | Links and parses. See notes 1 and 3. |
| TOML | `https://github.com/tree-sitter-grammars/tree-sitter-toml` | 0.7.0 | `TreeSitterTOML` | Links and parses. See note 3. |
| Markdown | `https://github.com/tree-sitter-grammars/tree-sitter-markdown` | 0.5.3 | `TreeSitterMarkdown` | Links and parses. See note 3. |
| CSV | `https://github.com/tree-sitter-grammars/tree-sitter-csv` | none | none | GAP. Each tag (v1.0.0 to v1.2.0) has an invalid `Package.swift`: a comma is missing after `.copy("csv/queries")`. See note 3. |
| Vue | `https://github.com/tree-sitter-grammars/tree-sitter-vue` | none | none | GAP. No tag and no `Package.swift`. See note 3. |

Notes:

1. The newest tags of JavaScript (0.25.0), Python (0.25.0), and YAML (0.7.1,
   0.7.2) do not link. Their manifests add `src/scanner.c` only when
   `FileManager.default.fileExists(atPath: "src/scanner.c")` is true. That
   path is relative to the folder of the build, thus the scanner is not
   compiled when the package is a dependency. The link fails with undefined
   `tree_sitter_*_external_scanner_*` symbols. The older tags in the table
   list the scanner in the manifest and link. The Rust crate uses JavaScript
   0.25 and Python 0.25. Decision 12 selects 0.25, thus task `^fdvr81s` put
   the files of the tag `v0.25.0` of each grammar in a local C target of this
   package (`Sources/TreeSitterJavaScript`, `Sources/TreeSitterPython`). The
   Swift port and the Rust crate use the same JavaScript and Python
   grammars. Decision 15 moves the two targets to
   FoundationModelsCodeContext.
2. The tag `0.7.4` of tree-sitter-swift has no `src/parser.c`. Only the tag
   `0.7.4-with-generated-files` has it. A `from: "0.7.4"` rule selects the
   tag without the parser, thus the rule must be `exact:` on the
   `-with-generated-files` tag.
3. The Rust crate does not use tree-sitter for the data formats. `yaml.rs`
   uses serde_yaml_ng, `toml_plugin.rs` uses the `toml` crate, and
   `json.rs`, `csv_plugin.rs`, and `markdown.rs` scan the text themselves.
   `vue.rs` splits the blocks itself and sends each `<script>` block to the
   TypeScript or JavaScript code plugin. Thus the CSV and Vue gaps do not
   stop a port that follows the Rust crate. Decision 14 selects the Swift
   parser for YAML and TOML.
