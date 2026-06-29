import SwiftUI
import AppKit

/// Standalone account / sign-in popover (the account button in the title bar),
/// split out of Settings to match the prototype. Sign-in is live via `NTSAuth`
/// (NTS Supporters); when already signed in it shows the account + a log-out.
struct LoginView: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var auth: NTSAuth
    @State private var email = ""
    @State private var password = ""

    var body: some View {
        ZStack(alignment: .top) {
            Color.black.opacity(0.32)
                .ignoresSafeArea()
                .onTapGesture { model.loginOpen = false }
            sheet.padding(.top, 14)
        }
    }

    private var sheet: some View {
        VStack(spacing: 0) {
            header

            VStack(alignment: .leading, spacing: 12) {
                if auth.isAuthenticated { signedIn } else { signInForm }
            }
            .padding(EdgeInsets(top: 16, leading: 18, bottom: 18, trailing: 18))
        }
        .frame(width: 300)
        .background(Theme.sheet)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.5), radius: 35, y: 24)
    }

    private var header: some View {
        ZStack {
            Text("Account")
                .font(Theme.ui(13, .semibold))
                .foregroundStyle(Theme.sheetInk)
            HStack {
                Button { model.loginOpen = false } label: {
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
    }

    private var signInForm: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Sign in to NTS").font(Theme.ui(16, .bold)).foregroundStyle(Theme.sheetInk)
                Text("Save favourites and pick up where you left off.")
                    .font(Theme.ui(12)).foregroundStyle(Theme.sheetInk2)
            }
            .padding(.bottom, 2)

            TextField("Email", text: $email)
                .textFieldStyle(.plain).textContentType(.username).disableAutocorrection(true)
                .font(Theme.ui(13.5)).foregroundStyle(Theme.sheetInk)
                .padding(EdgeInsets(top: 8, leading: 11, bottom: 8, trailing: 11))
                .background(inputChrome)

            SecureField("Password", text: $password)
                .textFieldStyle(.plain).textContentType(.password)
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
        VStack(alignment: .leading, spacing: 12) {
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
            Button { auth.signOut() } label: {
                Text("Log Out")
                    .font(Theme.ui(13, .medium)).foregroundStyle(Theme.sheetInk)
                    .frame(maxWidth: .infinity).padding(.vertical, 8)
                    .background(RoundedRectangle(cornerRadius: 8).fill(.white)
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(.black.opacity(0.18), lineWidth: 0.5)))
            }
            .buttonStyle(.plain)
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
            if auth.isAuthenticated { password = ""; model.loginOpen = false }
        }
    }
}
