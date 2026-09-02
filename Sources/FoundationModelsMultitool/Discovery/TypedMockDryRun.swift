import Foundation

/// Runs a candidate `runCode` snippet against **typed mocks** of a matched
/// catalog and reports the first failure its API usage produces.
///
/// ## What this answers, and what it does not
///
/// It answers exactly one question: *would this snippet throw on its API
/// usage?* It does not answer *is this snippet correct?* Two limits follow,
/// and neither is a defect to be fixed later:
///
/// - **Logic errors pass.** A snippet that calls everything correctly and
///   computes the wrong thing runs clean here.
/// - **Branch selection is arbitrary.** The mocks carry synthetic values, not
///   real data, so `if (cities.length > 2)` takes whichever branch a
///   two-element mocked array happens to select. A snippet can run clean here
///   and still fail on real data — which is what `runCode`'s own repair loop
///   is for.
///
/// A widened `any` in a signature (see `ToolValueShape.any`) is mocked as an
/// empty object and accepted as any argument, since the declared type
/// constrains nothing.
///
/// ## Why mocks rather than a checker
///
/// Nothing real runs: every matched `tools.*` path is replaced by a JavaScript
/// mock, so no side effect happens and no real datum exists to leak into the
/// generated sample. Each mock:
///
/// 1. checks arity and argument types against `ToolDescriptor.signature` — the
///    same structure the entry's `declare function` line is rendered from, so
///    the check and the advertised signature cannot disagree;
/// 2. resolves to a synthetic value shaped by the declared return type; and
/// 3. wraps that value in a `Proxy` that throws when the snippet reads a field
///    the declared type does not have, and in a second `Proxy` that throws
///    when the snippet reads a field off the *unawaited* call.
///
/// ## A false failure is worse than no check
///
/// A bogus failure feeds a wrong error back into the generation session, and
/// the generator then "repairs" correct code into broken code. So the mocks
/// lean permissive everywhere the answer is not clear-cut:
///
/// - **Scalars are real values.** A `string` mocks as `""`, a `number` as `0`,
///   a `boolean` as `false`, so passing one back into a parameter of that type
///   type-checks natively with no special case.
/// - **Objects and arrays carry a hidden type tag.** A mock standing for `T`
///   satisfies a parameter declared `T` at any depth by tag alone, before any
///   structural comparison runs.
/// - **The `Proxy` lets every JavaScript protocol access through.** Symbol
///   keys, anything on `Object.prototype`/`Array.prototype`, an array's
///   indices, and the handful of named protocol members (`then`, `toJSON`,
///   `length`, …) all forward to the target untouched. Only a plain string key
///   that looks like a data field the declared type lacks throws.
/// - **Extra properties on an argument object are fine.** Only *missing
///   required* fields and *wrong types* fail.
enum TypedMockDryRun {
    /// Runs `snippet` against typed mocks of `entries` and returns the first
    /// failure its API usage produced.
    ///
    /// A watchdog timeout counts as a failure and is reported as one: a
    /// snippet that cannot finish against mocks that resolve instantly cannot
    /// finish against real tools either.
    ///
    /// Any other thrown error — a cancelled enclosing `Task`, say — yields
    /// `nil` rather than a failure, so the gate this backs degrades to "no
    /// opinion" instead of rejecting a snippet for a reason that has nothing
    /// to do with the snippet.
    ///
    /// - Parameters:
    ///   - snippet: the candidate JavaScript to dry-run.
    ///   - entries: the matched catalog entries to mock. A `tools.*` path
    ///     outside this set is simply never defined, so calling one fails as
    ///     an ordinary JavaScript `TypeError`.
    ///   - interpreter: the sandbox to run the mocked snippet in. Its own time
    ///     limit bounds the run.
    /// - Returns: the failure message to feed back, or `nil` when the snippet
    ///   ran clean.
    static func apiUsageFailure(
        in snippet: String,
        against entries: [APISurface.Entry],
        using interpreter: any Interpreter
    ) -> String? {
        do {
            _ = try interpreter.run(code: "\(harness(for: entries))\n\(snippet)", installing: [])
            return nil
        } catch let error as InterpreterError {
            return error.message
        } catch {
            return nil
        }
    }

