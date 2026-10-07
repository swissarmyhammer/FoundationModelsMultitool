// `GitDiffTests` — the behavioral suite of the `tools.git.diff` verb.
//
// The suite makes `DiffArguments` with the memberwise initializer and calls
// the `Diff` verb directly, the way `GitShowTests` calls its verb. Each test
// makes its own temporary folder or repository, thus the tests are
// independent and they run in parallel safely.
//
// The first tests are the ports of the tests of `diff/mod.rs` in
// `../swissarmyhammer/crates/swissarmyhammer-tools/src/mcp/tools/git/`:
// `parse_file_ref`, `language_to_extension`, and the inline mode.

import Foundation
import Testing

@testable import FoundationModelsMultitool
@testable import MultitoolTestSupport

/// Behavioral tests for the `tools.git.diff` verb (task `^9f4rd5e`).
///
/// The card names each case: the inline mode with a missing argument and
/// with an unknown language; the file mode with `a.swift@HEAD~1` against
/// `a.swift`, a path outside the root, and an unknown ref; and the automatic
/// mode with a clean tree and with one staged and one unstaged file. The
/// staged-rename cases of the automatic mode come from task `^wvmh7vf`, and
/// the rename to a path outside the root comes from task `^pt6fyf0`.
@Suite("GitDiffTests")
struct GitDiffTests {

    /// The name of the temporary folder of one test. Thus a leaked folder is
    /// traceable to this suite.
    private static let testDirectoryName = "GitDiffTests"

    /// The Swift file of the file mode and of the automatic mode.
    private static let swiftFile = "a.swift"

    /// The second Swift file of the automatic mode.
    private static let otherSwiftFile = "b.swift"

    /// The first version of a Swift file: one function.
    private static let firstSwift = "func greet() -> String {\n    return \"hello\"\n}\n"

    /// The second version of ``firstSwift``: the body of the function
    /// changed.
    private static let secondSwift = "func greet() -> String {\n    return \"hello, world\"\n}\n"

    /// The name of the function of ``firstSwift`` and ``secondSwift``.
    private static let swiftFunctionName = "greet"

    /// The folder of the repository that is the root of a test with a root
    /// below the work folder.
    private static let subfolder = "src"

    /// A Swift file with one function whose body has several lines. A change
    /// of one line keeps most of its tokens, thus the engine pairs the two
    /// versions of the function across two paths (phase 3 of the matcher).
    private static let sumSwift =
        "func total(of values: [Int]) -> Int {\n    var sum = 0\n    for value in values {\n"
        + "        sum += value\n    }\n    return sum\n}\n"

    /// ``sumSwift`` with one changed line: the function returns twice the
    /// sum.
    private static let doubledSumSwift =
        "func total(of values: [Int]) -> Int {\n    var sum = 0\n    for value in values {\n"
        + "        sum += value\n    }\n    return sum * 2\n}\n"

    /// The name of the function of ``sumSwift`` and ``doubledSumSwift``.
    private static let sumFunctionName = "total"

    // MARK: - parse_file_ref

    /// A spec with no `@` is the whole path, with no ref
    /// (`test_parse_file_ref_no_ref`).
    @Test("a spec with no at sign is a path with no ref")
    func aSpecWithNoAtSignIsAPathWithNoRef() {
        #expect(DiffFileSpec(parsing: "src/main.rs") == DiffFileSpec(path: "src/main.rs", ref: nil))
    }

    /// A spec with `@` is the path before it and the ref after it
    /// (`test_parse_file_ref_with_ref`).
    @Test("a spec with an at sign is a path and a ref")
    func aSpecWithAnAtSignIsAPathAndARef() {
        #expect(DiffFileSpec(parsing: "src/main.rs@HEAD~1") == DiffFileSpec(path: "src/main.rs", ref: "HEAD~1"))
    }

    /// A sha is a ref too (`test_parse_file_ref_with_sha`).
    @Test("a spec with a sha after the at sign is a path and a sha")
    func aSpecWithAShaIsAPathAndASha() {
        #expect(DiffFileSpec(parsing: "src/lib.rs@abc123") == DiffFileSpec(path: "src/lib.rs", ref: "abc123"))
    }

