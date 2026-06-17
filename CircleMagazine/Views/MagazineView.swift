//
//  MagazineView.swift
//  CircleMagazine
//
//  The signed-in root: loads the live issue and renders it as a vertically
//  scrolled magazine — cover first, then widget pages.
//

import SwiftUI

struct MagazineView: View {
    let db: DatabaseService
    @Namespace private var zoom

    @State private var issue: (issue: Issue, pages: [(page: Page, widgets: [PageMedia])])?
    @State private var loading = true
    @State private var errorText: String?

    var body: some View {
        GeometryReader { geo in
            Group {
                if loading {
                    ProgressView()
                } else if let errorText {
                    ContentUnavailableView("Couldn't load issue", systemImage: "wifi.slash",
                                           description: Text(errorText))
                } else if let issue, !issue.pages.isEmpty {
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(Array(issue.pages.enumerated()), id: \.element.page.id) { index, entry in
                                if index == 0 {
                                    CoverPage(imageURL: coverURL(entry.widgets),
                                              width: geo.size.width, height: geo.size.height)
                                } else {
                                    WidgetPage(widgets: entry.widgets, width: geo.size.width, namespace: zoom)
                                }
                            }
                        }
                    }
                } else {
                    ContentUnavailableView("No issue yet", systemImage: "book.closed")
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .ignoresSafeArea()
        .overlay(alignment: .bottomTrailing) {
            Button("Sign out") { Task { try? await db.signOut() } }
                .buttonStyle(.bordered)
                .tint(.white)
                .padding()
        }
        .task {
            do { issue = try await db.fetchCurrentIssue() }
            catch { errorText = error.localizedDescription }
            loading = false
        }
    }

    /// Cover photo = the first image widget on the cover page.
    private func coverURL(_ widgets: [PageMedia]) -> URL? {
        widgets.first { $0.widgetType == .image }?.mediaUrl.flatMap(URL.init(string:))
    }
}
