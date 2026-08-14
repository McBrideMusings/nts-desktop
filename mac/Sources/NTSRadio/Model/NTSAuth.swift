import Foundation
import Combine
import Security

/// Firebase email/password auth for NTS (project `nts-ios-app`), implemented
/// against Google's Identity Toolkit + Secure Token REST endpoints — no Firebase
/// SDK. The refresh token is persisted in the Keychain so the session survives
/// relaunches; the short-lived ID token is cached in memory and refreshed on
/// demand. Live mixtape tracklists are gated by this token (paid NTS Supporters).
@MainActor
final class NTSAuth: ObservableObject {
    /// Public Firebase web API key for `nts-ios-app` (ships in NTS's own web
    /// bundle — a client identifier, not a secret).
    private static let apiKey = "AIzaSyA4Qp5AvHC8Rev72-10-_DY614w_bxUCJU"

    @Published private(set) var isAuthenticated = false
    @Published private(set) var email: String?
    @Published private(set) var isWorking = false
    @Published var errorMessage: String?

    private var idToken: String?
    private var idTokenExpiry: Date = .distantPast
    private var refreshToken: String?
    /// In-flight refresh, shared so concurrent callers exchange the rotating
    /// refresh token exactly once (a second exchange would revoke the first).
    private var refreshTask: Task<String, Error>?

    init() {
        if let stored = Keychain.read() {
            refreshToken = stored.refreshToken
            email = stored.email
            isAuthenticated = true
        }
    }

    /// A signed-in-looking instance that has never touched the Keychain and holds
    /// no token, for `admin snapshot`. The account pane reads its state off an
    /// `NTSAuth`, so rendering it against the live one made the shot depend on
    /// whoever was signed in on that Mac — the only shot in the set that did, and
    /// the only one that put a real address in a PNG. Every other shot seeds its
    /// own data; this is that seed. It cannot be used to reach the network:
    /// `validToken()` throws `notAuthenticated` with no refresh token.
    static func sample(email: String) -> NTSAuth {
        let auth = NTSAuth()
        auth.refreshToken = nil
        auth.idToken = nil
        auth.email = email
        auth.isAuthenticated = true
        return auth
    }

    // MARK: - Public

    func signIn(email: String, password: String) async {
        let email = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !email.isEmpty, !password.isEmpty else {
            errorMessage = "Enter your email and password."
            return
        }
        isWorking = true
        errorMessage = nil
        defer { isWorking = false }
        do {
            let r = try await Self.signInWithPassword(email: email, password: password)
            apply(idToken: r.idToken, refreshToken: r.refreshToken, expiresIn: r.expiresIn, email: r.email)
        } catch let e as AuthError {
            errorMessage = e.userFacing
        } catch {
            errorMessage = "Couldn’t sign in. Check your connection and try again."
        }
    }

    func signOut() {
        idToken = nil
        idTokenExpiry = .distantPast
        refreshToken = nil
        email = nil
        isAuthenticated = false
        errorMessage = nil
        Keychain.delete()
    }

    /// A valid (non-expired) Firebase ID token, refreshing via the stored refresh
    /// token when needed. Throws `AuthError.notAuthenticated` if signed out.
    func validToken() async throws -> String {
        if let idToken, idTokenExpiry.timeIntervalSinceNow > 60 { return idToken }
        guard refreshToken != nil else { throw AuthError.notAuthenticated }
        // Single-flight: the first caller starts the refresh; everyone else awaits
        // the same task. Cancelling one awaiter doesn't cancel the shared refresh.
        if let refreshTask { return try await refreshTask.value }
        let task = Task { [weak self] () throws -> String in
            guard let self else { throw AuthError.notAuthenticated }
            return try await self.performRefresh()
        }
        refreshTask = task
        defer { refreshTask = nil }
        return try await task.value
    }

    private func performRefresh() async throws -> String {
        guard let rt = refreshToken else { throw AuthError.notAuthenticated }
        do {
            let r = try await Self.exchangeRefreshToken(rt)
            apply(idToken: r.idToken, refreshToken: r.refreshToken, expiresIn: r.expiresIn, email: email)
            return r.idToken
        } catch let e as AuthError {
            // A definitive rejection (revoked / password changed) kills the
            // session. Transient network errors and cancellation do NOT — those
            // propagate so the caller can retry without signing the user out.
            signOut()
            throw e
        }
    }

    // MARK: - State

    private func apply(idToken: String, refreshToken: String, expiresIn: TimeInterval, email: String?) {
        self.idToken = idToken
        self.idTokenExpiry = Date().addingTimeInterval(expiresIn)
        self.refreshToken = refreshToken
        if let email { self.email = email }
        self.isAuthenticated = true
        Keychain.write(refreshToken: refreshToken, email: self.email)
    }

    // MARK: - REST

    private struct TokenResult { let idToken: String; let refreshToken: String; let expiresIn: TimeInterval; let email: String? }

