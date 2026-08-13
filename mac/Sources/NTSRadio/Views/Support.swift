import SwiftUI
import AppKit
import AVFoundation

// MARK: - Button style

/// `.plain`, but the button's whole frame takes the click.
///
/// Every icon button in this app is a glyph with a `.frame` around it and its
/// chip drawn behind with `.background`. A background is not part of what
/// SwiftUI hit-tests, and neither is the empty space a `.frame` adds, so a
/// `.plain` button like that only answers on the ink of the glyph itself — a
/// 13pt target inside a 32pt chip that looks like a button all the way to its
/// corners. Clicks landing in the gap did nothing at all, which reads as a dead
/// button rather than a missed one.
///
/// Setting `contentShape` here rather than at each call site is the point: the
/// style cannot be applied without also making the frame clickable, so a new
/// icon button cannot be added with the same gap. Use this instead of `.plain`
/// for anything whose tappable area is meant to be its chip.
struct HitButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .contentShape(Rectangle())
            .opacity(configuration.isPressed ? 0.65 : 1)
    }
}

extension ButtonStyle where Self == HitButtonStyle {
    static var hit: HitButtonStyle { HitButtonStyle() }
}

// MARK: - Label that is a link when it has somewhere to go

/// A label that becomes a link when `url` is non-nil: it switches to
/// `linkFont`/`linkColor` (NTS shows clickable labels bold white), shows an
/// underline + pointer cursor on hover, and opens the page in the browser when
/// clicked. Plain text otherwise — the schedule names programmes it has no
/// episode alias for, and a dead underline would promise a page that isn't there.
///
/// **A `Button`, not an `onTapGesture`.** The channel card is itself one big tap
/// target that tunes the channel, and a tap gesture inside it leaves which one
/// wins up to gesture resolution; a button consumes its own click, so opening the
/// episode page cannot also change what you are listening to.
struct LinkLabel: View {
    let text: String
    let url: URL?
    let font: Font
    var linkFont: Font? = nil
    let color: Color
    var linkColor: Color? = nil
    var tracking: CGFloat = 0
    var lineLimit: Int = 1
    @State private var hovering = false

    var body: some View {
        let isLink = url != nil
        Button {
            if let url { NSWorkspace.shared.open(url) }
        } label: {
            Text(text)
                .font(isLink ? (linkFont ?? font) : font)
                .tracking(tracking)
                .underline(isLink && hovering)
                .foregroundStyle(isLink ? (linkColor ?? color) : color)
                .lineLimit(lineLimit)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.hit)
        .disabled(!isLink)
        .onHover { inside in
            hovering = inside
            guard isLink else { return }
            if inside { NSCursor.pointingHand.set() } else { NSCursor.arrow.set() }
        }
        .help(url?.absoluteString ?? "")
    }
}

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
