import SwiftUI
import AppKit

/// macOS-style settings sheet. Account sign-in is live (NTS Supporters, via
/// `NTSAuth`); Check-for-Updates is intentionally non-functional for v1 (see
/// GitHub issue #2); Start-on-Login flips locally (real SMAppService wiring
/// lands with .app packaging).
struct SettingsView: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var auth: NTSAuth
    @State private var email = ""
    @State private var password = ""

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
                HStack(spacing: 6) {
                    Text("ACCOUNT")
                        .font(Theme.mono(9.5, .regular)).tracking(1.5)
                        .foregroundStyle(Theme.sheetInk2)
                    Spacer()
                    Text("NTS SUPPORTERS")
                        .font(Theme.mono(9.5, .regular)).tracking(1.5)
                        .foregroundStyle(Theme.sheetInk3)
                }
                .padding(.bottom, 9)

                if auth.isAuthenticated {
                    signedIn
                } else {
                    signInForm
                }

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

                HStack {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Show in Dock")
                            .font(Theme.ui(14, .medium)).foregroundStyle(Theme.sheetInk)
                        Text("Also show NTS in the Dock and app switcher.")
                            .font(Theme.ui(12)).foregroundStyle(Theme.sheetInk2)
                    }
                    .padding(.trailing, 14)
                    Spacer()
                    TogglePill(on: model.showInDock) { model.showInDock.toggle() }
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

    // MARK: Account states

    private var signInForm: some View {
        VStack(alignment: .leading, spacing: 9) {
            TextField("Email", text: $email)
                .textFieldStyle(.plain)
                .textContentType(.username)
                .disableAutocorrection(true)
                .font(Theme.ui(13.5)).foregroundStyle(Theme.sheetInk)
                .padding(EdgeInsets(top: 8, leading: 11, bottom: 8, trailing: 11))
                .background(inputChrome)

            SecureField("Password", text: $password)
                .textFieldStyle(.plain)
                .textContentType(.password)
                .font(Theme.ui(13.5)).foregroundStyle(Theme.sheetInk)
                .padding(EdgeInsets(top: 8, leading: 11, bottom: 8, trailing: 11))
                .background(inputChrome)
                .onSubmit(submit)

            if let err = auth.errorMessage {
                Text(err).font(Theme.ui(11.5)).foregroundStyle(Theme.red)
            }

            Button(action: submit) {
                HStack(spacing: 7) {
                    if auth.isWorking { ProgressView().controlSize(.small) }
                    Text(auth.isWorking ? "Logging In…" : "Log In")
                        .font(Theme.ui(14, .semibold)).foregroundStyle(.white)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 9)
                .background(RoundedRectangle(cornerRadius: 8).fill(Theme.blue))
            }
            .buttonStyle(.plain)
            .disabled(auth.isWorking)
        }
    }

    private var signedIn: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack(spacing: 8) {
                Circle().fill(Theme.green).frame(width: 8, height: 8)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Signed in").font(Theme.ui(13, .semibold)).foregroundStyle(Theme.sheetInk)
                    if let em = auth.email {
                        Text(em).font(Theme.ui(11.5)).foregroundStyle(Theme.sheetInk2)
                    }
                }
                Spacer()
            }
            ghost("Log Out") { auth.signOut() }
        }
    }

    private var inputChrome: some View {
        RoundedRectangle(cornerRadius: 7).fill(.white)
            .overlay(RoundedRectangle(cornerRadius: 7).stroke(.black.opacity(0.16), lineWidth: 1))
    }

    private func submit() {
        let e = email, p = password
        Task {
            await auth.signIn(email: e, password: p)
            if auth.isAuthenticated { password = "" }
        }
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
