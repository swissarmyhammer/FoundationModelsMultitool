import Foundation
import Testing

@testable import FoundationModelsMultitool

/// Tests for ``EntityMatcher`` and ``SemanticEntity`` — the port of
/// `model/identity.rs` and `model/entity.rs` in
/// `../swissarmyhammer/crates/swissarmyhammer-sem/src/`.
///
/// Each test of the Rust `mod tests` blocks has a test here with the same
/// input and the same assertions. The suite adds tests for the order of the
/// result and for the thresholds of the fuzzy phase.
@Suite("EntityMatcherTests")
struct EntityMatcherTests {

    /// An entity of type `function` with no structural hash: `make_entity`
    /// of the Rust tests in `model/identity.rs`.
    private static func entity(
        _ id: String, _ name: String, _ content: String, _ filePath: String, structuralHash: String? = nil
    ) -> SemanticEntity {
        SemanticEntity(
            id: id, filePath: filePath, entityType: "function", name: name, parentID: nil,
            content: content, contentHash: SemanticHash.contentHash(content), structuralHash: structuralHash,
            startLine: 1, endLine: 1, metadata: nil)
    }

    /// The change types of `result`, in order.
    private static func changeTypes(_ result: MatchResult) -> [ChangeType] {
        result.changes.map(\.changeType)
    }

    /// Nine tokens that two entities share in the fuzzy tests of the Rust
    /// suite.
    private static let sharedTokens = "alpha beta gamma delta epsilon zeta eta theta iota"

    // MARK: Entity id (`model/entity.rs`)

