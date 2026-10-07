// `YAMLScalarRules` — how serde_yaml_ng reads the text of a YAML scalar.
//
// A port of the scalar functions of `de.rs` in serde_yaml_ng 0.10.0:
// `parse_null`, `parse_bool`, `parse_unsigned_int`, `parse_negative_int`,
// `parse_f64`, `digits_but_not_number`, `visit_int`, and
// `visit_untagged_scalar`. The YAML loader reads a plain scalar with these
// rules, and the YAML emitter selects the quote style of a text with them.
//
// The rules are the YAML 1.2 core schema of serde_yaml_ng, not the YAML 1.1
// rules of the `Yams` Swift API: `yes` and `no` are texts, `0o17` is an
// integer, and `007` is a text. Each match is case-sensitive in the same way
// as Rust: `true`, `True`, and `TRUE` are booleans, and `tRUE` is a text.

/// The value that the text of an untagged plain scalar reads as:
/// `visit_untagged_scalar` in `de.rs`.
enum YAMLScalarReading: Equatable {

    /// An empty text, `null`, `Null`, `NULL`, or `~`.
    case null

    /// `true`, `True`, `TRUE`, `false`, `False`, or `FALSE`.
    case bool(Bool)

    /// An integer that fits a `u64`.
    case unsigned(UInt64)

    /// A negative integer that fits an `i64`.
    case negative(Int64)

    /// An integer that fits a `u128` or an `i128` and no 64-bit type. A
    /// `Value` cannot hold it: serde_yaml_ng refuses the document.
    case wideInteger

    /// A finite float.
    case float(Double)

    /// A text.
    case string

    /// The reading of `text`: `visit_untagged_scalar` in `de.rs`.
    ///
    /// - Parameter text: The text of the scalar.
    init(_ text: String) {
        if text.isEmpty || YAMLScalarRules.isNull(text) {
            self = .null
        } else if let value = YAMLScalarRules.bool(text) {
            self = .bool(value)
        } else if let integer = YAMLScalarRules.integer(text) {
            self = integer
        } else if !YAMLScalarRules.isDigitsButNotNumber(text), let value = YAMLScalarRules.float(text) {
            self = .float(value)
        } else {
            self = .string
        }
    }
}

/// The scalar functions of `de.rs` in serde_yaml_ng.
enum YAMLScalarRules {

    /// The texts of null: `parse_null` in `de.rs`.
    private static let nullTexts: Set = ["null", "Null", "NULL", "~"]

    /// The texts of each boolean: `parse_bool` in `de.rs`.
    private static let boolTexts: [String: Bool] = [
        "true": true, "True": true, "TRUE": true, "false": false, "False": false, "FALSE": false,
    ]

    /// The texts of positive infinity after the sign (`parse_f64`).
    private static let positiveInfinityTexts: Set = [".inf", ".Inf", ".INF"]

    /// The texts of negative infinity (`parse_f64`).
    private static let negativeInfinityTexts: Set = ["-.inf", "-.Inf", "-.INF"]

    /// The texts of NaN (`parse_f64`); a sign is not accepted.
    private static let notANumberTexts: Set = [".nan", ".NaN", ".NAN"]

    /// The prefix of each radix that `parse_unsigned_int` tries, in order.
    private static let radixPrefixes: [(prefix: String, radix: Int)] = [
        ("0x", NumberRadix.hexadecimal), ("0o", NumberRadix.octal), ("0b", NumberRadix.binary),
    ]

    /// The value of the digit `a` (and `A`): the first letter digit.
    private static let letterDigitBase = NumberRadix.decimal

    /// Whether `text` is null: `parse_null` in `de.rs`.
    static func isNull(_ text: String) -> Bool {
        nullTexts.contains(text)
    }

    /// The boolean of `text`, or `nil`: `parse_bool` in `de.rs`.
    static func bool(_ text: String) -> Bool? {
        boolTexts[text]
    }

