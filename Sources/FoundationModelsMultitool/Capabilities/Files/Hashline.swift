// `Hashline` — pure, IO-free hashline anchor primitives for line tagging
// and drift-tolerant resolution.
//
// A behavioral port of `../FoundationModelsFileTool/Sources/FileTool/
// Hashline.swift`. The sibling declares the type `public` for its own
// module surface; this package keeps it internal, the same way `PathGuard`
// and `PathCorrective` beside it do.
//
// eventplan.md § "Consolidation of the siblings": the files capability's
// read and edit verbs consume these primitives. `read file` tags content so
// the model can reference specific lines; `edit file` resolves those
// anchors back to lines, tolerates small drift (a few lines moved), and
// rejects stale edits (the referenced line's content changed). The verbs
// arrive on the file-verb cards this card blocks; until then the golden
// suite (`HashlineTests`) is the one caller.
//
// The module is an algorithm-exact port of the Rust
// `swissarmyhammer-hashline` crate (plus the `md5`-based whole-file
// freshness token from `swissarmyhammer-tools`'
// `shared_utils::whole_file_hash`). The hash algorithm is ported
// byte-for-byte so anchors emitted by the Rust `files` tool resolve here,
// and the reverse also holds — one anchor dialect across the ecosystem.
// Parity is pinned by golden vectors generated from the Rust crate
// (`Tests/FoundationModelsMultitoolTests/FilesGoldens/hashline-golden.json`).

import CryptoKit
import Foundation

/// Pure, IO-free hashline anchor primitives for line tagging and drift-tolerant resolution.
///
/// A *hashline anchor* tags a line of text with its 1-based line number and a
/// short content hash, rendered as `N:HH` (for example `42:a3`). See the file
/// header for the port provenance and the cross-tool dialect contract.
enum Hashline {
    /// The maximum distance, in lines, that proximity search looks from the exact line for a drifted anchor.
    ///
    /// The search expands symmetrically outward (`+1, -1, +2, -2, …`) up to this
    /// many lines on each side. Matches the Rust `PROXIMITY_WINDOW`.
    static let proximityWindow = 50

    // MARK: Per-line hash

    /// Compute the staleness hash of a single line.
    ///
    /// The line is hashed with leading and trailing *horizontal* whitespace
    /// (spaces and tabs) stripped but interior whitespace preserved, then reduced
    /// `mod 256`. The result is a coarse fingerprint: 256 distinct values are
    /// enough to detect that a line's content changed, not to uniquely identify
    /// it; the line number disambiguates hash collisions.
    ///
    /// Re-indenting a line (changing only leading/trailing horizontal
    /// whitespace) yields the same hash; changing interior content differs.
    ///
    /// - Parameter line: the line text (line terminator excluded).
    /// - Returns: the low byte of the CRC-32 of the trimmed line bytes.
    static func hashLine(_ line: String) -> UInt8 {
        let trimmed = trimHorizontal(line)
        return UInt8(crc32(Array(trimmed.utf8)) & lowByteMask)
    }

    /// The number of hexadecimal digits an anchor's line-content hash occupies.
    ///
    /// The line hash is a single byte, so it renders as (and parses back from)
    /// exactly two hex characters. ``renderHash(_:)`` pads to this width and
    /// ``parseAnchor(_:)`` requires exactly this many hex digits, so the anchor
    /// dialect's hash width is defined in one place.
    private static let hashHexDigits = 2

    /// The radix an anchor's hash digits parse under: hexadecimal.
    private static let hexRadix = 16

    /// Render a hash byte as two lowercase hexadecimal characters.
    ///
    /// For example, `0xa3` renders as `"a3"` and `0x0f` as `"0f"`.
    ///
    /// - Parameter hash: the hash byte to render.
    /// - Returns: two lowercase hexadecimal characters.
    static func renderHash(_ hash: UInt8) -> String {
        String(format: "%0\(hashHexDigits)x", hash)
    }

    // MARK: Tagging

