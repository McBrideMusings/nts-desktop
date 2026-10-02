import Foundation

/// Which of a track's two lines leads a tracklist row.
enum TrackLead: String, CaseIterable {
    case title, artist

    var label: String { rawValue.capitalized }
}

extension Track {
    /// The row's lead line and, when there is one, the line under it. With no
    /// artist the title stands alone in either order.
    func lines(leading lead: TrackLead) -> (String, String?) {
        if artist.isEmpty { return (title, nil) }
        return lead == .title ? (title, artist) : (artist, title)
    }
}
