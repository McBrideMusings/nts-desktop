import SwiftUI
import CoreText

/// Design tokens lifted verbatim from the Claude Design prototype
/// (tmp/claude/design/manifest.md). One place to keep the app in sync.
enum Theme {
    // Surfaces
    static let popover     = Color(hex: 0x0b0b0c)
    static let stage       = Color(hex: 0x0e0e10)
    static let stageInner  = Color(hex: 0x0c0c0d)
    static let nowBar      = Color.black
    static let chipBlack   = Color(hex: 0x0b0b0c)

    /// The title-bar band's height, and therefore the window's title-bar
    /// accessory's. 32pt keeps the traffic lights vertically centred in it. It
    /// lives here because three places need the same number and none of them
    /// owns it: the window controller sizes the accessory, `PopoverView` paints
    /// the band across the full window width, and `TitleBarControls` fills it.
    static let titleBarHeight: CGFloat = 32

    // Ink
    static let ink         = Color(hex: 0xf5f4f1)
    static let hubInk      = Color(hex: 0xf0efe9)
    static let inkMuted    = Color(hex: 0x8c8c88)

    // Accents
    static let ch1         = Color(hex: 0xff2b2b)   // London
    static let ch1Text     = Color.white
    static let ch2         = Color(hex: 0xe9e6dd)   // Los Angeles
    static let ch2Text     = Color(hex: 0x0b0b0c)
    static let liveDot     = Color(hex: 0xff2b2b)

    // There is no light-sheet palette here any more. Settings and the account
    // were drawn as macOS-looking cards inside the radio window, in their own
    // set of Apple greys with a painted red traffic light; both are panes of a
    // real window now and wear the system's colours, so the seven that dressed
    // them (`sheet`, `sheetInk`, `sheetInk2`, `sheetInk3`, `blue`, `red`,
    // `trafficRed`) are gone. A palette for a kind of window this app no longer
    // has is an invitation to draw another one.
    static let green       = Color(hex: 0x34c759)

    static func hairline(_ a: Double = 0.08) -> Color { .white.opacity(a) }

    /// The dial face's edge. Opaque on purpose: a translucent white hairline
    /// takes its colour from whatever cover art sits under it, so the ring
    /// changed shade as the artwork moved behind it.
    static let dialEdge = Color(hex: 0x2e2e31)

    // App backdrop gradient (behind the popover)
    static var appBackdrop: some View {
        ZStack {
            LinearGradient(colors: [Color(hex: 0x14151c), Color(hex: 0x0b0c10), Color(hex: 0x08080a)],
                           startPoint: .top, endPoint: .bottom)
            RadialGradient(colors: [Color(hex: 0x232742).opacity(0.9), .clear],
                           center: UnitPoint(x: 0.26, y: 0.06), startRadius: 0, endRadius: 520)
            RadialGradient(colors: [Color(hex: 0x2a1d33).opacity(0.9), .clear],
                           center: UnitPoint(x: 0.86, y: 0.88), startRadius: 0, endRadius: 520)
        }
    }

    // Fonts. Archivo (display) + Archivo Mono (labels) are bundled if present,
    // otherwise fall back to the system rounded/mono faces.
    static func display(_ size: CGFloat, _ weight: Font.Weight = .heavy) -> Font {
        .custom("Archivo", fixedSize: size).weight(weight)
    }
    // "Archivo Mono" isn't a real Google font; the prototype's mono labels fall
    // back to a monospace face, so we use the system monospaced one directly.
    static func mono(_ size: CGFloat, _ weight: Font.Weight = .semibold) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }
    static func ui(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight)
    }

    /// Register bundled fonts (Archivo). Call once at launch.
    ///
    /// Deliberately avoids `Bundle.module`. SwiftPM's generated accessor looks
    /// for the resource bundle beside `Bundle.main.bundleURL` — the .app root,
    /// not `Contents/Resources` — and when that misses it falls back to an
    /// absolute path inside the `.build` directory of the machine that compiled
    /// it, then traps with `fatalError` if that is gone too. An installed app
    /// therefore died at launch the moment `admin clean` ran. Two plain path
    /// lookups have no such fallback: the .app's own `Contents/Resources` first,
    /// then the flat SwiftPM bundle that sits next to `admin dev`'s bare binary.
    static func registerFonts() {
        let candidates = [
            Bundle.main.url(forResource: "Archivo", withExtension: "ttf"),
            Bundle.main.bundleURL
                .appendingPathComponent("NTSRadio_NTSRadio.bundle")
                .appendingPathComponent("Archivo.ttf"),
        ]
        guard let url = candidates
            .compactMap({ $0 })
            .first(where: { FileManager.default.fileExists(atPath: $0.path) })
        else { return }
        CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
    }
}

extension Color {
    init(hex: UInt32, alpha: Double = 1) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xff) / 255,
                  green: Double((hex >> 8) & 0xff) / 255,
                  blue: Double(hex & 0xff) / 255,
                  opacity: alpha)
    }

    /// HSL matching the prototype's `hsl(h s% l%)` helper.
    init(h: Double, s: Double, l: Double, opacity: Double = 1) {
        let c = (1 - abs(2 * l/100 - 1)) * (s/100)
        let hp = h / 60
        let x = c * (1 - abs(hp.truncatingRemainder(dividingBy: 2) - 1))
        var (r, g, b): (Double, Double, Double) = (0, 0, 0)
        switch hp {
        case 0..<1: (r, g, b) = (c, x, 0)
        case 1..<2: (r, g, b) = (x, c, 0)
        case 2..<3: (r, g, b) = (0, c, x)
        case 3..<4: (r, g, b) = (0, x, c)
        case 4..<5: (r, g, b) = (x, 0, c)
        default:    (r, g, b) = (c, 0, x)
        }
        let m = l/100 - c/2
        self.init(.sRGB, red: r + m, green: g + m, blue: b + m, opacity: opacity)
    }
}
