import Foundation
import Darwin
import XCTest
import NonoSwift

func canonicalURL(_ url: URL) -> URL {
    guard let resolved = realpath(url.path, nil) else {
        return URL(fileURLWithPath: (url.path as NSString).resolvingSymlinksInPath)
    }
    defer { free(resolved) }
    return URL(fileURLWithPath: String(cString: resolved))
}

func makeTemporaryDirectory(name: String = UUID().uuidString) throws -> URL {
    let url = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("nono-swift-tests", isDirectory: true)
        .appendingPathComponent(name, isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return canonicalURL(url)
}

func makeTemporaryFile(name: String = UUID().uuidString) throws -> URL {
    let directory = try makeTemporaryDirectory()
    let file = directory.appendingPathComponent(name)
    try "test".write(to: file, atomically: true, encoding: .utf8)
    return canonicalURL(file)
}

func assertThrowsNonoError(
    code expectedCode: NonoError.Code,
    _ body: () throws -> Void,
    file: StaticString = #filePath,
    line: UInt = #line
) {
    do {
        try body()
        XCTFail("expected NonoError.\(expectedCode)", file: file, line: line)
    } catch let error as NonoError {
        XCTAssertEqual(error.code, expectedCode, file: file, line: line)
    } catch {
        XCTFail("expected NonoError.\(expectedCode), got \(error)", file: file, line: line)
    }
}