    /// Builds the JavaScript preamble that defines `tools` and installs one
    /// typed mock per entry.
    ///
    /// Grouped entries get their namespace object created first, exactly as
    /// `MultiTool`'s own real `tools.*` glue does, and `entry.path`/
    /// `entry.group`/`entry.descriptor.name` are spliced bare for the same
    /// reason: each is already validated as a legal TypeScript (and so legal
    /// JavaScript) identifier before an `APISurface.Entry` can be constructed.
    ///
    /// - Parameter entries: the matched catalog entries to mock.
    /// - Returns: the preamble to prepend to the candidate snippet.
    private static func harness(for entries: [APISurface.Entry]) -> String {
        var lines = [runtime, "globalThis.tools = {};"]
        for entry in entries {
            if let group = entry.group {
                lines.append("tools.\(group) = tools.\(group) || {};")
            }
            let signature = entry.descriptor.signature
            lines.append(
                "tools.\(entry.path) = __mockTool({ call: \(ToolAPIRenderer.jsStringLiteral("tools.\(entry.path)")), "
                    + "arguments: \(literal(for: .object(signature.arguments))), "
                    + "result: \(literal(for: signature.result)) });"
            )
        }
        return lines.joined(separator: "\n")
    }

    /// Renders one declared shape as the JavaScript object literal the
    /// harness's runtime reads.
    ///
    /// Every shape carries its `declared` TypeScript type, which is the text
    /// each failure message names and, for the object and array shapes that
    /// get a `Proxy`, the hidden type tag's value as well. Two shapes with the
    /// same declared type are interchangeable, which is exactly the identity a
    /// structural type has.
    ///
    /// - Parameter shape: the declared shape to render.
    /// - Returns: the JavaScript object literal describing `shape`.
    private static func literal(for shape: ToolValueShape) -> String {
        let common = "kind: '\(kind(of: shape))', declared: \(ToolAPIRenderer.jsStringLiteral(shape.declaredType))"
        switch shape {
        case .string, .number, .boolean, .any:
            return "{ \(common) }"
        case .array(let element):
            return "{ \(common), element: \(literal(for: element)) }"
        case .object(let object):
            let properties = object.properties.map { property in
                "{ name: \(ToolAPIRenderer.jsStringLiteral(property.name)), required: \(property.isRequired), "
                    + "shape: \(literal(for: property.shape)) }"
            }
            return "{ \(common), properties: [\(properties.joined(separator: ", "))] }"
        }
    }

    /// The `kind` discriminator the harness's runtime switches on.
    ///
    /// The three scalar kinds are spelled exactly as JavaScript's own `typeof`
    /// spells them, so the runtime's type check is a direct comparison rather
    /// than a second mapping table.
    ///
    /// - Parameter shape: the declared shape to name.
    /// - Returns: the discriminator for `shape`.
    private static func kind(of shape: ToolValueShape) -> String {
        switch shape {
        case .string:
            return "string"
        case .number:
            return "number"
        case .boolean:
            return "boolean"
        case .array:
            return "array"
        case .object:
            return "object"
        case .any:
            return "any"
        }
    }

