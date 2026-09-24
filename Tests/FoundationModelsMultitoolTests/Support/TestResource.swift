import Foundation
import Testing

/// Reads the golden files and the fixture files of this test target.
///
/// A suite reads each golden file and each fixture file through this one
/// loader, thus the lookup, the failure message, and the decode step have one
/// home.
///
/// `Package.swift` copies the folders `FilesGoldens/`, `MCPFixtures/`, and
/// `WebGoldens/` into the test bundle. The `bundled` members read those files
/// through `Bundle.module`. The rendered surface goldens in `Goldens/` are read
/// from the source tree through ``RepositoryFile``, as `Package.swift` states.
enum TestResource {
    /// The extension of a JSON file.
    static let jsonExtension = "json"

    /// The folder of the rendered surface goldens, from the repository root.
    static let surfaceGoldensDirectory = "Tests/FoundationModelsMultitoolTests/Goldens"

    /// The URL of one file in a resource folder of the test bundle.
    ///
    /// - Parameters:
    ///   - name: The name of the file, with no extension.
    ///   - fileExtension: The extension of the file.
    ///   - folder: The resource folder that holds the file.
    /// - Returns: The URL of the file in the test bundle.
    /// - Throws: When the test bundle does not hold the file.
    static func bundledURL(named name: String, withExtension fileExtension: String, in folder: String) throws -> URL {
        try #require(
            Bundle.module.url(forResource: name, withExtension: fileExtension, subdirectory: folder),
            "\(folder)/\(name).\(fileExtension) must be bundled with the test target"
        )
    }

    /// The whole text of one file in a resource folder of the test bundle.
    ///
    /// - Parameters:
    ///   - name: The name of the file, with no extension.
    ///   - fileExtension: The extension of the file.
    ///   - folder: The resource folder that holds the file.
    /// - Returns: The UTF-8 text of the file, with no change.
    /// - Throws: When the test bundle does not hold the file, or when the file
    ///   does not read as UTF-8.
    static func bundledText(named name: String, withExtension fileExtension: String, in folder: String) throws -> String {
        try String(contentsOf: bundledURL(named: name, withExtension: fileExtension, in: folder), encoding: .utf8)
    }

    /// One JSON file in a resource folder of the test bundle, decoded.
    ///
    /// - Parameters:
    ///   - type: The type to decode the file as.
    ///   - name: The name of the file, with no `.json` extension.
    ///   - folder: The resource folder that holds the file.
    /// - Returns: The decoded value.
    /// - Throws: When the test bundle does not hold the file, or when its
    ///   bytes do not decode as `type`.
    static func bundledJSON<Value: Decodable>(_ type: Value.Type, named name: String, in folder: String) throws -> Value {
        let data = try Data(contentsOf: bundledURL(named: name, withExtension: jsonExtension, in: folder))
        return try JSONDecoder().decode(type, from: data)
    }

    /// One rendered surface golden, with its trailing newlines trimmed as the
    /// rendered source is trimmed.
    ///
    /// - Parameter name: The file name under `Goldens/`.
    /// - Returns: The golden text.
    /// - Throws: When the file does not read.
    static func surfaceGolden(named name: String) throws -> String {
        try RepositoryFile.read(relativePath: "\(surfaceGoldensDirectory)/\(name)")
            .trimmingCharacters(in: .newlines)
    }
}
