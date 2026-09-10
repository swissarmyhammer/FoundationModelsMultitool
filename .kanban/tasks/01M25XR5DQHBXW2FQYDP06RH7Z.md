---
assignees:
- claude-code
depends_on:
- 01M25MFASNMHXXFCZEMKN9AY20
position_column: todo
position_ordinal: '8680'
title: The selection tier misses the shell verbs on held-out queries, and answers nothing for one of them
---
## What the held-out suite found

Card `^kn9ay20` added `HeldOutSurfaceDiscoveryTests`: fifteen queries written
from a task description alone, over the same nine-entry files-and-shell surface
and the same `agentFlashModel` (`mlx-community/Qwen3-4B-4bit`) as the ten
recorded queries of card `^zqz1zan`.

Measured 2026-09-10, three rounds, identical in every round:

- correct paths found: 9 of the 22 declared, each round.
- undeclared paths returned: 8, each round.
- six of the fifteen queries found no declared path at all, in every round.

The ten recorded queries scored 19 of 25 in the same runs. So the gap is not
the model and not the surface: it is the wording of the queries the tier was
never fitted to.

## The six queries that fail, and what the tier answered

| query | declared | answered |
| --- | --- | --- |
| rewrite the whole contents of a module | files.write, files.patch | files.edit |
| i want to run the project test suite now | shell.execute | nothing at all |
| i need to see what the failing test printed | shell.getLines, shell.grepHistory | files.read |
| delete a leftover temporary directory | shell.execute | files.glob, files.edit |
| remove a scratch file i made earlier | files.patch, shell.execute | files.glob, files.edit, files.write |
| check which source files i have changed so far | shell.execute | files.glob |

Two readings stand out.

**The empty answer is back.** "i want to run the project test suite now" gets
`{"ids":[]}` — the same failure card `^zqz1zan` records, on a query the
preamble was never fitted to. The preamble tells the model to prefer the
closest candidate over an empty answer, and on this wording it does not.

**The shell capability is nearly invisible.** Four of the six ask for a command
or for the output of one. `shell.getLines` and `shell.grepHistory` were never
selected one time in 45 calls. The tier answers a files verb for almost every
phrasing that does not carry the word "run" or "shell".

## What to do

Find why, and fix the cause rather than the six queries. The places to look:

1. The entry descriptions of `shell.execute`, `shell.getLines` and
   `shell.grepHistory`. They may say what the verb does and not what a person
   wants when they ask for it.
2. The retrieval step in front of the selection model, which decides which
   entries the model even reads.
3. The selection preamble, which card `^zqz1zan` chose against the ten
   recorded queries alone.

Do not lower `heldOutRoundCorrectLevel` and do not change a held-out query to
match what the tier answers. Both make the reading disappear rather than the
defect.

## Acceptance Criteria

- [ ] The cause of the empty answer for "i want to run the project test suite now" is named.
- [ ] The cause of the missing shell verbs is named.
- [ ] `HeldOutSurfaceDiscoveryTests` passes over three rounds, with no assertion made weaker.
- [ ] `AgentSurfaceDiscoveryTests` still holds its own level of 19.

## Tests

- [ ] `swift test --package-path IntegrationTests --no-parallel`, for both discovery suites.

#discovery #search-tools #selection-tier