import SwiftUI

/// Spotify-style top navigation bar. A solid strip above the interface (never
/// any full-bleed media) that seats the macOS traffic-light buttons on the
/// left and the account + settings controls on the right.
///
/// The strip itself is just the visual row; the interactive settings + account
/// controls live in `TopBarControls`, which `RadioWindowController` mounts as a
/// real title-bar accessory. They can't live in this strip: with
/// `fullSizeContentView`, AppKit's title-bar view sits above the content view
/// and swallows every click in the title-bar band for window dragging, so any
/// button placed here would render but never receive a click.
struct TopBar: View {
    var body: some View {
        // 32pt tall — its center (16pt) matches the traffic lights' vertical
        // center, and the title-bar accessory floats its controls over the top
        // right of this same strip.
        Color.clear
            .frame(height: 32)
            .frame(maxWidth: .infinity)
            .background(Theme.nowBar)
            .overlay(alignment: .bottom) { Rectangle().fill(Theme.hairline(0.08)).frame(height: 1) }
    }
}

/// The settings + account controls, mounted by `RadioWindowController` as a
/// trailing title-bar accessory so AppKit routes clicks to them (see `TopBar`).
struct TopBarControls: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var auth: NTSAuth

    var body: some View {
        HStack(spacing: 8) {
            settingsButton
            profileButton
        }
        .padding(.trailing, 14)
        .frame(height: 32)
    }

    /// Login-state indicator: signed-in shows the email's initial with a green
    /// dot; signed-out shows a generic person glyph. Either way it opens the
    /// settings sheet, where sign-in / sign-out lives.
    private var profileButton: some View {
        Button { model.settingsOpen = true } label: {
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
