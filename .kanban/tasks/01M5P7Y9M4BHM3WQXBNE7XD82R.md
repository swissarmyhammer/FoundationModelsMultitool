---
assignees:
- claude-code
position_column: done
position_ordinal: ffffffd980
title: A snippet that declares its own `tools` still reaches the namespace
---
bench24-1023b django__django-14787 seq 19546: `const tools = await tools.files.list(...)` put the global in the TDZ for the whole snippet ("Cannot access 'tools' before initialization"). Fix (ShadowedTools): a token scan (strings, templates, comments, regex skipped) finds a binding of `tools` (const/let/var/function/class, destructuring); then each namespace call becomes `globalThis.tools…` — every `tools.` use before the declaration, and after it `tools.<group>.<verb>(` for a verb on the surface. The model's own uses (`tools.entries`, `tools:` keys, `{ tools }`) stay; a note says so. Test: ShadowedToolsTests with the run's snippet.