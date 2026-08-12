import SwiftUI

/// The NTS wordmark as an actual vector path.
///
/// It used to be drawn from a PNG — a 54px menu-bar bitmap blown up to fill the
/// dial's hub, and then a 512px render of the same artwork. Both were the wrong
/// shape of answer: a raster asset has one resolution and every size that is not
/// that resolution is a resample, so the mark was either mushy (upscaled) or
/// stair-stepped (crushed down in a single step). The artwork is a single
/// path in `mac/Resources/NTSLogo.svg`, so it is a path here too, and the
/// renderer draws it at whatever size and scale factor the display asks for.
///
/// The final subpath is the full 26×26 plate; the three letterforms are knocked
/// out of it, which is why this fills **even-odd** and not the default winding
/// rule. Filling it non-zero paints a solid block.
///
/// Regenerated from the SVG's `d` attribute — the coordinates below are that
/// attribute with its shorthand (`h`, `v`, `s`, relative commands) resolved to
/// absolute points. If NTS ever reissues the mark, replace the SVG and redo the
/// same expansion; nothing here is hand-tuned.
struct NTSMark: Shape {
    /// The artwork's own coordinate space, from the SVG's `viewBox`.
    private static let box: CGFloat = 26

    func path(in rect: CGRect) -> Path {
        // Uniform scale, centred — the mark is square, so this only ever adds
        // margin on one axis when the caller's rect is not.
        let s = min(rect.width, rect.height) / Self.box
        let ox = rect.minX + (rect.width - Self.box * s) / 2
        let oy = rect.minY + (rect.height - Self.box * s) / 2
        func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: ox + x * s, y: oy + y * s)
        }

        var p = Path()
        p.move(to: pt(22.7, 6.9))
        p.addLine(to: pt(22.3, 9))
        p.addLine(to: pt(20.8, 9))
        p.addLine(to: pt(21.3, 7))
        p.addCurve(to: pt(20.7, 5.9), control1: pt(21.4, 6.4), control2: pt(21.4, 5.9))
        p.addCurve(to: pt(19.6, 7), control1: pt(20, 5.9), control2: pt(19.7, 6.4))
        p.addLine(to: pt(19.2, 8.7))
        p.addCurve(to: pt(19.2, 10.2), control1: pt(19.1, 9.2), control2: pt(19.1, 9.7))
        p.addLine(to: pt(20.6, 14.3))
        p.addCurve(to: pt(20.7, 16.3), control1: pt(20.8, 14.9), control2: pt(20.9, 15.6))
        p.addLine(to: pt(20.1, 18.9))
        p.addCurve(to: pt(17.2, 21.3), control1: pt(19.7, 20.4), control2: pt(18.6, 21.3))
        p.addCurve(to: pt(15.3, 18.9), control1: pt(15.6, 21.3), control2: pt(14.9, 20.6))
        p.addLine(to: pt(15.8, 16.7))
        p.addLine(to: pt(17.3, 16.7))
        p.addLine(to: pt(16.8, 18.8))
        p.addCurve(to: pt(17.5, 20), control1: pt(16.6, 19.6), control2: pt(16.8, 20))
        p.addCurve(to: pt(18.7, 18.8), control1: pt(18.1, 20), control2: pt(18.5, 19.5))
        p.addLine(to: pt(19.2, 16.5))
        p.addCurve(to: pt(19.1, 14.9), control1: pt(19.3, 16), control2: pt(19.3, 15.4))
        p.addLine(to: pt(17.8, 11.1))
        p.addCurve(to: pt(17.6, 9), control1: pt(17.6, 10.4), control2: pt(17.5, 9.9))
        p.addLine(to: pt(18, 7))
        p.addCurve(to: pt(20.9, 4.6), control1: pt(18.4, 5.4), control2: pt(19.4, 4.6))
        p.addCurve(to: pt(22.7, 6.9), control1: pt(22.6, 4.6), control2: pt(23.1, 5.4))
        p.closeSubpath()
        p.move(to: pt(11.2, 21.1))
        p.addLine(to: pt(14.6, 6))
        p.addLine(to: pt(13, 6))
        p.addLine(to: pt(13.3, 4.7))
        p.addLine(to: pt(18.1, 4.7))
        p.addLine(to: pt(17.8, 6))
        p.addLine(to: pt(16.1, 6))
        p.addLine(to: pt(12.7, 21.1))
        p.addLine(to: pt(11.2, 21.1))
        p.closeSubpath()
        p.move(to: pt(6.7, 21.1))
        p.addLine(to: pt(8.1, 6.6))
        p.addLine(to: pt(4.8, 21.1))
        p.addLine(to: pt(3.5, 21.1))
        p.addLine(to: pt(7.2, 4.8))
        p.addLine(to: pt(9.4, 4.8))
        p.addLine(to: pt(8, 18.7))
        p.addLine(to: pt(11.2, 4.7))
        p.addLine(to: pt(12.5, 4.7))
        p.addLine(to: pt(8.8, 21.1))
        p.addLine(to: pt(6.7, 21.1))
        p.closeSubpath()
        p.move(to: pt(0, 26))
        p.addLine(to: pt(26, 26))
        p.addLine(to: pt(26, 0))
        p.addLine(to: pt(0, 0))
        p.addLine(to: pt(0, 26))
        p.closeSubpath()
        return p
    }
}

extension NTSMark {
    /// The mark as a filled view. Even-odd is not optional here — see the note
    /// on the shape.
    static func filled(_ color: Color) -> some View {
        NTSMark().fill(color, style: FillStyle(eoFill: true))
    }
}
