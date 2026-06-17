# NonoSwift Specification

## Goal

Build a Swift Package Manager library that provides macOS Swift bindings for the `nono` capability-based security sandbox, matching the public macOS behavior of `github.com/always-further/nono-go` without depending on Go or CGo.

Initial scope is macOS arm64 only. Intel macOS and Linux are out of scope.

## Source Material

Reference implementation: `https://github.com/always-further/nono-go`

Reference release inspected: latest `main` as of 2026-06-15, GitHub release `v0.21.0`.

Bundled upstream `nono` commit in `nono-go/internal/clib/MANIFEST.json`: `52809dda3b9ec5d7a237c26ac5e90840052993d9`.

The Swift package must wrap the same C ABI exposed by `internal/clib/nono.h`. The macOS arm64 `libnono_ffi.a` library must be built from upstream `nono` source, following the same source-build approach used by `nono-go/scripts/build-libs.sh`.

## Package Shape

Package name: `NonoSwift`

Library product: `NonoSwift`

Swift module: `NonoSwift`
C binary module: `CNono`

Minimum platform: macOS 12

Swift tools version: 5.9 or newer

License: Apache-2.0, preserving notices from `nono-go` and upstream `nono`.

Proposed layout:

```text
Package.swift
README.md
LICENSE
NOTICE.md
Scripts/
  build-nono.sh
  build-xcframework.sh
  verify-artifacts.sh
Sources/
  NonoSwift/
    CapabilitySet.swift
    Errors.swift
    QueryContext.swift
    SandboxState.swift
    Types.swift
    NonoSwift.swift
  NonoSwiftApplySandboxFixture/
    main.swift
Tests/
  NonoSwiftTests/
    CapabilitySetTests.swift
    QueryContextTests.swift
    SandboxStateTests.swift
    ApplySandboxTests.swift
Artifacts/
  CNono.xcframework
  MANIFEST.json
```

Draft `Package.swift`:

```swift
// swift-tools-version: 5.9
import PackageDescription

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
        .binaryTarget(
            name: "CNono",
            path: "Artifacts/CNono.xcframework"
        ),
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
```

## Binary Artifact Strategy

Do not call Go or CGo from Swift.

Build `libnono_ffi.a` from upstream `nono` source as part of package preparation. Normal `swift build` should consume the generated XCFramework so downstream Swift users do not need custom linker flags.

Cargo registry/git cache and Cargo build output should default to paths under `.build/nono-source-build`:

```text
.build/nono-source-build/cargo-home
.build/nono-source-build/cargo-target
```

This keeps generated Cargo state inside the workspace for sandboxed development. The Cargo executable and Rust toolchain still need to be readable/executable by the sandbox.

Use SwiftPM binary targets for macOS after the source build produces the artifact:

```text
Artifacts/CNono.xcframework
  macos-arm64/libnono_ffi.a
  Headers/nono.h
  Headers/module.modulemap
```

The module map inside the headers should expose the C ABI as `CNono`:

```c
module CNono {
  header "nono.h"
  export *
}
```

Build script requirements:

1. Clone upstream `https://github.com/always-further/nono.git` unless `--nono-src` points at an existing checkout.
2. Build the Rust package `nono-ffi` for `aarch64-apple-darwin` with Cargo.
3. Copy `bindings/c/include/nono.h` from the upstream checkout.
4. Create `Artifacts/CNono.xcframework` with `xcodebuild -create-xcframework`.
5. Write `Artifacts/MANIFEST.json` with upstream commit, header SHA256, library SHA256 value, target triple, and source repository URL.

The scripts support only `arm64`. `make artifacts` and `make artifacts-arm64` are equivalent.

Required build tools for artifact generation:

1. Xcode command line tools, including `xcodebuild`.
2. Rust toolchain with `cargo`.
3. Rust macOS target `aarch64-apple-darwin` installed via `rustup target add`.

Generated binary artifacts are not versioned. Build `Artifacts/CNono.xcframework` locally before `swift build` or `swift test`. Rebuilding artifacts from source requires Rust/Cargo.

Expected XCFramework build command shape:

```sh
NONO_SRC=.build/nono

cargo build --release --manifest-path "$NONO_SRC/Cargo.toml" -p nono-ffi --target aarch64-apple-darwin

xcodebuild -create-xcframework \
  -library ".build/nono-source-build/cargo-target/aarch64-apple-darwin/release/libnono_ffi.a" \
  -headers .build/CNonoHeaders \
  -output Artifacts/CNono.xcframework
```

