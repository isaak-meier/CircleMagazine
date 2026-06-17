//
//  MagazineLayout.swift
//  CircleMagazine
//
//  Grid + per-type footprints + the (stubbed) packing algorithm that arranges
//  widgets to fill a page. The packer is a placeholder — see packWidgets.
//

import Foundation

/// Widget pages are laid out on a fixed-column grid.
let gridColumns = 6

extension WidgetType {
    /// Fixed footprint in grid cells: (width, height). One shape per media type.
    /// ponytail: video is a tall 3×6 per the approved design — flip to (6, 3)
    /// for a full-width hero if that's what you meant.
    var footprint: (w: Int, h: Int) {
        switch self {
        case .video: return (3, 6)
        case .image: return (3, 3)
        case .text:  return (3, 2)
        case .audio: return (6, 1)
        }
    }
}

/// A widget assigned a grid position by the packer.
struct PlacedWidget: Identifiable {
    let media: PageMedia
    let col, row, w, h: Int
    var id: UUID { media.id }
}

/// Arrange a page's widgets into the grid.
///
/// ponytail: naive left-to-right shelf-pack stub — fills a row until the next
/// footprint won't fit, then drops to a new shelf. Renders correctly but leaves
/// gaps. Replace with the real bin-packer; keep this signature:
///   func packWidgets(_ widgets: [PageMedia], columns: Int) -> [PlacedWidget]
func packWidgets(_ widgets: [PageMedia], columns: Int = gridColumns) -> [PlacedWidget] {
    var placed: [PlacedWidget] = []
    var x = 0, row = 0, shelfHeight = 0
    for media in widgets {
        guard let (w, h) = media.widgetType?.footprint else { continue }
        if x + w > columns {            // wrap to a new shelf
            row += shelfHeight
            x = 0
            shelfHeight = 0
        }
        placed.append(PlacedWidget(media: media, col: x, row: row, w: w, h: h))
        x += w
        shelfHeight = max(shelfHeight, h)
    }
    return placed
}

/// Total grid rows a packed page occupies — used to size the page height.
func gridRows(_ placed: [PlacedWidget]) -> Int {
    placed.map { $0.row + $0.h }.max() ?? 0
}

#if DEBUG
/// Smallest check that breaks if the packer regresses: nothing overlaps and
/// nothing escapes the column bounds. Call from a debug context to exercise.
enum MagazineLayoutCheck {
    static func demo() {
        func media(_ t: WidgetType) -> PageMedia {
            PageMedia(id: UUID(), pageId: nil, mediaUrl: "x", mediaType: t.rawValue,
                      textContent: "x", position: nil, createdAt: nil)
        }
        let placed = packWidgets([media(.video), media(.image), media(.image),
                                  media(.text), media(.audio), media(.image)])
        for p in placed {
            assert(p.col >= 0 && p.col + p.w <= gridColumns, "widget escapes grid columns")
        }
        for i in placed.indices {
            for j in placed.indices where j > i {
                let a = placed[i], b = placed[j]
                let overlaps = a.col < b.col + b.w && b.col < a.col + a.w
                            && a.row < b.row + b.h && b.row < a.row + a.h
                assert(!overlaps, "packed widgets overlap")
            }
        }
    }
}
#endif
