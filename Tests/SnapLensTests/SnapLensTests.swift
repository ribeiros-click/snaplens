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

/// Regras da sincronização entre dispositivos.
final class SyncPlanTests: XCTestCase {
    private let now = Date()
    private var cutoff: Date { now.addingTimeInterval(-7 * 86400) }

    private func item(_ kind: ItemKind, daysAgo: Double, text: String? = nil, file: String? = "x.png") -> Item {
        var i = Item(kind: kind, text: text, file: kind.isText ? nil : file)
        i.date = now.addingTimeInterval(-daysAgo * 86400)
        return i
    }

    func testUploadsOnlyRecentLocalUnsentItemsOfEnabledKinds() {
        var synced = item(.screenshot, daysAgo: 1); synced.syncId = "abc"
        var fromOther = item(.screenshot, daysAgo: 1); fromOther.device = "PC"
        let recent = item(.screenshot, daysAgo: 1)
        let old = item(.screenshot, daysAgo: 10)
        let text = item(.ocr, daysAgo: 2, text: "olá")
        let emptyText = item(.clipboardText, daysAgo: 2, text: "")
        let video = item(.video, daysAgo: 1, file: "v.mp4")
        let up = SyncPlan.toUpload([synced, fromOther, recent, old, text, emptyText, video], cutoff: cutoff, options: .init())
        XCTAssertEqual(Set(up.map(\.id)), [recent.id, text.id]) // vídeos desligados por padrão
        XCTAssertEqual(up.first?.id, text.id) // mais antigo primeiro

        let withVideos = SyncPlan.toUpload([video], cutoff: cutoff, options: .init(images: true, videos: true, texts: true))
        XCTAssertEqual(withVideos.map(\.id), [video.id])
    }

    func testPropsRoundTripIntoIncomingItem() throws {
        var original = item(.screenshot, daysAgo: 1)
        original.source = "Claude"
        let props = SyncPlan.props(for: original, deviceID: "MAC-1", deviceName: "MacBook")
        let incoming = try XCTUnwrap(SyncPlan.incoming(props: props, fileID: "drive-file", localIDs: [], deviceID: "PC-2", cutoff: cutoff))
        XCTAssertEqual(incoming.id, original.id)
        XCTAssertEqual(incoming.kind, .screenshot)
        XCTAssertEqual(incoming.date.timeIntervalSince1970, original.date.timeIntervalSince1970, accuracy: 1)
        XCTAssertEqual(incoming.device, "MacBook")
        XCTAssertEqual(incoming.syncId, "drive-file")
        XCTAssertEqual(incoming.source, "Claude")
        XCTAssertEqual(incoming.file, original.id.uuidString + ".png")
    }

    func testIgnoresOwnKnownOldOrInvalidFiles() {
        let i = item(.screenshot, daysAgo: 1)
        let props = SyncPlan.props(for: i, deviceID: "MAC-1", deviceName: "MacBook")
        XCTAssertNil(SyncPlan.incoming(props: props, fileID: "f", localIDs: [], deviceID: "MAC-1", cutoff: cutoff)) // deste aparelho
        XCTAssertNil(SyncPlan.incoming(props: props, fileID: "f", localIDs: [i.id], deviceID: "PC", cutoff: cutoff)) // já existe
        let old = SyncPlan.props(for: item(.screenshot, daysAgo: 30), deviceID: "MAC-1", deviceName: "MacBook")
        XCTAssertNil(SyncPlan.incoming(props: old, fileID: "f", localIDs: [], deviceID: "PC", cutoff: cutoff)) // fora da janela
        XCTAssertNil(SyncPlan.incoming(props: ["id": "x"], fileID: "f", localIDs: [], deviceID: "PC", cutoff: cutoff))
    }

    /// Itens criados no Windows chegam com o id em maiúsculas e o tipo pelo nome do enum.
    func testAcceptsWindowsProps() throws {
        let props = ["id": "0F8FAD5B-D9CB-469F-A165-70867728950E", "kind": "clipboardText",
                     "date": ISO8601DateFormatter().string(from: now), "device": "PC-2", "deviceName": "DESKTOP-01"]
        let i = try XCTUnwrap(SyncPlan.incoming(props: props, fileID: "f", localIDs: [], deviceID: "MAC-1", cutoff: cutoff))
        XCTAssertEqual(i.kind, .clipboardText)
        XCTAssertNil(i.file)
    }
}
