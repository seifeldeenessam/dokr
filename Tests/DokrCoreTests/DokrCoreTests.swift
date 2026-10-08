import XCTest
@testable import DokrCore

final class AppFolderTests: XCTestCase {
    func testBundleNamesAreSanitizedAndUnique() {
        let a = AppFolder(name: "Dev")
        let b = AppFolder(name: "dev")
        let c = AppFolder(name: " ../Work:Stuff ")
        let d = AppFolder(name: "   ")
        let names = AppFolder.bundleNames(for: [a, b, c, d])

        XCTAssertEqual(names[a.id], "Dev")
        XCTAssertEqual(names[b.id], "dev 2")
        XCTAssertEqual(names[c.id], "-Work-Stuff")
        XCTAssertEqual(names[d.id], "Folder")
    }

    func testBundleIdentifierIsStable() {
        let id = UUID(uuidString: "12345678-ABCD-4000-8000-000000000001")!
        XCTAssertEqual(AppFolder(id: id, name: "x").bundleIdentifier, "com.seifeldeenessam.dokr.folder.12345678abcd40008000000000000001")
    }

    func testCodableRoundTrip() throws {
        let folder = AppFolder(name: "Dev", apps: [AppEntry(name: "Xcode", path: "/Applications/Xcode.app", bundleIdentifier: "com.apple.dt.Xcode")])
        let decoded = try JSONDecoder().decode(AppFolder.self, from: JSONEncoder().encode(folder))
        XCTAssertEqual(decoded, folder)
    }
}

final class DokrLinkTests: XCTestCase {
    private let id = UUID(uuidString: "12345678-ABCD-4000-8000-000000000001")!

    func testRoundTrip() {
        for link in [
            DokrLink.showFolder(id),
            .removeApp("com.apple.dt.Xcode", from: id),
            .removeApp("/Applications/A&B=C+D?.app", from: id),
        ] {
            XCTAssertEqual(DokrLink(url: link.url), link)
        }
        XCTAssertEqual(DokrLink.showFolder(id).url.absoluteString, "dokr://folder/12345678-ABCD-4000-8000-000000000001")
    }

    func testRejectsOtherURLs() {
        for string in [
            "https://folder/12345678-ABCD-4000-8000-000000000001",
            "dokr://other/12345678-ABCD-4000-8000-000000000001",
            "dokr://folder/nope",
            "dokr://folder/12345678-ABCD-4000-8000-000000000001/remove",
            "dokr://folder/12345678-ABCD-4000-8000-000000000001/rename?app=x",
        ] {
            XCTAssertNil(DokrLink(url: URL(string: string)!), string)
        }
    }
}

final class DockAppsCodecTests: XCTestCase {
    private let managed = "/Users/me/Library/Application Support/Dokr/Folders"

    private func appTile(_ url: String, bundleID: String?, guid: Int) -> [String: Any] {
        var data: [String: Any] = [
            "file-label": "x",
            "file-type": 41,
            "file-data": ["_CFURLString": url, "_CFURLStringType": 15] as [String: Any],
        ]
        data["bundle-identifier"] = bundleID
        return ["GUID": guid, "tile-type": "file-tile", "tile-data": data]
    }

    private let spacer: [String: Any] = ["tile-type": "spacer-tile", "tile-data": [:] as [String: Any]]

    func testPathDecoding() {
        let tile = appTile("file:///Users/me/Library/Application%20Support/Dokr/Folders/Dev.app/", bundleID: nil, guid: 1)
        XCTAssertEqual(DockAppsCodec.path(of: tile), "\(managed)/Dev.app")
        XCTAssertNil(DockAppsCodec.path(of: spacer))
    }

    func testSyncKeepsUpdatesDropsAndAppends() throws {
        let tiles = [
            appTile("file:///Applications/Safari.app/", bundleID: "com.apple.Safari", guid: 1),
            appTile("file:///Users/me/Library/Application%20Support/Dokr/Folders/Dev.app/", bundleID: "old", guid: 2),
            spacer,
            appTile("file:///Users/me/Library/Application%20Support/Dokr/Folders/Gone.app/", bundleID: "gone", guid: 3),
            appTile("file:///Applications/Notes.app/", bundleID: "com.apple.Notes", guid: 4),
        ]
        let items = [
            DockAppsCodec.Item(path: "\(managed)/Media.app", label: "Media", bundleIdentifier: "media"),
            DockAppsCodec.Item(path: "\(managed)/Dev.app", label: "Dev", bundleIdentifier: "dev"),
        ]

        let result = DockAppsCodec.sync(tiles, items: items, managedDirectory: managed)

        XCTAssertEqual(result.count, 5)
        XCTAssertEqual(result[0]["GUID"] as? Int, 1)
        XCTAssertEqual(result[1]["GUID"] as? Int, 2)
        XCTAssertEqual(DockAppsCodec.bundleIdentifier(of: result[1]), "dev")
        XCTAssertEqual((result[1]["tile-data"] as? [String: Any])?["file-label"] as? String, "Dev")
        XCTAssertEqual(result[2]["tile-type"] as? String, "spacer-tile")
        XCTAssertEqual(result[3]["GUID"] as? Int, 4)
        XCTAssertEqual(DockAppsCodec.path(of: result[4]), "\(managed)/Media.app")
        XCTAssertEqual(DockAppsCodec.bundleIdentifier(of: result[4]), "media")
        XCTAssertNil(result[4]["GUID"])
    }

    func testSyncHidesGroupedApps() {
        let tiles = [
            appTile("file:///Applications/Safari.app/", bundleID: "com.apple.Safari", guid: 1),
            appTile("file:///Applications/Notes.app/", bundleID: nil, guid: 2),
            appTile("file:///Applications/Mail.app/", bundleID: "com.apple.mail", guid: 3),
        ]
        let hidden = [
            AppEntry(name: "Safari", path: "/Somewhere/Else/Safari.app", bundleIdentifier: "com.apple.Safari"),
            AppEntry(name: "Notes", path: "/Applications/Notes.app"),
        ]

        let result = DockAppsCodec.sync(tiles, items: [], managedDirectory: managed, hiding: hidden)

        XCTAssertEqual(result.map { $0["GUID"] as? Int }, [3])
    }

    func testNewTileShape() throws {
        let tile = DockAppsCodec.tile(for: .init(path: "\(managed)/Dev.app", label: "Dev", bundleIdentifier: "dev"))
        let data = try XCTUnwrap(tile["tile-data"] as? [String: Any])
        let fileData = try XCTUnwrap(data["file-data"] as? [String: Any])
        XCTAssertEqual(tile["tile-type"] as? String, "file-tile")
        XCTAssertEqual(data["file-type"] as? Int, 41)
        XCTAssertEqual(fileData["_CFURLString"] as? String, "file:///Users/me/Library/Application%20Support/Dokr/Folders/Dev.app/")
    }
}

final class ICNSTests: XCTestCase {
    func testEncodeLayout() {
        let png = Data([0x89, 0x50, 0x4E, 0x47])
        let data = ICNS.encode([("ic07", png), ("ic08", png)])

        XCTAssertEqual(data.count, 8 + 2 * (8 + 4))
        XCTAssertEqual(Array(data.prefix(8)), Array("icns".utf8) + [0, 0, 0, 32])
        XCTAssertEqual(Array(data[8..<16]), Array("ic07".utf8) + [0, 0, 0, 12])
        XCTAssertEqual(Array(data[16..<20]), Array(png))
    }
}
