import SwiftUI

/// The settings + account controls that sit at the right end of the title-bar
/// strip. The strip itself, and the NTS mark centred in it, are drawn by
/// `PopoverView`.
///
/// This is *not* part of the content view. `RadioWindowController` mounts it as
/// a full-width `.top` title-bar accessory, which makes AppKit own the strip:
/// it routes clicks to the buttons (a view drawn into the content view under
/// the title bar renders but never gets a click — the title-bar view swallows
/// them for window dragging), and it reports the strip's height as the content
/// view's top safe-area inset, so the rail and dial start exactly below it.
/// The old arrangement drew this strip in the content stack and pulled the
/// stack up under the title bar by a hardcoded 32pt; whenever AppKit's real
/// band was taller, the whole interface slid up and the channel cards ran into
/// the traffic lights.
struct TopBar: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var auth: NTSAuth

    /// The strip's height, and therefore the title-bar band's. 32pt keeps the
    /// traffic lights vertically centred in it.
    static let height: CGFloat = 32

    var body: some View {
        HStack(spacing: 8) {
            Spacer(minLength: 0)
            catalogButton
            settingsButton
            profileButton
        }
        .padding(.trailing, 14)
        .frame(maxWidth: .infinity)
        .frame(height: Self.height)
        // Deliberately no background: AppKit insets this accessory past the
        // traffic lights, so anything centred inside it lands right of the
        // window's real centre. `PopoverView` paints the strip full-width in the
        // content view and centres the NTS mark there instead; this view is left
        // transparent so that strip shows through, and carries only the controls
        // — which have to live up here because the title bar eats clicks in the
        // content view's top band.
        // No hairline here: AppKit insets this view past the traffic lights, so
        // a rule drawn at its bottom would stop 78pt short of the left edge.
        // PopoverView draws it along the top of the content instead.
    }

    /// Login-state indicator: signed-in shows the email's initial with a green
    /// dot; signed-out shows a generic person glyph. Opens the standalone account
    /// popover, where sign-in / sign-out lives.
    private var profileButton: some View {
        Button { model.loginOpen = true } label: {
            ZStack(alignment: .bottomTrailing) {
                ZStack {
                    Circle()
                        .fill(auth.isAuthenticated ? Theme.green.opacity(0.22) : Theme.hairline(0.12))
                        .overlay(Circle().stroke(Theme.hairline(0.16), lineWidth: 1))
                    if auth.isAuthenticated, let initial = auth.email?.first {
                        Text(String(initial).uppercased())
                            .font(Theme.display(12, .heavy))
                            .foregroundStyle(Theme.ink)
                    } else {
                        Image(systemName: "person.crop.circle")
                            .font(.system(size: 16))
                            .foregroundStyle(Theme.inkMuted)
                    }
                }
                .frame(width: 26, height: 26)

                if auth.isAuthenticated {
                    Circle()
                        .fill(Theme.green)
                        .frame(width: 8, height: 8)
                        .overlay(Circle().stroke(Theme.nowBar, lineWidth: 1.5))
                }
            }
        }
        .buttonStyle(.plain)
        .help(auth.isAuthenticated ? "Account — \(auth.email ?? "signed in")" : "Sign in")
    }

    /// The one control that opens and closes the catalog. It stays in the same
    /// place either way and lights up while the catalog is up, so there is never a
    /// second, differently-placed way back out.
    private var catalogButton: some View {
        Button { model.toggleCatalog() } label: {
            Image(systemName: "square.grid.2x2.fill")
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(model.catalogOpen ? Theme.popover : Theme.ink)
                .frame(width: 26, height: 26)
                .background(RoundedRectangle(cornerRadius: 7)
                    .fill(model.catalogOpen ? Theme.ink : Theme.hairline(0.10)))
        }
        .buttonStyle(.plain)
        .help(model.catalogOpen ? "Hide the catalog" : "Schedule, saved and mixtapes")
    }

    private var settingsButton: some View {
        Button { model.settingsOpen = true } label: {
            Image(systemName: "gearshape")
                .font(.system(size: 15, weight: .regular))
                .foregroundStyle(Theme.ink)
                .frame(width: 26, height: 26)
                .background(RoundedRectangle(cornerRadius: 7).fill(Theme.hairline(0.10)))
        }
        .buttonStyle(.plain)
        .help("Settings")
    }
}
