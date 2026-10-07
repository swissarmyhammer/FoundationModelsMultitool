// `TOMLSourceScanner` — reads the parts of a TOML text that TOMLDecoder does
// not keep: the spelling of each time, and the integers that are out of the
// 64-bit range.
//
// The `toml` crate refuses an integer that is out of the `i64` range.
// TOMLDecoder reads such an integer as a float. Thus the TOML plugin finds
// these integers in the source text and refuses the file, as Rust does.

/// One time in a TOML text: `HH:MM`, with optional `:SS` and `.fraction`.
struct TOMLTimeLiteral {

    /// The hour.
    let hour: Int

    /// The minute.
    let minute: Int

    /// The second, or `nil` when the text has none.
    let second: Int?

    /// The digits of the fraction, or `nil` when the text has none.
    let fraction: [UInt8]?
}

/// Finds the times and the out-of-range integers of a TOML text. Each string
/// form of TOML (basic, literal, and their multi-line forms) and each comment
/// is passed over.
enum TOMLSourceScanner {

    /// The bytes that cannot come just before a time.
    private static let refusedPrefixes: Set<UInt8> = [
        UInt8(ascii: ":"), UInt8(ascii: "."), UInt8(ascii: "+"), UInt8(ascii: "-"),
    ]

    /// The count of quote marks that open a multi-line string.
    private static let multiLineQuoteCount = 3

    /// The count of bytes of `HH:MM`.
    private static let hourMinuteLength = 5

    /// The count of digits of a part of a time.
    private static let partDigits = 2

    /// The count of bytes of an escape in a basic string: `\` and one byte.
    private static let escapeLength = 2

    /// The prefixes of the integer forms that are not decimal, and their bases.
    /// The match is case-sensitive, as in TOML and the `toml` crate: `0X1` is
    /// not an integer.
    private static let radixPrefixes: [(prefix: [UInt8], radix: Int)] = [
        (Array("0x".utf8), NumberRadix.hexadecimal), (Array("0o".utf8), NumberRadix.octal),
        (Array("0b".utf8), NumberRadix.binary),
    ]

    /// The bytes that open a nested value: an array or an inline table.
    private static let openBrackets: Set<UInt8> = [UInt8(ascii: "["), UInt8(ascii: "{")]

    /// The bytes that close a nested value.
    private static let closeBrackets: Set<UInt8> = [UInt8(ascii: "]"), UInt8(ascii: "}")]

    /// The bytes between a value token and the next part of the line.
    private static let blanks: Set<UInt8> = [UInt8(ascii: " "), UInt8(ascii: "\t")]

    /// The times of `bytes`, in order.
    ///
    /// A time is two digits, `:`, and two digits, with no digit, `:`, `.`, `+`,
    /// or `-` before it (thus the offset of a datetime is not a time).
    ///
    /// - Parameter bytes: The UTF-8 bytes of the TOML text.
    /// - Returns: The times.
    static func timeLiterals(in bytes: [UInt8]) -> [TOMLTimeLiteral] {
        var literals: [TOMLTimeLiteral] = []
        var index = 0
        while index < bytes.count {
            if let end = endOfSkippedPart(in: bytes, at: index) {
                index = end
            } else if let (literal, end) = literal(in: bytes, at: index) {
                literals.append(literal)
                index = end
            } else {
                index += 1
            }
        }
        return literals
    }

    /// Whether a value of `bytes` is an integer out of the `Int64` range,
    /// which the `toml` crate refuses.
    ///
    /// The check reads each token of a value: the text after `=`, up to the
    /// end of the line or of its arrays and inline tables. A token is a run of
    /// letters, digits, `_`, `+`, `-`, `.`, and `:`. A token that a `=`
    /// follows is a key of an inline table, and is not read.
    ///
    /// - Parameter bytes: The UTF-8 bytes of the TOML text.
    /// - Returns: `true` when such an integer is found.
    static func hasIntegerOutOfRange(in bytes: [UInt8]) -> Bool {
        var isInValue = false
        var depth = 0
        var index = 0
        while index < bytes.count {
            if let end = endOfSkippedPart(in: bytes, at: index) {
                index = end
                continue
            }
            let byte = bytes[index]
            if isTokenByte(byte) {
                let end = bytes[index...].firstIndex { !isTokenByte($0) } ?? bytes.count
                if isInValue && !isKey(in: bytes, after: end) && isOutOfRange(Array(bytes[index..<end])) {
                    return true
                }
                index = end
                continue
            }
            switch byte {
            case UInt8(ascii: "=") where depth == 0:
                isInValue = true
            case UInt8(ascii: "\n") where depth == 0:
                isInValue = false
            case let open where isInValue && openBrackets.contains(open):
                depth += 1
            case let close where isInValue && depth > 0 && closeBrackets.contains(close):
                depth -= 1
            default:
                break
            }
            index += 1
        }
        return false
    }