    /// Annotate each line of `content` with a hashline anchor.
    ///
    /// Each line becomes `N:HH|line`, where `N` is the absolute 1-based line
    /// number (the first line is `startingAtLine`) and `HH` is ``renderHash(_:)``
    /// of ``hashLine(_:)``. Line endings present in `content` (`\n`, `\r\n`,
    /// `\r`, or a mix) are preserved exactly.
    ///
    /// - Parameters:
    ///   - content: the raw file content, terminators intact.
    ///   - startingAtLine: the 1-based line number assigned to the first line.
    /// - Returns: the tagged content as a single string.
    static func tag(lines content: String, startingAtLine: Int) -> String {
        var out = ""
        for (offset, line) in splitLines(content).enumerated() {
            let n = startingAtLine + offset
            out +=
                "\(n)\(anchorLineHashDelimiter)\(renderHash(hashLine(line.text)))\(anchorTextDelimiter)\(line.text)\(line.terminator)"
        }
        return out
    }

    /// The 1-based line number the first line of whole-file tagged content is numbered from.
    private static let firstTaggedLineNumber = 1

    /// Tag `content` with absolute hashline anchors, one entry per physical line.
    ///
    /// Composes ``tag(lines:startingAtLine:)`` from the first line with
    /// ``splitLines(_:)``, returning the per-line tagged text a whole-file
    /// hashline read renders — the single rendering `write file` and `edit file`
    /// both build their result envelopes from, so a chained `edit file` resolves
    /// against identical anchors without an intervening read.
    ///
    /// - Parameter content: the content to tag.
    /// - Returns: the tagged lines, empty for empty content.
    // The read verb card (^d3px093) makes `tools.files.read` render this;
    // until that card lands, no code in this package calls it.
    // periphery:ignore
    static func taggedLines(of content: String) -> [String] {
        splitLines(tag(lines: content, startingAtLine: firstTaggedLineNumber)).map(\.text)
    }

    // MARK: Whole-file freshness token

    /// Compute the whole-file freshness token as the lowercase-hex MD5 digest of the full file bytes.
    ///
    /// This is the `#hash:` token the `read file` tool surfaces and the write /
    /// edit guards re-derive from on-disk bytes to detect whole-file staleness.
    /// MD5 is used purely for change detection (not security), mirroring the Rust
    /// `whole_file_hash` (`format!("{:x}", md5::compute(bytes))`).
    ///
    /// - Parameter bytes: the full on-disk file bytes.
    /// - Returns: a 32-character lowercase hex string.
    static func wholeFileHash(bytes: Data) -> String {
        Insecure.MD5.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
    }

    // MARK: Anchor parsing

    /// The delimiter separating an anchor's `N:HH` head from its optional `|text` suffix.
    ///
    /// Shared by ``tag(lines:startingAtLine:)``, ``parseAnchor(_:)``, and
    /// ``resolveAnchor(_:in:)`` so the dialect is defined in one place.
    private static let anchorTextDelimiter: Character = "|"

    /// The delimiter separating an anchor's line number from its content hash in the `N:HH` head.
    ///
    /// Shared by ``tag(lines:startingAtLine:)`` and ``parseAnchor(_:)`` so the
    /// dialect is defined in one place.
    private static let anchorLineHashDelimiter: Character = ":"

