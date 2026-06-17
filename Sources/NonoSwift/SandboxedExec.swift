import CNono
import Darwin
import Foundation

@_silgen_name("fork")
private func systemFork() -> pid_t

public struct SandboxedExecResult: Sendable, Hashable {
    public let stdout: Data
    public let stderr: Data
    public let exitCode: Int32

    public init(stdout: Data, stderr: Data, exitCode: Int32) {
        self.stdout = stdout
        self.stderr = stderr
        self.exitCode = exitCode
    }
}

public func sandboxedExec(
    _ capabilities: CapabilitySet,
    command: [String],
    cwd: String? = nil,
    environment: [String: String] = [:],
    inheritEnvironment: Bool = false,
    timeout: TimeInterval? = nil
) throws -> SandboxedExecResult {
    guard let executable = command.first, !executable.isEmpty else {
        throw staticError(.invalidArgument, "command must not be empty")
    }
    if let timeout, timeout < 0 {
        throw staticError(.invalidArgument, "timeout must not be negative")
    }

    try command.forEach(checkNoNUL)
    if let cwd {
        try checkNoNUL(cwd)
    }

    let childEnvironment = try makeChildEnvironment(
        overrides: environment,
        inheritEnvironment: inheritEnvironment
    )
    let executablePath = try resolveExecutablePath(executable, environment: childEnvironment)
    let argv = try CStringArray([executablePath] + command.dropFirst())
    let envp = try CStringArray(childEnvironment.map { key, value in "\(key)=\(value)" }.sorted())
    let cwdPath = try cwd.map { try CStringBox($0) }
    let execPath = try CStringBox(executablePath)

    var stdoutPipe: [Int32] = [-1, -1]
    var stderrPipe: [Int32] = [-1, -1]
    guard pipe(&stdoutPipe) == 0 else {
        throw posixError("pipe stdout failed", errno)
    }
    guard pipe(&stderrPipe) == 0 else {
        closePair(stdoutPipe)
        throw posixError("pipe stderr failed", errno)
    }

    capabilities.lock.lock()
    guard let capabilityPointer = capabilities.pointer else {
        capabilities.lock.unlock()
        closePair(stdoutPipe)
        closePair(stderrPipe)
        throw staticError(.invalidArgument, CapabilitySet.closedMessage)
    }

    let pid = systemFork()
    if pid == -1 {
        let code = errno
        capabilities.lock.unlock()
        closePair(stdoutPipe)
        closePair(stderrPipe)
        throw posixError("fork failed", code)
    }

    if pid == 0 {
        runSandboxedExecChild(
            capabilityPointer: capabilityPointer,
            executablePath: execPath.pointer,
            argv: argv.pointer,
            envp: envp.pointer,
            cwd: cwdPath?.pointer,
            stdoutPipe: stdoutPipe,
            stderrPipe: stderrPipe
        )
    }

    capabilities.lock.unlock()

    close(stdoutPipe[1])
    close(stderrPipe[1])

    do {
        return try collectChildResult(
            pid: pid,
            stdoutFD: stdoutPipe[0],
            stderrFD: stderrPipe[0],
            timeout: timeout
        )
    } catch {
        close(stdoutPipe[0])
        close(stderrPipe[0])
        throw error
    }
}

private final class CStringBox {
    let pointer: UnsafeMutablePointer<CChar>

    init(_ string: String) throws {
        guard let pointer = strdup(string) else {
            throw staticError(.io, "failed to allocate C string")
        }
        self.pointer = pointer
    }

    deinit {
        free(pointer)
    }
}

private final class CStringArray {
    private let strings: [UnsafeMutablePointer<CChar>]
    let pointer: UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>

    init<S: Sequence>(_ values: S) throws where S.Element == String {
        var strings: [UnsafeMutablePointer<CChar>] = []
        for value in values {
            guard let string = strdup(value) else {
                strings.forEach { free($0) }
                throw staticError(.io, "failed to allocate C string")
            }
            strings.append(string)
        }

        let pointer = UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>.allocate(capacity: strings.count + 1)
        for index in strings.indices {
            pointer[index] = strings[index]
        }
        pointer[strings.count] = nil

        self.strings = strings
        self.pointer = pointer
    }

    deinit {
        strings.forEach { free($0) }
        pointer.deallocate()
    }
}

private func makeChildEnvironment(
    overrides: [String: String],
    inheritEnvironment: Bool
) throws -> [String: String] {
    var result = inheritEnvironment ? ProcessInfo.processInfo.environment : [:]
    for (key, value) in overrides {
        result[key] = value
    }

    for (key, value) in result {
        guard !key.isEmpty, !key.contains("=") else {
            throw staticError(.invalidArgument, "environment keys must be non-empty and must not contain '='")
        }
        try checkNoNUL(key)
        try checkNoNUL(value)
        if isDynamicLoaderEnvironmentKey(key) {
            throw staticError(.invalidArgument, "dynamic loader environment variables are not allowed")
        }
    }

    return result
}

private func isDynamicLoaderEnvironmentKey(_ key: String) -> Bool {
    key.hasPrefix("DYLD_") || key.hasPrefix("LD_")
}

