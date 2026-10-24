---
assignees:
- claude-code
position_column: done
position_ordinal: ffffffd280
title: 'tools: shell.execute result answers stdout/stderr/code/ok; cwd and co. stand for workingDirectory'
---
bench24-1023b, django__django-14534 (child seq 13568): `r.stdout.slice(-3000)` threw after the tests ran, so the model ran them again. An execute result now answers stdout/out/text (its output tail as one string, without the "N: " prefixes), stderr (""; the shell merges the streams), code/returncode/exit (exitCode), and ok/success. Real fields (output, lines, status) win. ToolInvoker: cwd/dir/directory/workdir/workingdir/cd → workingDirectory. Test: ShellResultAndPositionalTests. #bench