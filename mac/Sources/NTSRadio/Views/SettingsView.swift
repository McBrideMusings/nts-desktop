import SwiftUI
import AppKit
import Sparkle

/// Which pane of Settings is showing. The toolbar in `SettingsWindowController`
/// owns the choice; these are the panes it swaps between.
enum SettingsPane: String, CaseIterable {
    case general, account

    var title: String {
        switch self {
        case .general: return "General"
        case .account: return "Account"
        }
    }

    var symbol: String {
        switch self {
        case .general: return "gearshape"
        case .account: return "person.crop.circle"
        }
    }
}

/// Which pane the Settings window is showing, as an object the window's one
/// hosting controller observes.
///
/// The window used to swap its whole `contentViewController` per pane. AppKit
/// sized the window to the incoming view the instant it was installed and then
/// the resize ran on top of that, so every tab click shrank the window, showed
/// the toolbar's overflow chevron in the gap, and grew back. One hosted view
/// that changes what it draws has no such moment — SwiftUI reports a new
/// preferred size and AppKit resizes the window once, smoothly, on its own.
@MainActor
final class SettingsSelection: ObservableObject {
    @Published var pane: SettingsPane = .general
}

/// The contents of the app's Settings window. The window, its title bar and its
/// toolbar are `SettingsWindowController`'s.
///
/// **Deliberately unstyled, and laid out the way Mac settings have always been
/// laid out:** a right-aligned label against its control, rules between groups,
/// explanatory sentences under the control they explain. That is what
/// SwiftUI's default `Form` (the `.columns` style) draws, and it is why the
/// grouped style is not used here — grouped is the iOS-derived list of rounded
/// boxes, and this is a Mac preferences window.
///
/// Every other view in this app paints its own black faceplate, because the
/// radio is meant to read as an object. Settings is not part of that object — it
/// is the Mac's. No `Theme` values appear below, and none should. What this
/// replaced was two hand-drawn light-grey sheets inside the radio window, with
/// painted traffic lights that did nothing, which stayed light when the rest of
/// the system went dark.
struct SettingsView: View {
    @ObservedObject var selection: SettingsSelection
    /// The live account, except under `admin snapshot`, which passes a seeded one
    /// so the shot does not depend on who is signed in on the machine rendering it.
    var auth: NTSAuth = AppModel.shared.auth

    var body: some View {
        switch selection.pane {
        case .general: GeneralSettings()
        case .account: AccountSettings(auth: auth)
        }
    }
}

private struct GeneralSettings: View {
    @ObservedObject private var model = AppModel.shared

    /// Bridges Sparkle's plain `Bool` property (not `@Published`) into a
    /// SwiftUI `Toggle` — read/write straight through to the updater on access.
    private var autoChecksForUpdates: Binding<Bool> {
        Binding(
            get: { AppDelegate.updaterController.updater.automaticallyChecksForUpdates },
            set: { AppDelegate.updaterController.updater.automaticallyChecksForUpdates = $0 }
        )
    }

    private var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "0.1.0"
        let build = info?["CFBundleVersion"] as? String
        return build.map { "\(short) (\($0))" } ?? short
    }

    var body: some View {
        Form {
            LabeledContent("Startup:") {
                VStack(alignment: .leading, spacing: 6) {
                    Toggle("Open NTS Radio at login", isOn: $model.startOnLogin)
                    Toggle("Show in Dock", isOn: $model.showInDock)
                    Text("With the Dock icon hidden, NTS Radio lives in the menu bar only.")
                        .settingsNote()
                }
            }

            Divider().padding(.vertical, 6)

            LabeledContent("Version:", value: version)
            LabeledContent("Updates:") {
                VStack(alignment: .leading, spacing: 6) {
                    Toggle("Automatically check for updates", isOn: autoChecksForUpdates)
                    Button("Check for Updates…") {
                        AppDelegate.updaterController.checkForUpdates(nil)
                    }
                }
            }
            LabeledContent("About:") {
                Button("About NTS Radio") {
                    NSApp.activate(ignoringOtherApps: true)
                    NSApp.orderFrontStandardAboutPanel(nil)
                }
            }
        }
        .settingsPane()
    }
}

/// Sign in, or see who is signed in and sign out. System `TextField` and
/// `SecureField` rather than hand-drawn boxes, so autofill, the password
/// manager, tabbing between fields and Return-to-submit all work — none of which
/// the drawn sheet had.
private struct AccountSettings: View {
    @ObservedObject var auth: NTSAuth
    @State private var email = ""
    @State private var password = ""

    var body: some View {
        Form {
            if auth.isAuthenticated {
                LabeledContent("Signed in:") {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(auth.email ?? "your NTS account")
                        Button("Sign Out") { auth.signOut() }
                        Text("Live tracklists come from your NTS Supporters account.")
                            .settingsNote()
                    }
                }
            } else {
                LabeledContent("Email:") {
                    TextField("", text: $email, prompt: Text("you@example.com"))
                        .textContentType(.username)
                        .disableAutocorrection(true)
                        .frame(width: 240)
                }
                LabeledContent("Password:") {
                    VStack(alignment: .leading, spacing: 8) {
                        SecureField("", text: $password)
                            .textContentType(.password)
                            .frame(width: 240)
                            .onSubmit(submit)
                        HStack(spacing: 8) {
                            Button("Sign In", action: submit)
                                .keyboardShortcut(.defaultAction)
                                .disabled(auth.isWorking || email.isEmpty || password.isEmpty)
                            if auth.isWorking { ProgressView().controlSize(.small) }
                        }
                        if let err = auth.errorMessage {
                            Text(err).settingsNote().foregroundStyle(.red)
                        }
                        Text("Signing in saves favourites across devices, and an NTS Supporters account is what live tracklists need.")
                            .settingsNote()
                    }
                }
            }
        }
        .settingsPane()
    }

    private func submit() {
        let e = email, p = password
        Task {
            await auth.signIn(email: e, password: p)
            if auth.isAuthenticated { password = "" }
        }
    }
}

private extension View {
    /// The small grey sentence that explains the control above it.
    func settingsNote() -> some View {
        font(.callout)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: 330, alignment: .leading)
    }

    /// Shared padding, so both panes sit on the same margins and the window can
    /// size itself to whichever is showing.
    func settingsPane() -> some View {
        formStyle(.columns)
            .padding(.horizontal, 22)
            .padding(.vertical, 20)
            .frame(width: 520, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
    }
}