    /// An `@` at the start is not a ref: the whole spec is the path
    /// (`test_parse_file_ref_no_path`).
    @Test("an at sign at the start is part of the path")
    func anAtSignAtTheStartIsPartOfThePath() {
        #expect(DiffFileSpec(parsing: "@HEAD") == DiffFileSpec(path: "@HEAD", ref: nil))
    }

    /// An `@` at the end gives no empty ref: the whole spec is the path
    /// (`test_parse_file_ref_trailing_at`).
    @Test("an at sign at the end is part of the path")
    func anAtSignAtTheEndIsPartOfThePath() {
        #expect(DiffFileSpec(parsing: "src/main.rs@") == DiffFileSpec(path: "src/main.rs@", ref: nil))
    }

    /// The last `@` splits the spec (`rfind` in Rust), thus a path can hold
    /// an `@`.
    @Test("the last at sign splits the spec")
    func theLastAtSignSplitsTheSpec() {
        #expect(DiffFileSpec(parsing: "lib@2/a.rs@main") == DiffFileSpec(path: "lib@2/a.rs", ref: "main"))
    }

    // MARK: - language_to_extension

    /// The Rust names give `.rs`, in any case
    /// (`test_language_to_extension_rust`).
    @Test("rust names give the rs extension in any case")
    func rustNamesGiveTheRsExtensionInAnyCase() {
        #expect(Diff.fileExtension(forLanguage: "rust") == ".rs")
        #expect(Diff.fileExtension(forLanguage: "rs") == ".rs")
        #expect(Diff.fileExtension(forLanguage: "Rust") == ".rs")
        #expect(Diff.fileExtension(forLanguage: "RUST") == ".rs")
    }

    /// The TypeScript names give `.ts` (`test_language_to_extension_typescript`).
    @Test("typescript names give the ts extension")
    func typeScriptNamesGiveTheTsExtension() {
        #expect(Diff.fileExtension(forLanguage: "typescript") == ".ts")
        #expect(Diff.fileExtension(forLanguage: "ts") == ".ts")
    }

    /// An unknown name gives `.txt` (`test_language_to_extension_unknown`).
    @Test("an unknown language gives the txt extension")
    func anUnknownLanguageGivesTheTxtExtension() {
        #expect(Diff.fileExtension(forLanguage: "brainfuck") == ".txt")
    }

    /// The Fortran names keep the extension of the Rust table. The fallback
    /// plugin reads a `.f90` file (git.md decision 13).
    @Test("fortran names give the f90 extension")
    func fortranNamesGiveTheF90Extension() {
        #expect(Diff.fileExtension(forLanguage: "fortran") == ".f90")
        #expect(Diff.fileExtension(forLanguage: "f90") == ".f90")
    }

    // MARK: - Inline mode

    /// A changed function is one `modified` change
    /// (`test_inline_diff_modified_function`).
    @Test("inline mode finds a modified function")
    func inlineModeFindsAModifiedFunction() async throws {
        let left = "fn process_data() {\n    println!(\"hello\");\n}\n\nfn other() {\n    println!(\"other\");\n}\n"
        let right =
            "fn process_data(x: i32) {\n    println!(\"hello {}\", x);\n}\n\nfn other() {\n    println!(\"other\");\n}\n"

        let result = try await Self.inlineDiff(left: left, right: right, language: "rust")

        #expect(result.correction == nil)
        #expect(result.summary.modified == 1)
        #expect(result.summary.added == 0)
        #expect(result.summary.deleted == 0)
        let modified = try #require(result.changes.first { $0.changeType == "modified" })
        #expect(modified.entityName == "process_data")
        #expect(modified.filePath == "inline.rs")
        #expect(!modified.isContentCapped)
    }

