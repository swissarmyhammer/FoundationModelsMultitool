---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m0b78bqk8smhawfntahe6d4q
  text: |-
    ## Done, and one review finding class was refuted rather than obeyed

    Three sites corrected — `CLIArguments.direct`'s doc, `directFlag`'s doc and its `descriptionLines`, and `runDemo`'s `direct` parameter doc. Verified by running the shipped binary:

        $ swift run multitool-cli --help
          --direct     Run in direct mode: the registry vends runCode and wait alone,
                       with no searchTools tool; the snippet discovers tools via
                       help()/docs() instead.

    The premise checked against the code, not just against `README.md`: `makeSessionTools(librarian:)` returns `[MultiTool(registry: self), WaitTool()]` in direct mode (`MultiTool.swift:171`) and `[searchTools, runCode, WaitTool()]` otherwise (`:188`).

    Ungated `swift test` green, 59 tests / 11 suites. No executable line moved.

    ### The `swift/naming-clarity` findings were validator errors

    The first review pass raised two, both asking to write `searchToolsTool` where the code says `searchTools` — one in a doc sentence, one **inside `--help` output**. Both are wrong: `searchTools` is the `Tool`-protocol name (`SearchToolsTool.swift:65`, `public let name = "searchTools"`), which is what the model calls and what a CLI user reads. `SearchToolsTool` is the Swift type. Complying would have put a Swift type name into text a user cannot see or type.

    The rule graded declared Swift names and carried no scope statement, so it reached into prose and string literals. Fixed in `~/.validators/swift/rules/naming-clarity.md` with a scope bullet — matching the guard its sibling `doc-parameter-naming` already carries — and re-ran the same review: **0 findings**. The rule now refutes what it previously raised.

    ### One real defect found on the way, filed separately

    `Registry.affordances` omits `wait` in both modes while `makeSessionTools` mounts it in both — the same class as this card, one layer down, in a public value rather than a comment. Filed as `^01phnr8`; not fixed here because it moves a public value and two unit-test assertions with it.
  timestamp: 2026-08-18T19:58:28.083168+00:00
position_column: done
position_ordinal: cf80
title: multitool-cli says direct mode registers only runCode; it also vends wait
---
Direct mode takes discovery away and nothing else: `Registry.makeSessionTools(librarian:)` mounts `wait` in both modes, and `README.md` says so ("A direct-mode registry vends `runCode` and `wait` alone — direct mode takes discovery away, never detachment"). Three places in `Sources/multitool-cli/CLIRunner.swift` still say only `runCode` is registered:

- `CLIArguments.direct`'s doc: "only `multiTool`/`runCode` is registered with the session, no discovery".
- `CLIRunner.directFlag`'s `descriptionLines`, which is **user-facing `--help` output**: "Run in direct mode: only the runCode tool is registered with the session (no searchTools tool)".
- `runDemo`'s `direct` parameter doc: "only `multiTool` is registered with the session, `searchToolsTool` is omitted".

`CLIRunner.run(...)`'s own summary doc is already right — it says "`runCode` and `wait` alone under `--direct`" — so the file contradicts itself.

Found during the documentation-accuracy sweep on `^yzhpjab`/`^523qwcy`/`^mxjt7y5`. Left out of that sweep deliberately: it is a different cause (what direct mode drops), and the flag's `descriptionLines` is a shipped string a user reads, not a comment, so it was outside that pass's "documentation only, no executable code" constraint.

## Acceptance Criteria

- [ ] `--help` states what direct mode really vends
- [ ] No doc comment in `CLIRunner.swift` contradicts `run(...)`'s own summary
- [ ] `CLIArgumentTests`' usage-text assertions still hold, and ungated `swift test` is green