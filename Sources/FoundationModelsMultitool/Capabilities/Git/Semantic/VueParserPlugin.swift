// `VueParserPlugin` — the plugin of the semantic diff for a Vue single-file
// component (a `.vue` file).
//
// A port of `parser/plugins/vue.rs` in
// `../swissarmyhammer/crates/swissarmyhammer-sem/src/`: the struct
// `VueParserPlugin`, `extract_sfc_blocks`, `parse_opening_tag`, and
// `extract_attr`. The plugin uses no tree-sitter grammar (git.md decision
// 11): it cuts the file into its `<template>`, `<script>`, and `<style>`
// blocks line by line, and it sends the text in each `<script>` block to the
// code plugin with the TypeScript or the JavaScript grammar.
//
// Each match of a tag name, an attribute name, the `setup` marker, and a
// `lang` value is case-sensitive, the same as `vue.rs`. Thus `</Template>`,
// `<STYLE>`, `LANG="ts"`, `SETUP`, and `lang="TS"` do not match.
//
// The Rust plugin uses the default `compute_similarity`, thus this plugin
// uses the default ``SemanticParserPlugin/similarity(between:and:)``.

/// The Vue plugin: `VueParserPlugin` in `parser/plugins/vue.rs`.
struct VueParserPlugin: SemanticParserPlugin {

    /// The id of the Vue plugin.
    static let pluginID = "vue"

    /// The entity type of each block of a component (`"sfc_block"` in Rust).
    static let blockEntityType = "sfc_block"

    var id: String { Self.pluginID }

    /// The extension of a Vue file.
    var extensions: [String] { [".vue"] }

    /// The entities of one file: `extract_entities` in `vue.rs`.
    ///
    /// Each block gives one entity, in source order. The entities of the code
    /// in a `<script>` block come after the entity of that block.
    func extractEntities(content: String, filePath: String) -> [SemanticEntity] {
        SingleFileComponentBlock.blocks(in: content).flatMap { block in
            let blockEntity = Self.entity(of: block, filePath: filePath)
            return [blockEntity] + Self.scriptEntities(of: block, blockID: blockEntity.id, filePath: filePath)
        }
    }

    /// The entity of one block. A block has no parse tree, thus it has no
    /// structural hash.
    private static func entity(of block: SingleFileComponentBlock, filePath: String) -> SemanticEntity {
        SemanticEntity(
            id: SemanticEntity.makeID(filePath: filePath, entityType: blockEntityType, name: block.name, parentID: nil),
            filePath: filePath, entityType: blockEntityType, name: block.name, parentID: nil,
            content: block.fullContent, contentHash: SemanticHash.contentHash(block.fullContent), structuralHash: nil,
            startLine: block.startLine, endLine: block.endLine, metadata: nil)
    }

    /// The entities of the code in a `<script>` block, or no entity for each
    /// other block and for an empty script block.
    ///
    /// The code plugin reads the text in the block at the path
    /// `<filePath>:script.ts` or `<filePath>:script.js`. Then each entity
    /// gets the path of the `.vue` file, the block as its parent (also a
    /// method of a class, as in Rust), the lines of the `.vue` file, and an id
    /// from these values.
    private static func scriptEntities(
        of block: SingleFileComponentBlock, blockID: String, filePath: String
    ) -> [SemanticEntity] {
        guard block.tag == .script, !block.innerContent.isEmpty else { return [] }
        let lineOffset = block.innerStartLine - 1
        let scriptPath = "\(filePath):\(block.scriptFileName)"
        return CodeParserPlugin().extractEntities(content: block.innerContent, filePath: scriptPath).map { child in
            SemanticEntity(
                id: SemanticEntity.makeID(
                    filePath: filePath, entityType: child.entityType, name: child.name, parentID: blockID),
                filePath: filePath, entityType: child.entityType, name: child.name, parentID: blockID,
                content: child.content, contentHash: child.contentHash, structuralHash: child.structuralHash,
                startLine: child.startLine + lineOffset, endLine: child.endLine + lineOffset,
                metadata: child.metadata)
        }
    }
}

/// The tag of a block of a single-file component. `parse_opening_tag` tries
/// the tags in this order.
private enum SingleFileComponentTag: String, CaseIterable {
    case template
    case script
    case style
}

/// One block of a single-file component: `SfcBlock` in `vue.rs`.
private struct SingleFileComponentBlock {

    /// The tag of the block.
    let tag: SingleFileComponentTag

