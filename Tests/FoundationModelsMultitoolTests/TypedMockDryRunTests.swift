import Testing

@testable import FoundationModelsMultitool

/// Coverage for `TypedMockDryRun` — the gate that runs a candidate snippet
/// against typed mocks of the matched catalog and reports the first failure
/// its API usage produces.
///
/// The suite is deliberately lopsided toward the **false-failure** direction.
/// A bogus failure is worse than no check at all: it feeds a wrong error back
/// into the generation session, which then "repairs" correct code into broken
/// code. So every ordinary JavaScript idiom a correct snippet uses on a mocked
/// value gets its own passing test, and each of those tests fails the moment
/// the mock or its `Proxy` trips on something legal.
@Suite("TypedMockDryRun")
struct TypedMockDryRunTests {
    /// The catalog every case runs against: two standalone tools, one grouped
    /// tool, a tool with an optional enum-constrained argument, and a tool
    /// whose argument object is `getCities`'s own result shape.
    static func surface() throws -> APISurface {
        try MultiTool.Builder()
            .addTool(CitiesTool())
            .addTool(TempTool())
            .addTool(ForecastTool())
            .addTool(SummarizeTripTool())
            .addGroup(named: "github", [IssueCountTool()])
            .build()
    }

    /// Runs `snippet` against the shared catalog's typed mocks.
    ///
    /// - Parameter snippet: the JavaScript to dry-run.
    /// - Returns: the first failure message, or `nil` when the snippet ran
    ///   clean.
    static func failure(for snippet: String) throws -> String? {
        failure(for: snippet, against: try surface().entries)
    }

    /// Runs `snippet` against the typed mocks of `entries`, under the
    /// interpreter's stock time limit.
    ///
    /// - Parameters:
    ///   - snippet: the JavaScript to dry-run.
    ///   - entries: the catalog entries to mock.
    /// - Returns: the first failure message, or `nil` when the snippet ran
    ///   clean.
    static func failure(for snippet: String, against entries: [APISurface.Entry]) -> String? {
        TypedMockDryRun.apiUsageFailure(in: snippet, against: entries, using: JSCInterpreter())
    }

    /// Two typed entries: `notes.addNote`, whose result is a parsed JSON
    /// value, and `store`, whose one argument is a parsed JSON value.
    static func jsonEntries() throws -> [APISurface.Entry] {
        let addNote = try ToolAPIRenderer.render(
            name: "addNote",
            description: "Adds a note.",
            arguments: [
                ToolAPIRenderer.RenderedParameter(
                    name: "title", shape: .string(choices: []), isRequired: true, description: "the note title."
                ),
            ],
            returns: .json
        )
        let store = try ToolAPIRenderer.render(
            name: "store",
            description: "Stores a value.",
            arguments: [
                ToolAPIRenderer.RenderedParameter(
                    name: "payload", shape: .json, isRequired: true, description: "the value to store."
                ),
            ]
        )
        return [
            APISurface.Entry(path: "notes.addNote", group: "notes", descriptor: addNote),
            APISurface.Entry(path: "store", group: nil, descriptor: store),
        ]
    }

    /// The verb entries of the notes fixture
    /// (`Fixtures/OperationToolFixtures.swift`). Each verb returns a parsed
    /// JSON value, and `listNote` returns a JSON array.
    static func notesEntries() throws -> [APISurface.Entry] {
        try MultiTool.Builder()
            .addTool(NotesOperationTool())
            .build()
            .entries
    }

    // MARK: - False failures: idioms a correct snippet uses, which must pass clean

    @Test("a chained call passing one tool's returned field as the next tool's argument passes clean")
    func chainedCallThroughAReturnedFieldPassesClean() throws {
        let failure = try Self.failure(
            for: """
            const trip = await tools.getCities({});
            const temp = await tools.getTemperature({ city: trip.cities[0] });
            return temp.tempC;
            """
        )
        #expect(failure == nil)
    }

    @Test("passing a whole mocked result where its own declared shape is the parameter passes clean")
    func mockPassedWhereItsOwnDeclaredShapeIsExpectedPassesClean() throws {
        let failure = try Self.failure(
            for: """
            const trip = await tools.getCities({});
            return await tools.summarizeTrip({ trip: trip });
            """
        )
        #expect(failure == nil)
    }

    @Test("awaiting several calls through Promise.all passes clean")
    func promiseAllOverSeveralCallsPassesClean() throws {
        let failure = try Self.failure(
            for: """
            const both = await Promise.all([tools.getCities({}), tools.getCities({})]);
            return both[0].cities.length + both[1].cities.length;
            """
        )
        #expect(failure == nil)
    }

