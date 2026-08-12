import AppKit

/// The NTS logo for the status-bar item (and the title-bar mark), loaded as a
/// *template* NSImage so macOS tints and sizes it like every other menu-bar icon
/// (black on a light bar, white on a dark one). Rendered from Resources/NTSLogo.svg.
enum MenuBarIcon {
    static let logoImage: NSImage = {
        let img = Bundle.module.url(forResource: "NTSLogoTemplate", withExtension: "png")
            .flatMap { NSImage(contentsOf: $0) } ?? NSImage(size: NSSize(width: 16, height: 16))
        img.size = NSSize(width: 16, height: 16)   // menu-bar icons read best ~16pt
        img.isTemplate = true
        return img
    }()

    /// The same mark at 1024px, for the places that draw it large — the dial's
    /// idle hub reaches ~240px on a Retina display, and `logoImage` is a 54px
    /// bitmap pinned to 16pt, so blowing that one up is what made the wordmark
    /// mushy. Rendered from Resources/NTSLogo.svg by `cairosvg`.
    static let logoLarge: NSImage = {
        let img = Bundle.module.url(forResource: "NTSLogoLarge", withExtension: "png")
            .flatMap { NSImage(contentsOf: $0) } ?? logoImage
        img.isTemplate = true
        return img
    }()

    // MARK: Status-item frames

    /// Layout of the status-item image: the wordmark, a gap, then three bars.
    /// Every frame is this same size — idle included — so starting or stopping
    /// playback never changes the item's width and never shoves the menu-bar
    /// icons beside it sideways.
    private enum Bars {
        static let logo: CGFloat = 16
        static let gap: CGFloat = 3
        static let width: CGFloat = 3
        static let spacing: CGFloat = 2
        static let count = 3
        static let rest: CGFloat = 2
        /// One cycle of bar heights, 2pt to 14pt. Each bar reads this table at
        /// its own offset so the three never move in unison.
        static let cycle: [CGFloat] = [2, 6, 10, 14, 10, 6]
        static let phase = 2
        static let size = NSSize(
            width: logo + gap + CGFloat(count) * width + CGFloat(count - 1) * spacing,
            height: logo
        )
    }

    /// The bars at rest — shown whenever audio isn't actually playing.
    static let idleFrame: NSImage = frame(bars: Array(repeating: Bars.rest, count: Bars.count))

    /// One full animation cycle, stepped through on a timer while audio plays.
    static let playingFrames: [NSImage] = (0 ..< Bars.cycle.count).map { step in
        frame(bars: (0 ..< Bars.count).map { bar in
            Bars.cycle[(step + bar * Bars.phase) % Bars.cycle.count]
        })
    }

    /// Compose one frame: the wordmark on the left, bars at the given heights on
    /// the right. Marked as a template, so macOS keeps tinting it with the menu
    /// bar's colour and only the silhouette matters — which is why the fill
    /// colour used here is irrelevant.
    private static func frame(bars: [CGFloat]) -> NSImage {
        let img = NSImage(size: Bars.size, flipped: false) { _ in
            logoImage.draw(in: NSRect(x: 0, y: 0, width: Bars.logo, height: Bars.logo))
            NSColor.black.setFill()
            for (i, height) in bars.enumerated() {
                let x = Bars.logo + Bars.gap + CGFloat(i) * (Bars.width + Bars.spacing)
                NSBezierPath(
                    roundedRect: NSRect(x: x, y: 0, width: Bars.width, height: height),
                    xRadius: Bars.width / 2,
                    yRadius: Bars.width / 2
                ).fill()
            }
            return true
        }
        img.isTemplate = true
        return img
    }
}
