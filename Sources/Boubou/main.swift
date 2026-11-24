import AppKit
import SwiftUI

let args = CommandLine.arguments
if args.count > 2, args[1] == "icon" {
    do { try MainActor.assumeIsolated { try IconArt.export(to: URL(fileURLWithPath: args[2])) }; exit(0) }
    catch { FileHandle.standardError.write(Data("\(error)\n".utf8)); exit(1) }
}
if args.count > 2, args[1] == "lit" {
    try? MainActor.assumeIsolated { try IconArt.previewBed(to: URL(fileURLWithPath: args[2])) }; exit(0)
}
if args.count > 2, args[1] == "portraits" {
    do { try MainActor.assumeIsolated { try IconArt.portraits(to: URL(fileURLWithPath: args[2])) }; exit(0) }
    catch { FileHandle.standardError.write(Data("\(error)\n".utf8)); exit(1) }
}
if args.count > 2, args[1] == "apercu-interactif" {
    MainActor.assumeIsolated {
        for (nom, l, hj, hc) in [("panneau", 312.0, 214.0, 178.0), ("notch", 444.0, 190.0, 170.0)] {
            let r = ImageRenderer(content: InteractifApercu.vue(largeur: l, hJardin: hj, hCuisine: hc))
            r.scale = 2
            if let img = r.nsImage, let t = img.tiffRepresentation, let b = NSBitmapImageRep(data: t) {
                try? b.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: args[2]).appendingPathComponent("interactif-\(nom).png"))
            }
        }
    }
    exit(0)
}
if args.count > 2, args[1] == "apercu-scenes" {
    MainActor.assumeIsolated {
        let dir = URL(fileURLWithPath: args[2])
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let quoi = args.count > 3 ? args[3].split(separator: ",").compactMap { SceneKind(rawValue: String($0)) } : SceneKind.allCases
        for k in quoi {
            let r = ImageRenderer(content: ScenesApercu.pellicule(k, emojis: k == .cuisine ? ["🥕", "🥔", "🥕"] : [], resultat: k == .cuisine ? "🥣" : (k == .niveau ? "Externe" : nil), images: 8))
            r.scale = 1.5
            if let img = r.nsImage, let t = img.tiffRepresentation, let b = NSBitmapImageRep(data: t) {
                try? b.representation(using: .png, properties: [:])?.write(to: dir.appendingPathComponent("\(k.rawValue).png"))
            }
        }
    }
    exit(0)
}
if args.count > 1, args[1] == "essai-foyer" {
    Task { @MainActor in exit(await FoyerEssai.run() ? 0 : 1) }
    RunLoop.main.run()
}
if args.count > 4, args[1] == "apercu-foyer" {
    do {
        try MainActor.assumeIsolated {
            try FoyerApercu.run(etat: URL(fileURLWithPath: args[2]), jeu: URL(fileURLWithPath: args[3]), to: URL(fileURLWithPath: args[4]))
        }
        exit(0)
    } catch { print(error); exit(1) }
}
if args.count > 2, args[1] == "apercu" {
    do { try MainActor.assumeIsolated { try IconArt.preview(to: URL(fileURLWithPath: args[2])) }; exit(0) }
    catch { FileHandle.standardError.write(Data("\(error)\n".utf8)); exit(1) }
}

let app = NSApplication.shared
let delegate = MainActor.assumeIsolated { AppDelegate() }
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