    private static func signInWithPassword(email: String, password: String) async throws -> TokenResult {
        var req = URLRequest(url: URL(string: "https://identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key=\(apiKey)")!)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: [
            "email": email, "password": password, "returnSecureToken": true,
        ])
        let (data, _) = try await URLSession.shared.data(for: req)
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        if let err = (json["error"] as? [String: Any])?["message"] as? String {
            throw AuthError.api(err)
        }
        guard let idToken = json["idToken"] as? String,
              let refreshToken = json["refreshToken"] as? String,
              let expiresStr = json["expiresIn"] as? String, let expires = TimeInterval(expiresStr) else {
            throw AuthError.api("UNEXPECTED_RESPONSE")
        }
        return TokenResult(idToken: idToken, refreshToken: refreshToken, expiresIn: expires, email: json["email"] as? String ?? email)
    }

    private static func exchangeRefreshToken(_ refreshToken: String) async throws -> TokenResult {
        var req = URLRequest(url: URL(string: "https://securetoken.googleapis.com/v1/token?key=\(apiKey)")!)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        var comps = URLComponents()
        comps.queryItems = [.init(name: "grant_type", value: "refresh_token"), .init(name: "refresh_token", value: refreshToken)]
        req.httpBody = comps.percentEncodedQuery.flatMap { $0.data(using: .utf8) }
        let (data, _) = try await URLSession.shared.data(for: req)
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        if let err = (json["error"] as? [String: Any])?["message"] as? String {
            throw AuthError.api(err)
        }
        guard let idToken = json["id_token"] as? String,
              let newRefresh = json["refresh_token"] as? String,
              let expiresStr = json["expires_in"] as? String, let expires = TimeInterval(expiresStr) else {
            throw AuthError.api("UNEXPECTED_RESPONSE")
        }
        return TokenResult(idToken: idToken, refreshToken: newRefresh, expiresIn: expires, email: nil)
    }
}

enum AuthError: Error {
    case notAuthenticated
    case api(String)

    var userFacing: String {
        switch self {
        case .notAuthenticated:
            return "You’re signed out."
        case .api(let code):
            switch code {
            case let c where c.hasPrefix("INVALID_LOGIN_CREDENTIALS"),
                 let c where c.hasPrefix("INVALID_PASSWORD"),
                 let c where c.hasPrefix("EMAIL_NOT_FOUND"):
                return "Incorrect email or password."
            case let c where c.hasPrefix("USER_DISABLED"):
                return "This account has been disabled."
            case let c where c.hasPrefix("TOO_MANY_ATTEMPTS"):
                return "Too many attempts. Try again later."
            default:
                return "Sign-in failed. Please try again."
            }
        }
    }
}

// MARK: - Keychain

/// Minimal Keychain wrapper for the refresh token + email (one generic-password
/// item). Stored as JSON so both travel together.
private enum Keychain {
    private static let service = "live.nts.radio.firebase"
    private static let account = "refresh-token"

    struct Stored { let refreshToken: String; let email: String? }

    /// A readable form of an `OSStatus` — the same wording Keychain Access shows.
    private static func message(_ status: OSStatus) -> String {
        (SecCopyErrorMessageString(status, nil) as String?) ?? "OSStatus \(status)"
    }

    static func write(refreshToken: String, email: String?) {
        var payload: [String: String] = ["refreshToken": refreshToken]
        if let email { payload["email"] = email }
        guard let data = try? JSONSerialization.data(withJSONObject: payload) else {
            Log.auth.error("could not encode the refresh token — not persisted")
            return
        }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        // Firebase rotates the refresh token on every exchange, so this runs on
        // (almost) every launch, not just the first. Deleting and re-adding needs
        // the right to delete the existing item, which a code-signature change
        // revokes — the delete is refused, the add then collides with the item
        // that survived, and the rotated token never reaches disk. An update
        // needs no such ownership right, so probe for the item first and update
        // in place; add is only for the genuinely-first write.
        var probe = query
        probe[kSecMatchLimit as String] = kSecMatchLimitOne
        let found = SecItemCopyMatching(probe as CFDictionary, nil)
        switch found {
        case errSecSuccess:
            let attributes: [String: Any] = [kSecValueData as String: data]
            let updated = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
            if updated != errSecSuccess {
                // This is the one that matters. The session keeps working now, because
                // the token is still in memory — but nothing reaches disk, so the next
                // launch finds no token and the user is silently signed out.
                Log.auth.error("""
                    could not update the stored refresh token: \(message(updated), privacy: .public) — this \
                    session will work, but sign-in will not survive a relaunch
                    """)
            }
        case errSecItemNotFound:
            var add = query
            add[kSecValueData as String] = data
            add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
            let added = SecItemAdd(add as CFDictionary, nil)
            if added != errSecSuccess {
                Log.auth.error("""
                    could not store the refresh token: \(message(added), privacy: .public) — this \
                    session will work, but sign-in will not survive a relaunch
                    """)
            }
        default:
            Log.auth.error("could not check for the stored token: \(message(found), privacy: .public)")
        }
    }

    static func read() -> Stored? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data,
              let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: String],
              let rt = json["refreshToken"] else { return nil }
        return Stored(refreshToken: rt, email: json["email"])
    }

    static func delete() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        // Same defect as `write` had, one function down: a failure here leaves the
        // token on disk after signing out, so the next launch signs back in.
        let status = SecItemDelete(query as CFDictionary)
        if status != errSecSuccess, status != errSecItemNotFound {
            Log.auth.error("could not clear the stored token: \(message(status), privacy: .public)")
        }
    }
}
