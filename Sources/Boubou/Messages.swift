import Foundation

/// Les phrases de Boubou. Source : messages.json (dans l'app), remplacé par la version en ligne
/// du dépôt GitHub dès qu'elle est lisible — Yanis peut changer les textes sans publier de version.
@MainActor
final class Messages: ObservableObject {
    static let shared = Messages()
    static let remote = URL(string: "https://raw.githubusercontent.com/osayanis/boubou/main/messages.json")!

    @Published private(set) var table: [String: Any] = [:]
    private var bundled: [String: Any] = [:]
    private var last: [String: String] = [:]
    private var cache: URL { Store.shared.folder.appendingPathComponent("messages-en-ligne.json") }

    private init() {
        let candidates = [Bundle.main.url(forResource: "messages", withExtension: "json"),
                          URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("messages.json")]
        for url in candidates.compactMap({ $0 }) {
            if let t = Self.parse(try? Data(contentsOf: url)) { bundled = t; break }
        }
        table = bundled
        if let t = Self.parse(try? Data(contentsOf: cache)) { merge(t) }
    }

    nonisolated private static func parse(_ data: Data?) -> [String: Any]? {
        guard let data, let o = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return o
    }

    /// Les listes non vides de la version en ligne remplacent celles de l'app ; le reste est gardé.
    private func merge(_ remote: [String: Any]) {
        var t = bundled
        for (k, v) in remote {
            if let l = v as? [String], l.isEmpty { continue }
            t[k] = v
        }
        table = t
    }

    func refresh() {
        var req = URLRequest(url: Self.remote)
        req.cachePolicy = .reloadIgnoringLocalCacheData
        req.timeoutInterval = 20
        URLSession.shared.dataTask(with: req) { data, resp, _ in
            guard (resp as? HTTPURLResponse)?.statusCode == 200, let data, Self.parse(data) != nil else { return }
            DispatchQueue.main.async {
                guard let t = Self.parse(data) else { return }
                try? data.write(to: self.cache, options: .atomic)
                self.merge(t)
            }
        }.resume()
    }

    var from: String { (table["de"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? "Quelqu'un qui t'aime" }

    func list(_ key: String) -> [String] { (table[key] as? [String]) ?? [] }

    /// L'OsaNotch de Yanis : code ami à 6 chiffres et nom.
    var partner: (code: String, name: String)? {
        guard let l = table["lien"] as? [String: Any], let c = l["code"] as? String, c.count == 6, c.allSatisfy(\.isNumber) else { return nil }
        return (c, (l["nom"] as? String) ?? from)
    }

    /// L'évènement du jour (anniversaire de couple…), s'il y en a un.
    var eventToday: (text: String, party: Bool)? {
        let f = DateFormatter(); f.dateFormat = "MM-dd"
        let today = f.string(from: Date())
        for e in (table["evenements"] as? [[String: Any]]) ?? [] where (e["date"] as? String) == today {
            if let t = e["texte"] as? String { return (fill(t), (e["fete"] as? Bool) ?? true) }
        }
        return nil
    }

    /// Une phrase au hasard (jamais deux fois de suite la même), avec {prenom}, {de} et les variables.
    func pick(_ key: String, _ vars: [String: String] = [:]) -> String {
        let l = list(key)
        guard !l.isEmpty else { return "" }
        var choice = l.randomElement()!
        if l.count > 1 { while choice == last[key] { choice = l.randomElement()! } }
        last[key] = choice
        return fill(choice, vars)
    }

    func fill(_ s: String, _ vars: [String: String] = [:]) -> String {
        let name = Store.shared.name
        var r = s.replacingOccurrences(of: " {prenom}", with: name.isEmpty ? "" : " \(name)")
            .replacingOccurrences(of: "{prenom}", with: name.isEmpty ? "toi" : name)
            .replacingOccurrences(of: "{de}", with: from)
        for (k, v) in vars { r = r.replacingOccurrences(of: "{\(k)}", with: v) }
        return r
    }
}
