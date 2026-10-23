// `List` — the `tools.files.list` verb.
//
// SWE-bench run bench24-1023, django__django-13710: a model called
// `tools.files.list({ path: "django/utils" })` and got "not a function". No
// verb listed one directory: `glob` needs a pattern and answers files only,
// across the whole tree. This verb answers the entries of ONE directory, in
// the pattern of `Capabilities/Files/MakeDirectory.swift`: a plain
// `FoundationModels.Tool` that holds the `FileContext` it works against.
//
// A directory the verb cannot list stays IN BAND, as a `correction` beside an
// empty entry list. It is never thrown: a path outside the root, a missing
// directory, and a file at the path are each a mistake the model corrects
// inside the same answer.

import Foundation
import FoundationModels

/// The arguments of `tools.files.list`: the directory to list.
@Generable
struct ListArguments {

    /// The directory to list, or `nil` to list the session root.
    @Guide(
        description:
            "The directory to list, absolute or relative to the session root. Omit it to list "
            + "the session root.")
    var path: String?
}

/// The result of `tools.files.list`: the entries of the directory, or the
/// correction that says why there are none.
///
/// `correction` and the entries are exclusive. A listing carries no
/// correction, and a correction carries no entry.
@Generable(
    description:
        "the entries of the directory by name, a folder with a trailing slash, or the correction that says why there are none."
)
struct ListResult {

    /// The names of the entries, sorted, each folder with a trailing `/`.
    var entries: [String]

    /// Why the verb answered no entry, or `nil` when the entries stand.
    var correction: String?
}

extension List {

    /// The suffix that marks a folder among the entries.
    private static let folderSuffix = "/"

    /// A result carrying only a correction.
    ///
    /// - Parameter message: the correction the model reads and acts on.
    /// - Returns: the corrective ``ListResult``.
    private static func corrective(_ message: String) -> ListResult {
        ListResult(entries: [], correction: message)
    }

    /// The corrective message for a path that names no directory.
    ///
    /// - Parameter path: the requested path.
    /// - Returns: the corrective message.
    private static func notADirectoryMessage(_ path: String) -> String {
        "There is no directory to list at \(path). Give the path of a directory, or use "
            + "tools.files.read to read a file."
    }

    /// Lists the directory and answers its entries, or the correction that
    /// says why there are none.
    ///
    /// The path is bounded through the context's ``PathGuard`` for a
    /// directory, as `tools.files.glob` bounds its search root, and an absent
    /// path lists the session root. Each entry the host exclude patterns name
    /// is left out, as the search walks leave it out.
    ///
    /// - Parameter arguments: The directory to list.
    /// - Returns: The entries, or the correction.
    func call(arguments: ListArguments) async throws -> ListResult {
        let context = self.context
        return FileWalker.resolveRequestedPath(arguments.path, in: context) {
            context.pathGuard.validate($0, for: .directory)
        }
        .flatMap { FileWalker.boundDirectory($0, in: context) }
        .resolve(corrective: Self.corrective) { directory in
            guard FileWalker.isDirectory(directory.path),
                let names = try? FileManager.default.contentsOfDirectory(atPath: directory.path)
            else {
                return Self.corrective(Self.notADirectoryMessage(arguments.path ?? directory.path))
            }
            let root = FileWalker.canonicalDirectory(context.root).path
            let entries = names.sorted().compactMap { name -> String? in
                let url = directory.appendingPathComponent(name)
                let isFolder = FileWalker.isDirectory(url.path)
                if let relative = FileWalker.relativePath(ofAbsolute: url.path, under: root) {
                    let excluded =
                        isFolder
                        ? context.excludePatterns.excludes(folderPath: relative)
                        : context.excludePatterns.excludes(relativePath: relative)
                    if excluded { return nil }
                }
                return isFolder ? name + Self.folderSuffix : name
            }
            return ListResult(entries: entries, correction: nil)
        }
    }
}

/// Lists the entries of one directory under the session root.
///
/// ```swift
/// // In a snippet the model writes:
/// //   const listed = await tools.files.list({ path: "django/utils" });
/// ```
///
/// The contract: the entries are the names directly inside the directory,
/// sorted, each folder with a trailing `/`, hidden entries included. The path
/// is bounded through the session's ``PathGuard``, and an entry the host
/// exclude patterns name is left out. A path outside the root, a missing
/// directory, and a file at the path each come back as a `correction` rather
/// than as an error.
///
/// The context it works against is the context the files capability owns,
/// thus each verb of one capability answers for the same session.
struct List: Tool {

    /// The verb this tool renders as, which the files noun stands in front
    /// of: `tools.files.list`.
    let name = "list"

    /// The usage instructions, as the model reads them.
    let description = """
        list answers the entries of one directory: the names directly inside it, sorted, each \
        folder with a trailing slash. Omit path to list the session root. Use glob to find files \
        by name across the whole tree. A path outside the session root, a missing directory, and \
        a file at the path each come back as a correction rather than as an error — read it, \
        correct the call, and ask again.
        """

    /// The session context this verb works against, which the files capability owns.
    let context: FileContext
}
