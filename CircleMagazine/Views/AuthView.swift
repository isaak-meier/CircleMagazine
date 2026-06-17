//
//  AuthView.swift
//  CircleMagazine
//

import SwiftUI

enum AuthStep { case email, code, username }

struct AuthView: View {
    let db: DatabaseService

    @State private var step: AuthStep = .email
    @State private var email = ""
    @State private var code = ""
    @State private var username = ""
    @State private var isLoading = false
    @State private var errorText: String?

    var body: some View {
        VStack(spacing: 16) {
            switch step {
            case .email:
                Text("Enter your email").font(.headline)
                TextField("you@example.com", text: $email)
                    .textFieldStyle(.roundedBorder)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                button("Send code") { try await db.sendOTP(email: email); step = .code }

            case .code:
                Text("Enter the code sent to \(email)").font(.headline)
                TextField("123456", text: $code)
                    .textFieldStyle(.roundedBorder)
                    .keyboardType(.numberPad)
                button("Verify") {
                    try await db.verifyOTP(email: email, code: code)
                    if try await db.hasProfile() { db.authState = .signedIn } else { step = .username }
                }
                Button("Resend") { run { try await db.sendOTP(email: email) } }
                    .buttonStyle(.plain)
                    .disabled(isLoading)

            case .username:
                Text("Pick a username").font(.headline)
                TextField("username", text: $username)
                    .textFieldStyle(.roundedBorder)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                button("Create account") { try await db.createProfile(username: username); db.authState = .signedIn }
            }

            if isLoading { ProgressView() }
            if let errorText { Text(errorText).foregroundStyle(.red).font(.footnote) }
        }
        .padding()
    }

    private func button(_ title: String, action: @escaping () async throws -> Void) -> some View {
        Button(title) { run(action) }
            .buttonStyle(.borderedProminent)
            .disabled(isLoading)
    }

    private func run(_ action: @escaping () async throws -> Void) {
        Task {
            isLoading = true
            errorText = nil
            do { try await action() } catch { errorText = error.localizedDescription }
            isLoading = false
        }
    }
}
