// `YAMLLoader` — reads a YAML text into a ``YAMLValue`` the way
// `serde_yaml_ng::from_str::<Value>` reads it.
//
// A port of serde_yaml_ng 0.10.0: the parser wrapper (`libyaml/parser.rs`),
// the event loader (`loader.rs`), and the event deserializer
// (`DeserializerFromEvents` in `de.rs`) with the `Value` visitor
// (`value/de.rs`). The events come from the libyaml 0.2.5 C parser of the
// `CYaml` module of Yams — the same libyaml that serde_yaml_ng runs through
// unsafe-libyaml — thus each parse error, anchor, tag, and scalar style is
// the same as in Rust.
//
// serde_yaml_ng refuses the text, and this loader throws, when:
// - libyaml reports a parse error, or the text has a second document;
// - an alias names an anchor that no earlier node defines;
// - a node nests more than 128 containers deep, or the aliases expand more
//   than 100 times the count of events (`RecursionLimitExceeded`,
//   `RepetitionLimitExceeded`);
// - a mapping repeats a key (keys compare as values: `0x1` and `1` are the
//   same key);
// - a scalar with a core tag (`!!bool`, `!!int`, `!!float`, `!!null`) does
//   not read as that type, or a plain integer needs more than 64 bits.

import CYaml
import Foundation

/// The reasons that serde_yaml_ng refuses a YAML text.
enum YAMLLoadError: Error {

    /// libyaml could not create its parser.
    case parserUnavailable

    /// libyaml reported a syntax error.
    case syntax

    /// The text holds more than one document.
    case moreThanOneDocument

    /// An alias names an anchor that no earlier node defines.
    case unknownAnchor

    /// The events stopped before a node was complete.
    case endOfStream

    /// The nesting is deeper than ``YAMLLoader/recursionLimit``.
    case recursionLimitExceeded

    /// The aliases expand more than ``YAMLLoader/repetitionFactor`` times the
    /// count of events.
    case repetitionLimitExceeded

    /// A mapping repeats a key.
    case duplicateKey

    /// A scalar does not read as the value its tag or its text asks for.
    case invalidScalar
}

/// The YAML reader of the YAML plugin: `from_str::<Value>` of serde_yaml_ng.
enum YAMLLoader {

    /// The largest nesting of containers: `remaining_depth: 128` in `de.rs`.
    static let recursionLimit = 128

    /// The largest count of alias expansions for each event: `jumpcount >
    /// events.len() * 100` in `de.rs`.
    static let repetitionFactor = 100

    /// The value of the one document of `text`.
    ///
    /// - Parameter text: The YAML text.
    /// - Returns: The value; ``YAMLValue/null`` for a text with no document.
    /// - Throws: ``YAMLLoadError`` when serde_yaml_ng refuses the text.
    static func value(of text: String) throws(YAMLLoadError) -> YAMLValue {
        let document = try YAMLDocumentEvents(text: text)
        var reader = YAMLEventReader(document: document)
        var position = 0
        return try reader.value(at: &position, remainingDepth: recursionLimit, isTaggedAlready: false)
    }
}

/// One event of a loaded document: `Event` in `de.rs`.
private enum YAMLEvent {

    /// An alias, by the id of its anchor.
    case alias(Int)

    /// A scalar.
    case scalar(YAMLScalarEvent)

    /// The start of a sequence, with its tag.
    case sequenceStart(tag: String?)

    /// The end of a sequence.
    case sequenceEnd

    /// The start of a mapping, with its tag.
    case mappingStart(tag: String?)

    /// The end of a mapping.
    case mappingEnd

    /// The node of a text with no document.
    case void
}

/// One scalar event: `Scalar` in `libyaml/parser.rs`.
private struct YAMLScalarEvent {

    /// The tag after libyaml resolved its handle (`!!int` is
    /// `tag:yaml.org,2002:int`), or `nil`.
    let tag: String?

    /// The text of the scalar.
    let value: String

    /// Whether the scalar has the plain style (no quote marks, no block).
    let isPlain: Bool
}

/// The events of the first document of a YAML text: `Loader` and
/// `next_document` in `loader.rs`, and the test for a second document of
/// `Deserializer::de` in `de.rs`.
private struct YAMLDocumentEvents {

    /// The events of the document, in order.
    private(set) var events: [YAMLEvent] = []

