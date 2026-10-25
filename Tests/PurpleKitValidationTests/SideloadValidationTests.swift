import XCTest
@testable import PurpleKitValidation

final class SideloadValidationTests: XCTestCase {
    private let modernUDID = "00008110-001A2B3C4D5E6F70"
    private let oldUDID = String(repeating: "a1", count: 20)
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    func testAcceptsRealUDIDFormats() {
        XCTAssertTrue(SideloadValidation.isValidUDID(modernUDID))
        XCTAssertTrue(SideloadValidation.isValidUDID(oldUDID))
        XCTAssertTrue(SideloadValidation.isValidUDID(" \n" + modernUDID + "\n"))
    }

    func testRejectsVendorUUIDAndMalformedIdentifiers() {
        for value in ["", "550e8400-e29b-41d4-a716-446655440000",
                      "00008110-001A2B3C4D5E6F7Z",
                      "00008110-001A2B3C4D5E6F7",
                      String(repeating: "a", count: 39),
                      "00008110001A2B3C4D5E6F70"] {
            XCTAssertFalse(SideloadValidation.isValidUDID(value), value)
        }
    }

    private func matches(
        bundle: String = "com.example.app", team: String = "TEAM123",
        devices: [String]? = nil, certificates: [String] = ["ABC123"],
        expiry: TimeInterval = 3600
    ) -> Bool {
        SideloadValidation.profileMatches(
            bundleID: "com.example.app", teamID: "TEAM123",
            udid: modernUDID, certificateSerial: "ABC123",
            profileBundleID: bundle, profileTeamID: team,
            profileDevices: devices ?? [modernUDID], profileCertificateSerials: certificates,
            expiration: now.addingTimeInterval(expiry), now: now
        )
    }

    func testAcceptsMatchingUnexpiredProfile() {
        XCTAssertTrue(matches())
        XCTAssertTrue(matches(devices: [modernUDID.lowercased()], certificates: ["abc123"]))
    }

    func testRejectsProfileForAnotherDevice() {
        XCTAssertFalse(matches(devices: [oldUDID]))
        XCTAssertFalse(matches(devices: []))
    }

    func testRejectsExpiredProfileIncludingExactBoundary() {
        XCTAssertFalse(matches(expiry: -1))
        XCTAssertFalse(matches(expiry: 0))
    }

    func testRejectsWrongOrMissingCertificate() {
        XCTAssertFalse(matches(certificates: ["OTHER"]))
        XCTAssertFalse(matches(certificates: []))
    }

    func testRejectsAnotherTeam() {
        XCTAssertFalse(matches(team: "ANOTHER"))
    }

    func testRejectsMainProfileForExtension() {
        XCTAssertFalse(matches(bundle: "com.example.app.extension"))
        XCTAssertFalse(matches(bundle: "*"))
    }
}
