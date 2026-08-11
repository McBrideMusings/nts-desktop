import SwiftUI
import AppKit

/// The catalog: schedule, saved items, mixtapes and search, laid over the whole
/// faceplate.
///
/// It covers rather than pushes. A drawer would have to change the window's width
/// every time it opened, which moves the dial and the channel cards out from under
/// the cursor; covering leaves the faceplate's geometry alone, and the faceplate is
/// the part of this app that's meant to feel like an object.
struct CatalogOverlay: View {
    @EnvironmentObject var model: AppModel
    @FocusState private var searchFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            header
            Rectangle().fill(Theme.hairline(0.08)).frame(height: 1)
            ServiceBanner()

            if let detail = model.detail {
                ScrollView { DetailPane(detail: detail) }
            } else if model.catalogTab == .explore, model.query.isEmpty {
                // Explore brings its own filter controls and its own paging, so
                // it owns the whole pane rather than feeding the shared grid.
                ExploreView()
            } else if model.catalogTab == .schedule, model.query.isEmpty {
                // The schedule is read down a time column, so it gets a timeline
                // rather than the tile grid. A query still answers in tiles: it
                // mixes schedule slots, shows and mixtapes, which share no clock.
                ScheduleTimeline()
            } else {
                grid
            }
        }
        .background(Theme.popover.opacity(0.97))
        .background(.ultraThinMaterial)
        .transition(.opacity)
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 14) {
            if model.detail != nil {
                Button { model.detail = nil } label: {
                    Label("BACK", systemImage: "chevron.left")
                        .labelStyle(.titleAndIcon)
                        .font(Theme.mono(9, .bold))
                        .tracking(1.3)
                        .foregroundStyle(Theme.popover)
                        .padding(.horizontal, 12).padding(.vertical, 9)
                        .background(Theme.ink)
                }
                .buttonStyle(.plain)
            } else {
                tabs
            }

            Spacer(minLength: 12)
            searchField

            Button { model.toggleCatalog() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.ink)
                    .frame(width: 28, height: 28)
                    .background(Theme.hairline(0.08))
            }
            .buttonStyle(.plain)
            .help("Close the catalog")
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 13)
    }

    /// Dimmed while a query is running: the search covers everything at once, so
    /// whichever tab is selected has stopped deciding what you're looking at.
    private var tabs: some View {
        HStack(spacing: 2) {
            ForEach(CatalogTab.allCases) { tab in
                let on = model.catalogTab == tab && model.query.isEmpty
                Button { model.catalogTab = tab; model.query = "" } label: {
                    Text(tab.label)
                        .font(Theme.mono(9, .bold))
                        .tracking(1.3)
                        .foregroundStyle(on ? Theme.popover : Theme.inkMuted)
                        .padding(.horizontal, 12).padding(.vertical, 9)
                        .background(on ? Theme.ink : .clear)
                }
                .buttonStyle(.plain)
            }
        }
        .opacity(model.query.isEmpty ? 1 : 0.4)
    }

    private var searchField: some View {
        HStack(spacing: 9) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11))
                .foregroundStyle(Theme.inkMuted)
            TextField("Search shows, hosts, mixtapes", text: $model.query)
                .textFieldStyle(.plain)
                .font(Theme.ui(12))
                .foregroundStyle(Theme.ink)
                .focused($searchFocused)
            if !model.query.isEmpty {
                Button { model.query = ""; searchFocused = true } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.inkMuted)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 9)
        .frame(width: 300)
        .background(Theme.hairline(searchFocused ? 0.10 : 0.06))
        .overlay(Rectangle().stroke(Theme.hairline(searchFocused ? 0.34 : 0.08), lineWidth: 1))
    }

    // MARK: Grid

    private var grid: some View {
        let rows = model.catalogRows
        return ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                if !model.query.isEmpty {
                    HStack {
                        Text("\(rows.count) MATCH\(rows.count == 1 ? "" : "ES")")
                        Text("·").opacity(0.5)
                        Text(model.searchScope)
                    }
                    .font(Theme.mono(9, .bold))
                    .tracking(1.4)
                    .foregroundStyle(Theme.inkMuted)
                    .padding(.horizontal, 18)
                    .padding(.top, 14)
                }

                if rows.isEmpty {
                    emptyState
                } else {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 152, maximum: 240), spacing: 14)],
                              alignment: .leading, spacing: 16) {
                        ForEach(rows) { row in
                            Tile(row: row)
                        }
                    }
                    .padding(18)
                }
            }
        }
    }

    @ViewBuilder private var emptyState: some View {
        VStack(spacing: 8) {
            Text(model.query.isEmpty ? emptyTabMessage : "Nothing matches “\(model.query)”.")
                .font(Theme.ui(13))
                .foregroundStyle(Theme.inkMuted)
            if model.query.isEmpty, model.catalogTab == .saved {
                Text("Star a show or a mixtape and it lands here.")
                    .font(Theme.mono(9))
                    .tracking(1.2)
                    .foregroundStyle(Theme.inkMuted.opacity(0.7))
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 70)
    }

    private var emptyTabMessage: String {
        switch model.catalogTab {
        case .saved:    return "Nothing saved yet."
        case .schedule: return "The schedule hasn’t loaded yet."
        case .explore:  return "Nothing matches these filters."
        }
    }
}

