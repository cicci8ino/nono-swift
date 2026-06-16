// swift-tools-version: 5.9
import Foundation
import PackageDescription

// Updated by .github/workflows/release.yml. Local development uses
// NONO_SWIFT_BINARY_TARGET=local to select Artifacts/CNono.xcframework instead.
let cNonoReleaseVersion = "0.0.1"
let cNonoReleaseChecksum = "337a5b399d8d827d507571199a738a9ac82cc66ecdf9061f2d230a5368cb7126"
let useLocalCNono = ProcessInfo.processInfo.environment["NONO_SWIFT_BINARY_TARGET"] == "local"
let cNonoTarget: Target = useLocalCNono
    ? .binaryTarget(
        name: "CNono",
        path: "Artifacts/CNono.xcframework"
    )
    : .binaryTarget(
        name: "CNono",
        url: "https://github.com/cicci8ino/nono-swift/releases/download/\(cNonoReleaseVersion)/CNono.xcframework.zip",
        checksum: cNonoReleaseChecksum
    )

let package = Package(
    name: "NonoSwift",
    platforms: [
        .macOS(.v12)
    ],
    products: [
        .library(name: "NonoSwift", targets: ["NonoSwift"]),
        .executable(name: "NonoSwiftApplySandboxFixture", targets: ["NonoSwiftApplySandboxFixture"])
    ],
    targets: [
        cNonoTarget,
        .target(
            name: "NonoSwift",
            dependencies: ["CNono"],
            linkerSettings: [
                .linkedFramework("Security")
            ]
        ),
        .testTarget(
            name: "NonoSwiftTests",
            dependencies: ["NonoSwift"]
        ),
        .executableTarget(
            name: "NonoSwiftApplySandboxFixture",
            dependencies: ["NonoSwift"]
        )
    ]
)