    @Test("interpolating a mocked scalar into a template literal passes clean")
    func templateLiteralInterpolationPassesClean() throws {
        let failure = try Self.failure(
            for: """
            const trip = await tools.getCities({});
            return `first ${trip.cities[0]} of ${trip.cities.length}`;
            """
        )
        #expect(failure == nil)
    }

    @Test("destructuring and spreading a mocked array passes clean")
    func arrayDestructuringAndSpreadPassClean() throws {
        let failure = try Self.failure(
            for: """
            const trip = await tools.getCities({});
            const [first] = trip.cities;
            const copy = [...trip.cities];
            let seen = 0;
            for (const city of trip.cities) { seen += city.length; }
            return { first: first, count: copy.length, seen: seen };
            """
        )
        #expect(failure == nil)
    }

    @Test("JSON.stringify of a mocked object passes clean")
    func jsonStringifyOfAMockedObjectPassesClean() throws {
        let failure = try Self.failure(
            for: """
            const trip = await tools.getCities({});
            return JSON.stringify(trip);
            """
        )
        #expect(failure == nil)
    }

    @Test("the mock's own type tag is hidden: a mocked object enumerates only its declared fields")
    func mockTypeTagIsNotEnumerable() throws {
        // The snippet throws when the tag leaks into `Object.keys`, so a `nil`
        // failure here is the assertion that it stays hidden — a leaked tag
        // would also corrupt every `JSON.stringify` and object spread.
        let failure = try Self.failure(
            for: """
            const trip = await tools.getCities({});
            const keys = Object.keys(trip);
            if (keys.length !== 1 || keys[0] !== "cities") {
              throw new Error("unexpected keys: " + keys.join(","));
            }
            return keys.length;
            """
        )
        #expect(failure == nil)
    }

    @Test("length, map, and filter on a mocked array pass clean")
    func arrayProtocolMembersPassClean() throws {
        let failure = try Self.failure(
            for: """
            const trip = await tools.getCities({});
            const upper = trip.cities.map(function (city) { return city.toUpperCase(); });
            const kept = trip.cities.filter(function (city) { return city.length >= 0; });
            return upper.length + kept.length + trip.cities.length;
            """
        )
        #expect(failure == nil)
    }

    @Test("an argument object carrying extra properties beyond the declared ones passes clean")
    func extraArgumentPropertiesPassClean() throws {
        let failure = try Self.failure(
            for: """
            const temp = await tools.getTemperature({ city: "PDX", note: "ignored", depth: { more: 1 } });
            return temp.tempC;
            """
        )
        #expect(failure == nil)
    }