    /// An entity with no parent has the id `file::type::name`.
    @Test("an entity with no parent has the id file::type::name")
    func anEntityWithNoParentHasTheTypeInItsID() {
        #expect(
            SemanticEntity.makeID(filePath: "src/main.ts", entityType: "function", name: "hello", parentID: nil)
                == "src/main.ts::function::hello")
    }

    /// An entity with a parent has the id `file::parent::name`.
    @Test("an entity with a parent has the id file::parent::name")
    func anEntityWithAParentHasTheParentInItsID() {
        #expect(
            SemanticEntity.makeID(filePath: "src/main.ts", entityType: "method", name: "greet", parentID: "MyClass")
                == "src/main.ts::MyClass::greet")
    }

    // MARK: Phase 1: exact id

    /// The same id with a different content is one modified change.
    @Test("the same id with different content is modified")
    func theSameIDWithDifferentContentIsModified() throws {
        let result = EntityMatcher.matchEntities(
            before: [Self.entity("a::f::foo", "foo", "old content", "a.ts")],
            after: [Self.entity("a::f::foo", "foo", "new content", "a.ts")])

        #expect(Self.changeTypes(result) == [.modified])
        let change = try #require(result.changes.first)
        #expect(change.id == "change::a::f::foo")
        #expect(change.entityType == "function")
        #expect(change.entityName == "foo")
        #expect(change.beforeContent == "old content")
        #expect(change.afterContent == "new content")
        #expect(change.isStructuralChange == nil)
    }

    /// The same id with the same content is no change.
    @Test("the same id with the same content is no change")
    func theSameIDWithTheSameContentIsNoChange() {
        let result = EntityMatcher.matchEntities(
            before: [Self.entity("a::f::foo", "foo", "same", "a.ts")],
            after: [Self.entity("a::f::foo", "foo", "same", "a.ts")])

        #expect(result.changes.isEmpty)
    }

    /// A modified entity whose two sides have a structural hash tells
    /// whether the structure changed.
    @Test("a modified entity with two structural hashes tells whether the structure changed")
    func aModifiedEntityTellsWhetherTheStructureChanged() {
        let formatOnly = EntityMatcher.matchEntities(
            before: [Self.entity("id", "f", "a+b", "a.ts", structuralHash: "s1")],
            after: [Self.entity("id", "f", "a + b", "a.ts", structuralHash: "s1")])
        let structural = EntityMatcher.matchEntities(
            before: [Self.entity("id", "f", "a+b", "a.ts", structuralHash: "s1")],
            after: [Self.entity("id", "f", "b+a", "a.ts", structuralHash: "s2")])

        #expect(formatOnly.changes.map(\.isStructuralChange) == [false])
        #expect(structural.changes.map(\.isStructuralChange) == [true])
    }

    /// Phase 1 records the modified changes in the order of the after list.
    @Test("modified changes keep the order of the after list")
    func modifiedChangesKeepTheOrderOfTheAfterList() {
        let ids = ["c", "a", "b"]
        let result = EntityMatcher.matchEntities(
            before: ids.map { Self.entity($0, $0, "old \($0)", "a.ts") },
            after: ids.map { Self.entity($0, $0, "new \($0)", "a.ts") })

        #expect(result.changes.map(\.entityID) == ids)
    }

    // MARK: Added and deleted

    /// Two entities with nothing in common are one deleted and one added.
    @Test("two unrelated entities are deleted and added")
    func twoUnrelatedEntitiesAreDeletedAndAdded() {
        let result = EntityMatcher.matchEntities(
            before: [Self.entity("a::f::old", "old", "content", "a.ts")],
            after: [Self.entity("a::f::new", "new", "different", "a.ts")])

        #expect(Self.changeTypes(result) == [.deleted, .added])
        #expect(result.changes.map(\.id) == ["change::deleted::a::f::old", "change::added::a::f::new"])
        #expect(result.changes[0].afterContent == nil)
        #expect(result.changes[1].beforeContent == nil)
    }

    // MARK: Phase 2: content hash and structural hash

    /// The same content under a new id in the same file is renamed.
    @Test("the same content under a new id is renamed")
    func theSameContentUnderANewIDIsRenamed() {
        let result = EntityMatcher.matchEntities(
            before: [Self.entity("a::f::old", "old", "same content", "a.ts")],
            after: [Self.entity("a::f::new", "new", "same content", "a.ts")])

        #expect(Self.changeTypes(result) == [.renamed])
        #expect(result.changes[0].oldFilePath == nil)
    }

    /// The same content in another file is moved, with the old path.
    @Test("the same content in another file is moved")
    func theSameContentInAnotherFileIsMoved() {
        let result = EntityMatcher.matchEntities(
            before: [Self.entity("a::f::foo", "foo", "same content", "a.ts")],
            after: [Self.entity("b::f::foo", "foo", "same content", "b.ts")])

        #expect(Self.changeTypes(result) == [.moved])
        #expect(result.changes[0].oldFilePath == "a.ts")
        #expect(result.changes[0].filePath == "b.ts")
    }

    /// A move keeps the content of each side, the commit sha, and the
    /// author.
    @Test("a move keeps the content, the commit sha, and the author")
    func aMoveKeepsTheContentTheCommitAndTheAuthor() throws {
        let result = EntityMatcher.matchEntities(
            before: [Self.entity("old::f::fn1", "fn1", "body text here", "old.ts")],
            after: [Self.entity("new::f::fn1", "fn1", "body text here", "new.ts")],
            commitSHA: "sha1", author: "alice")

        #expect(result.changes.count == 1)
        let change = try #require(result.changes.first)
        #expect(change.changeType == .moved)
        #expect(change.beforeContent == "body text here")
        #expect(change.afterContent == "body text here")
        #expect(change.commitSHA == "sha1")
        #expect(change.author == "alice")
    }

    /// The same structural hash with a new id in the same file is renamed.
    @Test("the same structural hash under a new id is renamed")
    func theSameStructuralHashUnderANewIDIsRenamed() {
        let result = EntityMatcher.matchEntities(
            before: [Self.entity("a::f::old", "old", "fn old() { /* comment */ }", "a.ts", structuralHash: "struct-abc")],
            after: [Self.entity("a::f::new", "new", "fn new() {}", "a.ts", structuralHash: "struct-abc")])

        #expect(Self.changeTypes(result) == [.renamed])
        #expect(result.changes[0].oldFilePath == nil)
    }

    /// The same structural hash in another file is moved.
    @Test("the same structural hash in another file is moved")
    func theSameStructuralHashInAnotherFileIsMoved() {
        let result = EntityMatcher.matchEntities(
            before: [Self.entity("a::f::fn1", "fn1", "fn fn1() { let x = 1; }", "a.ts", structuralHash: "struct-xyz")],
            after: [Self.entity("b::f::fn1", "fn1", "fn fn1() { let y = 1; }", "b.ts", structuralHash: "struct-xyz")])

        #expect(Self.changeTypes(result) == [.moved])
        #expect(result.changes[0].oldFilePath == "a.ts")
    }

    /// An entity that phase 1 matched does not match again in phase 2.
    @Test("an entity that phase 1 matched does not match in phase 2")
    func anEntityThatPhaseOneMatchedDoesNotMatchAgain() {
        let result = EntityMatcher.matchEntities(
            before: [
                Self.entity("id1", "fn1", "content1", "a.ts", structuralHash: "hash-s"),
                Self.entity("id2", "fn2", "content2", "a.ts", structuralHash: "hash-s"),
            ],
            after: [
                Self.entity("id1", "fn1", "content1-changed", "a.ts", structuralHash: "hash-s"),
                Self.entity("id3", "fn3", "content3", "a.ts", structuralHash: "hash-s"),
            ])

        #expect(Self.changeTypes(result) == [.modified, .renamed])
        #expect(result.changes[1].beforeContent == "content2")
    }

    // MARK: Phase 3: fuzzy similarity

    /// A similar entity in the same file is renamed. Nine shared tokens and
    /// one unique token on each side give a Jaccard index of 9/11.
    @Test("a similar entity in the same file is renamed")
    func aSimilarEntityInTheSameFileIsRenamed() {
        let result = EntityMatcher.matchEntities(
            before: [Self.entity("a::old", "old", "\(Self.sharedTokens) old_unique", "a.ts")],
            after: [Self.entity("a::new", "new", "\(Self.sharedTokens) new_unique", "a.ts")],
            similarity: EntityMatcher.defaultSimilarity)

        #expect(Self.changeTypes(result) == [.renamed])
        #expect(result.changes[0].oldFilePath == nil)
    }

    /// A similar entity in another file is moved.
    @Test("a similar entity in another file is moved")
    func aSimilarEntityInAnotherFileIsMoved() {
        let result = EntityMatcher.matchEntities(
            before: [Self.entity("a::fn1", "fn1", "\(Self.sharedTokens) old_unique", "a.ts")],
            after: [Self.entity("b::fn1", "fn1", "\(Self.sharedTokens) new_unique", "b.ts")],
            similarity: EntityMatcher.defaultSimilarity)

        #expect(Self.changeTypes(result) == [.moved])
        #expect(result.changes[0].oldFilePath == "a.ts")
    }

    /// With no similarity function there is no fuzzy phase.
    @Test("with no similarity function a similar entity is deleted and added")
    func withNoSimilarityFunctionThereIsNoFuzzyPhase() {
        let result = EntityMatcher.matchEntities(
            before: [Self.entity("a::old", "old", "\(Self.sharedTokens) old_unique", "a.ts")],
            after: [Self.entity("a::new", "new", "\(Self.sharedTokens) new_unique", "a.ts")])

        #expect(Self.changeTypes(result) == [.deleted, .added])
    }

    /// Two entities that are too different are deleted and added.
    @Test("two entities below the threshold are deleted and added")
    func twoEntitiesBelowTheThresholdAreDeletedAndAdded() {
        let result = EntityMatcher.matchEntities(
            before: [Self.entity("a::fn1", "fn1", "completely different code here", "a.ts")],
            after: [Self.entity("b::fn2", "fn2", "totally unrelated stuff there", "b.ts")],
            similarity: EntityMatcher.defaultSimilarity)

        #expect(Self.changeTypes(result) == [.deleted, .added])
    }

    /// The fuzzy phase matches only entities of the same type.
    @Test("the fuzzy phase matches only entities of the same type")
    func theFuzzyPhaseMatchesOnlyTheSameType() {
        let before = Self.entity("a::old", "old", "\(Self.sharedTokens) old_unique", "a.ts")
        let after = SemanticEntity(
            id: "a::new", filePath: "a.ts", entityType: "class", name: "new", parentID: nil,
            content: "\(Self.sharedTokens) new_unique",
            contentHash: SemanticHash.contentHash("\(Self.sharedTokens) new_unique"), structuralHash: nil,
            startLine: 1, endLine: 1, metadata: nil)

        let result = EntityMatcher.matchEntities(
            before: [before], after: [after], similarity: EntityMatcher.defaultSimilarity)

        #expect(Self.changeTypes(result) == [.deleted, .added])
    }

    /// A score of exactly the threshold matches: the rule is `>= 0.8`.
    @Test("a score equal to the threshold matches")
    func aScoreEqualToTheThresholdMatches() {
        let result = EntityMatcher.matchEntities(
            before: [Self.entity("a::old", "old", "x", "a.ts")],
            after: [Self.entity("a::new", "new", "y", "a.ts")],
            similarity: { _, _ in EntityMatcher.fuzzyMatchThreshold })

        #expect(Self.changeTypes(result) == [.renamed])
    }

    /// A pair whose token counts differ by more than half is skipped before
    /// the similarity function runs.
    @Test("a pair with very different token counts is skipped")
    func aPairWithVeryDifferentTokenCountsIsSkipped() {
        let result = EntityMatcher.matchEntities(
            before: [Self.entity("a::old", "old", "one", "a.ts")],
            after: [Self.entity("a::new", "new", "one two three", "a.ts")],
            similarity: { _, _ in 1 })

        #expect(Self.changeTypes(result) == [.deleted, .added])
    }

    /// When two candidates have the same best score, the first one wins.
    @Test("the first of two equal best candidates wins")
    func theFirstOfTwoEqualBestCandidatesWins() {
        let result = EntityMatcher.matchEntities(
            before: [Self.entity("a::one", "one", "x", "a.ts"), Self.entity("a::two", "two", "y", "a.ts")],
            after: [Self.entity("a::new", "new", "z", "a.ts")],
            similarity: { _, _ in 1 })

        #expect(Self.changeTypes(result) == [.renamed, .deleted])
        #expect(result.changes[0].beforeContent == "x")
        #expect(result.changes[1].entityID == "a::two")
    }

    // MARK: Several entities

    /// One entity stays and one moves: only the move is a change.
    @Test("one entity stays and one moves")
    func oneEntityStaysAndOneMoves() {
        let result = EntityMatcher.matchEntities(
            before: [
                Self.entity("a::fn_stay", "fn_stay", "stay content", "a.ts"),
                Self.entity("a::fn_move", "fn_move", "move content", "a.ts"),
            ],
            after: [
                Self.entity("a::fn_stay", "fn_stay", "stay content", "a.ts"),
                Self.entity("b::fn_move", "fn_move", "move content", "b.ts"),
            ])

        #expect(Self.changeTypes(result) == [.moved])
        #expect(result.changes[0].entityID == "b::fn_move")
    }

    // MARK: Default similarity

    /// Similar texts give a score between 0.5 and 1.
    @Test("similar texts give a score between one half and one")
    func similarTextsGiveAPartialScore() {
        let score = EntityMatcher.defaultSimilarity(
            Self.entity("a", "a", "the quick brown fox", "a.ts"), Self.entity("b", "b", "the quick brown dog", "a.ts"))

        #expect(score > 0.5)
        #expect(score < 1)
    }

    /// The same text gives 1.
    @Test("the same text gives one")
    func theSameTextGivesOne() {
        let score = EntityMatcher.defaultSimilarity(
            Self.entity("a", "a", "hello world foo bar", "a.ts"), Self.entity("b", "b", "hello world foo bar", "b.ts"))

        #expect(abs(score - 1) < 1e-9)
    }

    /// Two empty texts give 0.
    @Test("two empty texts give zero")
    func twoEmptyTextsGiveZero() {
        let score = EntityMatcher.defaultSimilarity(Self.entity("a", "a", "", "a.ts"), Self.entity("b", "b", "", "b.ts"))

        #expect(score == 0)
    }

    /// Two texts with no shared token give 0.
    @Test("two texts with no shared token give zero")
    func twoTextsWithNoSharedTokenGiveZero() {
        let score = EntityMatcher.defaultSimilarity(
            Self.entity("a", "a", "alpha beta gamma", "a.ts"), Self.entity("b", "b", "delta epsilon zeta", "b.ts"))

        #expect(score == 0)
    }

    /// A token count ratio below 0.6 gives 0 before the Jaccard index.
    @Test("a token count ratio below the cutoff gives zero")
    func aTokenCountRatioBelowTheCutoffGivesZero() {
        let score = EntityMatcher.defaultSimilarity(
            Self.entity("a", "a", "fn foo", "a.ts"),
            Self.entity("b", "b", "one two three four five six seven eight nine ten eleven twelve", "b.ts"))

        #expect(score == 0)
    }

    /// Nine shared tokens and one unique token on each side give 9/11.
    @Test("nine shared tokens of eleven give nine elevenths")
    func nineSharedTokensOfElevenGiveNineElevenths() {
        let common = "one two three four five six seven eight nine"
        let score = EntityMatcher.defaultSimilarity(
            Self.entity("a", "a", "\(common) alpha", "a.ts"), Self.entity("b", "b", "\(common) beta", "b.ts"))

        #expect(abs(score - 9.0 / 11.0) < 1e-9)
        #expect(score >= EntityMatcher.fuzzyMatchThreshold)
    }

    /// One shared token of five gives a score below the threshold.
    @Test("one shared token of five is below the threshold")
    func oneSharedTokenOfFiveIsBelowTheThreshold() {
        let score = EntityMatcher.defaultSimilarity(
            Self.entity("a", "a", "shared alpha beta gamma", "a.ts"),
            Self.entity("b", "b", "shared delta epsilon zeta", "b.ts"))

        #expect(score < EntityMatcher.fuzzyMatchThreshold)
    }

    /// Unicode whitespace splits tokens, as the Rust `split_whitespace`
    /// does, and a token repeated on one side counts one time.
    @Test("unicode whitespace splits tokens and a repeated token counts one time")
    func unicodeWhitespaceSplitsTokens() {
        let score = EntityMatcher.defaultSimilarity(
            Self.entity("a", "a", "alpha\u{2003}beta\u{00A0}gamma alpha", "a.ts"),
            Self.entity("b", "b", "alpha beta gamma delta", "b.ts"))

        #expect(abs(score - 3.0 / 4.0) < 1e-9)
    }
}
