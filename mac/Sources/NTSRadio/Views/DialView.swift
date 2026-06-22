import SwiftUI

/// The radial mixtape dial. Fixed 620×580 design canvas (= popover width − rail),
/// center (310,290) — matching the prototype's geometry constants, generalised
/// from 10 to N mixtapes (pitch = 360/N).
///
/// Wedges are drawn as non-interactive visuals; a single hit layer over the
/// dial maps cursor position → angle → wedge index. (Stacking N full-size
/// interactive wedges doesn't work: SwiftUI hit-testing doesn't fall through
/// from the topmost sibling to the ones beneath, so only the last-drawn wedge
/// would respond.)
struct DialView: View {
    @EnvironmentObject var model: AppModel

    private let cx: CGFloat = 310
    private let cy: CGFloat = 290
    private let iconRing: CGFloat = 206
    private let iconSize: CGFloat = 56
    private let hubRadius: CGFloat = 113   // dead zone: the hub assembly

    private var tapes: [Mixtape] { model.catalog.mixtapes }
    private var pitch: Double { tapes.isEmpty ? 36 : 360.0 / Double(tapes.count) }
    private var half: Double { pitch / 2 }

    private func centerAngle(_ i: Int) -> Double { -90 + Double(i) * pitch }

    var body: some View {
        ZStack {
            // Full-bleed now-playing backdrop: the mixtape's looping video, or
            // the live channel's current-program artwork. Falls back to the bare
            // stage when nothing is playing.
            stageBackground

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
                    .frame(width: 620, height: 580)
                    .clipShape(sector(i))
                    .allowsHitTesting(false)
                }
            }

            // Single hit layer (under the hub, over the wedges)
            Color.clear
                .contentShape(Rectangle())
                .onContinuousHover { phase in
                    switch phase {
                    case .active(let loc): model.hoverIndex = wedgeIndex(at: loc)
                    case .ended: model.hoverIndex = nil
                    }
                }
                .gesture(SpatialTapGesture().onEnded { ev in
                    if let i = wedgeIndex(at: ev.location) { model.select(.mixtape(i)) }
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
                .frame(width: iconSize, height: iconSize)
                .clipShape(Circle())
                .saturation(lit ? 1 : 0.5)
                .brightness(lit ? 0 : -0.1)
                .scaleEffect(lit ? 1.1 : 1)
                .position(x: cx + iconRing * cos(a), y: cy + iconRing * sin(a))
                .allowsHitTesting(false)
            }

            hub.position(x: cx, y: cy)
        }
        .frame(width: 620, height: 580)
        .background(Theme.stage)
        .clipped()
    }

    /// Map a point in dial space to a wedge index (nil inside the hub zone).
    private func wedgeIndex(at p: CGPoint) -> Int? {
        guard !tapes.isEmpty else { return nil }
        let dx = p.x - cx, dy = p.y - cy
        if hypot(dx, dy) < hubRadius { return nil }
        var rel = (atan2(dy, dx) * 180 / .pi - (-90)).truncatingRemainder(dividingBy: 360)
        if rel < 0 { rel += 360 }
        return (Int((rel / pitch).rounded()) % tapes.count + tapes.count) % tapes.count
    }

    private func isLit(_ i: Int) -> Bool {
        if model.hoverIndex == i { return true }
        if case .mixtape(let s) = model.selection { return s == i && model.hoverIndex == nil }
        return false
    }

    /// The mixtape currently playing (full-bleed video backdrop), if any.
    private var playingMixtape: Mixtape? {
        guard model.isPlaying, case .mixtape(let i) = model.selection, tapes.indices.contains(i) else { return nil }
        return tapes[i]
    }

    /// The dial stage shows a full-bleed video only while a mixtape plays; for a
    /// live channel it stays the default stage (the program art fills the
    /// channel's card in the rail instead).
    @ViewBuilder private var stageBackground: some View {
        if let m = playingMixtape {
            ZStack {
                AsyncImage(url: m.coverURL) { $0.resizable().scaledToFill() } placeholder: { Theme.stageInner }
                if let anim = m.animationURL { WedgeAnimation(url: anim) }
                scrim
            }
            .frame(width: 620, height: 580)
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

    private func sector(_ i: Int) -> Sector {
        Sector(centerX: cx, centerY: cy,
               startDeg: centerAngle(i) - half,
               endDeg: centerAngle(i) + half)
    }

    /// Hub label — only shown for a mixtape (a hovered wedge or a selected
    /// mixtape). Empty when a channel is the source, so the hub stays a bare
    /// play/pause control.
    private var centerLabel: String {
        if let h = model.hoverIndex, tapes.indices.contains(h) { return tapes[h].title.uppercased() }
        if case .mixtape = model.selection { return model.displayName }
        return ""
    }

    private var pointerRotation: Double {
        if case .mixtape(let s) = model.selection { return Double(s) * pitch }
        return 0
    }

    private var hub: some View {
        ZStack {
            // Selection pointer
            ZStack(alignment: .top) {
                Color.clear
                RoundedRectangle(cornerRadius: 2)
                    .fill(model.accent)
                    .frame(width: 3, height: 18)
                    .padding(.top, 6)
            }
            .frame(width: 226, height: 226)
            .rotationEffect(.degrees(pointerRotation))
            .opacity(model.isLive ? 0 : 1)
            .allowsHitTesting(false)
            .animation(.spring(response: 0.45, dampingFraction: 0.6), value: pointerRotation)

            // Inner ring
            Circle()
                .fill(Theme.stageInner)
                .overlay(Circle().stroke(Theme.hairline(0.14), lineWidth: 1))
                .frame(width: 190, height: 190)
                .allowsHitTesting(false)

            // Play / pause hub
            Button { model.togglePlay() } label: {
                VStack(spacing: 9) {
                    Image(systemName: model.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 17))
                        .foregroundStyle(Theme.popover.opacity(0.88))
                    if !centerLabel.isEmpty {
                        ChipText(text: centerLabel, font: Theme.display(16, .heavy), fg: Theme.hubInk)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: 150)
                    }
                }
            }
            .buttonStyle(.plain)
            .frame(width: 166, height: 166)
            .background(Circle().fill(Theme.hubInk))
            .clipShape(Circle())
            .shadow(color: .black.opacity(0.5), radius: 11, y: 6)
        }
        .frame(width: 226, height: 226)
    }
}
