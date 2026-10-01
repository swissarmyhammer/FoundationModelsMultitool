---
comments:
- actor: claude-code
  id: 01m3sbr23vtjhkr29nmqtnp4a6
  text: |-
    ### finish — skipped (not started)
    - reason: the package build fails now in dependency FoundationModelsMetadataRegistry (PooledTextEmbedding.swift:65:18, 'PooledEmbedder' has no member 'dimension'). No test can go green until registry card 01M3QMDGD8148YNDHWBB1YXAQ1 is done and pushed.
    - reason: the working tree holds uncommitted changes of ^vg37780. A `/commit` for this card would put those changes in the wrong commit.
    - next: when the registry card is pushed, finish ^vg37780 first, then run `/finish` for this card.
  timestamp: 2026-09-30T14:33:24.347971+00:00
position_column: todo
position_ordinal: '8280'
title: Adopt LiveModelLoader(reporting:)
---
## What
FoundationModelsRouter changed the public initializer of `LiveModelLoader` (pushed as ce67176/afd9b5a, CI green). The old `LiveModelLoader(downloader:tokenizerLoader:weightsLocation:…)` is deleted; the new one is `LiveModelLoader(reporting: @escaping @Sendable (DownloadProgress) -> Void = { _ in })`. Models load through the Extras `MLXModelLoader`, so the caller gives no downloader and no tokenizer loader.

```swift
let router = Router(recordingsDir: dir, loader: LiveModelLoader())
```

- Change each call of the old initializer to `LiveModelLoader()` or `LiveModelLoader(reporting:)`: `Sources/MultitoolCLI/CLIRunner.swift` (~line 952) and `IntegrationTests/Tests/FoundationModelsMultitoolIntegrationTests/Support/LiveRouterFixture.swift` (~line 622).
- Remove the `#hubDownloader()` / `#huggingFaceTokenizerLoader()` imports and the `HuggingFace`, `Tokenizers` and `MLXHuggingFace` products that only those calls used (in `Package.swift` and `IntegrationTests/Package.swift`).
- `swift package update`, confirm the Router revision is afd9b5a or later; push to `origin main` when green.

## Acceptance Criteria
- [ ] No file calls `LiveModelLoader(downloader:`.
- [ ] The package and its IntegrationTests build.
- [ ] CI is green on the pushed commit.

## Tests
- [ ] `swift build` and `swift test` pass.
- [ ] `swift test --package-path IntegrationTests` passes (the real-model resolve still loads the models).

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass. #model-pool