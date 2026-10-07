// The build unit of the external scanner of the Python grammar.
//
// `src/scanner.c` is the file of the tag `v0.25.0` of
// https://github.com/tree-sitter/tree-sitter-python with no change. The
// target does not compile it directly (see `Package.swift`,
// `treeSitterPythonTargetName`): it compiles this file, which includes it.
//
// Why: the C compiler of a root package of SwiftPM enables the warning
// `-Wshorten-64-to-32`, and `src/scanner.c` gives three such warnings (a
// `size_t` value goes into a 32-bit field). SwiftPM does not show the
// warnings of a remote package, and the Rust `cc` build of the same file does
// not enable this warning. A change to the upstream file would make it
// different from the grammar of the Rust crate, thus this file stops the one
// warning for the upstream scanner only.
#pragma clang diagnostic ignored "-Wshorten-64-to-32"

#include "src/scanner.c"
