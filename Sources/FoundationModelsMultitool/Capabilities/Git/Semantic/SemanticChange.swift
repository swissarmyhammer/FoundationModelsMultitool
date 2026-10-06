// `SemanticChange` — one change to one entity, as the semantic diff reports
// it.
//
// A port of `model/change.rs` in
// `../swissarmyhammer/crates/swissarmyhammer-sem/src/`: the enum
// `ChangeType` and the struct `SemanticChange`. The raw value of each
// `ChangeType` case is the lowercase name that the Rust `Display` and
// `serde(rename_all = "lowercase")` write.
//
// The Rust struct also has a `timestamp` field. Each Rust path sets it to
// `None`, and no Rust code reads it, thus this port does not have it.

/// What happened to one entity: `ChangeType` in `model/change.rs`.
enum ChangeType: String, Sendable {

    /// The entity is new.
    case added

    /// The entity has the same id and a different content.
    case modified

    /// The entity is gone.
    case deleted

    /// The entity went to another file.
    case moved

    /// The entity has a new id in the same file.
    case renamed
}

/// One change to one entity: `SemanticChange` in `model/change.rs`.
struct SemanticChange: Equatable, Sendable {

    /// The id of the change, for example `change::<entity id>` or
    /// `change::added::<entity id>`.
    let id: String

    /// The id of the entity on the new side, or on the old side for a
    /// deleted entity.
    let entityID: String

    /// What happened to the entity.
    let changeType: ChangeType

    /// The kind of the entity, for example `function`.
    let entityType: String

    /// The name of the entity.
    let entityName: String

    /// The path of the file that holds the entity.
    let filePath: String

    /// The path of the file that held the entity before a move, or `nil`.
    let oldFilePath: String?

    /// The source text of the entity before the change, or `nil` for an
    /// added entity.
    let beforeContent: String?

    /// The source text of the entity after the change, or `nil` for a
    /// deleted entity.
    let afterContent: String?

    /// The sha of the commit of the change, when the caller gave one.
    let commitSHA: String?

    /// The author of the commit of the change, when the caller gave one.
    let author: String?

    /// Whether the structure of a modified entity changed (`true`) or only
    /// its comments or format (`false`): `structural_change` in Rust. It is
    /// `nil` when one side has no structural hash, and for each change that
    /// is not `modified`.
    let isStructuralChange: Bool?
}
