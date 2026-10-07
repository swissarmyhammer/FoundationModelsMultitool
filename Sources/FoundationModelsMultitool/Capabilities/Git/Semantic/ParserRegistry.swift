// `ParserRegistry` — selects the language plugin for each file of the
// semantic diff.
//
// A port of `parser/registry.rs` in
// `../swissarmyhammer/crates/swissarmyhammer-sem/src/`: the struct
// `ParserRegistry` and the function `get_extension`, and of
// `create_default_registry` in `parser/plugins/mod.rs`. The registry maps
// each extension to the plugin that registered it last. A file with no
// mapped extension gets the plugin whose id is `fallback`, when there is
// one.

/// The plugins of the semantic diff, by file extension:
/// `ParserRegistry` in `parser/registry.rs`.
struct ParserRegistry: Sendable {

    /// The id of the plugin for each file that no other plugin reads: the
    /// `"fallback"` of `get_plugin` in `parser/registry.rs`.
    static let fallbackPluginID = "fallback"

    /// The plugins, in the order of registration.
    private var plugins: [any SemanticParserPlugin] = []

    /// The index in ``plugins`` of the plugin for each extension:
    /// `extension_map` in Rust.
    private var pluginIndexByExtension: [String: Int] = [:]

    /// The registry of the semantic diff: `create_default_registry` in
    /// `parser/plugins/mod.rs`.
    ///
    /// The Rust registry has, in this order, the JSON, code, Vue, YAML,
    /// TOML, CSV, and Markdown plugins, and the fallback plugin last. The
    /// code and Vue plugins are the plugins that are ported now. Each task
    /// that ports another plugin registers it here, in the Rust order.
    ///
    /// - Returns: A registry with each ported plugin.
    static func makeDefault() -> ParserRegistry {
        var registry = ParserRegistry()
        registry.register(CodeParserPlugin())
        registry.register(VueParserPlugin())
        return registry
    }

    /// Adds `plugin` and maps each of its extensions to it: `register` in
    /// `parser/registry.rs`. A later plugin for the same extension
    /// replaces the earlier one in the map.
    ///
    /// - Parameter plugin: The plugin to add.
    mutating func register(_ plugin: any SemanticParserPlugin) {
        for fileExtension in plugin.extensions {
            pluginIndexByExtension[fileExtension] = plugins.count
        }
        plugins.append(plugin)
    }

    /// The plugin for `filePath`: `get_plugin` in `parser/registry.rs`.
    ///
    /// - Parameter filePath: The path of the file.
    /// - Returns: The plugin of the extension of the path, else the
    ///   fallback plugin, else `nil`.
    func plugin(forFilePath filePath: String) -> (any SemanticParserPlugin)? {
        if let index = pluginIndexByExtension[Self.fileExtension(of: filePath)] {
            return plugins[index]
        }
        return plugin(withID: Self.fallbackPluginID)
    }

    /// The first plugin with the id `id`: `get_plugin_by_id` in
    /// `parser/registry.rs`.
    ///
    /// - Parameter id: The id of the plugin.
    /// - Returns: The plugin, or `nil` when no plugin has the id.
    func plugin(withID id: String) -> (any SemanticParserPlugin)? {
        plugins.first { $0.id == id }
    }

    /// The extension of `filePath` in lowercase with a leading dot, or an
    /// empty text: `get_extension` in `parser/registry.rs`.
    ///
    /// The rules are those of the Rust `Path::extension`. The extension is
    /// the text after the last dot of the file name. A file name with no
    /// dot, or with only a leading dot (`.gitignore`), has no extension. A
    /// `.` component of the path is not a file name.
    ///
    /// The code plugin reads the language of a file with this function too.
    /// Its Rust source has a copy with the same rules
    /// (`dotted_lowercase_extension` in `parser/plugins/code/languages.rs`).
    static func fileExtension(of filePath: String) -> String {
        let fileName = filePath.split(separator: "/").last { $0 != "." }
        guard let fileName, fileName != "..",
            let dot = fileName.lastIndex(of: "."), dot != fileName.startIndex
        else { return "" }
        return "." + fileName[fileName.index(after: dot)...].lowercased()
    }
}
