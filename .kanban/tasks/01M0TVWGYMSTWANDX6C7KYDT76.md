---
assignees:
- claude-code
position_column: todo
position_ordinal: '9080'
title: A host-supplied ShellOutputChunkStream never receives a chunk
---
## What

`ShellCapability(storeDirectory:sandbox:outputChunkStream:)` and
`MultiTool.Builder.withShell(...)` both take a `ShellOutputChunkStream`, and both
carry it to `ShellRunner.outputChunkStream`. A host that subscribes to that
stream reads nothing, because `Execute` replaces it for each run.

`Sources/FoundationModelsMultitool/Capabilities/Shell/Execute.swift`,
`report(of:in:)`:

    let stream = ShellOutputChunkStream()
    var running = runner
    running.outputChunkStream = stream
    let pump = Task { await Self.reportOutput(of: stream, to: context) }

The verb needs a stream of its own: it drains that stream to post one `progress`
event for each chunk, and it calls `finish()` on it when the run ends, so it
cannot share a stream that outlives the run. But the assignment DROPS the stream
the host configured, so `ShellRunner.consume` tees into the private stream and
into nothing else.

Two shapes answer it, and the choice is the work of this card:

1. `ShellRunner.consume` tees into BOTH — the private stream of the verb and the
   configured one. `ShellOutputChunkStream.send` never blocks, so a second tee
   costs the child nothing.
2. `Execute` drains the CONFIGURED stream where one is there, and makes a
   private one only where none is. `finish()` then ends a stream the host still
   holds, which is wrong for a host that watches more than one run, so this
   shape needs a per-run end rather than `finish()`.

## Acceptance Criteria

- [ ] A `ShellOutputChunkStream` handed to `ShellCapability` receives the output
      chunks of a run, and its terminal marker.
- [ ] The `progress` events `Execute` posts are unchanged.
- [ ] A run with no configured stream behaves exactly as it does today.

## Tests

- [ ] A test subscribes to a stream handed to `ShellCapability`, runs one
      command through `tools.shell.execute`, and reads the chunks that command
      wrote.
- [ ] A test holds the `progress` events of that same run to what they are
      today.

Found while implementing ^zpdk266, which wired the parameter the card asked for.
#phase-2 #eventplan