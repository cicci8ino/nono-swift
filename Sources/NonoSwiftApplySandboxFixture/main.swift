import Foundation
import Darwin
import NonoSwift

func log(_ message: String) {
    FileHandle.standardError.write(Data("[NonoSwiftApplySandboxFixture] \(message)\n".utf8))
}

func canonicalPath(_ url: URL) -> String {
    guard let resolved = realpath(url.path, nil) else {
        return (url.path as NSString).resolvingSymlinksInPath
    }
    defer { free(resolved) }
    return String(cString: resolved)
}

enum FixtureError: Error, CustomStringConvertible {
    case unexpectedSuccess(String)
    case missingCommand(String)
    case networkAccessWasNotBlocked(errno: Int32)
    case processLaunchFailed(path: String, errno: Int32)
    case commandFailed(path: String, status: Int32, output: String)
    case waitFailed(errno: Int32)
    case stringAllocationFailed
    case unknownScenario(String)

    var description: String {
        switch self {
        case .unexpectedSuccess(let operation):
            return "\(operation) unexpectedly succeeded"
        case .missingCommand(let path):
            return "\(path) is not available or not executable"
        case .networkAccessWasNotBlocked(let code):
            return "network access was not blocked; errno=\(code)"
        case .processLaunchFailed(let path, let code):
            return "\(path) failed to launch; errno=\(code)"
        case .commandFailed(let path, let status, let output):
            return "\(path) failed with status \(status): \(output)"
        case .waitFailed(let code):
            return "waitpid failed; errno=\(code)"
        case .stringAllocationFailed:
            return "failed to allocate process argument string"
        case .unknownScenario(let scenario):
            return "unknown apply fixture scenario: \(scenario)"
        }
    }
}

func expectFailure(_ operation: String, _ body: () throws -> Void) throws {
    log("expecting denial: \(operation)")
    do {
        try body()
    } catch {
        log("denied as expected: \(operation) (\(error))")
        return
    }
    throw FixtureError.unexpectedSuccess(operation)
}

func verifyNetworkBlocked() throws {
    log("checking network is blocked")
    let fileDescriptor = socket(AF_INET, SOCK_STREAM, 0)
    if fileDescriptor == -1 {
        if errno == EPERM || errno == EACCES {
            log("network socket creation denied as expected")
            return
        }
        throw FixtureError.networkAccessWasNotBlocked(errno: errno)
    }
    defer { close(fileDescriptor) }

    var address = sockaddr_in()
    address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
    address.sin_family = sa_family_t(AF_INET)
    address.sin_port = in_port_t(9).bigEndian
    address.sin_addr = in_addr(s_addr: inet_addr("127.0.0.1"))

    let result = withUnsafePointer(to: &address) { pointer in
        pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { socketAddress in
            connect(fileDescriptor, socketAddress, socklen_t(MemoryLayout<sockaddr_in>.size))
        }
    }

    if result == -1, errno == EPERM || errno == EACCES {
        log("network connect denied as expected")
        return
    }

    throw FixtureError.networkAccessWasNotBlocked(errno: result == -1 ? errno : 0)
}

func withCStringArray<T>(_ strings: [String], _ body: (UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>) throws -> T) throws -> T {
    var cStrings: [UnsafeMutablePointer<CChar>?] = []
    cStrings.reserveCapacity(strings.count + 1)

    for string in strings {
        guard let cString = strdup(string) else {
            throw FixtureError.stringAllocationFailed
        }
        cStrings.append(cString)
    }
    cStrings.append(nil)
    defer {
        for cString in cStrings {
            free(cString)
        }
    }

    return try cStrings.withUnsafeMutableBufferPointer { buffer in
        try body(buffer.baseAddress!)
    }
}

func waitForProcess(_ pid: pid_t) throws -> Int32 {
    var status: Int32 = 0

    while true {
        let result = waitpid(pid, &status, 0)
        if result == pid {
            break
        }
        if result == -1, errno == EINTR {
            continue
        }
        throw FixtureError.waitFailed(errno: errno)
    }

    if (status & 0x7f) == 0 {
        return (status >> 8) & 0xff
    }
    return 128 + (status & 0x7f)
}

func spawnProcess(path: String, arguments: [String], environment: [String]) throws -> Int32 {
    var pid: pid_t = 0

    return try withCStringArray([path] + arguments) { argv in
        try withCStringArray(environment) { envp in
            let spawnResult = path.withCString { cPath in
                posix_spawn(&pid, cPath, nil, nil, argv, envp)
            }

            guard spawnResult == 0 else {
                throw FixtureError.processLaunchFailed(path: path, errno: spawnResult)
            }

            return try waitForProcess(pid)
        }
    }
}

func commandEnvironment(home: URL) -> [String] {
    let homePath = home.path
    return [
        "HOME=\(homePath)",
        "TMPDIR=\(homePath)",
        "XDG_CONFIG_HOME=\(homePath)",
        "PATH=/usr/bin:/bin"
    ]
}

