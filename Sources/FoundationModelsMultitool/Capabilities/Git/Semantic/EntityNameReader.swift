import Foundation

// `EntityNameReader` and `DeclaringCallReader` — read the name that a
// declaration gives itself, in each spelling that a grammar uses.
//
// A port of the name readers of `parser/plugins/code/entity_extractor.rs` in
// `../swissarmyhammer/crates/swissarmyhammer-sem/src/`: `extract_name`,
// `declared_name`, the readers for a variable declarator, a Python decorated
// definition, a C++ template, and a C declarator, `map_decorated_type`,
// `node_text`, and the Elixir readers (`extract_call_entity` and the
// functions it calls). ``CodeEntityExtractor`` calls them.
//
// The language tasks of git.md add a table entry and a grammar only. Thus
// each reader of the Rust file is here, also the readers for a language
// whose grammar is not in the package yet.

/// The name readers of `entity_extractor.rs` for a declaration node.
enum EntityNameReader {

    /// The field that a grammar gives the identifier of a declaration
    /// (`NAME_FIELD`).
    static let nameField = "name"

    /// The field of the thing that a C-family declaration declares, which
    /// holds the name when the declaration has no ``nameField``
    /// (`DECLARATOR_FIELD`).
    static let declaratorField = "declarator"

    /// The node kind of a bare name (`IDENTIFIER_KIND`).
    static let identifierKind = "identifier"

    /// The node kind that Python gives a `def` or `class` with decorators
    /// (`DECORATED_DEFINITION_KIND`).
    static let decoratedDefinitionKind = "decorated_definition"

    /// The node kinds of a bare name, in value position or in type position
    /// (`is_identifier`).
    private static let identifierKinds: Set = [identifierKind, "type_identifier"]

    /// The node kinds that declare a variable through `variable_declarator`
    /// children: JavaScript and TypeScript `let`, `const`, and `var`
    /// (`VARIABLE_DECLARATION_KINDS`).
    private static let variableDeclarationKinds: Set = ["lexical_declaration", "variable_declaration"]

    /// The node kind of one declarator of a `let`, `const`, or `var`.
    private static let variableDeclaratorKind = "variable_declarator"

    /// The node kinds whose name is in their ``declaratorField``: the C
    /// family (`DECLARATOR_NAMED_KINDS`).
    private static let declaratorNamedKinds: Set = ["function_definition", "declaration", "type_definition"]

    /// The node kinds below a Python decorated definition
    /// (`DECORATED_INNER_KINDS`).
    private static let decoratedInnerKinds: Set = ["function_definition", "class_definition"]

    /// The node kind of a C++ template, which names the declaration below
    /// its parameter list.
    private static let templateDeclarationKind = "template_declaration"

    /// The node kind of the parameter list of a C++ template.
    private static let templateParameterListKind = "template_parameter_list"

    /// The declarator kinds whose text is the name: a bare name, a field
    /// name, and a C++ qualified name such as `Shape::area`.
    private static let namedDeclaratorKinds: Set = [
        identifierKind, "type_identifier", "field_identifier", "qualified_identifier", "scoped_identifier",
    ]

    /// The declarator kinds that wrap another declarator: a pointer, a
    /// function, an array, and parentheses.
    private static let wrappingDeclaratorKinds: Set = [
        "pointer_declarator", "function_declarator", "array_declarator", "parenthesized_declarator",
    ]

    /// The entity type of each definition kind below a Python decorator
    /// (`map_decorated_type`).
    private static let decoratedTypeByKind: [String: String] = [
        "class_definition": "class", "function_definition": "function",
    ]

    /// The entity type of a decorated definition with no known definition
    /// below it.
    private static let defaultDecoratedType = "function"

    /// The name that the declaration `node` gives itself, or `nil` when it
    /// names nothing: `extract_name` in Rust.
    ///
    /// The ``nameField`` answers for each grammar that has one. Else the
    /// reader for the kind of `node` answers, and else the first identifier
    /// among the named children.
    static func name<Node: CodeSyntaxNode>(of node: Node, source: [UInt8]) -> String? {
        guard let nameNode = node.child(byFieldName: nameField) else {
            return declaredName(of: node, source: source) ?? firstIdentifierName(of: node, source: source)
        }
        return text(of: nameNode, source: source)
    }

    /// The entity type of a Python decorated definition: the type of the
    /// definition below its decorators (`map_decorated_type`).
    static func decoratedType<Node: CodeSyntaxNode>(of node: Node) -> String {
        node.namedChildren.lazy.compactMap { decoratedTypeByKind[$0.kind] }.first ?? defaultDecoratedType
    }