    /// The index in ``events`` of the node of each anchor id.
    private(set) var aliasTargets: [Int: Int] = [:]

    /// The id of each anchor name. A name that a later node defines again
    /// gets the id `count`, as in `loader.rs` (where a reused name does not
    /// grow the count).
    private var anchorIDs: [[UInt8]: Int] = [:]

    /// The events of the first document of `text`.
    ///
    /// - Throws: ``YAMLLoadError`` for a parse error, an unknown anchor, and
    ///   a second document.
    init(text: String) throws(YAMLLoadError) {
        var parser = yaml_parser_t()
        guard yaml_parser_initialize(&parser) == 1 else { throw .parserUnavailable }
        defer { yaml_parser_delete(&parser) }
        yaml_parser_set_encoding(&parser, YAML_UTF8_ENCODING)
        // libyaml needs an input pointer that is not null, also for an empty
        // text; the terminator is not part of the input.
        let bytes = Array(text.utf8) + [0]
        try bytes.withUnsafeBufferPointer { (buffer) throws(YAMLLoadError) in
            yaml_parser_set_input_string(&parser, buffer.baseAddress, buffer.count - 1)
            try readFirstDocument(parser: &parser)
        }
    }

    /// Reads the events of the first document, and then checks that the
    /// stream ends.
    private mutating func readFirstDocument(parser: inout yaml_parser_t) throws(YAMLLoadError) {
        while true {
            var event = yaml_event_t()
            guard yaml_parser_parse(&parser, &event) == 1 else { throw .syntax }
            defer { yaml_event_delete(&event) }
            switch event.type {
            case YAML_STREAM_START_EVENT, YAML_DOCUMENT_START_EVENT:
                continue
            case YAML_STREAM_END_EVENT:
                if events.isEmpty {
                    events.append(.void)
                }
                return
            case YAML_DOCUMENT_END_EVENT:
                try Self.requireStreamEnd(parser: &parser)
                return
            default:
                try append(event)
            }
        }
    }

    /// Throws ``YAMLLoadError/moreThanOneDocument`` unless the next event is
    /// the end of the stream.
    private static func requireStreamEnd(parser: inout yaml_parser_t) throws(YAMLLoadError) {
        var event = yaml_event_t()
        guard yaml_parser_parse(&parser, &event) == 1 else { throw .moreThanOneDocument }
        defer { yaml_event_delete(&event) }
        guard event.type == YAML_STREAM_END_EVENT else { throw .moreThanOneDocument }
    }

    /// Adds one node event; an anchor on it gets an id.
    private mutating func append(_ event: yaml_event_t) throws(YAMLLoadError) {
        switch event.type {
        case YAML_ALIAS_EVENT:
            guard let id = anchorIDs[Self.bytes(event.data.alias.anchor) ?? []] else { throw .unknownAnchor }
            events.append(.alias(id))
        case YAML_SCALAR_EVENT:
            let scalar = event.data.scalar
            defineAnchor(scalar.anchor)
            let value = String(decoding: UnsafeBufferPointer(start: scalar.value, count: scalar.length), as: UTF8.self)
            events.append(
                .scalar(
                    YAMLScalarEvent(
                        tag: Self.text(scalar.tag), value: value, isPlain: scalar.style == YAML_PLAIN_SCALAR_STYLE)))
        case YAML_SEQUENCE_START_EVENT:
            defineAnchor(event.data.sequence_start.anchor)
            events.append(.sequenceStart(tag: Self.text(event.data.sequence_start.tag)))
        case YAML_MAPPING_START_EVENT:
            defineAnchor(event.data.mapping_start.anchor)
            events.append(.mappingStart(tag: Self.text(event.data.mapping_start.tag)))
        case YAML_SEQUENCE_END_EVENT:
            events.append(.sequenceEnd)
        default:
            events.append(.mappingEnd)
        }
    }

    /// Gives the next node the anchor `anchor`, when there is one.
    private mutating func defineAnchor(_ anchor: UnsafeMutablePointer<yaml_char_t>?) {
        guard let name = Self.bytes(anchor) else { return }
        let id = anchorIDs.count
        anchorIDs[name] = id
        aliasTargets[id] = events.count
    }

    /// The bytes of a C string of libyaml, or `nil` for a null pointer.
    private static func bytes(_ pointer: UnsafeMutablePointer<yaml_char_t>?) -> [UInt8]? {
        pointer.map { Array(UnsafeBufferPointer(start: $0, count: strlen(UnsafeRawPointer($0).assumingMemoryBound(to: CChar.self)))) }
    }

