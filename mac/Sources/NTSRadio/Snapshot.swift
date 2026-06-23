import SwiftUI
import AppKit

/// Headless render of each popover state to PNG, for visual verification /
/// regression against the prototype screenshots. Triggered by
/// `NTS_SNAPSHOT=<dir> swift run`. Not part of the shipping app.
@MainActor
enum Snapshot {
    static func run(dir: String) {
        let base = URL(fileURLWithPath: dir)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)

        func shot(_ name: String, _ configure: (AppModel) -> Void) {
            let model = AppModel()
            configure(model)
            let view = PopoverView()
                .environmentObject(model)
                .environmentObject(model.auth)
                .frame(width: 800, height: 640)
            let renderer = ImageRenderer(content: view)
            renderer.scale = 2
            guard let img = renderer.nsImage,
                  let tiff = img.tiffRepresentation,
                  let rep = NSBitmapImageRep(data: tiff),
                  let png = rep.representation(using: .png, properties: [:])
            else { print("snapshot failed: \(name)"); return }
            try? png.write(to: base.appendingPathComponent(name))
            print("wrote \(name)")
        }

        shot("01-default-mix-dial.png") { _ in }
        shot("02-channel1-live.png") { $0.select(.channel(1)) }
        shot("03-tracklist.png") { $0.select(.channel(1)); $0.showTracks = true }
        shot("04-settings.png") { $0.settingsOpen = true }

        exit(0)
    }
}
