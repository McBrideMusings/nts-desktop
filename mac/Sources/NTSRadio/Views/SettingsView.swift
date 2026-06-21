import SwiftUI
import AppKit

/// macOS-style settings sheet. Account + Check-for-Updates are intentionally
/// non-functional for v1 (tracked in tmp/claude/followups.md); Start-on-Login
/// flips locally (real SMAppService wiring lands with .app packaging).
struct SettingsView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        ZStack(alignment: .top) {
            Color.black.opacity(0.32)
                .ignoresSafeArea()
                .onTapGesture { model.settingsOpen = false }

            sheet
                .padding(.top, 14)
        }
    }

    private var sheet: some View {
        VStack(spacing: 0) {
            ZStack {
                Text("Settings")
                    .font(Theme.ui(13, .semibold))
                    .foregroundStyle(Theme.sheetInk)
                HStack {
                    Button { model.settingsOpen = false } label: {
                        Circle().fill(Theme.trafficRed).frame(width: 12, height: 12)
                    }
                    .buttonStyle(.plain)
                    Spacer()
                }
                .padding(.leading, 14)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 13)
            .overlay(alignment: .bottom) { Rectangle().fill(.black.opacity(0.1)).frame(height: 0.5) }

            VStack(alignment: .leading, spacing: 0) {
                Text("ACCOUNT")
                    .font(Theme.mono(9.5, .regular)).tracking(1.5)
                    .foregroundStyle(Theme.sheetInk2)
                    .padding(.bottom, 9)

                field("Email")
                Spacer().frame(height: 9)
                field("Password")
                Spacer().frame(height: 13)

                Button { /* non-functional v1 */ } label: {
                    Text("Log In")
                        .font(Theme.ui(14, .semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 9)
                        .background(RoundedRectangle(cornerRadius: 8).fill(Theme.blue))
                }
                .buttonStyle(.plain)

                divider

                HStack {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Start on Login")
                            .font(Theme.ui(14, .medium)).foregroundStyle(Theme.sheetInk)
                        Text("Open NTS automatically when you sign in.")
                            .font(Theme.ui(12)).foregroundStyle(Theme.sheetInk2)
                    }
                    .padding(.trailing, 14)
                    Spacer()
                    TogglePill(on: model.startOnLogin) { model.startOnLogin.toggle() }
                }

                divider

                HStack(spacing: 10) {
                    ghost("About") { model.aboutOpen.toggle() }
                    ghost("Check for Updates…") { /* non-functional v1 */ }
                }

                if model.aboutOpen {
                    VStack(spacing: 3) {
                        Text("NTS Radio").font(Theme.ui(13, .bold)).tracking(0.3)
                            .foregroundStyle(Theme.sheetInk)
                        Text("Version 0.1 · Streaming worldwide since 2011")
                            .font(Theme.ui(11.5)).foregroundStyle(Theme.sheetInk2)
                        Text("Made with love in London & Manchester")
                            .font(Theme.ui(11.5)).foregroundStyle(Theme.sheetInk2)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(12)
                    .background(RoundedRectangle(cornerRadius: 9).fill(.black.opacity(0.04)))
                    .padding(.top, 13)
                }

                Button { NSApp.terminate(nil) } label: {
                    Text("Quit NTS Radio")
                        .font(Theme.ui(13, .medium))
                        .foregroundStyle(Theme.red)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 7)
                        .background(RoundedRectangle(cornerRadius: 7).fill(.white.opacity(0.9))
                            .overlay(RoundedRectangle(cornerRadius: 7).stroke(.black.opacity(0.22), lineWidth: 0.5)))
                }
                .buttonStyle(.plain)
                .padding(.top, 14)

                Text("© 2026 NTS Radio Ltd. All rights reserved.")
                    .font(Theme.ui(10.5)).foregroundStyle(Theme.sheetInk3)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 16)
            }
            .padding(EdgeInsets(top: 18, leading: 20, bottom: 16, trailing: 20))
        }
        .frame(width: 360)
        .background(Theme.sheet)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.5), radius: 35, y: 24)
    }

    private var divider: some View {
        Rectangle().fill(.black.opacity(0.1)).frame(height: 1).padding(.vertical, 18)
    }

    // Display-only field (Account login is non-functional in v1 — followups.md).
    private func field(_ placeholder: String) -> some View {
        Text(placeholder)
            .font(Theme.ui(13.5))
            .foregroundStyle(Theme.sheetInk2)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(EdgeInsets(top: 8, leading: 11, bottom: 8, trailing: 11))
            .background(RoundedRectangle(cornerRadius: 7).fill(.white)
                .overlay(RoundedRectangle(cornerRadius: 7).stroke(.black.opacity(0.16), lineWidth: 1)))
    }

    private func ghost(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(Theme.ui(13, .medium))
                .foregroundStyle(Theme.sheetInk)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 7)
                .background(RoundedRectangle(cornerRadius: 7).fill(.white.opacity(0.9))
                    .overlay(RoundedRectangle(cornerRadius: 7).stroke(.black.opacity(0.22), lineWidth: 0.5)))
        }
        .buttonStyle(.plain)
    }
}

private struct TogglePill: View {
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
