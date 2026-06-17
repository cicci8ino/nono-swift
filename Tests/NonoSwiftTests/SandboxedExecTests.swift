import Foundation
import XCTest
import NonoSwift

final class SandboxedExecTests: XCTestCase {
    func testRejectsEmptyCommand() {
        let caps = CapabilitySet()
        defer { caps.close() }

        assertThrowsNonoError(code: .invalidArgument) {
            _ = try sandboxedExec(caps, command: [])
        }
    }

    func testRejectsNULInCommand() {
        let caps = CapabilitySet()
        defer { caps.close() }

        assertThrowsNonoError(code: .invalidArgument) {
            _ = try sandboxedExec(caps, command: ["/bin/echo", "hello\0world"])
        }
    }

    func testRejectsNegativeTimeout() {
        let caps = CapabilitySet()
        defer { caps.close() }

        assertThrowsNonoError(code: .invalidArgument) {
            _ = try sandboxedExec(caps, command: ["/bin/echo", "hello"], timeout: -1)
        }
    }

    func testRejectsInvalidEnvironmentKey() {
        let caps = CapabilitySet()
        defer { caps.close() }

        assertThrowsNonoError(code: .invalidArgument) {
            _ = try sandboxedExec(
                caps,
                command: ["/bin/echo", "hello"],
                environment: ["BAD=KEY": "value"]
            )
        }
    }

    func testRejectsDynamicLoaderEnvironmentVariables() {
        let caps = CapabilitySet()
        defer { caps.close() }

        assertThrowsNonoError(code: .invalidArgument) {
            _ = try sandboxedExec(
                caps,
                command: ["/bin/echo", "hello"],
                environment: ["DYLD_INSERT_LIBRARIES": "/tmp/lib.dylib"]
            )
        }
    }

    func testRejectsClosedCapabilitySet() {
        let caps = CapabilitySet()
        caps.close()

        assertThrowsNonoError(code: .invalidArgument) {
            _ = try sandboxedExec(caps, command: ["/bin/echo", "hello"])
        }
    }

    func testRejectsUnresolvedExecutableName() {
        let caps = CapabilitySet()
        defer { caps.close() }

        assertThrowsNonoError(code: .pathNotFound) {
            _ = try sandboxedExec(caps, command: ["nono-swift-missing-executable"])
        }
    }

    func testRunsCommandInSandboxedChild() throws {
        let caps = CapabilitySet()
        defer { caps.close() }

        let result = try sandboxedExec(caps, command: ["/bin/echo", "hello"], timeout: 5)
        try skipIfNestedSandboxIsBlocked(result)

        XCTAssertEqual(result.exitCode, 0, String(decoding: result.stderr, as: UTF8.self))
        XCTAssertEqual(String(decoding: result.stdout, as: UTF8.self), "hello\n")
    }

    func testTimeoutKillsChild() throws {
        let caps = CapabilitySet()
        defer { caps.close() }

        let result = try sandboxedExec(caps, command: ["/bin/sleep", "2"], timeout: 0.1)
        try skipIfNestedSandboxIsBlocked(result)

        XCTAssertEqual(result.exitCode, -9, String(decoding: result.stderr, as: UTF8.self))
    }

    private func skipIfNestedSandboxIsBlocked(_ result: SandboxedExecResult) throws {
        let stderr = String(decoding: result.stderr, as: UTF8.self)
        if result.exitCode == 126, stderr.contains("sandbox apply failed") {
            throw XCTSkip(stderr)
        }
    }
}