private func resolveExecutablePath(_ executable: String, environment: [String: String]) throws -> String {
    if executable.contains("/") {
        return executable
    }

    let pathValue = environment["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin"
    for directory in pathValue.split(separator: ":", omittingEmptySubsequences: false) {
        let candidateDirectory = directory.isEmpty ? "." : String(directory)
        let candidate = URL(fileURLWithPath: candidateDirectory, isDirectory: true)
            .appendingPathComponent(executable)
            .path
        if access(candidate, X_OK) == 0 {
            return candidate
        }
    }

    throw staticError(.pathNotFound, "executable not found: \(executable)")
}

private func runSandboxedExecChild(
    capabilityPointer: OpaquePointer,
    executablePath: UnsafePointer<CChar>,
    argv: UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>,
    envp: UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>,
    cwd: UnsafePointer<CChar>?,
    stdoutPipe: [Int32],
    stderrPipe: [Int32]
) -> Never {
    close(stdoutPipe[0])
    close(stderrPipe[0])

    if dup2(stdoutPipe[1], STDOUT_FILENO) == -1 {
        _exit(126)
    }
    if dup2(stderrPipe[1], STDERR_FILENO) == -1 {
        _exit(126)
    }
    close(stdoutPipe[1])
    close(stderrPipe[1])

    if let cwd, chdir(cwd) == -1 {
        writeErrno("chdir failed", errno)
        _exit(126)
    }

    let devNull = open("/dev/null", O_RDONLY)
    if devNull >= 0 {
        _ = dup2(devNull, STDIN_FILENO)
        close(devNull)
    }

    let code = nono_sandbox_apply(capabilityPointer)
    if !isOK(code) {
        writeCString("sandbox apply failed: ")
        if let message = nono_last_error() {
            writeRawCString(message)
            nono_string_free(message)
        } else {
            writeCString("unknown error")
        }
        writeCString("\n")
        nono_clear_error()
        _exit(126)
    }

    execve(executablePath, argv, envp)
    writeErrno("execve failed", errno)
    _exit(127)
}

private func collectChildResult(
    pid: pid_t,
    stdoutFD: Int32,
    stderrFD: Int32,
    timeout: TimeInterval?
) throws -> SandboxedExecResult {
    try setNonBlocking(stdoutFD)
    try setNonBlocking(stderrFD)

    var stdout = Data()
    var stderr = Data()
    var stdoutOpen = true
    var stderrOpen = true
    var status: Int32 = 0
    var didExit = false
    let deadline = timeout.map { Date().addingTimeInterval($0) }

    while stdoutOpen || stderrOpen || !didExit {
        var observedChildExit = false

        if stdoutOpen {
            stdoutOpen = try drainPipe(stdoutFD, into: &stdout)
        }
        if stderrOpen {
            stderrOpen = try drainPipe(stderrFD, into: &stderr)
        }

        if !didExit {
            let waitResult = waitpid(pid, &status, WNOHANG)
            if waitResult == pid {
                didExit = true
                observedChildExit = true
            } else if waitResult == -1, errno != EINTR {
                throw posixError("waitpid failed", errno)
            }
        }

        if !didExit, let deadline, Date() >= deadline {
            kill(pid, SIGKILL)
            while waitpid(pid, &status, 0) == -1, errno == EINTR {}
            didExit = true
            observedChildExit = true
        }

        if observedChildExit {
            continue
        }

        // Descendants can inherit stdout/stderr and keep pipes open after the
        // direct child exits. Drain what is immediately available, then finish.
        if didExit, stdoutOpen || stderrOpen {
            break
        }

        if stdoutOpen || stderrOpen || !didExit {
            usleep(10_000)
        }
    }

    close(stdoutFD)
    close(stderrFD)

    return SandboxedExecResult(
        stdout: stdout,
        stderr: stderr,
        exitCode: exitCode(fromWaitStatus: status)
    )
}

private func drainPipe(_ fd: Int32, into data: inout Data) throws -> Bool {
    var buffer = [UInt8](repeating: 0, count: 8192)
    while true {
        let count = buffer.withUnsafeMutableBytes { rawBuffer in
            read(fd, rawBuffer.baseAddress, rawBuffer.count)
        }

        if count > 0 {
            data.append(contentsOf: buffer.prefix(Int(count)))
            continue
        }
        if count == 0 {
            return false
        }
        if errno == EINTR {
            continue
        }
        if errno == EAGAIN || errno == EWOULDBLOCK {
            return true
        }
        throw posixError("read pipe failed", errno)
    }
}

private func setNonBlocking(_ fd: Int32) throws {
    let flags = fcntl(fd, F_GETFL, 0)
    guard flags != -1 else {
        throw posixError("fcntl F_GETFL failed", errno)
    }
    guard fcntl(fd, F_SETFL, flags | O_NONBLOCK) != -1 else {
        throw posixError("fcntl F_SETFL failed", errno)
    }
}

private func exitCode(fromWaitStatus status: Int32) -> Int32 {
    if (status & 0x7f) == 0 {
        return (status >> 8) & 0xff
    }
    return -(status & 0x7f)
}

private func closePair(_ fds: [Int32]) {
    for fd in fds where fd >= 0 {
        close(fd)
    }
}

private func posixError(_ message: String, _ code: Int32) -> NonoError {
    staticError(.io, "\(message): \(String(cString: strerror(code)))")
}

private func writeErrno(_ prefix: String, _ code: Int32) {
    writeCString("\(prefix): \(String(cString: strerror(code)))\n")
}

private func writeCString(_ string: String) {
    string.withCString { pointer in
        writeRawCString(pointer)
    }
}

private func writeRawCString(_ pointer: UnsafePointer<CChar>) {
    _ = write(STDERR_FILENO, pointer, strlen(pointer))
}