// MARK: - Tile

/// One catalog result. Shared by the search grid, Saved, and Explore — they
/// return different things, but `CatalogRow` has already flattened all of them
/// into the same shape by the time they get here.
struct Tile: View {
    @EnvironmentObject var model: AppModel
    let row: CatalogRow
    @State private var hovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack(alignment: .topLeading) {
                Rectangle()
                    .fill(Theme.hairline(0.05))
                    .aspectRatio(1, contentMode: .fit)
                    // The schedule carries no artwork and the show index can't
                    // reach every show, so some slots genuinely have no picture.
                    // The mark makes that read as an empty sleeve rather than a
                    // failed download.
                    .overlay { ArtworkPlaceholder() }
                    .overlay {
                        if let url = row.image {
                            AsyncImage(url: url) { img in
                                img.resizable().scaledToFill()
                            } placeholder: {
                                Color.clear
                            }
                        }
                    }
                    .clipped()

                if row.live {
                    Text("LIVE")
                        .font(Theme.mono(8, .bold))
                        .tracking(1.4)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6).padding(.vertical, 4)
                        .background(Theme.liveDot)
                        .padding(8)
                }
            }
            .overlay(alignment: .bottomTrailing) { if hovering { hoverActions } }

            Text(row.title.uppercased())
                .font(Theme.display(12, .heavy))
                .foregroundStyle(Theme.ink)
                .lineLimit(2)
                .padding(.top, 9)
            Text(row.meta)
                .font(Theme.mono(9))
                .tracking(0.8)
                .foregroundStyle(Theme.inkMuted)
                .lineLimit(1)
                .padding(.top, 4)
        }
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        // An Explore result is a finished recording, so clicking it starts it —
        // same as clicking a mixtape on the dial. A schedule slot opens its show
        // instead: the audio either hasn't been broadcast yet or is already the
        // live channel you can hear from the rail.
        .onTapGesture {
            if case .episode = row.playable { model.play(row) } else { model.open(row) }
        }
    }

    /// Play and star, revealed on hover so the resting grid stays a wall of
    /// artwork rather than a wall of buttons.
    private var hoverActions: some View {
        HStack(spacing: 6) {
            if row.playable != nil {
                iconButton("play.fill") { model.play(row) }
            }
            if row.savedItem != nil {
                iconButton(model.isSaved(row) ? "star.fill" : "star") { model.toggleSaved(row) }
            }
        }
        .padding(8)
    }

    private func iconButton(_ name: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: name)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Theme.popover)
                .frame(width: 26, height: 26)
                .background(Theme.ink)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Detail

private struct DetailPane: View {
    @EnvironmentObject var model: AppModel
    let detail: CatalogDetail

    var body: some View {
        switch detail {
        case .show(let alias, let fallback): ShowDetailPane(alias: alias, fallbackTitle: fallback)
        case .mixtape(let alias): MixtapeDetailPane(alias: alias)
        }
    }
}

private struct ShowDetailPane: View {
    @EnvironmentObject var model: AppModel
    let alias: String
    let fallbackTitle: String