    /// A new function is one `added` change (`test_inline_diff_added_function`).
    @Test("inline mode finds an added function")
    func inlineModeFindsAnAddedFunction() async throws {
        let left = "fn existing() {\n    println!(\"existing\");\n}\n"
        let right = left + "\nfn new_function() {\n    println!(\"new\");\n}\n"

        let result = try await Self.inlineDiff(left: left, right: right, language: "rust")

        #expect(result.summary.added == 1)
        #expect(result.summary.modified == 0)
        let added = try #require(result.changes.first { $0.changeType == "added" })
        #expect(added.entityName == "new_function")
        #expect(added.beforeContent == nil)
        #expect(added.afterContent?.contains("new_function") == true)
    }

    /// A removed function is one `deleted` change
    /// (`test_inline_diff_deleted_function`).
    @Test("inline mode finds a deleted function")
    func inlineModeFindsADeletedFunction() async throws {
        let right = "fn keep_me() {\n    println!(\"keep\");\n}\n"
        let left = right + "\nfn delete_me() {\n    println!(\"delete\");\n}\n"

        let result = try await Self.inlineDiff(left: left, right: right, language: "rust")

        #expect(result.summary.deleted == 1)
        #expect(result.summary.modified == 0)
        let deleted = try #require(result.changes.first { $0.changeType == "deleted" })
        #expect(deleted.entityName == "delete_me")
        #expect(deleted.afterContent == nil)
    }

    /// TypeScript goes to the code plugin too (`test_inline_diff_typescript`).
    @Test("inline mode reads typescript")
    func inlineModeReadsTypeScript() async throws {
        let left = "export function hello(): string {\n    return \"hello\";\n}\n"
        let right = "export function hello(name: string): string {\n    return `Hello, ${name}!`;\n}\n"

        let result = try await Self.inlineDiff(left: left, right: right, language: "typescript")

        #expect(result.summary.modified == 1)
        let modified = try #require(result.changes.first)
        #expect(modified.entityName == "hello")
    }

    /// The same text on both sides is no change, and the inline mode still
    /// counts its one file, the same as Rust (`test_inline_diff_no_changes`).
    @Test("inline mode with the same text gives no change")
    func inlineModeWithTheSameTextGivesNoChange() async throws {
        let code = "fn same() {\n    println!(\"same\");\n}\n"

        let result = try await Self.inlineDiff(left: code, right: code, language: "rust")

        #expect(result.correction == nil)
        #expect(result.summary.added == 0)
        #expect(result.summary.modified == 0)
        #expect(result.summary.deleted == 0)
        #expect(result.summary.files == 1)
        #expect(result.changes.isEmpty)
    }

    /// A language with no plugin of its own goes to the fallback plugin,
    /// which cuts the text into chunks of lines. An unknown language gives
    /// `.txt`. The `f90` language gives `.f90`, and no code language claims
    /// that extension (git.md decision 13).
    @Test(
        "inline mode with a language that no plugin claims uses the fallback plugin",
        arguments: [("brainfuck", "inline.txt"), ("f90", "inline.f90")])
    func inlineModeWithALanguageThatNoPluginClaimsUsesTheFallbackPlugin(
        language: String, inlinePath: String
    ) async throws {
        let result = try await Self.inlineDiff(left: "one\ntwo\n", right: "one\nTWO\n", language: language)

        #expect(result.correction == nil)
        #expect(result.summary.modified == 1)
        let modified = try #require(result.changes.first)
        #expect(modified.entityType == FallbackParserPlugin.chunkEntityType)
        #expect(modified.filePath == inlinePath)
    }

    /// Each missing part of the inline mode is a correction that names the
    /// missing argument.
    @Test("inline mode with a missing argument is a correction that names it")
    func inlineModeWithAMissingArgumentIsACorrectionThatNamesIt() async throws {
        let context = Self.contextOutsideAnyRepository()
        let cases: [(arguments: DiffArguments, missing: String)] = [
            (Self.arguments(leftText: "a", language: "rust"), "rightText"),
            (Self.arguments(rightText: "a", language: "rust"), "leftText"),
            (Self.arguments(leftText: "a", rightText: "b"), "language"),
        ]

        for (arguments, missing) in cases {
            let result = try await Self.diff(arguments, in: context)

            try Self.expectCorrection(result, contains: "`\(missing)`")
        }
    }

