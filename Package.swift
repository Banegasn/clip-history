// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ClipHistory",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "ClipHistory",
            path: "Sources/ClipHistory",
            // AppKit + Carbon callbacks are easier under the Swift 5 concurrency
            // model; we don't need strict Swift 6 isolation for a single-process
            // menu-bar app that lives on the main thread.
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
