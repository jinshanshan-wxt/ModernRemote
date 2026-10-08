import SwiftUI
import AppKit

// A separate macOS canvas: transparent padding, continuous tile, original vector mark.
struct MacIconArtwork: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 185, style: .continuous)
                .fill(LinearGradient(colors: [.white, Color(white: 0.95)], startPoint: .top, endPoint: .bottom))
                .frame(width: 824, height: 824)
                .shadow(color: .black.opacity(0.16), radius: 8, y: 6)
            Canvas { context, _ in
                var note = Path()
                note.move(to: CGPoint(x: 480, y: 603))
                note.addLine(to: CGPoint(x: 480, y: 346))
                note.addQuadCurve(to: CGPoint(x: 501, y: 333), control: CGPoint(x: 480, y: 324))
                note.addCurve(to: CGPoint(x: 579, y: 418), control1: CGPoint(x: 538, y: 355), control2: CGPoint(x: 568, y: 367))
                note.addCurve(to: CGPoint(x: 559, y: 491), control1: CGPoint(x: 586, y: 449), control2: CGPoint(x: 576, y: 479))
                note.addCurve(to: CGPoint(x: 520, y: 404), control1: CGPoint(x: 565, y: 441), control2: CGPoint(x: 552, y: 416))
                note.addLine(to: CGPoint(x: 520, y: 618))
                note.addCurve(to: CGPoint(x: 436, y: 696), control1: CGPoint(x: 520, y: 654), control2: CGPoint(x: 485, y: 688))
                note.addCurve(to: CGPoint(x: 349, y: 652), control1: CGPoint(x: 389, y: 704), control2: CGPoint(x: 352, y: 683))
                note.addCurve(to: CGPoint(x: 407, y: 590), control1: CGPoint(x: 346, y: 620), control2: CGPoint(x: 370, y: 596))
                note.addCurve(to: CGPoint(x: 480, y: 603), control1: CGPoint(x: 437, y: 585), control2: CGPoint(x: 465, y: 590))
                note.closeSubpath()
                let coral = Gradient(colors: [Color(red: 1, green: 0.32, blue: 0.36), Color(red: 0.94, green: 0.13, blue: 0.40)])
                context.fill(note, with: .linearGradient(coral, startPoint: CGPoint(x: 400, y: 300), endPoint: CGPoint(x: 560, y: 710)))
                var arcs = Path()
                arcs.move(to: CGPoint(x: 559, y: 294))
                arcs.addCurve(to: CGPoint(x: 706, y: 428), control1: CGPoint(x: 632, y: 306), control2: CGPoint(x: 691, y: 359))
                arcs.move(to: CGPoint(x: 558, y: 349))
                arcs.addCurve(to: CGPoint(x: 651, y: 433), control1: CGPoint(x: 602, y: 359), control2: CGPoint(x: 639, y: 393))
                context.stroke(arcs, with: .linearGradient(coral, startPoint: CGPoint(x: 550, y: 290), endPoint: CGPoint(x: 700, y: 450)), style: StrokeStyle(lineWidth: 29, lineCap: .round))
            }.frame(width: 1024, height: 1024)
        }.frame(width: 1024, height: 1024)
    }
}

@main struct RenderMacIcon {
    @MainActor static func main() throws {
        guard CommandLine.arguments.count == 2 else { fatalError("Pass the output PNG path") }
        let renderer = ImageRenderer(content: MacIconArtwork())
        renderer.scale = 1
        guard let image = renderer.nsImage, let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff), let png = bitmap.representation(using: .png, properties: [:]) else {
            fatalError("Icon rendering failed")
        }
        try png.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
    }
}
