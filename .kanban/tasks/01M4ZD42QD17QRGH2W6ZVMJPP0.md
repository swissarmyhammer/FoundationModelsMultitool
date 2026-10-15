---
assignees:
- claude-code
position_column: done
position_ordinal: fffff280
title: Read the elicitation deliveries only after the sink recorded them
---
CI run 38709487896 on main failed at SandboxGlobalsTests.swift:481 ("elicit(\"question\") suspends the snippet and resumes with the accepted answer"): `await sink.deliveries == [.delivered]` read an empty log.

Cause: in Tests/FoundationModelsMultitoolTests/Fixtures/SandboxGlobalsFixtures.swift, `ScriptedElicitationSink.watch` calls `run.session.respond(...)`. That call resumes the snippet. The watch records the delivery with `log.record(delivery:)` only after `respond` returns. The test read the log when the snippet returned, thus it could read the log before the record. The URL-mode test had the same race on `completions` (`complete` resumes the snippet before `log.record(completion:)`).

Fix: `deliveries(count:)` and `completions(count:)` wait until the log recorded the count. `record(...)` wakes each waiter; the end of the watch also wakes them. No clock, no poll.

Changed tests: elicitStringShorthandRoundTripsAnAcceptedAnswer, elicitUrlModeResolvesAfterCompletion. New proof test: theDeliveriesReadWaitsForTheRecord (fixed order through the `holdingRecordAt:` test hook).

#mail-step-5 #bad-test