    @Test("omitting an optional declared argument passes clean, and supplying it passes clean")
    func optionalArgumentIsOptionalBothWays() throws {
        #expect(try Self.failure(for: "return (await tools.getForecast({ city: \"PDX\" })).summary;") == nil)
        #expect(
            try Self.failure(for: "return (await tools.getForecast({ city: \"PDX\", days: \"7\" })).summary;") == nil
        )
    }

    @Test("reading an optional declared field on a result passes clean")
    func readingAnOptionalDeclaredResultFieldPassesClean() throws {
        let failure = try Self.failure(
            for: """
            const forecast = await tools.getForecast({ city: "PDX" });
            return { summary: forecast.summary, advisory: forecast.advisory };
            """
        )
        #expect(failure == nil)
    }

    @Test("a grouped tools.<group>.<name> path is mocked under its qualified path")
    func groupedPathIsMocked() throws {
        let failure = try Self.failure(
            for: """
            const issues = await tools.github.getIssueCount({ repo: "swift" });
            return issues.count;
            """
        )
        #expect(failure == nil)
    }

    // MARK: - True failures: each with the specific message fed back

    @Test("an unknown tools.* path fails")
    func unknownPathFails() throws {
        let failure = try #require(try Self.failure(for: "return await tools.getItinerary({});"))
        #expect(failure.contains("getItinerary"))
    }

    @Test("passing more than one argument fails, naming the arity")
    func wrongArityFails() throws {
        let failure = try #require(
            try Self.failure(for: "return await tools.getTemperature({ city: \"PDX\" }, \"extra\");")
        )
        #expect(failure.contains("exactly one arguments object"))
        #expect(failure.contains("tools.getTemperature"))
    }

    @Test("passing a bare string where an arguments object is declared fails")
    func nonObjectArgumentFails() throws {
        let failure = try #require(try Self.failure(for: "return await tools.getTemperature(\"PDX\");"))
        #expect(failure.contains("tools.getTemperature"))
        #expect(failure.contains("{ city: string }"))
        #expect(failure.contains("string"))
    }

    @Test("omitting a required argument field fails, naming the field")
    func missingRequiredArgumentFieldFails() throws {
        let failure = try #require(try Self.failure(for: "return await tools.getTemperature({});"))
        #expect(failure.contains("missing the required field \"city\""))
    }

    @Test("passing the wrong type for a declared argument field fails, naming the field and the declared type")
    func wrongArgumentFieldTypeFails() throws {
        let failure = try #require(try Self.failure(for: "return await tools.getTemperature({ city: 7 });"))
        #expect(failure.contains("city"))
        #expect(failure.contains("must be string"))
        #expect(failure.contains("received number"))
    }

    @Test("passing a mocked object where a string field is declared fails")
    func mockPassedWhereAScalarIsDeclaredFails() throws {
        let failure = try #require(
            try Self.failure(
                for: """
                const trip = await tools.getCities({});
                return await tools.getTemperature({ city: trip });
                """
            )
        )
        #expect(failure.contains("must be string"))
    }

    @Test("reading a field the declared result type does not have fails, naming the declared type")
    func undeclaredResultFieldReadFails() throws {
        let failure = try #require(
            try Self.failure(
                for: """
                const trip = await tools.getCities({});
                return trip.itinerary;
                """
            )
        )
        #expect(failure.contains("itinerary"))
        #expect(failure.contains("{ cities: string[] }"))
    }

    @Test("treating an object result as the array it contains fails — the recorded getTrip/cities mistake")
    func treatingAnObjectResultAsAnArrayFails() throws {
        let failure = try #require(
            try Self.failure(
                for: """
                const trip = await tools.getCities({});
                return trip.map(function (city) { return city; });
                """
            )
        )
        #expect(failure.contains("map"))
        #expect(failure.contains("{ cities: string[] }"))
    }

    @Test("reading a property off a call that was never awaited fails, asking for await")
    func forgottenAwaitFails() throws {
        let failure = try #require(
            try Self.failure(
                for: """
                const trip = tools.getCities({});
                return trip.cities;
                """
            )
        )
        #expect(failure.contains("await"))
        #expect(failure.contains("tools.getCities"))
    }

    @Test("passing the wrong element type inside a declared array argument fails")
    func wrongArrayElementTypeFails() throws {
        let failure = try #require(try Self.failure(for: "return await tools.summarizeTrip({ trip: { cities: [7] } });"))
        #expect(failure.contains("must be string"))
    }

    @Test("a snippet that cannot finish against instant mocks fails rather than passing")
    func nonTerminatingSnippetFails() throws {
        let failure = try #require(
            TypedMockDryRun.apiUsageFailure(
                in: "while (true) {}",
                against: try Self.surface().entries,
                using: JSCInterpreter(timeLimit: 0.5)
            )
        )
        #expect(failure.contains("time limit"))
    }

    // MARK: - Parsed JSON values, which carry no declared structure

    @Test("reading a field of a parsed JSON result passes clean")
    func jsonResultFieldReadPassesClean() throws {
        let failure = try Self.failure(
            for: """
            const n = await tools.notes.addNote({ title: "x" });
            return n.id;
            """,
            against: Self.jsonEntries()
        )
        #expect(failure == nil)
    }

    @Test("filtering a parsed JSON result as an array, and reading its length, passes clean")
    func jsonResultFiltersAsAnArray() throws {
        let failure = try Self.failure(
            for: """
            const notes = await tools.notes.listNote({});
            return notes.filter((n) => n.id).length;
            """,
            against: Self.notesEntries()
        )
        #expect(failure == nil)
    }

    @Test("iterating a parsed JSON result with for...of, and passing a field of each element to a verb, passes clean")
    func jsonResultIteratesAsAnArray() throws {
        let failure = try Self.failure(
            for: """
            const notes = await tools.notes.listNote({});
            for (const note of notes) { await tools.notes.tagNote({ id: note.id, tag: "due" }); }
            """,
            against: Self.notesEntries()
        )
        #expect(failure == nil)
    }

    @Test("calling a string method on a field of a parsed JSON element passes clean")
    func jsonElementFieldMethodCallPassesClean() throws {
        let failure = try Self.failure(
            for: """
            const notes = await tools.notes.listNote({});
            const hits = notes.filter((note) => note.body.includes("Friday"));
            return hits.map((note) => note.title.toUpperCase());
            """,
            against: Self.notesEntries()
        )
        #expect(failure == nil)
    }

    @Test("passing an object where a parsed JSON argument is declared passes clean")
    func jsonArgumentAcceptsAnObject() throws {
        let failure = try Self.failure(
            for: "return await tools.store({ payload: { a: 1 } });",
            against: Self.jsonEntries()
        )
        #expect(failure == nil)
    }

    @Test("passing a string where a parsed JSON argument is declared fails, naming the declared type")
    func jsonArgumentRejectsAScalar() throws {
        let failure = try #require(
            try Self.failure(for: "return await tools.store({ payload: \"x\" });", against: Self.jsonEntries())
        )
        #expect(failure.contains("must be object"))
    }
}
