import SwiftUI
import AppKit

// User-requested iTunes Remote visual reference: blue gradient and white play triangle.
// Mac tile matches Music.app's 824/1024 opaque footprint. iOS remains full bleed.
struct RemoteIconArtwork: View {
    let macOS: Bool
    private var tile: CGFloat { macOS ? 824 : 1024 }
    var body: some View {
        ZStack {
            if macOS {
                RoundedRectangle(cornerRadius: 185, style: .continuous)
                    .fill(background).frame(width: tile, height: tile)
                    .shadow(color: .black.opacity(0.12), radius: 8, y: 6)
            } else {
                Rectangle().fill(background).frame(width: tile, height: tile)
            }
            Canvas { context, _ in
                var triangle = Path()
                triangle.move(to: CGPoint(x: 150, y: 130))
                triangle.addQuadCurve(to: CGPoint(x: 171, y: 116), control: CGPoint(x: 150, y: 105))
                triangle.addLine(to: CGPoint(x: 388, y: 244))
                triangle.addQuadCurve(to: CGPoint(x: 388, y: 267), control: CGPoint(x: 405, y: 256))
                triangle.addLine(to: CGPoint(x: 171, y: 395))
                triangle.addQuadCurve(to: CGPoint(x: 150, y: 382), control: CGPoint(x: 150, y: 407))
                triangle.closeSubpath()
                let scale = tile / 512
                let margin = (1024 - tile) / 2
                triangle = triangle.applying(CGAffineTransform(a: scale, b: 0, c: 0, d: scale, tx: margin, ty: margin))
                context.fill(triangle, with: .linearGradient(Gradient(colors: [.white, Color(red: 0.82, green: 0.90, blue: 1)]), startPoint: CGPoint(x: 350, y: 300), endPoint: CGPoint(x: 620, y: 740)))
            }.frame(width: 1024, height: 1024)
        }.frame(width: 1024, height: 1024)
    }
    private var background: LinearGradient {
        LinearGradient(colors: [Color(red: 0.39, green: 0.68, blue: 0.98), Color(red: 0, green: 0.39, blue: 0.89)], startPoint: .top, endPoint: .bottom)
    }
}

@main struct RenderMacIcon {
    @MainActor static func main() throws {
        guard CommandLine.arguments.count >= 2 else { fatalError("Pass output PNG path and optional --ios") }
        let renderer = ImageRenderer(content: RemoteIconArtwork(macOS: !CommandLine.arguments.contains("--ios")))
        renderer.scale = 1
        guard let image = renderer.nsImage, let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff), let png = bitmap.representation(using: .png, properties: [:]) else {
            fatalError("Icon rendering failed")
        }
        try png.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
    }
}
