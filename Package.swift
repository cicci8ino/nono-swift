// swift-tools-version: 5.9
import Foundation
import PackageDescription

// Updated by .github/workflows/release.yml. Local development uses
// NONO_SWIFT_BINARY_TARGET=local to select Artifacts/CNono.xcframework instead.
let cNonoReleaseVersion = "0.0.2"
let cNonoReleaseChecksum = "76910f93c8516c56890dcc9759a242a975a5cf6a71418dbf1053240e7390e856"
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
