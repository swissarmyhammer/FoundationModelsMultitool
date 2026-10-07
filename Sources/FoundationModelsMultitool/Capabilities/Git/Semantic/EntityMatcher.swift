// `EntityMatcher` — pairs the entities of the old side of a file with the
// entities of the new side, and names what happened to each one.
//
// A port of `model/identity.rs` in
// `../swissarmyhammer/crates/swissarmyhammer-sem/src/`: the type alias
// `SimilarityFn`, the struct `MatchResult`, and the functions
// `match_entities` and `default_similarity`. The three phases, the
// thresholds, and the order of the result are the same as in Rust:
//
// 1. Exact id: the same id on each side is `modified` when the content
//    hash differs, and no change when it is the same.
// 2. Hash: an entity with no id match takes an old entity with the same
//    content hash, or else with the same structural hash. That pair is
//    `moved` when the file path differs, and `renamed` when it is the same.
// 3. Fuzzy: with a similarity function, an entity with no match takes the
//    old entity of the same type with the best score of 0.8 or more.
//
// Each old entity with no match is `deleted`, and each new entity with no
// match is `added`.
//
// Two differences from the Rust code, and neither one changes a result
// that Rust makes in a fixed order:
//
// - Phase 1 in Rust walks a `HashMap`, thus the order of its `modified`
//   changes is not fixed. This port walks the ids in the order of the new
//   side.
// - `match_entities` takes a `_file_path` argument that it never reads.
//   This port does not have that argument.

/// A function that gives the similarity of two entities, from 0 to 1:
/// `SimilarityFn` in `model/identity.rs`.
typealias EntitySimilarity = (SemanticEntity, SemanticEntity) -> Double

/// The changes that ``EntityMatcher/matchEntities(before:after:similarity:commitSHA:author:)``
/// found: `MatchResult` in `model/identity.rs`.
struct MatchResult: Equatable, Sendable {

    /// The changes: the phase 1, 2, and 3 matches in that order, then the
    /// deleted entities, then the added entities.
    let changes: [SemanticChange]
}

/// The three-phase entity matcher of `model/identity.rs`.
enum EntityMatcher {

    /// The lowest similarity score that phase 3 accepts: `THRESHOLD` in
    /// `match_entities`.
    static let fuzzyMatchThreshold = 0.8

    /// Phase 3 skips a pair whose smaller token count is less than this
    /// part of the larger one: `SIZE_RATIO_CUTOFF` in `match_entities`.
    static let sizeRatioCutoff = 0.5

    /// ``defaultSimilarity(_:_:)`` gives 0 for a pair whose smaller token
    /// count is less than this part of the larger one.
    static let similarityTokenRatioCutoff = 0.6

    /// Pairs the entities of the two sides of a file: `match_entities` in
    /// `model/identity.rs`.
    ///
    /// - Parameters:
    ///   - before: The entities of the old side.
    ///   - after: The entities of the new side.
    ///   - similarity: The similarity function of phase 3, or `nil` for no
    ///     phase 3.
    ///   - commitSHA: The commit sha to write on each change, or `nil`.
    ///   - author: The author to write on each change, or `nil`.
    /// - Returns: The changes.
    static func matchEntities(
        before: [SemanticEntity],
        after: [SemanticEntity],
        similarity: EntitySimilarity? = nil,
        commitSHA: String? = nil,
        author: String? = nil
    ) -> MatchResult {
        var matching = Matching(commitSHA: commitSHA, author: author)
        matching.matchExactIDs(before: before, after: after)
        let unmatchedBefore = before.filter { !matching.matchedBefore.contains($0.id) }
        let unmatchedAfter = after.filter { !matching.matchedAfter.contains($0.id) }
        matching.matchHashes(before: unmatchedBefore, after: unmatchedAfter)
        if let similarity {
            matching.matchSimilar(
                before: unmatchedBefore.filter { !matching.matchedBefore.contains($0.id) },
                after: unmatchedAfter.filter { !matching.matchedAfter.contains($0.id) },
                similarity: similarity)
        }
        matching.recordUnmatched(before: before, after: after)
        return MatchResult(changes: matching.changes)
    }

    /// The Jaccard index of the whitespace-split tokens of the two
    /// contents: `default_similarity` in `model/identity.rs`.
    ///
    /// A pair whose token counts differ too much gives 0 before the index,
    /// because such a pair cannot reach ``fuzzyMatchThreshold``. Two empty
    /// contents give 0.
    ///
    /// - Parameters:
    ///   - first: One entity.
    ///   - second: The other entity.
    /// - Returns: The score, from 0 to 1.
    static func defaultSimilarity(_ first: SemanticEntity, _ second: SemanticEntity) -> Double {
        let firstTokens = whitespaceTokens(of: first.content)
        let secondTokens = whitespaceTokens(of: second.content)
        guard let ratio = tokenCountRatio(firstTokens.count, secondTokens.count), ratio < similarityTokenRatioCutoff
        else { return jaccardIndex(firstTokens, secondTokens) }
        return 0
    }

