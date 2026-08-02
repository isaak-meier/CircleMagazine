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
    /// Called when a developer switch changes what an edition fetch would
    /// return, so the cached editions can be dropped. A closure, not the store —
    /// this screen has no business holding a service.
    var onEditionSourceChanged: () -> Void = {}

    @AppStorage(IssueViewModel.forceComposeKey) private var forceCompose = false
    @AppStorage(DatabaseService.showDraftKey) private var showDraft = false
    @State private var showGallery = false

    var body: some View {
        VStack(spacing: 0) {
            Masthead(title: "Account")
            VStack(spacing: Style.Space.xl) {
                switch account.authState {
                case .signedIn(let user):
                    profile(user)
                    #if DEBUG
                    developer
                    #endif
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

    #if DEBUG
    /// Debug-only phase switch. Flips the SCREEN, not the `is_live` column —
    /// a real flip needs an UPDATE policy on `issues` (there isn't one, so the
    /// write would silently touch zero rows). Takes effect on re-entering a circle.
    private var developer: some View {
        VStack(alignment: .leading, spacing: Style.Space.xs) {
            Text("DEVELOPER")
                .font(Style.eyebrow).tracking(1.6)
                .foregroundStyle(Style.meta)
            Toggle("Force compose phase", isOn: $forceCompose)
                .font(Style.body)
                .foregroundStyle(Style.ink)
            Text("Shows the circle chat instead of the edition.")
                .font(Style.stamp).foregroundStyle(Style.meta)

            Toggle("Read the open draft", isOn: $showDraft)
                .font(Style.body)
                .foregroundStyle(Style.ink)
                .padding(.top, Style.Space.sm)
            Text("Opens this week's unpublished edition, so a post is readable the moment you make it.")
                .font(Style.stamp).foregroundStyle(Style.meta)

            Button("Send the edition nudge") {
                Task { await EditionNotifications.fireTestNotification() }
            }
            .buttonStyle(.link)
            .padding(.top, Style.Space.sm)
            Text("Fires the real Sunday notification in 5 seconds — background the app to see the banner.")
                .font(Style.stamp).foregroundStyle(Style.meta)

            Button("Card gallery") { showGallery = true }
                .buttonStyle(.link)
                .padding(.top, Style.Space.sm)
            Text("Every card variation and every compose step, on device, with no posts needed.")
                .font(Style.stamp).foregroundStyle(Style.meta)
        }
        .sheet(isPresented: $showGallery) { CardGalleryView() }
        .frame(maxWidth: .infinity, alignment: .leading)
        // The cached editions were fetched under the old setting, so drop them
        // and let the next circle you open refetch under the new one.
        .onChange(of: showDraft) { _, _ in onEditionSourceChanged() }
    }
    #endif

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
    AccountView(account: AccountManager(db: DatabaseService()))
}
