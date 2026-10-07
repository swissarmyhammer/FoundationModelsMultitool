// `TOMLValue` — the value of a TOML document, as the `toml` crate holds it,
// and the two texts of a value that the TOML plugin hashes.
//
// The TOML plugin of `../swissarmyhammer/crates/swissarmyhammer-sem/`
// (`toml_plugin.rs`) parses with the `toml` crate 1.1.2, whose `Table` is a
// `BTreeMap` (the keys in byte order). It hashes a table as the text of
// `serde_json::to_string_pretty`, and each other value as the text of
// `toml_value_to_string`. This file parses with TOMLDecoder and writes those
// two texts.
//
// A datetime is the one value whose text TOMLDecoder cannot give in full: the
// `toml_datetime` crate writes `07:32` for a time with no seconds (TOML 1.1)
// and `07:32:00.0` for a zero fraction, while TOMLDecoder keeps a second and
// a nanosecond only. ``TOMLTimeSpellings`` reads the spelling of each time
// from the source text (see ``TOMLSourceScanner``).
//
// Known gaps from the `toml` crate:
// - When one file writes the same time in two spellings (for example `07:32`
//   and `07:32:00`), the first spelling is used for both. TOMLDecoder does not
//   tell where in the text a value is.
// - TOMLDecoder refuses a leap second (`23:59:60`), which the `toml` crate
//   accepts; for such a file this plugin gives no entity.

import TOMLDecoder

/// A TOML value: `toml::Value`.
indirect enum TOMLValue {

    /// A text.
    case string(String)

    /// A 64-bit integer.
    case integer(Int64)

    /// A float.
    case float(Double)

    /// A boolean.
    case boolean(Bool)

    /// A datetime, as the `Display` of `toml_datetime::Datetime` writes it.
    case datetime(String)

    /// An array.
    case array([TOMLValue])

    /// A table, with its keys in byte order.
    case table([TOMLTableEntry])

    /// The root table of `source`, or `nil` when TOMLDecoder refuses the
    /// text. Each value is read, so a value that is not valid fails here too.
    /// An integer out of the `Int64` range also gives `nil`, as in the `toml`
    /// crate (TOMLDecoder reads it as a float).
    ///
    /// - Parameter source: The TOML text.
    /// - Returns: The root table.
    static func root(of source: String) -> TOMLValue? {
        guard let table = try? TOMLTable(source: source), let dictionary = try? [String: Any](table),
            !TOMLSourceScanner.hasIntegerOutOfRange(in: Array(source.utf8))
        else {
            return nil
        }
        return TOMLValue(any: dictionary, spellings: TOMLTimeSpellings(source: source))
    }

    /// The value of one value of `Dictionary(TOMLTable)`.
    private init?(any value: Any, spellings: TOMLTimeSpellings) {
        switch value {
        case let text as String:
            self = .string(text)
        case let integer as Int64:
            self = .integer(integer)
        case let float as Double:
            self = .float(float)
        case let flag as Bool:
            self = .boolean(flag)
        case let array as [Any]:
            self = .array(array.compactMap { TOMLValue(any: $0, spellings: spellings) })
        case let dictionary as [String: Any]:
            self = .table(
                dictionary.compactMap { key, value in
                    TOMLValue(any: value, spellings: spellings).map { TOMLTableEntry(key: key, value: $0) }
                }
                    .sorted { $0.key.utf8.lexicographicallyPrecedes($1.key.utf8) })
        default:
            guard let text = spellings.datetimeText(of: value) else { return nil }
            self = .datetime(text)
        }
    }

    /// The text of a value that is not a table: `toml_value_to_string` in
    /// `toml_plugin.rs`. A float writes its Rust `Display` (`inf`, `NaN`, no
    /// exponent), and an array writes its pretty JSON text.
    var scalarText: String {
        switch self {
        case .string(let text):
            return text
        case .integer(let integer):
            return String(integer)
        case .float(let float) where float.isNaN:
            return "NaN"
        case .float(let float) where float.isInfinite:
            return float < 0 ? "-inf" : "inf"
        case .float(let float):
            return RustFloatText.display(float)
        case .boolean(let flag):
            return String(flag)
        case .datetime(let text):
            return text
        case .array, .table:
            return prettyJSON
        }
    }

    /// The text of `serde_json::to_string_pretty` of the value.
    var prettyJSON: String {
        prettyJSON(indent: "")
    }

    /// The indent of one level of `serde_json::PrettyFormatter`.
    private static let jsonIndentUnit = "  "

    /// The key of the struct that `toml_datetime` serializes a datetime as.
    private static let datetimeField = "$__toml_private_datetime"

    /// The pretty JSON text of the value at the nesting `indent`.
    private func prettyJSON(indent: String) -> String {
        switch self {
        case .string(let text):
            return JSONText.quoted(text)
        case .integer(let integer):
            return String(integer)
        case .float(let float):
            return float.isFinite ? RustFloatText.serdeJSON(float) : "null"
        case .boolean(let flag):
            return String(flag)
        case .datetime(let text):
            return Self.prettyJSONObject([TOMLTableEntry(key: Self.datetimeField, value: .string(text))], indent: indent)
        case .array(let elements):
            guard !elements.isEmpty else { return "[]" }
            let inner = indent + Self.jsonIndentUnit
            return "[\n" + elements.map { inner + $0.prettyJSON(indent: inner) }.joined(separator: ",\n")
                + "\n" + indent + "]"
        case .table(let entries):
            return Self.prettyJSONObject(entries, indent: indent)
        }
    }

    /// The pretty JSON text of an object with `entries`, in their order.
    private static func prettyJSONObject(_ entries: [TOMLTableEntry], indent: String) -> String {
        guard !entries.isEmpty else { return "{}" }
        let inner = indent + jsonIndentUnit
        return "{\n"
            + entries.map { inner + JSONText.quoted($0.key) + ": " + $0.value.prettyJSON(indent: inner) }
            .joined(separator: ",\n") + "\n" + indent + "}"
    }
}

