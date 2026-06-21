import SwiftUI
import AppKit

// MARK: - Track row model

struct Track: Identifiable, Hashable {
    let id = UUID()
    let time: String
    let title: String
    let artist: String
    let hue: Double
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

// MARK: - Local cached image

/// Loads a cached NSImage from disk; shows a neutral fill while missing.
struct LocalImage: View {
    let url: URL?
    var body: some View {
        if let url, let img = NSImage(contentsOf: url) {
            Image(nsImage: img).resizable()
        } else {
            Rectangle().fill(Color(hex: 0x1a1a1d))
        }
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