    /// The index after the comment or the string at `index`, or `nil` when
    /// neither starts there.
    private static func endOfSkippedPart(in bytes: [UInt8], at index: Int) -> Int? {
        switch bytes[index] {
        case UInt8(ascii: "#"):
            return bytes[index...].firstIndex(of: UInt8(ascii: "\n")) ?? bytes.count
        case UInt8(ascii: "\""), UInt8(ascii: "'"):
            return endOfString(in: bytes, at: index)
        default:
            return nil
        }
    }

    /// Whether `byte` can be part of a value token.
    private static func isTokenByte(_ byte: UInt8) -> Bool {
        isDigit(byte) || (UInt8(ascii: "a")...UInt8(ascii: "z")).contains(byte)
            || (UInt8(ascii: "A")...UInt8(ascii: "Z")).contains(byte)
            || [UInt8(ascii: "_"), UInt8(ascii: "+"), UInt8(ascii: "-"), UInt8(ascii: "."), UInt8(ascii: ":")]
                .contains(byte)
    }

    /// Whether a `=` comes after the blanks at `index`: the token before
    /// `index` is then a key.
    private static func isKey(in bytes: [UInt8], after index: Int) -> Bool {
        let next = bytes[index...].first { !blanks.contains($0) }
        return next == UInt8(ascii: "=")
    }

    /// Whether `token` is a TOML integer that `Int64` cannot hold.
    private static func isOutOfRange(_ token: [UInt8]) -> Bool {
        var body = token[...]
        var sign: [UInt8] = []
        if let first = body.first, first == UInt8(ascii: "+") || first == UInt8(ascii: "-") {
            sign = first == UInt8(ascii: "-") ? [first] : []
            body = body.dropFirst()
        }
        var radix = NumberRadix.decimal
        for form in radixPrefixes where body.starts(with: form.prefix) {
            radix = form.radix
            body = body.dropFirst(form.prefix.count)
        }
        let digits = body.filter { $0 != UInt8(ascii: "_") }
        guard !digits.isEmpty, digits.allSatisfy({ isDigit($0, radix: radix) }) else { return false }
        return Int64(String(decoding: sign + digits, as: UTF8.self), radix: radix) == nil
    }

    /// The index after the string that opens at `start`.
    private static func endOfString(in bytes: [UInt8], at start: Int) -> Int {
        let quote = bytes[start]
        let isBasic = quote == UInt8(ascii: "\"")
        let isMultiLine = bytes[start...].prefix(multiLineQuoteCount).allSatisfy { $0 == quote }
            && bytes.count - start >= multiLineQuoteCount
        var index = start + (isMultiLine ? multiLineQuoteCount : 1)
        while index < bytes.count {
            let byte = bytes[index]
            if isBasic && byte == UInt8(ascii: "\\") {
                index += escapeLength
                continue
            }
            if byte == quote && (!isMultiLine || bytes[index...].prefix(multiLineQuoteCount).allSatisfy { $0 == quote }) {
                return index + (isMultiLine ? multiLineQuoteCount : 1)
            }
            if !isMultiLine && byte == UInt8(ascii: "\n") {
                return index
            }
            index += 1
        }
        return index
    }

    /// The time that starts at `start`, and the index after it, or `nil`.
    private static func literal(in bytes: [UInt8], at start: Int) -> (TOMLTimeLiteral, Int)? {
        guard start + hourMinuteLength <= bytes.count,
            start == 0 || !(isDigit(bytes[start - 1]) || refusedPrefixes.contains(bytes[start - 1])),
            let hour = number(in: bytes, at: start), bytes[start + partDigits] == UInt8(ascii: ":"),
            let minute = number(in: bytes, at: start + partDigits + 1)
        else { return nil }
        var index = start + hourMinuteLength
        var second: Int?
        var fraction: [UInt8]?
        if index < bytes.count, bytes[index] == UInt8(ascii: ":"), let value = number(in: bytes, at: index + 1) {
            second = value
            index += partDigits + 1
            if index < bytes.count, bytes[index] == UInt8(ascii: ".") {
                let digits = Array(bytes[(index + 1)...].prefix { isDigit($0) })
                if !digits.isEmpty {
                    fraction = digits
                    index += digits.count + 1
                }
            }
        }
        return (TOMLTimeLiteral(hour: hour, minute: minute, second: second, fraction: fraction), index)
    }

    /// The value of the two digits at `index`, or `nil`.
    private static func number(in bytes: [UInt8], at index: Int) -> Int? {
        guard index + partDigits <= bytes.count, isDigit(bytes[index]), isDigit(bytes[index + 1]) else { return nil }
        return Int(bytes[index] - UInt8(ascii: "0")) * NumberRadix.decimal + Int(bytes[index + 1] - UInt8(ascii: "0"))
    }

    /// Whether `byte` is a digit of `radix` (decimal when not given). The
    /// letters of a hexadecimal digit can be in either case, as TOML permits.
    private static func isDigit(_ byte: UInt8, radix: Int = NumberRadix.decimal) -> Bool {
        guard let value = Character(Unicode.Scalar(byte)).hexDigitValue else { return false }
        return value < radix
    }
}
