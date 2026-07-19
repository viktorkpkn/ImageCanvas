import XCTest
@testable import ImageCanvas

final class AppUpdateTests: XCTestCase {
    func testVersionComparisonUsesSemanticComponentsThenBuild() throws {
        let current = try XCTUnwrap(AppVersion("0.4.1", build: "3"))
        let newerVersion = try XCTUnwrap(AppVersion("v0.5.0", build: "1"))
        let newerBuild = try XCTUnwrap(AppVersion("0.4.1", build: "4"))

        XCTAssertGreaterThan(newerVersion, current)
        XCTAssertGreaterThan(newerBuild, current)
        XCTAssertEqual(AppVersion("1.2", build: "7"), AppVersion("1.2.0", build: "7"))
    }

    func testMalformedVersionsAreRejected() {
        XCTAssertNil(AppVersion("v1.beta"))
        XCTAssertNil(AppVersion("1..2"))
        XCTAssertNil(AppVersion(""))
    }

    func testDigestRequiresExactlyAValidSHA256Value() {
        let digest = String(repeating: "a", count: 64)

        XCTAssertEqual(AppUpdateService.normalizedDigest("sha256:\(digest)"), digest)
        XCTAssertEqual(AppUpdateService.normalizedDigest(digest.uppercased()), digest)
        XCTAssertNil(AppUpdateService.normalizedDigest("sha256:1234"))
        XCTAssertNil(AppUpdateService.normalizedDigest(nil))
    }

    func testBuildNumberComesFromReleaseAssetName() {
        XCTAssertEqual(
            AppUpdateService.buildNumber(in: "ImageCanvas-0.5.0-build4.zip"),
            4
        )
        XCTAssertNil(AppUpdateService.buildNumber(in: "ImageCanvas-0.5.0.zip"))
    }
}