    /// A content longer than the cap is cut to the cap, and the change says
    /// so.
    @Test("a content longer than the cap is cut and the change says so")
    func aContentLongerThanTheCapIsCutAndTheChangeSaysSo() async throws {
        let body = String(repeating: "    let value = 1;\n", count: Diff.contentCharacterCap)
        let left = "fn big() {\n\(body)}\n"
        let right = "fn big() {\n\(body)    let last = 1;\n}\n"

        let result = try await Self.inlineDiff(left: left, right: right, language: "rust")

        let modified = try #require(result.changes.first)
        #expect(modified.isContentCapped)
        #expect(modified.beforeContent?.count == Diff.contentCharacterCap)
        #expect(modified.afterContent?.count == Diff.contentCharacterCap)
        #expect(modified.afterContent.map { right.hasPrefix($0) } == true)
    }

    // MARK: - File mode

    /// A file at an older ref against the file in the work folder gives the
    /// changed function, under the path of the right side.
    @Test("file mode diffs a file at an older ref against the work folder")
    func fileModeDiffsAFileAtAnOlderRefAgainstTheWorkFolder() async throws {
        let repository = try Self.repositoryWithTwoSwiftVersions()

        let result = try await Self.diff(
            Self.arguments(left: "\(Self.swiftFile)@HEAD~1", right: Self.swiftFile),
            in: GitContext(root: repository.workDirectory))

        #expect(result.correction == nil)
        #expect(result.summary.files == 1)
        #expect(result.summary.modified == 1)
        let modified = try #require(result.changes.first)
        #expect(modified.changeType == "modified")
        #expect(modified.entityName == Self.swiftFunctionName)
        #expect(modified.filePath == Self.swiftFile)
        #expect(modified.oldFilePath == nil)
        #expect(modified.beforeContent?.contains("\"hello\"") == true)
        #expect(modified.afterContent?.contains("\"hello, world\"") == true)
    }

    /// The same file on both sides is no change.
    @Test("file mode with the same content gives no change")
    func fileModeWithTheSameContentGivesNoChange() async throws {
        let repository = try Self.repositoryWithTwoSwiftVersions()

        let result = try await Self.diff(
            Self.arguments(left: "\(Self.swiftFile)@HEAD", right: Self.swiftFile),
            in: GitContext(root: repository.workDirectory))

        #expect(result.correction == nil)
        #expect(result.changes.isEmpty)
        #expect(result.summary.files == 0)
    }

    /// A path outside the root goes through the path guard of the context,
    /// and the refusal of the guard is the correction: on a side with no ref
    /// and on a side with a ref.
    @Test("file mode with a path outside the root is a correction")
    func fileModeWithAPathOutsideTheRootIsACorrection() async throws {
        let repository = try Self.repositoryWithTwoSwiftVersions()
        let context = GitContext(root: repository.workDirectory)
        let outside = TestSupport.makeTemporaryDirectory(named: Self.testDirectoryName)
        let outsideFile = outside.appendingPathComponent(Self.swiftFile, isDirectory: false)
        try Self.firstSwift.write(to: outsideFile, atomically: true, encoding: .utf8)
        let refusal = try #require(throws: PathViolation.self) {
            try context.pathGuard.validatePath(outsideFile.path).get()
        }

