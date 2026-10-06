import Foundation
import Testing

@testable import FoundationModelsMultitool

/// Tests for ``CodeEntityExtractor`` — the port of
/// `parser/plugins/code/entity_extractor.rs` in
/// `../swissarmyhammer/crates/swissarmyhammer-sem/src/`.
///
/// The extractor reads a ``CodeSyntaxNode``, thus these tests give it trees
/// that ``FakeSyntaxTree`` builds by hand. Each tree has the shape that the
/// grammar of the named language gives. This covers each branch of the Rust
/// walk, also the branches for the languages whose grammar is not in the
/// package yet (TypeScript, Python, C, C++, Elixir). The golden suite
/// (`CodeParserPluginGoldenTests`) covers the real grammars.
@Suite("CodeEntityExtractorTests")
struct CodeEntityExtractorTests {

    /// The file path of each tree.
    private static let filePath = "f.x"

    /// The entities of the tree of `shape`.
    private static func entities(_ shape: FakeSyntaxShape, _ vocabulary: EntityVocabulary) -> [SemanticEntity] {
        let tree = FakeSyntaxTree.build(shape)
        return CodeEntityExtractor.extractEntities(
            root: tree.root, source: tree.source, filePath: filePath, vocabulary: vocabulary)
    }

    /// Each entity as `type name`, with ` in <parent id>` for a nested one.
    private static func summary(_ entities: [SemanticEntity]) -> [String] {
        entities.map { entity in
            "\(entity.entityType) \(entity.name)" + (entity.parentID.map { " in \($0)" } ?? "")
        }
    }

    /// A vocabulary with entity kinds and container kinds only.
    private static func vocabulary(_ entityKinds: Set<String>, containers: Set<String> = []) -> EntityVocabulary {
        EntityVocabulary(entityNodeTypes: entityKinds, containerNodeTypes: containers, callEntityIdentifiers: [])
    }

    /// A leaf with the field `name`.
    private static func name(_ text: String, kind: String = "identifier") -> FakeSyntaxShape {
        .leaf(kind: kind, text: text, field: "name")
    }

    /// A leaf that the grammar does not name, such as a keyword.
    private static func keyword(_ text: String) -> FakeSyntaxShape {
        .leaf(kind: text, text: text, isNamed: false)
    }

    /// The source file of each tree, with `children` at the top level.
    private static func file(_ children: FakeSyntaxShape...) -> FakeSyntaxShape {
        .node(kind: "source_file", children: children)
    }

    // MARK: Declarations

    /// A declaration with a `name` field is one entity, with the id, the
    /// hashes, and the lines of the Rust `record`.
    @Test("a declaration with a name field is one entity")
    func aDeclarationWithANameFieldIsOneEntity() throws {
        let tree = FakeSyntaxTree.build(
            Self.file(.node(kind: "function_item", children: [Self.keyword("fn"), Self.name("run")])))
        let functionNode = try #require(tree.root.children.first)

        let entities = CodeEntityExtractor.extractEntities(
            root: tree.root, source: tree.source, filePath: Self.filePath,
            vocabulary: Self.vocabulary(["function_item"]))

        let entity = try #require(entities.first)
        #expect(entities.count == 1)
        #expect(entity.id == "f.x::function::run")
        #expect(entity.entityType == "function")
        #expect(entity.name == "run")
        #expect(entity.parentID == nil)
        #expect(entity.content == "fn run")
        #expect(entity.contentHash == SemanticHash.contentHash("fn run"))
        #expect(entity.structuralHash == SemanticHash.structuralHash(of: functionNode, source: tree.source))
        #expect(entity.startLine == 1)
        #expect(entity.endLine == 1)
        #expect(entity.metadata == nil)
    }

