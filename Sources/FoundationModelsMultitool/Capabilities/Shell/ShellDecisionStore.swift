// `ShellDecisionStore` — the remembered "always" answers to a permission
// question.
//
// A permission question offers four kinds of answer. Two of them,
// `allow_always` and `reject_always`, ask the tool to remember. To remember
// them is the work of this layer, because this layer owns the shell
// configuration. Thus they live here.
//
// ## Where an answer goes
//
// There are three scopes. They agree with the layers of the configuration
// exactly (`ShellDotfolder`):
//
//   * `.session` — in memory, for the life of the store. **This is the
//     default**, and it is the only scope that the caller does not select.
//   * `.project` — `{git_root}/.shell/decisions.yaml`, beside the
//     `config.yaml` of that layer.
//   * `.user` — `$XDG_CONFIG_HOME/shell/decisions.yaml` (or
//     `~/.config/shell/decisions.yaml`), beside the `config.yaml` of that
//     layer.
//
// The session scope is the default because a written answer is a permanent
// grant. A permanent grant must be a thing that the caller asked for on behalf
// of the user. It must never occur because the caller left the scope out.
//
// The store reads each written layer again at each lookup. It keeps no copy.
// This is the same contract that `ShellPolicy` gives its configuration. Thus a
// change to a decisions file, or the removal of one, has an immediate effect,
// and to cancel an answer is only to remove a line.
//
// ## Two layers that disagree: the refusal wins
//
// A lookup reads all three scopes. If **one** of them holds `reject_always`,
// the answer is to refuse, whatever the other scopes hold. The result does not
// depend on the order of the scopes, by construction. Thus there is no rule of
// precedence to get wrong later.
//
// This difference is on purpose. The project layer stands *inside the
// repository*. A repository that you clone can thus carry a
// `.shell/decisions.yaml` that its author wrote. Because a refusal wins,
// content from a repository cannot cancel a "never do this" that the user
// wrote for themselves. It does not correct the opposite case: an
// `allow_always` from a repository is still an approval that the user never
// gave. That is the same limit of trust that the project `config.yaml` already
// has — a `permit:` pattern from a repository can already cancel a built-in
// refusal. It is also why to write an answer is an explicit choice of the
// caller, and why the default scope writes no file.
//
// ## The match key, and why it is this narrow
//
// The store keys a remembered answer on `matchKey(for:)`. The key matches
// **that command and no other command**. There is no wildcard match, no prefix
// match, and no pattern syntax on this path. Those live in `config.yaml`, where
// a person wrote them on purpose and can read them again.
//
// The threat is the key that matches too much. An `allow_always` that matches
// more than the user believed they approved is a permission that they never see
// again: the question does not come back, thus there is no moment at which they
// can notice.
//
// A prefix match would make an approval of `git status` cover
// `git status; rm -rf ~`. A pattern taken from the first word would make an
// approval of `npm test` cover `npm publish`. Both are silent increases of
// permission, and both are worse than the failure that they prevent, which is
// one more question only.
//
// Thus the store removes only text that the shell itself does not read, and it
// stops the moment that this is hard to establish. It collapses a command only
// if the command is one line **and** carries none of `'`, `"`, a backtick,
// `\`, or `$`. It keys each other command word for word, cut at the two ends
// and changed in no other way:
//
//   * **A command of several lines** carries structure — an embedded Python
//     script, the body of a here-document, a recipe of the Makefile kind —
//     where the indentation is content and selects the control flow. It is not
//     the separation of tokens.
//   * **A command that uses shell quoting, escapes, or expansion.** An earlier
//     revision tried to be cleverer here. It collapsed only the runs that it
//     believed stood outside quotes. It was wrong two times, and both faults
//     increased permission: quoting *starts again* inside `$( )`, thus
//     `rm "$(echo "my  file")"` and `rm "$(echo "my file")"` collapsed
//     together although they remove different files; and `$'…'` reads `\'`,
//     thus `rm $'my\'  file'` and `rm $'my\' file'` did the same. To get this
//     right means to lex the shell, and a lexer that is a little wrong gives
//     approvals that nobody gave. To stop costs one more question, which the
//     paragraph above already names as the failure worth having.
//
// The test that stops the collapse runs over **Unicode scalars, and not over
// `Character`s**. A Swift `Character` is a grapheme cluster. Thus `"` with a
// combining mark after it is one `Character` that equals neither of them, and a
// membership test on a `Set<Character>` misses it. Bash reads bytes: it sees
// the quote, it opens a quoted region, and `rm "\u{0308}my  file"\u{0308}`
// removes a different file from `rm "\u{0308}my file"\u{0308}`. Keyed for each
// `Character`, the two collapsed together, which is the same increase of
// permission in new clothes.
//
// What stays is the pair that the design needs: `npm test` and `npm  test` are
// one answer, because in a command with no quoting at all each run of spaces
// and tabs is the word separation that the shell discards. The store folds no
// case either: the shell, its `$PATH` lookups, and its arguments all read the
// case, thus `npm` and `NPM` are different commands.
//
// The cut at the two ends uses exactly the default `IFS` of bash — space, tab,
// newline — and nothing else. It is not `.whitespacesAndNewlines`, which would
// remove U+00A0 and the U+2000 block, and it does **not** include the carriage
// return. Bash splits on none of those, thus each one belongs to the word
// beside it. `echo a\u{00A0}` passes an argument that `echo a` does not, and
// `rm foo\r` removes a file named `foo\r`.
//
// Even inside `IFS`, the cut at the *end* has three hazards. All three have the
// same shape: text at the end that looks like separation, and that the shell
// reads.
//
//   * **A backslash escapes the whitespace that comes after it**, and thus
//     makes that whitespace into argument text. `touch bar\ ` makes a file
//     named `bar `, and `touch bar\` makes one named `bar`.
//   * **The delimiter of a here-document must match its line exactly.** One
//     space at the end leaves the here-document open, thus the line that was
//     the delimiter becomes body — and the body runs. `sh <<END⏎echo hi⏎END`
//     runs `echo hi`; the same text with one space at the end runs `echo hi`
//     *and* `END`. That is not one command in two spellings. It is one more
//     execution under the approval of the other one.
//   * **Empty lines at the end are the body of a here-document.** `cat <<EOF`
//     writes nothing; `cat <<EOF⏎⏎` writes one newline, because the empty line
//     that the cut would remove *is* the body. This one bit even with the guard
//     for several lines in place, because that guard examines what stays
//     *after* the removal of the run at the end — and with the operator on the
//     only line, what stays is one line. It is milder than the delimiter case,
//     because each line that such a run can add is whitespace only and thus no
//     new command can run. It is still two commands with different effects
//     under one approval.
//
// Cut without care, each pair keys the same. To decide whether a backslash at
// the end is a live escape, which line is a delimiter, or where a body ends
// means to lex the shell again. Thus the store simply keeps the run at the end
// whenever its removal would leave the key with a backslash at the end, would
// leave a key that still spans more than one line, or would leave a key that
// contains `<<`. That last test is a plain substring test and it fires too
// often on purpose: `echo "a<<b"` and `cat <<< x` open no here-document, and to
// keep their whitespace at the end only splits one answer into two, which is
// the direction that this design already accepts. The whitespace at the start
// has none of these cases: nothing can stand before position zero to escape it,
// and an empty line at the start does nothing.
//
// The store keeps the key as readable command text, and not as a digest. Thus
// `decisions.yaml` is open to audit — a user can open it, see exactly what they
// approved, and remove the line. That clarity is how a user cancels an answer,
// and it is worth a file that holds command text.
//
// ## What the store does with a fault
//
// A decisions file that the store cannot read or cannot parse makes a
// **warning**. It does not fail without a sound. This is the opposite of the
// quiet fall-back of the configuration layer, and it is on purpose: a
// configuration that does not read falls back to the stricter built-in rules,
// but a decisions file that does not read would drop a `reject_always` and thus
// fail *open*.
//
// For the same reason the store decodes each entry on its own, and not the file
// as a whole. One value that it does not know must not cancel the
// `reject_always` on the line beside it. Thus the store sets an unknown entry
// aside, warns about that entry, and writes it out again unchanged at the next
// save.
//
// ## Two writers at one time, and what the store truly promises
//
// To record into a written scope is a read-modify-write of the *whole* file of
// the layer: read each entry, replace one, write them all again. Two of those
// that interleave lose an entry, and the lost entry can be a `reject_always` —
// a silent fail-open, which is the failure that the section above refuses to
// accept from a corrupt file. Thus the store serializes the window two times
// over, and the two promises differ in strength on purpose:
//
//   * **Inside this process the promise holds for any two spellings of one
//     layer file that the resolution of symbolic links can tell apart.** Each
//     write to a given layer file takes a lock that covers the whole process.
//     The key of that lock is `lockURL(forDecisionsAt:)` — the *resolved*
//     directory of that file plus its leaf name, and not the raw path. The
//     write takes the lock before it reads, and holds it until the replacement
//     lands. Two `ShellPolicy` values built over the same layer cannot
//     interleave, whether through the same path, through a symbolic link to
//     the layer *directory*, or through two threads that share one value. What
//     this does not catch: two paths that reach one file by a *hard* link, two
//     spellings that differ in case only on a volume that ignores case, or a
//     `decisions.yaml` leaf that is itself a symbolic link to a different file.
//     The key resolves the directory only, and never the leaf, thus that last
//     case is a miss here that `storageIdentity(of:)` below does not share once
//     the file is there. See `lockURL(forDecisionsAt:)` for why the key has
//     this shape and for the cost that it leaves.
//   * **Across processes the promise is best effort, and each side must
//     co-operate.** The same window also runs under an exclusive `flock` on a
//     sidecar `decisions.yaml.lock`. That excludes any other process that takes
//     the same lock — two agents that share the user layer, most of all. It
//     uses a sidecar, and not the file itself, because the write is an atomic
//     replace: it renames a new file over the old one, thus a lock on the old
//     inode would guard nothing after the rename.
//
// The sidecar is a **permanent** empty file, and not a temporary one. The store
// makes it at the first attempt to write and never removes it. It never removes
// it on purpose: to remove it while another holder has it open is one of the
// hazards below, thus the store leaves it in place. The sidecar also appears
// after an attempt to write that the store *refuses*, because the store must
// hold the lock before the read that refuses. Thus a `remember` that throws
// `unreadableDecisionsFile` leaves the `decisions.yaml` of the user byte for
// byte the same, but it does add the sidecar beside it. In the project layer
// that file lands inside the repository, beside a `decisions.yaml` that a user
// can be committing. Thus it is worth a line in `.gitignore`.
//
// What the store does **not** promise, stated and not implied:
//
//   * Nothing here excludes a writer that does not take the lock — a text
//     editor, a shell redirect, another implementation. `flock` is advisory,
//     and this is a plain file that a user is welcome to edit.
//   * On a file system where `flock` does not work (some network mounts) the
//     promise inside the process is the only one that stays. That makes a
//     warning and goes ahead, because to refuse to record the answer of the
//     user would be the worse result.
//   * To remove the `.lock` file while a holder has the lock breaks the
//     exclusion: the next writer makes a new file and locks a different inode.
//   * Nothing serializes the gap *between* a read through `decision(for:)` and
//     a later `remember`. A caller that reads, decides, and then writes can
//     still lose a race in that gap. The store protects the write window only.
//   * **A record has no time limit.** Both locks block, thus a holder that
//     never ends blocks the caller for as long as it holds on. `remember` is
//     synchronous, thus on a cooperative thread of Swift it occupies a thread
//     that the runtime does not replace, and enough of those starve each other
//     task in the process. Leave that pool to call it:
//     `DispatchQueue.global().async`, a `Thread` of its own, or a continuation
//     that one of those resumes. **`Task.detached` does not do this** — it runs
//     on the same global cooperative executor as `Task {}` and differs only in
//     that it does not inherit the actor context, the priority, and the
//     task-locals. Thus to block inside it pins a cooperative thread exactly as
//     to block anywhere else does. The other choice — an attempt that does not
//     block, that gives up and writes anyway — is refused, because it brings
//     back exactly the lost-`reject_always` race under exactly the contention
//     that the lock exists for.
//   * The `warn` sink runs **inside** the critical section, because the read
//     that it reports on occurs under the lock. A sink that calls `remember`
//     again for the same layer deadlocks, and a slow sink holds the lock.
//     Warnings also repeat: to record an `allowAlways` reads the layer files
//     one time for the gate and again for the write, thus a file with an
//     unknown entry warns about that entry more than one time for each call.
//     Both are the cost of a store that keeps no copy of a decisions file,
//     which is what makes a hand edit take effect at once.
//
// A reader never waits, and never must: the replacement is atomic, thus a
// lookup sees either the whole old file or the whole new one.

