// `YAMLEmitter` — writes a ``YAMLValue`` as YAML text the way
// `serde_yaml_ng::to_string` writes a `Value`.
//
// A port of serde_yaml_ng 0.10.0: the `Serializer` of `ser.rs` (its state
// machine for tags, the scalar style of each text, and the document events),
// the `Serialize` of `Value` (`value/ser.rs`) and of `TaggedValue`
// (`value/tagged.rs`), and the emitter wrapper of `libyaml/emitter.rs`
// (unicode on, line width -1). The events go to the libyaml 0.2.5 C emitter
// of the `CYaml` module of Yams, the same libyaml that serde_yaml_ng runs
// through unsafe-libyaml, thus the text is the same byte for byte.
//
// One difference between the two emitters: unsafe-libyaml 0.2.11 reads a
// scalar above U+FFFF (for example an emoji) as printable, and the C libyaml
// does not. ``YAMLWideScalarMask`` replaces each such scalar with a private
// use scalar before libyaml reads it, and puts it back in the text after.
//
// The YAML plugin hashes this text for each key whose value is a mapping or a
// sequence. When serde_yaml_ng fails (a value with two tags, or an event that
// libyaml refuses), the Rust plugin hashes an empty text; ``text(of:)``
// returns `nil` for the same values.

import CYaml

/// The YAML writer of the YAML plugin: `to_string` of serde_yaml_ng.
enum YAMLEmitter {

    /// The YAML text of `value`, or `nil` where `to_string` fails.
    ///
    /// - Parameter value: The value to write.
    /// - Returns: The text, with the newline at its end.
    static func text(of value: YAMLValue) -> String? {
        guard let emitter = LibYAMLEmitter() else { return nil }
        let mask = YAMLWideScalarMask(value)
        var serializer = YAMLSerializer(emitter: emitter, mask: mask)
        do throws(YAMLEmitError) {
            try emitter.emit(.streamStart)
            try serializer.serialize(value)
            try emitter.emit(.streamEnd)
            try emitter.flush()
        } catch {
            return nil
        }
        return mask.unmasked(String(decoding: emitter.output.bytes, as: UTF8.self))
    }
}

/// Replaces each scalar above U+FFFF in the scalar texts with a private use
/// scalar (U+E000 and up) that the value does not hold, and back.
///
/// The C libyaml of Yams reads a scalar above U+FFFF as not printable: it
/// writes the text double quoted with a `\U` escape. unsafe-libyaml, which
/// serde_yaml_ng runs, reads it as printable and writes it as it is. A private
/// use scalar is printable for both emitters, and it is not a space, a line
/// break, or an indicator, thus libyaml selects the same style and writes the
/// same text around it.
private struct YAMLWideScalarMask {

    /// The first scalar above the Basic Multilingual Plane.
    private static let firstWideScalar: UInt32 = 0x10000

    /// The private use scalars of the Basic Multilingual Plane.
    private static let privateUseScalars: ClosedRange<UInt32> = 0xE000...0xF8FF

    /// The private use scalar of each wide scalar.
    private let masks: [Unicode.Scalar: Unicode.Scalar]

    /// The wide scalar of each private use scalar.
    private let originals: [Unicode.Scalar: Unicode.Scalar]

    /// A mask for the texts of `value`. A wide scalar gets no mask when no
    /// free private use scalar is left.
    ///
    /// - Parameter value: The value to write.
    init(_ value: YAMLValue) {
        var used: Set<Unicode.Scalar> = []
        Self.collectScalars(of: value, into: &used)
        let wide = used.filter { $0.value >= Self.firstWideScalar }.sorted { $0.value < $1.value }
        let free = Self.privateUseScalars.lazy.compactMap(Unicode.Scalar.init(_:)).filter { !used.contains($0) }
        let pairs = Array(zip(wide, free))
        masks = Dictionary(uniqueKeysWithValues: pairs)
        originals = Dictionary(uniqueKeysWithValues: pairs.map { ($1, $0) })
    }

    /// `text` with each wide scalar replaced by its mask.
    func masked(_ text: String) -> String {
        guard !masks.isEmpty else { return text }
        return Self.replacing(text, with: masks)
    }

    /// `text` with each mask replaced by its wide scalar.
    func unmasked(_ text: String) -> String {
        guard !originals.isEmpty else { return text }
        return Self.replacing(text, with: originals)
    }

    /// `text` with each scalar that `replacements` holds replaced.
    private static func replacing(_ text: String, with replacements: [Unicode.Scalar: Unicode.Scalar]) -> String {
        String(String.UnicodeScalarView(text.unicodeScalars.map { replacements[$0] ?? $0 }))
    }

