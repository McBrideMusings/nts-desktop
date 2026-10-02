import Foundation
import OSLog

/// A line-oriented log file on disk, capped in size.
///
/// When the file passes `maxBytes` it moves to `<name>.1` (replacing the one
/// already there) and a fresh file starts, so a log never holds more than about
/// twice the cap. Writes go through one serial queue and never block the caller.
final class FileLog: @unchecked Sendable {
    let url: URL
    private let maxBytes: Int
    private let queue: DispatchQueue
    private var handle: FileHandle?
    private var size = 0

    init(name: String, maxBytes: Int = 5_000_000) {
        url = LogFiles.directory.appendingPathComponent(name)
        self.maxBytes = maxBytes
        queue = DispatchQueue(label: "live.nts.desktop.filelog.\(name)")
    }

    /// Append one line. A newline inside `line` would split the record in two, so
    /// it is written as a literal `\n`.
    func write(_ line: String) {
        let clean = line.replacingOccurrences(of: "\n", with: "\\n")
        queue.async { self.append(clean + "\n") }
    }

    /// Return once every line written so far is on disk.
    func flush() { queue.sync {} }

    private func append(_ text: String) {
        guard let data = text.data(using: .utf8) else { return }
        if handle == nil { open() }
        if size + data.count > maxBytes { rotate() }
        guard let handle else { return }
        do {
            try handle.write(contentsOf: data)
            size += data.count
        } catch {
            self.handle = nil
        }
    }

    private func open() {
        let fm = FileManager.default
        try? fm.createDirectory(at: LogFiles.directory, withIntermediateDirectories: true)
        if !fm.fileExists(atPath: url.path) { fm.createFile(atPath: url.path, contents: nil) }
        handle = try? FileHandle(forWritingTo: url)
        size = Int((try? handle?.seekToEnd()) ?? 0)
    }

    private func rotate() {
        try? handle?.close()
        handle = nil
        let older = URL(fileURLWithPath: url.path + ".1")
        let fm = FileManager.default
        try? fm.removeItem(at: older)
        try? fm.moveItem(at: url, to: older)
        open()
    }
}

/// Where the app's files in `~/Library/Logs` live, and the two logs in them.
enum LogFiles {
    /// `~/Library/Logs/NTS Radio` — the folder Console.app lists under Log Reports.
    static let directory: URL = FileManager.default
        .urls(for: .libraryDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("Logs/NTS Radio", isDirectory: true)

    /// Every `Log` category, mirrored from the unified log by `AppLogMirror`.
    static let app = FileLog(name: "app.log")
    /// One line per `live_tracks` document change, from `TracksRecording`.
    static let tracks = FileLog(name: "tracks.log")

    /// Timestamps in both logs: local time with its UTC offset, to the millisecond.
    static func stamp(_ date: Date) -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        f.timeZone = .current
        return f.string(from: date)
    }
}

/// Copies what the app logged to the unified log into `app.log`.
///
/// A `Logger` call cannot be intercepted, so rather than wrapping every call
/// site this reads the process's own entries back from `OSLogStore` every two
/// seconds. The text is what `log show` would print, including `<private>`
/// where an interpolation was not marked public.
@MainActor
final class AppLogMirror {
    private var task: Task<Void, Never>?

    func start() {
        guard task == nil else { return }
        task = Task { [weak self] in await self?.run() }
    }

    func stop() {
        task?.cancel()
        task = nil
    }

    private func run() async {
        guard let store = try? OSLogStore(scope: .currentProcessIdentifier) else {
            Log.app.error("could not open the unified log; app.log will stay empty")
            return
        }
        let predicate = NSPredicate(format: "subsystem == %@", Log.subsystem)
        var last: Date?
        while !Task.isCancelled {
            let position = last.map { store.position(date: $0) } ?? store.position(timeIntervalSinceLatestBoot: 0)
            if let entries = try? store.getEntries(at: position, matching: predicate) {
                for case let entry as OSLogEntryLog in entries {
                    if let last, entry.date <= last { continue }
                    last = entry.date
                    LogFiles.app.write("\(LogFiles.stamp(entry.date))\t\(entry.category)\t\(Self.name(entry.level))\t\(entry.composedMessage)")
                }
            }
            try? await Task.sleep(nanoseconds: 2_000_000_000)
        }
    }

    private static func name(_ level: OSLogEntryLog.Level) -> String {
        switch level {
        case .debug: return "debug"
        case .info: return "info"
        case .notice: return "notice"
        case .error: return "error"
        case .fault: return "fault"
        default: return "undefined"
        }
    }
}
