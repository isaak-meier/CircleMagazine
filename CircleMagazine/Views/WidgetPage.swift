//
//  WidgetPage.swift
//  CircleMagazine
//
//  A page of widgets packed onto the grid and laid out by absolute position.
//

import SwiftUI

struct WidgetPage: View {
    let widgets: [PageMedia]
    let width: CGFloat
    var namespace: Namespace.ID

    var body: some View {
        let placed = packWidgets(widgets)
        let cell = width / CGFloat(gridColumns)
        let height = CGFloat(gridRows(placed)) * cell

        ZStack(alignment: .topLeading) {
            ForEach(placed) { p in
                WidgetView(media: p.media, namespace: namespace)
                    .frame(width: CGFloat(p.w) * cell, height: CGFloat(p.h) * cell)
                    .padding(2)
                    .offset(x: CGFloat(p.col) * cell, y: CGFloat(p.row) * cell)
            }
        }
        .frame(width: width, height: height, alignment: .topLeading)
    }
}
