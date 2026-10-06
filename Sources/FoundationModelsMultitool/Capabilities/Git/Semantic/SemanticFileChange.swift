// `SemanticFileChange` — one changed file, the input of the semantic
// differ.
//
// A port of the parts of `git_types.rs` in
// `../swissarmyhammer/crates/swissarmyhammer-sem/src/` that
// `parser/differ.rs` uses: the struct `FileChange` and the enum
// `FileStatus` of its `status` field. The Swift name has the prefix
// `Semantic`, because the files capability has a public `FileChange`
// (`Capabilities/Files/FileChangeSet.swift`). `DiffScope` and `CommitInfo`
// of the same Rust file serve the git layer of the Rust tool, and this port
// does not have them. The raw value of each `FileStatus` case is the
// lowercase name that the Rust `Display` and
// `serde(rename_all = "lowercase")` write.

/// What happened to one file: `FileStatus` in `git_types.rs`.
enum FileStatus: String, Sendable {

    /// The file is new.
    case added

    /// The file is on both sides with a different content.
    case modified

    /// The file is gone.
    case deleted

    /// The file has a new path.
    case renamed
}

/// One changed file: `FileChange` in `git_types.rs`.
struct SemanticFileChange: Equatable, Sendable {

    /// The path of the file on the new side, relative to the repository
    /// root.
    let filePath: String

    /// What happened to the file. The differ does not read it: the two
    /// contents tell the differ what to compare.
    // The `tools.git.diff` verb reads it when it lists the files of a diff.
    // periphery:ignore
    let status: FileStatus

    /// The path of the file on the old side, for a renamed file. The differ
    /// reads the old entities at this path.
    let oldFilePath: String?

    /// The text of the file on the old side, or `nil` for an added file.
    let beforeContent: String?

    /// The text of the file on the new side, or `nil` for a deleted file.
    let afterContent: String?
}