        for arguments in [
            Self.arguments(left: Self.swiftFile, right: outsideFile.path),
            Self.arguments(left: "\(outsideFile.path)@HEAD", right: Self.swiftFile),
        ] {
            let result = try await Self.diff(arguments, in: context)

            try Self.expectCorrection(result, contains: refusal.message)
        }
    }

    /// A ref that names no commit is a correction that names the ref.
    @Test("file mode with an unknown ref is a correction")
    func fileModeWithAnUnknownRefIsACorrection() async throws {
        let repository = try Self.repositoryWithTwoSwiftVersions()

        let result = try await Self.diff(
            Self.arguments(left: "\(Self.swiftFile)@no-such-ref", right: Self.swiftFile),
            in: GitContext(root: repository.workDirectory))

        try Self.expectCorrection(result, contains: "no-such-ref")
    }

    /// A file that the work folder does not hold is a correction that names
    /// the path.
    @Test("file mode with a missing work folder file is a correction")
    func fileModeWithAMissingWorkFolderFileIsACorrection() async throws {
        let repository = try Self.repositoryWithTwoSwiftVersions()

        let result = try await Self.diff(
            Self.arguments(left: Self.swiftFile, right: "missing.swift"),
            in: GitContext(root: repository.workDirectory))

        try Self.expectCorrection(result, contains: "missing.swift")
    }

    /// Each missing side of the file mode is a correction that names the
    /// missing argument.
    @Test("file mode with a missing side is a correction that names it")
    func fileModeWithAMissingSideIsACorrectionThatNamesIt() async throws {
        let repository = try Self.repositoryWithTwoSwiftVersions()
        let context = GitContext(root: repository.workDirectory)

        let noRight = try await Self.diff(Self.arguments(left: Self.swiftFile), in: context)
        let noLeft = try await Self.diff(Self.arguments(right: Self.swiftFile), in: context)

        try Self.expectCorrection(noRight, contains: "`right`")
        try Self.expectCorrection(noLeft, contains: "`left`")
    }

    // MARK: - Automatic mode

    /// A clean tree has no file to diff: no change and no correction.
    @Test("automatic mode with a clean tree gives no change")
    func automaticModeWithACleanTreeGivesNoChange() async throws {
        let repository = try Self.repositoryWithTwoSwiftVersions()

        let result = try await Self.diff(Self.arguments(), in: GitContext(root: repository.workDirectory))

        #expect(result.correction == nil)
        #expect(result.changes.isEmpty)
        #expect(result.summary.files == 0)
    }

    /// A staged file and an unstaged file are each diffed against HEAD.
    @Test("automatic mode diffs a staged file and an unstaged file against HEAD")
    func automaticModeDiffsAStagedFileAndAnUnstagedFileAgainstHead() async throws {
        let repository = try TemporaryGitRepository()
        try repository.write(Self.firstSwift, to: Self.swiftFile)
        try repository.write(Self.firstSwift, to: Self.otherSwiftFile)
        try repository.commit(message: "first")
        try repository.write(Self.secondSwift, to: Self.swiftFile)
        try repository.stage(Self.swiftFile)
        try repository.write(Self.secondSwift, to: Self.otherSwiftFile)
        let changedFiles: Set<String> = [Self.swiftFile, Self.otherSwiftFile]

        let result = try await Self.diff(Self.arguments(), in: GitContext(root: repository.workDirectory))

        #expect(result.correction == nil)
        #expect(Set(result.changes.map(\.filePath)) == changedFiles)
        #expect(result.summary.files == changedFiles.count)
        #expect(result.summary.modified == changedFiles.count)
        #expect(result.changes.allSatisfy { $0.entityName == Self.swiftFunctionName })
    }

    /// A file that git does not track is new: each of its entities is
    /// `added`.
    @Test("automatic mode gives the entities of an untracked file as added")
    func automaticModeGivesTheEntitiesOfAnUntrackedFileAsAdded() async throws {
        let repository = try Self.repositoryWithTwoSwiftVersions()
        try repository.write(Self.firstSwift, to: Self.otherSwiftFile)

        let result = try await Self.diff(Self.arguments(), in: GitContext(root: repository.workDirectory))

        #expect(result.summary.added == 1)
        let added = try #require(result.changes.first)
        #expect(added.filePath == Self.otherSwiftFile)
        #expect(added.changeType == "added")
    }

    /// A staged rename with no change of content reads HEAD at the old path
    /// (task `^wvmh7vf`): the entity is the same on each side, thus it moved
    /// to the new file, and no entity is added or deleted.
    @Test("automatic mode gives the entity of a staged rename as moved")
    func automaticModeGivesTheEntityOfAStagedRenameAsMoved() async throws {
        let repository = try TemporaryGitRepository()
        try repository.write(Self.firstSwift, to: Self.swiftFile)
        try repository.commit(message: "first")
        try repository.stageRename(from: Self.swiftFile, to: Self.otherSwiftFile)

        let result = try await Self.diff(Self.arguments(), in: GitContext(root: repository.workDirectory))

        #expect(result.correction == nil)
        #expect(result.summary.added == 0)
        #expect(result.summary.deleted == 0)
        #expect(result.summary.modified == 0)
        #expect(result.summary.moved == 1)
        let moved = try #require(result.changes.first)
        #expect(result.changes.count == 1)
        #expect(moved.changeType == "moved")
        #expect(moved.filePath == Self.otherSwiftFile)
        #expect(moved.oldFilePath == Self.swiftFile)
        #expect(moved.beforeContent == moved.afterContent)
    }

    /// A staged rename, then a change of the function in the work folder:
    /// the old side is the function at the old path, thus the function
    /// moved with its new body, and it is not added.
    @Test("automatic mode gives a changed function of a staged rename as moved")
    func automaticModeGivesAChangedFunctionOfAStagedRenameAsMoved() async throws {
        let repository = try TemporaryGitRepository()
        try repository.write(Self.sumSwift, to: Self.swiftFile)
        try repository.commit(message: "first")
        try repository.stageRename(from: Self.swiftFile, to: Self.otherSwiftFile)
        try repository.write(Self.doubledSumSwift, to: Self.otherSwiftFile)

        let result = try await Self.diff(Self.arguments(), in: GitContext(root: repository.workDirectory))

        #expect(result.summary.added == 0)
        #expect(result.summary.deleted == 0)
        let moved = try #require(result.changes.first)
        #expect(result.changes.count == 1)
        #expect(moved.changeType == "moved")
        #expect(moved.entityName == Self.sumFunctionName)
        #expect(moved.filePath == Self.otherSwiftFile)
        #expect(moved.oldFilePath == Self.swiftFile)
        #expect(moved.beforeContent?.contains("return sum\n") == true)
        #expect(moved.afterContent?.contains("return sum * 2\n") == true)
    }

    /// A rename from a path outside the root: the old path is never read
    /// (git.md § "Decisions", item 8), thus the file is new below the root
    /// and its entity is `added`, with no old path.
    @Test("automatic mode gives a rename from outside the root as added")
    func automaticModeGivesARenameFromOutsideTheRootAsAdded() async throws {
        let repository = try TemporaryGitRepository()
        try repository.write(Self.firstSwift, to: Self.swiftFile)
        try repository.write("kept\n", to: "\(Self.subfolder)/kept.txt")
        try repository.commit(message: "first")
        try repository.stageRename(from: Self.swiftFile, to: "\(Self.subfolder)/\(Self.otherSwiftFile)")
        let root = repository.workDirectory.appendingPathComponent(Self.subfolder, isDirectory: true)

        let result = try await Self.diff(Self.arguments(), in: GitContext(root: root))

        #expect(result.correction == nil)
        #expect(result.summary.added == 1)
        #expect(result.summary.deleted == 0)
        let added = try #require(result.changes.first)
        #expect(result.changes.count == 1)
        #expect(added.changeType == "added")
        #expect(added.filePath == Self.otherSwiftFile)
        #expect(added.oldFilePath == nil)
    }

    /// A rename from below the root to a path outside the root: the old file
    /// is gone from the root, thus its entity is `deleted` at the old path.
    /// The new path is never read (git.md § "Decisions", item 8).
    @Test("automatic mode gives a rename to outside the root as deleted")
    func automaticModeGivesARenameToOutsideTheRootAsDeleted() async throws {
        let repository = try TemporaryGitRepository()
        try repository.write(Self.firstSwift, to: "\(Self.subfolder)/\(Self.swiftFile)")
        try repository.write("kept\n", to: "\(Self.subfolder)/kept.txt")
        try repository.commit(message: "first")
        try repository.stageRename(from: "\(Self.subfolder)/\(Self.swiftFile)", to: Self.otherSwiftFile)
        let root = repository.workDirectory.appendingPathComponent(Self.subfolder, isDirectory: true)

        let result = try await Self.diff(Self.arguments(), in: GitContext(root: root))

        #expect(result.correction == nil)
        #expect(result.summary.added == 0)
        #expect(result.summary.deleted == 1)
        let deleted = try #require(result.changes.first)
        #expect(result.changes.count == 1)
        #expect(deleted.changeType == "deleted")
        #expect(deleted.entityName == Self.swiftFunctionName)
        #expect(deleted.filePath == Self.swiftFile)
        #expect(deleted.oldFilePath == nil)
        #expect(deleted.afterContent == nil)
    }

    /// A root in no repository is a correction.
    @Test("automatic mode with a root in no repository is a correction")
    func automaticModeWithARootInNoRepositoryIsACorrection() async throws {
        let result = try await Self.diff(Self.arguments(), in: Self.contextOutsideAnyRepository())

        try Self.expectCorrection(result, contains: "not in a git repository")
    }

    // MARK: - Helpers

    /// Calls the `tools.git.diff` verb over a context.
    ///
    /// - Parameters:
    ///   - arguments: The arguments of the call.
    ///   - context: The context of the verb.
    /// - Returns: The result of the verb.
    private static func diff(_ arguments: DiffArguments, in context: GitContext) async throws -> GitDiffResult {
        try await Diff(context: context).call(arguments: arguments)
    }

    /// Calls the inline mode of the verb, in a root in no repository: the
    /// inline mode reads no file.
    ///
    /// - Parameters:
    ///   - left: The text of the old side.
    ///   - right: The text of the new side.
    ///   - language: The language of the two texts.
    /// - Returns: The result of the verb.
    private static func inlineDiff(left: String, right: String, language: String) async throws -> GitDiffResult {
        try await diff(
            arguments(leftText: left, rightText: right, language: language), in: contextOutsideAnyRepository())
    }

    /// The arguments of one call, with `nil` for each argument not given.
    ///
    /// - Parameters:
    ///   - left: The left file spec.
    ///   - right: The right file spec.
    ///   - leftText: The inline text of the old side.
    ///   - rightText: The inline text of the new side.
    ///   - language: The language of the inline texts.
    /// - Returns: The arguments.
    private static func arguments(
        left: String? = nil, right: String? = nil, leftText: String? = nil, rightText: String? = nil,
        language: String? = nil
    ) -> DiffArguments {
        DiffArguments(left: left, right: right, leftText: leftText, rightText: rightText, language: language)
    }

    /// A context whose root is in no repository.
    ///
    /// - Returns: The context.
    private static func contextOutsideAnyRepository() -> GitContext {
        GitContext(root: TestSupport.makeTemporaryDirectory(named: testDirectoryName))
    }

    /// A repository with ``firstSwift`` and then ``secondSwift`` committed to
    /// ``swiftFile``.
    ///
    /// - Returns: The repository.
    /// - Throws: When a write, a commit, or the branch fails.
    private static func repositoryWithTwoSwiftVersions() throws -> TemporaryGitRepository {
        try GitTestHistory.makeTwoVersions(of: swiftFile, firstText: firstSwift, secondText: secondSwift)
    }

    /// Expects that `result` is a correction that holds `fragment`, with no
    /// change and an empty summary.
    ///
    /// - Parameters:
    ///   - result: The result of the verb.
    ///   - fragment: Text that the correction must hold.
    /// - Throws: When the result has no correction.
    private static func expectCorrection(_ result: GitDiffResult, contains fragment: String) throws {
        let correction = try #require(result.correction)
        #expect(correction.contains(fragment), "correction was: \(correction)")
        #expect(result.changes.isEmpty)
        #expect(result.summary.files == 0)
    }
}
