// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "MacSpaces",
    platforms: [.macOS(.v13)],
    targets: [
        // Scanners, models, services — no SwiftUI, linkable by tests.
        .target(
            name: "MacSpacesCore",
            path: "Sources/MacSpacesCore"
        ),
        .executableTarget(
            name: "MacSpaces",
            dependencies: ["MacSpacesCore"],
            path: "Sources/MacSpaces"
        ),
        // A macro-free test runner: this machine's Command Line Tools lack the
        // XCTest framework and the Swift Testing macro plugin, so tests are a
        // plain executable that exits non-zero on failure. Run: swift run macspaces-tests
        .executableTarget(
            name: "macspaces-tests",
            dependencies: ["MacSpacesCore"],
            path: "Tests/MacSpacesTestRunner"
        ),
    ]
)
