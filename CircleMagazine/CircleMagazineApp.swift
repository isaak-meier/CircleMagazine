//
//  CircleMagazineApp.swift
//  CircleMagazine
//
//  Created by Isaak Meier on 6/15/26.
//

import SwiftUI

@main
struct CircleMagazineApp: App {
    @State private var account: AccountManager
    @State private var loader: IssueLoader

    init() {
        // Build db once, then hand the same instance to both owners.
        // (@State initializers can't see sibling properties, so do it here
        // and seed each wrapper via State(initialValue:).)
        let db = DatabaseService()
        _account = State(initialValue: AccountManager(db: db))
        _loader = State(initialValue: IssueLoader(db: db))
    }

    var body: some Scene {
        WindowGroup {
            switch account.authState {
            case .loading:   ProgressView()
            case .signedOut: WelcomeView(account: account)
            case .signedIn:  MagazineView(loader: loader)
            }
        }
    }
}
