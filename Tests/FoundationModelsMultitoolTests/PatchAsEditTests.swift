// `PatchAsEditTests` — a `files.patch` call with the arguments of an edit
// runs that edit ("Postel's rule": be liberal in what you accept).
//
// dotask24 django__django-13447 seq 738 and kanban24 django__django-14997
// seq 23317: `tools.files.patch({ path, edits: [{ oldText, newText }] })`
// failed with `Tool "patch" is missing its required argument "patch"`.

import Foundation
import Testing

@testable import FoundationModelsMultitool
@testable import MultitoolTestSupport

@Suite(.ownsTemporaryDirectories) struct PatchAsEditTests {

    /// Runs `code` on a surface with the files capability over a root with
    /// `s.py`, and answers the output and the text of `s.py` after the run.
    private static func run(_ code: String) async throws -> (output: String, file: String) {
        let root = TestSupport.makeTemporaryDirectory(named: "PatchAsEditTests")
        let url = root.appendingPathComponent("s.py")
        try Data("APPS = [\n    'django.contrib.admin',\n    'x',\n]\n".utf8).write(to: url)
        let registry = try MultiTool.Builder(mode: .open).withFiles(root: root, readOnly: false).buildRegistry()
        let output = try await MultiTool(registry: registry).call(arguments: RunCodeArguments(code: code))
        return (output, try String(contentsOf: url, encoding: .utf8))
    }

    @Test("the snippet of seq 738: patch with edits of oldText and newText edits the file")
    func patchWithEditsRunsTheEdit() async throws {
        let (output, file) = try await Self.run(
            #"""
            const r = await tools.files.patch({ path: "s.py", edits: [{ oldText: "    'django.contrib.admin',", newText: "    'django.contrib.admin.apps.SimpleAdminConfig'," }, { oldText: "'x'", newText: "'y'" }] });
            return { correction: r.correction };
            """#)

        #expect(file.contains("'django.contrib.admin.apps.SimpleAdminConfig',"), "output was: \(output)")
        #expect(file.contains("'y'"), "file was: \(file)")
    }

    @Test("patch with one top-level pair of old_string and new_string edits the file")
    func patchWithOnePairRunsTheEdit() async throws {
        let (output, file) = try await Self.run(
            #"return await tools.files.patch({ path: "s.py", old_string: "'x'", new_string: "'z'" });"#)

        #expect(file.contains("'z'"), "output was: \(output)")
    }

    @Test("edit takes the edits shape too")
    func editTakesTheEditsShape() async throws {
        let (output, file) = try await Self.run(
            #"return await tools.files.edit({ path: "s.py", edits: [{ oldText: "'x'", newText: "'w'" }] });"#)

        #expect(file.contains("'w'"), "output was: \(output)")
    }
}
