---
assignees:
- claude-code
position_column: doing
position_ordinal: '8180'
title: Fix vendored mlx-swift-lm compile failure against current Xcode-beta SDK (GenerationOptions.SamplingMode.Kind rename)
---
## What
Discovered incidentally while implementing task `h6rqz4v` (Retire callTool/DirectToolCall escape hatch). The vendored `mlx-swift-lm` dependency (pinned commit `e6ccd272`, branch `mlx-foundationmodels`, checked out under `.build/checkouts/mlx-swift-lm`) fails to compile against the currently-installed Xcode-beta SDK because Apple renamed `GenerationOptions.SamplingMode.Kind`'s cases: `.top`/`.nucleus` are now `.randomTopK`/`.randomProbabilityThreshold`.

Confirmed via `git stash` that this is pre-existing and unrelated to any change in this repo — it's purely a vendored-dependency-vs-SDK version skew. It was worked around locally only inside `.build/checkouts/` (gitignored, not part of any diff) to unblock verification builds during `h6rqz4v`'s implementation.

## Acceptance Criteria
- [ ] Identify the correct long-term fix: either pin to an `mlx-swift-lm` revision that already targets the renamed API, or update the vendored pin/patch so `swift build`/`swift build --build-tests` succeed against the current Xcode-beta SDK without a manual local workaround.
- [ ] `swift build` and `swift build --build-tests` succeed from a clean checkout with no manual intervention in `.build/`.
- [ ] Document the SDK/toolchain version dependency if it's expected to recur (e.g. in README or a comment near the dependency declaration in `Package.swift`).