    /// The count of tokens in both lists divided by the count of tokens in
    /// either list, each list read as a set. Two empty lists give 0.
    private static func jaccardIndex(_ firstTokens: [String], _ secondTokens: [String]) -> Double {
        let firstSet = Set(firstTokens)
        let secondSet = Set(secondTokens)
        let unionCount = firstSet.union(secondSet).count
        guard unionCount > 0 else { return 0 }
        return Double(firstSet.intersection(secondSet).count) / Double(unionCount)
    }

    /// The tokens of `text`, split at each Unicode whitespace scalar, as the
    /// Rust `str::split_whitespace` splits them.
    static func whitespaceTokens(of text: String) -> [String] {
        text.unicodeScalars
            .split(whereSeparator: \.properties.isWhitespace)
            .map { String(String.UnicodeScalarView($0)) }
    }

    /// The smaller count divided by the larger count, or `nil` when the
    /// larger count is 0. Rust compares this ratio with each cutoff only
    /// when the larger count is above 0.
    static func tokenCountRatio(_ first: Int, _ second: Int) -> Double? {
        let larger = max(first, second)
        guard larger > 0 else { return nil }
        return Double(min(first, second)) / Double(larger)
    }
}

/// The state of one ``EntityMatcher/matchEntities(before:after:similarity:commitSHA:author:)``
/// call: the ids that a phase matched, and the changes so far.
private struct Matching {

    /// The commit sha to write on each change.
    let commitSHA: String?

    /// The author to write on each change.
    let author: String?

    /// The ids of the old entities that a phase matched:
    /// `matched_before` in Rust.
    var matchedBefore: Set<String> = []

    /// The ids of the new entities that a phase matched: `matched_after`
    /// in Rust.
    var matchedAfter: Set<String> = []

    /// The changes so far, in the order of the Rust result.
    var changes: [SemanticChange] = []

    // MARK: Phase 1

    /// Phase 1: the same id on each side. A `HashMap` collect in Rust keeps
    /// the last entity of each id, and so does this.
    mutating func matchExactIDs(before: [SemanticEntity], after: [SemanticEntity]) {
        let beforeByID = Dictionary(before.map { ($0.id, $0) }, uniquingKeysWith: { _, last in last })
        let afterByID = Dictionary(after.map { ($0.id, $0) }, uniquingKeysWith: { _, last in last })
        var visited: Set<String> = []
        for entity in after where visited.insert(entity.id).inserted {
            guard let newEntity = afterByID[entity.id], let oldEntity = beforeByID[entity.id] else { continue }
            matchedBefore.insert(entity.id)
            matchedAfter.insert(entity.id)
            if oldEntity.contentHash != newEntity.contentHash {
                recordModified(from: oldEntity, to: newEntity)
            }
        }
    }

    /// Records one `modified` change.
    private mutating func recordModified(from oldEntity: SemanticEntity, to newEntity: SemanticEntity) {
        var isStructuralChange: Bool?
        if let oldHash = oldEntity.structuralHash, let newHash = newEntity.structuralHash {
            isStructuralChange = oldHash != newHash
        }
        changes.append(
            change(
                id: "change::\(newEntity.id)", entity: newEntity, type: .modified, oldFilePath: nil,
                beforeContent: oldEntity.content, afterContent: newEntity.content,
                isStructuralChange: isStructuralChange))
    }

    // MARK: Phase 2

    /// Phase 2: the same content hash, or else the same structural hash.
    mutating func matchHashes(before: [SemanticEntity], after: [SemanticEntity]) {
        var candidates = HashCandidates(before: before)
        for newEntity in after where !matchedAfter.contains(newEntity.id) {
            let found =
                candidates.takeContentMatch(for: newEntity)
                ?? candidates.takeStructuralMatch(for: newEntity, skipping: matchedBefore)
            if let oldEntity = found {
                recordPair(from: oldEntity, to: newEntity)
            }
        }
    }

    // MARK: Phase 3

    /// Phase 3: the best similar entity of the same type, with a score of
    /// ``EntityMatcher/fuzzyMatchThreshold`` or more.
    mutating func matchSimilar(
        before: [SemanticEntity], after: [SemanticEntity], similarity: EntitySimilarity
    ) {
        guard !before.isEmpty, !after.isEmpty else { return }
        let beforeCounts = before.map { EntityMatcher.whitespaceTokens(of: $0.content).count }
        for newEntity in after {
            let newCount = EntityMatcher.whitespaceTokens(of: newEntity.content).count
            var best: SemanticEntity?
            var bestScore = 0.0
            for (index, oldEntity) in before.enumerated()
            where isCandidate(oldEntity, for: newEntity, tokenCounts: (beforeCounts[index], newCount)) {
                let score = similarity(oldEntity, newEntity)
                if score > bestScore && score >= EntityMatcher.fuzzyMatchThreshold {
                    bestScore = score
                    best = oldEntity
                }
            }
            if let best {
                recordPair(from: best, to: newEntity)
            }
        }
    }