import Darwin
import Foundation
import Synchronization
import Yams

/// The shape on disk of the `decisions.yaml` of one layer.
///
/// The decode runs **for each entry**, and not for the file as a whole. A value
/// that the current code does not know — a hand-written `allow_once`, which is
/// a real kind of answer but not a remembered one — lands in `unrecognized`
/// instead of failing the whole file. Anything else would let one typing
/// mistake cancel a `reject_always` on the line above it, which is a fail-open
/// on the entry that matters most.
///
/// The next write carries each `unrecognized` entry back out. Thus a rewrite
/// never destroys text that the user typed without a sound, and the warning
/// about it keeps coming until they correct it. One level up, `remember`
/// applies the same promise to a file that does not parse **at all**: it
/// refuses the write instead of replacing the file with one entry.
struct ShellDecisionFile: Sendable, Equatable {
    /// Match key to remembered answer, for each value that this code
    /// understands.
    var decisions: [String: ShellDecisionStore.Decision]
    /// Match key to raw value, for each value that it does not understand.
    var unrecognized: [String: String]

    /// Makes a record of one file.
    ///
    /// - Parameters:
    ///   - decisions: Match key to remembered answer.
    ///   - unrecognized: Match key to raw value, for each value outside
    ///     `Decision`.
    init(
        decisions: [String: ShellDecisionStore.Decision],
        unrecognized: [String: String] = [:]
    ) {
        self.decisions = decisions
        self.unrecognized = unrecognized
    }
}

