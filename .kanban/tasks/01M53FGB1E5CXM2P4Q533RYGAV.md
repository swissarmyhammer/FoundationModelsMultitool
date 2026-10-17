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
depends_on:
- 01M53FG8K2C3T24RJWRNF9DKS3
position_column: todo
position_ordinal: '8580'
title: 'Group D (c): make the default userPresence of MCPServer safe, or make the value required'
---
Elicitation fixes from the 2026-10-16 check (elicitation-plan.md section 10), group D (c).

The default userPresence of MCPServer is .interactive (MCPServer.swift about line 436). A headless host that forgets the value advertises elicitation.

Two choices: make the default safe (headless), or make the value required. This changes public API.

STOP before the change: first find which callers and tests use the default, and send the facts and a recommendation to the owner's coordinating session (swissarmyhammer-96) in plain text. Do the change only after the owner chooses. Record the choice here.

The fix starts with a fixed-order test that fails before the fix (RED), then passes (GREEN). One full run. #elicitation-fixes