    /// The text of a C string of libyaml, or `nil` for a null pointer.
    private static func text(_ pointer: UnsafeMutablePointer<yaml_char_t>?) -> String? {
        bytes(pointer).map { String(decoding: $0, as: UTF8.self) }
    }
}

/// Reads the events of a document into a value: `DeserializerFromEvents` in
/// `de.rs` with the `Value` visitor of `value/de.rs`.
private struct YAMLEventReader {

    /// The tag of a boolean scalar: `Tag::BOOL`.
    private static let boolTag = "tag:yaml.org,2002:bool"

    /// The tag of an integer scalar: `Tag::INT`.
    private static let integerTag = "tag:yaml.org,2002:int"

    /// The tag of a float scalar: `Tag::FLOAT`.
    private static let floatTag = "tag:yaml.org,2002:float"

    /// The tag of a null scalar: `Tag::NULL`.
    private static let nullTag = "tag:yaml.org,2002:null"

    /// The events of the document.
    let document: YAMLDocumentEvents

    /// The count of alias expansions so far: `jumpcount` in `de.rs`.
    private var jumpCount = 0

    /// A reader of `document`.
    init(document: YAMLDocumentEvents) {
        self.document = document
    }

    /// The value of the node at `position`, which then points after the node:
    /// `deserialize_any` in `de.rs`.
    ///
    /// - Parameters:
    ///   - position: The index of the first event of the node.
    ///   - remainingDepth: The count of containers that may still open.
    ///   - isTaggedAlready: Whether the node is the content of a local tag
    ///     (the `tagged_already` of `de.rs`).
    mutating func value(at position: inout Int, remainingDepth: Int, isTaggedAlready: Bool) throws(YAMLLoadError)
        -> YAMLValue
    {
        let event = try next(at: &position)
        switch event {
        case .alias(let id):
            return try expand(alias: id, remainingDepth: remainingDepth)
        case .scalar(let scalar):
            guard !isTaggedAlready, let localTag = Self.localTag(scalar.tag) else {
                return try Self.value(of: scalar, isTaggedAlready: isTaggedAlready)
            }
            return try tagged(localTag, at: &position, remainingDepth: remainingDepth)
        case .sequenceStart(let tag):
            guard !isTaggedAlready, let localTag = Self.localTag(tag) else {
                return .sequence(try sequence(at: &position, remainingDepth: remainingDepth))
            }
            return try tagged(localTag, at: &position, remainingDepth: remainingDepth)
        case .mappingStart(let tag):
            guard !isTaggedAlready, let localTag = Self.localTag(tag) else {
                return .mapping(try mapping(at: &position, remainingDepth: remainingDepth))
            }
            return try tagged(localTag, at: &position, remainingDepth: remainingDepth)
        case .void:
            return .null
        case .sequenceEnd, .mappingEnd:
            throw .endOfStream
        }
    }

    /// The event at `position`, which then points after it.
    private func next(at position: inout Int) throws(YAMLLoadError) -> YAMLEvent {
        guard position < document.events.count else { throw .endOfStream }
        defer { position += 1 }
        return document.events[position]
    }

    /// The value of the node of an anchor: `jump` in `de.rs`.
    private mutating func expand(alias id: Int, remainingDepth: Int) throws(YAMLLoadError) -> YAMLValue {
        jumpCount += 1
        guard jumpCount <= document.events.count * YAMLLoader.repetitionFactor else {
            throw .repetitionLimitExceeded
        }
        guard var target = document.aliasTargets[id] else { throw .unknownAnchor }
        return try value(at: &target, remainingDepth: remainingDepth, isTaggedAlready: false)
    }

    /// The tagged value of the node whose first event is just before
    /// `position`: `visit_enum` of the `Value` visitor reads the same event
    /// again as the content of the tag.
    private mutating func tagged(_ tag: String, at position: inout Int, remainingDepth: Int) throws(YAMLLoadError)
        -> YAMLValue
    {
        position -= 1
        let content = try value(at: &position, remainingDepth: remainingDepth, isTaggedAlready: true)
        return .tagged(tag: tag, value: content)
    }

