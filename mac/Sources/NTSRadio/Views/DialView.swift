import SwiftUI

/// The radial mixtape dial. Originally a fixed 620×580 design canvas; now fluid
/// — all geometry is derived from the view's actual size via `Geo` so the dial
/// grows, shrinks, and stays crisp as the window resizes. The circle is sized
/// off the smaller dimension (it's round), centered in whatever space it gets.
///
/// Wedges are drawn as non-interactive visuals; a single hit layer over the
/// dial maps cursor position → angle → wedge index. (Stacking N full-size
/// interactive wedges doesn't work: SwiftUI hit-testing doesn't fall through
/// from the topmost sibling to the ones beneath, so only the last-drawn wedge
/// would respond.)
struct DialView: View {
    @EnvironmentObject var model: AppModel

    /// Resolved dial geometry for the current view size. The reference design
    /// was 620×580 with the dial limited by the 580 (vertical) extent, so every
    /// original pixel constant is scaled by `k = min(w,h)/580`.
    private struct Geo {
        let w: CGFloat, h: CGFloat
        var cx: CGFloat { w / 2 }
        var cy: CGFloat { h / 2 }
        var k: CGFloat { min(w, h) / 580 }
        var iconRing: CGFloat { 206 * k }
        var iconSize: CGFloat { 56 * k }
        var hubRadius: CGFloat { 113 * k }   // dead zone: the hub assembly
        var bleed: CGFloat { max(w, h) * 2 } // wedge radius — past the frame
    }

    private var tapes: [Mixtape] { model.catalog.mixtapes }
    private var pitch: Double { tapes.isEmpty ? 36 : 360.0 / Double(tapes.count) }
    private var half: Double { pitch / 2 }

    private func centerAngle(_ i: Int) -> Double { -90 + Double(i) * pitch }

    var body: some View {
        GeometryReader { proxy in
            let g = Geo(w: proxy.size.width, h: proxy.size.height)
            ZStack {
                // Full-bleed now-playing backdrop: the mixtape's looping video, or
                // the live channel's current-program artwork. Falls back to the bare
                // stage when nothing is playing.
                stageBackground(g)

                // Cover-art wedges — a hovered slice previews its still poster with
                // the looping animation layered on top (clipped to the sector). The
                // actively-playing source fills the whole stage via stageBackground.
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
                        .allowsHitTesting(false)
                    }
                }

                // Single hit layer (under the hub, over the wedges)
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

                // Monochrome symbol ring (always visible — how you see/aim at each
                // mixtape now that wedges are blank by default).
                ForEach(Array(tapes.enumerated()), id: \.element.id) { i, tape in
                    let lit = isLit(i)
                    let a = centerAngle(i) * .pi / 180
                    AsyncImage(url: tape.iconURL) { img in
                        img.resizable().scaledToFill()
                    } placeholder: {
                        Color.clear
                    }
                    .frame(width: g.iconSize, height: g.iconSize)
                    .clipShape(Circle())
                    .saturation(lit ? 1 : 0.5)
                    .brightness(lit ? 0 : -0.1)
                    .scaleEffect(lit ? 1.1 : 1)
                    .position(x: g.cx + g.iconRing * cos(a), y: g.cy + g.iconRing * sin(a))
                    .allowsHitTesting(false)
                }

                // The play hub is always present (so the dial never reads as an
                // empty void); in the idle state it just has no selection tail.
                hub(g).position(x: g.cx, y: g.cy)
            }
            .frame(width: g.w, height: g.h)
            .background(Theme.stage)
            .clipped()
        }
    }

    /// Map a point in dial space to a wedge index (nil inside the hub zone).
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

    /// The mixtape currently playing (full-bleed video backdrop), if any.
    private var playingMixtape: Mixtape? {
        guard model.isPlaying, case .mixtape = model.selection else { return nil }
        return model.currentMixtape
    }

    /// The dial stage shows a full-bleed video only while a mixtape plays; for a
    /// live channel it stays the default stage (the program art fills the
    /// channel's card in the rail instead).
    @ViewBuilder private func stageBackground(_ g: Geo) -> some View {
        if let m = playingMixtape {
            ZStack {
                AsyncImage(url: m.coverURL) { $0.resizable().scaledToFill() } placeholder: { Theme.stageInner }
                if let anim = m.animationURL { WedgeAnimation(url: anim) }
                scrim
            }
            .frame(width: g.w, height: g.h)
            .clipped()
            .allowsHitTesting(false)
        } else {
            Theme.stageInner
        }
    }

    /// Dim layer over the backdrop so the icon ring and hub stay legible.
    private var scrim: some View {
        LinearGradient(
            colors: [.black.opacity(0.30), .black.opacity(0.50)],
            startPoint: .top, endPoint: .bottom)
    }

    private func sector(_ i: Int, _ g: Geo) -> Sector {
        Sector(centerX: g.cx, centerY: g.cy,
               startDeg: centerAngle(i) - half,
               endDeg: centerAngle(i) + half,
               radius: g.bleed)
    }

    private var pointerRotation: Double {
        if let alias = model.currentMixtape?.alias,
           let idx = tapes.firstIndex(where: { $0.alias == alias }) {
            return Double(idx) * pitch
        }
        return 0
    }

    private func hub(_ g: Geo) -> some View {
        let k = g.k
        return ZStack {
            // Selection pointer — a triangular tail on the hub rim pointing at the
            // active mixtape (matches the prototype; was a thin tick before).
            ZStack(alignment: .top) {
                Color.clear
                HubTail()
                    .fill(Theme.hubInk)
                    .frame(width: 30 * k, height: 17 * k)
                    .padding(.top, 18 * k)
            }
            .frame(width: 226 * k, height: 226 * k)
            .rotationEffect(.degrees(pointerRotation))
            .opacity((model.isLive || model.isIdle) ? 0 : 1)   // no tail until a mixtape is picked
            .allowsHitTesting(false)
            .animation(.spring(response: 0.45, dampingFraction: 0.6), value: pointerRotation)

            // Inner ring
            Circle()
                .fill(Theme.stageInner)
                .overlay(Circle().stroke(Theme.hairline(0.14), lineWidth: 1))
                .frame(width: 190 * k, height: 190 * k)
                .allowsHitTesting(false)

            // Center hub disc — a passive focal element, always present (no
            // play/pause control here; transport lives in the now-playing bar).
            Circle()
                .fill(Theme.hubInk)
                .frame(width: 166 * k, height: 166 * k)
                .shadow(color: .black.opacity(0.5), radius: 11 * k, y: 6 * k)
        }
        .frame(width: 226 * k, height: 226 * k)
    }
}

/// The hub's selection tail — a triangle whose tip points outward (up before the
/// pointer's rotation), reading as a tail off the hub disc toward the active
/// mixtape.
private struct HubTail: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.midX, y: r.minY))     // tip (outward)
        p.addLine(to: CGPoint(x: r.minX, y: r.maxY))  // base left
        p.addLine(to: CGPoint(x: r.maxX, y: r.maxY))  // base right
        p.closeSubpath()
        return p
    }
}