extension ShellDecisionFile: Codable {
    /// The coding keys of the one mapping of the file.
    enum CodingKeys: String, CodingKey {
        case decisions
    }

    /// Decodes a record of one file. It reads an absent `decisions:` key as
    /// empty, and it sorts each entry by whether the value of that entry names
    /// a known `Decision`.
    ///
    /// - Parameter decoder: The decoder to read from.
    /// - Throws: When the YAML is not a mapping, or when `decisions:` is there
    ///   but is not a map of strings to strings.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let raw =
            try container.decodeIfPresent([String: String].self, forKey: .decisions) ?? [:]
        decisions = [:]
        unrecognized = [:]
        for (key, value) in raw {
            if let decision = ShellDecisionStore.Decision(rawValue: value) {
                decisions[key] = decision
            } else {
                unrecognized[key] = value
            }
        }
    }

    /// Encodes both halves back into the one `decisions:` mapping. Thus a value
    /// that this code could not read comes through the round trip unchanged.
    ///
    /// - Parameter encoder: The encoder to write to.
    /// - Throws: When the encode fails.
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(
            decisions.mapValues(\.rawValue).merging(unrecognized) { current, _ in current },
            forKey: .decisions)
    }
}

/// The remembered `allow_always` and `reject_always` answers, in layers like
/// the configuration.
///
/// See the header of this file for the scopes, for the rule that a refusal
/// wins, and for the threat model of the match key. All three are security
/// decisions, and not details of the implementation.
///
/// A reference type, thus each copy of the `ShellPolicy` value that holds one
/// shares the same session answers.
public final class ShellDecisionStore: Sendable {
    /// A remembered "always" answer to a permission question.
    ///
    /// These are the two kinds that persist. The one-shot kinds
    /// (`allow_once` and `reject_once`) are not here: by definition nothing
    /// remembers them, thus they never reach this store.
    public enum Decision: String, Sendable, Codable {
        /// Run this command from now on, and do not ask again.
        case allowAlways = "allow_always"
        /// Refuse this command from now on, and do not ask again.
        case rejectAlways = "reject_always"
    }

