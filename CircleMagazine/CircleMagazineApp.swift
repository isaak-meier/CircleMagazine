//
//  CircleMagazineApp.swift
//  CircleMagazine
//
//  Created by Isaak Meier on 6/15/26.
//

import SwiftUI

@main
struct CircleMagazineApp: App {
    @State private var db = DatabaseService()

    var body: some Scene {
        WindowGroup {
            switch db.authState {
            case .loading:   ProgressView()
            case .signedOut: WelcomeView(db: db)
            case .signedIn:  ContentView(db: db)
            }
        }
    }
}
