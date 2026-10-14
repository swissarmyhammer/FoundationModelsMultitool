---
assignees:
- claude-code
position_column: todo
position_ordinal: '8780'
title: 'Live run: two graded scenarios fail on a model choice'
---
Found in mail step 5, T4, live IntegrationTests run (2026-10-14, Router 3f3ba209, Extras 278e9cb, profile multitool-tiny, standard Qwen3.8-27B-mxfp4).

- EnvironmentScenarioTests "the model reads the injected date from a snippet, and no verb answers a correction": SCENARIO environmentWeekdayAndOperatingSystem result=FAIL calledTheVerbs=fail noCorrection=pass answerHoldsTheInjectedDate=pass. The model called environment.os, not environment.now. Calls: runCode, searchTools, runCode.
- WebResearchScenarioTests "the model calls tools.web.search from a snippet and answers with swift.org": SCENARIO webResearch result=FAIL searchedTheWeb=fail validAnswer=pass. The model made no tool call.

The runner read the tool calls through the MailID subscription (the environment run shows its calls), and 113 of 115 tests passed. No earlier live result of these two scenarios is on the board, so no baseline exists. Decision needed: a model choice in a graded live scenario, or a change of the prompt, the surface, or the context render of Router.

#mail-step-5