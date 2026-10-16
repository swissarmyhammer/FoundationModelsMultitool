---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m525gvtg735g0av499bk7yt6
  text: |-
    Research done. Facts for the work:
    - JSCInterpreter installs a host function with context.setObject(forKeyedSubscript: name). A rejection is "<name>: <error>". Thus a host function named "elicit.confirm" gives the prefix "elicit.confirm: " with no extra code.
    - ToolContext.elicit (Extras) validates an accepted form answer and changes an invalid accept to .decline(reason: invalidAnswerReasonPrefix + failure). The helpers get that check with no code here.
    - docs("globals") reaches the snippet as a JSON string. ResultRenderer.serialize uses JSONEncoder, which writes "\n" as two characters and "/" as "\/". The cap test must measure the serialized text, not the raw page.
    - Commit 3 affects one more test than the design lists: theDeliveriesReadWaitsForTheRecord answers elicit("Which repository?") with content {repo}. With the answer field required, that accept becomes a decline.
    - No constants exist for the names help and docs. Design f asks to drop them via constants, thus commit 1 adds MultiTool.helpGlobalName and MultiTool.docsGlobalName.
  timestamp: 2026-10-16T10:53:28.784445+00:00
- actor: claude-code
  id: 01m52685d623g53mw871yytggs
  text: 'Task 20 (commit 1) done. The elicit global now comes from one table in MultiTool+ElicitationHelpers.swift. The page text and the short form did not change. Proof: the filtered run (SandboxGlobalsTests and the two HardeningTests injected-globals tests) had 41 tests pass before the change and 41 tests pass after it. The new doc-coverage test installedGlobalsMatchTheDocumentedGlobals cannot fail on the old code, because it covers a pure refactor. Full run: "Test run with 2411 tests in 211 suites passed". The build gives no compiler warnings. One SwiftPM build-graph warning ("missing creator for mutated node ... mlx-swift_Cmlx.bundle") was already in the build before this change.'
  timestamp: 2026-10-16T11:06:12.262712+00:00
position_column: doing
position_ordinal: '8180'
title: 'Elicitation helpers from one declarative table: elicit.confirm/choose/chooseMany/askText/askNumber and the text short form (elicitation-plan tasks 20, 21, 22)'
---
Spike (task 27): an installed host function takes properties. The preamble can move an installed host function "elicit.<m>" onto elicit. Proof: a probe run of 5 tests passed (the probe was deleted). Recommendation: the namespace elicit.<m>, not flat names. Flat `confirm` clashes with snippet code (`const confirm = await confirm(..)` fails; a snippet `function confirm` silently replaces it). The headless gate stays one name, and the current hint covers each helper.

Design:
a. Table in a new file MultiTool+ElicitationHelpers.swift. Entry `ElicitationGlobal`: name, summary, example, signatures (parameters, content TS type), makeQuestion([InterpreterValue]) throws -> ElicitationQuestion { request, content renderer }. renderAnswer gives { action, content (accept only), reason }. `elicit` is the first entry. Its SandboxGlobalDoc and elicitUsage are generated. SandboxGlobalError gets the usage of each entry.
b. Task 21 entries, each a form with one required field `answer`, and content = the plain value: confirm boolean; choose string enum; chooseMany array of an enum with minItems/maxItems; askText string with format/pattern; askNumber number or integer with minimum/maximum. Argument errors throw before a request (prefix "elicit.<m>: " + usage).
c. Task 22: elicit("question") sends { answer: string }, required; content on accept = the string. This is a BEHAVIOR CHANGE (content.<key> stops working). Tests and README/SECURITY change with it.
d. The table generates the host functions (one elicit path), the preamble lines (a gate in JS, because the preamble is made one time for each registry), docs("globals") (ElicitationAnswer<T>, one line for each helper in `declare namespace elicit`, the awaited-names sentence), docs("elicit.<m>") full blocks, and the usage text.
e. Headless: no entry installed or documented. The current hint applies.
f. Doc-coverage test: the installed globals (globalThis minus the raw JSContext baseline, plus the own function members) == the documented names (declare function + namespace members), for interactive and headless. The test parsers accept dotted names.
g. Fixed-order tests with ScriptedElicitationSink: request schema and answer for each helper; decline/cancel reason; an accept that is not valid gives decline with the invalid-answer prefix; argument errors send no request; headless gives the hint.
h. Commits: 20 (table, no behavior change), 21 (helpers), 22 (short form, behavior change).
Open for the owner: plan section 3 shows flat names; help() lists only registry paths (the plan says one line for each helper "in help()"); the page must stay under the 4,000-character cap; optional non-writable install with Object.defineProperty.

#elicitation-phase-5