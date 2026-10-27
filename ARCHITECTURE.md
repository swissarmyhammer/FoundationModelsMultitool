# Architecture

## No backward compatibility

This package has not shipped, and none of the swissarmyhammer packages has. We do not keep backward compatibility, and we do not write code for it.

- When a file format or an on-disk layout changes, write and read only the new one. Do not keep a reader for the old format, and do not write migration code. Data on disk in the old format may simply stop working.
- When an API changes, change every caller in the same change, or in the packages that depend on it. Do not keep deprecated aliases, shims, or old overloads.
- Do not keep a schema version only so that an old file can still be read.

This rule holds until we ship. When we ship, this section will say what we promise from then on.

## Line numbers start at 1

Each line number and each column that the model sees or gives starts at 1. This is the same as an editor, a compiler message, a traceback and `grep -n`.

- `files.read` takes `offset` as a 1-based line. Its hashline anchors `N:HH|text` give the 1-based line `N`.
- `files.edit` and `files.patch` give 1-based lines in their spans, their context lines and their parse failures.
- `files.grep` gives the 1-based `line` of each match and each context line. A line from `files.grep` goes directly into `files.read` and `files.edit`.
- `tools.code_context` uses the same rule. FoundationModelsCodeContext does the conversion at its tool boundary (see its ARCHITECTURE.md).

Code inside the package can use 0-based indexes into an array of lines. Convert at the tool boundary, in one location. Do not send a 0-based value to the model, and do not accept one from it. When you add a result type with a line or a column, write "1-based" in its doc comment and add a test for it.