    /// The text of `node`, or an empty text when its bytes are not valid
    /// UTF-8: `node_text` in Rust, which reads `Node::utf8_text`. The empty
    /// text is the contract of the Rust reader, not a sentinel.
    ///
    /// `node` must be a node of the parse of `source`, thus its byte range
    /// is in `source`.
    static func text<Node: CodeSyntaxNode>(of node: Node, source: [UInt8]) -> String {
        String(validating: source[node.startByte..<node.endByte], as: UTF8.self) ?? ""
    }

    /// The first identifier among the named children of `node`, for a
    /// declaration whose grammar names it nowhere else
    /// (`first_identifier_name`).
    static func firstIdentifierName<Node: CodeSyntaxNode>(of node: Node, source: [UInt8]) -> String? {
        node.namedChildren.first { identifierKinds.contains($0.kind) }.map { text(of: $0, source: source) }
    }

    /// The name that a declaration spells in a place other than a
    /// ``nameField``, or `nil` when its kind spells it nowhere else
    /// (`declared_name`).
    private static func declaredName<Node: CodeSyntaxNode>(of node: Node, source: [UInt8]) -> String? {
        if variableDeclarationKinds.contains(node.kind) {
            return firstNamedChild(of: node, kinds: [variableDeclaratorKind], source: source)
        }
        if node.kind == decoratedDefinitionKind {
            return firstNamedChild(of: node, kinds: decoratedInnerKinds, source: source)
        }
        if declaratorNamedKinds.contains(node.kind) {
            return node.child(byFieldName: declaratorField).flatMap { declaratorName(of: $0, source: source) }
        }
        if node.kind == templateDeclarationKind {
            return templateDeclarationName(of: node, source: source)
        }
        return nil
    }

    /// The ``nameField`` text of the first named child of `node` whose kind
    /// is in `kinds` and that has a ``nameField``: the reader for a variable
    /// declarator (`variable_declarator_name`) and for the definition below
    /// a Python decorator (`decorated_definition_name`).
    private static func firstNamedChild<Node: CodeSyntaxNode>(
        of node: Node, kinds: Set<String>, source: [UInt8]
    ) -> String? {
        node.namedChildren.lazy
            .filter { kinds.contains($0.kind) }
            .compactMap { $0.child(byFieldName: nameField) }
            .first
            .map { text(of: $0, source: source) }
    }

    /// The name of the declaration that a C++ template stands above, which
    /// is a sibling of its parameter list (`template_declaration_name`).
    private static func templateDeclarationName<Node: CodeSyntaxNode>(
        of node: Node, source: [UInt8]
    ) -> String? {
        node.namedChildren.lazy
            .filter { $0.kind != templateParameterListKind }
            .compactMap { child -> String? in
                guard let nameNode = child.child(byFieldName: nameField) else {
                    let declarator = child.child(byFieldName: declaratorField)
                    return declarator.flatMap { declaratorName(of: $0, source: source) }
                }
                return text(of: nameNode, source: source)
            }
            .first
    }

    /// The name at the end of a C declarator chain, such as `make` in
    /// `int *make(void)` (`extract_declarator_name`).
    private static func declaratorName<Node: CodeSyntaxNode>(of node: Node, source: [UInt8]) -> String? {
        if namedDeclaratorKinds.contains(node.kind) {
            return text(of: node, source: source)
        }
        if wrappingDeclaratorKinds.contains(node.kind) {
            guard let inner = node.child(byFieldName: declaratorField) else {
                return firstIdentifierName(of: node, source: source)
            }
            return declaratorName(of: inner, source: source)
        }
        guard let nameNode = node.child(byFieldName: nameField) else {
            return firstIdentifierName(of: node, source: source)
        }
        return text(of: nameNode, source: source)
    }
}

/// The readers of `entity_extractor.rs` for a call that declares an entity,
/// such as Elixir `def` and `defmodule` (`extract_call_entity`).
enum DeclaringCallReader {

    /// The field of a call that holds its target.
    private static let targetField = "target"

    /// The node kind of the argument list of a call.
    private static let argumentsKind = "arguments"

    /// The entity type of each declaring keyword.
    private static let entityTypeByKeyword: [String: String] = [
        "defmodule": "module", "def": "function", "defp": "function", "defdelegate": "function",
        "defmacro": "macro", "defmacrop": "macro", "defguard": "guard", "defguardp": "guard",
        "defprotocol": "protocol", "defimpl": "impl", "defstruct": "struct", "defexception": "exception",
    ]

    /// The fixed name of the entity of each keyword that declares a part of
    /// its module and has no name of its own.
    private static let fixedNameByKeyword: [String: String] = [
        "defstruct": "__struct__", "defexception": "__exception__",
    ]

    /// The keywords whose first alias or identifier is the name.
    private static let aliasNamedKeywords: Set = ["defmodule", "defprotocol"]

    /// The keyword of a protocol implementation, whose name is the protocol
    /// and the `for:` target.
    private static let implementationKeyword = "defimpl"

    /// The keyword argument of `defimpl` that names the target.
    private static let implementationTargetKey = "for"

