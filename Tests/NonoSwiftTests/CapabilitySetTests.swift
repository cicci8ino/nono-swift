import XCTest
import Foundation
import NonoSwift

final class CapabilitySetTests: XCTestCase {
    func testCloseIsIdempotent() {
        let caps = CapabilitySet()
        caps.close()
        caps.close()
    }

    func testMutatingClosedCapabilitySetThrows() throws {
        let directory = try makeTemporaryDirectory()
        let file = try makeTemporaryFile()
        let caps = CapabilitySet()
        caps.close()

        let mutators: [() throws -> Void] = [
            { try caps.allowPath(directory.path, access: .read) },
            { try caps.allowFile(file.path, access: .read) },
            { try caps.setNetworkMode(.allowAll) },
            { try caps.setNetworkBlocked(true) },
            { try caps.setProxyPort(8080) },
            { try caps.allowCommand("git") },
            { try caps.blockCommand("curl") },
            { try caps.addPlatformRule("(version 1)") },
            { try caps.deduplicate() }
        ]

        for mutator in mutators {
            assertThrowsNonoError(code: .invalidArgument) {
                try mutator()
            }
        }
    }

    func testAllowPathAllAccessModes() throws {
        let directory = try makeTemporaryDirectory()

        for access in [AccessMode.read, .write, .readWrite] {
            let caps = CapabilitySet()
            defer { caps.close() }
            try caps.allowPath(directory.path, access: access)
            XCTAssertEqual(caps.fileSystemCapabilities.first?.access, access)
        }
    }

    func testAllowPathMissingPathThrowsPathNotFound() {
        let caps = CapabilitySet()
        defer { caps.close() }

        assertThrowsNonoError(code: .pathNotFound) {
            try caps.allowPath("/this/path/does/not/exist/nono-swift", access: .read)
        }
    }

    func testAllowFile() throws {
        let file = try makeTemporaryFile()
        let caps = CapabilitySet()
        defer { caps.close() }

        try caps.allowFile(file.path, access: .read)

        let capability = try XCTUnwrap(caps.fileSystemCapabilities.first)
        XCTAssertEqual(capability.originalPath, file.path)
        XCTAssertEqual(capability.access, .read)
        XCTAssertTrue(capability.isFile)
        XCTAssertEqual(capability.source, .user)
    }

    func testAllowFileDirectoryThrowsExpectedFile() throws {
        let directory = try makeTemporaryDirectory()
        let caps = CapabilitySet()
        defer { caps.close() }

        assertThrowsNonoError(code: .expectedFile) {
            try caps.allowFile(directory.path, access: .read)
        }
    }

    func testStringsContainingNULThrowInvalidArgument() {
        let caps = CapabilitySet()
        defer { caps.close() }

        let checks: [() throws -> Void] = [
            { try caps.allowPath("/tmp\0truncated", access: .read) },
            { try caps.allowFile("/tmp\0truncated", access: .read) },
            { try caps.allowCommand("git\0 --bypass") },
            { try caps.blockCommand("curl\0 --bypass") },
            { try caps.addPlatformRule("rule\0inject") },
            { _ = try caps.pathCovered("/tmp\0truncated") }
        ]

        for check in checks {
            assertThrowsNonoError(code: .invalidArgument) {
                try check()
            }
        }
    }

    func testCommandRulesAndPlatformRules() throws {
        let caps = CapabilitySet()
        defer { caps.close() }

        try caps.allowCommand("git")
        try caps.blockCommand("curl")
        try caps.addPlatformRule("(version 1)")
    }

    func testDeduplicateKeepsHighestAccess() throws {
        let directory = try makeTemporaryDirectory()
        let caps = CapabilitySet()
        defer { caps.close() }

        try caps.allowPath(directory.path, access: .read)
        try caps.allowPath(directory.path, access: .readWrite)

        try caps.deduplicate()

        let capabilities = caps.fileSystemCapabilities
        XCTAssertEqual(capabilities.count, 1)
        XCTAssertEqual(capabilities.first?.access, .readWrite)
    }

    func testNetworkModeAndProxyPort() throws {
        let caps = CapabilitySet()
        defer { caps.close() }

        try caps.setNetworkMode(.blocked)
        XCTAssertEqual(caps.networkMode, .blocked)
        XCTAssertTrue(caps.isNetworkBlocked)
        XCTAssertEqual(caps.proxyPort, 0)

        try caps.setNetworkMode(.allowAll)
        XCTAssertEqual(caps.networkMode, .allowAll)
        XCTAssertFalse(caps.isNetworkBlocked)

        try caps.setNetworkMode(.proxyOnly)
        try caps.setProxyPort(8080)
        XCTAssertEqual(caps.networkMode, .proxyOnly)
        XCTAssertEqual(caps.proxyPort, 8080)
    }

    func testSetNetworkBlockedInteraction() throws {
        let caps = CapabilitySet()
        defer { caps.close() }

        try caps.setNetworkBlocked(true)
        XCTAssertEqual(caps.networkMode, .blocked)
        XCTAssertTrue(caps.isNetworkBlocked)

        try caps.setNetworkBlocked(false)
        XCTAssertEqual(caps.networkMode, .allowAll)
        XCTAssertFalse(caps.isNetworkBlocked)
    }

    func testPathCovered() throws {
        let directory = try makeTemporaryDirectory()
        let caps = CapabilitySet()
        defer { caps.close() }

        try caps.allowPath(directory.path, access: .read)

        XCTAssertTrue(try caps.pathCovered(directory.appendingPathComponent("child.txt").path))
        XCTAssertFalse(try caps.pathCovered("/definitely-not-covered-by-nono-swift"))
    }

    func testSummaryAndFileSystemCapabilities() throws {
        let directory = try makeTemporaryDirectory()
        let caps = CapabilitySet()
        defer { caps.close() }

        try caps.allowPath(directory.path, access: .readWrite)

        XCTAssertFalse(caps.summary.isEmpty)
        let capability = try XCTUnwrap(caps.fileSystemCapabilities.first)
        XCTAssertEqual(capability.originalPath, directory.path)
        XCTAssertEqual(capability.resolvedPath, directory.path)
        XCTAssertEqual(capability.access, .readWrite)
        XCTAssertFalse(capability.isFile)
        XCTAssertEqual(capability.source, .user)
        XCTAssertEqual(capability.groupName, "")
    }

    func testConcurrentCapabilitySetAccess() throws {
        let caps = CapabilitySet()
        defer { caps.close() }

        let errorLock = NSLock()
        var errors: [Error] = []

        DispatchQueue.concurrentPerform(iterations: 100) { index in
            do {
                if index.isMultiple(of: 3) {
                    try caps.setNetworkMode(.blocked)
                } else if index.isMultiple(of: 3, offsetBy: 1) {
                    try caps.setNetworkMode(.allowAll)
                } else {
                    _ = caps.networkMode
                    _ = caps.isNetworkBlocked
                    _ = caps.proxyPort
                    _ = caps.summary
                    _ = caps.fileSystemCapabilities
                }
            } catch {
                errorLock.lock()
                errors.append(error)
                errorLock.unlock()
            }
        }

        XCTAssertTrue(errors.isEmpty, "unexpected concurrent access errors: \(errors)")
    }
}

private extension Int {
    func isMultiple(of divisor: Int, offsetBy offset: Int) -> Bool {
        (self - offset).isMultiple(of: divisor)
    }
}
