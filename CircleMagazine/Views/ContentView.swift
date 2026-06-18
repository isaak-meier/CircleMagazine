//
//  ContentView.swift
//  CircleMagazine
//
//  Created by Isaak Meier on 6/15/26.
//

import SwiftUI

struct ContentView: View {
    let db: DatabaseService

    var body: some View {
        GeometryReader { geo in
            VStack {
                Spacer()

                Image(systemName: "circle.bottomthird.split")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: geo.size.width / 4)

                Spacer().frame(height: 10)

                Text("Sometimes we think our problems are more important than our life")
                    .multilineTextAlignment(.center)
                    .italic()

                Spacer().frame(height: 10)

                Button("Print All Issues") {
                    Task {
                        await db.queryIssues()
                    }
                }
                .buttonStyle(.bordered)

                Button("Sign out") { Task { try? await db.signOut() } }
                    .buttonStyle(.bordered)

                Spacer()
            }
            .padding()
            .frame(maxWidth: .infinity)
        }
    }
}

#Preview {
    ContentView(db: DatabaseService())
}
