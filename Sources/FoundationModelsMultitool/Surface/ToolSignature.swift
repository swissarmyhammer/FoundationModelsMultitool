/// The declared shape of one value in a rendered tool signature — an
/// argument, one of its properties, or what awaiting a call resolves to.
///
/// This is the structural half of what `ToolAPIRenderer` produces from a
/// tool's `@Generable` schema. The textual half — the `declare function`
/// signature the model reads — is rendered *from* this value, not alongside
/// it (see ``declaredType``), so a checker that reads the shape and a model
/// that reads the declaration are looking at one description of the tool
/// rather than two that could drift.
///
/// The cases are exactly the TypeScript types plan.md's type-mapping table
/// maps a schema onto, and ``any`` is the same widening the table calls for
/// when the schema holds something no precise type can express.
public indirect enum ToolValueShape: Sendable, Equatable {
    /// A string, constrained to `choices` when the schema carried an `enum`
    /// and unconstrained when `choices` is empty.
    case string(choices: [InterpreterValue])

    /// A number — the schema's `integer` and `number` both land here, since
    /// JavaScript has one numeric type.
    case number

    /// A boolean.
    case boolean

    /// An array of `element`.
    case array(element: ToolValueShape)

    /// An object with the given properties.
    case object(ToolObjectShape)

    /// A value the schema described in a way no precise TypeScript type
    /// expresses — a cyclic `$ref`, an `anyOf`, or an unrecognized `type` —
    /// declared as `any` and left unconstrained.
    case any

    /// This shape's TypeScript type, exactly as it appears in the rendered
    /// `declare function` signature.
    ///
    /// Delegates to `ToolAPIRenderer`, which owns every rule about splicing
    /// schema-derived text into generated TypeScript safely, so the escaping
    /// and the key-quoting are not restated here.
    public var declaredType: String {
        ToolAPIRenderer.declaredType(of: self)
    }
}

/// The declared shape of an object in a rendered tool signature — a tool's
/// whole `args` object, or any object nested inside a signature.
public struct ToolObjectShape: Sendable, Equatable {
    /// One declared property of an object shape.
    public struct Property: Sendable, Equatable {
        /// The property's name, exactly as the schema spelled it.
        public let name: String

        /// The property's own declared shape.
        public let shape: ToolValueShape

        /// Whether the schema lists this property as required.
        public let isRequired: Bool

        /// Creates a declared property.
        ///
        /// Explicit for the same reason as `ToolDescriptor.init`: a `public`
        /// struct's synthesized initializer is only `internal`-accessible,
        /// and this type is part of the `FoundationModelsMultitool` library
        /// product's surface.
        public init(name: String, shape: ToolValueShape, isRequired: Bool) {
            self.name = name
            self.shape = shape
            self.isRequired = isRequired
        }
    }

    /// Every declared property, in the schema's own declared order (`x-order`
    /// when present, alphabetical otherwise) — the same order the rendered
    /// object type and `@param` lines use.
    public let properties: [Property]

    /// Creates an object shape over the given properties.
    ///
    /// Explicit for the same reason as `Property.init` above: a `public`
    /// struct's synthesized initializer is only `internal`-accessible.
    public init(properties: [Property]) {
        self.properties = properties
    }

    /// This object's TypeScript type, exactly as it appears in the rendered
    /// `declare function` signature — `{}` when it declares no property.
    public var declaredType: String {
        ToolAPIRenderer.declaredType(ofObject: self)
    }

    /// Returns the declared property with the given name, or `nil` when this
    /// object declares no such property.
    public func property(named name: String) -> Property? {
        properties.first { $0.name == name }
    }
}

/// One tool's whole signature as structure rather than text: what a call
/// takes, and what awaiting it resolves to.
///
/// Carried on every ``ToolDescriptor``, so anything holding a rendered
/// catalog entry can check a call against the same schema the entry's
/// `declare function` line advertises.
public struct ToolSignature: Sendable, Equatable {
    /// The single `args` object every `tools.*` call takes — plan.md's
    /// "object (named) parameters, always".
    public let arguments: ToolObjectShape

    /// What awaiting the call resolves to. The declared return type is
    /// `Promise<…>` around this shape.
    public let result: ToolValueShape

    /// Creates a signature over an argument object and a result shape.
    ///
    /// Explicit for the same reason as `ToolObjectShape.init`: a `public`
    /// struct's synthesized initializer is only `internal`-accessible.
    public init(arguments: ToolObjectShape, result: ToolValueShape) {
        self.arguments = arguments
        self.result = result
    }
}
