import Foundation

/// The account's follows and saved episodes, read and written where nts.live
/// actually keeps them.
///
/// There is no favourites REST endpoint — `/api/v2/users/me`,
/// `/api/v2/favourites` and `/api/v2/users/me/favourites` all return the
/// website's HTML shell, meaning those routes never existed. nts.live's own
/// bundle shows the real mechanism, two top-level Firestore collections:
///
/// - `favourites` — `{ show_alias, episode_alias, device_id, created_at }`
/// - `user_devices` — doc id is an installation id, holding
///   `{ device_id, firebase_user_uid, device_description, created_at }`
///
/// Note what that means: **a favourite belongs to a device, not to a user.**
/// nts.live reads yours by looking up every device registered to your Firebase
/// uid and then querying `favourites` for `device_id in [those]`. So this app
/// registers itself as one more of your devices, writes its own favourites
/// under that id, and reads across all of them — which is how a show starred on
/// the website or the phone shows up here.
///
/// This talks Firestore's REST API rather than the gRPC client in
/// `NTSFirestore`: that one is a Listen (streaming read) client for tracklists,
/// and CRUD over REST is a fraction of the machinery of adding writes to it.
@MainActor
enum NTSFavourites {
    /// One row of the `favourites` collection.
    struct Favourite: Hashable {
        /// The full document path, which is what a delete needs.
        let name: String
        let showAlias: String
        let episodeAlias: String

        var isEpisode: Bool { !episodeAlias.isEmpty }
    }

    enum FavouritesError: LocalizedError {
        case notAuthenticated
        case badToken
        case refused(Int)

        var errorDescription: String? {
            switch self {
            case .notAuthenticated: return "Sign in to sync what you’ve saved with NTS."
            case .badToken:         return "Could not read the account id from the sign-in token."
            case .refused(let code): return "NTS’s database refused the request (HTTP \(code))."
            }
        }
    }

    private static let project = "nts-ios-app"
    private static var root: String {
        "https://firestore.googleapis.com/v1/projects/\(project)/databases/(default)/documents"
    }

    /// This Mac's device id, generated once and kept. It is the id the account's
    /// `user_devices` entry is filed under, so it has to survive relaunch or
    /// every launch would look like a new device and strand the last one's stars.
    static var deviceID: String {
        if let existing = UserDefaults.standard.string(forKey: "ntsDeviceID") { return existing }
        let fresh = UUID().uuidString
        UserDefaults.standard.set(fresh, forKey: "ntsDeviceID")
        return fresh
    }

    // MARK: Reading

    /// Every favourite on every device registered to this account.
    static func fetch(token: String) async throws -> [Favourite] {
        let devices = try await deviceIDs(token: token)
        guard !devices.isEmpty else { return [] }

        let filter: [String: Any] = [
            "fieldFilter": [
                "field": ["fieldPath": "device_id"],
                "op": "IN",
                // Firestore caps an IN filter at 30 values. Someone with more
                // than thirty registered devices gets their newest thirty, which
                // is a better answer than an error.
                "value": ["arrayValue": ["values": devices.prefix(30).map { ["stringValue": $0] }]],
            ],
        ]
        let rows = try await runQuery(collection: "favourites", where: filter, token: token)
        return rows.compactMap { doc in
            guard let name = doc["name"] as? String,
                  let fields = doc["fields"] as? [String: Any] else { return nil }
            return Favourite(name: name,
                             showAlias: string(fields["show_alias"]),
                             episodeAlias: string(fields["episode_alias"]))
        }
    }

    /// The device ids registered to this account, newest first.
    private static func deviceIDs(token: String) async throws -> [String] {
        let uid = try accountID(from: token)
        let filter: [String: Any] = [
            "fieldFilter": [
                "field": ["fieldPath": "firebase_user_uid"],
                "op": "EQUAL",
                "value": ["stringValue": uid],
            ],
        ]
        let rows = try await runQuery(collection: "user_devices", where: filter, token: token)
        let ids = rows.compactMap { doc -> String? in
            guard let fields = doc["fields"] as? [String: Any] else { return nil }
            let id = string(fields["device_id"])
            return id.isEmpty ? nil : id
        }
        // This Mac may not be registered yet — include it so a star written here
        // is readable here even before the registration lands.
        return ids.contains(deviceID) ? ids : ids + [deviceID]
    }