    /// The name and the entity type of the entity that the call `node`
    /// declares, or `nil` when it declares none (`extract_call_entity`).
    static func entity<Node: CodeSyntaxNode>(
        of node: Node, vocabulary: EntityVocabulary, source: [UInt8]
    ) -> (name: String, entityType: String)? {
        guard let target = node.child(byFieldName: targetField), target.kind == EntityNameReader.identifierKind
        else { return nil }
        let keyword = EntityNameReader.text(of: target, source: source)
        guard vocabulary.callEntityIdentifiers.contains(keyword),
            let entityType = entityTypeByKeyword[keyword],
            let arguments = node.namedChildren.first(where: { $0.kind == argumentsKind }),
            let name = name(declaredBy: keyword, arguments: arguments, source: source)
        else { return nil }
        return (name, entityType)
    }

    /// The name that the keyword `keyword` declares with the arguments
    /// `arguments`.
    private static func name<Node: CodeSyntaxNode>(
        declaredBy keyword: String, arguments: Node, source: [UInt8]
    ) -> String? {
        guard let fixedName = fixedNameByKeyword[keyword] else {
            return argumentName(declaredBy: keyword, arguments: arguments, source: source)
        }
        return fixedName
    }

    /// The name that the keyword `keyword`, which has no fixed name,
    /// declares with the arguments `arguments`.
    private static func argumentName<Node: CodeSyntaxNode>(
        declaredBy keyword: String, arguments: Node, source: [UInt8]
    ) -> String? {
        if aliasNamedKeywords.contains(keyword) {
            return firstAliasOrIdentifier(in: arguments, source: source)
        }
        if keyword == implementationKeyword {
            return implementationName(arguments: arguments, source: source)
        }
        return arguments.namedChildren.first.flatMap { functionName(fromArgument: $0, source: source) }
    }

    /// The name of a `defimpl`: the protocol, and ` for <target>` when the
    /// call has a `for:` keyword argument.
    private static func implementationName<Node: CodeSyntaxNode>(arguments: Node, source: [UInt8]) -> String? {
        guard let base = firstAliasOrIdentifier(in: arguments, source: source) else { return nil }
        guard let target = keywordValue(in: arguments, key: implementationTargetKey, source: source) else {
            return base
        }
        return "\(base) for \(target)"
    }

    /// The function name in the first argument of `def`, `defp`, `defmacro`,
    /// `defguard`, or `defdelegate` (`extract_fn_name_from_arg`): the target
    /// of a call with parameters, a bare identifier with no parameters, or
    /// the left side of a `when` clause.
    private static func functionName<Node: CodeSyntaxNode>(fromArgument node: Node, source: [UInt8]) -> String? {
        switch node.kind {
        case "call":
            guard let target = node.child(byFieldName: targetField) else {
                return node.namedChildren.first { $0.kind == EntityNameReader.identifierKind }
                    .map { EntityNameReader.text(of: $0, source: source) }
            }
            return EntityNameReader.text(of: target, source: source)
        case EntityNameReader.identifierKind:
            return EntityNameReader.text(of: node, source: source)
        case "binary_operator":
            return node.child(byFieldName: "left").flatMap { functionName(fromArgument: $0, source: source) }
        default:
            return nil
        }
    }

    /// The first module alias or bare name among the arguments of a call
    /// (`extract_first_alias_or_identifier`).
    private static func firstAliasOrIdentifier<Node: CodeSyntaxNode>(
        in arguments: Node, source: [UInt8]
    ) -> String? {
        arguments.namedChildren.first { $0.kind == "alias" || $0.kind == EntityNameReader.identifierKind }
            .map { EntityNameReader.text(of: $0, source: source) }
    }

    /// The value that the keyword list among `arguments` gives `key`, such
    /// as the `for:` of `defimpl Protocol, for: Target`
    /// (`extract_keyword_value`).
    private static func keywordValue<Node: CodeSyntaxNode>(
        in arguments: Node, key: String, source: [UInt8]
    ) -> String? {
        arguments.namedChildren.lazy
            .filter { $0.kind == "keywords" }
            .flatMap(\.namedChildren)
            .compactMap { pairValue(of: $0, key: key, source: source) }
            .first
    }

    /// The value of `pair` when it is the keyword pair for `key`, else `nil`
    /// (`pair_value_for_key`). The key text is `key:` or `key`, because a
    /// grammar can cut the key node with or without its colon.
    private static func pairValue<Node: CodeSyntaxNode>(of pair: Node, key: String, source: [UInt8]) -> String? {
        guard pair.kind == "pair", let keyNode = pair.child(byFieldName: "key") else { return nil }
        let keyText = EntityNameReader.text(of: keyNode, source: source)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard keyText == "\(key):" || keyText == key, let value = pair.child(byFieldName: "value") else {
            return nil
        }
        return EntityNameReader.text(of: value, source: source)
    }
}
