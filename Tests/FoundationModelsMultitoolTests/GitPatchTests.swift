import Foundation
import Testing

@testable import FoundationModelsMultitool

/// Behavioral tests for the git-format patch a ``FileChangeSet`` renders.
///
/// This suite is a port of the sibling FileTool suite. It pins the exact
/// wire text of every change kind — a modification's unified hunk, a
/// creation's `new file mode` / `/dev/null` pairing, a deletion's inverse, a
/// rename's `rename from` / `rename to` headers, the
/// `\ No newline at end of file` marker, and the binary placeholder for
/// content that could not be captured — thus a client that parses the patch
/// sees genuine git format. The rendering is pure, thus every case here
/// builds ``FileChange`` values directly.
@Suite struct GitPatchTests {
    // MARK: Test scaffolding

    /// The session root every rendered path is relative to.
    private static let root = URL(fileURLWithPath: "/repo", isDirectory: true)

    /// The number of lines in the long-file case: enough to hold two edits
    /// more than one context width apart, thus they render as two hunks.
    private static let longFileLineCount = 20

    /// The number of hunks the two distant edits in the long-file case make.
    private static let distantEditHunkCount = 2

    /// The absolute path of `name` under ``root``.
    ///
    /// - Parameter name: the file name.
    /// - Returns: the absolute path.
    private static func path(_ name: String) -> String {
        root.appendingPathComponent(name, isDirectory: false).path
    }

    /// The patch of a change set carrying `changes`.
    ///
    /// - Parameter changes: the changes to render.
    /// - Returns: the git-format patch.
    private static func patch(_ changes: FileChange...) -> String {
        FileChangeSet(root: root, changes: changes).patch
    }

    // MARK: Modify