    /// The elements of a sequence whose start is just before `position`:
    /// `visit_sequence` and `end_sequence` in `de.rs`.
    private mutating func sequence(at position: inout Int, remainingDepth: Int) throws(YAMLLoadError) -> [YAMLValue] {
        guard remainingDepth > 0 else { throw .recursionLimitExceeded }
        var elements: [YAMLValue] = []
        while try !isContainerEnd(at: position) {
            elements.append(try value(at: &position, remainingDepth: remainingDepth - 1, isTaggedAlready: false))
        }
        position += 1
        return elements
    }

    /// The entries of a mapping whose start is just before `position`:
    /// `visit_mapping` in `de.rs` and the `Mapping` visitor of `mapping.rs`,
    /// which refuses a repeated key.
    private mutating func mapping(at position: inout Int, remainingDepth: Int) throws(YAMLLoadError) -> YAMLMapping {
        guard remainingDepth > 0 else { throw .recursionLimitExceeded }
        var entries: [YAMLMapping.Entry] = []
        var keys: Set<YAMLValue> = []
        while try !isContainerEnd(at: position) {
            let key = try value(at: &position, remainingDepth: remainingDepth - 1, isTaggedAlready: false)
            guard keys.insert(key).inserted else { throw .duplicateKey }
            let entryValue = try value(at: &position, remainingDepth: remainingDepth - 1, isTaggedAlready: false)
            entries.append(YAMLMapping.Entry(key: key, value: entryValue))
        }
        position += 1
        return YAMLMapping(entries: entries)
    }

    /// Whether the event at `position` ends a sequence or a mapping.
    private func isContainerEnd(at position: Int) throws(YAMLLoadError) -> Bool {
        guard position < document.events.count else { throw .endOfStream }
        switch document.events[position] {
        case .sequenceEnd, .mappingEnd, .void:
            return true
        default:
            return false
        }
    }

    /// The tag of a node as a local tag, or `nil`: `parse_tag` in `de.rs`. A
    /// tag that starts with `!` loses that `!`, unless it is only `!`.
    private static func localTag(_ tag: String?) -> String? {
        guard let tag, tag.utf8.first == UInt8(ascii: "!") else { return nil }
        return YAMLValue.withoutBang(tag)
    }

    /// The value of a scalar: `visit_scalar` in `de.rs`.
    private static func value(of scalar: YAMLScalarEvent, isTaggedAlready: Bool) throws(YAMLLoadError) -> YAMLValue {
        guard let tag = scalar.tag, !isTaggedAlready else { return try untaggedValue(of: scalar) }
        return try value(of: scalar.value, coreTag: tag)
    }

    /// The value of a scalar with no tag, or with a tag that a tagged value
    /// above it already holds: a quoted scalar is a text, and a plain scalar
    /// is read with ``YAMLScalarReading``.
    private static func untaggedValue(of scalar: YAMLScalarEvent) throws(YAMLLoadError) -> YAMLValue {
        let text = scalar.value
        guard scalar.isPlain else { return .string(text) }
        return try value(ofUntagged: YAMLScalarReading(text), text: text)
    }

    /// The value of a scalar with a tag that is not local: a core tag asks
    /// for its type, and each other tag gives a text.
    private static func value(of text: String, coreTag tag: String) throws(YAMLLoadError) -> YAMLValue {
        switch tag {
        case boolTag:
            guard let value = YAMLScalarRules.bool(text) else { throw .invalidScalar }
            return .bool(value)
        case integerTag:
            guard let reading = YAMLScalarRules.integer(text) else { throw .invalidScalar }
            return try value(ofUntagged: reading, text: text)
        case floatTag:
            guard let value = YAMLScalarRules.float(text) else { throw .invalidScalar }
            return .number(.float(value))
        case nullTag:
            guard YAMLScalarRules.isNull(text) else { throw .invalidScalar }
            return .null
        default:
            return .string(text)
        }
    }

    /// The value of a reading of a plain scalar: the `Value` visitor, which
    /// refuses an integer wider than 64 bits.
    private static func value(ofUntagged reading: YAMLScalarReading, text: String) throws(YAMLLoadError) -> YAMLValue {
        switch reading {
        case .null:
            return .null
        case .bool(let value):
            return .bool(value)
        case .unsigned(let value):
            return .number(.positive(value))
        case .negative(let value):
            return .number(.negative(value))
        case .wideInteger:
            throw .invalidScalar
        case .float(let value):
            return .number(.float(value))
        case .string:
            return .string(text)
        }
    }
}
