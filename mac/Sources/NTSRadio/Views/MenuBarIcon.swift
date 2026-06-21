import SwiftUI
import AppKit

/// The status-bar item: NTS's four equalizer bars, drawn as a *template*
/// NSImage so macOS tints/sizes it like every other menu-bar icon. A custom
/// SwiftUI Shape label renders as a zero-width (invisible) item, so we hand
/// MenuBarExtra a concrete Image.
struct MenuBarIcon: View {
    var playing: Bool

    var body: some View {
        Image(nsImage: MenuBarIcon.barsImage)
    }

    static let barsImage: NSImage = {
        let heights: [CGFloat] = [0.55, 1.0, 0.42, 0.8]
        let barW: CGFloat = 2, gap: CGFloat = 1.6
        let w: CGFloat = CGFloat(heights.count) * barW + CGFloat(heights.count - 1) * gap
        let h: CGFloat = 15

        let img = NSImage(size: NSSize(width: w, height: h))
        img.lockFocus()
        NSColor.black.setFill()
        var x: CGFloat = 0
        for frac in heights {
            let bh = max(2, h * frac)
            NSBezierPath(roundedRect: NSRect(x: x, y: 0, width: barW, height: bh),
                         xRadius: 1, yRadius: 1).fill()
            x += barW + gap
        }
        img.unlockFocus()
        img.isTemplate = true   // adapts to light/dark menu bar
        return img
    }()
}
