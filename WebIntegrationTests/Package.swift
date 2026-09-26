// swift-tools-version: 6.1
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

/// The name of the package under test, and the directory `..` holds.
private let productPackageName = "FoundationModelsMultitool"

/// The HTML parser package of the web capability.
///
/// `../Package.swift` states why the web capability uses it
/// (`htmlParserPackage`). This manifest states it again only so that SwiftPM
/// resolves the same package with the same requirement.
private let htmlParserPackage = "SwiftSoup"

/// SwiftPM manifest for the live web suite: real web requests, and no model.
///
/// **Why this is a package of its own.** `swift test` at the repository root
/// must stay offline. A package that the root manifest does not name is
/// invisible to the root `swift test`, thus the build graph keeps the root run
/// offline, and not a convention. `web.md` § "Testing", Level 2 states the
/// design.
///
/// **This package reads the environment on purpose.** The keyed provider
/// tests read the API keys from the environment, because
/// `WebConfiguration.fromEnvironment()` is the feature under test. The
/// manifest of `IntegrationTests/` states: "nothing here reads the
/// environment, and nothing may start doing so". That rule stays true for
/// `IntegrationTests/`, because the keyed tests are here and not there. An
/// environment variable never selects a test of this package: the package
/// boundary selects the suite.
///
/// The command is:
///
///     swift test --package-path WebIntegrationTests --no-parallel
///
/// `--no-parallel`, and `.serialized` on each suite, keep the request rate to
/// each provider low. Each test has `.timeLimit(.minutes(1))`, and each request
/// has a short timeout, thus a provider that does not answer fails its test
/// and does not stop the run.
///
/// **The compile coupling.** The root build does not compile these files. A
/// CI step that runs `swift build --package-path WebIntegrationTests
/// --build-tests` on each run keeps them from rot, the same as
/// `IntegrationTests/Package.swift` states for its own package.
///
/// **Why the dependency list repeats the root manifest.** A package can name
/// only the products of the packages that it declares. The SwiftSoup
/// declaration is therefore stated again here, and its URL and requirement
/// match `../Package.swift` exactly. A difference is a resolution conflict.
let package = Package(
    name: "FoundationModelsMultitoolWebIntegrationTests",
    // Commit to macOS 27 / FoundationModels v2, exactly as `../Package.swift`
    // does; a lower floor here would not resolve against it.
    platforms: [
        .macOS("27.0")
    ],
    dependencies: [
        .package(path: ".."),
        .package(url: "https://github.com/scinfu/\(htmlParserPackage).git", from: "2.13.9"),
    ],
    targets: [
        // The live web suite. It links only the library under test: the web
        // capability needs no model, thus no MLX product and no live Router
        // wiring is linked.
        .testTarget(
            name: "FoundationModelsMultitoolWebIntegrationTests",
            dependencies: [
                .product(name: productPackageName, package: productPackageName)
            ],
            path: "Tests/FoundationModelsMultitoolWebIntegrationTests"
        )
    ]
)
