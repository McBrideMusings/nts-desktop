import SwiftUI
import AppKit
import AVFoundation

// MARK: - Track row model

struct Track: Identifiable, Hashable {
    let id = UUID()
    let time: String
    let title: String
    let artist: String
    let hue: Double
    /// Seconds into the recording, for a past episode's tracklist only — nil for
    /// a live push, which has no seek position to highlight against. What picks
    /// out "now playing" in a fixed, known-in-advance list instead of always
    /// being the first row.
    var offsetSeconds: Double? = nil

    /// What the track is, rather than which instance it is. Every Firestore push
    /// rebuilds the whole list, so `id` — and `==` along with it — is fresh each
    /// time; telling "same track, pushed again" from "a new track started" has to
    /// go on the contents.
    var key: String { "\(time)|\(title)|\(artist)" }
}

// MARK: - Pie sector shape (a dial wedge)

/// A filled sector from `center` spanning [startDeg, endDeg], radius large
/// enough to bleed past the frame. Angles are screen-space degrees (0 = +x,
/// −90 = up), matching the prototype's cos/sin geometry.
struct Sector: Shape {
    var centerX: CGFloat
    var centerY: CGFloat
    var startDeg: Double
    var endDeg: Double
    var radius: CGFloat = 1900

    func path(in rect: CGRect) -> Path {
        var p = Path()
        let c = CGPoint(x: centerX, y: centerY)
        p.move(to: c)
        p.addArc(center: c, radius: radius,
                 startAngle: .degrees(startDeg), endAngle: .degrees(endDeg),
                 clockwise: false)
        p.closeSubpath()
        return p
    }
}

// MARK: - Looping muted video (dial wedge animation)

/// Plays a remote looping, muted mp4 — used to animate a dial wedge while it's
/// hovered or actively playing. Instantiated only for the active wedge(s); the
/// player is torn down on disappear so at most a couple ever exist at once.
struct WedgeAnimation: NSViewRepresentable {
    let url: URL

    func makeNSView(context: Context) -> LoopingPlayerView {
        let v = LoopingPlayerView()
        v.configure(url: url)
        return v
    }

    func updateNSView(_ nsView: LoopingPlayerView, context: Context) {
        nsView.configure(url: url)
    }

    static func dismantleNSView(_ nsView: LoopingPlayerView, coordinator: ()) {
        nsView.teardown()
    }
}

/// Layer-hosting NSView backing `WedgeAnimation`. Uses AVPlayerLooper for a
/// seamless gapless loop.
final class LoopingPlayerView: NSView {
    private let playerLayer = AVPlayerLayer()
    private var queuePlayer: AVQueuePlayer?
    private var looper: AVPlayerLooper?
    private var currentURL: URL?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        let base = CALayer()
        layer = base
        wantsLayer = true
        playerLayer.videoGravity = .resizeAspectFill
        base.addSublayer(playerLayer)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) unused") }

    override func layout() {
        super.layout()
        playerLayer.frame = bounds
    }

    func configure(url: URL) {
        guard url != currentURL else { return }
        teardown()
        currentURL = url
        let q = AVQueuePlayer()
        q.isMuted = true
        looper = AVPlayerLooper(player: q, templateItem: AVPlayerItem(url: url))
        playerLayer.player = q
        queuePlayer = q
        q.play()
    }

    func teardown() {
        queuePlayer?.pause()
        playerLayer.player = nil
        looper = nil
        queuePlayer = nil
        currentURL = nil
    }
}

// MARK: - Per-line highlighted text (NTS "chip" style)

/// Text wrapped in a solid black highlight block. The prototype uses per-line
/// inline highlight (box-decoration-break: clone); SwiftUI can't do per-line
/// backgrounds cheaply, so this is a single padded block — close visual match.
struct ChipText<S: StringProtocol>: View {
    let text: S
    var font: Font
    var fg: Color = .white
    var bg: Color = Theme.chipBlack
    var hPad: CGFloat = 7
    var vPad: CGFloat = 2

    var body: some View {
        Text(text)
            .font(font)
            .foregroundStyle(fg)
            .padding(.horizontal, hPad)
            .padding(.vertical, vPad)
            .background(bg)
    }
}
