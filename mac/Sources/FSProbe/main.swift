import Foundation
import NTSFirestore

// Throwaway probe: prove the Firestore Listen stream delivers live tracks.
//   NTS_TOKEN=<firebase-id-token> swift run FSProbe <mixtape-alias|1|2>
// Pass a mixtape alias, or "1"/"2" for live channel 1/2. Prints the newest-
// first list on every push, then exits after ~25s.

let arg = CommandLine.arguments.dropFirst().first ?? "memory-lane"
// "1"/"2" select a live channel (matched by stream_pathname); anything else is
// a mixtape alias (matched by stream_id).
let (field, value): (String, String) = {
    switch arg {
    case "1": return ("stream_pathname", "/stream")
    case "2": return ("stream_pathname", "/stream2")
    default:  return ("stream_id", arg)
    }
}()
guard let token = ProcessInfo.processInfo.environment["NTS_TOKEN"], !token.isEmpty else {
    FileHandle.standardError.write(Data("NTS_TOKEN env var is required\n".utf8))
    exit(2)
}

let df = DateFormatter()
df.dateFormat = "HH:mm:ss"

let listener = FirestoreListener(
    filterField: field,
    filterValue: value,
    tokenProvider: { token },
    onUpdate: { tracks in
        print("── update: \(tracks.count) tracks ──")
        for t in tracks.prefix(5) {
            let who = t.artists.joined(separator: ", ")
            print("  \(df.string(from: t.startTime))  \(t.title.isEmpty ? "(identifying…)" : t.title)  — \(who)")
        }
    }
)

print("listening to live_tracks for \(field)=\(value) …")
listener.start()
try await Task.sleep(nanoseconds: 25 * 1_000_000_000)
listener.stop()
print("done.")