/// One key of a TOML table and its value. A struct and not a tuple: an array
/// of tuples of the indirect ``TOMLValue`` makes the Swift 6.4 compiler report
/// a circular reference.
struct TOMLTableEntry {

    /// The key.
    let key: String

    /// The value of the key.
    let value: TOMLValue
}

/// The JSON text rules of serde_json.
enum JSONText {

    /// The short escapes of serde_json for the bytes below a space, `"`, and
    /// `\`. Each other byte below a space is written `\u00XX`.
    private static let shortEscapes: [Unicode.Scalar: String] = [
        "\"": "\\\"", "\\": "\\\\", "\u{08}": "\\b", "\u{0C}": "\\f", "\n": "\\n", "\r": "\\r", "\t": "\\t",
    ]

    /// The first scalar that serde_json writes as it is (a space).
    private static let firstPlainScalar: UInt32 = 0x20

    /// The count of hex digits after `\u00`.
    private static let controlEscapeDigits = 2

    /// `text` as a JSON string: `format_escaped_str` of serde_json.
    ///
    /// - Parameter text: The text.
    /// - Returns: The quoted text.
    static func quoted(_ text: String) -> String {
        "\"" + text.unicodeScalars.map(escapedText).joined() + "\""
    }

    /// The text of one scalar in a JSON string: its short escape, its
    /// `\u00XX` escape, or the scalar itself.
    private static func escapedText(of scalar: Unicode.Scalar) -> String {
        if let escape = shortEscapes[scalar] {
            return escape
        }
        guard scalar.value < firstPlainScalar else { return String(scalar) }
        let hex = String(scalar.value, radix: NumberRadix.hexadecimal)
        return "\\u00" + String(repeating: "0", count: controlEscapeDigits - hex.count) + hex
    }
}

/// The spelling of each time in a TOML text, and the `Display` text of each
/// TOMLDecoder datetime: `Display` of `toml_datetime::Datetime`.
struct TOMLTimeSpellings {

    /// A time with its seconds and nanoseconds as TOMLDecoder holds them.
    private struct TimeKey: Hashable {
        let hour: Int
        let minute: Int
        let second: Int
        let nanosecond: Int
    }

    /// The count of fraction digits that `toml_datetime` keeps.
    private static let nanosecondDigits = 9

    /// The count of digits of a part of a date or a time.
    private static let partDigits = 2

    /// The count of digits of a year.
    private static let yearDigits = 4

    /// The count of minutes in one hour.
    private static let minutesPerHour = 60

    /// The first spelling of each time in the source.
    private let spellings: [TimeKey: String]

