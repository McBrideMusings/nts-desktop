import AppKit
import SwiftUI

/// What the status item shows in the middle of its plate.
///
/// The wordmark is only legible enough at 16 pt to be recognised, not read, so it
/// does one job: "nothing is playing". The moment audio starts it is replaced by a
/// single character naming the source, which is legible at 16 pt with no waiting.
enum MenuBarBadge: Hashable {
    /// The NTS wordmark. The resting state, and the only state that carries it.
    case mark
    /// One character: "1" or "2" for the live channels, "M" for a mixtape.
    case character(String)
    /// A play triangle, for everything else — an archive episode, a show tuned
    /// from the schedule, anything with no character of its own.
    case play

    init(_ selection: Selection) {
        switch selection {
        case .idle:            self = .mark
        case .channel(let n):  self = .character(String(n.rawValue))
        case .mixtape:         self = .character("M")
        case .episode:         self = .play
        }
    }
}

/// The status-item image: a 16 pt square, always, whatever it is showing. Nothing
/// is ever drawn beside it, so starting or stopping playback never shifts the
/// icons to its left.
///
/// Drawn as a *template* image, so macOS tints it like every other menu-bar icon
/// (black on a light bar, white on a dark one) and only the alpha channel matters
/// — which is why the fill colours below are all `.black` and none of that is a
/// choice. It also means nothing can "light up": the only two moves available are
/// ink appearing and ink disappearing.
///
/// While playing, a waterline crosses the square. Below it the picture is normal —
/// solid plate with the badge knocked out of it. Above it the picture inverts: the
/// plate is gone and the badge is the only ink left. The badge stays legible at
/// every instant; it just changes which side of the ink it is on.
enum MenuBarIcon {
    /// Menu-bar icons read best at 16 pt, and the square is 16 pt in both states.
    static let side: CGFloat = 16
    /// `NTSMark`'s own coordinate space, from the artwork's viewBox. Everything
    /// below is written in these units and scaled once on the way out.
    private static let box: CGFloat = 26

    // MARK: The waterline

    /// Where the waterline sits `t` seconds into playback, in the 26-unit space.
    ///
    /// Two sines of periods that do not divide into each other, so the line never
    /// settles into a countable beat — a single sine reads as a metronome, which is
    /// wrong for a stream that has no tempo the app knows about.
    ///
    /// The two amplitudes sum to 9.7, so the line stays within 3.3…22.7 and the
    /// clamp never fires at these numbers. It is here for the amplitudes rather
    /// than for the current ones: raising either past 11.5 would push the line off
    /// the square, and clipping it flat at the edge is the intended result.
    static func waterline(at t: TimeInterval) -> CGFloat {
        let y = 13
            + 7.5 * sin(t * 2 * .pi / 1.15)
            + 2.2 * sin(t * 2 * .pi / 0.37)
        return CGFloat(min(24.5, max(1.5, y)))
    }

    // MARK: Frames

    /// The image shown before anything is selected: the wordmark, no waterline.
    @MainActor
    static let idleFrame: NSImage = image(badge: .mark, waterline: nil)

    /// One frame. `waterline` is nil for a still image; otherwise it is a position
    /// in the 26-unit space, from `waterline(at:)`.
    ///
    /// Cached on the way out. The animation redraws 25 times a second and the
    /// waterline is quantised to a quarter of a unit — a hair under a third of a
    /// screen point at 16 pt — so the cache tops out at a few hundred small images
    /// and every frame after the first second is a dictionary hit.
    ///
    /// Main-actor because of that cache: it is a plain `Dictionary`, and two
    /// threads writing one would corrupt it rather than merely race to a wrong
    /// picture. Every caller is already on the main actor — the animation timer
    /// and the status item itself — so the annotation records what is true rather
    /// than constraining anything.
    @MainActor
    static func image(badge: MenuBarBadge, waterline: CGFloat?) -> NSImage {
        let quantised = waterline.map { (($0 * 4).rounded() / 4) }
        let key = Key(badge: badge, waterline: quantised)
        if let hit = cache[key] { return hit }
        let made = render(badge: badge, waterline: quantised)
        cache[key] = made
        return made
    }

    private struct Key: Hashable {
        let badge: MenuBarBadge
        let waterline: CGFloat?
    }
    @MainActor
    private static var cache: [Key: NSImage] = [:]

    // MARK: Drawing

