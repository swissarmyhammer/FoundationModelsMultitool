---
assignees:
- claude-code
position_column: done
position_ordinal: ffffffe980
title: 'A: a string argument accepts an object or array (JSON-encode); a multi-type schema is read'
---
kanban24 django__django-14997 seq 23396/24180: runKanban({variables: {body}}) refused "argument variables must be string, got an object". Fix in ToolInvoker: a `.string` property given an object/array gets its JSON text (Postel); a property whose schema `type` is a list (or untyped) accepts any listed kind. Test first in ForgivingCallsTests. #forgive