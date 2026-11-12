// swift-tools-version:5.9
import PackageDescription

// The engine of cabinePCC, the PCC end of the Cabine link (../docs/cabine-link.md): it keeps the lines,
// runs one of them for the Cabine cabs connected to it, and has a headless daemon around it.
//
// A self-contained SwiftPM package beside the XcodeGen-driven app, with no external dependencies:
// Foundation and Network.framework only, so it builds offline with `swift build`. CabinePCCKit is the
// part the app hosts; cabine-pccd is the same engine with no window.
let package = Package(
    name: "CabinePCC",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .library(name: "CabinePCCKit", targets: ["CabinePCCKit"]),
        .executable(name: "cabine-pccd", targets: ["cabine-pccd"])
    ],
    targets: [
        .target(
            name: "CabinePCCKit",
            path: "Sources/CabinePCCKit"
        ),
        .executableTarget(
            name: "cabine-pccd",
            dependencies: ["CabinePCCKit"],
            path: "Sources/cabine-pccd"
        )
    ]
)
