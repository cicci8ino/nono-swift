import XCTest
import NonoSwift

final class NonoSwiftTests: XCTestCase {
    func testVersionIsNonEmpty() {
        XCTAssertFalse(NonoSwift.version.isEmpty)
    }

    func testSupportInfoHasPlatform() {
        let info = NonoSwift.supportInfo()
        XCTAssertFalse(info.platform.isEmpty)
        XCTAssertEqual(info.isSupported, NonoSwift.isSupported)
    }
}
