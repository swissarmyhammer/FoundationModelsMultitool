import Testing

/// The offline checks of ``DiscoveryAnswerCheck``: the rules every gated
/// discovery suite holds each answer to.
///
/// Each check gives a list of matched paths to the check, as a discovery
/// answer gives them. No check loads a model, and no check reads a catalog of
/// a real mount. Thus each check always runs, and a wrong rule fails here
/// before a live run can hide it behind a model that never answers that shape.
@Suite("DiscoveryAnswerCheck: an answer holds only real catalog paths, one time each, inside the limit")
struct DiscoveryAnswerCheckTests {

    /// The catalog of every check: three paths of the files-and-shell surface.
    private static let catalog = ["files.read", "files.write", "shell.execute"]

    /// The check of every test, with a limit of the size of the catalog — the
    /// limit `searchTools` takes when the host gives none.
    private static let check = DiscoveryAnswerCheck(catalog: catalog, limit: catalog.count)

    /// A path that the catalog does not define. It has the shape of a real
    /// path, so only the catalog lookup can find it.
    private static let pathOutsideTheCatalog = "files.delete"

    @Test("An answer that holds a path the catalog does not define fails the check")
    func aPathOutsideTheCatalogIsAFault() {
        let faults = Self.check.faults(in: ["files.read", Self.pathOutsideTheCatalog])
        #expect(faults == [.pathNotInCatalog(Self.pathOutsideTheCatalog)])
    }

    @Test("An answer that holds one path two times fails the check")
    func aRepeatedPathIsAFault() {
        let faults = Self.check.faults(in: ["files.read", "shell.execute", "files.read"])
        #expect(faults == [.repeatedPath("files.read")])
    }

    @Test("An answer with more paths than the limit fails the check")
    func anAnswerOverTheLimitIsAFault() {
        let check = DiscoveryAnswerCheck(catalog: Self.catalog, limit: 1)
        let faults = check.faults(in: ["files.read", "shell.execute"])
        #expect(faults == [.overLimit(count: 2, limit: 1)])
    }

    @Test("An answer of catalog paths, one time each, inside the limit, has no fault")
    func aWellFormedAnswerHasNoFault() {
        #expect(Self.check.faults(in: ["shell.execute", "files.read"]).isEmpty)
    }

    @Test("An empty answer has no fault, because how many paths a model selects is not a rule of the code")
    func anEmptyAnswerHasNoFault() {
        #expect(Self.check.faults(in: []).isEmpty)
    }

    @Test("A query that declares a path the catalog does not define is found")
    func aDeclaredPathOutsideTheCatalogIsFound() {
        let query = GradedDiscoveryQuery(
            task: "remove a file", correctPaths: ["shell.execute", Self.pathOutsideTheCatalog])
        #expect(Self.check.declaredPathsOutsideTheCatalog(of: query) == [Self.pathOutsideTheCatalog])
    }
}
