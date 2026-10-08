import Foundation

/// `dokr://` URLs the folder helpers send to Dokr.
public enum DokrLink: Equatable, Sendable {
    /// `dokr://folder/<uuid>`: select the folder.
    case showFolder(UUID)
    /// `dokr://folder/<uuid>/remove?app=<AppEntry.id>`: remove the app and update the Dock.
    case removeApp(String, from: UUID)

    public static let scheme = "dokr"

    public var url: URL {
        var components = URLComponents()
        components.scheme = Self.scheme
        components.host = "folder"
        switch self {
        case .showFolder(let id):
            components.path = "/\(id.uuidString)"
        case .removeApp(let appID, let id):
            components.path = "/\(id.uuidString)/remove"
            // `queryItems` leaves `&`, `=` and `+` as-is, which would garble paths containing them.
            var allowed = CharacterSet.urlQueryAllowed
            allowed.remove(charactersIn: "&=+?")
            components.percentEncodedQuery = "app=" + appID.addingPercentEncoding(withAllowedCharacters: allowed)!
        }
        return components.url!
    }

    public init?(url: URL) {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              components.scheme?.lowercased() == Self.scheme,
              components.host?.lowercased() == "folder"
        else { return nil }
        let parts = components.path.split(separator: "/").map(String.init)
        guard let first = parts.first, let id = UUID(uuidString: first) else { return nil }
        switch parts.dropFirst().first {
        case nil:
            self = .showFolder(id)
        case "remove":
            guard let appID = components.queryItems?.first(where: { $0.name == "app" })?.value, !appID.isEmpty else { return nil }
            self = .removeApp(appID, from: id)
        default:
            return nil
        }
    }
}
