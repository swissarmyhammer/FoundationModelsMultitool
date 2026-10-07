import Foundation
import Testing

@testable import FoundationModelsMultitool

/// Tests for ``VueParserPlugin`` — the port of `parser/plugins/vue.rs` in
/// `../swissarmyhammer/crates/swissarmyhammer-sem/src/`.
///
/// The first three tests port the Rust tests `test_vue_sfc_extraction`,
/// `test_vue_script_setup`, and `test_vue_line_numbers`. The other tests
/// check the rules of `extract_sfc_blocks` and `parse_opening_tag` that the
/// golden suite (`CodeParserPluginGoldenTests`) does not name.
@Suite("VueParserPluginTests")
struct VueParserPluginTests {

    /// The entities that the Vue plugin reads from `content` at `filePath`.
    private static func entities(_ content: String, at filePath: String) -> [SemanticEntity] {
        VueParserPlugin().extractEntities(content: content, filePath: filePath)
    }

    /// The names of the block entities of `entities`, in source order.
    private static func blockNames(_ entities: [SemanticEntity]) -> [String] {
        entities.filter { $0.entityType == VueParserPlugin.blockEntityType }.map(\.name)
    }

    // MARK: Routing

    /// The default registry gives a `.vue` file to the Vue plugin, in any
    /// case, as `get_plugin` lowercases the extension.
    @Test("the default registry selects the Vue plugin for a vue file", arguments: ["src/App.vue", "SRC/APP.VUE"])
    func theDefaultRegistrySelectsTheVuePlugin(filePath: String) {
        #expect(ParserRegistry.makeDefault().plugin(forFilePath: filePath)?.id == VueParserPlugin.pluginID)
    }

    // MARK: Ported Rust tests

    /// The plugin gives one entity for each block, and the entities of the
    /// script block (`test_vue_sfc_extraction`).
    @Test("a single-file component gives its blocks and its script entities")
    func aSingleFileComponentGivesItsBlocksAndItsScriptEntities() {
        let source = """
            <template>
              <div class="app">
                <h1>{{ message }}</h1>
              </div>
            </template>

            <script lang="ts">
            import { defineComponent, ref } from 'vue'

            export default defineComponent({
              name: 'App',
              setup() {
                const message = ref('Hello')
                return { message }
              }
            })

            function helper(x: number): number {
              return x * 2
            }
            </script>

            <style scoped>
            .app {
              color: red;
            }
            </style>

            """

        let entities = Self.entities(source, at: "App.vue")

        #expect(Self.blockNames(entities) == ["template", "script", "style"])
        #expect(entities.contains { $0.name == "helper" })
    }

    /// A `<script setup>` block has the name `script setup`, and each entity
    /// of the block has the block as its parent (`test_vue_script_setup`).
    @Test("a script setup block is the parent of its entities")
    func aScriptSetupBlockIsTheParentOfItsEntities() throws {
        let source = """
            <script setup lang="ts">
            import { ref, computed } from 'vue'

            const count = ref(0)

            function increment() {
              count.value++
            }

            class Counter {
              value: number = 0
              increment() {
                this.value++
              }
            }
            </script>

            <template>
              <button @click="increment">{{ count }}</button>
            </template>

            """

        let entities = Self.entities(source, at: "Counter.vue")

        #expect(Self.blockNames(entities) == ["script setup", "template"])
        #expect(entities.contains { $0.name == "Counter" })
        let increment = try #require(entities.first { $0.name == "increment" })
        #expect(increment.parentID == "Counter.vue::sfc_block::script setup")
    }

    /// The lines of a block are its lines in the file, and the lines of a
    /// script entity are moved to the file too (`test_vue_line_numbers`).
    @Test("the lines of each entity are its lines in the file")
    func theLinesOfEachEntityAreItsLinesInTheFile() throws {
        let source =
            "<template>\n  <div>hi</div>\n</template>\n\n<script lang=\"ts\">\nfunction hello() {\n  return 'hello'\n}\n</script>\n"

        let entities = Self.entities(source, at: "test.vue")

        let template = try #require(entities.first { $0.name == "template" })
        #expect(template.startLine == 1)
        #expect(template.endLine == 3)
        let script = try #require(entities.first { $0.name == "script" })
        #expect(script.startLine == 5)
        #expect(script.endLine == 9)
        let hello = try #require(entities.first { $0.name == "hello" })
        #expect(hello.startLine == 6)
        #expect(hello.endLine == 8)
    }

    // MARK: Blocks

