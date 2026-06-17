import XCTest
import Foundation
import NonoSwift

final class QueryContextTests: XCTestCase {
    func testQueryPathAllowedAndDenied() throws {
        let directory = try makeTemporaryDirectory()
        let caps = CapabilitySet()
        defer { caps.close() }

        try caps.allowPath(directory.path, access: .read)
        let query = try QueryContext(capabilities: caps)
        defer { query.close() }

        let allowed = try query.queryPath(directory.appendingPathComponent("file.txt").path, access: .read)
        XCTAssertEqual(allowed.status, .allowed)
        XCTAssertEqual(allowed.reason, .grantedPath)
        XCTAssertFalse(allowed.grantedPath.isEmpty)

        let denied = try query.queryPath("/definitely-not-covered-by-nono-swift", access: .read)
        XCTAssertEqual(denied.status, .denied)
        XCTAssertEqual(denied.reason, .pathNotGranted)
    }

    func testQueryPathInsufficientAccess() throws {
        let directory = try makeTemporaryDirectory()
        let caps = CapabilitySet()
        defer { caps.close() }

        try caps.allowPath(directory.path, access: .read)
        let query = try QueryContext(capabilities: caps)
        defer { query.close() }

        let result = try query.queryPath(directory.appendingPathComponent("file.txt").path, access: .write)
        XCTAssertEqual(result.status, .denied)
        XCTAssertEqual(result.reason, .insufficientAccess)
        XCTAssertEqual(result.actualAccess, "read")
        XCTAssertEqual(result.requestedAccess, "write")
    }

    func testQueryNetwork() throws {
        let caps = CapabilitySet()
        defer { caps.close() }

        try caps.setNetworkMode(.allowAll)
        let allowed = try QueryContext(capabilities: caps)
        defer { allowed.close() }
        XCTAssertEqual(try allowed.queryNetwork().status, .allowed)
        XCTAssertEqual(try allowed.queryNetwork().reason, .networkAllowed)

        try caps.setNetworkMode(.blocked)
        let blocked = try QueryContext(capabilities: caps)
        defer { blocked.close() }
        XCTAssertEqual(try blocked.queryNetwork().status, .denied)
        XCTAssertEqual(try blocked.queryNetwork().reason, .networkBlocked)
    }

    func testQueryNetworkBlockedStringFieldsAreEmpty() throws {
        let caps = CapabilitySet()
        defer { caps.close() }

        try caps.setNetworkMode(.blocked)
        let query = try QueryContext(capabilities: caps)
        defer { query.close() }

        let result = try query.queryNetwork()
        XCTAssertEqual(result.status, .denied)
        XCTAssertEqual(result.reason, .networkBlocked)
        XCTAssertEqual(result.grantedPath, "")
        XCTAssertEqual(result.grantedAccess, "")
        XCTAssertEqual(result.actualAccess, "")
        XCTAssertEqual(result.requestedAccess, "")
    }

    func testQueryContextSnapshotsCapabilities() throws {
        let firstDirectory = try makeTemporaryDirectory(name: "first-\(UUID().uuidString)")
        let secondDirectory = try makeTemporaryDirectory(name: "second-\(UUID().uuidString)")
        let caps = CapabilitySet()
        defer { caps.close() }

        try caps.allowPath(firstDirectory.path, access: .read)
        let query = try QueryContext(capabilities: caps)
        defer { query.close() }

        try caps.allowPath(secondDirectory.path, access: .read)

        let result = try query.queryPath(secondDirectory.appendingPathComponent("file.txt").path, access: .read)
        XCTAssertEqual(result.status, .denied)
        XCTAssertEqual(result.reason, .pathNotGranted)
    }

    func testCloseIsIdempotent() throws {
        let directory = try makeTemporaryDirectory()
        let caps = CapabilitySet()
        defer { caps.close() }

        try caps.allowPath(directory.path, access: .read)
        let query = try QueryContext(capabilities: caps)

        query.close()
        query.close()
    }

    func testClosedQueryContextThrowsInvalidArgument() throws {
        let directory = try makeTemporaryDirectory()
        let caps = CapabilitySet()
        defer { caps.close() }

        try caps.allowPath(directory.path, access: .read)
        let query = try QueryContext(capabilities: caps)
        query.close()

        assertThrowsNonoError(code: .invalidArgument) {
            _ = try query.queryPath(directory.path, access: .read)
        }
        assertThrowsNonoError(code: .invalidArgument) {
            _ = try query.queryNetwork()
        }
    }

    func testQueryPathRejectsNUL() throws {
        let directory = try makeTemporaryDirectory()
        let caps = CapabilitySet()
        defer { caps.close() }

        try caps.allowPath(directory.path, access: .read)
        let query = try QueryContext(capabilities: caps)
        defer { query.close() }

        assertThrowsNonoError(code: .invalidArgument) {
            _ = try query.queryPath("/tmp\0truncated", access: .read)
        }
    }

    func testQueryContextFromClosedCapabilitySetThrows() throws {
        let caps = CapabilitySet()
        caps.close()

        assertThrowsNonoError(code: .invalidArgument) {
            _ = try QueryContext(capabilities: caps)
        }
    }

    func testConcurrentQueryContextAccess() throws {
        let directory = try makeTemporaryDirectory()
        let caps = CapabilitySet()
        defer { caps.close() }

        try caps.allowPath(directory.path, access: .read)
        try caps.setNetworkMode(.allowAll)

        let query = try QueryContext(capabilities: caps)
        defer { query.close() }

        let errorLock = NSLock()
        var failures: [String] = []

        DispatchQueue.concurrentPerform(iterations: 100) { index in
            do {
                if index.isMultiple(of: 2) {
                    let result = try query.queryPath(directory.appendingPathComponent("file.txt").path, access: .read)
                    if result.status != .allowed {
                        errorLock.lock()
                        failures.append("unexpected path query status: \(result.status)")
                        errorLock.unlock()
                    }
                } else {
                    let result = try query.queryNetwork()
                    if result.status != .allowed {
                        errorLock.lock()
                        failures.append("unexpected network query status: \(result.status)")
                        errorLock.unlock()
                    }
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
