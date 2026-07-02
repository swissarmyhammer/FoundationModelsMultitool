---
comments:
- actor: wballard
  id: 01kwgcnr8eyx5228q73e8yjqf0
  text: |-
    Superseded: all 3 acceptance-criteria items in this task's description (renderObjectType keys via objectKeyLiteral, the "@param args.<key>" line's key escaping, and tsLiteral's .string case escaping via escapeForJSStringLiteral) were independently found and fixed as part of task v2ccaqx's third review-round pass (2026-07-01 21:41 review findings), which required a full re-audit of ToolAPIRenderer.swift for the same bug class. See v2ccaqx's task comments for the full diff description and test coverage (5 new tests + 3 new fixtures covering these sites, plus 2 more sites found in that same audit: the @returns line's return-type copy and the @example line's example-call copy, plus a follow-up patternClause fix for a trailing-`*` pattern edge case).

    Recommend closing this task as redundant, or verifying against the current ToolAPIRenderer.swift before doing so — leaving that decision to the board owner since closing tasks is out of scope for the implement pass that surfaced this.
  timestamp: 2026-07-02T03:06:34.638489+00:00
position_column: todo
position_ordinal: '9180'
title: 'ToolAPIRenderer: escape remaining unescaped schema-derived splice sites (renderObjectType keys, @param args.<key>, enum literals)'
---
## What

Follow-up to task `v2ccaqx` (M2: ToolAPIRenderer — GenerationSchema → TS declaration + JSDoc), found by an adversarial double-check review while fixing that task's 7 review findings about unescaped schema-derived text.

The double-check reviewer identified the same splice-without-escaping bug class at three more sites in `Sources/FoundationModelsMultitool/Surface/ToolAPIRenderer.swift` that were outside the 7 findings `v2ccaqx` targeted:

1. `renderObjectType`: `parts.append("\(key)\(optionalMark): \(propertyType)")` — property keys are spliced bare into the TS object-type declaration (the actual `args:`/`@returns` type embedded in `declare function ...`), not run through `objectKeyLiteral`. This is arguably the most serious of the three since it lands inside the real function signature, not just a doc/example.
2. `render(name:description:parameters:returns:onWiden:)`: `paramLines.append(... "@param args.\(key) — ...")` — property `key` is spliced into the JSDoc `@param` line unescaped (only the description text after the em dash goes through `escapeForJSDocComment`).
3. `tsLiteral`'s `.string` case (`return "\"\(string)\""`), used by `enumUnion` — enum choice values are rendered unescaped both in the TS type union embedded directly in the `declare function` signature (`renderObjectType`/`tsType`'s `typeString` branch) and in the `@param`'s `"one of ..."` doc clause.

Note: `v2ccaqx`'s work already added the shared helpers `isLegalTSIdentifier`, `escapeForJSStringLiteral`, `objectKeyLiteral`, and `escapeForJSDocComment` — this task should reuse them, not reinvent escaping logic.

## Acceptance Criteria

- [ ] `renderObjectType`'s property keys route through `objectKeyLiteral` (bare when a legal TS identifier, quoted+escaped otherwise) — same as the two `exampleFields`/`exampleObjectLiteral` sites `v2ccaqx` already fixed.
- [ ] The `@param args.<key>` line's `key` is validated/escaped so it can't break out of the JSDoc block or the `args.` accessor syntax.
- [ ] `tsLiteral`'s `.string` case (and therefore `enumUnion`) escapes embedded quotes via `escapeForJSStringLiteral`, both where it lands in the TS type union and in the `@param`'s "one of ..." doc clause.
- [ ] Table-driven test coverage added for each site (adversarial property name / enum value inputs), matching the corpus style already established in `Tests/FoundationModelsMultitoolTests/ToolAPIRendererTests.swift`.
- [ ] `swift build` and `swift test` green.

## Workflow

Use `/tdd` — write failing tests first per site, then implement to make them pass.
