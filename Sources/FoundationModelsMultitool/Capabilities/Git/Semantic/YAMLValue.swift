// `YAMLValue` — the value of a YAML document, as serde_yaml_ng reads it.
//
// A port of the parts of serde_yaml_ng 0.10.0 that the YAML plugin of
// `../swissarmyhammer/crates/swissarmyhammer-sem/` reaches: the enum `Value`
// (`value/mod.rs`), the struct `Number` (`number.rs`), the struct `Mapping`
// (`mapping.rs`), and the struct `TaggedValue` (`value/tagged.rs`), with
// their equality and their `Display` and `Debug` texts.
//
// Two values are equal under the rules of serde_yaml_ng: a text compares
// byte for byte (not by canonical equivalence, as a Swift `String` does), two
// NaN floats are equal, a mapping compares with no regard to the order of its
// entries, and a tag compares with no regard to one leading `!`.

/// A YAML value: `Value` in serde_yaml_ng.
indirect enum YAMLValue: Hashable {

    /// `~`, `null`, an empty plain scalar.
    case null

    /// `true` or `false`.
    case bool(Bool)

    /// An integer or a float.
    case number(YAMLNumber)

    /// A text.
    case string(String)

    /// A sequence of values.
    case sequence([YAMLValue])

    /// A mapping of keys to values.
    case mapping(YAMLMapping)

    /// A value with a local tag (`!Ref Foo`). `tag` is the tag with its first
    /// `!` removed, as `parse_tag` in `de.rs` gives it.
    case tagged(tag: String, value: YAMLValue)

    /// The equality of `Value` in serde_yaml_ng.
    static func == (lhs: YAMLValue, rhs: YAMLValue) -> Bool {
        switch (lhs, rhs) {
        case (.null, .null):
            return true
        case (.bool(let left), .bool(let right)):
            return left == right
        case (.number(let left), .number(let right)):
            return left == right
        case (.string(let left), .string(let right)):
            return left.utf8.elementsEqual(right.utf8)
        case (.sequence(let left), .sequence(let right)):
            return left == right
        case (.mapping(let left), .mapping(let right)):
            return left == right
        case (.tagged(let leftTag, let leftValue), .tagged(let rightTag, let rightValue)):
            return Self.withoutBang(leftTag).utf8.elementsEqual(Self.withoutBang(rightTag).utf8)
                && leftValue == rightValue
        default:
            return false
        }
    }

    /// A hash that agrees with ``==(_:_:)``: `Hash` of `Value` in
    /// serde_yaml_ng.
    func hash(into hasher: inout Hasher) {
        switch self {
        case .null:
            hasher.combine(0)
        case .bool(let value):
            hasher.combine(value)
        case .number(let value):
            hasher.combine(value)
        case .string(let value):
            hasher.combine(Array(value.utf8))
        case .sequence(let values):
            hasher.combine(values)
        case .mapping(let mapping):
            hasher.combine(mapping)
        case .tagged(let tag, let value):
            hasher.combine(Array(Self.withoutBang(tag).utf8))
            hasher.combine(value)
        }
    }

    /// `tag` with one leading `!` removed, unless the tag is only `!`:
    /// `nobang` in `value/tagged.rs`.
    static func withoutBang(_ tag: String) -> String {
        guard tag.utf8.first == UInt8(ascii: "!"), tag.utf8.count > 1 else { return tag }
        return String(decoding: tag.utf8.dropFirst(), as: UTF8.self)
    }

    /// The text of a tag: `!` and the tag with no leading `!` (the `Display`
    /// and the `Debug` of `Tag` in `value/tagged.rs`).
    static func tagText(_ tag: String) -> String {
        "!" + withoutBang(tag)
    }

    /// The text that `format!("{:?}", value)` writes: the derived and the
    /// hand-written `Debug` of `Value` in `value/debug.rs`, for example
    /// `Null`, `Bool(true)`, `Number(1.5)`, `String("a")`, `Sequence [Null]`,
    /// `Mapping {"k": Number(1)}`, or `TaggedValue { tag: !Ref, value:
    /// String("Foo") }`.
    var debugText: String {
        switch self {
        case .null:
            return "Null"
        case .bool(let value):
            return "Bool(\(value))"
        case .number(let number):
            return "Number(\(number.text))"
        case .string(let text):
            return "String(\(RustText.debugQuoted(text)))"
        case .sequence(let values):
            return "Sequence [" + values.map(\.debugText).joined(separator: ", ") + "]"
        case .mapping(let mapping):
            return "Mapping {" + mapping.entries.map { "\($0.key.mappingKeyDebugText): \($0.value.debugText)" }
                .joined(separator: ", ") + "}"
        case .tagged(let tag, let value):
            return "TaggedValue { tag: \(Self.tagText(tag)), value: \(value.debugText) }"
        }
    }

    /// The text of a key in the `Debug` of `Mapping`: a bool, a number, and
    /// a text write their own `Debug` (with no `Bool(…)`, `Number(…)`, or
    /// `String(…)` around it); each other key writes the `Debug` of `Value`.
    private var mappingKeyDebugText: String {
        switch self {
        case .bool(let value):
            return String(value)
        case .number(let number):
            return number.text
        case .string(let text):
            return RustText.debugQuoted(text)
        default:
            return debugText
        }
    }
}

