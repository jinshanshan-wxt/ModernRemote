import SwiftUI
import UIKit
import ImageIO

// Decode once, away from the main thread. NSCache releases decoded pixels under
// memory pressure; disk-cache JPEGs remain available across launches.
enum ArtworkImages {
    private static let images = NSCache<NSString, UIImage>()
    static func decode(_ data: Data, key: String) async -> UIImage? {
        if let image = images.object(forKey: key as NSString) { return image }
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                guard let source = CGImageSourceCreateWithData(data as CFData, nil),
                      let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                        kCGImageSourceCreateThumbnailFromImageAlways: true,
                        kCGImageSourceThumbnailMaxPixelSize: 640,
                        kCGImageSourceShouldCacheImmediately: true
                      ] as CFDictionary) else { continuation.resume(returning: nil); return }
                let image = UIImage(cgImage: cg)
                images.totalCostLimit = 64 * 1024 * 1024
                images.setObject(image, forKey: key as NSString, cost: cg.bytesPerRow * cg.height)
                continuation.resume(returning: image)
            }
        }
    }
}

// An index rail deliberately has its own state. Dragging it must not rerun the
// library query, animate thousands of rows, or change playback.
struct QuickScrollRail: View {
    let targets: [QuickScrollTarget]
    let scroll: (String) -> Void
    @State private var active = false
    @State private var fraction: Double = 0
    @State private var lastID: String?
    @State private var lastJump = Date.distantPast
    private var selected: QuickScrollTarget? {
        guard !targets.isEmpty else { return nil }
        return targets[LibraryNavigation.position(fraction, count: targets.count)]
    }
    var body: some View {
        if targets.count > 25 {
            GeometryReader { geometry in
                let height = min(420.0, max(60.0, geometry.size.height - 40))
                ZStack(alignment: .trailing) {
                    if active, let selected {
                        Text(selected.title).font(.headline).lineLimit(2)
                            .padding(12).frame(width: 240, alignment: .leading)
                            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                            .offset(x: -36).allowsHitTesting(false)
                    }
                    ZStack {
                        Capsule().fill(Color.secondary.opacity(active ? 0.3 : 0.12)).frame(width: 4)
                        VStack(spacing: 0) {
                            ForEach(0..<min(20, targets.count), id: \.self) { index in
                                let item = targets[LibraryNavigation.position(Double(index) / Double(min(20, targets.count) - 1), count: targets.count)]
                                Text(item.label).font(.system(size: 9, weight: .semibold)).foregroundStyle(Color.accentColor)
                                    .frame(maxHeight: .infinity)
                            }
                        }.frame(width: 20)
                        if active {
                            Capsule().fill(Color.accentColor).frame(width: 5, height: 24)
                                .offset(x: -11, y: CGFloat(fraction - 0.5) * (height - 24))
                        }
                    }.frame(width: 28, height: height).contentShape(Rectangle())
                        .gesture(DragGesture(minimumDistance: 0).onChanged { value in
                            active = true
                            fraction = min(1, max(0, value.location.y / height))
                            if let item = selected, lastID != item.id, Date().timeIntervalSince(lastJump) >= 0.04 {
                                lastID = item.id; lastJump = Date(); scroll(item.id)
                            }
                        }.onEnded { _ in
                            if let item = selected { scroll(item.id) }
                            active = false; lastID = nil
                        })
                        .accessibilityLabel("快速定位")
                        .accessibilityValue(selected?.title ?? "")
                        .accessibilityAdjustableAction { direction in
                            fraction = min(1, max(0, fraction + (direction == .increment ? 0.05 : -0.05)))
                            if let item = selected { scroll(item.id) }
                        }
                }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
            }.frame(width: 28)
        }
    }
}