    /// Parse a hashline anchor in the `N:HH` format.
    ///
    /// Returns the 1-based line number and hash. An optional `|text` suffix is
    /// tolerated and ignored here (the caller uses the text for verification or
    /// fallback; see ``resolveAnchor(_:in:)``).
    ///
    /// - Parameter anchorString: the anchor to parse, in the dialect `N:HH` with
    ///   an optional `|text` suffix.
    /// - Returns: the 1-based `line` number and `hash` byte, or `nil` for
    ///   anything that is not a well-formed anchor: the line must parse as a Rust
    ///   `usize` (an optional single leading `+` then a non-empty run of ASCII
    ///   decimal digits — `-` and whitespace rejected) and the hash must be
    ///   exactly two hex digits.
    static func parseAnchor(_ anchorString: String) -> (line: Int, hash: UInt8)? {
        // Strip an optional `|text` suffix; the text is ignored here.
        let anchor: Substring =
            anchorString.firstIndex(of: anchorTextDelimiter).map { anchorString[anchorString.startIndex..<$0] }
            ?? Substring(anchorString)
        guard let colon = anchor.firstIndex(of: anchorLineHashDelimiter) else { return nil }
        let number = anchor[anchor.startIndex..<colon]
        let hex = anchor[anchor.index(after: colon)...]
        guard !number.isEmpty, hex.count == hashHexDigits else { return nil }
        // Match Rust `usize::from_str`: allow one optional leading `+`, then a
        // non-empty ASCII digit run. `-`, whitespace, and non-digits are rejected.
        var digits = number
        if digits.first == "+" { digits = digits.dropFirst() }
        guard !digits.isEmpty,
            digits.allSatisfy({ $0.isASCII && ("0"..."9").contains($0) }),
            let line = Int(digits)
        else { return nil }
        guard let hash = UInt8(hex, radix: hexRadix) else { return nil }
        return (line, hash)
    }

    // MARK: Anchor resolution

    /// Resolve a hashline anchor string against `content`, tolerating small drift.
    ///
    /// Returns the **1-based** line number whose content hashes to the anchor's
    /// hash, or `nil` when the anchor is stale/unresolvable.
    ///
    /// The `anchor` carries the dialect `N:HH` with an optional `|text` suffix;
    /// the suffix (when present) is used to verify/relocate — see
    /// ``resolveAnchorIn(_:line:hash:text:)`` for the exact rule. A caller that
    /// gets `nil` should fall through to literal interpretation rather than
    /// misapply.
    ///
    /// - Parameters:
    ///   - anchor: the hashline anchor, in the dialect `N:HH` with an optional
    ///     `|text` suffix.
    ///   - content: the text to resolve the anchor against.
    /// - Returns: the **1-based** line number the anchor resolves to, or `nil`
    ///   when the anchor is malformed, stale, or unresolvable.
    static func resolveAnchor(_ anchor: String, in content: String) -> Int? {
        guard let (line, hash) = parseAnchor(anchor) else { return nil }
        let text: String? = anchor.firstIndex(of: anchorTextDelimiter).map {
            String(anchor[anchor.index(after: $0)...])
        }
        return resolveAnchorIn(content, line: line, hash: hash, text: text)
    }

    /// Resolve a hashline anchor to a **1-based** line number, tolerating small drift.
    ///
    /// Returns the line number whose content hashes to `hash`.
    ///
    /// Resolution order:
    /// 1. The exact 1-based `line`, if its content hashes to `hash`.
    /// 2. A proximity search expanding symmetrically outward from `line` (deltas
    ///    `+1, -1, +2, -2, …` up to ``proximityWindow`` lines on each side),
    ///    taking the first line that hashes to `hash`.
    ///
    /// The optional `text` is a verification/tie-breaker: when present, a
    /// candidate (exact or in-window) whose trimmed line text equals the trimmed
    /// `text` is preferred over a merely-hash-matching candidate, scanning
    /// outward from `line`. If `text` matches no in-window candidate, resolution
    /// falls back to the nearest hash-matching line (text is a fallback, not a
    /// hard gate). When **nothing** in the window hashes to `hash`, returns `nil`.
    ///
    /// `line == 0` (or any non-positive line) is treated as "no exact candidate"
    /// and the search proceeds from the first line. Performs no IO.
    ///
    /// - Parameters:
    ///   - content: the text to resolve the anchor against.
    ///   - line: the anchor's 1-based line number; `0` or negative means "no
    ///     exact candidate".
    ///   - hash: the content hash a candidate line must match.
    ///   - text: the optional `|text` suffix used to verify/relocate a candidate;
    ///     `nil` when the anchor carried no text.
    /// - Returns: the **1-based** line number the anchor resolves to, or `nil`
    ///   when nothing in the proximity window hashes to `hash`.
    static func resolveAnchorIn(_ content: String, line: Int, hash: UInt8, text: String?) -> Int? {
        let lines = splitLines(content).map(\.text)
        return resolveIndex(lines, line: line, hash: hash, text: text).map { $0 + 1 }
    }

