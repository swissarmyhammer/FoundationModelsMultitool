// `BuiltinSkills` — the folder of the skills that the library ships as a
// resource. The folder `skills/` is one layer root: each child folder is one
// skill, and each skill folder holds a `SKILL.md` file.

import Foundation

/// The skills that the library ships as a resource.
public enum BuiltinSkills {

    /// The name of the resource folder that holds the skills.
    private static let resourceName = "skills"

    /// The folder of the skills that the library ships.
    ///
    /// Each child folder of this folder is one skill, and holds a `SKILL.md`
    /// file. For example, `sessions/SKILL.md` tells an agent how to use the
    /// `sessions` tool.
    ///
    /// ACPAgent gives this URL to `DotfolderStack` as the defaults layer of
    /// the skills stack. A skill in a layer above the defaults layer replaces
    /// the skill with the same name in this folder.
    public static var directory: URL {
        Bundle.module.url(forResource: resourceName, withExtension: nil)
            ?? (Bundle.module.resourceURL ?? Bundle.module.bundleURL)
            .appendingPathComponent(resourceName, isDirectory: true)
    }
}
