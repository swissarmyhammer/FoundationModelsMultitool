---
assignees:
- claude-code
position_column: todo
position_ordinal: '8180'
title: 'files: host-given exclude patterns for the search verbs'
---
## Source

Request from the FoundationModelsACPAgent session (2026-10-07). The design comes from the user of that session. Its tracking task is `^t30r8aj`. Do not implement this task until the user says so.

## Problem

In a SWE-bench run, `tools.files.grep` returned lines from the agent's own transcripts under `.acp-agent/transcripts/<session>/transcript.jsonl` in the working directory of the agent. Each grep then matched earlier tool outputs. This gave false matches and made the context larger.

Examples: run `bench/preds.code-context-1006.jsonl`, `django__django-13447` sequence 230; and two results in `django__django-14411` in the run of 2026-10-05.

## Design (from the user of the ACP agent session)

1. The files capability gets an option: a list of exclude patterns in gitignore syntax. The host gives the list when it composes the capability (`FilesCapability` initializer and `MultiTool.Builder.withFiles(...)`). Examples: `.acp-agent/`, `*.log`, `!keep.log`.
2. Do NOT put any agent folder in Multitool. Multitool has no default patterns for the agent. The host (the ACP agent) gives `.acp-agent/`.
3. The search verbs (`files.grep`, `files.glob`, and each other verb that walks a folder tree, for example through `FileWalker`) skip a path that matches a pattern, in the same way as a path that `.gitignore` ignores. A read or a write of an explicit path does not change.
4. Use the same gitignore matcher that the files capability uses now for `.gitignore` (see `FileWalker`, `GlobEngine`, `GrepEngine`), if it has one, so that the two rules agree. If it has none, record the matcher that you add and why.
5. The host patterns stay on when `respectGitIgnore` is `false` (decided 2026-10-07 by the ACP agent session). `respectGitIgnore` is an argument that the model can set in a call. The host patterns are the rule of the host, and the model must not be able to turn them off. Otherwise one grep with `respectGitIgnore: false` finds the agent transcripts again. Write this rule and its reason in the doc comment of the option and of `respectGitIgnore`.

## Tests

- With the exclude patterns `[".acp-agent/"]`, a grep and a glob over a tree that has `.acp-agent/transcripts/x.jsonl` with a matching line do not return that file. A file that is not excluded is still returned.
- With `respectGitIgnore: false` and the exclude patterns `[".acp-agent/"]`, a grep still skips `.acp-agent/` (and a glob too).
- With no exclude patterns, the behavior does not change (the current tests stay green).
- A negated pattern (`!`) and a folder pattern (`dir/`) work as in gitignore.
- A read of `.acp-agent/transcripts/x.jsonl` by its explicit path still works.

## Acceptance

- `swift build --build-tests` and `swift test` pass with no new warnings.
- The tests above pass.
- `README.md` names the new option in the `files` section. #files