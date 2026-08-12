import SwiftUI
import AppKit

/// The contents of the app's Settings window. The window itself is
/// `SettingsWindowController`'s — a real one, with the system title bar, its own
/// remembered position, and a life independent of the radio window.
///
/// **Deliberately unstyled.** Every other view in this app paints its own black
/// faceplate, because the radio is meant to read as an object. Settings is not
/// part of that object — it is the Mac's, and it should look like every other
/// app's settings: a grouped `Form`, system controls, system fonts, system
/// colours, following light and dark mode on its own. No `Theme` values appear
/// below, and none should. What this replaced was a hand-drawn light-grey sheet
/// with painted traffic lights inside the radio window — a picture of a settings
/// window rather than one, which could not be moved, could not be opened without
/// the radio window, and stayed light when the rest of the system went dark.
struct SettingsView: View {
    @ObservedObject private var model = AppModel.shared

    private var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "0.1.0"
        let build = info?["CFBundleVersion"] as? String
        return build.map { "\(short) (\($0))" } ?? short
    }

    var body: some View {
        Form {
            Section {
                // This one only remembers itself — nothing registers a login
                // item yet, so flipping it does not make the app launch at
                // login. Tracked; it needs `SMAppService`.
                Toggle("Open NTS Radio at login", isOn: $model.startOnLogin)
                Toggle("Show in Dock", isOn: $model.showInDock)
            } footer: {
                Text("With the Dock icon hidden, NTS Radio lives in the menu bar only.")
            }

            Section {
                LabeledContent("Version", value: version)
                // No Check for Updates row: auto-update was closed as out of
                // scope (GitHub #2 — a private repo can serve neither an appcast
                // nor the .dmg), so a permanently greyed-out button here would be
                // promising something that is never coming.
                Button("About NTS Radio") {
                    NSApp.activate(ignoringOtherApps: true)
                    NSApp.orderFrontStandardAboutPanel(nil)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 420)
        .fixedSize(horizontal: false, vertical: true)
    }
}
