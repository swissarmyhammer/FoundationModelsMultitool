---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m4a98jz9ptvm7prmmqnwp0te
  text: |-
    Research (implement step):
    - README.md has no `### Files` section. Only `### Web` stands under `## Capabilities`. The new `### Git` section follows the form of `### Web`. The intro sentence "Four capabilities" must change to five.
    - `WebDocumentationTests` reads the `## Capabilities` section of README.md through `RepositoryFile.section(headed:inRelativeFile:)`. A `GitDocumentationTests` suite in the same form guards the git section and the "Status of this document" text of git.md.
    - Search catalog: `APISurface.Entry: SearchableMetadata` is generic. The id is the path (`git.diff`), and the indexed text is the block (banner `// tools.git.<verb>` plus the description). No git-specific metadata exists. A unit test drives `SearchToolsTool.makeSearcher(over:selection:nil,embedder:nil)` over `withGit` plus `withFiles` (distractors) with the queries "git", "diff", "blame", "branch".
    - Rendered surface goldens (`Tests/.../Goldens/`) hold no git entry and no files entry. No golden changes.
    - Live model pattern: `WebResearchScenarioTests` (withLiveRouterFixture, `registry.makeSessionTools(selection:embedder:)` with `fixture.discoverySeams`, `streamTurn`, `grade`, `reportGatedResult`). `NativeTranscript.typedToolPaths(in:)` gives the `tools.*` paths each snippet wrote. Each `runCode` output is in `StreamedTurn.calls[i].output`.
    - Goal snippet with no model: `WebRunCodeLiveTests` form (`MultiTool(registry:).call(arguments:)`).
    - Time budget: CI run 37061505863 took 17 min 06 s for the integration job (tests 703 s). The margin is approximately 3 min.
  timestamp: 2026-10-07T04:17:05.513306+00:00
- actor: claude-code
  id: 01m4b0penzprqn5nbetx6qk7d3
  text: |-
    ### finish iteration 1 — stuck (recorded late: the disk was full)
    - implement: stuck — 7 files in the working tree, not committed: README.md, git.md, Tests/FoundationModelsMultitoolTests/{GitSearchTests,GitDocumentationTests,GitGoalSnippetTests}.swift, Tests/Support/MultitoolTestSupport/GitScenarioHistory.swift, IntegrationTests/Tests/FoundationModelsMultitoolIntegrationTests/GitScenarioTests.swift
    - evidence: unit 2234 passed in 194 suites. Integration run 1: 107 tests in 35 suites passed, 440.8 s test time, 498 s wall; the git suite took 187 s. After "Answer in one short sentence." was added to each prompt, the git suite took 139.3 s (6 of 6 pass); run 2 exited 0 in 435 s wall, but the log stops before the summary line because the disk filled. No progress comment could be written then (os error 28).
    - open: (1) the goal scenario asserts only `git.diff`, because the model can answer with the automatic diff mode; a unit test runs the goal snippet word for word with `git.changes`. (2) A search for "git" ranks `files.glob` among the git verbs, because the search tokenizer reads `git.changes` as one token; the correct fix is in FoundationModelsRanker (no task made yet). (3) The sub agent estimates the CI integration job at 24–26 min (last CI run 17 min 06 s; the runner is 3–4 times slower). Only a CI run after a push can confirm it.
    - next: iteration 2 runs the test step (full unit and full integration suite, with the summary line), then commit and review.
  timestamp: 2026-10-07T11:06:37.119669+00:00
- actor: claude-code
  id: 01m4b14hpfsn9ryngjzxfmgyfw
  text: |-
    ### test - green
    - swift build --build-tests: exit 0. Only warning: the known mlx-swift_Cmlx.bundle "missing creator for mutated node" (dependency warning).
    - swift test (unit): 2234 tests in 194 suites passed after 13.214 s. 0 failures.
    - swift test --package-path IntegrationTests --no-parallel: "Test run with 107 tests in 35 suites passed after 328.251 seconds." Wall time (time): real 6m2.783s.
    - Git suite "Gated git scenarios: a real model reads a repository through tools.git in runCode": passed after 119.291 s (6 test cases).
    - 6 old tests skip because a provider key is not set (BRAVE, TAVILY, EXA, SERPER, KAGI, SEARXNG_URL). They are not part of this change.
    - Disk: 88 GiB free after the run. Nothing was committed.
    - next: review
  timestamp: 2026-10-07T11:14:18.959773+00:00
- actor: claude-code
  id: 01m4b15ad1p9e58zg0mvx3865k
  text: |-
    ### commit — changed
    - evidence: one local commit, subject "feat: add git live model tests, README section, and git status shipped". The sha is in git log (a comment cannot hold its own sha). No build product or log file is staged.
    - next: review
  timestamp: 2026-10-07T11:14:44.257518+00:00
depends_on:
- 01M48VAY56DD7FRP5ZN9F4RD5E
- 01M48V8V37DM9YG6EQ1ZDB38Q4
- 01M48V95RGBAG8P7ENHJMM1A0K
- 01M48VA2QSPSBZ18AAAFDVR81S
- 01M48VA6MJK1WHXPJYJ4AC64T6
- 01M48VAAXDRA9N07ACFBT90ANX
position_column: doing
position_ordinal: '80'
title: 'git: live model tests, README section, and git.md status'
---
## Goal

Close the `git` capability: prove it with the real model, document it, and mark the plan as shipped.

## Work

1. Integration tests in `IntegrationTests/` (the nested package) that mount `withGit(root:)` on a temporary repository and let the real model answer through `runCode`. Use the goal snippet of `git.md` as one scenario. Add scenarios for `status`, `log`, `show`, `blame`, and a `diff` of a renamed function.
2. Follow the rules of the integration suite:
   - Each test runs on each push. No nightly split, no skip, no repeated rounds. The whole suite stays in 20 minutes; measure the new time and record it in a comment.
   - Assert code properties only (for example: the snippet called `tools.git.diff`, the result has no `correction`). Print model scores; do not assert a fixed score.
3. `README.md`: add a `git` section in the form of the `files` and `web` sections: `withGit(root:)`, the verb table, the read-only rule, the root rule, and the language list of the semantic diff.
4. `git.md`: change "Status of this document" to say that the code shipped, and that the code and `README.md` are correct when they are different from this document (the same text as `web.md`).
5. Check the rendered surface goldens, and the search catalog metadata (`Surface/APISurface+SearchableMetadata.swift`), so that a search for "git", "diff", "blame", or "branch" finds the verbs.

## Acceptance

- `swift build` and `swift test` pass with no new warnings.
- `swift test --package-path IntegrationTests --no-parallel` passes, in 20 minutes or less in total. #git