// `GitScenarioHistory` — the repository that the scenarios of the git
// capability read.
//
// Task `^xd2dbd1`: the unit test of the goal snippet of git.md and the live
// model scenarios of `IntegrationTests/` read the same repository. One builder
// keeps the two kinds of test on the same facts, thus the helper stands in the
// `MultitoolTestSupport` product, beside `TemporaryGitRepository`.

import Foundation

/// The repository that the git scenarios read: three commits, and one
/// function that the work folder renames.
///
/// A namespace, not a value: ``make()`` makes a new temporary repository, thus
/// each test holds its own repository.
enum GitScenarioHistory {

    /// The Swift file whose greeting the third commit changes, relative to the
    /// work folder.
    static let greeterPath = "Sources/Greeter.swift"

    /// The Swift file whose function the work folder renames, relative to the
    /// work folder.
    static let geometryPath = "Sources/Geometry.swift"

    /// The greeting of the first commit.
    static let firstGreeting = "Hello"

    /// The greeting of the third commit.
    static let changedGreeting = "Good morning"

    /// The name of the function of the second commit.
    static let functionName = "area"

    /// The name of the function after the rename in the work folder.
    static let renamedFunctionName = "surfaceArea"

    /// The subject of the first commit.
    static let firstSubject = "Add the greeter"

    /// The subject of the second commit.
    static let secondSubject = "Add the geometry"

    /// The subject of the third commit, which HEAD names.
    static let thirdSubject = "Change the greeting"

    /// The text of ``greeterPath`` with one greeting.
    ///
    /// - Parameter greeting: The greeting, on the second line.
    /// - Returns: The Swift text.
    static func greeterText(greeting: String) -> String {
        "struct Greeter {\n    let greeting = \"\(greeting)\"\n}\n"
    }

    /// The text of ``geometryPath`` with one function. The body has several
    /// lines, and the rename keeps the body.
    ///
    /// - Parameter name: The name of the function.
    /// - Returns: The Swift text.
    static func geometryText(functionName name: String) -> String {
        "func \(name)(width: Double, height: Double) -> Double {\n    let product = width * height\n"
            + "    return product\n}\n"
    }

    /// Makes the repository. The branch of HEAD holds three commits:
    ///
    /// 1. ``firstSubject``: ``greeterPath`` with ``firstGreeting``.
    /// 2. ``secondSubject``: ``geometryPath`` with the function
    ///    ``functionName``.
    /// 3. ``thirdSubject``: ``greeterPath`` with ``changedGreeting``.
    ///
    /// Then the work folder renames the function to ``renamedFunctionName``,
    /// and stages nothing. Thus ``geometryPath`` is the one changed file.
    ///
    /// - Returns: The repository, and the sha of each commit, oldest first.
    /// - Throws: When a write or a commit fails.
    static func make() throws -> (repository: TemporaryGitRepository, shas: [String]) {
        let repository = try TemporaryGitRepository()
        try repository.write(greeterText(greeting: firstGreeting), to: greeterPath)
        let first = try repository.commit(message: firstSubject)
        try repository.write(geometryText(functionName: functionName), to: geometryPath)
        let second = try repository.commit(message: secondSubject)
        try repository.write(greeterText(greeting: changedGreeting), to: greeterPath)
        let third = try repository.commit(message: thirdSubject)
        try repository.write(geometryText(functionName: renamedFunctionName), to: geometryPath)
        return (repository, [first, second, third])
    }
}