/// A YAML number: `Number` in serde_yaml_ng.
///
/// An integer of zero or more is ``positive(_:)``, a negative integer is
/// ``negative(_:)``. The two never compare equal to each other or to a
/// float.
enum YAMLNumber: Hashable {

    /// An integer of zero or more (`N::PosInt`).
    case positive(UInt64)

    /// An integer below zero (`N::NegInt`).
    case negative(Int64)

    /// A float (`N::Float`). serde_yaml_ng keeps one NaN.
    case float(Double)

    /// The first value that ``hash(into:)`` combines for a positive integer.
    private static let positiveHashKind = 0

    /// The first value that ``hash(into:)`` combines for a negative integer.
    private static let negativeHashKind = 1

    /// The value that ``hash(into:)`` combines for a float.
    private static let floatHashKind = 2

    /// The equality of `N` in serde_yaml_ng: two NaN floats are equal.
    static func == (lhs: YAMLNumber, rhs: YAMLNumber) -> Bool {
        switch (lhs, rhs) {
        case (.positive(let left), .positive(let right)):
            return left == right
        case (.negative(let left), .negative(let right)):
            return left == right
        case (.float(let left), .float(let right)):
            return (left.isNaN && right.isNaN) || left == right
        default:
            return false
        }
    }

    /// A hash that agrees with ``==(_:_:)``. As in serde_yaml_ng, every float
    /// has the same hash.
    func hash(into hasher: inout Hasher) {
        switch self {
        case .positive(let value):
            hasher.combine(Self.positiveHashKind)
            hasher.combine(value)
        case .negative(let value):
            hasher.combine(Self.negativeHashKind)
            hasher.combine(value)
        case .float:
            hasher.combine(Self.floatHashKind)
        }
    }

    /// The `Display` text of the number, which is also the text that the
    /// serializer writes: the decimal integer, `.nan`, `.inf`, `-.inf`, or the
    /// `ryu` text of a float.
    var text: String {
        switch self {
        case .positive(let value):
            return String(value)
        case .negative(let value):
            return String(value)
        case .float(let value) where value.isNaN:
            return ".nan"
        case .float(let value) where value.isInfinite:
            return value < 0 ? "-.inf" : ".inf"
        case .float(let value):
            return RustFloatText.ryu(value)
        }
    }
}

/// A YAML mapping: `Mapping` in serde_yaml_ng, an ordered map that compares
/// with no regard to the order of its entries.
struct YAMLMapping: Hashable {

    /// One key and its value. A struct and not a tuple: an array of tuples
    /// of the indirect ``YAMLValue`` makes the Swift 6.4 compiler report a
    /// circular reference.
    struct Entry: Hashable {

        /// The key.
        let key: YAMLValue

        /// The value of the key.
        let value: YAMLValue
    }

    /// The entries, in the order of the text.
    let entries: [Entry]

    /// Two mappings are equal when they hold the same keys with equal values.
    static func == (lhs: YAMLMapping, rhs: YAMLMapping) -> Bool {
        guard lhs.entries.count == rhs.entries.count else { return false }
        let right = Dictionary(rhs.entries.map { ($0.key, $0.value) }, uniquingKeysWith: { first, _ in first })
        return lhs.entries.allSatisfy { right[$0.key] == $0.value }
    }

    /// A hash that does not read the order of the entries (the XOR of the
    /// hash of each entry, as in serde_yaml_ng).
    func hash(into hasher: inout Hasher) {
        hasher.combine(entries.reduce(0) { $0 ^ $1.hashValue })
    }
}
