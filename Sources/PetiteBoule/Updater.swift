import AppKit
import ServiceManagement

/// Mises à jour automatiques depuis les releases GitHub d'osayanis/petiteboule (dépôt public).
/// La release « latest » contient PetiteBoule.zip (publish.sh l'y met). Vérifie au lancement puis
/// toutes les 6 h ; installe toute seule, quand rien n'est ouvert à l'écran, puis se relance.
@MainActor
final class Updater: ObservableObject {
    static let shared = Updater()
    static let repo = "osayanis/petiteboule"
    static let asset = "PetiteBoule.zip"
    static var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0"
    }

    @Published var status = "À jour"
    private var ready: (version: String, app: URL, work: URL)?
    private var busy = false
    private var timer: Timer?

    func start() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 30) { self.check() }
        timer = Timer.scheduledTimer(withTimeInterval: 6 * 3600, repeats: true) { _ in
            MainActor.assumeIsolated { Updater.shared.check() }
        }
        // toutes les minutes : une mise à jour prête s'installe dès que l'écran est tranquille
        Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { _ in
            MainActor.assumeIsolated { Updater.shared.installIfIdle() }
        }
    }

    func check(manual: Bool = false) {
        guard !busy, ready == nil else { if manual, let r = ready { status = "Version \(r.version) prête, elle s'installe dans un instant" }; return }
        busy = true
        if manual { status = "Recherche…" }
        Task {
            defer { busy = false }
            do {
                var req = URLRequest(url: URL(string: "https://api.github.com/repos/\(Self.repo)/releases/latest")!)
                req.cachePolicy = .reloadIgnoringLocalCacheData
                req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
                req.setValue("PetiteBoule", forHTTPHeaderField: "User-Agent")
                let (data, resp) = try await URLSession.shared.data(for: req)
                guard (resp as? HTTPURLResponse)?.statusCode == 200,
                      let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let tag = json["tag_name"] as? String,
                      let assets = json["assets"] as? [[String: Any]],
                      let a = assets.first(where: { $0["name"] as? String == Self.asset }),
                      let s = a["browser_download_url"] as? String, let url = URL(string: s) else {
                    if manual { status = "Pas de version en ligne pour l'instant" }
                    return
                }
                let latest = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
                guard Self.isNewer(latest, than: Self.currentVersion) else {
                    status = "À jour (vérifié à \(Date().formatted(date: .omitted, time: .shortened)))"
                    return
                }
                status = "Téléchargement de la version \(latest)…"
                let r = try await download(url, version: latest)
                ready = r
                status = "Version \(latest) prête, elle s'installe dans un instant"
                installIfIdle()
            } catch {
                if manual { status = "Impossible de vérifier (pas d'internet ?)" }
            }
        }
    }

    private func download(_ url: URL, version: String) async throws -> (String, URL, URL) {
        let (tmp, resp) = try await URLSession.shared.download(from: url)
        guard (resp as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
        let work = FileManager.default.temporaryDirectory.appendingPathComponent("PetiteBoule-maj-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
        let zip = work.appendingPathComponent(Self.asset)
        try FileManager.default.moveItem(at: tmp, to: zip)
        try Self.run("/usr/bin/ditto", ["-x", "-k", zip.path, work.path])
        let app = work.appendingPathComponent("Petite Boule.app")
        // Même identifiant, signature intacte, et vraiment plus récente : sinon on ne touche à rien.
        guard let info = NSDictionary(contentsOf: app.appendingPathComponent("Contents/Info.plist")) as? [String: Any],
              info["CFBundleIdentifier"] as? String == Bundle.main.bundleIdentifier,
              let v = info["CFBundleShortVersionString"] as? String, Self.isNewer(v, than: Self.currentVersion) else {
            throw URLError(.cannotDecodeContentData)
        }
        try Self.run("/usr/bin/codesign", ["--verify", "--deep", "--strict", app.path])
        return (v, app, work)
    }

    /// Rien à l'écran (ni bulle, ni cabinet) : on remplace l'app et on la relance en silence.
    func installIfIdle() {
        guard let r = ready, Coach.shared.bubble == nil, !Coach.shared.cabinetOpen, !Coach.shared.breathing else { return }
        let current = Bundle.main.bundlePath
        guard current.hasSuffix(".app") else { return }
        let script = r.work.appendingPathComponent("remplacer.sh")
        let text = """
        #!/bin/bash
        while kill -0 \(ProcessInfo.processInfo.processIdentifier) 2>/dev/null; do sleep 0.2; done
        rm -rf "\(current)"
        /usr/bin/ditto "\(r.app.path)" "\(current)"
        rm -rf "\(r.work.path)"
        open -g "\(current)" --args --mise-a-jour
        """
        guard (try? text.write(to: script, atomically: true, encoding: .utf8)) != nil else { return }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/bash")
        p.arguments = [script.path]
        guard (try? p.run()) != nil else { return }
        NSApp.terminate(nil)
    }

    static func isNewer(_ a: String, than b: String) -> Bool {
        let pa = a.split(separator: ".").map { Int($0) ?? 0 }, pb = b.split(separator: ".").map { Int($0) ?? 0 }
        for i in 0..<max(pa.count, pb.count) {
            let x = i < pa.count ? pa[i] : 0, y = i < pb.count ? pb[i] : 0
            if x != y { return x > y }
        }
        return false
    }

    @discardableResult
    static func run(_ tool: String, _ args: [String]) throws -> Int32 {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: tool)
        p.arguments = args
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        try p.run()
        p.waitUntilExit()
        guard p.terminationStatus == 0 else { throw URLError(.cannotOpenFile) }
        return p.terminationStatus
    }
}

/// Ouverture au démarrage du Mac (Réglages Système › Ouverture).
enum LoginItem {
    static var enabled: Bool { SMAppService.mainApp.status == .enabled }
    static func enable() { try? SMAppService.mainApp.register() }
    static func disable() { try? SMAppService.mainApp.unregister() }
}
