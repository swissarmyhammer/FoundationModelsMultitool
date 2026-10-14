---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m4y05enxwrxe2ztdhac5dh3c
  text: 'Owner instruction: before the final runs of T4, move both packages (root and IntegrationTests) to Router 906c2b17 with Extras b68a5d4 (swift package update of the family pins). Router 906c2b17 fixes a rare lock-order deadlock in the session output hub; no public API change. No hung run was seen before this.'
  timestamp: 2026-10-14T20:02:54.269647+00:00
- actor: claude-code
  id: 01m4y426kwdyc7k44rdxgjem2w
  text: 'New heads for the final runs (owner, replaces 906c2b17): Router 3f3ba209 (906c2b17 plus a test fix, no API change) and Extras 7f530ff. Extras 7f530ff adds elicitation reasons: ElicitationResponse.reason, .decline(reason:), .cancel(reason:). A run cancel, a sweep and a close now end open questions with .cancel(reason: RunPlane.runCancelledReason); a duplicate id gives .cancel(reason: RunPlane.duplicateElicitationIdReason). If a Multitool test checks a bare .cancel of a run-plane question, change it to the reason form and name it in the report.'
  timestamp: 2026-10-14T21:11:02.012725+00:00
depends_on:
- 01M4XW9N4S2W8WTPXZDE9ASE3A
position_column: todo
position_ordinal: '8480'
title: 'Mail step 5 T4: docs and comments, final suite run, final commit and final report'
---
Step 5 of the mail work. Read mailbox.md (sections 3, 4 and 5, the signals table, section 8 rows 2 to 5, and the Progress table). All items in mailbox.md are decisions. This task starts after T3.

## Work
- Docs and comments: remove each reference to SessionMailbox, drain(), cancel() with no id, and "turn" for Router work.
- Do one full suite run.
- Do the IntegrationTests live run one time, only if the models are complete in the local cache. Check the cache first. Do not download models in a test run.
- Make the final commit.
- Send the final report: the list of commits and the check of section 8 row 5: "The tests check the same behavior as before. No test was removed only to make the build pass."

## Rules
- Write all text (comments, docs, commits, reports, tasks) in STE.
- Commit with Multitool green. Report to the step 5 owner: the commit, the test result, and each difference from the plan with its reason. Do not push until the owner accepts step 5.
- Run the full suite one time. Do not run tests again and again to find a failure. A test that fails only sometimes is a bad test: find the cause and make it deterministic, or fix the race in the code. Do not use .timeLimit, sleep, clock wait, poll or retry. If a test hangs, take `sample <pid>` of your own test process before you stop it. Stop only your own process ids.
- Ask the owner before a decision that is not in the plan. Do not delete a test without the decision of the owner.

#mail-step-5