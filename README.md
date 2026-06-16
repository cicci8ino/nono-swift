# NonoSwift

[![CI](https://github.com/cicci8ino/nono-swift/actions/workflows/ci.yml/badge.svg)](https://github.com/cicci8ino/nono-swift/actions/workflows/ci.yml)
[![Release](https://github.com/cicci8ino/nono-swift/actions/workflows/release.yml/badge.svg)](https://github.com/cicci8ino/nono-swift/actions/workflows/release.yml)

Swift Package Manager bindings for [`nono`](https://github.com/always-further/nono), a capability-based process sandbox.

This is an unofficial Swift macOS package. It is not maintained by, endorsed by, or affiliated with the upstream `nono` project.

`NonoSwift` exposes a Swift-native API over the upstream `nono` C FFI. The sandbox implementation remains in upstream Rust; this package handles Swift packaging, pointer ownership, string conversion, error mapping, and tests.

## Platform Support

| Platform | Architecture | Status |
| --- | --- | --- |
| macOS 12+ | arm64 | Supported |

Intel macOS and Linux are not supported.

## Installation

Add the released package in Xcode or in `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/cicci8ino/nono-swift.git", from: "0.1.0")
]
```

Then add the product to your target:

```swift
.product(name: "NonoSwift", package: "nono-swift")
```

Import it from Swift:

```swift
import NonoSwift
```

SwiftPM downloads the `CNono.xcframework.zip` release asset automatically and verifies the checksum in `Package.swift`. App developers do not need Go, CGo, Rust, or Cargo.

## Quick Start

```swift
import NonoSwift

let caps = CapabilitySet()
defer { caps.close() }

try caps.allowPath("/Users/andrea/data", access: .read)
try caps.allowPath("/tmp", access: .readWrite)
try caps.setNetworkMode(.blocked)

try NonoSwift.apply(caps)
```

`apply(_:)` is irreversible for the current process. Once applied, the current process and its children can only access resources granted by the capability set. It does not sandbox your whole Mac, and it does not persist after the process exits.

## Query Without Applying

Use `QueryContext` to inspect what a capability set would allow before applying it:

```swift
let caps = CapabilitySet()
defer { caps.close() }

try caps.allowPath("/Users/andrea/data", access: .read)
try caps.setNetworkMode(.allowAll)

let query = try QueryContext(capabilities: caps)
defer { query.close() }

let path = try query.queryPath("/Users/andrea/data/file.txt", access: .read)
let network = try query.queryNetwork()
```

`QueryContext` snapshots the capability set at initialization. Later changes to `caps` do not affect existing query contexts.

## Serialize State

```swift
let state = try SandboxState(capabilities: caps)
defer { state.close() }

let json = try state.json()

let restored = try SandboxState(json: json)
defer { restored.close() }

let restoredCaps = try restored.capabilities()
defer { restoredCaps.close() }
```

## Error Handling

Failing operations throw `NonoError`:

```swift
do {
    try caps.allowPath("/missing/path", access: .read)
} catch let error as NonoError {
    print(error.code)
    print(error.message)
}
```

Useful error codes include:

```swift
.pathNotFound
.expectedDirectory
.expectedFile
.pathCanonicalization
.noCapabilities
.sandboxInit
.unsupportedPlatform
.blockedCommand
.configParse
.profileParse
.io
.invalidArgument
.trustVerification
.unknown
```

## Build From Source

The Swift package links a binary target:

```text
Artifacts/CNono.xcframework
```

That artifact is generated from upstream `nono` source with Cargo. The generated `Artifacts/CNono.xcframework` and `Artifacts/MANIFEST.json` are intentionally ignored and should not be committed. Tagged releases publish `CNono.xcframework.zip` as a GitHub Release asset instead of storing binaries in git.

Requirements for maintainers rebuilding the artifact:

1. Xcode command line tools, including `xcodebuild`
2. Rust and Cargo
3. Rust macOS target: `rustup target add aarch64-apple-darwin`

Build the arm64 macOS artifact:

```sh
make artifacts
make verify-artifacts
```

`make artifacts` and `make artifacts-arm64` are equivalent; both produce an arm64-only local artifact.

Local source builds use the generated artifact by setting `NONO_SWIFT_BINARY_TARGET=local`. The Makefile does this automatically. If you run SwiftPM directly from a source checkout, pass the variable yourself:

```sh
NONO_SWIFT_BINARY_TARGET=local swift build
NONO_SWIFT_BINARY_TARGET=local swift test
```

The artifact build keeps Cargo state inside the repository by default:

```text
.build/nono-source-build/cargo-home
.build/nono-source-build/cargo-target
```

Keeping Cargo state local makes cleanup simple and avoids polluting global Cargo caches. The Cargo executable and Rust toolchain still come from your normal Rust installation.

Use an existing upstream checkout instead of cloning:

```sh
./Scripts/build-xcframework.sh --nono-src /path/to/nono
```

Pin a specific upstream ref:

```sh
NONO_REF=<commit-or-tag> make artifacts
```

## Tests

From a source checkout, run normal tests with the Makefile so the local artifact is generated and selected:

```sh
make test-arm64
```

Or run SwiftPM directly after building artifacts:

```sh
make artifacts
NONO_SWIFT_BINARY_TARGET=local swift test
```

`swift test` launches the irreversible apply fixture in separate child processes. If the host environment blocks nested sandboxing, those XCTest cases skip. To require the apply fixture to pass, run:

```sh
make test-apply
```

For the apply fixture only:

```sh
make test-apply-arm64
```

The fixture applies the sandbox only to its own process. It runs two separate scenarios because sandbox application is irreversible:

1. A minimal sandbox first verifies `/usr/bin/whoami` runs before sandboxing, then applies caps and verifies filesystem/network restrictions plus that an explicit platform `process-exec*` deny prevents the command from running.
2. A process-capable sandbox first verifies `/usr/bin/whoami` runs before sandboxing, then applies caps with system executable/runtime read grants and verifies the command still runs while filesystem and network restrictions still hold.

The fixture does not persist after the process exits and does not affect the shell that launched it.

## Release Checklist

Do not commit generated binaries. To publish a release, run the manual GitHub Actions `Release` workflow with a semantic version such as `0.1.0`.

The release workflow:

1. Builds the arm64 `CNono.xcframework` from upstream source.
2. Verifies `Artifacts/MANIFEST.json`.
3. Runs the Swift test suite and strict apply fixture.
4. Zips the XCFramework.
5. Computes `swift package compute-checksum`.
6. Updates `Package.swift` with the release version and checksum.
7. Commits the manifest update, tags the release, and uploads `CNono.xcframework.zip` as a GitHub Release asset.

The generated `Artifacts/CNono.xcframework` and `Artifacts/MANIFEST.json` remain ignored and unversioned.

## macOS Path Canonicalization

macOS often exposes `/var` paths as symlinks under `/private/var`. The upstream library canonicalizes paths, so callers comparing paths should resolve symlinks first. This especially affects paths returned by temporary-directory APIs.

## How It Works

The package is layered like this:

```text
Swift app
  imports NonoSwift
    calls Swift resource-owner wrappers
      calls CNono C ABI from nono.h
        links libnono_ffi.a
          implemented by upstream Rust nono
            applies macOS Seatbelt sandboxing
```

`CapabilitySet`, `QueryContext`, and `SandboxState` are Swift `final class` owners around opaque C pointers. They free their native resources in `close()` and `deinit`.

## License

Apache-2.0. See `LICENSE` and `NOTICE.md`.