    /// The fixed JavaScript the harness's per-entry mock installs call into.
    ///
    /// Written with single-quoted JavaScript strings throughout, so no
    /// fragment of it needs escaping on the way through a Swift literal, and
    /// what a reader sees here is exactly what the sandbox parses.
    ///
    /// The two `Proxy` handlers are the whole substance:
    ///
    /// - `__mockProxy` traps reads of undeclared data fields on a resolved
    ///   value. It forwards symbol keys, own properties (the declared fields
    ///   and the hidden tag), anything reachable on `Object.prototype`, an
    ///   array's own prototype members and indices, and the named protocol
    ///   members in `__mockPassThrough`. Everything else throws, naming the
    ///   declared type.
    /// - `__mockPending` traps reads on the *promise* a call returns, which is
    ///   the forgotten-`await` shape: only `then`/`catch`/`finally`,
    ///   `constructor`, and symbol keys forward, and anything else throws
    ///   asking for `await`. This mirrors the trap `JSCInterpreter` installs
    ///   around a real async host function's result; it is restated here in
    ///   JavaScript because this harness installs no host functions at all, so
    ///   there is no Swift-side bridge to inherit it from.
    ///
    /// A mocked array is given **two** elements rather than none or one, so
    /// `[0]`, `[1]`, `.length`, `map`, and `filter` all behave the way they
    /// would on real data. An empty array would let a snippet run clean while
    /// exercising nothing inside its loops.
    private static let runtime = """
        var __mockTagKey = '__mockShape';
        var __mockPassThrough = ['then', 'catch', 'finally', 'toJSON', 'inspect', 'length'];
        function __mockDescribe(value) {
          if (value === null) { return 'null'; }
          if (value === undefined) { return 'undefined'; }
          if (Array.isArray(value)) { return 'an array'; }
          return typeof value;
        }
        function __mockValue(shape, label) {
          if (shape.kind === 'string') { return ''; }
          if (shape.kind === 'number') { return 0; }
          if (shape.kind === 'boolean') { return false; }
          if (shape.kind === 'any') { return {}; }
          if (shape.kind === 'array') {
            var elements = [__mockValue(shape.element, label + '[]'), __mockValue(shape.element, label + '[]')];
            return __mockProxy(elements, shape, label);
          }
          var target = {};
          for (var index = 0; index < shape.properties.length; index++) {
            var property = shape.properties[index];
            target[property.name] = __mockValue(property.shape, label + '.' + property.name);
          }
          return __mockProxy(target, shape, label);
        }
        function __mockProxy(target, shape, label) {
          Object.defineProperty(target, __mockTagKey, {
            value: shape.declared, enumerable: false, writable: false, configurable: false
          });
          return new Proxy(target, {
            get: function (holder, key) {
              if (typeof key === 'symbol') { return holder[key]; }
              if (Object.prototype.hasOwnProperty.call(holder, key)) { return holder[key]; }
              if (key in Object.prototype) { return holder[key]; }
              if (__mockPassThrough.indexOf(key) >= 0) { return holder[key]; }
              if (Array.isArray(holder) && (key in Array.prototype || String(Number(key)) === key)) {
                return holder[key];
              }
              throw new Error(
                label + ' is declared ' + shape.declared + ' and has no "' + key +
                '". Read only the fields the declared type has.'
              );
            }
          });
        }
        function __mockPending(call, promise) {
          return new Proxy(promise, {
            get: function (holder, key) {
              if (typeof key === 'symbol' || key === 'constructor') { return holder[key]; }
              if (key === 'then' || key === 'catch' || key === 'finally') { return holder[key].bind(holder); }
              throw new Error(
                call + ': accessed property "' + String(key) + '" on a pending result - did you forget `await`? ' +
                'Await the call before reading a property.'
              );
            }
          });
        }
        function __mockTypeFailure(where, shape, value) {
          return new Error(where + ' must be ' + shape.declared + ', but received ' + __mockDescribe(value) + '.');
        }
        function __mockCheck(value, shape, where) {
          if (shape.kind === 'any') { return; }
          if (shape.kind === 'string' || shape.kind === 'number' || shape.kind === 'boolean') {
            if (typeof value !== shape.kind) { throw __mockTypeFailure(where, shape, value); }
            return;
          }
          if (value !== null && value !== undefined && value[__mockTagKey] === shape.declared) { return; }
          if (shape.kind === 'array') {
            if (!Array.isArray(value)) { throw __mockTypeFailure(where, shape, value); }
            for (var element = 0; element < value.length; element++) {
              __mockCheck(value[element], shape.element, where + '[' + element + ']');
            }
            return;
          }
          if (value === null || typeof value !== 'object' || Array.isArray(value)) {
            throw __mockTypeFailure(where, shape, value);
          }
          for (var index = 0; index < shape.properties.length; index++) {
            var property = shape.properties[index];
            if (!property.required) { continue; }
            if (!(property.name in value)) {
              throw new Error(
                where + ' is missing the required field "' + property.name +
                '"; it is declared ' + shape.declared + '.'
              );
            }
            __mockCheck(value[property.name], property.shape, where + '.' + property.name);
          }
        }
        function __mockTool(spec) {
          return function () {
            if (arguments.length > 1) {
              throw new Error(
                spec.call + ' takes exactly one arguments object; received ' + arguments.length + ' arguments.'
              );
            }
            var supplied = arguments.length === 0 ? {} : arguments[0];
            if (supplied === undefined || supplied === null) { supplied = {}; }
            __mockCheck(supplied, spec.arguments, spec.call + "'s arguments object");
            return __mockPending(spec.call, Promise.resolve(__mockValue(spec.result, spec.call + "'s result")));
          };
        }
        """
}