    /// Resolve a hashline anchor to a **0-based** index into `lines`.
    ///
    /// `lines` holds the per-line texts of the content (terminators excluded).
    /// Shared core for the resolution entry points; mirrors the Rust
    /// `resolve_index`.
    private static func resolveIndex(_ lines: [String], line: Int, hash: UInt8, text: String?) -> Int? {
        func hashMatches(_ index: Int) -> Bool {
            index >= 0 && index < lines.count && hashLine(lines[index]) == hash
        }
        func textMatches(_ index: Int) -> Bool {
            guard let wanted = text, index >= 0, index < lines.count else { return false }
            return trimHorizontal(lines[index]) == trimHorizontal(wanted)
        }

        // The exact line as a 0-based index; `line <= 0` -> no exact candidate.
        let exact: Int? = line >= 1 ? line - 1 : nil
        let center = exact ?? 0

        // Visit candidates in proximity order, recording the nearest hash match
        // and the nearest text-confirmed hash match. The exact line is delta 0.
        var nearestHash: Int?
        var nearestText: Int?
        func consider(_ candidate: Int) {
            guard candidate >= 0, hashMatches(candidate) else { return }
            if nearestHash == nil { nearestHash = candidate }
            if nearestText == nil, textMatches(candidate) { nearestText = candidate }
        }

        if exact != nil { consider(center) }
        for delta in 1...proximityWindow {
            consider(center + delta)
            consider(center - delta)
        }

        // Prefer a text-confirmed candidate; otherwise the nearest hash match.
        return nearestText ?? nearestHash
    }

    // MARK: Line splitting

    /// A single line of content paired with its original terminator.
    ///
    /// The ``text`` excludes the terminator; the ``terminator`` is the sequence
    /// that followed it (`\n`, `\r\n`, `\r`, or `""` for a final unterminated
    /// line). Splitting and then concatenating `text + terminator` over every
    /// line reproduces the original content exactly.
    struct Line {
        /// The line text, excluding its terminator.
        let text: String

        /// The line's original terminator, or `""` for a final unterminated line.
        let terminator: String
    }

    /// Split `content` into physical lines, preserving each line's original terminator.
    ///
    /// Mirrors the Rust `split_lines`: scans over Unicode scalars (not
    /// graphemes, so `\r\n` is treated as two scalars — a bare `\r` and a `\n` —
    /// exactly as the Rust byte scan does, rather than as a single grapheme
    /// cluster). Empty content yields no lines; content ending in a terminator
    /// yields no phantom trailing empty line. This is the single line model the
    /// hashline anchors emitted by ``tag(lines:startingAtLine:)`` are numbered
    /// against, so windowing callers split with the same rule the anchors use.
    ///
    /// - Parameter content: the text to split into physical lines.
    /// - Returns: the physical lines in order, each paired with its original
    ///   terminator; empty for empty content.
    static func splitLines(_ content: String) -> [Line] {
        var result: [Line] = []
        let scalars = content.unicodeScalars
        let end = scalars.endIndex
        var i = scalars.startIndex
        var lineStart = i

        func text(upTo index: String.UnicodeScalarView.Index) -> String {
            String(String.UnicodeScalarView(scalars[lineStart..<index]))
        }

        while i < end {
            guard let terminator = Self.lineTerminator(in: scalars, at: i, end: end) else {
                i = scalars.index(after: i)
                continue
            }
            result.append(Line(text: text(upTo: i), terminator: terminator))
            i = scalars.index(i, offsetBy: terminator.unicodeScalars.count)
            lineStart = i
        }
        if lineStart < end {
            result.append(Line(text: text(upTo: end), terminator: ""))
        }
        return result
    }