Apple Silicon only build command shape:

```sh
./Scripts/build-xcframework.sh --arch arm64
```

The Swift target must link Apple `Security.framework`, matching the Go CGo flags for macOS.

## Public Swift API

### Top-Level Functions

```swift
public func apply(_ capabilities: CapabilitySet) throws
public func sandboxedExec(
    _ capabilities: CapabilitySet,
    command: [String],
    cwd: String?,
    environment: [String: String],
    inheritEnvironment: Bool,
    timeout: TimeInterval?
) throws -> SandboxedExecResult
public var isSupported: Bool { get }
public func supportInfo() -> PlatformInfo
public var version: String { get }
```

Consumers can call these directly after `import NonoSwift` or qualify them with the module name, for example `try NonoSwift.apply(caps)`.

`apply(_:)` is irreversible. On success it must free and invalidate the consumed capability set so later use throws `NonoError.Code.invalidArgument`.

`sandboxedExec` forks a child, applies the capability set in the child, then executes the command. The parent remains unsandboxed and retains ownership of the capability set.

### CapabilitySet

```swift
public final class CapabilitySet: @unchecked Sendable {
    public init()
    deinit

    public func close()

    public func allowPath(_ path: String, access: AccessMode) throws
    public func allowFile(_ path: String, access: AccessMode) throws

    public func setNetworkMode(_ mode: NetworkMode) throws
    public func blockNetwork() throws
    public var networkMode: NetworkMode { get }

    public func setProxyPort(_ port: UInt16) throws
    public var proxyPort: UInt16 { get }

    public func addPlatformRule(_ rule: String) throws

    public func deduplicate() throws
    public func pathCovered(_ path: String) throws -> Bool

    public var isNetworkBlocked: Bool { get }
    public var summary: String { get }
    public var fileSystemCapabilities: [FileSystemCapability] { get }
}
```

`CapabilitySet` owns an opaque `NonoCapabilitySet *`. It must free the pointer in `deinit` and in `close()`. `close()` must be idempotent.

### QueryContext

```swift
public final class QueryContext: @unchecked Sendable {
    public init(capabilities: CapabilitySet) throws
    deinit

    public func close()
    public func queryPath(_ path: String, access: AccessMode) throws -> QueryResult
    public func queryNetwork() throws -> QueryResult
}
```

`QueryContext` owns an opaque `NonoQueryContext *`. It snapshots the capability set during initialization. Changes to the original capability set after initialization must not change the query context.

### SandboxState

```swift
public final class SandboxState: @unchecked Sendable {
    public init(capabilities: CapabilitySet) throws
    public init(json: String) throws
    deinit

    public func close()
    public func json() throws -> String
    public func capabilities() throws -> CapabilitySet
}
```

`SandboxState` owns an opaque `NonoSandboxState *`. It provides JSON serialization and restoration of capability sets.

### Value Types

```swift
public enum AccessMode: UInt32, Sendable, CustomStringConvertible {
    case read = 0
    case write = 1
    case readWrite = 2
}

public enum NetworkMode: UInt32, Sendable, CustomStringConvertible {
    case blocked = 0
    case allowAll = 1
    case proxyOnly = 2
}

public enum CapabilitySource: Int32, Sendable, CustomStringConvertible {
    case user = 0
    case group = 1
    case system = 2
    case profile = 3
}

public enum QueryStatus: Int32, Sendable, CustomStringConvertible {
    case allowed = 0
    case denied = 1
}

public enum QueryReason: Int32, Sendable, CustomStringConvertible {
    case grantedPath = 0
    case networkAllowed = 1
    case pathNotGranted = 2
    case insufficientAccess = 3
    case networkBlocked = 4
}

public struct FileSystemCapability: Sendable, Equatable {
    public let originalPath: String
    public let resolvedPath: String
    public let access: AccessMode
    public let isFile: Bool
    public let source: CapabilitySource
    public let groupName: String
}

public struct QueryResult: Sendable, Equatable {
    public let status: QueryStatus
    public let reason: QueryReason
    public let grantedPath: String
    public let grantedAccess: String
    public let actualAccess: String
    public let requestedAccess: String
}

public struct PlatformInfo: Sendable, Equatable {
    public let isSupported: Bool
    public let platform: String
    public let details: String
}

public struct SandboxedExecResult: Sendable, Equatable {
    public let stdout: Data
    public let stderr: Data
    public let exitCode: Int32
}
```

