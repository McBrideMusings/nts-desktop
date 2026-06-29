import SwiftUI
import AppKit

/// The status-bar item: the NTS logo, loaded as a *template* NSImage so macOS
/// tints and sizes it to match every other menu-bar icon (black on a light bar,
/// white on a dark one). The artwork (NTSLogoTemplate.png) is the NTS mark with
/// the letters knocked out, rendered from Resources/NTSLogo.svg.
struct MenuBarIcon: View {
    var body: some View {
        Image(nsImage: MenuBarIcon.logoImage)
    }

    static let logoImage: NSImage = {
        let img = Bundle.module.url(forResource: "NTSLogoTemplate", withExtension: "png")
            .flatMap { NSImage(contentsOf: $0) } ?? NSImage(size: NSSize(width: 16, height: 16))
        img.size = NSSize(width: 16, height: 16)   // menu-bar icons read best ~16pt
        img.isTemplate = true
        return img
    }()
}
