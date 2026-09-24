/// Reads the `dump` output of a value, for the redaction tests of the web
/// configuration types.
///
/// `WebAPIKeyTests` and `WebConfigurationTests` each examine that no `dump`
/// output shows a key value. This namespace is the one place that gets the
/// output as a string.
enum WebRedactionProbe {
    /// Writes the `dump` output of `value` into a string.
    ///
    /// - Parameter value: The value to dump.
    /// - Returns: The text that `dump` writes for `value`.
    static func dumped(_ value: some Any) -> String {
        var output = ""
        // The call writes into `output`, not to standard out.
        // swiftlint:disable:next no_direct_standard_out_logs
        dump(value, to: &output)
        return output
    }
}
