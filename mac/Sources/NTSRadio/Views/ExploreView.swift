import SwiftUI

/// Browse the archive by mood and genre — the only route in the app to the
/// ~89,000 episodes that are neither on air this fortnight nor on the dial.
///
/// The filter controls sit above the results and always state what is being
/// asked for. A grid of episodes with no visible reason for *those* episodes is
/// unreadable, and the filters are also the only way to tell an empty result
/// from a failed one.
struct ExploreView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            controls
            Rectangle().fill(Theme.hairline(0.06)).frame(height: 1)
            if model.genreDrawerOpen {
                GenreDrawer()
                Rectangle().fill(Theme.hairline(0.06)).frame(height: 1)
            }
            results
        }
    }

    // MARK: Controls

    private var controls: some View {
        VStack(alignment: .leading, spacing: 9) {
            moodRow

            HStack(spacing: 7) {
                Toggle_("GENRES\(model.explore.filters.genres.isEmpty ? "" : " · \(model.explore.filters.genres.count)")",
                        on: model.genreDrawerOpen || !model.explore.filters.genres.isEmpty) {
                    model.genreDrawerOpen.toggle()
                }
                // Two toggles that are not toggles at NTS's end: "Music Only" is
                // the mood tag `no-talkin`, and "Focused" is `genre_count`.
                Toggle_("MUSIC ONLY", on: model.explore.filters.musicOnly) {
                    model.explore.filters.musicOnly.toggle()
                }
                Toggle_("FOCUSED", on: model.explore.filters.focused) {
                    model.explore.filters.focused.toggle()
                }
                Spacer(minLength: 0)
                if !model.explore.filters.isEmpty {
                    Button { model.explore.filters = .init() } label: {
                        Text("CLEAR")
                            .font(Theme.mono(9, .bold))
                            .tracking(1.2)
                            .foregroundStyle(Theme.inkMuted)
                    }
                    .buttonStyle(.plain)
                }
            }

            if !model.explore.filters.genres.isEmpty { selectedGenres }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 11)
    }

    /// The ten moods, each carrying the artwork NTS files it under.
    private var moodRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 7) {
                ForEach(model.moods) { mood in
                    let on = model.explore.filters.mood == mood.id
                    Button { model.toggleMood(mood.id) } label: {
                        HStack(spacing: 6) {
                            Rectangle()
                                .fill(Theme.hairline(0.08))
                                .frame(width: 18, height: 18)
                                .overlay {
                                    if let url = mood.image {
                                        AsyncImage(url: url) { $0.resizable().scaledToFill() }
                                            placeholder: { Color.clear }
                                    }
                                }
                                .clipped()
                            Text(mood.name)
                                .font(Theme.mono(9, .bold))
                                .tracking(1.1)
                        }
                        .foregroundStyle(on ? Theme.popover : Theme.ink)
                        .padding(.horizontal, 7).padding(.vertical, 5)
                        .background(on ? Theme.ink : Theme.hairline(0.05))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .frame(height: 30)
    }

    private var selectedGenres: some View {
        FlowLayout(spacing: 5) {
            ForEach(model.explore.filters.genres, id: \.self) { id in
                Button { model.toggleGenre(id) } label: {
                    HStack(spacing: 4) {
                        Text(model.genreName(id).uppercased())
                        Image(systemName: "xmark").font(.system(size: 7, weight: .bold))
                    }
                    .font(Theme.mono(8, .bold))
                    .tracking(1)
                    .foregroundStyle(Theme.popover)
                    .padding(.horizontal, 6).padding(.vertical, 4)
                    .background(Theme.ink)
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: Results

    private var results: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 6) {
                    Text(scopeLine)
                    if model.explore.loading {
                        Text("· LOADING").foregroundStyle(Theme.inkMuted.opacity(0.7))
                    }
                }
                .font(Theme.mono(9, .bold))
                .tracking(1.4)
                .foregroundStyle(Theme.inkMuted)
                .padding(.horizontal, 18)
                .padding(.top, 12)

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 152, maximum: 240), spacing: 14)],
                          alignment: .leading, spacing: 16) {
                    ForEach(model.catalogRows) { row in
                        Tile(row: row)
                            .onAppear {
                                // Paging is driven by the last tile appearing
                                // rather than a scroll offset: the grid reflows
                                // between one and three columns with the window,
                                // so there is no fixed height to measure against.
                                if row.id == model.catalogRows.last?.id { model.explore.loadMore() }
                            }
                    }
                }
                .padding(18)
            }
        }
    }

    private var scopeLine: String {
        if model.explore.episodes.isEmpty {
            return model.explore.loading ? "SEARCHING NTS" : "NOTHING MATCHES THESE FILTERS"
        }
        return "\(model.explore.episodes.count) OF \(model.explore.total) EPISODES"
    }
}

// MARK: - Genre drawer

/// The 20 primary genres, one open at a time. All 438 subgenres at once would
/// be a wall; the primaries alone are a browsable list at any window width.
private struct GenreDrawer: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(model.genres) { genre in
                    row(genre)
                    if model.openGenre == genre.id, !genre.subgenres.isEmpty {
                        FlowLayout(spacing: 5) {
                            ForEach(genre.subgenres) { sub in
                                chip(sub.name, id: sub.id)
                            }
                        }
                        .padding(.horizontal, 18)
                        .padding(.bottom, 10)
                    }
                }
            }
        }
        .frame(maxHeight: 220)
    }

    private func row(_ genre: NTSAPI.Genre) -> some View {
        HStack(spacing: 8) {
            Button {
                model.openGenre = model.openGenre == genre.id ? nil : genre.id
            } label: {
                HStack(spacing: 7) {
                    Image(systemName: model.openGenre == genre.id ? "chevron.down" : "chevron.right")
                        .font(.system(size: 8, weight: .bold))
                    Text(genre.name.uppercased())
                        .font(Theme.mono(9, .bold))
                        .tracking(1.2)
                }
                .foregroundStyle(Theme.ink)
            }
            .buttonStyle(.plain)

            // The primary is selectable in its own right — "all ambient / new
            // age" is a real thing to ask for, not just a folder.
            chip("ALL", id: genre.id)
            Spacer(minLength: 0)
            Text("\(genre.subgenres.count)")
                .font(Theme.mono(8))
                .foregroundStyle(Theme.inkMuted.opacity(0.7))
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 7)
    }

    private func chip(_ name: String, id: String) -> some View {
        let on = model.explore.filters.genres.contains(id)
        return Button { model.toggleGenre(id) } label: {
            Text(name.uppercased())
                .font(Theme.mono(8, .bold))
                .tracking(1)
                .foregroundStyle(on ? Theme.popover : Theme.inkMuted)
                .padding(.horizontal, 6).padding(.vertical, 4)
                .background(on ? Theme.ink : Theme.hairline(0.05))
        }
        .buttonStyle(.plain)
    }
}

/// A filter toggle: on is filled, off is outlined. Deliberately not a checkbox —
/// these read as a row of states, not a form.
private struct Toggle_: View {
    let title: String
    let on: Bool
    let action: () -> Void

    init(_ title: String, on: Bool, action: @escaping () -> Void) {
        self.title = title
        self.on = on
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(Theme.mono(9, .bold))
                .tracking(1.2)
                .foregroundStyle(on ? Theme.popover : Theme.inkMuted)
                .padding(.horizontal, 8).padding(.vertical, 5)
                .background(on ? Theme.ink : .clear)
                .overlay(Rectangle().stroke(Theme.hairline(on ? 0 : 0.12), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}
