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
/// The field named `device_id` is the trap. nts.live fills it with
///
///     getUserUid() || getInstallationId() || gaClientId
///
/// so for anyone signed in it holds **the Firebase user uid**, not a device at
/// all — which is why favourites follow you between browsers with no device
/// registry involved. The installation id is only the fallback for someone who
/// stars something before signing in, and `user_devices` is how those orphaned
/// ids are later found and read alongside the uid.
///
/// So this writes `device_id = uid`, exactly as the website does, and reads
/// `device_id IN [uid] + any installation ids registered to the account`.
/// Writing a per-Mac id here instead would have produced favourites nothing
/// else could see.
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

    /// This installation's own id, kept only for the `user_devices` row. It is
    /// *not* what favourites are filed under while signed in — see the note
    /// above — so nothing depends on it matching anything the website knows.
    static var installationID: String {
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
        let installations = rows.compactMap { doc -> String? in
            guard let fields = doc["fields"] as? [String: Any] else { return nil }
            let id = string(fields["device_id"])
            return id.isEmpty ? nil : id
        }
        // The uid first: that is where every favourite made while signed in
        // lives, on every browser and every phone. The installation ids only
        // carry stars made before signing in.
        return [uid] + installations.filter { $0 != uid }
    }

    // MARK: Writing

    /// Register this Mac against the account, so favourites written here are
    /// found by the same device lookup nts.live does.
    static func registerDevice(token: String) async throws {
        let uid = try accountID(from: token)
        let fields: [String: Any] = [
            "device_id": ["stringValue": installationID],
            "firebase_user_uid": ["stringValue": uid],
            "device_description": ["stringValue": "NTS Radio for Mac"],
            "created_at": ["timestampValue": timestamp()],
        ]
        // PATCH with the id in the path is Firestore's create-or-update; the
        // installation is the same one every launch, so this must not make a
        // new row.
        _ = try await send("PATCH", path: "\(root)/user_devices/\(installationID)",
                           body: ["fields": fields], token: token)
    }

    /// Star something on the account, answering with the row Firestore created.
    ///
    /// The document name is the whole point of the return value: it is what a
    /// later delete addresses, and without it an unstar has to hope the row was
    /// in the snapshot `Saved.sync()` read at launch — which a star made in this
    /// session never is.
    @discardableResult
    static func add(showAlias: String, episodeAlias: String = "", token: String) async throws -> Favourite {
        let uid = try accountID(from: token)
        let fields: [String: Any] = [
            "show_alias": ["stringValue": showAlias],
            "episode_alias": ["stringValue": episodeAlias],
            // The uid, because that is what the website files its own under and
            // what its reader queries for. A per-Mac id here would be invisible
            // everywhere but here.
            "device_id": ["stringValue": uid],
            "created_at": ["timestampValue": timestamp()],
            // The website hangs a session map off every favourite. Only the uid
            // in it is meaningful to anything that reads these back.
            "session": ["mapValue": ["fields": ["firebase_user_uid": ["stringValue": uid]]]],
        ]
        let data = try await send("POST", path: "\(root)/favourites",
                                  body: ["fields": fields], token: token)
        let created = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        return Favourite(name: created?["name"] as? String ?? "",
                         showAlias: showAlias, episodeAlias: episodeAlias)
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
