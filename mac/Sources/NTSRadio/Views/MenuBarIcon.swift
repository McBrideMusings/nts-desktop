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
}
