import SwiftUI

/// The radial mixtape dial — the Atonemo's sixteen-detent rotary, on screen.
///
/// Geometry is derived from the view's actual size so the dial grows and shrinks
/// with the window. The layout follows the hardware: the mixtape icons are
/// printed on the faceplate *around* the knob, the knob itself is knurled with a
/// detent tick per position, and a triangular index rides the knob's rim and
/// turns to whichever mixtape is selected.
///
/// Wedges are drawn as non-interactive visuals; a single hit layer over the dial
/// maps cursor position → angle → wedge index. (Stacking N full-size interactive
/// wedges doesn't work: SwiftUI hit-testing doesn't fall through from the topmost
/// sibling to the ones beneath, so only the last-drawn wedge would respond.)
struct DialView: View {
    @EnvironmentObject var model: AppModel

    /// Resolved dial geometry. Every radius is a fraction of the dial's diameter,
    /// which is itself the smaller of the two dimensions — the dial is round, so
    /// the short side is what constrains it.
    private struct Geo {
        let w: CGFloat, h: CGFloat
        var cx: CGFloat { w / 2 }
        var cy: CGFloat { h / 2 }
        /// The dial's overall diameter, leaving room for the icon ring's labels.
        var d: CGFloat { min(w, h) * 0.92 }
        var iconRing: CGFloat { d * 0.435 }
        var iconSize: CGFloat { max(20, d * 0.078) }
        var knob: CGFloat { d * 0.70 }
        var face: CGFloat { knob * 0.84 }
        /// Dead zone: a click inside the knob isn't aimed at a wedge.
        var hubRadius: CGFloat { knob / 2 }
        var bleed: CGFloat { max(w, h) * 2 }
    }

    private var tapes: [Mixtape] { model.catalog.mixtapes }
    private var pitch: Double { tapes.isEmpty ? 36 : 360.0 / Double(tapes.count) }
    private var half: Double { pitch / 2 }

    private func centerAngle(_ i: Int) -> Double { -90 + Double(i) * pitch }

    /// What the knob face is showing: the tape under the cursor while hovering,
    /// otherwise the selected one. Hovering previews without committing, the way
    /// turning a detent past a position does.
    private var facing: Mixtape? {
        if let i = model.hoverIndex, tapes.indices.contains(i) { return tapes[i] }
        return model.currentMixtape
    }
    private var facingIndex: Int? {
        guard let f = facing else { return nil }
        return tapes.firstIndex { $0.alias == f.alias }
    }

    var body: some View {
        GeometryReader { proxy in
            let g = Geo(w: proxy.size.width, h: proxy.size.height)
            // The proxy reports `.zero` on the first layout pass, and again while
            // siblings are still measuring. Every radius below is a fraction of
            // that, so the whole dial collapses to a point in the top-left corner
            // for those frames — and worse, the hit layer would measure a tap's
            // angle from (0, 0) and select a wedge the cursor is nowhere near.
            // Show the bare stage until there is a real size to build from.
            if min(g.w, g.h) > 0 {
                dial(g)
            } else {
                Theme.stage
            }
        }
    }

