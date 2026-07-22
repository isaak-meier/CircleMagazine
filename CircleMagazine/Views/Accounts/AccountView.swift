//
//  AccountView.swift
//  CircleMagazine
//
//  Basic account screen: shows the username and signs out when signed in,
//  otherwise offers a sign-in. Same editorial palette as the rest of the app.
//

import SwiftUI

struct AccountView: View {
    let account: AccountManager
    let issueLoader: IssueLoader
    @AppStorage(IssueLoader.showDraftKey) private var showDraftIssue = false

    var body: some View {
        VStack(spacing: 0) {
            Masthead(title: "Account")
            VStack(spacing: Style.Space.xl) {
                switch account.authState {
                case .signedIn(let user):
                    profile(user)
                    editionToggle
                    Spacer()
                    signOut
                case .loading, .signedOut:
                    Spacer()
                    signIn
                }
            }
            .frame(maxHeight: .infinity)
            .padding(.horizontal, Style.Space.lg)
            .padding(.top, Style.Space.xl)
            .padding(.bottom, Style.Space.xl)
        }
        .background(Style.chrome)
    }

    private func profile(_ user: User) -> some View {
        VStack(alignment: .leading, spacing: Style.Space.xs) {
            Text("USERNAME")
                .font(Style.eyebrow).tracking(1.6)
                .foregroundStyle(Style.meta)
            Text(user.username)
                .font(Style.cardTitle).foregroundStyle(Style.ink)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Flips the feed between the live edition and the newest draft.
    private var editionToggle: some View {
        VStack(alignment: .leading, spacing: Style.Space.xs) {
            Text("EDITION")
                .font(Style.eyebrow).tracking(1.6)
                .foregroundStyle(Style.meta)
            Toggle("Preview the upcoming edition", isOn: $showDraftIssue)
                .font(Style.body).foregroundStyle(Style.ink)
                .tint(Style.ink)
                .onChange(of: showDraftIssue) {
                    Task { await issueLoader.refresh() }
                }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var signOut: some View {
        Button("Sign out") { Task { try? await account.signOut() } }
            .buttonStyle(.primary)
    }

    // ponytail: the App routes signedOut → WelcomeView, so RootTabView (and thus
    // this view) only renders when signed in. This branch is a type-safety net
    // that shouldn't appear; the button is inert until a real entry point needs it.
    private var signIn: some View {
        Button("Sign in") { }.buttonStyle(.primary)
    }
}

#Preview {
    AccountView(account: AccountManager(db: DatabaseService()),
                issueLoader: .preview(.loading))
}
