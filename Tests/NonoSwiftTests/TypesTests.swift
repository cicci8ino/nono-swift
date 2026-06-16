import XCTest
import NonoSwift

final class TypesTests: XCTestCase {
    func testAccessModeDescriptions() {
        XCTAssertEqual(AccessMode.read.description, "read")
        XCTAssertEqual(AccessMode.write.description, "write")
        XCTAssertEqual(AccessMode.readWrite.description, "read-write")
        XCTAssertEqual(AccessMode(rawValue: 99).description, "AccessMode(99)")
    }

    func testNetworkModeDescriptions() {
        XCTAssertEqual(NetworkMode.blocked.description, "blocked")
        XCTAssertEqual(NetworkMode.allowAll.description, "allow-all")
        XCTAssertEqual(NetworkMode.proxyOnly.description, "proxy-only")
        XCTAssertEqual(NetworkMode(rawValue: 99).description, "NetworkMode(99)")
    }

    func testCapabilitySourceDescriptions() {
        XCTAssertEqual(CapabilitySource.user.description, "user")
        XCTAssertEqual(CapabilitySource.group.description, "group")
        XCTAssertEqual(CapabilitySource.system.description, "system")
        XCTAssertEqual(CapabilitySource.profile.description, "profile")
        XCTAssertEqual(CapabilitySource(rawValue: 99).description, "CapabilitySource(99)")
    }

    func testQueryStatusDescriptions() {
        XCTAssertEqual(QueryStatus.allowed.description, "allowed")
        XCTAssertEqual(QueryStatus.denied.description, "denied")
        XCTAssertEqual(QueryStatus(rawValue: 99).description, "QueryStatus(99)")
    }

    func testQueryReasonDescriptions() {
        XCTAssertEqual(QueryReason.grantedPath.description, "granted-path")
        XCTAssertEqual(QueryReason.networkAllowed.description, "network-allowed")
        XCTAssertEqual(QueryReason.pathNotGranted.description, "path-not-granted")
        XCTAssertEqual(QueryReason.insufficientAccess.description, "insufficient-access")
        XCTAssertEqual(QueryReason.networkBlocked.description, "network-blocked")
        XCTAssertEqual(QueryReason(rawValue: 99).description, "QueryReason(99)")
    }
}
