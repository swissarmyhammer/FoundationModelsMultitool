// `KeyRedaction` — removes API key values from a text.
//
// A provider can echo the key of a request in its error text. Before such a
// text goes into `notes` or into a `correction`, the web capability replaces
// each key value in it with `<redacted>`. Thus the sandbox and the model never
// see a key (web.md § "Keys").

/// Removes API key values from a text.
///
/// A namespace, and not a value: each member is `static`.
enum KeyRedaction {
    /// The text that takes the place of a key value.
    ///
    /// `WebAPIKey` shows the same text in each of its string forms.
    static let placeholder = "<redacted>"

    /// Replaces each occurrence of each key value in `text` with
    /// ``placeholder``.
    ///
    /// The replacement starts with the longest key. Thus when one key contains
    /// a shorter key, the longer key goes whole, and no part of it stays in
    /// the text. An empty key changes nothing.
    ///
    /// - Parameters:
    ///   - text: The text to redact, for example the error text of a provider.
    ///   - keys: The key values to remove.
    /// - Returns: `text` with each key value replaced by ``placeholder``.
    static func redactingKeys(_ text: String, keys: [String]) -> String {
        keys
            .filter { !$0.isEmpty }
            .sorted { $0.count > $1.count }
            .reduce(text) { redacted, key in redacted.replacing(key, with: placeholder) }
    }
}