    /// Where the store keeps a remembered answer.
    public enum Scope: Sendable, Hashable {
        /// In memory, for the life of this store. It writes to no file. This is
        /// the default, and it does not persist.
        case session
        /// `{git_root}/.shell/decisions.yaml`, beside the project
        /// configuration.
        case project
        /// `$XDG_CONFIG_HOME/shell/decisions.yaml` (or `~/.config/shell/`),
        /// beside the user configuration.
        case user
    }

    /// The decisions file of the user layer, or `nil` when there is no user
    /// layer.
    let userDecisionsURL: URL?
    /// The decisions file of the project layer, or `nil` when there is no
    /// project layer — outside a git working tree, for one.
    let projectDecisionsURL: URL?
    /// The sink for an advisory warning, most of all a decisions file that the
    /// store cannot read.
    ///
    /// The store calls it on the thread of the caller. For a write that
    /// persists, it calls the sink **inside** the lock that it holds across the
    /// read-modify-write. The sink must not call `remember` again for the same
    /// layer — that deadlocks — and a slow sink delays each other writer of
    /// that layer. See the header of this file.
    let warn: @Sendable (String) -> Void
    /// The session answers: match key to decision, for the life of this store.
    private let sessionDecisions = Mutex<[String: Decision]>([:])

    /// The default warning sink: one line for each warning, to stderr.
    ///
    /// The shell policy layer shares this sink. A type in that layer that wants
    /// a default sink must use this one, and must not declare a second one.
    public static let stderrWarn: @Sendable (String) -> Void = { message in
        FileHandle.standardError.write(Data("shell policy warning: \(message)\n".utf8))
    }

    /// Makes a store over the given written layers.
    ///
    /// It is public so that a host owns where the answers persist. The host
    /// passes whatever URLs it selects, or `nil` for a layer that it does not
    /// want to persist at all, which makes each answer a session answer in
    /// effect. Nothing here takes a path from a `config.yaml`.
    ///
    /// - Parameters:
    ///   - userDecisionsURL: The decisions file of the user layer, or `nil` for
    ///     no user layer.
    ///   - projectDecisionsURL: The decisions file of the project layer, or
    ///     `nil` for no project layer.
    ///   - warn: The advisory warning sink. The default writes to stderr.
    public init(
        userDecisionsURL: URL?, projectDecisionsURL: URL?,
        warn: @escaping @Sendable (String) -> Void = ShellDecisionStore.stderrWarn
    ) {
        self.userDecisionsURL = userDecisionsURL
        self.projectDecisionsURL = projectDecisionsURL
        self.warn = warn
    }

    // MARK: - Lookup

    /// The remembered answer for `command`, resolved across all three scopes.
    ///
    /// The refusal wins: a `rejectAlways` in any scope is the answer, whatever
    /// the other scopes hold. If no scope refuses, an `allowAlways` in any
    /// scope is the answer.
    ///
    /// - Parameter command: The text of the shell command.
    /// - Returns: The remembered answer, or `nil` when no scope holds one.
    func decision(for command: String) -> Decision? {
        let remembered = decisionsByScope(for: command)
        if remembered.values.contains(.rejectAlways) { return .rejectAlways }
        // Each answer that stays is an `allowAlways`. Thus which one the store
        // selects cannot change the result.
        return remembered.values.first
    }

    /// The scopes that hold `decision` for `command`.
    ///
    /// This exists for the gate in `ShellPolicy.remember(_:for:in:)`. That gate
    /// must know *where* a refusal lives before it can tell whether an approval
    /// written to some other scope would have no effect, because a refusal
    /// wins.
    ///
    /// - Parameters:
    ///   - decision: The answer to look for.
    ///   - command: The text of the shell command.
    /// - Returns: The scopes that hold that answer. It is empty when no scope
    ///   holds it.
    func scopes(remembering decision: Decision, for command: String) -> Set<Scope> {
        Set(decisionsByScope(for: command).filter { $0.value == decision }.keys)
    }

    /// What each scope holds for `command`. It leaves out each scope that holds
    /// nothing.
    ///
    /// This is the one read that each lookup goes through. Thus no query can
    /// read a different set of scopes from another query.
    ///
    /// - Parameter command: The text of the shell command.
    /// - Returns: A map of scope to answer, over the scopes that hold an
    ///   answer.
    private func decisionsByScope(for command: String) -> [Scope: Decision] {
        let key = Self.matchKey(for: command)
        var remembered: [Scope: Decision] = [:]
        remembered[.session] = sessionDecisions.withLock { $0[key] }
        remembered[.user] = persistedFile(at: userDecisionsURL)?.decisions[key]
        remembered[.project] = persistedFile(at: projectDecisionsURL)?.decisions[key]
        return remembered
    }

    // MARK: - Recording