    /// Adds each scalar of the texts and tags of `value` to `scalars`.
    private static func collectScalars(of value: YAMLValue, into scalars: inout Set<Unicode.Scalar>) {
        switch value {
        case .null, .bool, .number:
            break
        case .string(let text):
            scalars.formUnion(text.unicodeScalars)
        case .sequence(let elements):
            for element in elements {
                collectScalars(of: element, into: &scalars)
            }
        case .mapping(let mapping):
            for entry in mapping.entries {
                collectScalars(of: entry.key, into: &scalars)
                collectScalars(of: entry.value, into: &scalars)
            }
        case .tagged(let tag, let content):
            scalars.formUnion(tag.unicodeScalars)
            collectScalars(of: content, into: &scalars)
        }
    }
}

/// The failure of a write: an error of libyaml, or a value with two tags
/// (`SerializeNestedEnum` in serde_yaml_ng).
private enum YAMLEmitError: Error {

    /// libyaml refused an event.
    case emitter

    /// A tagged value holds another tagged value.
    case nestedTag
}

/// The scalar styles that serde_yaml_ng asks libyaml for: `ScalarStyle` in
/// `libyaml/emitter.rs`.
private enum YAMLScalarStyle {

    /// libyaml selects the style.
    case any

    /// No quote marks.
    case plain

    /// Single quote marks.
    case singleQuoted

    /// A literal block.
    case literal

    /// The libyaml style of this style.
    var libYAMLStyle: yaml_scalar_style_t {
        switch self {
        case .any:
            return YAML_ANY_SCALAR_STYLE
        case .plain:
            return YAML_PLAIN_SCALAR_STYLE
        case .singleQuoted:
            return YAML_SINGLE_QUOTED_SCALAR_STYLE
        case .literal:
            return YAML_LITERAL_SCALAR_STYLE
        }
    }

    /// The style of a text: `serialize_str` in `ser.rs`. A text with a
    /// newline is a literal block. A text that would read back as another
    /// type (null, a boolean, a number) or as a number with a leading zero
    /// is single quoted. Each other text lets libyaml select.
    init(of text: String) {
        if text.utf8.contains(UInt8(ascii: "\n")) {
            self = .literal
            return
        }
        switch YAMLScalarReading(text) {
        case .string:
            self = YAMLScalarRules.isDigitsButNotNumber(text) ? .singleQuoted : .any
        default:
            self = .singleQuoted
        }
    }
}

/// One emitter event: `Event` in `libyaml/emitter.rs`.
private enum YAMLEmitterEvent {

    /// The start of the stream.
    case streamStart

    /// The end of the stream.
    case streamEnd

    /// The implicit start of a document.
    case documentStart

    /// The implicit end of a document.
    case documentEnd

    /// A scalar with its tag, text, and style.
    case scalar(tag: String?, value: String, style: YAMLScalarStyle)

    /// The start of a sequence with its tag.
    case sequenceStart(tag: String?)

    /// The end of a sequence.
    case sequenceEnd

    /// The start of a mapping with its tag.
    case mappingStart(tag: String?)

    /// The end of a mapping.
    case mappingEnd
}

/// The bytes that libyaml writes.
private final class YAMLOutput {

    /// The bytes so far.
    var bytes: [UInt8] = []
}

/// A libyaml emitter with the settings of `Emitter::new` in
/// `libyaml/emitter.rs`: unicode output and no line width limit.
private final class LibYAMLEmitter {

    /// The line width that means no limit.
    private static let unlimitedWidth: Int32 = -1

    /// The libyaml emitter, at a stable address.
    private let emitter = UnsafeMutablePointer<yaml_emitter_t>.allocate(capacity: 1)

    /// The text that the emitter writes.
    let output = YAMLOutput()

    /// A new emitter, or `nil` when libyaml cannot create one.
    init?() {
        emitter.initialize(to: yaml_emitter_t())
        guard yaml_emitter_initialize(emitter) == 1 else {
            emitter.deallocate()
            return nil
        }
        yaml_emitter_set_unicode(emitter, 1)
        yaml_emitter_set_width(emitter, Self.unlimitedWidth)
        yaml_emitter_set_output(
            emitter,
            { data, buffer, size in
                guard let data, let buffer else { return 0 }
                Unmanaged<YAMLOutput>.fromOpaque(data).takeUnretainedValue().bytes
                    .append(contentsOf: UnsafeBufferPointer(start: buffer, count: size))
                return 1
            }, Unmanaged.passUnretained(output).toOpaque())
    }

    deinit {
        yaml_emitter_delete(emitter)
        emitter.deallocate()
    }

