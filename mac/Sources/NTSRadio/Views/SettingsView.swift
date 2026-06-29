import SwiftUI
import AppKit

/// macOS-style settings popover, grouped GENERAL / DISPLAY sections (matching the
/// prototype). Sign-in lives in the standalone account popover (`LoginView`), not
/// here. Check-for-Updates is intentionally non-functional for v1 (GitHub #2);
/// Start-on-Login flips locally (real SMAppService wiring lands with packaging).
struct SettingsView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        ZStack(alignment: .top) {
            Color.black.opacity(0.32)
                .ignoresSafeArea()
                .onTapGesture { model.settingsOpen = false }
            sheet.padding(.top, 14)
        }
    }

    private var sheet: some View {
        VStack(spacing: 0) {
            header

            VStack(alignment: .leading, spacing: 16) {
                section("GENERAL") {
                    card {
                        settingRow("Start on Login",
                                   "Open NTS automatically when you sign in.",
                                   on: model.startOnLogin) { model.startOnLogin.toggle() }
                    }
                }

                section("DISPLAY") {
                    card {
                        settingRow("Hide Dial Dot When Small",
                                   "Drop the channel's center dot once the window shrinks.",
                                   on: model.hideDialDotWhenSmall) { model.hideDialDotWhenSmall.toggle() }
                    }
                }

                card {
                    linkRow("Check for Updates…") { /* non-functional v1 (GitHub #2) */ }
                    rowDivider
                    linkRow("About NTS Radio") { model.aboutOpen.toggle() }
                }

                if model.aboutOpen { aboutCard }

                Text("© 2026 NTS Radio Ltd.")
                    .font(Theme.ui(10.5)).foregroundStyle(Theme.sheetInk3)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 2)
            }
            .padding(EdgeInsets(top: 16, leading: 16, bottom: 16, trailing: 16))
        }
        .frame(width: 340)
        .background(Theme.sheet)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.5), radius: 35, y: 24)
    }

    // MARK: Header

    private var header: some View {
        ZStack {
            Text("Settings")
                .font(Theme.ui(13, .semibold))
                .foregroundStyle(Theme.sheetInk)
            HStack(spacing: 8) {
                Button { model.settingsOpen = false } label: {
                    Circle().fill(Theme.trafficRed).frame(width: 12, height: 12)
                }
                .buttonStyle(.plain)
                Circle().fill(.black.opacity(0.12)).frame(width: 12, height: 12)
                Circle().fill(.black.opacity(0.12)).frame(width: 12, height: 12)
                Spacer()
            }
            .padding(.leading, 14)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 13)
        .overlay(alignment: .bottom) { Rectangle().fill(.black.opacity(0.1)).frame(height: 0.5) }
    }

    // MARK: Building blocks

    private func section<Content: View>(_ title: String, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title)
                .font(Theme.mono(9.5, .regular)).tracking(1.5)
                .foregroundStyle(Theme.sheetInk3)
                .padding(.leading, 4)
            content()
        }
    }

    private func card<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(spacing: 0) { content() }
            .background(RoundedRectangle(cornerRadius: 10).fill(.white))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(.black.opacity(0.06), lineWidth: 0.5))
    }

    private var rowDivider: some View {
        Rectangle().fill(.black.opacity(0.08)).frame(height: 0.5).padding(.leading, 14)
    }

    private func settingRow(_ title: String, _ desc: String, on: Bool, _ toggle: @escaping () -> Void) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(Theme.ui(14, .medium)).foregroundStyle(Theme.sheetInk)
                Text(desc).font(Theme.ui(12)).foregroundStyle(Theme.sheetInk2)
            }
            Spacer()
            TogglePill(on: on, action: toggle)
        }
        .padding(EdgeInsets(top: 11, leading: 14, bottom: 11, trailing: 12))
    }

    private func linkRow(_ title: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Text(title).font(Theme.ui(14, .regular)).foregroundStyle(Theme.sheetInk)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.sheetInk3)
            }
            .contentShape(Rectangle())
            .padding(EdgeInsets(top: 12, leading: 14, bottom: 12, trailing: 14))
        }
        .buttonStyle(.plain)
    }

    private var aboutCard: some View {
        VStack(spacing: 3) {
            Text("NTS Radio").font(Theme.ui(13, .bold)).tracking(0.3).foregroundStyle(Theme.sheetInk)
            Text("Version 0.1 · Streaming worldwide since 2011")
                .font(Theme.ui(11.5)).foregroundStyle(Theme.sheetInk2)
            Text("Made with love in London & Manchester")
                .font(Theme.ui(11.5)).foregroundStyle(Theme.sheetInk2)
        }
        .frame(maxWidth: .infinity)
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 10).fill(.black.opacity(0.04)))
    }
}

struct TogglePill: View {
    let on: Bool
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            ZStack(alignment: on ? .trailing : .leading) {
                Capsule().fill(on ? Theme.green : .black.opacity(0.16))
                    .frame(width: 40, height: 24)
                Circle().fill(.white).frame(width: 20, height: 20)
                    .shadow(color: .black.opacity(0.3), radius: 1, y: 1)
                    .padding(2)
            }
            .frame(width: 40, height: 24)
        }
        .buttonStyle(.plain)
        .animation(.spring(response: 0.18, dampingFraction: 0.7), value: on)
    }
}
