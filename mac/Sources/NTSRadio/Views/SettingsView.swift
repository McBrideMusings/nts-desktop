import SwiftUI
import AppKit

/// The contents of the app's Settings window — mounted as the `Settings` scene in
/// `NTSRadioApp`, which is what makes it a real window: system title bar, ⌘,
/// to open, ⌘W to close, its own position remembered, and it stays put when the
/// radio window is dismissed.
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
                Toggle("Open NTS Radio at login", isOn: $model.startOnLogin)
                Toggle("Show in Dock", isOn: $model.showInDock)
            } footer: {
                Text("With the Dock icon hidden, NTS Radio lives in the menu bar only.")
            }

            Section {
                LabeledContent("Version", value: version)
                // Non-functional for v1 on purpose — see GitHub issue #2.
                Button("Check for Updates…") { }
                    .disabled(true)
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
