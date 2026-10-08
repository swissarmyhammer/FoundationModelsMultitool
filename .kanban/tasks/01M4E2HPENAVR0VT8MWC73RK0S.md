---
assignees:
- claude-code
depends_on:
- 01M4E1X8XTSWVC55RYD9P3E1NH
- 01M4E1XR9RGN1BNPYHWDKT9H63
position_column: todo
position_ordinal: '8380'
title: Add the tools.environment.now verb for the date and the time
---
## What
Add the `now` verb to `EnvironmentCapability`. One verb gives the date and the time (decision from the user, 2026-10-08: one `now` verb, not separate `date` and `time` verbs).

File to create:
- `Sources/FoundationModelsMultitool/Capabilities/Environment/Now.swift` — `struct Now: Tool` with `name = "now"`.
  - `@Generable struct NowArguments { var timeZone: String? }` — an optional IANA time zone identifier, for example `Europe/Paris`. When it is `nil`, use `context.timeZone`.
  - `@Generable struct NowResult` with these fields:
    - `iso8601` — the local time with its offset, for example `2026-10-08T14:03:27-07:00`.
    - `utc` — the same instant in UTC, for example `2026-10-08T21:03:27Z`.
    - `date` — `yyyy-MM-dd`.
    - `time` — `HH:mm:ss` (24-hour).
    - `weekday` — the English name, for example `Thursday`.
    - `timeZone` — the identifier, for example `America/Los_Angeles`.
    - `utcOffset` — for example `-07:00`.
    - `epochSeconds` — whole seconds since 1970-01-01T00:00:00Z.
    - `correction: String?`
  - An unknown `timeZone` identifier gives a `correction` that names the bad identifier, and all other fields are empty or zero. The verb does not throw (the correction stays in band).
  - Use a `Calendar(identifier: .gregorian)` and the `en_US_POSIX` locale for each format, so the output does not change with the user's locale.

Files to modify:
- `Sources/FoundationModelsMultitool/Capabilities/Environment/EnvironmentCapability.swift` — add `Now(context:)` to `tools`.

Write comments in ASD-STE100 Simplified Technical English.

## Acceptance Criteria
- [ ] With an injected clock at a fixed instant and an injected time zone, each field is exactly the expected text.
- [ ] `timeZone: "Asia/Tokyo"` changes `iso8601`, `date`, `time`, `weekday`, `timeZone`, and `utcOffset`, but not `utc` or `epochSeconds`.
- [ ] A time zone with daylight saving time gives the correct offset on each side of the change.
- [ ] `timeZone: "Not/AZone"` gives a `correction`, not a thrown error.

## Tests
- [ ] `Tests/FoundationModelsMultitoolTests/EnvironmentNowTests.swift` — the cases above, each with an injected clock (never the real clock for exact values).
- [ ] Update `EnvironmentCapabilityTests.swift` for the new verb name, and the builder surface golden if it lists the verbs.
- [ ] Run `swift test` — all tests pass.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass. #environment