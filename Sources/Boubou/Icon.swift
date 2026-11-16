import SwiftUI
import AppKit

/// L'icône : Boubou en docteur sur le fond sombre des apps Osa, avec une croix de pharmacie.
struct IconArt: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 230, style: .continuous)
                .fill(LinearGradient(colors: [Color(red: 0.2, green: 0.2, blue: 0.26), Color(red: 0.06, green: 0.06, blue: 0.09)],
                                     startPoint: .top, endPoint: .bottom))
                .frame(width: 824, height: 824)
            Circle().fill(RadialGradient(colors: [.white.opacity(0.14), .clear], center: .center, startRadius: 0, endRadius: 340))
                .frame(width: 700, height: 700).offset(y: 30)
            Cross().fill(Boule.scrub).frame(width: 150, height: 150).rotationEffect(.degrees(10)).offset(x: 235, y: -235)
            Boule(mood: .happy, size: 440).offset(y: 60)
        }
        .frame(width: 1024, height: 1024)
    }

    @MainActor static func export(to dir: URL) throws {
        let r = ImageRenderer(content: IconArt())
        r.scale = 1
        guard let cg = r.cgImage else { throw NSError(domain: "Icone", code: 1) }
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        for (px, name) in [(16, "16x16"), (32, "16x16@2x"), (32, "32x32"), (64, "32x32@2x"), (128, "128x128"), (256, "128x128@2x"),
                           (256, "256x256"), (512, "256x256@2x"), (512, "512x512"), (1024, "512x512@2x")] {
            let ctx = CGContext(data: nil, width: px, height: px, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            ctx.interpolationQuality = .high
            ctx.draw(cg, in: CGRect(x: 0, y: 0, width: px, height: px))
            let rep = NSBitmapImageRep(cgImage: ctx.makeImage()!)
            try rep.representation(using: .png, properties: [:])!.write(to: dir.appendingPathComponent("icon_\(name).png"))
        }
    }

    /// `Boubou apercu <fichier.png>` : toutes les humeurs côte à côte, pour vérifier le dessin.
    @MainActor static func preview(to file: URL) throws {
        let moods: [Boule.Mood] = [.calm, .happy, .curious, .excited, .worried, .sad, .sleepy, .dizzy, .love]
        let v = VStack(spacing: 30) {
            HStack(spacing: 10) { ForEach(Array(moods.enumerated()), id: \.offset) { Boule(mood: $0.element, size: 160) } }
            HStack(spacing: 10) {
                Boule(arms: .wave, size: 160); Boule(arms: .up, size: 160); Boule(arms: .hug, size: 160)
                Boule(size: 160, breath: 1)
                Boule(mood: .excited, arms: .up, size: 160, hat: true)
                Boule(arms: .up, size: 160, tilt: 14)
                BedView(size: 300)
                Boule(size: 56); Boule(size: 46)
            }
        }
        .padding(30).background(Color(red: 0.12, green: 0.12, blue: 0.15))
        let r = ImageRenderer(content: v)
        r.scale = 2
        guard let cg = r.cgImage else { throw NSError(domain: "Apercu", code: 1) }
        try NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:])!.write(to: file)
    }
}

extension IconArt {
    @MainActor static func previewBed(to file: URL) throws {
        let v = HStack(spacing: 40) { BedView(size: 360); BedView(size: 96) }.padding(40).background(Color(red: 0.12, green: 0.12, blue: 0.15))
        let r = ImageRenderer(content: v); r.scale = 2
        guard let cg = r.cgImage else { throw NSError(domain: "Apercu", code: 1) }
        try NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:])!.write(to: file)
    }
}

/// La croix verte de pharmacie.
struct Cross: Shape {
    func path(in r: CGRect) -> Path {
        let t = r.width * 0.34
        var p = Path()
        p.addRoundedRect(in: CGRect(x: r.midX - t / 2, y: r.minY, width: t, height: r.height), cornerSize: CGSize(width: t * 0.25, height: t * 0.25))
        p.addRoundedRect(in: CGRect(x: r.minX, y: r.midY - t / 2, width: r.width, height: t), cornerSize: CGSize(width: t * 0.25, height: t * 0.25))
        return p
    }
}