    // MARK: Writing

    /// Register this Mac against the account, so favourites written here are
    /// found by the same device lookup nts.live does.
    static func registerDevice(token: String) async throws {
        let uid = try accountID(from: token)
        let fields: [String: Any] = [
            "device_id": ["stringValue": deviceID],
            "firebase_user_uid": ["stringValue": uid],
            "device_description": ["stringValue": "NTS Radio for Mac"],
            "created_at": ["timestampValue": timestamp()],
        ]
        // PATCH with the id in the path is Firestore's create-or-update; the
        // device is the same device every launch, so this must not make a new row.
        _ = try await send("PATCH", path: "\(root)/user_devices/\(deviceID)",
                           body: ["fields": fields], token: token)
    }

    /// Star something on the account.
    static func add(showAlias: String, episodeAlias: String = "", token: String) async throws {
        let fields: [String: Any] = [
            "show_alias": ["stringValue": showAlias],
            "episode_alias": ["stringValue": episodeAlias],
            "device_id": ["stringValue": deviceID],
            "created_at": ["timestampValue": timestamp()],
        ]
        _ = try await send("POST", path: "\(root)/favourites",
                           body: ["fields": fields], token: token)
    }

    /// Unstar it. `name` is the document path a fetch handed back.
    static func remove(name: String, token: String) async throws {
        _ = try await send("DELETE", path: "https://firestore.googleapis.com/v1/\(name)",
                           body: nil, token: token)
    }

    // MARK: Plumbing

    private static func runQuery(collection: String,
                                 where filter: [String: Any],
                                 token: String) async throws -> [[String: Any]] {
        // No `orderBy`. nts.live's own client sorts by `created_at`, but a
        // filter on one field ordered by another needs a composite index, and
        // this is NTS's Firestore project — asking for that ordering answers
        // `FAILED_PRECONDITION: The query requires an index`, with a link to a
        // console nobody here can open. The rows are merged into a set anyway,
        // so their order on the wire never mattered.
        let body: [String: Any] = [
            "structuredQuery": [
                "from": [["collectionId": collection]],
                "where": filter,
                "limit": 500,
            ],
        ]
        let data = try await send("POST", path: "\(root):runQuery", body: body, token: token)
        let rows = (try? JSONSerialization.jsonObject(with: data)) as? [[String: Any]] ?? []
        // A runQuery answers with one element per match, each wrapping the
        // document — plus, when nothing matches, a single element with no
        // `document` key at all.
        return rows.compactMap { $0["document"] as? [String: Any] }
    }

    @discardableResult
    private static func send(_ method: String, path: String,
                             body: [String: Any]?, token: String) async throws -> Data {
        guard let url = URL(string: path) else { throw FavouritesError.refused(0) }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        }
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            guard (200..<300).contains(code) else {
                // Firestore explains itself in the body — a missing index, a
                // rejected field. Without this the log says only "400", which is
                // the one thing that doesn't help.
                let detail = String(data: data, encoding: .utf8) ?? ""
                Log.auth.error("favourites \(method, privacy: .public) \(code) — \(detail, privacy: .public)")
                throw FavouritesError.refused(code)
            }
            ServiceStatus.shared.succeeded("favourites")
            return data
        } catch {
            Log.auth.error("favourites \(method, privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
            ServiceStatus.shared.failed("favourites", error)
            throw error
        }
    }

    /// The account id out of the Firebase ID token. It is a JWT, and the middle
    /// segment carries `user_id` — read, not verified: Firestore verifies it for
    /// real on every request, and a wrong id here just returns nothing.
    private static func accountID(from token: String) throws -> String {
        let parts = token.split(separator: ".")
        guard parts.count == 3 else { throw FavouritesError.badToken }
        var payload = String(parts[1])
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        payload += String(repeating: "=", count: (4 - payload.count % 4) % 4)
        guard let data = Data(base64Encoded: payload),
              let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let uid = (json["user_id"] ?? json["sub"]) as? String
        else { throw FavouritesError.badToken }
        return uid
    }

    private static func string(_ value: Any?) -> String {
        ((value as? [String: Any])?["stringValue"] as? String) ?? ""
    }

    private static let iso: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()
    private static func timestamp() -> String { iso.string(from: Date()) }
}