    /// Records `decision` for `command` in `scope`.
    ///
    /// A written scope reads, changes, and writes the file of the layer. Thus
    /// the write replaces an answer that already stands for the same key, and
    /// keeps each other key.
    ///
    /// This is the low-level write, and it applies no policy of its own.
    /// A caller should go through `ShellPolicy.remember(_:for:in:)`, which also
    /// refuses to write an `allowAlways` that nothing could honor — because a
    /// `deny` rule refuses the command, or because another scope already holds
    /// a refusal for it and a refusal wins across scopes.
    ///
    /// It blocks until it holds the lock of the layer. See the header of this
    /// file for the strength of that exclusion and for what it costs a caller.
    ///
    /// - Parameters:
    ///   - decision: The answer to remember.
    ///   - command: The text of the shell command that the user answered for.
    ///   - scope: Where to keep it.
    /// - Throws: `ShellPolicyError.noStorageForScope` when `scope` has no file
    ///   in the layering of this store;
    ///   `ShellPolicyError.unreadableDecisionsFile` when the file of the layer
    ///   is there but does not parse, because the write would destroy it; or a
    ///   file-system or encoding error when the write fails.
    func remember(_ decision: Decision, for command: String, in scope: Scope) throws {
        let key = Self.matchKey(for: command)
        guard scope != .session else {
            sessionDecisions.withLock { $0[key] = decision }
            return
        }
        guard let url = url(for: scope) else {
            throw ShellPolicyError.noStorageForScope(scope)
        }

        // The read, the change, and the write are one critical section. Split
        // apart, they drop the entry of a concurrent writer without a sound.
        // See the header of this file for how strong that exclusion is and
        // where it stops.
        try withExclusiveAccess(to: url) {
            guard var file = persistedFile(at: url) else {
                throw ShellPolicyError.unreadableDecisionsFile(url)
            }
            file.decisions[key] = decision
            file.unrecognized[key] = nil
            try YAMLEncoder().encode(file).write(to: url, atomically: true, encoding: .utf8)
        }
    }

    // MARK: - Serializing the read-modify-write

    /// The write locks inside this process, one for each lock-file path, made
    /// at the first use.
    ///
    /// They cover the whole process, and not one store, because the store that
    /// owns a layer file is not unique: `ShellPolicy` is a value type and a
    /// process can build several over the same `~/.config/shell`. The key is
    /// the path, thus a write to one layer never waits for a write to a
    /// different layer.
    ///
    /// The registry only grows. Its bound is the number of different layer
    /// files that a process touches, which is two in production.
    ///
    /// It is not the same thing as the `flock` below, although it looks like
    /// it. A `flock` lock belongs to an *open file description*, thus two
    /// descriptors that two threads of one process opened do exclude each
    /// other. What this adds is that the promise inside the process does not
    /// depend on a system call that succeeds — if the sidecar does not open at
    /// all (a file system with no `flock`, a limit on descriptors that load
    /// reached) this still holds, and the fall-back is weaker instead of
    /// absent. No test can disprove it on its own, for exactly that reason: to
    /// delete it turns nothing red, and nobody must delete it for that.
    private static let writeLocks = Mutex<[String: NSLock]>([:])

    /// Runs `body` with exclusive access to the layer file at `url`.
    ///
    /// Inside this process the promise holds for any two spellings of `url`
    /// that the resolution of symbolic links can tell apart — see
    /// `lockURL(forDecisionsAt:)`, whose resolved path this locks on. Across
    /// processes each side must co-operate and the promise is best effort. A
    /// failure to take the lock across processes warns and goes ahead, because
    /// a file system with no working `flock` must not cost the user the ability
    /// to record an answer at all.
    ///
    /// It makes the directory of the layer first, because the sidecar lock file
    /// lives in that directory — and the write that comes after would need it
    /// in any case.
    ///
    /// - Parameters:
    ///   - url: The decisions file of the layer.
    ///   - body: The read-modify-write to run under the lock.
    /// - Returns: Whatever `body` gives back.
    /// - Throws: A file-system error when the directory of the layer does not
    ///   create, or anything that `body` throws.
    private func withExclusiveAccess<T>(to url: URL, _ body: () throws -> T) throws -> T {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let lockPath = Self.lockURL(forDecisionsAt: url).path

        let inProcess = Self.writeLock(at: lockPath)
        inProcess.lock()
        defer { inProcess.unlock() }

        let descriptor = Self.acquireCrossProcessLock(at: lockPath)
        if descriptor == nil {
            warn(
                "could not lock \(lockPath) for writing; another process writing the same "
                    + "decisions file at the same moment could drop this answer")
        }
        defer { Self.releaseCrossProcessLock(descriptor) }

        return try body()
    }

    /// The lock inside this process that guards `path`, made at the first use.
    ///
    /// - Parameter path: The path of the lock file, used as the registry key
    ///   only.
    /// - Returns: The lock for that path, shared by each caller in this
    ///   process.
    private static func writeLock(at path: String) -> NSLock {
        writeLocks.withLock { locks in
            if let existing = locks[path] { return existing }
            let lock = NSLock()
            locks[path] = lock
            return lock
        }
    }

