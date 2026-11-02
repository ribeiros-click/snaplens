import XCTest
@testable import SnapLens

/// Comparação de versões usada pelo aviso de atualização: "1.10" é mais nova que "1.9".
@MainActor
final class UpdateCheckerTests: XCTestCase {
    func testComparesNumericallyNotAsText() {
        XCTAssertTrue(UpdateChecker.isNewer("1.10", than: "1.9"))
        XCTAssertFalse(UpdateChecker.isNewer("1.9", than: "1.10"))
    }

    func testEqualAndMissingComponents() {
        XCTAssertFalse(UpdateChecker.isNewer("1.10", than: "1.10"))
        XCTAssertFalse(UpdateChecker.isNewer("1.10", than: "1.10.0"))
        XCTAssertTrue(UpdateChecker.isNewer("1.10.1", than: "1.10"))
        XCTAssertTrue(UpdateChecker.isNewer("2.0", than: "1.99"))
    }

    func testIgnoresSuffixes() {
        XCTAssertTrue(UpdateChecker.isNewer("1.11-beta", than: "1.10"))
        XCTAssertFalse(UpdateChecker.isNewer("garbage", than: "1.0"))
    }
}

/// Validades da caixa de compartilhar.
final class ShareChoiceTests: XCTestCase {
    func testResolve() {
        XCTAssertEqual(ShareChoice.once.resolve(customDays: 7).once, true)
        XCTAssertEqual(ShareChoice.once.resolve(customDays: 7).seconds, 30 * 86400)
        XCTAssertEqual(ShareChoice.d1.resolve(customDays: 7).seconds, 86400)
        XCTAssertEqual(ShareChoice.d5.resolve(customDays: 7).seconds, 5 * 86400)
        XCTAssertEqual(ShareChoice.never.resolve(customDays: 7).seconds, 0)
    }

    func testCustomDaysAreClamped() {
        XCTAssertEqual(ShareChoice.custom.resolve(customDays: 3).seconds, 3 * 86400)
        XCTAssertEqual(ShareChoice.custom.resolve(customDays: 0).seconds, 86400)
        XCTAssertEqual(ShareChoice.custom.resolve(customDays: 9999).seconds, 365 * 86400)
    }
}

/// Link do Google Lens: a URL da imagem vai codificada no parâmetro `url`.
final class LensURLTests: XCTestCase {
    func testBuildsUploadByURL() throws {
        let url = try XCTUnwrap(ShareClient.lensURL(imageURL: "https://lens.ribeiros.click/i/abc123XYZ0?x=1&y=2"))
        XCTAssertEqual(url.host, "lens.google.com")
        XCTAssertEqual(url.path, "/uploadbyurl")
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        XCTAssertEqual(items.first { $0.name == "url" }?.value, "https://lens.ribeiros.click/i/abc123XYZ0?x=1&y=2")
        XCTAssertNotNil(items.first { $0.name == "hl" }?.value)
    }
}

/// Pasta escolhida no Drive é guardada como JSON nos ajustes.
final class DriveFolderTests: XCTestCase {
    func testRoundTrip() throws {
        let f = DriveFolder(id: "1AbC", name: "Prints/SnapLens")
        let back = try JSONDecoder().decode(DriveFolder.self, from: JSONEncoder().encode(f))
        XCTAssertEqual(back, f)
    }
}
