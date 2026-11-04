---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m6hj9tjreyjhxvaz4yc49a6x
  text: |-
    ### review — clean
    - evidence: review sha 980dd817~1..980dd817, 0 findings, 2 files reviewed
    - next: none. The task moved to done.
  timestamp: 2026-11-03T20:41:07.928604+00:00
position_column: done
position_ordinal: ffffffe680
title: 'Sub-agent tools see the current MCP catalog: a public current-registry accessor'
---
Source: the restore audit for nested sub-agent sessions, item 5. Coordinator: foundationmodelsacpagent-87.

Problem: makeSessionTools drops the staging half (MultiTool.swift near line 184). Each call makes a new RegistryHolder (near line 219). SurfaceRefresher stages only on the holder of the root session. No public API reads holder.current. So tools built for a sub-agent run from the original Registry keep the build-time catalog. They never see MCP catalog changes, in a fresh run or in a restored run.

Work:
- Choose the smaller and safe way: a public current-registry accessor, or fork the mounted MultiTool and SearchToolsTool of the root (they share the holder, see MultiTool+Forking.swift).
- A restored run builds from the current registry at restore time.
- Write the test first. A catalog change on the root must show in the tools of a sub-agent run, fresh and restored.
- No test may depend on machine speed.

Order of work from the coordinator: this card first, then the shell owner card, then the crash leftovers card. For each: tdd, review, commit, push, and 2 lines to the coordinator. Priority stays with the shell failed outcome card (01M6HA2RQ7K35W788Y20JNRBPA) when its Extras blocker clears.