    /// Takes an exclusive `flock` on the sidecar at `path`. It blocks until the
    /// lock is free.
    ///
    /// - Parameter path: The path of the sidecar lock file. It makes the file
    ///   when the file is absent.
    /// - Returns: The locked descriptor, or `nil` when it could not take the
    ///   lock at all — the file did not open, or the file system does not
    ///   implement `flock`.
    private static func acquireCrossProcessLock(at path: String) -> Int32? {
        let descriptor = open(
            path, O_RDONLY | O_CREAT | O_CLOEXEC, ShellDotfolder.lockFileMode)
        guard descriptor >= 0 else { return nil }
        while flock(descriptor, LOCK_EX) != 0 {
            // A signal that arrives during the wait is not a failure to lock.
            guard errno == EINTR else {
                close(descriptor)
                return nil
            }
        }
        return descriptor
    }

    /// Releases a lock that `acquireCrossProcessLock(at:)` took.
    ///
    /// - Parameter descriptor: The locked descriptor, or `nil` when nothing
    ///   took the lock.
    private static func releaseCrossProcessLock(_ descriptor: Int32?) {
        guard let descriptor else { return }
        flock(descriptor, LOCK_UN)
        close(descriptor)
    }

    /// The scopes that keep their remembered answers in the same place as
    /// `scope` — always with `scope` itself.
    ///
    /// A scope and a file are not one to one: two layer roots can be the same
    /// place, or one can be a symbolic link to the other, and one entry then
    /// shows under both scopes. A caller that reasons about whether a write to
    /// `scope` would replace the entry of some other scope must compare files,
    /// and not cases. `.session` has no file, thus it shares with nothing else.
    ///
    /// - Parameter scope: The scope that the caller writes to.
    /// - Returns: `scope` with each other scope that the same file backs.
    func scopesSharingStorage(with scope: Scope) -> Set<Scope> {
        guard let target = Self.storageIdentity(of: url(for: scope)) else { return [scope] }
        let sharing = Self.persistedScopes.filter {
            Self.storageIdentity(of: url(for: $0)) == target
        }
        return Set(sharing).union([scope])
    }

    /// A **careful** identity for the decisions file of a layer: two identities
    /// that are equal mean one file, but two that differ can still be one file.
    ///
    /// It errs in one direction on purpose, and that direction is the safe one.
    /// It never joins two files that differ, because a resolved, standard path
    /// is unique for each different file. Thus it can never make the caller
    /// subtract a scope that the caller must keep, which is the only way that
    /// this could wrongly *permit* a write with no effect. Each thing that it
    /// gets wrong falls the other way, into a refusal of an approval that would
    /// have worked.
    ///
    /// Plain `URL` equality is too strict: `~/.config/shell` and a symbolic
    /// link that points at it are different URLs for one file, and to treat
    /// them as different makes a write that *would* replace an entry look like
    /// a write that could not. To resolve the path catches that, and the
    /// simpler case of two roots set to the same path.
    ///
    /// Three things it still misses, and all three fail closed: two paths that
    /// reach one file by a *hard* link; two spellings that differ in case only
    /// on a volume that ignores case; and a leaf that is not there yet, because
    /// `resolvingSymlinksInPath()` leaves a path alone when the full path is
    /// absent. Thus `link/decisions.yaml` and `real/decisions.yaml` resolve
    /// apart until something makes the file.
    ///
    /// That last one never reaches an answer, by an invariant that is worth a
    /// statement: this identity changes a result only for a scope that truly
    /// *holds a refusal*, and a written scope can hold one only when its file
    /// is there and parses — which is exactly the case where the resolution is
    /// complete. A shared file that one scope reads a refusal out of is there
    /// for the other scope too, by definition.
    ///
    /// The answer is also a snapshot: it does not catch a path that something
    /// re-points between this call and the write.
    ///
    /// - Parameter url: The decisions file of a layer, or `nil` for no layer.
    /// - Returns: The resolved, standard path, or `nil` when there is no layer.
    private static func storageIdentity(of url: URL?) -> String? {
        url?.resolvingSymlinksInPath().standardizedFileURL.path
    }

    /// The scopes that have a file at all, for `scopesSharingStorage` to
    /// compare across.
    private static let persistedScopes: [Scope] = [.user, .project]

    /// The file that backs `scope`.
    ///
    /// - Parameter scope: The scope to locate.
    /// - Returns: The decisions file, or `nil` for `.session`, which has none
    ///   by definition, and for a layer that this store did not receive.
    func url(for scope: Scope) -> URL? {
        switch scope {
        case .session: nil
        case .project: projectDecisionsURL
        case .user: userDecisionsURL
        }
    }

