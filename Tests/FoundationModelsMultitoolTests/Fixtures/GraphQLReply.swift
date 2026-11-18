import Foundation
import FoundationModelsExtras
import GraphQL
import Testing

/// The parts of one GraphQL response of an endpoint that a test reads: the
/// `data` object, the code and the message of each error, and the
/// `extensions.rewrites` list.
struct GraphQLReply {

    /// Runs one GraphQL document on an endpoint and reads the response.
    ///
    /// Each GraphQL endpoint test runs its documents through this one helper.
    ///
    /// - Parameters:
    ///   - document: The GraphQL document.
    ///   - variables: The values of the variables of the document.
    ///   - viewer: The client of the call, or `nil` for the agent of the
    ///     session itself.
    ///   - endpoint: The endpoint that runs the document.
    /// - Returns: The response.
    /// - Throws: What the endpoint throws, or an error when the response is
    ///   not a JSON object.
    static func run(
        _ document: String, variables: [String: Map] = [:], viewer: GraphQLViewer? = nil,
        on endpoint: some GraphQLEndpoint
    ) async throws -> GraphQLReply {
        try GraphQLReply(
            json: await endpoint.execute(query: document, variables: variables, operationName: nil, viewer: viewer))
    }

    /// Reads the newest cursor of an endpoint from the root query `cursor`.
    ///
    /// Each GraphQL endpoint test reads a cursor through this one helper.
    ///
    /// - Parameters:
    ///   - endpoint: The endpoint that gives the cursor.
    ///   - viewer: The client of the call, or `nil` for the agent of the
    ///     session itself.
    /// - Returns: The cursor.
    /// - Throws: What the endpoint throws, or an error when the response has
    ///   no cursor.
    static func cursor(of endpoint: some GraphQLEndpoint, viewer: GraphQLViewer? = nil) async throws -> String {
        try #require(try await run("{ cursor }", viewer: viewer, on: endpoint).data?["cursor"] as? String)
    }

    /// The `data` object, or `nil` when the response has none.
    let data: [String: Any]?

    /// The code of each error, in order.
    let codes: [String]

    /// The message of each error, in order.
    let messages: [String]

    /// The `extensions.rewrites` list.
    let rewrites: [[String: Any]]

    /// Reads a response.
    ///
    /// - Parameter json: The JSON text of the response.
    /// - Throws: An error when the text is not a JSON object.
    init(json: String) throws {
        let object = try #require(try JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any])
        data = object["data"] as? [String: Any]
        let errors = object["errors"] as? [[String: Any]] ?? []
        codes = errors.compactMap { error in (error["extensions"] as? [String: Any])?["code"] as? String }
        messages = errors.compactMap { error in error["message"] as? String }
        rewrites = (object["extensions"] as? [String: Any])?["rewrites"] as? [[String: Any]] ?? []
    }

    /// The list of objects at `key` of `data`.
    ///
    /// - Parameter key: The response key.
    /// - Returns: The objects.
    /// - Throws: An error when `data` has no list of objects at `key`.
    func list(_ key: String) throws -> [[String: Any]] {
        try #require(data?[key] as? [[String: Any]])
    }

    /// The object at `key` of `data`.
    ///
    /// - Parameter key: The response key.
    /// - Returns: The object.
    /// - Throws: An error when `data` has no object at `key`.
    func object(_ key: String) throws -> [String: Any] {
        try #require(data?[key] as? [String: Any])
    }

    /// Tells if `data` holds `null` at `key`.
    ///
    /// - Parameter key: The response key.
    /// - Returns: `true` for a `null` value.
    func isNull(_ key: String) -> Bool {
        data?[key] is NSNull
    }

    /// Tells if the response reports the rewrite of `from` to `to` in
    /// `extensions.rewrites`. The rewrite can be of a name or of a value.
    ///
    /// - Parameters:
    ///   - from: The name or the value that the call wrote.
    ///   - to: The name of the schema that the call reached, or the canonical
    ///     form of the value.
    ///   - path: The path of the rewrite in the document. When it is `nil`,
    ///     the path of the rewrite is not examined.
    /// - Returns: `true` when the list holds the rewrite.
    func rewrote(_ from: String, to: String, at path: [String]? = nil) -> Bool {
        rewrites.contains { rewrite in
            rewrite["from"] as? String == from && rewrite["to"] as? String == to
                && (path == nil || rewrite["path"] as? [String] == path)
        }
    }
}
