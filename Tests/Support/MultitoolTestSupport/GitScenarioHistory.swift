// `GitScenarioHistory` — the repository that the scenarios of the git
// capability read.
//
// Task `^xd2dbd1`: the unit test of the goal snippet of git.md and the live
// model scenario of `IntegrationTests/` read the same repository. One builder
// keeps the two kinds of test on the same facts, thus the helper stands in the
// `MultitoolTestSupport` product, beside `TemporaryGitRepository`.

import Foundation

/// The repository that the git scenarios read: one commit, and one function
/// that the work folder renames.
///
/// A namespace, not a value: ``make()`` makes a new temporary repository, thus
/// each test holds its own repository.
enum GitScenarioHistory {

    /// The Swift file whose function the work folder renames, relative to the
    /// work folder.
    static let geometryPath = "Sources/Geometry.swift"

    /// The name of the function of the commit.
    static let functionName = "area"

    /// The name of the function after the rename in the work folder.
    static let renamedFunctionName = "surfaceArea"

    /// The subject of the commit.
    private static let subject = "Add the geometry"

    /// The text of ``geometryPath`` with one function. The body has several
    /// lines, and the rename keeps the body.
    ///
    /// - Parameter name: The name of the function.
    /// - Returns: The Swift text.
    private static func geometryText(functionName name: String) -> String {
        "func \(name)(width: Double, height: Double) -> Double {\n    let product = width * height\n"
            + "    return product\n}\n"
    }

    /// Makes the repository. The branch of HEAD holds one commit:
    /// ``geometryPath`` with the function ``functionName``.
    ///
    /// Then the work folder renames the function to ``renamedFunctionName``,
    /// and stages nothing. Thus ``geometryPath`` is the one changed file.
    ///
    /// - Returns: The repository.
    /// - Throws: When a write or the commit fails.
    static func make() throws -> TemporaryGitRepository {
        let repository = try TemporaryGitRepository()
        try repository.write(geometryText(functionName: functionName), to: geometryPath)
        try repository.commit(message: subject)
        try repository.write(geometryText(functionName: renamedFunctionName), to: geometryPath)
        return repository
    }
}
