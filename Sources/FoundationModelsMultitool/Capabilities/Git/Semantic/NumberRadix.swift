// `NumberRadix` — the radixes of the number texts that the data plugins of
// the semantic diff read and write.
//
// The TOML scanner, the YAML scalar rules, and the text rules of Rust and of
// serde_json each read or write a number in one of these radixes. This file
// gives each radix one name, so that no plugin writes the radix as a number.

/// The radixes of the number texts of the data plugins.
enum NumberRadix {

    /// The radix of a binary integer (`0b`).
    static let binary = 2

    /// The radix of an octal integer (`0o`).
    static let octal = 8

    /// The radix of a decimal integer.
    static let decimal = 10

    /// The radix of a hexadecimal integer (`0x`) and of a hexadecimal escape.
    static let hexadecimal = 16
}
