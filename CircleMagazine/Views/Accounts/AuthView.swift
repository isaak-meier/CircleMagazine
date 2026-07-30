//
//  AuthView.swift
//  CircleMagazine
//

import SwiftUI

struct AuthView: View {
    @Bindable var account: AccountManager

    /// Supabase's emailed OTP length.
    private static let codeLength = 6

    var body: some View {
        VStack(spacing: 0) {
            Masthead(title: title)
            VStack(alignment: .leading, spacing: Style.Space.lg) {
                content
                if let errorText = account.errorText {
                    ErrorBanner(message: errorText)
                }
            }
            .padding(.horizontal, Style.Space.lg)
            .padding(.top, Style.Space.xl)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Style.chrome)
    }

    @ViewBuilder
    private var content: some View {
        switch account.step {
        case .email:
            prompt("Enter your email")
            TextField("you@example.com", text: $account.email)
                .keyboardType(.emailAddress)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .editorialField()
            Button("Send code") { Task { await account.sendCode() } }
                .buttonStyle(.primary(loading: account.isLoading)).disabled(account.isLoading)

        case .code:
            prompt("Enter the code sent to \(account.email)")
            // Same boxes as joining a circle by invite code — both are a
            // six-character code, so they're the same control.
            CodeField(length: Self.codeLength, input: $account.code, kind: .digits)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button("Verify") { Task { await account.verify() } }
                .buttonStyle(.primary(loading: account.isLoading))
                .disabled(account.isLoading || account.code.count < Self.codeLength)
            Button("Resend") { Task { await account.resendCode() } }
                .buttonStyle(.link).disabled(account.isLoading)

        case .username:
            prompt("Pick a username")
            TextField("username", text: $account.username)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .editorialField()
            Button("Create account") { Task { await account.createAccount() } }
                .buttonStyle(.primary(loading: account.isLoading)).disabled(account.isLoading)
        }
    }

    // Only the username step is unambiguously a new account; email/code could be either.
    private var title: String {
        if case .username = account.step { return "Sign Up" }
        return "Sign In"
    }

    private func prompt(_ text: String) -> some View {
        Text(text).font(Style.cardTitle).foregroundStyle(Style.ink)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

#Preview {
    AuthView(account: AccountManager(db: DatabaseService()))
}
