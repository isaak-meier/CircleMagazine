//
//  MagazineView.swift
//  CircleMagazine
//
//  The signed-in root: loads the live issue and renders it as a vertically
//  scrolled magazine — cover first, then widget pages.
//

import SwiftUI

struct MagazineView: View {
    let loader: IssueLoader
    @Namespace private var zoom

    static let pageColors: [Color] = [.indigo, .teal, .orange, .pink]

    var body: some View {
        GeometryReader { geo in
            Group {
                switch loader.loadState {
                case .loading:
                    ProgressView()
                case .failedToLoad(let error):
                    ContentUnavailableView("Couldn't load issue", systemImage: "wifi.slash",
                                           description: Text(error))
                case .loaded(let magazine):
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(Array(magazine.pages.enumerated()), id: \.element.page.id) { index, entry in
                                Group {
                                    if index == 0 {
                                        CoverPage(imageURL: coverURL(entry.widgets),
                                                  width: geo.size.width, height: geo.size.height)
                                    } else {
                                        WidgetPage(widgets: entry.widgets, width: geo.size.width, namespace: zoom)
                                    }
                                }
                                // Every page is exactly one viewport tall so snap targets
                                // are uniform; content centers within it.
                                .frame(width: geo.size.width, height: geo.size.height)
                                .background(index == 0 ? Color.clear
                                            : Self.pageColors[(index - 1) % Self.pageColors.count])
                            }
                        }
                        .scrollTargetLayout()
                    }
                    .scrollTargetBehavior(.paging)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .ignoresSafeArea()
        .task { await loader.refreshIfNeeded() }
    }

    /// Cover photo = the first image widget on the cover page.
    private func coverURL(_ widgets: [PageMedia]) -> URL? {
        widgets.first { $0.widgetType == .image }?.mediaUrl.flatMap(URL.init(string:))
    }
}

// ponytail: preview mirrors the real ScrollView/LazyVStack so swipe matches
// production, but skips the DB — cover + placeholder pages, no live fetch.
#Preview("Swipe") {
    GeometryReader { geo in
        ScrollView {
            LazyVStack(spacing: 0) {
                CoverPage(imageURL: nil, width: geo.size.width, height: geo.size.height)
                ForEach(0..<4, id: \.self) { i in
                    [Color.indigo, .teal, .orange, .pink][i]
                        .frame(width: geo.size.width, height: geo.size.height)
                        .overlay(Text("Page \(i + 1)").font(.largeTitle.bold()).foregroundStyle(.white))
                }
            }
            .scrollTargetLayout()
        }
        .scrollTargetBehavior(.paging)
    }
    // On the GeometryReader so geo reports full screen — page height == viewport,
    // matching MagazineView. (On the ScrollView it wouldn't, breaking the snap.)
    .ignoresSafeArea()
}