    /// Writes one event.
    func emit(_ event: YAMLEmitterEvent) throws(YAMLEmitError) {
        var libYAMLEvent = yaml_event_t()
        guard Self.initialize(&libYAMLEvent, for: event) == 1, yaml_emitter_emit(emitter, &libYAMLEvent) == 1 else {
            throw .emitter
        }
    }

    /// Writes the bytes that libyaml still holds.
    func flush() throws(YAMLEmitError) {
        guard yaml_emitter_flush(emitter) == 1 else { throw .emitter }
    }

    /// Fills `libYAMLEvent` with `event`: the event constructors in
    /// `Emitter::emit` of `libyaml/emitter.rs`. A node with no tag is
    /// implicit; a node with a tag writes it.
    private static func initialize(_ libYAMLEvent: inout yaml_event_t, for event: YAMLEmitterEvent) -> Int32 {
        switch event {
        case .streamStart:
            return yaml_stream_start_event_initialize(&libYAMLEvent, YAML_UTF8_ENCODING)
        case .streamEnd:
            return yaml_stream_end_event_initialize(&libYAMLEvent)
        case .documentStart:
            return yaml_document_start_event_initialize(&libYAMLEvent, nil, nil, nil, 1)
        case .documentEnd:
            return yaml_document_end_event_initialize(&libYAMLEvent, 1)
        case .scalar(let tag, let value, let style):
            return withCString(tag) { tagPointer in
                var bytes = Array(value.utf8) + [0]
                return bytes.withUnsafeMutableBufferPointer { valuePointer in
                    yaml_scalar_event_initialize(
                        &libYAMLEvent, nil, tagPointer, valuePointer.baseAddress, Int32(valuePointer.count - 1),
                        tag == nil ? 1 : 0, tag == nil ? 1 : 0, style.libYAMLStyle)
                }
            }
        case .sequenceStart(let tag):
            return withCString(tag) {
                yaml_sequence_start_event_initialize(&libYAMLEvent, nil, $0, tag == nil ? 1 : 0, YAML_ANY_SEQUENCE_STYLE)
            }
        case .sequenceEnd:
            return yaml_sequence_end_event_initialize(&libYAMLEvent)
        case .mappingStart(let tag):
            return withCString(tag) {
                yaml_mapping_start_event_initialize(&libYAMLEvent, nil, $0, tag == nil ? 1 : 0, YAML_ANY_MAPPING_STYLE)
            }
        case .mappingEnd:
            return yaml_mapping_end_event_initialize(&libYAMLEvent)
        }
    }

    /// Calls `body` with a C string of `text`, or with a null pointer.
    private static func withCString(
        _ text: String?, _ body: (UnsafeMutablePointer<yaml_char_t>?) -> Int32
    ) -> Int32 {
        guard let text else { return body(nil) }
        var bytes = Array(text.utf8) + [0]
        return bytes.withUnsafeMutableBufferPointer { body($0.baseAddress) }
    }
}

/// The serializer of `ser.rs`: it turns a value into emitter events, and it
/// turns the one-entry map that serde writes for a tagged value into a tag on
/// the next node.
private struct YAMLSerializer {

    /// The state of the tag test: `State` in `ser.rs`.
    private enum State: Equatable {

        /// No test is open.
        case nothingInParticular

        /// A map of one entry started: its key can be a tag.
        case checkForTag

        /// A map of one entry started under a found tag: a second tag fails.
        case checkForDuplicateTag

        /// The tag of the next node.
        case foundTag(String)

        /// The tag of the map is written; the map writes no end.
        case alreadyTagged
    }

    /// The emitter of the events.
    private let emitter: LibYAMLEmitter

    /// The mask of the wide scalars of each scalar text. A tag is not
    /// masked: libyaml escapes each byte of a tag that is not ASCII.
    private let mask: YAMLWideScalarMask

    /// The count of open nodes: `depth` in `ser.rs`. A document starts and
    /// ends at depth 0.
    private var depth = 0

    /// The state of the tag test.
    private var state = State.nothingInParticular

    /// A serializer that writes to `emitter`, with `mask` on each scalar text.
    init(emitter: LibYAMLEmitter, mask: YAMLWideScalarMask) {
        self.emitter = emitter
        self.mask = mask
    }

