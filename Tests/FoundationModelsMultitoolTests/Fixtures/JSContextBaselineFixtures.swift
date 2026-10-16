import JavaScriptCore
import Testing

/// The globals that JavaScriptCore itself gives a new `JSContext`, before
/// this package installs anything.
///
/// Two suites read this baseline. `HardeningTests` subtracts it to find the
/// globals that the sandbox injects, and `SandboxGlobalsTests` subtracts it
/// to find the globals that `docs("globals")` must document.
enum JSContextBaseline {
    /// Every own-property name on `globalThis` in a completely vanilla
    /// `JSContext` — the baseline JavaScriptCore itself ships with, before
    /// this package injects anything — **except** `console`.
    ///
    /// `console` is deliberately excluded from this baseline, even though
    /// it's already an own property of a bare `JSContext()` on this SDK
    /// (measured directly: a fresh `JSContext()`'s `globalThis` already has
    /// a `console`, one of Apple's own `JSContext` wrapper class's default
    /// conveniences — not an ECMAScript builtin at all, unlike this
    /// baseline's other members). `JSCInterpreter.installConsole` always
    /// *replaces* `globalThis.console` outright (`context.setObject(console,
    /// forKeyedSubscript: "console")`, where `console` is a brand-new
    /// object carrying only `log`) rather than extending whatever was there
    /// — so nothing of JSC's own default `console` (whatever other methods
    /// it might expose) is ever reachable from a `MultiTool` run; the
    /// `console` a snippet actually sees is 100% this package's minimal
    /// shim. Counting it as part of the untouched baseline here would make
    /// `HardeningTests` (and the README↔code sync it backs) miss that this
    /// package fully owns and controls `console`'s reachable surface, same
    /// as `tools`/`help`/`docs`.
    ///
    /// - Returns: the baseline global names.
    /// - Throws: when JavaScriptCore cannot make a context or list its
    ///   globals.
    static func globalNames() throws -> Set<String> {
        let context = try #require(JSContext())
        let namesValue = try #require(context.evaluateScript("Object.getOwnPropertyNames(globalThis)"))
        let names = try #require(namesValue.toArray() as? [String])
        return Set(names).subtracting(["console"])
    }
}