    /// The semantic model names each grammar kind of `map_node_type`, and a
    /// kind that is not in the table keeps its own name.
    @Test(
        "the entity type is the mapped name of the kind",
        arguments: [
            ("function_declaration", "function"), ("method_definition", "method"), ("class_specifier", "class"),
            ("interface_declaration", "interface"), ("type_item", "type"), ("enum_item", "enum"),
            ("struct_item", "struct"), ("union_specifier", "union"), ("impl_item", "impl"),
            ("trait_item", "trait"), ("mod_item", "module"), ("var_declaration", "variable"),
            ("const_item", "constant"), ("static_item", "static"), ("constructor_declaration", "constructor"),
            ("field_declaration", "field"), ("property_declaration", "property"),
            ("annotation_type_declaration", "annotation"), ("protocol_declaration", "protocol_declaration"),
        ])
    func theEntityTypeIsTheMappedNameOfTheKind(kind: String, entityType: String) {
        let entities = Self.entities(
            Self.file(.node(kind: kind, children: [Self.name("thing")])), Self.vocabulary([kind]))

        #expect(Self.summary(entities) == ["\(entityType) thing"])
    }

    /// An entity inside a container child of an entity is recorded after its
    /// parent, with the id of the parent.
    @Test("an entity in a container is recorded under its parent")
    func anEntityInAContainerIsRecordedUnderItsParent() {
        let method = FakeSyntaxShape.node(kind: "method_definition", children: [Self.name("area")])
        let body = FakeSyntaxShape.node(kind: "class_body", children: [method])
        let shape = Self.file(
            .node(kind: "class_declaration", children: [Self.name("Shape", kind: "type_identifier"), body]))

        let entities = Self.entities(
            shape, Self.vocabulary(["class_declaration", "method_definition"], containers: ["class_body"]))

        #expect(Self.summary(entities) == ["class Shape", "method area in f.x::class::Shape"])
        #expect(entities.last?.id == "f.x::f.x::class::Shape::area")
    }

    /// The walk below an entity reads only its container children, as in
    /// Rust: a declaration in a body that is not a container is not an
    /// entity.
    @Test("an entity outside a container of its parent is not read")
    func anEntityOutsideAContainerIsNotRead() {
        let inner = FakeSyntaxShape.node(kind: "function_item", children: [Self.name("inner")])
        let outer = FakeSyntaxShape.node(
            kind: "function_item", children: [Self.name("outer"), .node(kind: "block", children: [inner])])

        let entities = Self.entities(Self.file(outer), Self.vocabulary(["function_item"]))

        #expect(Self.summary(entities) == ["function outer"])
    }

    /// A declaration that names nothing is not an entity, and the walk goes
    /// on into its children with the same parent.
    @Test("a declaration that names nothing passes its children on")
    func aDeclarationThatNamesNothingPassesItsChildrenOn() {
        let inner = FakeSyntaxShape.node(kind: "function_item", children: [Self.name("inner")])
        let wrapper = FakeSyntaxShape.node(kind: "wrapper_item", children: [.node(kind: "block", children: [inner])])

        let entities = Self.entities(Self.file(wrapper), Self.vocabulary(["wrapper_item", "function_item"]))

        #expect(Self.summary(entities) == ["function inner"])
    }

    /// A kind with no `name` field takes the first identifier among its
    /// named children.
    @Test("a declaration with no name field takes its first identifier")
    func aDeclarationWithNoNameFieldTakesItsFirstIdentifier() {
        let alias = FakeSyntaxShape.node(
            kind: "alias_item", children: [Self.keyword("type"), .leaf(kind: "type_identifier", text: "Meters")])

        let entities = Self.entities(Self.file(alias), Self.vocabulary(["alias_item"]))

        #expect(Self.summary(entities) == ["alias_item Meters"])
    }

    // MARK: Wrappers and other name spellings

    /// An export statement is followed to the declaration it exports, as in
    /// TypeScript.
    @Test("an export statement records the declaration it exports")
    func anExportStatementRecordsTheDeclarationItExports() {
        let function = FakeSyntaxShape.node(
            kind: "function_declaration", children: [Self.name("greet")], field: "declaration")
        let export = FakeSyntaxShape.node(kind: "export_statement", children: [Self.keyword("export"), function])

        let entities = Self.entities(
            Self.file(export), Self.vocabulary(["export_statement", "function_declaration"]))

        #expect(Self.summary(entities) == ["function greet"])
    }

