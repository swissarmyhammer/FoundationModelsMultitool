---
assignees:
- claude-code
position_column: done
position_ordinal: fffffffa80
title: 'shell.execute in a snippet: r.output holds the whole output as raw lines; a max-output argument gets a note'
---
checked24 django__django-13710, session 01M77V76GMQNDW5HVXDF4RCQ5K, seq 4675…5168: the coder ran the full Django suite about 9 times (3–4.5 min each). Its snippet was `r.output.filter(l => /^(FAIL|ERROR):/.test(l))`, but `r.output` held only the last 32 lines, each as "N: text". The FAIL headers sat at lines 560–606 of 624, so the filter found nothing. The model reasoned "the output has already been consumed … I'll need to rerun the full suite" (seq 4761). `maxOutputChars: 200000` was ignored without a word.

Fix:
- `Execute.snippetValue` adds the whole stored output (up to a large bound) as a hidden field.
- The JS shell shape moves it out of the enumerable fields. `r.output` reads every line as raw text (no "N: "), and `r.lines` reads every line numbered, "N: text". `r.text`/`stdout` is the raw text joined.
- The serialized report (`return r`, and the model's own read of a report) keeps the 32-line numbered tail and `outputNote`.
- `maxOutputChars`, `maxOutput`, `maxChars`, `maxLines`, `outputLimit`, `limit`: the result gets a `notes` entry saying the argument is not one of shell.execute, and that the snippet's r.output holds the whole output.
- The execute description says which field is which.

Tests: filtering r.output for ^FAIL: at line 10 of 100 finds it; r.lines has 100 numbered lines; `return r` still renders the 32-line tail; maxOutputChars gives the note. #shell