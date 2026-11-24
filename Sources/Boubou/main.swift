import AppKit

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