    private var detail: NTSAPI.ShowDetail? { model.showDetails[alias] }
    private var episodes: [NTSAPI.Episode] { model.showEpisodes[alias] ?? [] }
    private var indexed: NTSAPI.ShowRef? { model.showIndex.ref(alias) }
    private var slot: NTSAPI.Broadcast? { model.schedule.first { $0.showAlias == alias } }

    private var artwork: URL? { detail?.image ?? slot?.image ?? indexed?.pictureURL }
    private var savedItem: Saved.Item {
        Saved.Item(kind: .show, alias: alias, title: detail?.name ?? fallbackTitle,
                   subtitle: detail?.location ?? "", image: artwork?.absoluteString)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 22) {
            Rectangle()
                .fill(Theme.hairline(0.05))
                .frame(width: 300, height: 300)
                .overlay {
                    if let artwork {
                        AsyncImage(url: artwork) { $0.resizable().scaledToFill() } placeholder: { Color.clear }
                    }
                }
                .clipped()

            VStack(alignment: .leading, spacing: 0) {
                Text((detail?.name ?? fallbackTitle).uppercased())
                    .font(Theme.display(30, .black))
                    .foregroundStyle(Theme.ink)

                Text(subline)
                    .font(Theme.mono(9, .bold))
                    .tracking(1.6)
                    .foregroundStyle(Theme.inkMuted)
                    .padding(.top, 10)

                let tags = (detail?.genres ?? slot?.genres ?? []) + (detail?.moods ?? [])
                if !tags.isEmpty {
                    ChipRow(tags: tags)
                        .padding(.top, 14)
                }

                if let d = detail, !d.description.isEmpty {
                    Text(d.description)
                        .font(Theme.ui(13))
                        .foregroundStyle(Color(hex: 0xc2c1bc))
                        .lineSpacing(4)
                        .frame(maxWidth: 620, alignment: .leading)
                        .padding(.top, 14)
                } else if detail == nil {
                    Text("Loading the show page…")
                        .font(Theme.ui(12))
                        .foregroundStyle(Theme.inkMuted)
                        .padding(.top, 14)
                }

                actions.padding(.top, 18)

                if !episodes.isEmpty {
                    SectionLabel("PAST EPISODES · \(episodes.count)").padding(.top, 24)
                    ForEach(episodes) { ep in
                        EpisodeRow(episode: ep)
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(22)
        .task { await model.loadShow(alias) }
    }

    private var subline: String {
        var bits: [String] = []
        if let s = slot { bits.append("NTS \(s.channel)") }
        let loc = detail?.location ?? slot?.location ?? indexed?.location ?? ""
        if !loc.isEmpty { bits.append(loc) }
        if let s = slot, !s.startEnd.isEmpty { bits.append(s.startEnd) }
        return bits.joined(separator: " · ")
    }

    private var actions: some View {
        HStack(spacing: 8) {
            if let s = slot {
                ActionButton(title: model.isOnAir(s) ? "▶ PLAY LIVE" : "▶ TUNE TO NTS \(s.channel)",
                             filled: true) {
                    model.select(.channel(s.channel))
                    model.loadCurrent(autoplay: true)
                }
            }
            ActionButton(title: model.saved.contains(.show, alias) ? "★ SAVED" : "☆ SAVE SHOW",
                         filled: false) {
                model.saved.toggle(savedItem)
            }
            if let url = URL(string: "https://www.nts.live/shows/\(alias)") {
                ActionButton(title: "↗ NTS.LIVE", filled: false) { NSWorkspace.shared.open(url) }
            }
        }
    }
}

private struct MixtapeDetailPane: View {
    @EnvironmentObject var model: AppModel
    let alias: String

    private var tape: Mixtape? { model.catalog.mixtapes.first { $0.alias == alias } }
    private var detent: Int? { model.catalog.mixtapes.firstIndex { $0.alias == alias }.map { $0 + 1 } }

    var body: some View {
        if let m = tape {
            HStack(alignment: .top, spacing: 22) {
                Rectangle()
                    .fill(Theme.hairline(0.05))
                    .frame(width: 300, height: 300)
                    .overlay {
                        AsyncImage(url: m.coverURL) { $0.resizable().scaledToFill() } placeholder: { Color.clear }
                    }
                    .clipped()

                VStack(alignment: .leading, spacing: 0) {
                    Text(m.title.uppercased())
                        .font(Theme.display(30, .black))
                        .foregroundStyle(Theme.ink)
                    Text("INFINITE MIXTAPE · DETENT \(String(format: "%02d", detent ?? 0)) OF \(model.catalog.mixtapes.count)")
                        .font(Theme.mono(9, .bold))
                        .tracking(1.6)
                        .foregroundStyle(Theme.inkMuted)
                        .padding(.top, 10)

                    Text(m.subtitle)
                        .font(Theme.ui(13))
                        .foregroundStyle(Color(hex: 0xc2c1bc))
                        .lineSpacing(4)
                        .frame(maxWidth: 620, alignment: .leading)
                        .padding(.top, 14)

                    HStack(spacing: 8) {
                        ActionButton(title: "▶ PLAY MIXTAPE", filled: true) {
                            model.select(.mixtape(alias))
                            model.loadCurrent(autoplay: true)
                        }
                        ActionButton(title: model.saved.contains(.mixtape, alias) ? "★ SAVED" : "☆ SAVE",
                                     filled: false) {
                            model.saved.toggle(Saved.Item(kind: .mixtape, alias: alias, title: m.title,
                                                          subtitle: m.subtitle,
                                                          image: m.coverURL?.absoluteString))
                        }
                    }
                    .padding(.top, 18)

                    // The credits are the only path from a mixtape to the shows
                    // inside it — the dial can't express that, and neither could
                    // the old single-screen layout.
                    if m.credits.isEmpty {
                        SectionLabel("SHOWS FEEDING THIS MIXTAPE").padding(.top, 24)
                        Text("NTS lists no credits for this one.")
                            .font(Theme.ui(12))
                            .foregroundStyle(Theme.inkMuted)
                            .padding(.top, 6)
                    } else {
                        SectionLabel("SHOWS FEEDING THIS MIXTAPE · \(m.credits.count)").padding(.top, 24)
                        CreditRow(credits: m.credits)
                            .padding(.top, 6)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(22)
        } else {
            Text("That mixtape is no longer in the catalog.")
                .font(Theme.ui(13))
                .foregroundStyle(Theme.inkMuted)
                .padding(40)
        }
    }
}

// MARK: - Small parts

/// What sits behind a tile, hero or timeline sleeve when there is no artwork.
struct ArtworkPlaceholder: View {
    /// The tile's mark is drawn for a 152pt-wide cover; the timeline's sleeve is
    /// 40pt, where the same 26pt mark fills the square.
    var size: CGFloat = 26

    var body: some View {
        Image(nsImage: MenuBarIcon.logoImage)
            .resizable()
            .renderingMode(.template)
            .scaledToFit()
            .frame(width: size, height: size)
            .foregroundStyle(Theme.ink.opacity(0.10))
    }
}

private struct SectionLabel: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text)
            .font(Theme.mono(9, .bold))
            .tracking(1.6)
            .foregroundStyle(Theme.inkMuted)
    }
}

private struct ChipRow: View {
    let tags: [String]
    var wide = false

    var body: some View {
        FlowLayout(spacing: 5) {
            ForEach(tags, id: \.self) { t in
                Text(t.uppercased())
                    .font(Theme.mono(8, .semibold))
                    .tracking(1.2)
                    .foregroundStyle(Color(hex: 0xc9c8c2))
                    .lineLimit(1)
                    .padding(.horizontal, 6).padding(.vertical, 4)
                    .overlay(Rectangle().stroke(Theme.hairline(0.14), lineWidth: 1))
            }
        }
        .frame(maxWidth: wide ? 620 : 520, alignment: .leading)
    }
}

/// A mixtape's credits, each one a link into that show's page. Every credit
/// carries its own alias from the feed, so this is a real route from a mixtape to
/// the shows and hosts inside it rather than a list of names.
private struct CreditRow: View {
    @EnvironmentObject var model: AppModel
    let credits: [NTSAPI.MixtapeCredit]

    var body: some View {
        FlowLayout(spacing: 6) {
            ForEach(credits) { c in
                CreditChip(credit: c) {
                    guard !c.alias.isEmpty else { return }
                    model.detail = .show(alias: c.alias, fallbackTitle: c.name)
                    Task { await model.loadShow(c.alias) }
                }
            }
        }
        .frame(maxWidth: 620, alignment: .leading)
    }
}

private struct CreditChip: View {
    let credit: NTSAPI.MixtapeCredit
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        let linked = !credit.alias.isEmpty
        Text(credit.name.uppercased())
            .font(Theme.mono(8, .semibold))
            .tracking(1.2)
            .foregroundStyle(linked && hovering ? Theme.popover : Color(hex: 0xc9c8c2))
            .lineLimit(1)
            .padding(.horizontal, 7).padding(.vertical, 5)
            .background(linked && hovering ? Theme.ink : .clear)
            .overlay(Rectangle().stroke(Theme.hairline(linked ? 0.22 : 0.10), lineWidth: 1))
            .contentShape(Rectangle())
            .onHover { hovering = $0 && linked }
            .onTapGesture(perform: action)
    }
}

private struct ActionButton: View {
    let title: String
    let filled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(Theme.mono(9, .bold))
                .tracking(1.3)
                .foregroundStyle(filled ? Theme.popover : Theme.ink)
                .padding(.horizontal, 16).padding(.vertical, 11)
                .background(filled ? Theme.ink : .clear)
                .overlay(filled ? nil : Rectangle().stroke(Theme.hairline(0.14), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}

private struct EpisodeRow: View {
    @EnvironmentObject var model: AppModel
    let episode: NTSAPI.Episode
    @State private var hovering = false

    private var playing: Bool {
        model.selection == .episode(show: episode.showAlias, episode: episode.alias)
    }

    var body: some View {
        HStack(spacing: 11) {
            Rectangle()
                .fill(Theme.hairline(0.05))
                .frame(width: 40, height: 40)
                .overlay {
                    if let url = episode.image {
                        AsyncImage(url: url) { $0.resizable().scaledToFill() } placeholder: { Color.clear }
                    }
                }
                .clipped()
            VStack(alignment: .leading, spacing: 3) {
                Text(episode.name.uppercased())
                    .font(Theme.display(12, .heavy))
                    .foregroundStyle(playing ? Theme.liveDot : Theme.ink)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    Text(episode.date)
                    if playing {
                        Text(model.episodeLoading ? "LOADING" : "PLAYING")
                            .foregroundStyle(Theme.liveDot)
                    }
                }
                .font(Theme.mono(9))
                .foregroundStyle(Theme.inkMuted)
            }
            Spacer(minLength: 0)
            if let url = episode.pageURL, hovering {
                Button { NSWorkspace.shared.open(url) } label: {
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.inkMuted)
                        .frame(width: 22, height: 22)
                }
                .buttonStyle(.plain)
                .help("Open on nts.live")
            }
        }
        .frame(maxWidth: 620, alignment: .leading)
        .padding(.vertical, 8)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Theme.hairline(0.06)).frame(height: 1)
        }
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        // Tapping the row plays the episode; the arrow is the way out to the web
        // page. It was the other way round when nothing here could be played.
        .onTapGesture {
            guard !episode.alias.isEmpty, !episode.showAlias.isEmpty else { return }
            model.select(.episode(show: episode.showAlias, episode: episode.alias))
        }
    }
}

/// Wrapping row of chips. SwiftUI has no flow container, and an `HStack` of a
/// show's genres plus moods runs off the pane — this measures each subview and
/// breaks the line when the next one won't fit.
struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, lineH: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x > 0, x + s.width > width { x = 0; y += lineH + spacing; lineH = 0 }
            x += s.width + spacing
            lineH = max(lineH, s.height)
        }
        return CGSize(width: proposal.width ?? x, height: y + lineH)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, lineH: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x > bounds.minX, x + s.width > bounds.maxX { x = bounds.minX; y += lineH + spacing; lineH = 0 }
            v.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(s))
            x += s.width + spacing
            lineH = max(lineH, s.height)
        }
    }
}
