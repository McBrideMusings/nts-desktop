import SwiftUI
import AppKit
import Charts

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
    @ObservedObject private var prefs = AppModel.shared.preferences

    private var isPerceptual: Bool { prefs.curve.kind == .perceptual }

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
                    Toggle("Open NTS Radio at login", isOn: $prefs.startOnLogin)
                    Toggle("Show in Dock", isOn: $prefs.showInDock)
                    Text("With the Dock icon hidden, NTS Radio lives in the menu bar only.")
                        .settingsNote()
                }
            }

            Divider().padding(.vertical, 6)

            LabeledContent("Volume:") {
                VStack(alignment: .leading, spacing: 8) {
                    Picker("Volume", selection: $prefs.curve.kind) {
                        Text("Linear").tag(VolumeCurve.Kind.linear)
                        Text("Perceptual").tag(VolumeCurve.Kind.perceptual)
                    }
                    .pickerStyle(.radioGroup)
                    .labelsHidden()

                    HStack(spacing: 8) {
                        Text("Gentle").font(.callout).foregroundStyle(.secondary)
                        Slider(value: $prefs.curve.exponent, in: VolumeCurve.exponentRange, step: 0.25)
                            .frame(width: 160)
                            .accessibilityLabel("Steepness")
                        Text("Steep").font(.callout).foregroundStyle(.secondary)
                    }
                    .disabled(!isPerceptual)

                    VolumeCurveChart(curve: prefs.curve, slider: prefs.slider)
                        .frame(width: 330, height: 130)
                        .opacity(isPerceptual ? 1 : 0.45)

                    Text("Perceptual gives the quiet end of the slider more room, so small adjustments at low volume are easier.")
                        .settingsNote()
                }
            }

            Divider().padding(.vertical, 6)

            Picker("Tracklist rows lead with:", selection: $prefs.trackLead) {
                ForEach(TrackLead.allCases, id: \.self) { Text($0.label).tag($0) }
            }
            .pickerStyle(.radioGroup)

            Divider().padding(.vertical, 6)

            LabeledContent("Version:", value: version)
            LabeledContent("Updates:") {
                VStack(alignment: .leading, spacing: 6) {
                    Toggle("Automatically check for updates", isOn: $prefs.autoChecksForUpdates)
                    Button("Check for Updates…") {
                        prefs.checkForUpdates()
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

/// Loudness against knob position: the linear curve as a faint reference, the
/// chosen curve as the main line, a dot at where the knob is now. The y axis is
/// dB, because that is how loudness is heard; −∞ at position 0 sits on the −60 floor.
private struct VolumeCurveChart: View {
    let curve: VolumeCurve
    let slider: Double

    private static let linear = VolumeCurve(kind: .linear, exponent: 1)
    private static let positions = Array(stride(from: 0.0, through: 100.0, by: 1.0))

    var body: some View {
        Chart {
            ForEach(Self.positions, id: \.self) { x in
                LineMark(x: .value("Position", x),
                         y: .value("dB", Self.linear.decibels(forSlider: x)),
                         series: .value("Curve", "linear"))
                    .foregroundStyle(.secondary.opacity(0.4))
            }
            ForEach(Self.positions, id: \.self) { x in
                LineMark(x: .value("Position", x),
                         y: .value("dB", curve.decibels(forSlider: x)),
                         series: .value("Curve", "current"))
                    .foregroundStyle(Color.accentColor)
                    .lineStyle(StrokeStyle(lineWidth: 2))
            }
            PointMark(x: .value("Position", slider),
                      y: .value("dB", curve.decibels(forSlider: slider)))
                .foregroundStyle(Color.accentColor)
                .symbolSize(60)
        }
        .chartXScale(domain: 0...100)
        .chartYScale(domain: -60...0)
        .chartXAxis {
            AxisMarks(values: [0, 25, 50, 75, 100])
        }
        .chartYAxis {
            AxisMarks(values: [-60, -40, -20, 0]) { value in
                AxisGridLine()
                AxisValueLabel {
                    if let db = value.as(Double.self) { Text("\(Int(db)) dB") }
                }
            }
        }
        .accessibilityLabel("Loudness by slider position")
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
        WholePoints {
            formStyle(.columns)
                .padding(.horizontal, 22)
                .padding(.vertical, 20)
                .frame(width: 520, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// Reports its content's size rounded up to whole points.
///
/// The window takes its size from the pane, and a pane whose height came out
/// fractional (595.5) never settled: AppKit snapped the window to 596, the
/// hosting view read the spare half point as safe area and grew by it, and
/// every pass repeated that until AppKit raised for running out of passes and
/// the app died. A whole-point height is one the window can match exactly.
private struct WholePoints: Layout {
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let size = subviews.first?.sizeThatFits(proposal) ?? .zero
        return CGSize(width: size.width.rounded(.up), height: size.height.rounded(.up))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        subviews.first?.place(at: bounds.origin, proposal: ProposedViewSize(bounds.size))
    }
}
