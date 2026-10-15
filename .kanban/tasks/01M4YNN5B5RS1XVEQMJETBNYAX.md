---
assignees:
- claude-code
position_column: todo
position_ordinal: 8a80
title: Move to Router 77b2da68 and add the three new SessionEvent cases
---
Router main 77b2da68 needs Extras 7f530ff or later (Extras main is 278e9cb). It adds three public SessionEvent cases:
- .workStarted (no payload, origin .system)
- .workEnded (no payload, origin .system)
- .elicitationEnded(ElicitationEnd)

After cancelAll() or close() ends a question, respond(elicitationId:response:) gives .noPendingElicitation.

Do:
- Move to Router 77b2da68.
- Add the three cases to ScenarioRunner.streamAnswer and to each other exhaustive switch. Keep each switch exhaustive with no default, and make no behavior change.
- Build both packages and do one full root run.
- Commit, push when green, and report the head and CI.

Start after the commit of task 01M4YJ7297HG75Q4M31VQMMQ49 (owner order). Multitool CI on main can fail until this push. #mail-new-events