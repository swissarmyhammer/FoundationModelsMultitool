---
assignees:
- claude-code
depends_on:
- 01M48VAY56DD7FRP5ZN9F4RD5E
- 01M48V8V37DM9YG6EQ1ZDB38Q4
- 01M48V95RGBAG8P7ENHJMM1A0K
- 01M48VA2QSPSBZ18AAAFDVR81S
- 01M48VA6MJK1WHXPJYJ4AC64T6
- 01M48VAAXDRA9N07ACFBT90ANX
position_column: todo
position_ordinal: 8d80
title: 'git: live model tests, README section, and git.md status'
---
## Goal

Close the `git` capability: prove it with the real model, document it, and mark the plan as shipped.

## Work

1. Integration tests in `IntegrationTests/` (the nested package) that mount `withGit(root:)` on a temporary repository and let the real model answer through `runCode`. Use the goal snippet of `git.md` as one scenario. Add scenarios for `status`, `log`, `show`, `blame`, and a `diff` of a renamed function.
2. Follow the rules of the integration suite:
   - Each test runs on each push. No nightly split, no skip, no repeated rounds. The whole suite stays in 20 minutes; measure the new time and record it in a comment.
   - Assert code properties only (for example: the snippet called `tools.git.diff`, the result has no `correction`). Print model scores; do not assert a fixed score.
3. `README.md`: add a `git` section in the form of the `files` and `web` sections: `withGit(root:)`, the verb table, the read-only rule, the root rule, and the language list of the semantic diff.
4. `git.md`: change "Status of this document" to say that the code shipped, and that the code and `README.md` are correct when they are different from this document (the same text as `web.md`).
5. Check the rendered surface goldens, and the search catalog metadata (`Surface/APISurface+SearchableMetadata.swift`), so that a search for "git", "diff", "blame", or "branch" finds the verbs.

## Acceptance

- `swift build` and `swift test` pass with no new warnings.
- `swift test --package-path IntegrationTests --no-parallel` passes, in 20 minutes or less in total. #git