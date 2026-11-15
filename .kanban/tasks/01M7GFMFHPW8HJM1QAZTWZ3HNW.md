---
assignees:
- claude-code
depends_on:
- 01M7GFMCT4RYT4NAQ1PPY6W2KW
position_column: done
position_ordinal: ffffffff8280
title: 'MT-2: pin and unpin operations of SessionsTool'
---
TestudoApp Step 2 (D184, D100 (a)): the agent can pin too. Add the operations `pin session` and `unpin session` to `SessionsTool`, with the same rules as `pinSession` and `unpinSession` of `SessionsGraph`. They call `SessionDirectory.setPinned`. Add the risk facts (MT-7) as for `tag` and `untag`. The `list` result shows a pinned session as pinned.

Precondition: the Extras pin API is on Extras origin/main. Depends on the mutations task.

Tests: pin and unpin through the tool; check the text result, the refusal for an unknown id, and that `pinnedSessions` of the endpoint shows the change.