func verifyProcessDenied(path: String, arguments: [String], home: URL, stage: String) throws {
    log("checking \(path) is denied \(stage)")

    do {
        let status = try spawnProcess(path: path, arguments: arguments, environment: commandEnvironment(home: home))
        if status != 0 {
            log("\(path) exited non-zero as expected (status \(status))")
            return
        }
    } catch FixtureError.processLaunchFailed(_, let code) {
        log("\(path) launch denied as expected (errno=\(code))")
        return
    }

    throw FixtureError.unexpectedSuccess("\(path) execution")
}

func verifyProcessRuns(path: String, arguments: [String], home: URL, stage: String) throws {
    log("checking \(path) runs \(stage)")

    let status = try spawnProcess(path: path, arguments: arguments, environment: commandEnvironment(home: home))
    guard status == 0 else {
        throw FixtureError.commandFailed(path: path, status: status, output: "")
    }

    log("\(path) succeeded \(stage)")
}

func applySandbox(_ caps: CapabilitySet) throws -> Bool {
    do {
        try NonoSwift.apply(caps)
        return true
    } catch {
        if ProcessInfo.processInfo.environment["NONO_REQUIRE_APPLY"] == "1" {
            throw error
        }
        log("sandbox apply skipped: \(error)")
        return false
    }
}

struct FixtureCommand {
    let path: String
    let arguments: [String]
}

func requireCommandExists(_ fileManager: FileManager) throws -> FixtureCommand {
    let command = "/usr/bin/whoami"

    guard fileManager.isExecutableFile(atPath: command) else {
        throw FixtureError.missingCommand(command)
    }

    log("using command at \(command)")
    return FixtureCommand(path: command, arguments: [])
}

func addReadablePathIfDirectoryExists(_ path: String, to caps: CapabilitySet) throws {
    var isDirectory: ObjCBool = false
    guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory), isDirectory.boolValue else {
        return
    }

    try caps.allowPath(canonicalPath(URL(fileURLWithPath: path, isDirectory: true)), access: .read)
}

func addSystemRuntimeReadGrants(to caps: CapabilitySet) throws {
    for path in [
        "/usr",
        "/bin",
        "/System",
        "/etc",
        "/private/etc",
        "/Library",
        "/Applications/Xcode.app",
        "/Library/Developer"
    ] {
        try addReadablePathIfDirectoryExists(path, to: caps)
    }
}

struct FixtureTree {
    let root: URL
    let canonicalReadWriteDirectory: String
    let canonicalReadOnlyDirectory: String
    let canonicalReadWriteFile: URL
    let canonicalReadOnlyFile: URL
    let canonicalDeniedFile: URL
    let canonicalReadWriteCreatedFile: URL
    let canonicalReadOnlyCreatedFile: URL
    let canonicalDeniedCreatedFile: URL
}

func makeFixtureTree() throws -> FixtureTree {
    let fileManager = FileManager.default

    let root = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("nono-swift-apply-\(UUID().uuidString)", isDirectory: true)
    let readWriteDirectory = root.appendingPathComponent("read-write", isDirectory: true)
    let readOnlyDirectory = root.appendingPathComponent("read-only", isDirectory: true)
    let deniedDirectory = root.appendingPathComponent("denied", isDirectory: true)
    let readWriteFile = readWriteDirectory.appendingPathComponent("read-write.txt")
    let readOnlyFile = readOnlyDirectory.appendingPathComponent("read-only.txt")
    let deniedFile = deniedDirectory.appendingPathComponent("denied.txt")

    log("creating temporary sandbox fixture tree at \(root.path)")
    try fileManager.createDirectory(at: readWriteDirectory, withIntermediateDirectories: true)
    try fileManager.createDirectory(at: readOnlyDirectory, withIntermediateDirectories: true)
    try fileManager.createDirectory(at: deniedDirectory, withIntermediateDirectories: true)
    try "read-write".write(to: readWriteFile, atomically: true, encoding: .utf8)
    try "read-only".write(to: readOnlyFile, atomically: true, encoding: .utf8)
    try "denied".write(to: deniedFile, atomically: true, encoding: .utf8)

    let canonicalReadWriteDirectory = canonicalPath(readWriteDirectory)
    let canonicalReadOnlyDirectory = canonicalPath(readOnlyDirectory)
    let canonicalReadWriteFile = URL(fileURLWithPath: canonicalPath(readWriteFile))
    let canonicalReadOnlyFile = URL(fileURLWithPath: canonicalPath(readOnlyFile))
    let canonicalDeniedFile = URL(fileURLWithPath: canonicalPath(deniedFile))
    let canonicalReadWriteCreatedFile = URL(fileURLWithPath: canonicalReadWriteDirectory)
        .appendingPathComponent("created-after-apply.txt")
    let canonicalReadOnlyCreatedFile = URL(fileURLWithPath: canonicalReadOnlyDirectory)
        .appendingPathComponent("created-after-apply.txt")
    let canonicalDeniedCreatedFile = URL(fileURLWithPath: canonicalPath(deniedDirectory))
        .appendingPathComponent("created-after-apply.txt")
    log("canonical read-write directory: \(canonicalReadWriteDirectory)")
    log("canonical read-only directory: \(canonicalReadOnlyDirectory)")
    log("canonical denied file: \(canonicalDeniedFile.path)")

    return FixtureTree(
        root: root,
        canonicalReadWriteDirectory: canonicalReadWriteDirectory,
        canonicalReadOnlyDirectory: canonicalReadOnlyDirectory,
        canonicalReadWriteFile: canonicalReadWriteFile,
        canonicalReadOnlyFile: canonicalReadOnlyFile,
        canonicalDeniedFile: canonicalDeniedFile,
        canonicalReadWriteCreatedFile: canonicalReadWriteCreatedFile,
        canonicalReadOnlyCreatedFile: canonicalReadOnlyCreatedFile,
        canonicalDeniedCreatedFile: canonicalDeniedCreatedFile
    )
}

