import Foundation
import Testing

@testable import FoundationModelsMultitool

/// Golden-vector and behavioral tests for the ``Hashline`` module.
///
/// This suite is a port of the sibling FileTool suite. The golden fixtures in
/// `FilesGoldens/hashline-golden.json` come directly from the Rust
/// `swissarmyhammer-hashline` crate (per-line `crc32fast` hash, `tag`
/// line-ending preservation, `parse_anchor`, `resolve_anchor_in`) plus the
/// `md5`-based whole-file freshness token from `swissarmyhammer-tools`'
/// `shared_utils::whole_file_hash`. Assertion of the Swift port against them
/// pins the cross-tool anchor dialect: an anchor that the Rust `files` tool
/// emits must resolve identically here, and the reverse also holds.
@Suite struct HashlineTests {
    // MARK: Golden fixture model

    private struct Golden: Decodable {
        struct HashLineCase: Decodable {
            let input: String
            let hash: UInt8
            let rendered: String
        }
        struct TagCase: Decodable {
            let content: String
            let startLine: Int
            let expected: String
        }
        struct WholeFileCase: Decodable {
            let content: String
            let expected: String
        }
        struct AnchorResult: Decodable {
            let line: Int
            let hash: UInt8
        }
        struct ParseCase: Decodable {
            let input: String
            let result: AnchorResult?
        }
        struct ResolveCase: Decodable {
            let content: String
            let line: Int
            let hash: UInt8
            let text: String?
            let expected: Int?
        }
        let hashLine: [HashLineCase]
        let tag: [TagCase]
        let wholeFileHash: [WholeFileCase]
        let parseAnchor: [ParseCase]
        let resolveAnchor: [ResolveCase]
    }