    /// The sidecar file that a writer takes an exclusive `flock` on while it
    /// rewrites `url`. It is also the path that `writeLock(at:)` keys the
    /// registry of locks inside the process on.
    ///
    /// It resolves the symbolic links in the *containing directory* of `url`
    /// and adds the leaf name again. It does not resolve the whole path, as
    /// `storageIdentity(of:)` does. The two cannot share one implementation:
    /// `withExclusiveAccess(to:)` calls this before the decisions file of the
    /// layer is necessarily there — the first write to a layer makes it — and
    /// `resolvingSymlinksInPath()` leaves the spelling of an absent leaf alone.
    /// To resolve the whole path would thus still key `link/decisions.yaml` and
    /// `real/decisions.yaml` apart on exactly that first write, which is the
    /// write where a lost `reject_always` costs the most. The directory, unlike
    /// the leaf, is there by the time this runs — `withExclusiveAccess` makes
    /// it first — thus to resolve that much joins both spellings whether or not
    /// the file itself is there yet. This was examined against a real symbolic
    /// link to a directory, and not reasoned about, because this file has a
    /// history of getting `resolvingSymlinksInPath()` wrong in that way.
    ///
    /// To resolve the directory is still unique for each different directory,
    /// thus this can join two spellings of one real file but can never join two
    /// files that truly differ. Two of its misses are the same misses that
    /// `storageIdentity(of:)` has, for the same reason: two paths that reach
    /// one file by a *hard* link, and two spellings that differ in case only on
    /// a volume that ignores case. A third miss is not shared: because this
    /// never resolves the *leaf*, a `decisions.yaml` that is itself a symbolic
    /// link to a different file keys apart here even once it is there, where
    /// `storageIdentity(of:)` would join it. That is the cost of the correction
    /// for the absent leaf — to resolve the leaf too would open that race
    /// again.
    ///
    /// - Parameter url: The decisions file of a layer.
    /// - Returns: The sidecar lock file of that file, `<decisions.yaml>.lock`
    ///   beside it, with the directory part resolved. Thus two spellings of one
    ///   layer root agree on this path even before the file is there.
    static func lockURL(forDecisionsAt url: URL) -> URL {
        let resolvedDirectory =
            url.deletingLastPathComponent()
            .resolvingSymlinksInPath()
            .standardizedFileURL
        return resolvedDirectory
            .appendingPathComponent(url.lastPathComponent + ShellDotfolder.lockFileSuffix)
    }