    /// Whether phase 3 scores `oldEntity` for `newEntity`: the old entity
    /// has no match yet, the two have the same type, and their token counts
    /// are near enough (``EntityMatcher/sizeRatioCutoff``).
    private func isCandidate(
        _ oldEntity: SemanticEntity, for newEntity: SemanticEntity, tokenCounts: (Int, Int)
    ) -> Bool {
        guard !matchedBefore.contains(oldEntity.id), oldEntity.entityType == newEntity.entityType else {
            return false
        }
        guard let ratio = EntityMatcher.tokenCountRatio(tokenCounts.0, tokenCounts.1) else { return true }
        return ratio >= EntityMatcher.sizeRatioCutoff
    }

    // MARK: Records

    /// Records a phase 2 or phase 3 pair: `moved` when the file path
    /// differs, else `renamed`.
    private mutating func recordPair(from oldEntity: SemanticEntity, to newEntity: SemanticEntity) {
        matchedBefore.insert(oldEntity.id)
        matchedAfter.insert(newEntity.id)
        let isMove = oldEntity.filePath != newEntity.filePath
        changes.append(
            change(
                id: "change::\(newEntity.id)", entity: newEntity, type: isMove ? .moved : .renamed,
                oldFilePath: isMove ? oldEntity.filePath : nil,
                beforeContent: oldEntity.content, afterContent: newEntity.content, isStructuralChange: nil))
    }

    /// Records each old entity with no match as `deleted`, then each new
    /// entity with no match as `added`.
    mutating func recordUnmatched(before: [SemanticEntity], after: [SemanticEntity]) {
        for entity in before where !matchedBefore.contains(entity.id) {
            changes.append(
                change(
                    id: "change::deleted::\(entity.id)", entity: entity, type: .deleted, oldFilePath: nil,
                    beforeContent: entity.content, afterContent: nil, isStructuralChange: nil))
        }
        for entity in after where !matchedAfter.contains(entity.id) {
            changes.append(
                change(
                    id: "change::added::\(entity.id)", entity: entity, type: .added, oldFilePath: nil,
                    beforeContent: nil, afterContent: entity.content, isStructuralChange: nil))
        }
    }

    /// One change of `entity`, with the commit sha and the author of this
    /// call.
    private func change(
        id: String, entity: SemanticEntity, type: ChangeType, oldFilePath: String?,
        beforeContent: String?, afterContent: String?, isStructuralChange: Bool?
    ) -> SemanticChange {
        SemanticChange(
            id: id, entityID: entity.id, changeType: type, entityType: entity.entityType,
            entityName: entity.name, filePath: entity.filePath, oldFilePath: oldFilePath,
            beforeContent: beforeContent, afterContent: afterContent, commitSHA: commitSHA, author: author,
            isStructuralChange: isStructuralChange)
    }
}

/// The old entities of phase 2, grouped by content hash and by structural
/// hash: `before_by_hash` and `before_by_structural` in `match_entities`.
private struct HashCandidates {

    /// The old entities with each content hash, in input order.
    private var byContentHash: [String: [SemanticEntity]] = [:]

    /// The old entities with each structural hash, in input order.
    private var byStructuralHash: [String: [SemanticEntity]] = [:]

    /// Groups `before` by each hash.
    init(before: [SemanticEntity]) {
        for entity in before {
            byContentHash[entity.contentHash, default: []].append(entity)
            if let structuralHash = entity.structuralHash {
                byStructuralHash[structuralHash, default: []].append(entity)
            }
        }
    }

    /// Takes the last old entity with the content hash of `newEntity`, as
    /// the Rust `Vec::pop` does.
    mutating func takeContentMatch(for newEntity: SemanticEntity) -> SemanticEntity? {
        byContentHash[newEntity.contentHash]?.popLast()
    }

    /// Takes the first old entity with the structural hash of `newEntity`
    /// whose id is not in `matched`.
    mutating func takeStructuralMatch(for newEntity: SemanticEntity, skipping matched: Set<String>) -> SemanticEntity? {
        guard let structuralHash = newEntity.structuralHash,
            let index = byStructuralHash[structuralHash]?.firstIndex(where: { !matched.contains($0.id) })
        else { return nil }
        return byStructuralHash[structuralHash]?.remove(at: index)
    }
}
