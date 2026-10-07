// `RustFloatText` — the three texts of a finite `f64` that the data plugins of
// the semantic diff hash.
//
// The YAML and TOML plugins of `../swissarmyhammer/crates/swissarmyhammer-sem/`
// hash the text of each value. A float becomes text in one of three forms:
//
// - the `ryu` crate (`ryu::Buffer::format_finite`), which serde_yaml_ng
//   writes: `1.0`, `0.1`, `1e16`, `1.5e300`, `1e-7`;
// - the `zmij` crate, which serde_json 1.0.150 writes: the same layout with a
//   `+` before an exponent of zero or more (`1e+16`, `1e-7`);
// - the Rust `Display` of `f64` (`format!("{}", value)`), which
//   `toml_value_to_string` writes: `1`, `0.1`, `10000000000000000`,
//   `0.0000001`, with no exponent ever.
//
// Each form starts from the shortest decimal digits that read back as the
// same `f64`. Swift's `description` of a `Double` writes the same shortest
// digits, thus this file takes the digits from it and writes them in the
// layout of each Rust form.

/// The Rust texts of a finite `Double`.
enum RustFloatText {

    /// The largest count of integer digits that `ryu` writes in plain
    /// layout (`kk <= 16` in `ryu::pretty`); a larger value has an exponent.
    private static let ryuLargestPlainPointPosition = 16

    /// The smallest point position that `ryu` writes as `0.000…digits`
    /// (`-5 < kk` in `ryu::pretty`); a smaller one has an exponent.
    private static let ryuSmallestPlainPointPosition = -4

    /// The text of `value` that `ryu::Buffer::format_finite` writes.
    ///
    /// - Parameter value: A finite value.
    /// - Returns: The text, for example `1.0`, `12.34`, `0.001234`, `1e30`,
    ///   or `1.234e33`.
    static func ryu(_ value: Double) -> String {
        scientificOrPlain(value, positiveExponentSign: "")
    }

    /// The text of `value` that serde_json writes (its `zmij` float
    /// formatter): the layout of ``ryu(_:)``, with a `+` before an exponent
    /// of zero or more (`1e+16`, `1e-7`).
    ///
    /// - Parameter value: A finite value.
    /// - Returns: The text.
    static func serdeJSON(_ value: Double) -> String {
        scientificOrPlain(value, positiveExponentSign: "+")
    }

    /// The layout of `ryu::pretty` and of `zmij`: plain for a point position
    /// from -4 to 16, else one digit, the other digits after a point, and
    /// the exponent.
    private static func scientificOrPlain(_ value: Double, positiveExponentSign: String) -> String {
        let decimal = ShortestDecimal(value)
        let digits = decimal.digits
        let pointPosition = decimal.pointPosition
        let body: String
        if pointPosition >= digits.count && pointPosition <= ryuLargestPlainPointPosition {
            body = digits + String(repeating: "0", count: pointPosition - digits.count) + ".0"
        } else if pointPosition > 0 && pointPosition <= ryuLargestPlainPointPosition {
            body = String(digits.prefix(pointPosition)) + "." + String(digits.dropFirst(pointPosition))
        } else if pointPosition <= 0 && pointPosition >= ryuSmallestPlainPointPosition {
            body = "0." + String(repeating: "0", count: -pointPosition) + digits
        } else {
            let exponent = pointPosition - 1
            let mantissa = digits.count == 1 ? digits : String(digits.prefix(1)) + "." + String(digits.dropFirst())
            body = mantissa + "e" + (exponent >= 0 ? positiveExponentSign : "") + String(exponent)
        }
        return (decimal.isNegative ? "-" : "") + body
    }

    /// The text of `value` that the Rust `Display` of `f64` writes.
    ///
    /// - Parameter value: A finite value.
    /// - Returns: The text, for example `1`, `0.1`, `1000000000000000000000`,
    ///   or `-0`.
    static func display(_ value: Double) -> String {
        let decimal = ShortestDecimal(value)
        let digits = decimal.digits
        let pointPosition = decimal.pointPosition
        let body: String
        if pointPosition <= 0 {
            body = "0." + String(repeating: "0", count: -pointPosition) + digits
        } else if pointPosition < digits.count {
            body = String(digits.prefix(pointPosition)) + "." + String(digits.dropFirst(pointPosition))
        } else {
            body = digits + String(repeating: "0", count: pointPosition - digits.count)
        }
        return (decimal.isNegative ? "-" : "") + body
    }
}

/// The shortest decimal form of a finite `Double`: `0.<digits> × 10^pointPosition`.
private struct ShortestDecimal {

    /// Whether the sign bit is set (also for `-0.0`).
    let isNegative: Bool

    /// The significant digits, with no leading and no trailing zero; `0` for
    /// a zero value.
    let digits: String

    /// The count of digits before the decimal point when the point is placed
    /// in `digits` (it can be zero, negative, or larger than the count of
    /// digits). It is 1 for a zero value.
    let pointPosition: Int

    /// The shortest decimal form of `value`, read from Swift's `description`,
    /// which writes the shortest digits that read back as `value` (as
    /// `1.0`, `0.0001`, `1e-05`, or `1.2345678901234568e+17`).
    init(_ value: Double) {
        isNegative = value.sign == .minus
        let text = value.magnitude.description
        let parts = text.split(separator: "e", maxSplits: 1)
        let mantissa = parts[0]
        let exponent = parts.count > 1 ? Int(parts[1]) ?? 0 : 0
        let integerPart = mantissa.prefix { $0 != "." }
        let allDigits = mantissa.filter(\.isNumber)
        let leadingZeros = allDigits.prefix { $0 == "0" }.count
        let significant = allDigits.dropFirst(leadingZeros).reversed().drop { $0 == "0" }.reversed()
        guard !significant.isEmpty else {
            digits = "0"
            pointPosition = 1
            return
        }
        digits = String(significant)
        pointPosition = integerPart.count - leadingZeros + exponent
    }
}