    /// Writes `value`: the `Serialize` of `Value` in `value/ser.rs`.
    mutating func serialize(_ value: YAMLValue) throws(YAMLEmitError) {
        switch value {
        case .null:
            try emitScalar("null", style: .plain)
        case .bool(let flag):
            try emitScalar(flag ? "true" : "false", style: .plain)
        case .number(let number):
            try emitScalar(number.text, style: .plain)
        case .string(let text):
            try emitScalar(text, style: YAMLScalarStyle(of: text))
        case .sequence(let elements):
            try emitSequenceStart()
            for element in elements {
                try serialize(element)
            }
            try emitter.emit(.sequenceEnd)
            try valueEnd()
        case .mapping(let mapping):
            try startMap(entryCount: mapping.entries.count)
            for entry in mapping.entries {
                try serializeEntry(key: entry.key, value: entry.value)
            }
            try endMap()
        case .tagged(let tag, let content):
            try startMap(entryCount: 1)
            try collectTag(tag)
            let isTagged = isFoundTag
            try serialize(content)
            if isTagged {
                state = .alreadyTagged
            }
            try endMap()
        }
    }

    /// Whether the state holds a found tag.
    private var isFoundTag: Bool {
        if case .foundTag = state {
            return true
        }
        return false
    }

    /// One entry of a map: `SerializeMap::serialize_entry` in `ser.rs`.
    private mutating func serializeEntry(key: YAMLValue, value: YAMLValue) throws(YAMLEmitError) {
        try serialize(key)
        let isTagged = isFoundTag
        try serialize(value)
        if isTagged {
            state = .alreadyTagged
        }
    }

    /// `serialize_map` in `ser.rs`: a map of one entry waits for its key,
    /// which can be a tag.
    private mutating func startMap(entryCount: Int) throws(YAMLEmitError) {
        guard entryCount == 1 else {
            try emitMappingStart()
            return
        }
        if isFoundTag {
            try emitMappingStart()
            state = .checkForDuplicateTag
        } else {
            state = .checkForTag
        }
    }

    /// `SerializeMap::end` in `ser.rs`.
    private mutating func endMap() throws(YAMLEmitError) {
        if state == .checkForTag {
            try emitMappingStart()
        }
        if state != .alreadyTagged {
            try emitter.emit(.mappingEnd)
            try valueEnd()
        }
        state = .nothingInParticular
    }

    /// The key of a tagged value: `collect_str` in `ser.rs` with the `Display`
    /// of `Tag` (`!` and the tag), which `check_for_tag` reads as a tag.
    private mutating func collectTag(_ tag: String) throws(YAMLEmitError) {
        switch state {
        case .checkForDuplicateTag:
            throw .nestedTag
        case .checkForTag:
            state = .foundTag(YAMLValue.withoutBang(tag))
        default:
            try emitScalar(YAMLValue.tagText(tag), style: YAMLScalarStyle(of: YAMLValue.tagText(tag)))
        }
    }

    /// `emit_scalar` in `ser.rs`.
    private mutating func emitScalar(_ value: String, style: YAMLScalarStyle) throws(YAMLEmitError) {
        try flushMappingStart()
        let tag = takeTag()
        try valueStart()
        try emitter.emit(.scalar(tag: tag, value: mask.masked(value), style: style))
        try valueEnd()
    }

    /// `emit_sequence_start` in `ser.rs`.
    private mutating func emitSequenceStart() throws(YAMLEmitError) {
        try flushMappingStart()
        try valueStart()
        try emitter.emit(.sequenceStart(tag: takeTag()))
    }

    /// `emit_mapping_start` in `ser.rs`.
    private mutating func emitMappingStart() throws(YAMLEmitError) {
        try flushMappingStart()
        try valueStart()
        try emitter.emit(.mappingStart(tag: takeTag()))
    }

    /// `flush_mapping_start` in `ser.rs`: a map of one entry whose key is
    /// not a tag starts now.
    private mutating func flushMappingStart() throws(YAMLEmitError) {
        switch state {
        case .checkForTag:
            state = .nothingInParticular
            try emitMappingStart()
        case .checkForDuplicateTag:
            state = .nothingInParticular
        default:
            break
        }
    }

    /// `take_tag` in `ser.rs`: the found tag with a leading `!`, which the
    /// state then drops.
    private mutating func takeTag() -> String? {
        guard case .foundTag(let tag) = state else { return nil }
        state = .nothingInParticular
        return tag.utf8.first == UInt8(ascii: "!") ? tag : "!" + tag
    }

    /// `value_start` in `ser.rs`.
    private mutating func valueStart() throws(YAMLEmitError) {
        if depth == 0 {
            try emitter.emit(.documentStart)
        }
        depth += 1
    }

    /// `value_end` in `ser.rs`.
    private mutating func valueEnd() throws(YAMLEmitError) {
        depth -= 1
        if depth == 0 {
            try emitter.emit(.documentEnd)
        }
    }
}