    /// The spellings of the times in `source`. When the source writes the
    /// same time two or more times, the first spelling is kept.
    ///
    /// - Parameter source: The TOML text.
    init(source: String) {
        spellings = Dictionary(
            TOMLSourceScanner.timeLiterals(in: Array(source.utf8)).map(Self.spelling),
            uniquingKeysWith: { first, _ in first })
    }

    /// The key and the spelling of one time of the source.
    private static func spelling(of literal: TOMLTimeLiteral) -> (TimeKey, String) {
        let nanosecond = literal.fraction.map(nanoseconds)
        let key = TimeKey(
            hour: literal.hour, minute: literal.minute, second: literal.second ?? 0, nanosecond: nanosecond ?? 0)
        let text = timeText(hour: literal.hour, minute: literal.minute, second: literal.second, nanosecond: nanosecond)
        return (key, text)
    }

    /// The `Display` text of a TOMLDecoder datetime value, or `nil` when
    /// `value` is not a datetime.
    ///
    /// - Parameter value: A value of `Dictionary(TOMLTable)`.
    /// - Returns: For example `1979-05-27T07:32:00Z`, `07:32`, or
    ///   `1979-05-27`.
    func datetimeText(of value: Any) -> String? {
        switch value {
        case let datetime as OffsetDateTime:
            return Self.dateText(datetime.date) + "T" + timeText(datetime.time) + Self.offsetText(datetime)
        case let datetime as LocalDateTime:
            return Self.dateText(datetime.date) + "T" + timeText(datetime.time)
        case let date as LocalDate:
            return Self.dateText(date)
        case let time as LocalTime:
            return timeText(time)
        default:
            return nil
        }
    }

    /// The text of a time: its spelling in the source, else the text with
    /// seconds and a fraction only when the fraction is not zero.
    private func timeText(_ time: LocalTime) -> String {
        let key = TimeKey(
            hour: Int(time.hour), minute: Int(time.minute), second: Int(time.second),
            nanosecond: Int(time.nanosecond))
        return spellings[key]
            ?? Self.timeText(
                hour: key.hour, minute: key.minute, second: key.second,
                nanosecond: key.nanosecond == 0 ? nil : key.nanosecond)
    }

    /// `HH:MM[:SS][.fraction]`: the `Display` of `toml_datetime::Time`.
    private static func timeText(hour: Int, minute: Int, second: Int?, nanosecond: Int?) -> String {
        var text = padded(hour, to: partDigits) + ":" + padded(minute, to: partDigits)
        if let second = second ?? (nanosecond == nil ? nil : 0) {
            text += ":" + padded(second, to: partDigits)
        }
        if let nanosecond {
            let digits = padded(nanosecond, to: nanosecondDigits).reversed().drop { $0 == "0" }.reversed()
            text += "." + (digits.isEmpty ? "0" : String(digits))
        }
        return text
    }

    /// `YYYY-MM-DD`: the `Display` of `toml_datetime::Date`.
    private static func dateText(_ date: LocalDate) -> String {
        padded(Int(date.year), to: yearDigits) + "-" + padded(Int(date.month), to: partDigits) + "-"
            + padded(Int(date.day), to: partDigits)
    }

    /// `Z`, or `+HH:MM` / `-HH:MM`: the `Display` of `toml_datetime::Offset`.
    private static func offsetText(_ datetime: OffsetDateTime) -> String {
        if datetime.features.contains(.lowercaseZ) || datetime.features.contains(.uppercaseZ) {
            return "Z"
        }
        let minutes = Int(datetime.offset)
        return (minutes < 0 ? "-" : "+") + padded(abs(minutes) / minutesPerHour, to: partDigits) + ":"
            + padded(abs(minutes) % minutesPerHour, to: partDigits)
    }

    /// The nanoseconds of the fraction digits: `s_to_nanoseconds` of
    /// `toml_datetime`, which reads the first nine digits.
    private static func nanoseconds(_ fraction: [UInt8]) -> Int {
        let digits = fraction.prefix(nanosecondDigits).map { Int($0 - UInt8(ascii: "0")) }
        let padding = Array(repeating: 0, count: nanosecondDigits - digits.count)
        return (digits + padding).reduce(0) { $0 * NumberRadix.decimal + $1 }
    }

    /// `value` in decimal with leading zeros to `width` digits.
    private static func padded(_ value: Int, to width: Int) -> String {
        let digits = String(value)
        return String(repeating: "0", count: max(0, width - digits.count)) + digits
    }
}

