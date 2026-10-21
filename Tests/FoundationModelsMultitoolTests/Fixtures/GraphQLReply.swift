import Foundation
import Testing

/// The parts of one GraphQL response of an endpoint that a test reads: the
/// `data` object, the code and the message of each error, and the
/// `extensions.rewrites` list.
struct GraphQLReply {

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

    /// Tells if the response reports the rewrite of the name `from` to the
    /// name `to` in `extensions.rewrites`.
    ///
    /// - Parameters:
    ///   - from: The name that the call wrote.
    ///   - to: The name of the schema that the call reached.
    /// - Returns: `true` when the list holds the rewrite.
    func rewrote(_ from: String, to: String) -> Bool {
        rewrites.contains { rewrite in rewrite["from"] as? String == from && rewrite["to"] as? String == to }
    }
}
