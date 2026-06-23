import Foundation
import NTSFirestore

// Throwaway probe: prove the Firestore Listen stream delivers live tracks.
//   NTS_TOKEN=<firebase-id-token> swift run FSProbe <mixtape-alias>
// Prints the newest-first list on every push, then exits after ~25s.

let alias = CommandLine.arguments.dropFirst().first ?? "memory-lane"
guard let token = ProcessInfo.processInfo.environment["NTS_TOKEN"], !token.isEmpty else {
    FileHandle.standardError.write(Data("NTS_TOKEN env var is required\n".utf8))
    exit(2)
}

let df = DateFormatter()
df.dateFormat = "HH:mm:ss"

let listener = FirestoreListener(
    streamID: alias,
    tokenProvider: { token },
    onUpdate: { tracks in
        print("── update: \(tracks.count) tracks ──")
        for t in tracks.prefix(5) {
            let who = t.artists.joined(separator: ", ")
            print("  \(df.string(from: t.startTime))  \(t.title.isEmpty ? "(identifying…)" : t.title)  — \(who)")
        }
    }
)

print("listening to live_tracks for stream_id=\(alias) …")
listener.start()
try await Task.sleep(nanoseconds: 25 * 1_000_000_000)
listener.stop()
print("done.")
