import Foundation
import NTSFirestore
import NTSChannel

/// Writes every `live_tracks` change for both live channels and every mixtape to
/// `tracks.log`, whichever source is playing — one Firestore stream, one target
/// per source (`FirestoreTracksRecorder`). Runs while signed in, since the
/// collection is supporter-gated.
///
/// The tracklist drawer shows a de-duplicated, minute-resolution view of one
/// source. This keeps the raw feed: every document id, its `start_time` to the
/// millisecond, the `artist_names` array as stored, and Firestore's own create and
/// update times — so a track list that looks wrong can be checked against what
/// NTS actually wrote.
@MainActor
final class TracksRecording {
    private var recorder: FirestoreTracksRecorder?
    /// The labels of what is being recorded, empty while signed out.
    private(set) var sources: [String] = []

    /// Open, change or close the stream so it covers exactly `mixtapes` plus the
    /// two channels while `signedIn`. A call that changes nothing leaves the
    /// connection alone.
    func update(signedIn: Bool, mixtapes: [String], token: @escaping @Sendable () async throws -> String) {
        var wanted: [(label: String, filter: LiveTracksFilter)] = []
        if signedIn {
            wanted += ChannelNumber.allCases.map { ("channel-\($0)", LiveTracksFilter.channel($0)) }
            wanted += Set(mixtapes).sorted().map { ("mixtape:\($0)", LiveTracksFilter.mixtape($0)) }
        }
        let labels = wanted.map(\.label)
        guard labels != sources else { return }
        recorder?.stop()
        recorder = nil
        sources = labels
        guard !wanted.isEmpty else {
            Log.tracks.info("recorder stopped")
            return
        }
        Log.tracks.info("recorder starting with \(wanted.count, privacy: .public) sources")
        let recorder = FirestoreTracksRecorder(
            sources: wanted,
            tokenProvider: token,
            onChange: { LogFiles.tracks.write(Self.line(for: $0)) },
            onLifecycle: { message in
                Log.tracks.info("\(message, privacy: .public)")
                LogFiles.tracks.write("\(LogFiles.stamp(Date()))\tstream\t\(message)")
            }
        )
        self.recorder = recorder
        recorder.start()
    }

    /// `received  source  kind  id  start  title  artists  created  updated  other`,
    /// tab-separated. Title and artists are JSON so a tab, a quote or a comma
    /// inside a name cannot move a column, and so the array's own elements show.
    nonisolated static func line(for c: TrackChange) -> String {
        let none = "-"
        let fields = [
            LogFiles.stamp(c.receivedAt),
            c.source,
            c.kind.rawValue + (c.initial ? "/snapshot" : ""),
            c.documentID,
            "start=" + (c.startTime.map(LogFiles.stamp) ?? none),
            "title=" + (c.title.map(json) ?? none),
            "artists=" + (c.artists.map(json) ?? none),
            "created=" + (c.createTime.map(LogFiles.stamp) ?? none),
            "updated=" + (c.updateTime.map(LogFiles.stamp) ?? none),
            "other=" + (c.otherFields.isEmpty ? none : c.otherFields.joined(separator: ",")),
        ]
        return fields.joined(separator: "\t")
    }

    private nonisolated static func json<T: Encodable>(_ value: T) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.withoutEscapingSlashes]
        guard let data = try? encoder.encode(value), let text = String(data: data, encoding: .utf8) else { return "?" }
        return text
    }
}
