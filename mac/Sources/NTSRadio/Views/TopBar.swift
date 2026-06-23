import SwiftUI

/// Spotify-style top navigation bar. A solid strip above the interface (never
/// any full-bleed media) that seats the macOS traffic-light buttons on the
/// left and the account + settings controls on the right. Doubles as the
/// window's drag region (the transparent title bar sits over it).
struct TopBar: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var auth: NTSAuth

    var body: some View {
        HStack(spacing: 8) {
            // Keep clear of the traffic lights (their cluster ends at x≈69); the
            // window draws them over our content (fullSizeContentView).
            Spacer(minLength: 76)

            settingsButton
            profileButton
        }
        .padding(.trailing, 14)
        // 32pt tall with vertically-centered controls puts their centers at 16pt
        // from the top — exactly the traffic lights' vertical center (measured).
        .frame(height: 32)
        .frame(maxWidth: .infinity)
        .background(Theme.nowBar)
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.hairline(0.08)).frame(height: 1) }
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
        Button { model.settingsOpen.toggle() } label: {
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