    @Test func aModifiedFileRendersAUnifiedHunk() {
        let patch = Self.patch(
            FileChange(
                kind: .modify,
                path: Self.path("code.txt"),
                oldContent: "one\ntwo\nthree\n",
                newContent: "one\nTWO\nthree\n"
            )
        )

        #expect(
            patch == """
                diff --git a/code.txt b/code.txt
                --- a/code.txt
                +++ b/code.txt
                @@ -1,3 +1,3 @@
                 one
                -two
                +TWO
                 three

                """
        )
    }

    @Test func distantChangesRenderAsSeparateHunks() {
        let old = (1...Self.longFileLineCount).map { "line \($0)\n" }.joined()
        let new =
            old
            .replacingOccurrences(of: "line 2\n", with: "LINE 2\n")
            .replacingOccurrences(of: "line 19\n", with: "LINE 19\n")

        let patch = Self.patch(
            FileChange(kind: .modify, path: Self.path("code.txt"), oldContent: old, newContent: new)
        )

        #expect(patch.components(separatedBy: "@@ -").count - 1 == Self.distantEditHunkCount)
        #expect(patch.contains("@@ -1,5 +1,5 @@"))
        #expect(patch.contains("@@ -16,5 +16,5 @@"))
    }

    @Test func anUnchangedFileRendersNothing() {
        let patch = Self.patch(
            FileChange(
                kind: .modify, path: Self.path("code.txt"), oldContent: "same\n", newContent: "same\n")
        )

        #expect(patch.isEmpty)
    }

    // MARK: Add and delete

    @Test func anAddedFileRendersAsACreationAgainstDevNull() {
        let patch = Self.patch(
            FileChange(kind: .add, path: Self.path("new.txt"), newContent: "hello\n")
        )

        #expect(
            patch == """
                diff --git a/new.txt b/new.txt
                new file mode 100644
                --- /dev/null
                +++ b/new.txt
                @@ -0,0 +1 @@
                +hello

                """
        )
    }

    @Test func aDeletedFileRendersAsARemovalIntoDevNull() {
        let patch = Self.patch(
            FileChange(kind: .delete, path: Self.path("gone.txt"), oldContent: "obsolete\n")
        )

        #expect(
            patch == """
                diff --git a/gone.txt b/gone.txt
                deleted file mode 100644
                --- a/gone.txt
                +++ /dev/null
                @@ -1 +0,0 @@
                -obsolete

                """
        )
    }

    // MARK: Move and copy

    @Test func aPureRenameRendersRenameHeadersWithNoHunk() {
        let patch = Self.patch(
            FileChange(
                kind: .move,
                path: Self.path("source.txt"),
                destinationPath: Self.path("dest.txt"),
                oldContent: "keep me\n",
                newContent: "keep me\n"
            )
        )

        #expect(
            patch == """
                diff --git a/source.txt b/dest.txt
                rename from source.txt
                rename to dest.txt

                """
        )
    }

    @Test func aRenameThatAlsoEditsRendersRenameHeadersAndAHunk() {
        let patch = Self.patch(
            FileChange(
                kind: .move,
                path: Self.path("source.txt"),
                destinationPath: Self.path("dest.txt"),
                oldContent: "before\n",
                newContent: "after\n"
            )
        )

        #expect(
            patch == """
                diff --git a/source.txt b/dest.txt
                rename from source.txt
                rename to dest.txt
                --- a/source.txt
                +++ b/dest.txt
                @@ -1 +1 @@
                -before
                +after

                """
        )
    }

    @Test func aCopyRendersCopyHeaders() {
        let patch = Self.patch(
            FileChange(
                kind: .copy,
                path: Self.path("source.txt"),
                destinationPath: Self.path("duplicate.txt"),
                oldContent: "shared\n",
                newContent: "shared\n"
            )
        )

        #expect(
            patch == """
                diff --git a/source.txt b/duplicate.txt
                copy from source.txt
                copy to duplicate.txt

                """
        )
    }

    // MARK: Line-terminator edges

    @Test func aFinalLineWithoutANewlineCarriesTheNoNewlineMarker() {
        let patch = Self.patch(
            FileChange(kind: .modify, path: Self.path("code.txt"), oldContent: "a\nb", newContent: "a\nB")
        )

        #expect(
            patch == """
                diff --git a/code.txt b/code.txt
                --- a/code.txt
                +++ b/code.txt
                @@ -1,2 +1,2 @@
                 a
                -b
                \\ No newline at end of file
                +B
                \\ No newline at end of file

                """
        )
    }

    @Test func addingAFinalNewlineRewritesTheLastLine() {
        let patch = Self.patch(
            FileChange(
                kind: .modify, path: Self.path("code.txt"), oldContent: "a\nb", newContent: "a\nb\n")
        )

        #expect(
            patch == """
                diff --git a/code.txt b/code.txt
                --- a/code.txt
                +++ b/code.txt
                @@ -1,2 +1,2 @@
                 a
                -b
                \\ No newline at end of file
                +b

                """
        )
    }

    @Test func carriageReturnsStayInsideTheRenderedLines() {
        let patch = Self.patch(
            FileChange(
                kind: .modify,
                path: Self.path("code.txt"),
                oldContent: "one\r\ntwo\r\nthree\r\n",
                newContent: "one\r\nTWO\r\nthree\r\n"
            )
        )

        // Git's line model splits on `\n` only, thus a CRLF file's `\r` is part
        // of the line's content and must survive into the hunk; a dropped `\r`
        // would rewrite every terminator in the file when the patch is applied.
        let expected = [
            "diff --git a/code.txt b/code.txt\n",
            "--- a/code.txt\n",
            "+++ b/code.txt\n",
            "@@ -1,3 +1,3 @@\n",
            " one\r\n",
            "-two\r\n",
            "+TWO\r\n",
            " three\r\n",
        ].joined()
        #expect(patch == expected)
    }

    @Test func aLoneCarriageReturnIsNotALineBreak() {
        let patch = Self.patch(
            FileChange(kind: .modify, path: Self.path("code.txt"), oldContent: "a\rb", newContent: "a\rB")
        )

        let expected = [
            "diff --git a/code.txt b/code.txt\n",
            "--- a/code.txt\n",
            "+++ b/code.txt\n",
            "@@ -1 +1 @@\n",
            "-a\rb\n",
            "\\ No newline at end of file\n",
            "+a\rB\n",
            "\\ No newline at end of file\n",
        ].joined()
        #expect(patch == expected)
    }

    @Test func anEmptyAddedFileRendersHeadersOnly() {
        let patch = Self.patch(
            FileChange(kind: .add, path: Self.path("empty.txt"), newContent: "")
        )

        #expect(
            patch == """
                diff --git a/empty.txt b/empty.txt
                new file mode 100644

                """
        )
    }

    // MARK: Uncapturable content

    @Test func aChangeWithUncapturableTextRendersAsBinary() {
        let patch = Self.patch(
            FileChange(kind: .modify, path: Self.path("image.png"), oldContent: nil, newContent: "text\n")
        )

        #expect(
            patch == """
                diff --git a/image.png b/image.png
                index 0000000..0000000 100644
                Binary files a/image.png and b/image.png differ

                """
        )
    }

    @Test func anUncapturableCreationNamesDevNullOnTheOldSide() {
        let patch = Self.patch(
            FileChange(kind: .add, path: Self.path("image.png"), newContent: nil)
        )

        #expect(
            patch == """
                diff --git a/image.png b/image.png
                new file mode 100644
                index 0000000..0000000
                Binary files /dev/null and b/image.png differ

                """
        )
    }

    @Test func anUncapturableDeletionNamesDevNullOnTheNewSide() {
        let patch = Self.patch(
            FileChange(kind: .delete, path: Self.path("image.png"), oldContent: nil)
        )

        #expect(
            patch == """
                diff --git a/image.png b/image.png
                deleted file mode 100644
                index 0000000..0000000
                Binary files a/image.png and /dev/null differ

                """
        )
    }

    /// The zeroed `index` line is what makes `git apply` refuse a binary
    /// section loudly instead of a silent skip, thus it must appear on exactly
    /// the sections that carry a placeholder — never on a diffable one, where
    /// a fabricated blob hash would be a lie about content git can read.
    @Test func onlyTheBinaryPlaceholderCarriesAnIndexLine() {
        let patch = Self.patch(
            FileChange(kind: .modify, path: Self.path("text.txt"), oldContent: "a\n", newContent: "b\n"),
            FileChange(kind: .modify, path: Self.path("image.png"), oldContent: nil, newContent: nil),
            FileChange(kind: .move, path: Self.path("old.png"), destinationPath: Self.path("new.png"))
        )

        #expect(
            patch == """
                diff --git a/text.txt b/text.txt
                --- a/text.txt
                +++ b/text.txt
                @@ -1 +1 @@
                -a
                +b
                diff --git a/image.png b/image.png
                index 0000000..0000000 100644
                Binary files a/image.png and b/image.png differ
                diff --git a/old.png b/new.png
                rename from old.png
                rename to new.png
                index 0000000..0000000 100644
                Binary files a/old.png and b/new.png differ

                """
        )
    }

    // MARK: Multi-file and nesting

    @Test func aMultiFileChangeSetRendersOneSectionPerFileInOrder() {
        let patch = Self.patch(
            FileChange(kind: .add, path: Self.path("added.txt"), newContent: "added\n"),
            FileChange(kind: .delete, path: Self.path("gone.txt"), oldContent: "gone\n")
        )

        #expect(patch.hasPrefix("diff --git a/added.txt b/added.txt\n"))
        #expect(patch.contains("\ndiff --git a/gone.txt b/gone.txt\n"))
    }

    @Test func aNestedPathRendersRelativeToTheRoot() {
        let patch = Self.patch(
            FileChange(kind: .add, path: Self.path("Sources/deep/file.swift"), newContent: "code\n")
        )

        #expect(patch.hasPrefix("diff --git a/Sources/deep/file.swift b/Sources/deep/file.swift\n"))
    }

    @Test func anEmptyChangeSetRendersAnEmptyPatch() {
        #expect(FileChangeSet(root: Self.root, changes: []).patch.isEmpty)
    }
}
