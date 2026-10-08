import Foundation

/// Minimal writer for PNG-based `.icns` files.
public enum ICNS {
    /// OSType → pixel size of the PNG it holds.
    public static let entries: [(type: String, pixels: Int)] = [
        ("icp4", 16), ("icp5", 32),
        ("ic11", 32), ("ic12", 64),
        ("ic07", 128), ("ic13", 256),
        ("ic08", 256), ("ic14", 512),
        ("ic09", 512), ("ic10", 1024),
    ]

    public static func encode(_ images: [(type: String, png: Data)]) -> Data {
        var body = Data()
        for image in images {
            body.append(fourCC(image.type))
            body.append(bigEndian(8 + image.png.count))
            body.append(image.png)
        }
        var file = fourCC("icns")
        file.append(bigEndian(8 + body.count))
        file.append(body)
        return file
    }

    private static func fourCC(_ code: String) -> Data {
        precondition(code.utf8.count == 4, "OSType must be 4 ASCII characters")
        return Data(code.utf8)
    }

    private static func bigEndian(_ value: Int) -> Data {
        withUnsafeBytes(of: UInt32(value).bigEndian) { Data($0) }
    }
}