    /// A block entity holds the lines of the block, its content hash, and no
    /// structural hash: the plugin parses no tree for a block.
    @Test("a block entity holds the text of the block")
    func aBlockEntityHoldsTheTextOfTheBlock() throws {
        let block = "<template>\n  <div>hi</div>\n</template>"

        let entity = try #require(Self.entities(block + "\n", at: "view.vue").first)

        #expect(entity.id == "view.vue::sfc_block::template")
        #expect(entity.entityType == VueParserPlugin.blockEntityType)
        #expect(entity.parentID == nil)
        #expect(entity.content == block)
        #expect(entity.contentHash == SemanticHash.contentHash(block))
        #expect(entity.structuralHash == nil)
    }

    /// A block with no closing tag runs to the last line of the file.
    @Test("a block with no closing tag runs to the end of the file")
    func aBlockWithNoClosingTagRunsToTheEndOfTheFile() throws {
        let entity = try #require(Self.entities("<template>\n  <div/>\n", at: "open.vue").first)

        #expect(entity.content == "<template>\n  <div/>")
        #expect(entity.startLine == 1)
        #expect(entity.endLine == 2)
    }

    /// The plugin cuts the lines as the Rust `str::lines` does: a carriage
    /// return before a line feed is not part of the line.
    @Test("a carriage return at the end of a line is not part of the block")
    func aCarriageReturnAtTheEndOfALineIsNotPartOfTheBlock() throws {
        let entity = try #require(Self.entities("<template>\r\n  <div/>\r\n</template>\r\n", at: "crlf.vue").first)

        #expect(entity.content == "<template>\n  <div/>\n</template>")
        #expect(entity.endLine == 3)
    }

    /// An opening tag can have indentation before it.
    @Test("an indented opening tag starts a block")
    func anIndentedOpeningTagStartsABlock() {
        #expect(Self.blockNames(Self.entities("  <style>\n  </style>\n", at: "indent.vue")) == ["style"])
    }

    /// A tag whose name only starts with a block name is not a block.
    @Test("a tag that only starts with a block name is not a block")
    func aTagThatOnlyStartsWithABlockNameIsNotABlock() {
        #expect(Self.entities("<scripts>\n</scripts>\n<templates/>\n", at: "other.vue").isEmpty)
    }

    /// The second plain script block has the name `script:2`. A
    /// `<script setup>` block counts as a script block too.
    @Test("a second script block has the name script:2")
    func aSecondScriptBlockHasTheNameScript2() {
        let source = "<script setup>\nconst a = 1\n</script>\n<script>\nconst b = 2\n</script>\n"

        #expect(Self.blockNames(Self.entities(source, at: "two.vue")) == ["script setup", "script:2"])
    }

    // MARK: Script entities

    /// An empty script block gives the block entity only.
    @Test("an empty script block gives the block entity only")
    func anEmptyScriptBlockGivesTheBlockEntityOnly() {
        #expect(Self.entities("<script>\n</script>\n", at: "empty.vue").map(\.name) == ["script"])
    }

    /// A method of a class in a script block has the block as its parent,
    /// not the class: the Rust plugin sets the parent of each script entity.
    @Test("a method of a class in a script block has the block as its parent")
    func aMethodOfAClassInAScriptBlockHasTheBlockAsItsParent() throws {
        let source = "<script>\nclass Counter {\n  increment() {\n    this.value++\n  }\n}\n</script>\n"

        let entities = Self.entities(source, at: "C.vue")

        let method = try #require(entities.first { $0.name == "increment" })
        #expect(method.parentID == "C.vue::sfc_block::script")
        #expect(method.id == "C.vue::C.vue::sfc_block::script::increment")
        #expect(method.filePath == "C.vue")
    }

    /// A script block with `lang='ts'` (in single quotes) goes to the
    /// TypeScript grammar, thus an interface is an entity.
    @Test("a script block with lang ts goes to the TypeScript grammar")
    func aScriptBlockWithLangTsGoesToTheTypeScriptGrammar() {
        let source = "<script lang='ts'>\ninterface Shape {\n  area(): number;\n}\n</script>\n"

        let entities = Self.entities(source, at: "shape.vue")

        #expect(entities.contains { $0.entityType == "interface" && $0.name == "Shape" })
    }

    /// A script block with no `lang` goes to the JavaScript grammar, which has
    /// no interface, thus the block is the one entity.
    @Test("a script block with no lang goes to the JavaScript grammar")
    func aScriptBlockWithNoLangGoesToTheJavaScriptGrammar() {
        let source = "<script>\ninterface Shape {\n  area(): number;\n}\n</script>\n"

        #expect(Self.entities(source, at: "shape.vue").map(\.name) == ["script"])
    }
}
