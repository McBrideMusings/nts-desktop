import SwiftUI
import AppKit

/// The settings button at the right end of the title bar, and nothing else. The
/// band it sits in — its black, its hairline, and the NTS mark centred in it —
/// belongs to `PopoverView`.
///
/// Two buttons left this strip. The catalog is a segment of the pane switch in
/// the now-playing bar now (`PaneSwitch` in `NowPlayingBar.swift`), because a
/// control that picks between panes has to sit with the other one that does —
/// split across two ends of the window, the pair could show two panes lit at
/// once. The account button is gone entirely: signing in is a tab of the Settings
/// window, so the gear is the way to it, and the green dot on the gear is the
/// signed-in state that button used to carry.
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
    @EnvironmentObject var auth: NTSAuth

    var body: some View {
        HStack(spacing: 8) {
            Spacer(minLength: 0)
            settingsButton
        }
        .padding(.trailing, 14)
        .frame(maxWidth: .infinity)
        .frame(height: Theme.titleBarHeight)
        // No background and no hairline: both would stop 78pt short of the left
        // edge, for the same reason the mark could not be centred here.
        // `PopoverView` paints them across the full width and this view is left
        // transparent so they show through.
    }

    /// Settings never lights up — it is a separate window, and a lit gear beside
    /// a window that may be behind another app would be claiming one. The green
    /// dot is not that: it says the account is signed in, which is what the
    /// account button used to say and what decides whether live tracklists
    /// arrive at all.
    private var settingsButton: some View {
        Button { SettingsWindowController.shared.show() } label: {
            ZStack(alignment: .bottomTrailing) {
                Image(systemName: "gearshape")
                    .font(.system(size: 15, weight: .regular))
                    .foregroundStyle(Theme.ink)
                    .frame(width: 26, height: 26)
                    .background(RoundedRectangle(cornerRadius: 7).fill(Theme.hairline(0.10)))

                if auth.isAuthenticated {
                    Circle()
                        .fill(Theme.green)
                        .frame(width: 8, height: 8)
                        .overlay(Circle().stroke(Theme.nowBar, lineWidth: 1.5))
                }
            }
        }
        .buttonStyle(.hit)
        .help(auth.isAuthenticated
              ? "Settings — signed in as \(auth.email ?? "your NTS account")"
              : "Settings — not signed in")
    }
}