func verifyFilesystemEnforcement(_ tree: FixtureTree) throws {
    log("checking read from read-write grant")
    _ = try String(contentsOf: tree.canonicalReadWriteFile, encoding: .utf8)
    log("checking write inside read-write grant")
    try "created".write(to: tree.canonicalReadWriteCreatedFile, atomically: false, encoding: .utf8)
    log("checking read of newly written file inside read-write grant")
    _ = try String(contentsOf: tree.canonicalReadWriteCreatedFile, encoding: .utf8)

    log("checking read from read-only grant")
    _ = try String(contentsOf: tree.canonicalReadOnlyFile, encoding: .utf8)
    try expectFailure("write inside read-only capability") {
        try "should fail".write(to: tree.canonicalReadOnlyCreatedFile, atomically: false, encoding: .utf8)
    }

    try expectFailure("read outside capabilities") {
        _ = try String(contentsOf: tree.canonicalDeniedFile, encoding: .utf8)
    }
    try expectFailure("write outside capabilities") {
        try "should fail".write(to: tree.canonicalDeniedCreatedFile, atomically: false, encoding: .utf8)
    }
}

func runMinimalFilesystemScenario() throws {
    log("starting scenario: minimal-filesystem-network")

    let fileManager = FileManager.default
    let command = try requireCommandExists(fileManager)
    let tree = try makeFixtureTree()
    let commandHome = URL(fileURLWithPath: tree.canonicalReadWriteDirectory)

    try verifyProcessRuns(
        path: command.path,
        arguments: command.arguments,
        home: commandHome,
        stage: "before sandbox"
    )

    let caps = CapabilitySet()
    try caps.allowPath(tree.canonicalReadWriteDirectory, access: .readWrite)
    try caps.allowPath(tree.canonicalReadOnlyDirectory, access: .read)
    try caps.addPlatformRule("(deny process-exec* (literal \"\(command.path)\"))")
    try caps.setNetworkMode(.blocked)

    log("configured capabilities:")
    log(caps.summary)

    log("applying sandbox to fixture process")

    guard try applySandbox(caps) else {
        return
    }

    log("sandbox applied")

    try verifyFilesystemEnforcement(tree)
    try verifyNetworkBlocked()
    try verifyProcessDenied(
        path: command.path,
        arguments: command.arguments,
        home: commandHome,
        stage: "after sandbox"
    )
    log("scenario minimal-filesystem-network verified")
}

func runProcessesWithSystemGrantsScenario() throws {
    log("starting scenario: processes-run-with-system-grants")

    let fileManager = FileManager.default
    let command = try requireCommandExists(fileManager)
    let tree = try makeFixtureTree()
    let commandHome = URL(fileURLWithPath: tree.canonicalReadWriteDirectory)

    try verifyProcessRuns(
        path: command.path,
        arguments: command.arguments,
        home: commandHome,
        stage: "before sandbox"
    )

    let caps = CapabilitySet()
    try caps.allowPath(tree.canonicalReadWriteDirectory, access: .readWrite)
    try caps.allowPath(tree.canonicalReadOnlyDirectory, access: .read)
    try addSystemRuntimeReadGrants(to: caps)
    try caps.setNetworkMode(.blocked)

    log("configured capabilities:")
    log(caps.summary)

    log("applying sandbox to fixture process")
    guard try applySandbox(caps) else {
        return
    }
    log("sandbox applied")

    try verifyFilesystemEnforcement(tree)
    try verifyNetworkBlocked()
    try verifyProcessRuns(
        path: command.path,
        arguments: command.arguments,
        home: commandHome,
        stage: "after sandbox"
    )
    log("scenario processes-run-with-system-grants verified")
}

func run() throws {
    let scenario = ProcessInfo.processInfo.environment["NONO_APPLY_SCENARIO"] ?? "minimal-filesystem-network"
    switch scenario {
    case "minimal-filesystem-network":
        try runMinimalFilesystemScenario()
    case "processes-run-with-system-grants":
        try runProcessesWithSystemGrantsScenario()
    default:
        throw FixtureError.unknownScenario(scenario)
    }
}

do {
    try run()
} catch {
    FileHandle.standardError.write(Data("\(error)\n".utf8))
    exit(1)
}