    /// Whether `text` is a leading zero and more decimal digits (with one
    /// optional sign), which YAML 1.2 reads as a text:
    /// `digits_but_not_number` in `de.rs`.
    static func isDigitsButNotNumber(_ text: String) -> Bool {
        let bytes = text.utf8
        let unsigned = bytes.first.map { $0 == UInt8(ascii: "-") || $0 == UInt8(ascii: "+") } == true
            ? bytes.dropFirst() : bytes[...]
        return unsigned.count > 1 && unsigned.first == UInt8(ascii: "0")
            && unsigned.dropFirst().allSatisfy { (UInt8(ascii: "0")...UInt8(ascii: "9")).contains($0) }
    }

    /// The integer reading of `text`, or `nil`: `visit_int` in `de.rs`. It
    /// tries a `u64`, an `i64`, a `u128`, and an `i128`, in that order.
    static func integer(_ text: String) -> YAMLScalarReading? {
        if let value: UInt64 = unsignedInteger(text) {
            return .unsigned(value)
        }
        if let value: Int64 = negativeInteger(text) {
            // `-0` and `-0x0` read as zero, which `From<i64>` makes positive.
            return value < 0 ? .negative(value) : .unsigned(UInt64(value))
        }
        let wideUnsigned: UInt128? = unsignedInteger(text)
        let wideNegative: Int128? = negativeInteger(text)
        return wideUnsigned != nil || wideNegative != nil ? .wideInteger : nil
    }

    /// `parse_unsigned_int` in `de.rs`.
    private static func unsignedInteger<T: FixedWidthInteger>(_ text: String) -> T? {
        let unpositive = text.utf8.first == UInt8(ascii: "+") ? String(decoding: text.utf8.dropFirst(), as: UTF8.self) : text
        for (prefix, radix) in radixPrefixes {
            guard let rest = utf8Suffix(of: unpositive, after: prefix) else { continue }
            guard !startsWithSign(rest) else { return nil }
            if let value: T = rustInteger(rest, radix: radix) {
                return value
            }
        }
        guard !startsWithSign(unpositive), !isDigitsButNotNumber(text) else { return nil }
        return rustInteger(unpositive, radix: NumberRadix.decimal)
    }

    /// `parse_negative_int` in `de.rs`.
    private static func negativeInteger<T: FixedWidthInteger>(_ text: String) -> T? {
        for (prefix, radix) in radixPrefixes {
            guard let rest = utf8Suffix(of: text, after: "-" + prefix) else { continue }
            if let value: T = rustInteger("-" + rest, radix: radix) {
                return value
            }
        }
        guard !isDigitsButNotNumber(text) else { return nil }
        return rustInteger(text, radix: NumberRadix.decimal)
    }

    /// The float of `text`, or `nil`: `parse_f64` in `de.rs`. An infinite
    /// result of the decimal parse is refused.
    static func float(_ text: String) -> Double? {
        var unpositive = text
        if text.utf8.first == UInt8(ascii: "+") {
            unpositive = String(decoding: text.utf8.dropFirst(), as: UTF8.self)
            guard !startsWithSign(unpositive) else { return nil }
        }
        if positiveInfinityTexts.contains(unpositive) {
            return .infinity
        }
        if negativeInfinityTexts.contains(text) {
            return -.infinity
        }
        if notANumberTexts.contains(text) {
            return .nan
        }
        guard RustDecimalSyntax.isFloat(unpositive), let value = Double(unpositive), value.isFinite else {
            return nil
        }
        return value
    }

    /// Whether `text` starts with `+` or `-`.
    private static func startsWithSign(_ text: String) -> Bool {
        text.utf8.first == UInt8(ascii: "+") || text.utf8.first == UInt8(ascii: "-")
    }

    /// The text after `prefix`, when `text` starts with it byte for byte
    /// (the Rust `str::strip_prefix`).
    private static func utf8Suffix(of text: String, after prefix: String) -> String? {
        guard text.utf8.starts(with: prefix.utf8) else { return nil }
        return String(decoding: text.utf8.dropFirst(prefix.utf8.count), as: UTF8.self)
    }

