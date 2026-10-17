---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m53s6ya0r6tasedp328vkbdg
  text: |-
    Research done. Facts from the code:
    - Sandbox answer (ElicitationQuestion.renderAnswer): always { action, content, reason }. content is null unless accept; reason is null when none. elicit("q") content = text; elicit({message, requestedSchema}) content = object of fields; elicit({message, url}) content = null; confirm boolean, choose string, chooseMany string[], askText string, askNumber number.
    - elicit url: Fetch.httpURL (absolute http/https with host), else argument error before the request goes out (decodeElicitURL).
    - MCPServer headless: clientCapabilities(for: .headless) declares no elicitation; answerElicitation gives cancel with RunPlane.noUserPresentReason at once.
    - Link: each tools/call _meta.progressToken = request id; callingContext(linkedBy:) uses echoed token, else the one run (same holdingRunToken) of all calls in flight, else handler, else cancel (noAnswererReason / notLinkedReason).
    - Wire reasons in _meta.reason: hostGone, noUserPresent, schemaOutsideTheSubset (decline), invalidURL (decline), noAnswerer, notLinked, runFailed, connectionEnded.
    - disconnect / new connect: endHeldHostElicitations + endOldContextElicitations give cancel with connectionEndedReason.
    - HardeningTests parses "- `name`" lines of README "### Injected globals" up to the next "\n#"; README has no MCP subsection yet.
  timestamp: 2026-10-17T01:56:49.600667+00:00
- actor: claude-code
  id: 01m53savq9q43abfh4fpgbfq4c
  text: |-
    ### implement — changed
    - evidence: README.md (new "### Questions from an MCP server" subsection before "### Injected globals"; the elicit text in "### Injected globals" now gives the { action, content, reason } result, the content of each form and helper, and the url check). docs/SECURITY.md (elicit bullet: "Router's own ElicitationRequest" corrected to "the ElicitationRequest of FoundationModelsExtras", url check, result shape; new "## Questions from an MCP server" section: progress-token link, one-run link, restricted schema, headless cancel with no declared capability, _meta.reason, end of held URL flows on disconnect or reconnect). The default userPresence of MCPServer is not described (^33rygav). `swift test` one run: exit 0, "Test run with 2437 tests in 211 suites passed". One SwiftPM build line "warning: missing creator for mutated node" for the mlx-swift_Cmlx.bundle came from the build system, not from these doc files.
    - next: /review
  timestamp: 2026-10-17T01:58:58.025440+00:00
- actor: claude-code
  id: 01m53sbwbchx86t32f0xwfpt28
  text: |-
    ### commit — changed
    - evidence: 919c737 docs: correct the elicitation text in README and SECURITY
    - next: review
  timestamp: 2026-10-17T01:59:31.436842+00:00
depends_on:
- 01M53FG8K2C3T24RJWRNF9DKS3
position_column: doing
position_ordinal: '8180'
title: 'Group D (d): correct the elicitation text in README and docs/SECURITY.md'
---
Elicitation fixes from the 2026-10-16 check (elicitation-plan.md section 10), group D (d).

README.md and docs/SECURITY.md must describe:
- the { action, content, reason } result,
- the headless MCP cancel,
- the progress-token link of a server question to its call.

docs/SECURITY.md about line 62 names "Router's own ElicitationRequest", but the type is in FoundationModelsExtras. Correct it.

If a test reads these files (HardeningTests reads the README list of globals), keep it green. One full run. #elicitation-fixes