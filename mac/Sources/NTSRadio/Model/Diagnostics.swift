import Foundation
import Combine
import OSLog

/// Where the app writes what happened.
///
/// `print()` goes nowhere in an installed `.app` — there is no terminal attached,
/// so a failure written that way is unrecoverable after the fact. `Logger` lands
/// in the unified log, which means a failure that happened yesterday can still be
/// read back:
///
/// ```
/// log show --predicate 'subsystem == "live.nts.desktop"' --last 1h --info
/// log stream --predicate 'subsystem == "live.nts.desktop"' --level info
/// ```
enum Log {
    private static let subsystem = Bundle.main.bundleIdentifier ?? "live.nts.desktop"

    /// Requests to nts.live: what was asked for and what came back.
    static let api = Logger(subsystem: subsystem, category: "api")
    /// Sign-in and the Keychain.
    static let auth = Logger(subsystem: subsystem, category: "auth")
    /// Playback: what was loaded, and what refused to load.
    static let player = Logger(subsystem: subsystem, category: "player")
    /// The app itself: windows, the login item, anything the shell refuses.
    static let app = Logger(subsystem: subsystem, category: "app")
}

/// Whether nts.live is answering, in terms the interface can show.
///
/// Every request funnels through `NTSAPI.fetch`, which reports here on the way
/// out. That is deliberate: before this, each call site swallowed its own error
/// with `try?`, so a catalog that had quietly stopped updating looked exactly
/// like one with nothing new in it. A single sink means no call site can drop a
/// failure on the floor, and the banner has one thing to read.
@MainActor
final class ServiceStatus: ObservableObject {
    static let shared = ServiceStatus()

    struct Outage: Equatable {
        /// What the user lost, as a clause: "the schedule may be out of date",
        /// "this episode wouldn’t start".
        let what: String
        /// Whose fault it looks like — NTS, or this machine being offline.
        let headline: String
        /// The technical detail, for the log and the scripted state.
        let detail: String
        /// Which endpoint reported it, so its next success can clear it.
        let endpoint: String
        let since: Date
        var failures: Int

        var message: String { "\(headline) — \(what)." }
    }

    @Published private(set) var outage: Outage?

    private init() {}

    /// Logging is the caller's job (`NTSAPI.fetchData`/`fetch` do it for every
    /// request, reported or not) — this only tracks what the banner shows.
    func failed(_ endpoint: String, _ error: Error) {
        let offline = (error as? URLError).map {
            [.notConnectedToInternet, .networkConnectionLost, .cannotFindHost,
             .cannotConnectToHost, .timedOut].contains($0.code)
        } ?? false

        let detail = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription

        if var existing = outage, existing.endpoint == endpoint {
            existing.failures += 1
            outage = existing
            return
        }
        outage = Outage(
            what: Self.plainName(for: endpoint),
            headline: offline ? "No connection" : "NTS isn’t answering",
            detail: detail,
            endpoint: endpoint,
            since: Date(),
            failures: 1
        )
    }

    func succeeded(_ endpoint: String) {
        guard outage?.endpoint == endpoint else { return }
        outage = nil
    }

    /// What each endpoint means to someone looking at the window. An outage
    /// banner that named `/api/v2/radio/schedule/1` would be telling the user
    /// about our plumbing rather than about their radio.
    ///
    /// Two different consequences, so two different sentences: a feed that
    /// failed leaves what is already on screen standing but stale, while a play
    /// that failed produced no audio at all. Saying "may be out of date" about a
    /// dead play button would be describing the wrong problem.
    private static func plainName(for endpoint: String) -> String {
        switch endpoint {
        case "schedule":        return "the schedule may be out of date"
        case "mixtapes":        return "the mixtape list may be out of date"
        case "shows":           return "the show index may be incomplete"
        case "show":            return "this show’s details wouldn’t load"
        case "episodes":        return "this show’s episodes wouldn’t load"
        // The rail fetching the current programme's photograph hits the same
        // endpoint as pressing play on an episode, but the consequence is a
        // missing picture, not silence. Reported separately so the banner stops
        // announcing a playback failure while the radio is playing fine.
        case "on-air-detail":   return "the current show’s artwork wouldn’t load"
        case "episode",
             "resolve-stream",
             "site-token":      return "this episode wouldn’t start"
        default:                return "something wouldn’t load"
        }
    }
}
