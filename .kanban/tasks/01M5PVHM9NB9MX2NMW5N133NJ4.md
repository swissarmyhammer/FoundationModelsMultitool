---
assignees:
- claude-code
position_column: done
position_ordinal: ffffffde80
title: Decide whether search_tools' selection model may be the caller's model (after Router sha)
---
BLOCKED until foundationmodelsacpagent-83 sends the Router sha. SearchToolsTool+Seams.swift:30-41 has a rule: the selection model must not be the caller's model. It exists because Router refused, or deadlocked on, a nested same-model call. Once the lock covers only the model call, that reason is gone.

Test first: add a test where the selection model is the caller's model and show that the nested call completes. If it does, drop the rule and its doc comment. If it does not, keep the rule and write down the reason that is still true. Run the full `swift test`, then commit and push, and send the sha to the peer. #blocked