    /// A `let` or `const` declaration takes the name of its first variable
    /// declarator, as in TypeScript.
    @Test("a lexical declaration takes the name of its declarator")
    func aLexicalDeclarationTakesTheNameOfItsDeclarator() {
        let value = FakeSyntaxShape.leaf(kind: "number", text: "10", field: "value")
        let declarator = FakeSyntaxShape.node(kind: "variable_declarator", children: [Self.name("limit"), value])
        let declaration = FakeSyntaxShape.node(
            kind: "lexical_declaration", children: [Self.keyword("const"), declarator])

        let entities = Self.entities(Self.file(declaration), Self.vocabulary(["lexical_declaration"]))

        #expect(Self.summary(entities) == ["variable limit"])
    }

    /// A Python decorated definition takes the name and the type of the
    /// definition below its decorators.
    @Test(
        "a decorated definition takes the name and the type of its definition",
        arguments: [("class_definition", "class"), ("function_definition", "function")])
    func aDecoratedDefinitionTakesTheNameAndTypeOfItsDefinition(innerKind: String, entityType: String) {
        let decorator = FakeSyntaxShape.node(kind: "decorator", children: [.leaf(kind: "identifier", text: "cached")])
        let definition = FakeSyntaxShape.node(kind: innerKind, children: [Self.name("Point")], field: "definition")
        let decorated = FakeSyntaxShape.node(kind: "decorated_definition", children: [decorator, definition])

        let entities = Self.entities(
            Self.file(decorated),
            Self.vocabulary(["decorated_definition", "class_definition", "function_definition"]))

        #expect(Self.summary(entities) == ["\(entityType) Point"])
    }

    /// A C declaration takes its name from the end of its declarator chain.
    @Test("a C declaration takes its name from its declarator chain")
    func aCDeclarationTakesItsNameFromItsDeclaratorChain() {
        let identifier = FakeSyntaxShape.leaf(kind: "identifier", text: "make", field: "declarator")
        let function = FakeSyntaxShape.node(
            kind: "function_declarator",
            children: [identifier, .node(kind: "parameter_list", children: [])], field: "declarator")
        let pointer = FakeSyntaxShape.node(kind: "pointer_declarator", children: [function], field: "declarator")
        let returnType = FakeSyntaxShape.leaf(kind: "primitive_type", text: "int", field: "type")
        let definition = FakeSyntaxShape.node(kind: "function_definition", children: [returnType, pointer])

        let entities = Self.entities(Self.file(definition), Self.vocabulary(["function_definition"]))

        #expect(Self.summary(entities) == ["function make"])
    }

    /// A C++ qualified name is the whole name, with its scope.
    @Test("a qualified declarator name keeps its scope")
    func aQualifiedDeclaratorNameKeepsItsScope() {
        let name = FakeSyntaxShape.leaf(kind: "qualified_identifier", text: "Shape::area", field: "declarator")
        let function = FakeSyntaxShape.node(kind: "function_declarator", children: [name], field: "declarator")
        let definition = FakeSyntaxShape.node(kind: "function_definition", children: [function])

        let entities = Self.entities(Self.file(definition), Self.vocabulary(["function_definition"]))

        #expect(Self.summary(entities) == ["function Shape::area"])
    }

    /// A C++ template takes the name of the declaration it stands above,
    /// not a name from its parameter list.
    @Test("a template takes the name of its declaration")
    func aTemplateTakesTheNameOfItsDeclaration() {
        let parameters = FakeSyntaxShape.node(
            kind: "template_parameter_list", children: [.leaf(kind: "type_identifier", text: "T")])
        let declaration = FakeSyntaxShape.node(
            kind: "class_specifier", children: [Self.name("Box", kind: "type_identifier")])
        let template = FakeSyntaxShape.node(kind: "template_declaration", children: [parameters, declaration])

        let entities = Self.entities(Self.file(template), Self.vocabulary(["template_declaration"]))

        #expect(Self.summary(entities) == ["template Box"])
    }

    // MARK: Declaring calls (Elixir)

    /// The Elixir vocabulary of these tests.
    private static let elixir = EntityVocabulary(
        entityNodeTypes: [], containerNodeTypes: ["do_block"],
        callEntityIdentifiers: ["defmodule", "def", "defimpl", "defstruct", "defguard"])

