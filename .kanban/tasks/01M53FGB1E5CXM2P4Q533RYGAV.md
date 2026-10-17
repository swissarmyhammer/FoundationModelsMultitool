---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m53s27968ey0q31ch7agb25t
  text: |-
    ### research — waits for the owner's choice (2026-10-16)
    - Public API: MCPServer has one public init (MCPServer.swift:442), with `userPresence: UserPresence = .interactive` (:449; doc :438-439). MCPServerPool.init() takes no presence. Extras RunPlane(clock:userPresence:) (RunPlaneActor.swift:224) also defaults to .interactive.
    - Call sites in this repo: about 39 use the default, all tests or integration tests (MCPTestSupport.swift:195/259/384 helpers default to .interactive). 3 pass .headless (ResilienceTests.swift:826, MCPElicitationTests.swift:1401, :1418). No production source builds an MCPServer; the host does. The doc example MCPCapability.swift:81 uses the default.
    - ../ACPAgent is not at /Users/wballard/github/swissarmyhammer/ACPAgent; not checked.
    - The sandbox reads presence per call from ToolContext.userPresence (RunPlane); MCPServer fixes it at init. Nothing makes the two agree.
    - Docs: README describes presence only for the sandbox elicit global; MCPServer presence is only in source doc comments.
    - Recommendation sent to the owner: make the value required (no default). Do not change code before the owner chooses.
  timestamp: 2026-10-17T01:54:14.950641+00:00
- actor: claude-code
  id: 01m53s388b9sxrvbvaqm82yqex
  text: |-
    ### decision — owner chose option A (2026-10-16)
    - userPresence of MCPServer becomes required (no default). Do not change RunPlane now.
    - ACPAgent (../FoundationModelsACPAgent): production already passes the value (MCPComposition.swift:609). 2 tests use the default (MCPCompositionTests.swift:592 and :659). The owner asks ACPAgent to pass `userPresence: .interactive` there first.
    - Push order: push this card only after the owner says that the ACPAgent commit is on main. This card goes in a second push, alone.
    - Add a README paragraph and a short note in the commit message.
  timestamp: 2026-10-17T01:54:48.715535+00:00
- actor: claude-code
  id: 01m53s8artce655f8krnt6ntrj
  text: |-
    ### unblocked — ACPAgent is on main (2026-10-16)
    - ACPAgent commit 5638084 is on main. Its 2 tests pass `userPresence: .interactive`, and no other ACPAgent call omits it.
    - Push this change when its review is clean, then report the commits and the CI result to the owner.
  timestamp: 2026-10-17T01:57:35.130794+00:00
- actor: claude-code
  id: 01m53t5rfk57em7ntt3km382zj
  text: |-
    ### implement — work done (2026-10-16)
    - RED (compile-time): I removed the default `= .interactive` from `userPresence` in the public init of MCPServer. Then `swift build --build-tests` failed with `LargeCatalogSurface.swift:65:79: error: missing argument for parameter 'userPresence' in call`. Before the change, `MCPServer(name:)` with no userPresence compiled. A runtime test already exists for a headless server: `ResilienceTests.headlessInitializeCarriesNoElicitationCapability`. Thus I added no new test.
    - GREEN: each call site of the public init now passes `.interactive`: LargeCatalogSurface.swift (default maker), IntegrationTests MCPBareSessionTests.swift and MCPElicitationBareSessionTests.swift, and the doc example in MCPCapability.swift. None of these is about a headless host.
    - Test helpers: MCPTestSupport.makeServer, connectedMCPServer(to:...), connectedLoopbackMCPServer and MCPElicitationTests.connected keep `.interactive` as a test-only default. These helpers call the internal init, which has no default. To make them required would change about 60 call sites in about 20 files. Each helper doc comment now says that the default is test-only and that the public init has none.
    - Discovery: LargeCatalogSurface.swift uses `.interactive` in a default argument value. Swift then requires an explicit `import FoundationModelsExtras` in that file. Thus I added the Extras product to the MCPTestServer target in Package.swift, because each target declares the products that it imports. This is a new edge in the dependency graph of the test-support target. No new package comes into the graph.
    - README: I added one paragraph in "### Questions from an MCP server" about the required argument, `.interactive` and `.headless`.
    - Root `swift test`: one run with exit 1, because the build failed on the missing import above. After the fix, one run with exit 0: "Test run with 2437 tests in 211 suites passed after 5.152 seconds". The one warning is the SwiftPM build-system warning "missing creator for mutated node" for the mlx-swift_Cmlx bundle. This warning came before my change, and no source line causes it.
    - BLOCKER: `swift build --build-tests` in IntegrationTests/ (one run) gave exit 1. The errors are in MCPServer+Elicitation.swift, a file that I did not change: `extra argument 'source' in call` at :135 and :146, `'holdingRunToken' is inaccessible` at :242, and `ToolContext has no member 'endElicitation'` at :558. Cause: the gitignored IntegrationTests/Package.resolved pins FoundationModelsExtras at e65287a. The root Package.resolved pins it at 1f586a7. The rule "CI resolves branch heads" forbids moving local pins except to diagnose a CI failure. Thus I did not move the pin. The build stopped before it compiled the two IntegrationTests files that I changed.
  timestamp: 2026-10-17T02:13:39.443944+00:00