    /// Reads the decisions file of one layer new from disk.
    ///
    /// A file that is absent is simply empty. A file that does not read or does
    /// not parse warns, and the store reads it as empty. An entry whose value
    /// is not a known `Decision` warns on its own and leaves the entries beside
    /// it whole. See the header of this file for why any of that is loud here
    /// and quiet in the configuration layer.
    ///
    /// - Parameter url: The decisions file of the layer, or `nil` for no layer.
    /// - Returns: The parsed file of the layer; an empty file when there is
    ///   nothing to read at all; and `nil` when the file is *there but not
    ///   usable*. A reader reads `nil` as "no decisions", because the store
    ///   already warned it, and `remember` refuses to write over it, because a
    ///   read-modify-write that read nothing would replace each thing that the
    ///   user typed.
    private func persistedFile(at url: URL?) -> ShellDecisionFile? {
        let empty = ShellDecisionFile(decisions: [:])
        guard let url, FileManager.default.fileExists(atPath: url.path) else { return empty }
        guard let text = try? String(contentsOf: url, encoding: .utf8) else {
            warn("remembered decisions at \(url.path) could not be read; ignoring them")
            return nil
        }
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return empty }
        guard let file = try? YAMLDecoder().decode(ShellDecisionFile.self, from: text) else {
            warn("remembered decisions at \(url.path) could not be parsed; ignoring them")
            return nil
        }
        for (key, value) in file.unrecognized {
            warn(
                "remembered decision \(value.debugDescription) for \(key.debugDescription) in "
                    + "\(url.path) is not a recognized answer; ignoring that entry")
        }
        return file
    }

    // MARK: - The match key

    /// The scalars whose presence anywhere in a command means that the command
    /// uses shell quoting, escapes, or expansion — and thus that this type
    /// refuses to change it at all.
    ///
    /// To decide what a quote encloses means to lex the shell, and the lexer
    /// must be right about `$'…'`, about quoting that starts again inside
    /// `$( )` and inside backticks, and about which backslashes each place
    /// reads. A lexer that is a little wrong gives approvals that the user never
    /// gave, which is exactly the failure that this design exists to prevent.
    /// To stop is the honest move.
    ///
    /// These are scalars, and not `Character`s, because a `Character` is a
    /// grapheme cluster: `"` with a combining mark after it is one `Character`
    /// that equals no member of this set, but bash still reads the `"` and opens
    /// a quoted region. See the header of this file.
    private static let shellQuotingScalars: Set<Unicode.Scalar> = ["'", "\"", "`", "\\", "$"]

    /// The scalars that make a command span more than one line.
    ///
    /// It is exactly the set that `Character.isNewline` knows — CR, LF, vertical
    /// tab, form feed, NEL, and the two Unicode separators. The store examines
    /// one scalar at a time, for the same grapheme-cluster reason as
    /// `shellQuotingScalars`.
    private static let lineBreakScalars = CharacterSet.newlines

    /// The whitespace that the word splitter of bash truly reads as a
    /// separator — exactly the default `IFS`, which is space, tab, and newline.
    ///
    /// It is not `.whitespacesAndNewlines`, on purpose, and it does **not
    /// include the carriage return**, on purpose. Neither U+00A0, nor the
    /// U+2000 block, nor CR is in `IFS`, thus each one belongs to the word that
    /// it stands against: `rm foo\r` removes a file named `foo\r`, and not one
    /// named `foo`. To cut any of them would join two commands that act on
    /// different things.
    ///
    /// To leave CR out also corrects the case inside a command: a command that
    /// keeps a CR fails the `isPlain` test below, because CR is in
    /// `lineBreakScalars`, and thus the store keys it word for word instead of
    /// collapsing it.
    private static let separatorWhitespace = CharacterSet(charactersIn: " \t\n")

    /// The backslash, which escapes the whitespace that comes after it and thus
    /// turns that whitespace into argument text and not into separation.
    private static let escapeScalar: Unicode.Scalar = "\\"

    /// The redirection operator of a here-document. Its presence means that the
    /// whitespace at the end can be body text and not separation.
    ///
    /// The store matches it as a plain substring, which fires too often on
    /// `cat <<< x` and on a literal `<<` inside an argument. That is the safe
    /// direction: it splits one answer into two, and it does not join two
    /// answers into one.
    private static let heredocOperator = "<<"

    /// The key that the store remembers `command` under.
    ///
    /// Exact equality on this key is the only match that this store makes. See
    /// the header of this file for the threat model. In short, the store
    /// removes only text that the shell itself does not read, and it refuses to
    /// change anything wherever that is hard to establish.
    ///
    /// - Parameter command: The text of the shell command.
    /// - Returns: The match key: the command cut of the separator whitespace at
    ///   its two ends, with the runs of spaces and tabs inside it collapsed to
    ///   one space. The store keeps the run at the end when to remove it would
    ///   show an escaping backslash, would leave a key of more than one line, or
    ///   would leave a key that holds the operator of a here-document — see
    ///   `trimmingSeparatorWhitespace(in:)`. The store skips the collapse for a
    ///   command that spans more than one line, and for a command that holds any
    ///   character of shell quoting, escapes, or expansion.
    public static func matchKey(for command: String) -> String {
        let trimmed = trimmingSeparatorWhitespace(in: command)
        let isPlain = trimmed.unicodeScalars.allSatisfy {
            !lineBreakScalars.contains($0) && !shellQuotingScalars.contains($0)
        }
        guard isPlain else { return trimmed }
        return collapsingSeparatorRuns(in: trimmed)
    }

    /// Removes the separator whitespace at the two ends that the shell would
    /// have discarded.
    ///
    /// To remove the whitespace at the start is always safe: nothing can stand
    /// before position zero to escape it, and an empty line at the start does
    /// nothing. The run at the *end* is the dangerous end, and the store keeps
    /// it in three cases. In each case, to establish that the whitespace truly
    /// is separation means to lex the shell, and the unclear answer must be the
    /// one that costs a question and not an approval:
    ///
    ///   * **To remove it would show a backslash**, which can be escaping the
    ///     same whitespace that the store removes. `touch bar\ ` makes a file
    ///     named `bar `; `touch bar\` makes `bar`.
    ///   * **What stays still spans more than one line**, thus the last line can
    ///     be the delimiter of a here-document — and a delimiter must match its
    ///     line *exactly*. One space at the end leaves the here-document open,
    ///     which turns the delimiter into body text: `sh <<END⏎echo hi⏎END` runs
    ///     `echo hi`, and the same text with one more space also runs `END`.
    ///   * **What stays holds the operator of a here-document at all**, because
    ///     the run at the end can *be* the body. `cat <<EOF` writes nothing;
    ///     `cat <<EOF⏎⏎` writes one newline. The test for several lines above
    ///     cannot catch that one: with the operator on the only line, what stays
    ///     after the removal of the run is one line.
    ///
    /// The test for several lines runs on what *stays*, and not on the input.
    /// Thus a command whose newlines all stood at the end (`echo a⏎⏎`) still
    /// cuts down to the one-line form that it equals. The test for a
    /// here-document runs on the same remainder, and it is a substring test and
    /// not a parse — see `heredocOperator` for why to fire too often is the
    /// direction to accept.
    ///
    /// - Parameter command: The text of the shell command.
    /// - Returns: The command, cut at its two ends.
    private static func trimmingSeparatorWhitespace(in command: String) -> String {
        var scalars = command.unicodeScalars[...]
        while let first = scalars.first, separatorWhitespace.contains(first) {
            scalars = scalars.dropFirst()
        }
        var withoutTrailing = scalars
        while let last = withoutTrailing.last, separatorWhitespace.contains(last) {
            withoutTrailing = withoutTrailing.dropLast()
        }
        let trimmed = String(String.UnicodeScalarView(withoutTrailing))
        let exposesEscape = withoutTrailing.last == escapeScalar
        let stillSpansLines = withoutTrailing.contains { lineBreakScalars.contains($0) }
        let mayOpenHeredoc = trimmed.contains(heredocOperator)
        guard exposesEscape || stillSpansLines || mayOpenHeredoc else { return trimmed }
        return String(String.UnicodeScalarView(scalars))
    }

    /// Collapses the runs of spaces and tabs to one space.
    ///
    /// The store calls this only for a command that it already established to
    /// carry no quoting, no escapes, and no expansion, and to occupy one line.
    /// Thus each run of spaces and tabs in it is the word separation that the
    /// shell discards.
    ///
    /// - Parameter command: A command of one line, cut at its two ends, with no
    ///   quotes.
    /// - Returns: The command with its separator runs collapsed.
    private static func collapsingSeparatorRuns(in command: String) -> String {
        var result = ""
        result.reserveCapacity(command.count)
        var inSeparatorRun = false
        for character in command {
            if character == " " || character == "\t" {
                if !inSeparatorRun {
                    result.append(" ")
                    inSeparatorRun = true
                }
            } else {
                result.append(character)
                inSeparatorRun = false
            }
        }
        return result
    }
}
