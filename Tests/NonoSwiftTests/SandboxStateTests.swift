import Foundation
import XCTest
import NonoSwift

final class SandboxStateTests: XCTestCase {
    func testJSONRoundTrip() throws {
        let directory = try makeTemporaryDirectory()
        let caps = CapabilitySet()
        defer { caps.close() }

        try caps.allowPath(directory.path, access: .readWrite)
        try caps.setNetworkMode(.blocked)

        let state = try SandboxState(capabilities: caps)
        defer { state.close() }

        let json = try state.json()
        let object = try JSONSerialization.jsonObject(with: Data(json.utf8))
        XCTAssertTrue(JSONSerialization.isValidJSONObject(object))

        let restoredState = try SandboxState(json: json)
        defer { restoredState.close() }

        let restoredCaps = try restoredState.capabilities()
        defer { restoredCaps.close() }

        XCTAssertEqual(restoredCaps.networkMode, .blocked)
        XCTAssertEqual(restoredCaps.fileSystemCapabilities.first?.access, .readWrite)
    }

    func testClosedStateThrowsInvalidArgument() throws {
        let directory = try makeTemporaryDirectory()
        let caps = CapabilitySet()
        defer { caps.close() }

        try caps.allowPath(directory.path, access: .read)
        let state = try SandboxState(capabilities: caps)
        state.close()

        assertThrowsNonoError(code: .invalidArgument) {
            _ = try state.json()
        }
        assertThrowsNonoError(code: .invalidArgument) {
            _ = try state.capabilities()
        }
    }

    func testStateFromClosedCapabilitySetThrows() {
        let caps = CapabilitySet()
        caps.close()

        assertThrowsNonoError(code: .invalidArgument) {
            _ = try SandboxState(capabilities: caps)
        }
    }

    func testInvalidJSONThrowsUnknown() {
        assertThrowsNonoError(code: .unknown) {
            _ = try SandboxState(json: "{not-json")
        }
    }

    func testJSONRejectsNUL() {
        assertThrowsNonoError(code: .invalidArgument) {
            _ = try SandboxState(json: "{\"key\":\0\"value\"}")
        }
    }

    func testConcurrentJSONSerialization() throws {
        let directory = try makeTemporaryDirectory()
        let caps = CapabilitySet()
        defer { caps.close() }

        try caps.allowPath(directory.path, access: .read)
        let state = try SandboxState(capabilities: caps)
        defer { state.close() }

        let errorLock = NSLock()
        var failures: [String] = []

        DispatchQueue.concurrentPerform(iterations: 100) { _ in
            do {
                let json = try state.json()
                let object = try JSONSerialization.jsonObject(with: Data(json.utf8))
                if !JSONSerialization.isValidJSONObject(object) {
                    errorLock.lock()
                    failures.append("invalid JSON object")
                    errorLock.unlock()
                }
            } catch {
                errorLock.lock()
                failures.append(String(describing: error))
                errorLock.unlock()
            }
        }

        XCTAssertTrue(failures.isEmpty, failures.joined(separator: "\n"))
    }
}
