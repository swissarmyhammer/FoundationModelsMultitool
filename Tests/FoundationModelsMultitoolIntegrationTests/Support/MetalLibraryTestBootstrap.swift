// Root-cause fix for `swift test`'s metallib PATH RESOLUTION bug — ported
// verbatim (mechanism unchanged, only comments retargeted at this package)
// from `mlx-swift-lm`'s own `Tests/MLXFoundationModelsTests/
// TestBootstrap.swift` (kanban `23ff1zx`; memory note
// `swiftpm-test-gpu-metallib-limit`), the sibling package this one already
// depends on transitively — this is the same `Cmlx`/`mlx-swift` dependency,
// so the same fix applies verbatim.
//
// mlx-swift's Metal backend (`Cmlx`, `mlx/backend/metal/device.cpp`,
// `load_default_library`) locates its compiled shader library by probing, in
// order: (1) `<binary-dir>/mlx.metallib`, where `<binary-dir>` is resolved
// via `dladdr` on the statically-linked `Cmlx` code -- i.e. wherever that
// code ends up linked, which for a test bundle is the actual executing
// Mach-O binary; (2) `<binary-dir>/Resources/mlx.metallib`; (3) a SwiftPM
// resource bundle reachable from the main bundle or any bundle in
// `Bundle.allBundles`/`Bundle.allFrameworks`; (4) `<binary-dir>/Resources/
// default.metallib`; (5) a CWD-relative `default.metallib`.
//
// SwiftPM places the built metallib inside `mlx-swift_Cmlx.bundle/Contents/
// Resources/default.metallib`, colocated with each `.xctest` bundle. Under
// `xcodebuild test`, the launched process's main bundle/working directory
// satisfies one of the probes above, so loading just works. Under plain
// `swift test`, the running binary lives at `<Target>.xctest/Contents/MacOS/
// <Target>`, two directory levels away from `<Target>.xctest/Contents/
// Resources/mlx-swift_Cmlx.bundle/...` -- every probe misses, and the first
// GPU-device MLXArray eval aborts the whole test process with "Failed to
// load the default metallib". This is exactly what this package's own gated
// scenarios hit under `MULTITOOL_INTEGRATION=1 swift test`: the first live
// `MLXLanguageModel`/Router generation call touches the GPU device.
//
// This bootstrap closes the gap at its source: it locates the resource
// bundle SwiftPM already built and creates a `mlx.metallib` symlink next to
// the running test binary, satisfying probe #1. It must run before any
// GPU-touching test evaluates an array; call `MetalLibraryTestBootstrap
// .ensureColocatedMetallib` (a `static let`, so Swift's once-only semantics
// make repeat calls free) before any gated scenario resolves a live model —
// see `LiveRouterFixture.resolve()` and `CLISmokeTests`.
//
// The fix is idempotent (skips if the symlink already exists) and a
// harmless no-op under `xcodebuild` -- there, an earlier probe already
// succeeds, so this symlink is simply never consulted.

import Foundation

/// Installs a metallib symlink to fix Swift Package Manager test binary path
/// resolution for GPU-device tests (see the file header above for the full
/// root-cause writeup).
enum MetalLibraryTestBootstrap {

    /// Runs the symlink installation exactly once per test process. Callers
    /// trigger this via `_ = MetalLibraryTestBootstrap.ensureColocatedMetallib`
    /// before any test touches a GPU-device `MLXArray`.
    static let ensureColocatedMetallib: Void = {
        do {
            try installSymlinkIfNeeded()
        } catch {
            // Best-effort: if this fails, the original mlx "Failed to load
            // the default metallib" error will surface on first GPU eval,
            // same as before this bootstrap existed.
            logError("MetalLibraryTestBootstrap: \(error)")
        }
    }()

    /// Anchor class purely so `Bundle(for:)` can identify the `.xctest`
    /// bundle this test binary was built into -- `Bundle(for:)` accepts any
    /// class, it need not be a test case itself.
    private final class BundleAnchor {}

    private static let resourceBundleName = "mlx-swift_Cmlx.bundle"
    private static let metallibRelativePath = "Contents/Resources/default.metallib"

    private static func installSymlinkIfNeeded() throws {
        guard let binaryDirectory = currentTestBinaryDirectory() else {
            logError(
                """
                MetalLibraryTestBootstrap: could not determine the running test \
                binary's directory; GPU-device tests may crash with "Failed to \
                load the default metallib".
                """)
            return
        }
        let symlinkURL = binaryDirectory.appendingPathComponent("mlx.metallib")
        if FileManager.default.fileExists(atPath: symlinkURL.path) { return }
        guard let metallibURL = locateDefaultMetallib(testBundle: Bundle(for: BundleAnchor.self))
        else {
            logError(
                """
                MetalLibraryTestBootstrap: could not locate \
                mlx-swift_Cmlx.bundle/default.metallib; GPU-device tests may crash \
                with "Failed to load the default metallib".
                """)
            return
        }
        try FileManager.default.createSymbolicLink(at: symlinkURL, withDestinationURL: metallibURL)
    }

    /// Writes `message` to stderr followed by a newline. Shared by the
    /// best-effort diagnostic paths in `installSymlinkIfNeeded`, which log
    /// and continue rather than fail the bootstrap outright.
    private static func logError(_ message: String) {
        FileHandle.standardError.write(Data((message + "\n").utf8))
    }

    /// Directory containing the running test binary -- mirrors mlx's
    /// `current_binary_dir()` (a `dladdr` lookup on the statically-linked
    /// `Cmlx` code, which resolves to whatever Mach-O that code was linked
    /// into, i.e. this very test executable).
    private static func currentTestBinaryDirectory() -> URL? {
        let bundle = Bundle(for: BundleAnchor.self)
        if let executableURL = bundle.executableURL {
            return executableURL.deletingLastPathComponent()
        }
        // Every macOS test/app bundle uses this layout; fall back to it if
        // `executableURL` is somehow unavailable.
        return bundle.bundleURL.appendingPathComponent("Contents/MacOS")
    }

    /// Finds `mlx-swift_Cmlx.bundle/Contents/Resources/default.metallib`.
    ///
    /// Tries the fast, common case first (the bundle SwiftPM colocates
    /// inside this very `.xctest` bundle's own `Contents/Resources/`), then
    /// falls back to scanning every loaded bundle/framework the same way
    /// mlx's own `load_swiftpm_library` does, to stay robust across build
    /// layouts (`swift test` vs. `xcodebuild`, differing SwiftPM versions).
    private static func locateDefaultMetallib(testBundle: Bundle) -> URL? {
        var candidateBases: [URL] = [
            testBundle.bundleURL.appendingPathComponent("Contents/Resources")
        ]
        candidateBases += Bundle.allBundles.map { $0.bundleURL }
        candidateBases += Bundle.allBundles.compactMap { $0.resourceURL }
        candidateBases += Bundle.allFrameworks.map { $0.bundleURL }
        candidateBases += Bundle.allFrameworks.compactMap { $0.resourceURL }

        for base in candidateBases {
            let metallibURL =
                base
                .appendingPathComponent(resourceBundleName)
                .appendingPathComponent(metallibRelativePath)
            if FileManager.default.fileExists(atPath: metallibURL.path) {
                return metallibURL
            }
        }
        return nil
    }
}