    private func dial(_ g: Geo) -> some View {
        ZStack {
            // Full-bleed now-playing backdrop: the mixtape's looping video.
            stageBackground(g)

            // Cover-art wedges — a hovered slice previews its still poster with
            // the looping animation layered on top (clipped to the sector).
            ForEach(Array(tapes.enumerated()), id: \.element.id) { i, tape in
                if model.hoverIndex == i {
                    ZStack {
                        AsyncImage(url: tape.coverURL) { img in
                            img.resizable().scaledToFill()
                        } placeholder: {
                            Color.clear
                        }
                        if let anim = tape.animationURL {
                            WedgeAnimation(url: anim)
                        }
                    }
                    .frame(width: g.w, height: g.h)
                    .clipShape(sector(i, g))
                    .opacity(0.5)
                    .allowsHitTesting(false)
                }
            }

            // Single hit layer (under the knob, over the wedges)
            Color.clear
                .contentShape(Rectangle())
                .onContinuousHover { phase in
                    switch phase {
                    case .active(let loc): model.hoverIndex = wedgeIndex(at: loc, g)
                    case .ended: model.hoverIndex = nil
                    }
                }
                .gesture(SpatialTapGesture().onEnded { ev in
                    if let i = wedgeIndex(at: ev.location, g) { model.select(.mixtape(tapes[i].alias)) }
                })

            // Icons printed on the faceplate, outside the knob — where the
            // Atonemo puts them. Always visible: they're how you aim.
            ForEach(Array(tapes.enumerated()), id: \.element.id) { i, tape in
                let lit = isLit(i)
                let a = centerAngle(i) * .pi / 180
                AsyncImage(url: tape.iconURL) { img in
                    img.resizable().scaledToFit()
                } placeholder: {
                    Color.clear
                }
                .frame(width: g.iconSize, height: g.iconSize)
                .opacity(lit ? 1 : 0.42)
                .scaleEffect(lit ? 1.12 : 1)
                .animation(.easeOut(duration: 0.14), value: lit)
                .position(x: g.cx + g.iconRing * cos(a), y: g.cy + g.iconRing * sin(a))
                .allowsHitTesting(false)
            }

            knob(g).position(x: g.cx, y: g.cy)
        }
        .frame(width: g.w, height: g.h)
        .background(Theme.stage)
        .clipped()
    }

    /// Map a point in dial space to a wedge index (nil inside the knob).
    private func wedgeIndex(at p: CGPoint, _ g: Geo) -> Int? {
        guard !tapes.isEmpty else { return nil }
        let dx = p.x - g.cx, dy = p.y - g.cy
        if hypot(dx, dy) < g.hubRadius { return nil }
        var rel = (atan2(dy, dx) * 180 / .pi - (-90)).truncatingRemainder(dividingBy: 360)
        if rel < 0 { rel += 360 }
        return (Int((rel / pitch).rounded()) % tapes.count + tapes.count) % tapes.count
    }

    private func isLit(_ i: Int) -> Bool {
        if model.hoverIndex == i { return true }
        if model.hoverIndex == nil, tapes.indices.contains(i) { return model.currentMixtape?.alias == tapes[i].alias }
        return false
    }

    private var playingMixtape: Mixtape? {
        guard model.isPlaying, case .mixtape = model.selection else { return nil }
        return model.currentMixtape
    }

    @ViewBuilder private func stageBackground(_ g: Geo) -> some View {
        if let m = playingMixtape {
            ZStack {
                AsyncImage(url: m.coverURL) { $0.resizable().scaledToFill() } placeholder: { Theme.stageInner }
                if let anim = m.animationURL { WedgeAnimation(url: anim) }
                LinearGradient(colors: [.black.opacity(0.62), .black.opacity(0.78)],
                               startPoint: .top, endPoint: .bottom)
            }
            .frame(width: g.w, height: g.h)
            .clipped()
            .allowsHitTesting(false)
        } else {
            Theme.stageInner
        }
    }

    private func sector(_ i: Int, _ g: Geo) -> Sector {
        Sector(centerX: g.cx, centerY: g.cy,
               startDeg: centerAngle(i) - half,
               endDeg: centerAngle(i) + half,
               radius: g.bleed)
    }

    /// Where the index mark should point, wrapped into 0..<360 like a compass.
    /// `model.knobAngle` is the unwrapped position it actually travels to.
    private var pointerTarget: Double {
        guard let i = facingIndex else { return model.knobAngle }
        return Double(i) * pitch
    }

    /// The signed turn from the knob's current angle to `target`, taking whichever
    /// way round is shorter — never more than half a turn.
    private func shortestTurn(to target: Double) -> Double {
        var d = (target - model.knobAngle).truncatingRemainder(dividingBy: 360)
        if d > 180 { d -= 360 }
        if d < -180 { d += 360 }
        return d
    }