    private static func render(badge: MenuBarBadge, waterline: CGFloat?) -> NSImage {
        let img = NSImage(size: NSSize(width: side, height: side), flipped: true) { _ in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return true }
            // Work in the artwork's 26-unit space; scale once, here. The context is
            // flipped, so y runs downward exactly as it does in the SVG the mark
            // and the triangle were both taken from.
            ctx.scaleBy(x: side / box, y: side / box)

            guard let y = waterline else {
                draw(badge: badge, ctx: ctx)     // still: the whole square, normal
                return true
            }

            // Below the line: the ordinary picture.
            ctx.saveGState()
            ctx.clip(to: CGRect(x: 0, y: y, width: box, height: box - y))
            draw(badge: badge, ctx: ctx)
            ctx.restoreGState()

            // Above it: no plate, and the badge is the ink instead of the hole.
            ctx.saveGState()
            ctx.clip(to: CGRect(x: 0, y: 0, width: box, height: y))
            drawBadgeAsInk(badge, ctx: ctx)
            ctx.restoreGState()

            return true
        }
        img.isTemplate = true
        return img
    }

    /// The normal picture: a solid plate with the badge knocked out of it. The
    /// wordmark is knocked out by the even-odd rule the artwork is built around;
    /// the badge characters are punched out with `.destinationOut`, which is the
    /// same result reached without needing a glyph outline.
    private static func draw(badge: MenuBarBadge, ctx: CGContext) {
        switch badge {
        case .mark:
            ctx.addPath(markPath)
            ctx.setFillColor(.black)
            ctx.fillPath(using: .evenOdd)

        case .character, .play:
            ctx.setFillColor(.black)
            ctx.fill(CGRect(x: 0, y: 0, width: box, height: box))
            ctx.saveGState()
            ctx.setBlendMode(.destinationOut)
            drawBadgeAsInk(badge, ctx: ctx)
            ctx.restoreGState()
        }
    }

    /// The badge drawn as ink on nothing — used above the waterline, and used again
    /// through `.destinationOut` to punch the same shape out of the plate below it.
    private static func drawBadgeAsInk(_ badge: MenuBarBadge, ctx: CGContext) {
        switch badge {
        case .mark:
            // Above the line the wordmark is the ink: the letters alone, without
            // the plate they are normally cut out of.
            ctx.addPath(glyphsPath)
            ctx.setFillColor(.black)
            ctx.fillPath(using: .evenOdd)

        case .play:
            ctx.addPath(playPath)
            ctx.setFillColor(.black)
            ctx.fillPath()

        case .character(let s):
            let text = NSAttributedString(string: s, attributes: [
                .font: badgeFont,
                .foregroundColor: NSColor.black
            ])
            let size = text.size()
            text.draw(at: CGPoint(x: (box - size.width) / 2, y: (box - size.height) / 2))
        }
    }

    // MARK: Shapes

    /// The mark exactly as the dial draws it — one path, letters knocked out of the
    /// plate by the even-odd rule. Taken from `NTSMark` rather than copied, so the
    /// status item and the hub can never drift apart.
    private static let markPath: CGPath =
        NTSMark().path(in: CGRect(x: 0, y: 0, width: box, height: box)).cgPath

    /// The same path with the plate removed, leaving the three letterforms. The
    /// plate is `NTSMark`'s final subpath, so dropping the last four line segments
    /// would be fragile; subtracting the rect it covers is not.
    private static let glyphsPath: CGPath = {
        let full = CGMutablePath()
        full.addPath(markPath)
        // The plate is the full 26x26 square. Adding a second copy of it makes the
        // even-odd winding cancel, which leaves only the letterforms behind.
        full.addRect(CGRect(x: 0, y: 0, width: box, height: box))
        return full
    }()

    /// The play triangle, in the same 26-unit space.
    private static let playPath: CGPath = {
        let p = CGMutablePath()
        p.move(to: CGPoint(x: 8.6, y: 6.2))
        p.addLine(to: CGPoint(x: 19.4, y: 13))
        p.addLine(to: CGPoint(x: 8.6, y: 19.8))
        p.closeSubpath()
        return p
    }()

    /// Archivo, the face the rest of the app is set in — registered at launch by
    /// `Theme.registerFonts()`, which runs before the status item is built.
    ///
    /// The bundled file is variable, and its named instances come out of AppKit as
    /// `ArchivoRoman-*` (`ArchivoRoman-Regular`, `ArchivoRoman-Bold`,
    /// `ArchivoRoman-ExtraBold`, …) — with the single exception of
    /// `Archivo-SemiBold`. There is no face called `Archivo-Bold`, so ask for the
    /// name that exists. Falls back to the system face at a matching weight when
    /// the bundled font is missing entirely.
    private static let badgeFont: NSFont = {
        let size: CGFloat = 22           // in the 26-unit space, so ~13.5 pt drawn
        return NSFont(name: "ArchivoRoman-ExtraBold", size: size)
            ?? NSFont(name: "ArchivoRoman-Bold", size: size)
            ?? .systemFont(ofSize: size, weight: .heavy)
    }()
}