    /// The line terminator beginning at `index`, or `nil` when ordinary text sits there.
    ///
    /// Recognizes the three terminators the line model preserves — `\n`, `\r\n`,
    /// and a lone `\r` — with `\r\n` taking precedence over the bare `\r` so a
    /// CRLF is never split into two lines. Isolating that decision here reduces
    /// ``splitLines(_:)``'s loop to a flat "terminator or not" fork instead of
    /// an if / else-if chain with a third case nested inside it.
    ///
    /// - Parameters:
    ///   - scalars: the content's Unicode scalars.
    ///   - index: the position to test; must be within `scalars`.
    ///   - end: the scalars' end index.
    /// - Returns: the terminator sequence found at `index`, or `nil` when the
    ///   scalar there is ordinary text. The returned string's scalar count is
    ///   exactly how far a scan advances past it.
    private static func lineTerminator(
        in scalars: String.UnicodeScalarView,
        at index: String.UnicodeScalarView.Index,
        end: String.UnicodeScalarView.Index
    ) -> String? {
        switch scalars[index] {
        case "\n":
            return "\n"
        case "\r":
            let next = scalars.index(after: index)
            return next < end && scalars[next] == "\n" ? "\r\n" : "\r"
        default:
            return nil
        }
    }

    // MARK: Internals

    /// Trim leading and trailing horizontal whitespace (spaces and tabs), preserving interior content.
    ///
    /// Mirrors Rust's
    /// `trim_matches([' ', '\t'])`, which trims per *scalar* (`char`), not per
    /// grapheme cluster — so a leading space immediately followed by a combining
    /// mark trims the space and keeps the bare mark. Scanning scalars keeps this
    /// consistent with ``splitLines(_:)``'s character model.
    private static func trimHorizontal<S: StringProtocol>(_ s: S) -> String {
        var scalars = Substring(s).unicodeScalars
        while let first = scalars.first, first == " " || first == "\t" { scalars = scalars.dropFirst() }
        while let last = scalars.last, last == " " || last == "\t" { scalars = scalars.dropLast() }
        var out = ""
        out.unicodeScalars.append(contentsOf: scalars)
        return out
    }

    /// The number of bits in one byte, the width the CRC-32 table is indexed by.
    private static let bitsPerByte = 8

    /// The number of entries in the CRC-32 lookup table: one per distinct byte value.
    private static let crc32TableSize = 1 << bitsPerByte

    /// The mask selecting the low byte of a CRC-32 register.
    private static let lowByteMask: UInt32 = 0xff

    /// The reflected IEEE CRC-32 generator polynomial.
    private static let crc32Polynomial: UInt32 = 0xEDB8_8320

    /// The IEEE CRC-32 register initialization and final-XOR value.
    ///
    /// The reflected CRC-32 (`crc32fast`) both seeds the register with and XORs
    /// the final result against this value.
    private static let crc32XOROut: UInt32 = 0xFFFF_FFFF

    /// The precomputed IEEE CRC-32 lookup table.
    ///
    /// Standard reflected CRC-32 (polynomial ``crc32Polynomial``, init/xorout
    /// ``crc32XOROut``) — the algorithm `crc32fast` implements, so
    /// ``hashLine(_:)`` matches the Rust crate bit-for-bit.
    private static let crc32Table: [UInt32] = (0..<crc32TableSize).map { index in
        var c = UInt32(index)
        for _ in 0..<bitsPerByte {
            c = (c & 1) != 0 ? (crc32Polynomial ^ (c >> 1)) : (c >> 1)
        }
        return c
    }

    /// The reflected IEEE CRC-32 of a byte sequence, table-driven one byte at a time.
    ///
    /// - Parameter bytes: the bytes to checksum.
    /// - Returns: the CRC-32 of `bytes`.
    private static func crc32(_ bytes: [UInt8]) -> UInt32 {
        var crc = crc32XOROut
        for byte in bytes {
            let index = Int((crc ^ UInt32(byte)) & lowByteMask)
            crc = crc32Table[index] ^ (crc >> bitsPerByte)
        }
        return crc ^ crc32XOROut
    }
}