- actor: claude-code
  id: 01m53t60e892d9z532km375npp
  text: |-
    ### implement — stuck
    - evidence: 8 files changed — MCPServer.swift (no default on userPresence, doc), MCPCapability.swift (doc example), README.md (one paragraph), Package.swift (Extras product on MCPTestServer), LargeCatalogSurface.swift (import + `.interactive`), MCPTestSupport.swift and MCPElicitationTests.swift (helper docs: test-only default), IntegrationTests MCPBareSessionTests.swift and MCPElicitationBareSessionTests.swift (`.interactive`). RED: the build gave "missing argument for parameter 'userPresence'" before the call sites were changed. Root `swift test`: exit 0, 2437 tests in 211 suites passed. IntegrationTests `swift build --build-tests`: exit 1 in MCPServer+Elicitation.swift (a file that I did not change), because the local IntegrationTests pin of Extras is e65287a and the root pin is 1f586a7.
    - next: the owner decides one of two things. (a) May I move the gitignored IntegrationTests pin of FoundationModelsExtras to 1f586a7 (the root pin) and run the IntegrationTests build one more time? (b) Or does CI (which resolves the branch heads) give the IntegrationTests build check? The task stays in doing.
  timestamp: 2026-10-17T02:13:47.592633+00:00
- actor: claude-code
  id: 01m53tajsyd8s3rgd6mqxjafh5
  text: |-
    ### implement — no-change
    - evidence: In IntegrationTests/, `swift package update FoundationModelsExtras` ran one time (exit 0). The old pin was e65287a. FoundationModelsExtras now resolves at main 1f586a797e6d40bd8071c0c8038fa6e056b80ecf. `git merge-base --is-ancestor 2d1c476 HEAD` in .build/checkouts/FoundationModelsExtras gives exit 0, thus the revision contains ToolContext.endElicitation.
    - evidence: `swift build --build-tests` in IntegrationTests/ ran one time. Exit code 0. "Build complete!". There are zero compiler errors and zero compiler warnings. The only warning is from the build system: "missing creator for mutated node" for .build/out/Products/Debug/mlx-swift_Cmlx.bundle/Contents/MacOS. This warning is about the mlx-swift resource bundle. It is not in a file that this task changed.
    - No source file changed. The userPresence fix with `.interactive` was not necessary. Package.resolved is gitignored. Package.swift did not change. The integration tests did not run.
    - next: review.
  timestamp: 2026-10-17T02:16:17.470806+00:00
- actor: claude-code
  id: 01m53tby8xvc1f2vma224150tk
  text: |-
    ### commit — changed
    - evidence: commit "feat(mcp)!: require userPresence on MCPServer" (local, not pushed). It has a BREAKING CHANGE footer. All changes and the .kanban files are in this one commit.
    - next: review
  timestamp: 2026-10-17T02:17:01.981843+00:00
- actor: claude-code
  id: 01m53tk6abmn4kvf9abm2hvcz3
  text: |-
    ### review — clean
    - evidence: review sha HEAD~1..HEAD (commit 8526877). 0 findings, 0 confirmed, 0 refuted. 7 attempts, 0 failed. 8 files reviewed. The ignore rule (.reviewignore) excluded 4 .kanban files. No validator matched README.md.
    - next: The task is in done. No work remains for this task.
  timestamp: 2026-10-17T02:20:59.595040+00:00
- actor: claude-code
  id: 01m53tm2197202vagkng4jvbmk
  text: |-
    ### finish iteration 1 — clean
    - implement: changed — 9 files (userPresence required; call sites pass .interactive; test helpers keep a test-only default; README paragraph); IntegrationTests resolved to Extras main 1f586a7 and built, exit 0
    - test: green — swift test, exit 0, 2437 passed (the implement step had one more run that stopped on a missing import before the fix)
    - commit: 8526877
    - review: clean — 0 findings
    - next: push after the CI run of 93a9790 ends, then report the commits and CI to the owner.
  timestamp: 2026-10-17T02:21:27.977977+00:00
depends_on:
- 01M53FG8K2C3T24RJWRNF9DKS3
position_column: done
position_ordinal: ffffff8d80
title: 'Group D (c): make the default userPresence of MCPServer safe, or make the value required'
---
Elicitation fixes from the 2026-10-16 check (elicitation-plan.md section 10), group D (c).

The default userPresence of MCPServer is .interactive (MCPServer.swift about line 436). A headless host that forgets the value advertises elicitation.

Two choices: make the default safe (headless), or make the value required. This changes public API.

STOP before the change: first find which callers and tests use the default, and send the facts and a recommendation to the owner's coordinating session (swissarmyhammer-96) in plain text. Do the change only after the owner chooses. Record the choice here.

The fix starts with a fixed-order test that fails before the fix (RED), then passes (GREEN). One full run. #elicitation-fixes