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
///
/// Two files in `~/Library/Logs/NTS Radio/` (the path is `logDirectory` in the
/// scripted `state`) hold the same history without `log show`:
///
/// - `app.log` — every category below, written by `AppLogger` at the call, in
///   call order. Tab-separated: time, category, level, message.
/// - `tracks.log` — one line per `live_tracks` document change for both live
///   channels and every mixtape, written by `TracksRecording` while signed in.
///
/// Each rotates to `<name>.1` at 5MB.
enum Log {
    static let subsystem = Bundle.main.bundleIdentifier ?? "live.nts.desktop"

    /// Requests to nts.live: what was asked for and what came back.
    static let api = AppLogger(category: "api")
    /// Sign-in and the Keychain.
    static let auth = AppLogger(category: "auth")
    /// Playback: what was loaded, and what refused to load.
    static let player = AppLogger(category: "player")
    /// The app itself: windows, the login item, anything the shell refuses.
    static let app = AppLogger(category: "app")
    /// The `live_tracks` recorder: when its stream connects, reconnects or fails.
    /// The documents themselves go to `tracks.log`.
    static let tracks = AppLogger(category: "tracks")
}

/// One `Log` category. Each call renders its line once and writes that text
/// both to `app.log` and to the unified log, so the file holds every line the
/// moment it is logged — a launch that quits a second later still has them all.
///
/// Call sites read like `Logger`'s: `\(value, privacy: .public)` prints the
/// value, and a string or object without it prints `<private>` in both places.
/// Numbers and flags print as they are, as `Logger` prints them.
struct AppLogger: Sendable {
    let category: String
    private let logger: Logger

    init(category: String) {
        self.category = category
        logger = Logger(subsystem: Log.subsystem, category: category)
    }

    func debug(_ message: LogMessage) { write(message, level: .debug, name: "debug") }
    func info(_ message: LogMessage) { write(message, level: .info, name: "info") }
    func notice(_ message: LogMessage) { write(message, level: .default, name: "notice") }
    func error(_ message: LogMessage) { write(message, level: .error, name: "error") }

    private func write(_ message: LogMessage, level: OSLogType, name: String) {
        logger.log(level: level, "\(message.text, privacy: .public)")
        let flat = message.text.replacingOccurrences(of: "\t", with: " ")
        LogFiles.app.writeStamped("\(category)\t\(name)\t\(flat)")
    }
}

/// The text of one `AppLogger` line, built from a string literal.
struct LogMessage: ExpressibleByStringInterpolation, Sendable {
    let text: String

    init(stringLiteral value: String) { text = value }
    init(stringInterpolation: Interpolation) { text = stringInterpolation.text }

    enum Privacy { case `public`, `private` }

    struct Interpolation: StringInterpolationProtocol {
        var text = ""

        init(literalCapacity: Int, interpolationCount: Int) {
            text.reserveCapacity(literalCapacity + interpolationCount * 8)
        }

        mutating func appendLiteral(_ literal: String) { text += literal }

        mutating func appendInterpolation<T>(_ value: T, privacy: Privacy = .private) {
            text += privacy == .public ? String(describing: value) : "<private>"
        }

        mutating func appendInterpolation<T: BinaryInteger>(_ value: T, privacy: Privacy = .public) {
            text += privacy == .public ? String(value) : "<private>"
        }

        /// Six decimals, as `Logger` prints a float by default.
        mutating func appendInterpolation<T: BinaryFloatingPoint>(_ value: T, privacy: Privacy = .public) {
            text += privacy == .public ? String(format: "%f", Double(value)) : "<private>"
        }

        mutating func appendInterpolation(_ value: Bool, privacy: Privacy = .public) {
            text += privacy == .public ? String(value) : "<private>"
        }
    }
}

/// The name a request is logged and reported under — not a URL.
enum Endpoint: String {
    case schedule, mixtapes, sitemap, show, episodes, episode, moods, genres, explore, favourites
    case recentlyAdded = "recently-added"
    case onAirDetail = "on-air-detail"
    case scheduleArt = "schedule-art"
    case resolveStream = "resolve-stream"
    case siteToken = "site-token"

    /// What a failure means to someone looking at the window. An outage
    /// banner that named `/api/v2/radio/schedule/1` would be telling the user
    /// about our plumbing rather than about their radio.
    ///
    /// Two different consequences, so two different sentences: a feed that
    /// failed leaves what is already on screen standing but stale, while a play
    /// that failed produced no audio at all. Saying "may be out of date" about a
    /// dead play button would be describing the wrong problem.
    var consequence: String {
        switch self {
        case .schedule:         return "the schedule may be out of date"
        case .mixtapes:         return "the mixtape list may be out of date"
        case .show:             return "this show’s details wouldn’t load"
        case .episodes:         return "this show’s episodes wouldn’t load"
        // The rail fetching the current programme's photograph hits the same
        // endpoint as pressing play on an episode, but the consequence is a
        // missing picture, not silence. Reported separately so the banner stops
        // announcing a playback failure while the radio is playing fine.
        case .onAirDetail:      return "the current show’s artwork wouldn’t load"
        case .episode,
             .resolveStream,
             .siteToken:        return "this episode wouldn’t start"
        case .sitemap, .recentlyAdded, .moods, .genres, .explore,
             .scheduleArt, .favourites:
                                return "something wouldn’t load"
        }
    }
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
        let endpoint: Endpoint
        let since: Date
        var failures: Int

        var message: String { "\(headline) — \(what)." }
    }

    @Published private(set) var outage: Outage?

    private init() {}

    /// Logging is the caller's job (`NTSAPI.fetchData`/`fetch` do it for every
    /// request, reported or not) — this only tracks what the banner shows.
    func failed(_ endpoint: Endpoint, _ error: Error) {
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
            what: endpoint.consequence,
            headline: offline ? "No connection" : "NTS isn’t answering",
            detail: detail,
            endpoint: endpoint,
            since: Date(),
            failures: 1
        )
    }

    func succeeded(_ endpoint: Endpoint) {
        guard outage?.endpoint == endpoint else { return }
        outage = nil
    }
}
