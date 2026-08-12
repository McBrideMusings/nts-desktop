import SwiftUI
import AppKit

/// The settings and account buttons at the right end of the title bar, and
/// nothing else. The band they sit in — its black, its hairline, and the NTS
/// mark centred in it — belongs to `PopoverView`.
///
/// The catalog button used to live here too. It is a segment of the pane switch
/// in the now-playing bar now (`PaneSwitch` in `NowPlayingBar.swift`), beside the
/// tracklist and the faceplate, because a control that picks between three panes
/// has to sit with the other two — split across two ends of the window, the pair
/// of them could show two panes lit at once.
///
/// **This view cannot centre anything, and the name says so on purpose.**
/// `RadioWindowController` mounts it as a `.top` title-bar accessory, and AppKit
/// insets that accessory past the traffic lights: its box starts about 78pt in
/// from the window's left edge and stops ~10pt short on the right, so the middle
/// of this view is roughly 33pt right of the middle of the window. Laying the
/// NTS mark out here is what put it visibly off-centre, and no amount of
/// balancing spacers inside this box could fix it — the box is the wrong box.
/// Anything that must sit on the window's centre line goes in `PopoverView`'s
/// band, which is drawn in the content view and spans the true window width.
///
/// What this view is *for* is clicks: the title bar swallows mouse events in the
/// content view's top band (it reserves them for window dragging), so a button
/// drawn down there renders but never responds. Mounting the controls as an
/// accessory is the only way they work. It also reports the band's height as the
/// content view's top safe-area inset, so the rail and dial start exactly below
/// it — the arrangement before this one drew the strip in the content stack and
/// pulled the stack up by a hardcoded 32pt, and whenever AppKit's real band was
/// taller the whole interface slid up into the traffic lights.
struct TitleBarControls: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var auth: NTSAuth

    var body: some View {
        HStack(spacing: 8) {
            Spacer(minLength: 0)
            settingsButton
            profileButton
        }
        .padding(.trailing, 14)
        .frame(maxWidth: .infinity)
        .frame(height: Theme.titleBarHeight)
        // No background and no hairline: both would stop 78pt short of the left
        // edge, for the same reason the mark could not be centred here.
        // `PopoverView` paints them across the full width and this view is left
        // transparent so they show through.
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
        .buttonStyle(.hit)
        .help(auth.isAuthenticated ? "Account — \(auth.email ?? "signed in")" : "Sign in")
    }

    /// Settings is a separate window, so this button never lights up — it has no
    /// open/closed state to report about this window, and a lit gear beside a
    /// window that may be behind another app would be claiming one.
    private var settingsButton: some View {
        Button { SettingsWindowController.shared.show() } label: {
            Image(systemName: "gearshape")
                .font(.system(size: 15, weight: .regular))
                .foregroundStyle(Theme.ink)
                .frame(width: 26, height: 26)
                .background(RoundedRectangle(cornerRadius: 7).fill(Theme.hairline(0.10)))
        }
        .buttonStyle(.hit)
        .help("Settings")
    }
}
