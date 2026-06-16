import Foundation
import XCTest

final class ApplySandboxTests: XCTestCase {
    func testApplySandboxMinimalFilesystemNetwork() throws {
        try runFixture(scenario: "minimal-filesystem-network")
    }

    func testApplySandboxProcessesRunWithSystemGrants() throws {
        try runFixture(scenario: "processes-run-with-system-grants")
    }

    private func runFixture(scenario: String) throws {
        let fixtureURL = try fixtureExecutableURL()
        let outputPipe = Pipe()

        let process = Process()
        process.executableURL = fixtureURL
        process.environment = ProcessInfo.processInfo.environment.merging([
            "NONO_APPLY_SCENARIO": scenario
        ]) { _, new in new }
        process.standardOutput = outputPipe
        process.standardError = outputPipe

        try process.run()
        process.waitUntilExit()

        let output = String(decoding: outputPipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        if output.contains("sandbox apply skipped") {
            throw XCTSkip(output)
        }

        XCTAssertEqual(process.terminationStatus, 0, output)
        XCTAssertTrue(output.contains("scenario \(scenario) verified"), output)
    }

    private func fixtureExecutableURL() throws -> URL {
        let buildDirectory = Bundle(for: ApplySandboxTests.self).bundleURL.deletingLastPathComponent()
        let fixtureURL = buildDirectory.appendingPathComponent("NonoSwiftApplySandboxFixture")

        guard FileManager.default.isExecutableFile(atPath: fixtureURL.path) else {
            throw XCTSkip("NonoSwiftApplySandboxFixture was not built at \(fixtureURL.path)")
        }

        return fixtureURL
    }
}