String descriptions must match `nono-go`:

```text
AccessMode.read -> "read"
AccessMode.write -> "write"
AccessMode.readWrite -> "read-write"
NetworkMode.blocked -> "blocked"
NetworkMode.allowAll -> "allow-all"
NetworkMode.proxyOnly -> "proxy-only"
CapabilitySource.user -> "user"
CapabilitySource.group -> "group"
CapabilitySource.system -> "system"
CapabilitySource.profile -> "profile"
QueryStatus.allowed -> "allowed"
QueryStatus.denied -> "denied"
QueryReason.grantedPath -> "granted-path"
QueryReason.networkAllowed -> "network-allowed"
QueryReason.pathNotGranted -> "path-not-granted"
QueryReason.insufficientAccess -> "insufficient-access"
QueryReason.networkBlocked -> "network-blocked"
```

Unknown raw values should be representable internally when returned by C. If Swift enums cannot represent an unknown value directly, add an internal fallback or expose wrapper structs for C-backed enums before shipping a stable public API.

## Error Model

Expose C error categories as Swift values:

```swift
public struct NonoError: Error, Sendable, Equatable, CustomStringConvertible {
    public enum Code: Int32, Sendable {
        case pathNotFound = -1
        case expectedDirectory = -2
        case expectedFile = -3
        case pathCanonicalization = -4
        case noCapabilities = -5
        case sandboxInit = -6
        case unsupportedPlatform = -7
        case blockedCommand = -8
        case configParse = -9
        case profileParse = -10
        case io = -11
        case invalidArgument = -12
        case trustVerification = -13
        case unknown = -99
    }

    public let code: Code
    public let message: String
}
```

Rules:

1. On failing C calls that return `NonoErrorCode`, immediately call `nono_last_error()`, copy the message, free it with `nono_string_free()`, then call `nono_clear_error()`.
2. For C functions that return `NULL` without a numeric error code, map to `.unknown` and use `nono_last_error()` for the message.
3. For Swift-side validation failures, construct `NonoError(code: .invalidArgument, message: ...)` without reading C thread-local error state.
4. Reject Swift strings containing `\0` before passing them to C.
5. Closed objects should throw `.invalidArgument` from mutating/querying methods. Read-only convenience properties may return safe defaults matching `nono-go`: blocked network mode, proxy port `0`, empty summary, empty capabilities.

## Memory Management

All C-owned strings returned from the FFI must be copied into Swift and freed with `nono_string_free()` exactly once.

Nil C strings map to empty Swift strings.

Free all nullable string fields in `NonoQueryResult`, even when the current reason does not use them.

Opaque pointers must be invalidated after free:

```text
NonoCapabilitySet * -> nono_capability_set_free
NonoQueryContext * -> nono_query_context_free
NonoSandboxState * -> nono_sandbox_state_free
```

## Thread Safety

The Go implementation is thread-safe. The Swift implementation must also be safe for concurrent use.

Use one lock per owning class. `NSLock` is acceptable for the initial implementation; a reader/writer lock can be added later if profiling shows contention.

Do not expose async variants for FFI methods. Error mapping must happen synchronously and immediately after the C call, with no `await`, dispatch, or callback between the failing C call and `nono_last_error()`. This preserves the C library's thread-local last-error behavior.

Classes that are internally locked may be marked `@unchecked Sendable`.

## Behavioral Requirements

The Swift package must preserve these `nono-go` behaviors:

1. `CapabilitySet()` allocates a new empty capability set or traps only on impossible allocation failure.
2. `allowPath` validates that the path exists and is a directory.
3. `allowFile` validates that the path exists and is a file.
4. macOS paths are canonicalized by the C library, including `/var` resolving under `/private/var`.
5. Network mode supports `.blocked`, `.allowAll`, and `.proxyOnly`.
6. Proxy port is meaningful only for `.proxyOnly`.
7. `blockNetwork()` is a non-deprecated convenience equivalent to `setNetworkMode(.blocked)`.
8. Do not expose startup-only command allow/block metadata as sandbox enforcement API.
9. `sandboxedExec` applies the sandbox in a child process before `execve`, captures stdout/stderr, and returns nonzero child exits as `SandboxedExecResult` rather than throwing.
10. `sandboxedExec` must reject empty commands, NUL-containing strings, negative timeouts, invalid environment keys, and dynamic-loader environment variables.
11. `addPlatformRule` accepts macOS Seatbelt S-expressions and may reject malformed or root-granting rules.
12. `deduplicate` keeps the highest access level for overlapping filesystem capabilities.
13. `pathCovered` checks directory capability coverage.
14. `fileSystemCapabilities` returns all filesystem capabilities and skips entries whose access mode is `NONO_ACCESS_MODE_INVALID`.
15. `QueryContext` clones capabilities at creation time.
16. `SandboxState` JSON round-trips capability sets.
17. `apply` applies the sandbox to the current process and all children and is irreversible.

