//
//  ContentView.swift
//  CircleMagazine
//
//  Created by Isaak Meier on 6/15/26.
//

import SwiftUI

enum InsertState { case idle, ready, loading, success, failure }

struct ContentView: View {
    @State private var insertState: InsertState = .idle

    let db: DatabaseService

    var body: some View {
        GeometryReader { geo in
            VStack {
                Spacer()

                ZStack {
                    Image(systemName: "circle.bottomthird.split")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: geo.size.width / 4)
                        .opacity(insertState == .idle ? 1 : 0)
                        .scaleEffect(insertState == .idle ? 1 : 0.7)

                    if insertState != .idle {
                        Group {
                            switch insertState {
                            case .ready:
                                Button("Insert Test Issue") {
                                    Task {
                                        insertState = .loading
                                        let ok = await db.insertTestIssue()
                                        insertState = ok ? .success : .failure
                                    }
                                }
                                .buttonStyle(.borderedProminent)
                            case .loading:
                                ProgressView()
                                    .controlSize(.large)
                            case .success:
                                Image(systemName: "checkmark.circle.fill")
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                                    .foregroundStyle(.green)
                                    .frame(width: geo.size.width / 4)
                            case .failure:
                                Button {
                                    insertState = .ready
                                } label: {
                                    Image(systemName: "exclamationmark.triangle.fill")
                                        .resizable()
                                        .aspectRatio(contentMode: .fit)
                                        .foregroundStyle(.red)
                                        .frame(width: geo.size.width / 4)
                                }
                                .buttonStyle(.plain)
                            case .idle:
                                EmptyView()
                            }
                        }
                        .transition(.opacity.combined(with: .scale(0.8)))
                    }
                }
                .animation(.spring(duration: 0.35), value: insertState)
                .onTapGesture {
                    if insertState == .idle { insertState = .ready }
                }

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
