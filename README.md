# NonoSwift

[![CI](https://github.com/cicci8ino/nono-swift/actions/workflows/ci.yml/badge.svg)](https://github.com/cicci8ino/nono-swift/actions/workflows/ci.yml)

> [!WARNING]
> This is the only piece of text in the entire repository that has properly been reviewed by a human. This package is not production ready, it has not been security reviewed or security tested, it has been heavily (I mean, mostly) developed with AI coding agents and it's only meant to be used by me on PoCs rather than production ready projects. Do not rely on it as a security boundary for sensitive workloads without your own review, testing, and threat analysis.

Swift Package Manager bindings for [`nono`](https://github.com/always-further/nono), a capability-based process sandbox.

This is an unofficial macOS package. It is not maintained by, endorsed by, or affiliated with the upstream `nono` project. The sandbox implementation remains upstream Rust; this package provides Swift wrappers and release packaging for the C FFI.

## Support

| Platform | Architecture | Status |
| --- | --- | --- |
| macOS 12+ | arm64 | Supported |

Intel macOS and Linux are not supported.

## Install

Use a release version so SwiftPM downloads the matching `CNono.xcframework.zip` GitHub Release asset:

```swift
dependencies: [
    .package(url: "https://github.com/cicci8ino/nono-swift.git", from: "0.0.2")
]
```

```swift
.product(name: "NonoSwift", package: "nono-swift")
```

SwiftPM verifies the binary checksum from `Package.swift`. Consumers do not need Go, CGo, Rust, or Cargo.

## Usage

Sandbox the current process:

```swift
import NonoSwift

let caps = CapabilitySet()
defer { caps.close() }

try caps.allowPath("/Users/andrea/data", access: .read)
try caps.allowPath("/tmp", access: .readWrite)
try caps.blockNetwork()

try NonoSwift.apply(caps)
```

`apply(_:)` is irreversible for the current process.

Run a sandboxed child while keeping the parent unsandboxed:

```swift
let caps = CapabilitySet()
defer { caps.close() }

try caps.allowPath("/Users/andrea/workspace", access: .readWrite)
try caps.blockNetwork()

let result = try sandboxedExec(
    caps,
    command: ["/usr/bin/python3", "agent.py"],
    cwd: "/Users/andrea/workspace",
    timeout: 30
)
```

`sandboxedExec` captures stdout/stderr, returns nonzero child exits in `SandboxedExecResult`, and does not inherit the parent environment unless `inheritEnvironment: true` is passed. Dynamic-loader variables such as `DYLD_*` and `LD_*` are rejected.

Query without applying:

```swift
let query = try QueryContext(capabilities: caps)
let path = try query.queryPath("/Users/andrea/data/file.txt", access: .read)
let network = try query.queryNetwork()
```

Serialize state:

```swift
let state = try SandboxState(capabilities: caps)
let json = try state.json()
let restoredCaps = try SandboxState(json: json).capabilities()
```

Errors are thrown as `NonoError` with `code` and `message`.

## Behavior

- `CapabilitySet` path grants are canonicalized by upstream `nono`; on macOS, `/var` paths often resolve under `/private/var`.
- An empty `CapabilitySet()` still applies upstream nono's macOS baseline profile.
- Filesystem access is denied unless explicitly granted with `allowPath` or `allowFile`.
- Network is allowed by default; call `blockNetwork()` or `setNetworkMode(.blocked)` to deny it.
- Process execution is allowed by default on macOS; use `addPlatformRule(_:)` for explicit Seatbelt denies.
- The baseline `(literal "/")` read rule is exact-path access for root path resolution, not recursive disk access.
- Startup-only command metadata APIs are intentionally not exposed: no `allowCommand`, `blockCommand`, or deprecated `setNetworkBlocked`.

## Development

Source checkouts use a locally generated binary target:

```sh
make artifacts
make test
```

The Makefile exports `NONO_SWIFT_BINARY_TARGET=local`, so SwiftPM uses:

```text
Artifacts/CNono.xcframework
```

If you run SwiftPM directly, set the variable yourself:

```sh
NONO_SWIFT_BINARY_TARGET=local swift test
```

Requirements for rebuilding the artifact:

1. Xcode command line tools, including `xcodebuild`
2. Rust and Cargo
3. Rust macOS target: `rustup target add aarch64-apple-darwin`

Generated artifacts are ignored and should not be committed:

```text
Artifacts/CNono.xcframework
Artifacts/MANIFEST.json
```

Useful local commands:

```sh
make artifacts
make verify-artifacts
make test
make test-apply
```

`make test-apply` runs the irreversible apply fixture in child processes and requires sandbox application to succeed.

## Layout

`CapabilitySet`, `QueryContext`, and `SandboxState` are Swift owners around opaque C pointers. `NonoSwift` links `CNono`, which links upstream `libnono_ffi.a` and applies macOS Seatbelt sandboxing.

## License

Apache-2.0. See `LICENSE` and `NOTICE.md`.