    private static func loadGolden() throws -> Golden {
        let url = try #require(
            Bundle.module.url(
                forResource: "hashline-golden",
                withExtension: "json",
                subdirectory: "FilesGoldens"
            ),
            "hashline-golden.json fixture must be bundled with the test target"
        )
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(Golden.self, from: data)
    }

    // MARK: Golden-vector parity (cross-tool anchor dialect)

    @Test func hashLineMatchesRustGoldenVectors() throws {
        for c in try Self.loadGolden().hashLine {
            #expect(
                Hashline.hashLine(c.input) == c.hash,
                "hashLine(\(c.input.debugDescription)) should be \(c.hash)"
            )
            #expect(
                Hashline.renderHash(Hashline.hashLine(c.input)) == c.rendered,
                "renderHash for \(c.input.debugDescription) should be \(c.rendered)"
            )
        }
    }

    @Test func tagMatchesRustGoldenVectors() throws {
        for c in try Self.loadGolden().tag {
            #expect(
                Hashline.tag(lines: c.content, startingAtLine: c.startLine) == c.expected,
                "tag(\(c.content.debugDescription), \(c.startLine)) mismatch"
            )
        }
    }

    @Test func wholeFileHashMatchesRustGoldenVectors() throws {
        for c in try Self.loadGolden().wholeFileHash {
            let bytes = Data(c.content.utf8)
            #expect(
                Hashline.wholeFileHash(bytes: bytes) == c.expected,
                "wholeFileHash(\(c.content.debugDescription)) mismatch"
            )
        }
    }

    @Test func parseAnchorMatchesRustGoldenVectors() throws {
        for c in try Self.loadGolden().parseAnchor {
            let parsed = Hashline.parseAnchor(c.input)
            if let expected = c.result {
                #expect(parsed?.line == expected.line, "line for \(c.input.debugDescription)")
                #expect(parsed?.hash == expected.hash, "hash for \(c.input.debugDescription)")
            } else {
                #expect(parsed == nil, "\(c.input.debugDescription) must not parse")
            }
        }
    }

    @Test func resolveAnchorMatchesRustGoldenVectors() throws {
        for c in try Self.loadGolden().resolveAnchor {
            let resolved = Hashline.resolveAnchorIn(
                c.content, line: c.line, hash: c.hash, text: c.text
            )
            #expect(
                resolved == c.expected,
                "resolve(line \(c.line), hash \(c.hash), text \(String(describing: c.text))) mismatch"
            )
        }
    }

    // MARK: Behavioral tests (drift, proximity window, staleness, |text)

    @Test func resolvesDriftedAnchorAtPlusOne() {
        // The anchor points at line 2 ("b"); an inserted line moved "b" to
        // line 3. The proximity search finds it again (delta +1).
        let content = "a\nx\nb\nc"
        #expect(Hashline.resolveAnchorIn(content, line: 2, hash: Hashline.hashLine("b"), text: nil) == 3)
    }

    /// The count of filler-line candidates the window-boundary test examines
    /// to find a filler whose hash differs from the needle's hash.
    ///
    /// Each candidate is a run of `"z"` of a different length, so at most one
    /// candidate can collide with the needle's single-byte hash per length;
    /// this many candidates make a full miss impossible in practice.
    private static let fillerCandidateCount = 40

    @Test func resolvesAtWindowEdgeButFailsOneBeyond() throws {
        // Build content whose only in-window hash match is the NEEDLE line, so
        // the window boundary gets a clean test: the needle is reachable at
        // delta `proximityWindow`, not one line farther.
        let window = Hashline.proximityWindow
        let needle = "NEEDLE"
        let needleHash = Hashline.hashLine(needle)
        let filler = try #require(
            (1...Self.fillerCandidateCount).map { String(repeating: "z", count: $0) }
                .first { Hashline.hashLine($0) != needleHash },
            "a filler line whose hash differs from the needle's must exist"
        )

        let atEdge = (Array(repeating: filler, count: window) + [needle]).joined(separator: "\n")
        #expect(
            Hashline.resolveAnchorIn(atEdge, line: 1, hash: needleHash, text: nil) == window + 1,
            "NEEDLE at delta +\(window) must resolve"
        )

        let beyondEdge = (Array(repeating: filler, count: window + 1) + [needle]).joined(separator: "\n")
        #expect(
            Hashline.resolveAnchorIn(beyondEdge, line: 1, hash: needleHash, text: nil) == nil,
            "NEEDLE at delta +\(window + 1) is outside the window and must not resolve"
        )

        // And symmetrically upward: NEEDLE a full window above the anchor.
        let aboveEdge = ([needle] + Array(repeating: filler, count: window)).joined(separator: "\n")
        #expect(
            Hashline.resolveAnchorIn(aboveEdge, line: window + 1, hash: needleHash, text: nil) == 1,
            "NEEDLE at delta -\(window) must resolve"
        )
    }

    @Test func staleAnchorFallsThroughToNil() {
        // Nothing in the window hashes to the expected value -> nil, so the
        // caller can fall through to literal interpretation and not misapply.
        let content = "a\nb\nc"
        #expect(
            Hashline.resolveAnchorIn(content, line: 2, hash: Hashline.hashLine("totally-different"), text: nil) == nil
        )
    }

    @Test func textSuffixRelocatesToSharedHashLine() {
        // Two in-window lines share the same hash; the symmetric search hits
        // +delta first, so the below-anchor "match" (line 5) wins.
        let content = "match\nfiller\nanchor_pos\nfiller\nmatch"
        #expect(
            Hashline.resolveAnchorIn(content, line: 3, hash: Hashline.hashLine("match"), text: "match") == 5
        )
    }

    @Test func tokenAndHashesAreStableAcrossRepeatedHashing() {
        let content = "alpha\nbeta\ngamma\n"
        let bytes = Data(content.utf8)
        #expect(Hashline.wholeFileHash(bytes: bytes) == Hashline.wholeFileHash(bytes: bytes))
        #expect(Hashline.tag(lines: content, startingAtLine: 1) == Hashline.tag(lines: content, startingAtLine: 1))
        #expect(Hashline.hashLine("beta") == Hashline.hashLine("beta"))
        // A changed file yields a different token.
        #expect(
            Hashline.wholeFileHash(bytes: bytes) != Hashline.wholeFileHash(bytes: Data("alpha\nBETA\ngamma\n".utf8)))
    }

    @Test func emptyFileAndEmptyLineEdgeCases() {
        #expect(Hashline.tag(lines: "", startingAtLine: 1) == "")
        #expect(Hashline.hashLine("") == 0)
        #expect(Hashline.resolveAnchorIn("", line: 1, hash: 0, text: nil) == nil)
        // MD5 of the empty byte string.
        #expect(Hashline.wholeFileHash(bytes: Data()) == "d41d8cd98f00b204e9800998ecf8427e")
    }

    // MARK: String-form resolveAnchor(_:in:) — the anchor dialect callers use

    @Test func resolveAnchorFromTaggedLineString() {
        // Lift an anchor back out of tagged content and resolve it, exactly as
        // `edit file` will: the anchor string carries `N:HH|text`.
        let content = "one\ntwo\nthree"
        let tagged = Hashline.tag(lines: content, startingAtLine: 1)
        let secondAnchor = String(tagged.split(separator: "\n")[1])  // "2:HH|two"
        #expect(Hashline.resolveAnchor(secondAnchor, in: content) == 2)
    }

    @Test func resolveAnchorStringRelocatesUnderDrift() {
        // The anchor comes from the original; the content then drifted by an
        // insertion.
        let original = "one\ntwo\nthree"
        let tagged = Hashline.tag(lines: original, startingAtLine: 1)
        let secondAnchor = String(tagged.split(separator: "\n")[1])  // anchors "two" at line 2
        let drifted = "one\nINSERTED\ntwo\nthree"
        #expect(Hashline.resolveAnchor(secondAnchor, in: drifted) == 3)
    }

    @Test func resolveAnchorStringReturnsNilForUnparseable() {
        #expect(Hashline.resolveAnchor("not an anchor", in: "one\ntwo") == nil)
    }

    // MARK: Exactness edge cases surfaced by adversarial review

    @Test func parseAnchorAcceptsLeadingPlusRejectsMinusAndSpace() {
        // Rust `usize::from_str` accepts an optional leading `+` but rejects
        // `-` and surrounding whitespace; the port matches that exactly.
        #expect(Hashline.parseAnchor("+42:a3")?.line == 42)
        #expect(Hashline.parseAnchor("+42:a3")?.hash == 0xa3)
        #expect(Hashline.parseAnchor("-42:a3") == nil)
        #expect(Hashline.parseAnchor(" 42:a3") == nil)
        #expect(Hashline.parseAnchor("42 :a3") == nil)
    }

    @Test func hashLineTrimsHorizontalWhitespaceByScalarNotGrapheme() {
        // Rust `trim_matches([' ', '\t'])` trims per scalar, so a leading
        // space followed by a combining mark trims to the bare mark — the
        // identical hash to the already-bare form. A grapheme-based trim
        // (which treats " \u{0301}" as one cluster) would NOT trim and would
        // hash differently.
        #expect(Hashline.hashLine("\u{20}\u{0301}x") == Hashline.hashLine("\u{0301}x"))
    }
}
