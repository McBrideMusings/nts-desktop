/// The single equality filter that selects one source's tracks in NTS's
/// Firestore `live_tracks` collection. NTS keys mixtapes and live channels on
/// different fields, so this is the one place that mapping lives — both the app
/// and the `FSProbe` tool build their `FirestoreListener` filter from here.
public struct LiveTracksFilter: Equatable, Sendable {
    public let field: String
    public let value: String

    /// An infinite mixtape, matched by its alias.
    public static func mixtape(_ alias: String) -> LiveTracksFilter {
        LiveTracksFilter(field: "stream_id", value: alias)
    }

    /// A live channel, matched by its stream pathname. Returns nil for any
    /// number other than 1 or 2 — NTS has exactly two live channels, so an
    /// unknown number is a caller bug, not a third stream to guess at.
    public static func channel(_ number: Int) -> LiveTracksFilter? {
        switch number {
        case 1: return LiveTracksFilter(field: "stream_pathname", value: "/stream")
        case 2: return LiveTracksFilter(field: "stream_pathname", value: "/stream2")
        default: return nil
        }
    }
}
