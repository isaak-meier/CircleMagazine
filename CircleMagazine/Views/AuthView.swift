//
//  AuthView.swift
//  CircleMagazine
//

import SwiftUI

struct AuthView: View {
    @Bindable var account: AccountManager

    var body: some View {
        VStack(spacing: 16) {
            switch account.step {
            case .email:
                Text("Enter your email").font(.headline)
                TextField("you@example.com", text: $account.email)
                    .textFieldStyle(.roundedBorder)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                Button("Send code") { Task { await account.sendCode() } }
                    .buttonStyle(.borderedProminent)
                    .disabled(account.isLoading)

            case .code:
                Text("Enter the code sent to \(account.email)").font(.headline)
                TextField("123456", text: $account.code)
                    .textFieldStyle(.roundedBorder)
                    .keyboardType(.numberPad)
                Button("Verify") { Task { await account.verify() } }
                    .buttonStyle(.borderedProminent)
                    .disabled(account.isLoading)
                Button("Resend") { Task { await account.resendCode() } }
                    .buttonStyle(.plain)
                    .disabled(account.isLoading)

            case .username:
                Text("Pick a username").font(.headline)
                TextField("username", text: $account.username)
                    .textFieldStyle(.roundedBorder)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                Button("Create account") { Task { await account.createAccount() } }
                    .buttonStyle(.borderedProminent)
                    .disabled(account.isLoading)
            }

            if account.isLoading { ProgressView() }
            if let errorText = account.errorText {
                Text(errorText).foregroundStyle(.red).font(.footnote)
            }
        }
        .padding()
    }
}