    /// The name of the block: the tag, or `script setup`, or `script:<n>`
    /// for the second and each later script block.
    let name: String

    /// The value of the `lang` attribute of the opening tag, or an empty
    /// text.
    let language: String

    /// The lines of the block, from the opening tag to the closing tag.
    let fullContent: String

    /// The lines between the opening tag and the closing tag.
    let innerContent: String

    /// The 1-based line of the opening tag.
    let startLine: Int

    /// The 1-based line of the closing tag, or the last line of the file when
    /// the block has no closing tag.
    let endLine: Int

    /// The 1-based line after the opening tag.
    let innerStartLine: Int
}

extension SingleFileComponentBlock {

    /// The `lang` values that send a script block to the TypeScript grammar.
    private static let typeScriptLanguages: Set = ["ts", "tsx"]

    /// The name of the code file of a script block: `script.ts` for a
    /// TypeScript block, else `script.js`. The code plugin selects the
    /// grammar from its extension. The match of the `lang` value is
    /// case-sensitive, the same as `vue.rs`: `TS` gives `script.js`.
    var scriptFileName: String {
        Self.typeScriptLanguages.contains(language) ? "script.ts" : "script.js"
    }

    /// The blocks of a component, in source order: `extract_sfc_blocks` in
    /// `vue.rs`.
    ///
    /// The lines are the lines of the Rust `str::lines`. An opening tag
    /// starts a block, and the first later line that starts with the closing
    /// tag stops it. A block with no closing tag runs to the last line. The
    /// search for the next opening tag starts after the block. The matches of
    /// the opening tag and the closing tag are case-sensitive, the same as
    /// `vue.rs`.
    ///
    /// - Parameter content: The text of the file.
    /// - Returns: The blocks.
    static func blocks(in content: String) -> [SingleFileComponentBlock] {
        let lines = RustText.lines(of: content)
        let spans = Array(
            sequence(state: lines.startIndex) { position -> BlockSpan? in
                guard let span = BlockSpan.next(in: lines, from: position) else { return nil }
                position = span.endIndex
                return span
            })
        return spans.indices.map { index in
            let scriptOrdinal = spans[...index].count { $0.opening.tag == .script }
            return SingleFileComponentBlock(span: spans[index], scriptOrdinal: scriptOrdinal, lines: lines)
        }
    }

    /// The block of `span`.
    ///
    /// - Parameters:
    ///   - span: The opening tag and the lines of the block.
    ///   - scriptOrdinal: The count of script blocks up to this block, this
    ///     block included.
    ///   - lines: The lines of the file.
    private init(span: BlockSpan, scriptOrdinal: Int, lines: [String]) {
        let innerLines =
            span.innerStartIndex < span.closingIndex ? lines[span.innerStartIndex..<span.closingIndex] : []
        self.init(
            tag: span.opening.tag, name: Self.name(of: span.opening, scriptOrdinal: scriptOrdinal),
            language: span.opening.language,
            fullContent: lines[span.openingIndex..<span.endIndex].joined(separator: "\n"),
            innerContent: innerLines.joined(separator: "\n"),
            startLine: span.openingIndex + 1, endLine: span.endIndex, innerStartLine: span.innerStartIndex + 1)
    }

    /// The name of a block: the tag, `script setup` for a script block with
    /// `setup`, and `script:<n>` for the second and each later script block.
    private static func name(of opening: OpeningTag, scriptOrdinal: Int) -> String {
        guard opening.tag == .script else { return opening.tag.rawValue }
        if opening.isSetup {
            return "script setup"
        }
        return scriptOrdinal > 1 ? "script:\(scriptOrdinal)" : "script"
    }
}

/// The lines of one block before it has a name: one pass of the loop of
/// `extract_sfc_blocks` in `vue.rs`. Each value is an index into the lines of
/// the file.
private struct BlockSpan {

    /// The opening tag of the block.
    let opening: OpeningTag

    /// The line of the opening tag.
    let openingIndex: Int

    /// The line of the closing tag, or the count of lines when the block has
    /// no closing tag.
    let closingIndex: Int

    /// The count of lines of the file.
    let lineCount: Int

    /// The line after the opening tag.
    var innerStartIndex: Int { openingIndex + 1 }

    /// The line after the block: after the closing tag, or the count of lines.
    var endIndex: Int { closingIndex < lineCount ? closingIndex + 1 : lineCount }

