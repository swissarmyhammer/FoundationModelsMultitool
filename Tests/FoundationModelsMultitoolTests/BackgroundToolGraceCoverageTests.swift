import Foundation
import FoundationModels
import FoundationModelsExtras
import Testing
import ULID

@testable import FoundationModelsMultitool

/// Every `BackgroundTool` of this package has a settle period.
///
/// The type of `BackgroundTool.inlineSettleGrace` is a non-optional
/// `TimeInterval`, so a conformer cannot state "no grace". But a conformer can
/// still state `0`, which sends each call to the background at once — the
/// defect of `tools.shell.execute` that the user reported four times. This
/// suite finds each conformer in the source of this package, and fails when
/// one has no row in ``coveredConformers`` or when a row reads a grace that
/// is not the hosting default.
@Suite("each background tool of this package waits for the settle period")
struct BackgroundToolGraceCoverageTests {

    /// The directory of the source of this package.
    private static var sourcesDirectory: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources")
    }

    /// The pattern of a declaration that makes a type a `BackgroundTool`:
    /// `extension Name: BackgroundTool`, or a type declaration whose list of
    /// conformances holds `BackgroundTool`.
    private static var conformancePattern: Regex<(Substring, Substring)> {
        #/(?:extension|struct|final class|class|actor|enum)\s+(\w+)\s*:[^{]*\bBackgroundTool\b/#
    }

    /// The name of each type in the source that conforms to `BackgroundTool`.
    ///
    /// - Returns: The type names.
    /// - Throws: When a source file does not read.
    private static func conformersInSource() throws -> Set<String> {
        let enumerator = try #require(FileManager.default.enumerator(at: sourcesDirectory, includingPropertiesForKeys: nil))
        var names: Set<String> = []
        for case let file as URL in enumerator where file.pathExtension == "swift" {
            let text = try String(contentsOf: file, encoding: .utf8)
            for match in text.matches(of: conformancePattern) {
                names.insert(String(match.output.1))
            }
        }
        return names
    }

    /// One instance of each conformer, by type name.
    ///
    /// A new conformer needs a row here, and the test then reads its grace.
    ///
    /// - Returns: The instances.
    /// - Throws: When a tool does not build.
    private static func coveredConformers() throws -> [String: any BackgroundTool] {
        let state = try ShellState(
            preferredDirectory: FileManager.default.temporaryDirectory
                .appendingPathComponent("multitool-grace-\(ULID.generate())"))
        let registry = try MultiTool.Builder().addTool(CitiesTool()).buildRegistry()
        return [
            "MultiTool": MultiTool(registry: registry),
            "SearchToolsTool": try SearchToolsTool(registry: registry, selection: nil),
            "Execute": Execute(runner: ShellRunner(state: state, registry: ProcessRegistry())),
        ]
    }

    @Test("each BackgroundTool in the source has a row, and each row has the hosting default as its grace")
    func everyBackgroundToolHasTheDefaultGrace() throws {
        let found = try Self.conformersInSource()
        let covered = try Self.coveredConformers()

        #expect(!found.isEmpty, "the scan found no conformer: \(Self.sourcesDirectory.path)")
        for name in found.sorted() {
            guard let tool = covered[name] else {
                Issue.record("\(name) conforms to BackgroundTool and has no row in coveredConformers")
                continue
            }
            #expect(tool.inlineSettleGrace > 0, "\(name) has no settle period")
            #expect(tool.inlineSettleGrace == ToolMount.defaultInlineSettleGrace, "\(name)")
        }
        #expect(Set(covered.keys) == found, "a row names a type that no longer conforms")
    }
}