    /// A call with the target `target` and the arguments `arguments`, and a
    /// `do` block with `body` when `body` is not `nil`.
    private static func call(
        _ target: String, _ arguments: [FakeSyntaxShape], body: [FakeSyntaxShape]? = nil,
        field: String? = nil
    ) -> FakeSyntaxShape {
        let targetLeaf = FakeSyntaxShape.leaf(kind: "identifier", text: target, field: "target")
        let block = body.map { [FakeSyntaxShape.node(kind: "do_block", children: $0)] } ?? []
        return .node(
            kind: "call", children: [targetLeaf, .node(kind: "arguments", children: arguments)] + block, field: field)
    }

    /// A bare name in Elixir source.
    private static func identifier(_ text: String) -> FakeSyntaxShape {
        .leaf(kind: "identifier", text: text)
    }

    /// A module alias in Elixir source.
    private static func alias(_ text: String) -> FakeSyntaxShape {
        .leaf(kind: "alias", text: text)
    }

    /// The entities of the Elixir source that `calls` make.
    private static func elixirEntities(_ calls: FakeSyntaxShape...) -> [String] {
        summary(entities(.node(kind: "source", children: calls), elixir))
    }

    /// `defmodule` declares a module, and a `def` in its `do` block declares
    /// a function of that module.
    @Test("defmodule declares a module that holds its functions")
    func defmoduleDeclaresAModuleThatHoldsItsFunctions() {
        let function = Self.call("def", [Self.call("create", [Self.identifier("attrs")])])
        let module = Self.call("defmodule", [Self.alias("MyApp.Accounts")], body: [function])

        #expect(
            Self.elixirEntities(module) == [
                "module MyApp.Accounts", "function create in f.x::module::MyApp.Accounts",
            ])
    }

    /// A `def` with no parameters names its function with a bare identifier.
    @Test("an arity-0 def takes its bare name")
    func anArityZeroDefTakesItsBareName() {
        #expect(Self.elixirEntities(Self.call("def", [Self.identifier("version")])) == ["function version"])
    }

    /// `defimpl` names the protocol and the `for:` target.
    @Test("defimpl names the protocol and its target")
    func defimplNamesTheProtocolAndItsTarget() {
        let key = FakeSyntaxShape.leaf(kind: "keyword", text: "for:", field: "key")
        let value = FakeSyntaxShape.leaf(kind: "alias", text: "User", field: "value")
        let keywords = FakeSyntaxShape.node(
            kind: "keywords", children: [.node(kind: "pair", children: [key, value])])

        let entities = Self.elixirEntities(Self.call("defimpl", [Self.alias("String.Chars"), keywords]))

        #expect(entities == ["impl String.Chars for User"])
    }

    /// `defstruct` declares the struct of its module, with a fixed name.
    @Test("defstruct declares the struct of its module")
    func defstructDeclaresTheStructOfItsModule() {
        let entities = Self.elixirEntities(Self.call("defstruct", [.node(kind: "list", children: [])]))

        #expect(entities == ["struct __struct__"])
    }

    /// `defguard` with a `when` clause takes the name on the left side.
    @Test("defguard takes the name on the left of its when clause")
    func defguardTakesTheNameOnTheLeftOfItsWhenClause() {
        let guardCall = Self.call("is_even", [Self.identifier("x")], field: "left")
        let condition = FakeSyntaxShape.leaf(kind: "boolean", text: "true", field: "right")
        let clause = FakeSyntaxShape.node(
            kind: "binary_operator", children: [guardCall, Self.keyword("when"), condition])

        #expect(Self.elixirEntities(Self.call("defguard", [clause])) == ["guard is_even"])
    }

    /// A call whose target is not a declaring keyword is not an entity.
    @Test("a call with another target is not an entity")
    func aCallWithAnotherTargetIsNotAnEntity() {
        #expect(Self.elixirEntities(Self.call("import", [Self.alias("Ecto.Query")])).isEmpty)
    }

    /// A language with no declaring keywords does not read a call as an
    /// entity, also when its target is `def`.
    @Test("a language with no declaring keywords reads no call")
    func aLanguageWithNoDeclaringKeywordsReadsNoCall() {
        let entities = Self.entities(
            .node(kind: "source", children: [Self.call("def", [Self.identifier("version")])]), Self.vocabulary([]))

        #expect(entities.isEmpty)
    }
}