## Example Usage

```swift
import NonoSwift

let caps = CapabilitySet()
defer { caps.close() }

try caps.allowPath("/Users/andrea/data", access: .read)
try caps.allowPath("/tmp", access: .readWrite)
try caps.blockNetwork()

try NonoSwift.apply(caps)
```

Query without applying:

```swift
let caps = CapabilitySet()
try caps.allowPath("/Users/andrea/data", access: .read)
try caps.setNetworkMode(.allowAll)

let query = try QueryContext(capabilities: caps)
let pathResult = try query.queryPath("/Users/andrea/data/file.txt", access: .read)
let networkResult = try query.queryNetwork()
```

Serialize and restore:

```swift
let state = try SandboxState(capabilities: caps)
let json = try state.json()

let restored = try SandboxState(json: json)
let restoredCaps = try restored.capabilities()
```

## Tests

Port the `nono-go` test coverage to Swift where practical.

Required normal tests:

1. Enum descriptions match expected strings.
2. `NonoSwift.version` is non-empty.
3. `NonoSwift.supportInfo()` returns a non-empty platform.
4. `CapabilitySet.close()` is idempotent.
5. Mutating a closed `CapabilitySet` throws `.invalidArgument`.
6. `allowPath` succeeds for a temp directory for all access modes.
7. `allowPath` for a missing path throws `.pathNotFound`.
8. `allowFile` succeeds for a temp file.
9. `allowFile` for a directory throws `.expectedFile`.
10. Strings containing `\0` are rejected with `.invalidArgument`.
11. `networkMode`, `isNetworkBlocked`, and `proxyPort` reflect configured state.
12. `pathCovered` returns true for paths under an allowed directory and false for uncovered paths.
13. `fileSystemCapabilities` exposes original path, resolved path, access, file/directory flag, source, and group name.
14. `QueryContext` allows covered paths and denies uncovered paths.
15. `QueryContext` denies insufficient access with actual and requested access populated.
16. `QueryContext` reports network allowed/blocked correctly.
17. `QueryContext` is a snapshot and does not change after the source `CapabilitySet` is mutated.
18. `SandboxState` serializes to valid JSON and restores equivalent capabilities.
19. Concurrent calls on `CapabilitySet`, `QueryContext`, and `SandboxState` do not crash or race under Thread Sanitizer.

Required gated test:

1. `apply` must be tested only in a subprocess because it is irreversible.
2. Use the `NonoSwiftApplySandboxFixture` executable instead of applying a sandbox inside the XCTest runner.
3. Gate the fixture behind `NONO_REQUIRE_APPLY=1` or equivalent.
4. The child process should allow one temp directory, block network, apply the sandbox, verify allowed access succeeds, and verify an uncovered file access fails.
5. The fixture should be run from a normal shell, not from inside an existing `nono` sandbox, because nested macOS sandbox initialization may fail with `Operation not permitted`.

## Acceptance Criteria

The package is complete when:

1. `swift build` succeeds on Apple Silicon macOS after `make artifacts`.
2. `swift test` succeeds without applying a sandbox to the test runner process.
3. The gated subprocess apply test passes on macOS when explicitly enabled.
4. A downstream Swift package can add this package and `import NonoSwift` without custom linker flags.
5. The package does not require Go or CGo for any build path.
6. Swift builds do not require Rust or Cargo once `Artifacts/CNono.xcframework` has been generated locally.
7. Source artifact generation builds upstream `nono-ffi` with Cargo for arm64 macOS.
8. The artifact manifest verifies the source-built header and libraries against recorded SHA256 values.
9. README documents irreversible sandbox application, macOS `/var` canonicalization, artifact rebuilding from source, and the subprocess testing requirement.

## Future Scope

Linux support can be added later, but it should not block the macOS package. SwiftPM binary targets are Apple-focused, so Linux support may require a separate source-based C target, system library target, or artifact bundle strategy.