    /// The first block at `position` or after it, or `nil` when no later line
    /// has an opening tag.
    ///
    /// The search for the closing tag is case-sensitive, the same as
    /// `vue.rs`: a line that starts with `</Template>` does not stop a
    /// `template` block.
    ///
    /// - Parameters:
    ///   - lines: The lines of the file.
    ///   - position: The first line to read.
    /// - Returns: The block.
    static func next(in lines: [String], from position: Int) -> BlockSpan? {
        let openings = lines.indices[position...].lazy.compactMap { index in
            OpeningTag(line: RustText.trimmed(lines[index])).map { (index: index, opening: $0) }
        }
        guard let found = openings.first else { return nil }
        let closingTag = "</\(found.opening.tag.rawValue)>".utf8
        let isClosing = { (index: Int) in RustText.trimmed(lines[index]).utf8.starts(with: closingTag) }
        let closingIndex = lines.indices[(found.index + 1)...].first(where: isClosing) ?? lines.count
        return BlockSpan(
            opening: found.opening, openingIndex: found.index, closingIndex: closingIndex, lineCount: lines.count)
    }
}

/// The opening tag of a block: `TagInfo` and `parse_opening_tag` in `vue.rs`.
private struct OpeningTag {

    /// The quote marks of an attribute value, in the order that
    /// `extract_attr` tries them.
    private static let attributeQuotes = [UInt8(ascii: "\""), UInt8(ascii: "'")]

    /// The text between the name of an attribute and its quoted value.
    private static let attributeAssignment = UInt8(ascii: "=")

    /// The name of the attribute that gives the language of a script block.
    private static let languageAttribute = "lang"

    /// The text that marks a `<script setup>` block, anywhere in the line. The
    /// match is case-sensitive, the same as `vue.rs`.
    private static let setupMarker = "setup"

    /// The characters that can follow the tag name in an opening tag. An
    /// empty rest is valid too.
    private static let tagNameTerminators = [UInt8(ascii: ">"), UInt8(ascii: " ")]

    /// The tag of the block.
    let tag: SingleFileComponentTag

    /// The value of the `lang` attribute, or an empty text.
    let language: String

    /// Whether the line has the text `setup`.
    let isSetup: Bool

    /// The opening tag on `line`, or `nil` when the line does not start with
    /// `<template`, `<script`, or `<style` and then `>`, a space, or nothing.
    ///
    /// - Parameter line: A line with no whitespace at its two ends.
    init?(line: String) {
        guard let tag = SingleFileComponentTag.allCases.first(where: { Self.isOpening($0, of: line) }) else {
            return nil
        }
        self.tag = tag
        language =
            Self.attributeQuotes.lazy.compactMap { Self.attribute(Self.languageAttribute, quotedBy: $0, in: line) }
            .first ?? ""
        isSetup = line.utf8.firstRange(of: Self.setupMarker.utf8) != nil
    }

    /// Whether `line` opens a block of `tag`: the line starts with `<` and
    /// the tag name, and then `>`, a space, or nothing. The match of the tag
    /// name is case-sensitive, the same as `vue.rs`: `<Template>` does not
    /// open a block.
    private static func isOpening(_ tag: SingleFileComponentTag, of line: String) -> Bool {
        let prefix = "<\(tag.rawValue)".utf8
        guard line.utf8.starts(with: prefix) else { return false }
        return line.utf8.dropFirst(prefix.count).first.map(tagNameTerminators.contains(_:)) ?? true
    }

    /// The value of `name="…"` (or `name='…'`) in `line`: one pass of
    /// `extract_attr` in `vue.rs`.
    ///
    /// The search for the attribute name is case-sensitive, the same as
    /// `vue.rs`: `LANG="ts"` is not the attribute `lang`.
    ///
    /// - Parameters:
    ///   - name: The name of the attribute.
    ///   - quote: The quote mark of the value.
    ///   - line: The line of the opening tag.
    /// - Returns: The text between the first `name=` and the next quote
    ///   mark, or `nil` when the line has no such text.
    private static func attribute(_ name: String, quotedBy quote: UInt8, in line: String) -> String? {
        let bytes = line.utf8
        guard let opening = bytes.firstRange(of: Array(name.utf8) + [attributeAssignment, quote]),
            let closing = bytes[opening.upperBound...].firstIndex(of: quote)
        else { return nil }
        return String(decoding: bytes[opening.upperBound..<closing], as: UTF8.self)
    }
}
