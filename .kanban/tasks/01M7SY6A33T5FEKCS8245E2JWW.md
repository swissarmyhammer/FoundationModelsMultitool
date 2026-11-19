---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m7sy72j8x4zeprzv58n7ftyk
  text: 'Correction: in the Work list, "the rest of the skill text is ^skill task" means task ^jqxnt67 (01M7SY6VG7D05XAHNZJJQXNT67). The endpoint field is task ^c5dkdc6.'
  timestamp: 2026-11-19T12:58:57.992045+00:00
depends_on:
- 01M7SY5YTKRE2TS1R6KR2MC120
position_column: todo
position_ordinal: '8180'
title: The search sessions operation of the sessions tool (D207)
---
Decision: D207 (d), (e), (g) in TestudoApp/features/decisions.md (commit ba585e0). Brief: /Users/wballard/github/swissarmyhammer/.briefs/search/mt-brief.md, items 3 and 5.

Precondition: ^r2mc120 (the protocol and the parse).

## Work

- Host API: `SessionsTool.init(directory:exporter:searcher:)` and `SessionsGraph.endpoint(of:exporter:searcher:)`, with `searcher` nil by default, so each current caller still compiles. The endpoint keeps the searcher of its directory, as it keeps the exporter.
- Add `search sessions` (`searchSessions` in code mode) to the tool. Arguments: `query` (required), `folder` (optional), `archived` (false by default), `limit` (20 by default, 50 at most).
- Turn the parsed tokens into the request: `@<session>` through the one resolver (an ambiguous one gives AMBIGUOUS_REFERENCE); the tag form, `agent:` and `folder:` through the session filter of the directory; `is:archived` or `archived: true` to `includeArchived`. The caller folder is `preferredFolder`.
- The answer is plain text (D207 (g)): for each session one line `@<short id> <name> (<folder>) <date> – <n> hits`, then at most three lines `  <author>: <snippet>`. The last line tells the limit: the search covers only the sessions that this server records, not the sessions of other agents. With no hit: one line that says that no session matches, with the query, and the same limit line.
- With no searcher: the corrective `MISSING_SEARCHER`, which names the UI command Search (⌘F).
- Add one example row for `search sessions` to `Resources/skills/sessions/SKILL.md`, so SessionsSkillTests stays green; the rest of the skill text is ^skill task.
- Aliases (D86).

## Tests

- [ ] With a fake searcher: the answer text with the limit line, and the no-hit text.
- [ ] No searcher: MISSING_SEARCHER.
- [ ] `archived`, `limit` (the cap at 50), `folder`.
- [ ] `@<slug>` through the resolver, and an ambiguous one.
- [ ] The preferred folder is the caller folder.
- [ ] A wrong date in the query gives the corrective. #sessions #search