    /// The knob: a plain disc carrying the mixtape's cover, and a triangular index
    /// on its rim that turns to the selected position.
    private func knob(_ g: Geo) -> some View {
        ZStack {
            Circle()
                .fill(Theme.stageInner)
                .frame(width: g.knob, height: g.knob)
                .shadow(color: .black.opacity(0.65), radius: g.knob * 0.06, y: g.knob * 0.02)

            knobFace(g)

            // Index mark, riding the rim. It turns with the selection, so the
            // triangle always aims at the mixtape the knob is clicked into.
            IndexMark()
                .fill(Theme.ink)
                .frame(width: g.knob * 0.075, height: g.knob * 0.05)
                .offset(y: -g.knob / 2 + g.knob * 0.038)
                .rotationEffect(.degrees(model.knobAngle))
                .opacity(facing == nil ? 0 : 1)
                .animation(.spring(response: 0.45, dampingFraction: 0.72), value: model.knobAngle)
                .onAppear { model.knobAngle = pointerTarget }
                .onChange(of: pointerTarget) { _, new in model.knobAngle += shortestTurn(to: new) }
        }
        .frame(width: g.knob, height: g.knob)
        .allowsHitTesting(false)
    }

    @ViewBuilder private func knobFace(_ g: Geo) -> some View {
        ZStack {
            Circle().fill(Theme.stageInner)
            if let m = facing {
                AsyncImage(url: m.coverURL) { img in
                    img.resizable().scaledToFill()
                } placeholder: {
                    Color.clear
                }
                .saturation(0.7)
                RadialGradient(colors: [.black.opacity(0.62), .black.opacity(0.93)],
                               center: .center, startRadius: 0, endRadius: g.face * 0.62)
            }

            VStack(spacing: g.face * 0.035) {
                // Under about 96pt across, the face can hold a word or two at a
                // size nobody can read. It holds the mark instead.
                if let m = facing, g.face >= 96 {
                    Text(m.title.uppercased())
                        .font(Theme.display(max(13, g.face * 0.115), .black))
                        .foregroundStyle(Theme.ink)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .minimumScaleFactor(0.6)
                    if g.face >= 150 {
                        Text(m.subtitle)
                            .font(Theme.ui(max(9, g.face * 0.05)))
                            .foregroundStyle(Theme.ink.opacity(0.7))
                            .multilineTextAlignment(.center)
                            .lineLimit(2)
                    }
                } else {
                    // Idle: the mark alone.
                    Image(nsImage: MenuBarIcon.logoImage)
                        .resizable()
                        .renderingMode(.template)
                        .scaledToFit()
                        .frame(width: g.face * 0.20, height: g.face * 0.20)
                        .foregroundStyle(Theme.ink.opacity(0.85))
                }
            }
            // The text sits in the largest square that fits inside the face, so a
            // line can never be wider than the circle is at the height it lands
            // on. Horizontal padding could not do that: it left the box as wide
            // as the disc, and titles that reach the sides — EXPANSIONS, SHEET
            // MUSIC, ISLAND TIME, 4 TO THE FLOOR — were cut off by the clip.
            .frame(width: g.face * 0.70)
        }
        .frame(width: g.face, height: g.face)
        .clipShape(Circle())
        .overlay(Circle().stroke(Theme.dialEdge, lineWidth: 1))
        .shadow(color: .black.opacity(0.55), radius: g.face * 0.06, y: g.face * 0.02)
    }
}

/// The knob's index mark — a triangle whose tip points outward, so once the knob
/// is rotated it reads as an arrow at the selected position.
private struct IndexMark: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.midX, y: r.minY))
        p.addLine(to: CGPoint(x: r.minX, y: r.maxY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.maxY))
        p.closeSubpath()
        return p
    }
}
