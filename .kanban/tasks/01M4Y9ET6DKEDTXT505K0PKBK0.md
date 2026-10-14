---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m4y9hcr3tq4x7fnptwnbprvp
  text: |-
    Evidence check (owner decision 3): the whole session journal of each failed run was read (IntegrationTests/.build/recordings/FMMultitoolIntegration-ABA09365-0492-43A6-A808-1EFA11D9638F and FMMultitoolIntegration-0DCA9731-F3D6-4DE3-9CBD-7B3117040C37, transcript.jsonl).
    - Environment: one prompt in the session, so one answer; 3 tool calls (runCode, searchTools, runCode). The snippet took the weekday from JavaScript `new Date()` and called tools.environment.os. `environment.now` is in no entry of the session.
    - Web research: one prompt and one response in the session; no toolCalls entry at all.
    Thus no tool call happened in another answer: the grade read the right answer. This is the model's choice. FIRST BASELINE (2026-10-14, Router 3f3ba209, Extras 278e9cb, standard Qwen3.8-27B-mxfp4): environmentWeekdayAndOperatingSystem FAIL (calledTheVerbs), webResearch FAIL (searchedTheWeb). These two results do not block the push (owner decision).
  timestamp: 2026-10-14T22:46:42.691666+00:00
position_column: todo
position_ordinal: '8780'
title: 'Live run: two graded scenarios fail on a model choice'
---
Found in mail step 5, T4, live IntegrationTests run (2026-10-14, Router 3f3ba209, Extras 278e9cb, profile multitool-tiny, standard Qwen3.8-27B-mxfp4).

- EnvironmentScenarioTests "the model reads the injected date from a snippet, and no verb answers a correction": SCENARIO environmentWeekdayAndOperatingSystem result=FAIL calledTheVerbs=fail noCorrection=pass answerHoldsTheInjectedDate=pass. The model called environment.os, not environment.now. Calls: runCode, searchTools, runCode.
- WebResearchScenarioTests "the model calls tools.web.search from a snippet and answers with swift.org": SCENARIO webResearch result=FAIL searchedTheWeb=fail validAnswer=pass. The model made no tool call.

The runner read the tool calls through the MailID subscription (the environment run shows its calls), and 113 of 115 tests passed. No earlier live result of these two scenarios is on the board, so no baseline exists. Decision needed: a model choice in a graded live scenario, or a change of the prompt, the surface, or the context render of Router.

#mail-step-5