    /// The integer of `text` in `radix`, or `nil`: `from_str_radix` of the
    /// Rust integer types.
    ///
    /// One `+` may lead; one `-` may lead for a signed type (for an unsigned
    /// type it is a bad digit). A lone sign, an empty text, a bad digit, and
    /// an overflow give `nil`. A digit is `0`–`9`, then `a`–`z` in either case.
    static func rustInteger<T: FixedWidthInteger>(_ text: String, radix: Int) -> T? {
        var digits = text.utf8[...]
        var isNegative = false
        if let first = digits.first, first == UInt8(ascii: "+") || first == UInt8(ascii: "-") {
            guard digits.count > 1 else { return nil }
            if first == UInt8(ascii: "+") {
                digits = digits.dropFirst()
            } else if T.isSigned {
                isNegative = true
                digits = digits.dropFirst()
            }
        }
        guard !digits.isEmpty else { return nil }
        var value: T = 0
        for byte in digits {
            guard let digit = digitValue(byte), digit < radix else { return nil }
            let (shifted, isShiftOverflow) = value.multipliedReportingOverflow(by: T(radix))
            let (next, isAddOverflow) = isNegative
                ? shifted.subtractingReportingOverflow(T(digit)) : shifted.addingReportingOverflow(T(digit))
            guard !isShiftOverflow, !isAddOverflow else { return nil }
            value = next
        }
        return value
    }

    /// The value of one digit byte (`char::to_digit` with radix 36), or `nil`.
    private static func digitValue(_ byte: UInt8) -> Int? {
        switch byte {
        case UInt8(ascii: "0")...UInt8(ascii: "9"):
            return Int(byte - UInt8(ascii: "0"))
        case UInt8(ascii: "a")...UInt8(ascii: "z"):
            return Int(byte - UInt8(ascii: "a")) + letterDigitBase
        case UInt8(ascii: "A")...UInt8(ascii: "Z"):
            return Int(byte - UInt8(ascii: "A")) + letterDigitBase
        default:
            return nil
        }
    }
}

/// The decimal grammar of `str::parse::<f64>` in Rust (`core::num::dec2flt`),
/// for the texts that are not `inf`, `infinity`, or `nan`:
/// `Sign? (Digit+ | Digit+ '.' Digit* | Digit* '.' Digit+) ([eE] Sign? Digit+)?`.
enum RustDecimalSyntax {

    /// Whether `text` is a decimal float of that grammar.
    ///
    /// - Parameter text: The text to test.
    /// - Returns: `true` when the whole text matches.
    static func isFloat(_ text: String) -> Bool {
        var bytes = text.utf8[...]
        if let first = bytes.first, first == UInt8(ascii: "+") || first == UInt8(ascii: "-") {
            bytes = bytes.dropFirst()
        }
        let integerDigits = bytes.prefix(while: isDigit).count
        bytes = bytes.dropFirst(integerDigits)
        var fractionDigits = 0
        if bytes.first == UInt8(ascii: ".") {
            bytes = bytes.dropFirst()
            fractionDigits = bytes.prefix(while: isDigit).count
            bytes = bytes.dropFirst(fractionDigits)
        }
        guard integerDigits + fractionDigits > 0 else { return false }
        if let marker = bytes.first, marker == UInt8(ascii: "e") || marker == UInt8(ascii: "E") {
            bytes = bytes.dropFirst()
            if let sign = bytes.first, sign == UInt8(ascii: "+") || sign == UInt8(ascii: "-") {
                bytes = bytes.dropFirst()
            }
            let exponentDigits = bytes.prefix(while: isDigit).count
            guard exponentDigits > 0 else { return false }
            bytes = bytes.dropFirst(exponentDigits)
        }
        return bytes.isEmpty
    }

    /// Whether `byte` is an ASCII decimal digit.
    private static func isDigit(_ byte: UInt8) -> Bool {
        (UInt8(ascii: "0")...UInt8(ascii: "9")).contains(byte)
    }
}
