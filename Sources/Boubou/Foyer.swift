import SwiftUI
import AppKit

// Le foyer : Boubou qu'on élève à deux. L'état vit sur boubou.osalabs.fr (voir boubou-site/docs/foyer.md),
// Jeanne s'en occupe ici, Yanis depuis son OsaNotch. Cette app ne fait qu'afficher et envoyer des gestes.

// MARK: - Modèles (décodage tolérant : un champ inconnu ou absent ne casse rien)

struct FoyerJeu: Decodable {
    struct Ingredient: Decodable { var nom: String; var emoji: String; var un: String?; var prix: Int?; var potager: Bool?; var rare: Bool? }
    struct Plante: Decodable { var heures: Double; var recolte: Int }
    struct Recette: Decodable, Identifiable { var id: String; var nom: String; var un: String?; var emoji: String; var ingredients: [String: Int]?; var soigne: Bool? }
    struct Niveau: Decodable { var n: Int; var nom: String; var xp: Int; var cadeau: String? }
    struct Accessoire: Decodable { var nom: String; var emoji: String; var niveau: Int }
    var ingredients: [String: Ingredient]
    var plantes: [String: Plante]
    var recettes: [Recette]
    var mystere: Recette?
    var cru: [String: [String: Int]]?
    var niveaux: [Niveau]
    var accessoires: [String: Accessoire]
    var etoiles: [String: Int]?

    /// Ordre d'affichage : le potager, puis l'épicerie, puis le reste.
    static let ordre = ["carotte", "salade", "tomate", "patate", "fraise", "potiron", "oeuf", "farine", "lait", "citron", "riz",
                        "fromage", "miel", "chocolat", "carotte_doree"]
    func trie(_ ids: some Sequence<String>) -> [String] {
        ids.sorted { (Self.ordre.firstIndex(of: $0) ?? 99, $0) < (Self.ordre.firstIndex(of: $1) ?? 99, $1) }
    }
    func plat(_ id: String) -> Recette? { id == "mystere" ? mystere : recettes.first { $0.id == id } }
    func emoji(_ id: String) -> String { ingredients[id]?.emoji ?? plat(id)?.emoji ?? "❓" }
}

struct FoyerEtat: Decodable {
    struct Niveau: Decodable { var n: Int; var nom: String; var xp: Int; var suivant: Suivant?
        struct Suivant: Decodable { var nom: String; var xp: Int } }
    struct Case: Decodable { var plante: String; var plantee: Double; var arrosee: Bool; var par: String?; var prete: Bool; var fin: Double }
    struct Evenement: Decodable, Identifiable {
        var quand: Double; var qui: String; var emoji: String; var texte: String; var type: String?; var detail: String?
        var id: String { "\(quand)-\(qui)-\(texte)" }
    }
    struct Mot: Decodable, Identifiable { var id: String; var quand: Double; var texte: String; var lu: Bool }

    var stats: [String: Int]
    var humeur: String
    var malade: Bool
    var dort: Bool
    var xp: Int
    var niveau: Niveau
    var etoiles: Int
    var etoilesRestantAujourdhui: Int?
    var inventaire: [String: Int]
    var frigo: [String: Int]
    var potager: [Case?]
    var recettes: [String]
    var accessoire: String?
    var accessoires: [String]
    var coursesFaites: Bool
    var prochainRamassage: Double
    var journal: [Evenement]
    var mots: [Mot]
    var maintenant: Double

    func stat(_ s: String) -> Int { stats[s] ?? 50 }
    /// L'expression de Boubou quand rien d'autre ne se passe.
    var mood: Boule.Mood {
        switch humeur {
        case "heureux": return .happy
        case "faim", "sale", "malade": return .worried
        case "triste": return .sad
        case "fatigue", "dort": return .sleepy
        default: return .calm
        }
    }
    /// Le petit signe au-dessus de sa tête quand il a besoin de quelque chose.
    var besoin: String? {
        switch humeur {
        case "faim": return "🍽️"
        case "sale": return "🛁"
        case "fatigue": return "💤"
        case "triste": return "💔"
        case "malade": return "🤒"
        default: return nil
        }
    }
}

struct FoyerReponse: Decodable {
    struct Passage: Decodable { var n: Int; var nom: String; var cadeau: String? }
    struct Resultat: Decodable {
        var niveau: Passage?
        var plat: String?
        var nouvelle: Bool?
        var gueri: Bool?
        var recolte: [String: Int]?
        var achat: [String: Int]?
        var etoiles: Int?
        var mystere: Int?
        var ingredient: String?
    }
    var ok: Bool
    var erreur: String?
    var etat: FoyerEtat?
    var resultat: Resultat?
}

// MARK: - Le client

@MainActor
final class Foyer: ObservableObject {
    static let shared = Foyer()

    @Published private(set) var etat: FoyerEtat?
    @Published private(set) var jeu: FoyerJeu?
    @Published private(set) var inscrit = false
    /// Petite phrase affichée en bas de l'onglet Boubou (résultat d'un geste, erreur).
    @Published var toast: String?
    /// Le champ « un mot pour Yanis » est ouvert.
    @Published var ecrire = false
    /// Écart entre l'horloge du serveur et celle du Mac (ms).
    private(set) var decalage: Double = 0

    let secret: String
    private let base: URL
    private var timer: Timer?
    private var toastTask: Task<Void, Never>?
    private var donnees: Set<String>
    /// Ce que Yanis a fait et que Boubou n'a pas encore raconté.
    private var histoires: [FoyerEtat.Evenement] = []
    private var carotteMontree = Date.distantPast
    private var derniereCaresse = Date.distantPast
    private var besoinsDits: [String: Date] = [:]

    init() {
        if let s = UserDefaults.standard.string(forKey: "BoubouFoyer"), s.count >= 32 { secret = s }
        else {
            var b = [UInt8](repeating: 0, count: 32)
            _ = SecRandomCopyBytes(kSecRandomDefault, b.count, &b)
            secret = b.map { String(format: "%02x", $0) }.joined()
            UserDefaults.standard.set(secret, forKey: "BoubouFoyer")
        }
        base = URL(string: ProcessInfo.processInfo.environment["BOUBOU_API"] ?? "https://boubou.osalabs.fr")!
        donnees = Set(UserDefaults.standard.stringArray(forKey: "BoubouEtoilesDonnees") ?? [])
    }

    func start() {
        // Une Boubou de test (dossier ou scène de démo) ne doit jamais inscrire le vrai foyer :
        // le premier secret inscrit sur boubou.osalabs.fr devient LE foyer.
        let env = ProcessInfo.processInfo.environment
        if (env["BOUBOU_DOSSIER"] != nil || env["BOUBOU_DEMO"] != nil), env["BOUBOU_API"] == nil { return }
        Task {
            await inscrire()
            await chargerJeu()
            await rafraichir()
        }
        timer = Timer.scheduledTimer(withTimeInterval: 120, repeats: true) { _ in
            MainActor.assumeIsolated { Task { await Foyer.shared.rafraichir() } }
        }
    }

    var maintenant: Double { Date().timeIntervalSince1970 * 1000 + decalage }

    /// Pour `Boubou apercu-foyer` : un état lu dans un fichier, sans réseau.
    func injecter(etat e: FoyerEtat, jeu j: FoyerJeu) {
        jeu = j; inscrit = true; decalage = e.maintenant - Date().timeIntervalSince1970 * 1000; etat = e
    }

    private func requete(_ chemin: String, corps: [String: Any]? = nil) async -> Data? {
        var r = URLRequest(url: base.appendingPathComponent(chemin))
        r.timeoutInterval = 15
        r.setValue("Bearer \(secret)", forHTTPHeaderField: "Authorization")
        if let corps {
            r.httpMethod = "POST"
            r.setValue("application/json", forHTTPHeaderField: "Content-Type")
            r.httpBody = try? JSONSerialization.data(withJSONObject: corps)
        }
        return try? await URLSession.shared.data(for: r).0
    }

    private func inscrire() async {
        guard let d = await requete("api/foyer/inscription", corps: ["secret": secret]),
              let o = try? JSONSerialization.jsonObject(with: d) as? [String: Any] else { return }
        inscrit = o["ok"] as? Bool == true
        if inscrit { Link.shared.helloFoyer() }
    }

    private func chargerJeu() async {
        guard let d = await requete("api/foyer/jeu"), let j = try? JSONDecoder().decode(FoyerJeu.self, from: d) else { return }
        jeu = j
    }

    func rafraichir() async {
        if !inscrit { await inscrire() }
        if jeu == nil { await chargerJeu() }
        guard inscrit, let d = await requete("api/foyer"), let r = try? JSONDecoder().decode(FoyerReponse.self, from: d), let e = r.etat else { return }
        recoit(e)
    }

    private func recoit(_ e: FoyerEtat) {
        let avant = etat
        decalage = e.maintenant - Date().timeIntervalSince1970 * 1000
        etat = e
        // Ce que Yanis a fait depuis la dernière fois : Boubou le raconte.
        let cle = "BoubouVuYanis"
        let vu = UserDefaults.standard.double(forKey: cle)
        let derniers = e.journal.filter { $0.qui == "yanis" && $0.quand > vu }
        if let plusRecent = e.journal.first(where: { $0.qui == "yanis" })?.quand { UserDefaults.standard.set(plusRecent, forKey: cle) }
        if vu > 0, !derniers.isEmpty {
            histoires = Array((derniers + histoires).prefix(8))
            Coach.shared.hop += 1
            if derniers.contains(where: { $0.type == "niveau" }) { FX.shared.burst(.confetti) }
        }
        // Yanis l'a couché depuis son notch : il va au lit ici aussi (mais on ne le réveille jamais à distance).
        if let a = avant, !a.dort, e.dort, !Coach.shared.sleeping { Coach.shared.sleep(depuisFoyer: true) }
    }

    /// Un geste. Met l'état à jour, prévient l'OsaNotch de Yanis, et renvoie la réponse (nil si hors ligne).
    @discardableResult
    func geste(_ type: String, _ params: [String: Any] = [:]) async -> FoyerReponse? {
        if !inscrit { await inscrire() }
        guard inscrit else { dire("Pas de connexion pour l'instant…"); return nil }
        var corps = params; corps["qui"] = "jeanne"; corps["type"] = type
        guard let d = await requete("api/foyer/action", corps: corps),
              let r = try? JSONDecoder().decode(FoyerReponse.self, from: d) else { dire("Pas de connexion pour l'instant…"); return nil }
        if let e = r.etat { recoit(e) }
        if r.ok {
            Link.shared.nudge(type)
            if let n = r.resultat?.niveau { Coach.shared.niveau(n.nom, cadeau: n.cadeau.flatMap { jeu?.accessoires[$0]?.nom }) }
        } else if let m = r.erreur { dire(m) }
        return r
    }

    /// Des étoiles pour le travail fait dans Boubou (une seule fois par chose cochée).
    func etoiles(_ raison: String, cle: String) {
        let k = "\(Day.key()):\(cle)"
        guard !donnees.contains(k) else { return }
        donnees.insert(k)
        let aujourdhui = Day.key()
        donnees = donnees.filter { $0.hasPrefix(aujourdhui) }
        UserDefaults.standard.set(Array(donnees), forKey: "BoubouEtoilesDonnees")
        Task {
            if let r = await geste("etoiles", ["raison": raison]), let n = r.resultat?.etoiles, n > 0 {
                FX.shared.burst(.sparkles)
                dire("+\(n) ⭐")
            }
        }
    }

    /// Toutes les 20 s (Coach.tick) : une carotte sauvage a poussé ? Elle apparaît à côté de Boubou.
    func verifierCarotte() {
        guard let e = etat, e.prochainRamassage <= maintenant, !e.dort, !CarrotController.shared.visible,
              Date().timeIntervalSince(carotteMontree) > 30 * 60 else { return }
        carotteMontree = Date()
        CarrotController.shared.show()
    }

    /// Les caresses comptent comme un câlin, au plus une fois toutes les 3 minutes.
    func caresse() {
        guard inscrit, Date().timeIntervalSince(derniereCaresse) > 180, etat?.dort == false else { return }
        derniereCaresse = Date()
        Task { await geste("calin") }
    }

    /// Appelé par Coach quand Boubou est libre de parler. Renvoie true s'il a dit quelque chose.
    func raconter() -> Bool {
        let coach = Coach.shared
        if !histoires.isEmpty {
            let h = histoires; histoires = []
            if let ev = h.first, let spec = scene(de: ev) {
                // ce que Yanis a fait se joue sur le bureau, puis Boubou le raconte
                StageController.shared.jouer(spec)
                let reste = h.count > 1 ? h : []
                Task {
                    try? await Task.sleep(for: .seconds(spec.kind.duree + 0.3))
                    if reste.isEmpty { coach.say(self.phrase(ev), mood: .love, arms: .hug, autoHide: 12) }
                    else { coach.say("Pendant que tu travaillais, Yanis est passé me voir 💛", lines: reste.prefix(4).map { "\($0.emoji) \($0.texte)" }, mood: .love, arms: .hug, autoHide: 16) }
                    FX.shared.burst(.hearts)
                }
                return true
            }
            if h.count == 1, let ev = h.first {
                coach.say(phrase(ev), mood: .love, arms: .hug, autoHide: 12)
            } else {
                coach.say("Pendant que tu travaillais, Yanis est passé me voir 💛", lines: h.prefix(4).map { "\($0.emoji) \($0.texte)" },
                          mood: .love, arms: .hug, autoHide: 16)
            }
            FX.shared.burst(.hearts)
            return true
        }
        // Un besoin, au plus une fois toutes les 3 h chacun, et jamais la nuit
        guard let e = etat, !e.dort else { return false }
        let besoins: [(String, Bool, [String])] = [
            ("malade", e.malade, ["Atchoum… J'ai un petit rhume 🤧 Une soupe, un velouté ou une tisane me guériraient."]),
            ("ventre", e.stat("ventre") < 25, ["J'ai un petit creux… 🍽️ Il reste quelque chose au frigo ?", "Mon ventre gargouille 🥕"]),
            ("calins", e.stat("calins") < 25, ["Tu me fais un câlin ? Passe la souris sur moi 🤗", "Je me sens un peu seul…"]),
            ("toilette", e.stat("toilette") < 20, ["Je crois que j'ai besoin d'un bain 🛁", "Je suis tout crotté…"]),
            ("energie", e.stat("energie") < 20, ["Je suis épuisé… Un petit dodo ? (double-clic sur moi) 💤"]),
        ]
        for (cle, oui, phrases) in besoins where oui {
            if let d = besoinsDits[cle], Date().timeIntervalSince(d) < 3 * 3600 { continue }
            besoinsDits[cle] = Date()
            coach.say(phrases.randomElement()!, mood: cle == "energie" ? .sleepy : .worried, arms: .wave,
                      actions: [BubbleAction(title: "M'occuper de lui", primary: true) { Coach.shared.ouvrirFoyer() },
                                BubbleAction(title: "Plus tard") { Coach.shared.dismiss() }],
                      autoHide: 25)
            return true
        }
        return false
    }

    private func scene(de ev: FoyerEtat.Evenement) -> SceneSpec? {
        let j = jeu, acc = etat?.accessoire
        switch ev.type {
        case "courses": return SceneSpec(kind: .courses, accessoire: acc)
        case "bain": return SceneSpec(kind: .bain, accessoire: acc)
        case "nourrir": return SceneSpec(kind: .repas, emojis: [ev.detail.map { j?.emoji($0) ?? "🥞" } ?? "🥞"], accessoire: acc)
        case "cuisiner":
            let p = ev.detail.flatMap { j?.plat($0) }
            let ings = (p?.ingredients ?? [:]).flatMap { k, n in Array(repeating: j?.emoji(k) ?? "🥕", count: n) }
            return SceneSpec(kind: .cuisine, emojis: ings, resultat: ev.detail == "mystere" ? "🫕" : p?.emoji)
        case "planter": return SceneSpec(kind: .planter, emojis: [ev.detail.map { j?.emoji($0) ?? "🥕" } ?? "🥕"], accessoire: acc)
        case "arroser": return SceneSpec(kind: .arroser, emojis: ["🥕"], accessoire: acc)
        case "recolter": return SceneSpec(kind: .recolter, emojis: [ev.detail.map { j?.emoji($0) ?? "🥕" } ?? "🥕"], accessoire: acc)
        case "niveau": return SceneSpec(kind: .niveau, resultat: ev.detail, accessoire: acc)
        default: return nil
        }
    }

    private func phrase(_ ev: FoyerEtat.Evenement) -> String {
        let plat = ev.detail.flatMap { jeu?.plat($0)?.un ?? jeu?.ingredients[$0]?.un }
        switch ev.type {
        case "nourrir": return plat.map { "Yanis m'a donné \($0) ! Miam 😋" } ?? "Yanis m'a donné à manger 😋"
        case "cuisiner": return plat.map { "Yanis a cuisiné \($0) ! C'est au frigo 🍳" } ?? "Yanis a fait à manger 🍳"
        case "calin": return "Yanis m'a fait un câlin depuis son Mac 🤗"
        case "bain": return "Yanis m'a donné le bain, je sens bon 🛁"
        case "courses": return "Yanis a fait les courses ! Regarde le placard 🧺"
        case "planter", "arroser", "recolter": return "Yanis s'est occupé du potager 🌱"
        case "habiller": return "Yanis m'a habillé ! Ça me va ? ✨"
        case "jouer": return "Yanis a joué avec moi 🫧"
        case "niveau": return "Grâce à Yanis, je passe \(ev.detail ?? "au niveau suivant") ! 🎓"
        default: return "\(ev.emoji) \(ev.texte)"
        }
    }

    func dire(_ s: String) {
        toastTask?.cancel()
        withAnimation(.snappy) { toast = s }
        toastTask = Task {
            try? await Task.sleep(for: .seconds(3.5))
            guard !Task.isCancelled else { return }
            withAnimation(.snappy) { self.toast = nil }
        }
    }
}

// MARK: - Ce que Boubou fait quand on s'occupe de lui

extension Coach {
    func ouvrirFoyer() {
        dismiss()
        UserDefaults.standard.set("boubou", forKey: "BoubouOnglet")
        AppDelegate.shared?.quick.open()
    }

    func niveau(_ nom: String, cadeau: String?) {
        onClosePanel()
        let spec = SceneSpec(kind: .niveau, resultat: nom, accessoire: Foyer.shared.etat?.accessoire)
        // après la scène en cours (le repas, la cuisine…), pas par-dessus
        let attente = max(0, (scene != nil ? 4.5 : 0))
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(attente))
            StageController.shared.jouer(spec)
            try? await Task.sleep(for: .seconds(spec.kind.duree))
            self?.finNiveau(nom, cadeau: cadeau)
        }
    }

    private func finNiveau(_ nom: String, cadeau: String?) {
        FX.shared.burst(.sparkles)
        say("Je passe \(nom) ! 🎓", footnote: cadeau.map { "Nouveau dans la garde-robe : \($0.lowercased())" },
            mood: .excited, arms: .up, autoHide: 12)
        setMood(.excited, arms: .up, for: 4)
        hop += 1
    }

    func nourrir(plat: String? = nil, ingredient: String? = nil) async {
        var p: [String: Any] = [:]
        if let plat { p["plat"] = plat } else if let ingredient { p["ingredient"] = ingredient }
        guard let r = await Foyer.shared.geste("nourrir", p), r.ok else { return }
        let j = Foyer.shared.jeu
        let nom = plat.flatMap { j?.plat($0)?.nom } ?? ingredient.flatMap { j?.ingredients[$0]?.nom } ?? ""
        // le repas se joue sur le bureau : Boubou mange pour de vrai
        onClosePanel()
        let spec = SceneSpec(kind: .repas, emojis: [j?.emoji(plat ?? ingredient ?? "") ?? "🥕"], accessoire: Foyer.shared.etat?.accessoire)
        StageController.shared.jouer(spec)
        try? await Task.sleep(for: .seconds(spec.kind.duree + 0.2))
        let texte: String, humeur: Boule.Mood
        if r.resultat?.gueri == true { texte = "Atchoum… guéri ! Merci 💛"; humeur = .excited }
        else if let d = r.resultat?.mystere, d < 0 { texte = "Hmm… c'est… spécial 😵‍💫"; humeur = .dizzy }
        else if ingredient == "citron" { texte = "Pouah, c'est acide 🍋"; humeur = .dizzy }
        else { texte = ["Miam ! \(nom) 😋", "Trop bon, \(nom.lowercased()) !", "\(nom), mon préféré 😋"].randomElement()!; humeur = .happy }
        say(texte, mood: humeur, arms: .up, autoHide: 5)
    }

    func calinFoyer() async {
        guard let r = await Foyer.shared.geste("calin"), r.ok else { return }
        setMood(.love, arms: .hug, for: 2.5); hop += 1
        FX.shared.burst(.hearts)
        Foyer.shared.dire(["Câliiin 🤗", "Je t'aime fort 💛", "Encore !"].randomElement()!)
    }

    func bain() async {
        guard let r = await Foyer.shared.geste("bain"), r.ok else { return }
        onClosePanel()
        let spec = SceneSpec(kind: .bain, accessoire: Foyer.shared.etat?.accessoire)
        StageController.shared.jouer(spec)
        try? await Task.sleep(for: .seconds(spec.kind.duree + 0.3))
        say(["Tout propre ! Je sens la lavande ✨", "Plouf ! Merci 🛁", "J'ai trouvé un canard dans le bain 🦆"].randomElement()!,
            mood: .happy, arms: .up, autoHide: 5)
    }

    func cuisiner(_ ingredients: [String]) async {
        guard let r = await Foyer.shared.geste("cuisiner", ["ingredients": ingredients]), r.ok else { return }
        onClosePanel()
        let id = r.resultat?.plat ?? "mystere"
        let plat = Foyer.shared.jeu?.plat(id)
        let j = Foyer.shared.jeu
        let spec = SceneSpec(kind: .cuisine, emojis: ingredients.map { j?.emoji($0) ?? "🥕" }, resultat: id == "mystere" ? "🫕" : plat?.emoji)
        StageController.shared.jouer(spec)
        try? await Task.sleep(for: .seconds(spec.kind.duree + 0.3))
        if id == "mystere" {
            say("Euh… j'ai inventé un plat mystère 🫕 Il est au frigo, à tes risques !", mood: .dizzy, arms: .up, autoHide: 8)
        } else if r.resultat?.nouvelle == true {
            FX.shared.burst(.confetti)
            say("Nouvelle recette : \(plat?.nom ?? id) \(plat?.emoji ?? "") ! Je la note dans le carnet.", mood: .excited, arms: .up, autoHide: 9)
        } else {
            FX.shared.burst(.sparkles)
            say("\(plat?.nom ?? "C'est prêt") \(plat?.emoji ?? "") ! C'est au frigo.", mood: .happy, arms: .up, autoHide: 6)
        }
    }

    func planter(_ i: Int, _ plante: String) async {
        guard let r = await Foyer.shared.geste("planter", ["case": i, "plante": plante]), r.ok else { return }
        hop += 1
        Foyer.shared.dire("Planté 🌱 Pense à l'arroser")
    }

    func arroser(_ i: Int) async {
        guard let r = await Foyer.shared.geste("arroser", ["case": i]), r.ok else { return }
        FX.shared.burst(.drops)
        Foyer.shared.dire("Arrosé 💧 Ça pousse plus vite")
    }

    func recolter(_ i: Int) async {
        guard let r = await Foyer.shared.geste("recolter", ["case": i]), r.ok else { return }
        let j = Foyer.shared.jeu
        let txt = (r.resultat?.recolte ?? [:]).map { "\($1) \(j?.emoji($0) ?? "")" }.joined(separator: " ")
        hop += 1
        FX.shared.burst(.sparkles)
        Foyer.shared.dire("Récolte : \(txt) 🧺")
    }

    func acheter(_ i: String) async {
        guard let r = await Foyer.shared.geste("acheter", ["ingredient": i, "n": 1]), r.ok else { return }
        Foyer.shared.dire("\(Foyer.shared.jeu?.emoji(i) ?? "") dans le placard")
    }

    func habiller(_ a: String?) async {
        guard let r = await Foyer.shared.geste("habiller", ["accessoire": a ?? NSNull()]), r.ok else { return }
        hop += 1
        setMood(.happy, arms: .up, for: 2)
        Foyer.shared.dire(a == nil ? "Juste ma blouse, sobre 🩺" : "Je suis beau ? ✨")
    }

    func carotte(doree: Bool, n: Int) {
        hop += 1
        if doree {
            FX.shared.burst(.confetti)
            say("UNE CAROTTE DORÉE ✨🥕 C'est très rare ! Garde-la pour un grand jour (ou donne-la-moi 👀)", mood: .excited, arms: .up, autoHide: 10)
        } else {
            FX.shared.burst(.sparkles)
            say(n > 1 ? "\(n) carottes ! 🥕 Dans le placard." : ["Une carotte ! 🥕 Dans le placard.", "Croc 🥕 Elle est belle celle-là !"].randomElement()!,
                mood: .happy, arms: .up, autoHide: 5)
        }
    }

    /// Un mot pour Yanis : il le recevra dans son notch. Il ne peut pas répondre par là, c'est voulu.
    func envoyerMot(_ texte: String) async -> Bool {
        guard let r = await Foyer.shared.geste("mot", ["texte": String(texte.prefix(500))]), r.ok else { return false }
        FX.shared.burst(.hearts)
        setMood(.love, arms: .hug, for: 3)
        hop += 1
        return true
    }
}

// MARK: - L'onglet Boubou du panneau

struct FoyerView: View {
    @ObservedObject var foyer = Foyer.shared
    @ObservedObject var coach = Coach.shared
    @AppStorage("BoubouSection") private var section = "potager"
    @State private var marmite: [String] = []
    @State private var carnet = false
    @AppStorage("BoubouMotBrouillon") private var mot = ""
    @State private var envoi = false
    @State private var envole = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let e = foyer.etat, let j = foyer.jeu {
                carte(e, j)
                gestes(e, j)
                onglets(e)
                Group {
                    switch section {
                    case "cuisine": cuisine(e, j)
                    case "epicerie": epicerie(e, j)
                    case "garde": garde(e, j)
                    case "journal": journal(e)
                    default: potager(e, j)
                    }
                }
                .transition(.opacity)
                .id(section)
            } else {
                HStack(spacing: 10) {
                    ProgressView().controlSize(.small)
                    Text(foyer.inscrit ? "Boubou arrive…" : "Je me connecte à la maison de Boubou…")
                        .font(.system(size: 12.5, weight: .semibold)).foregroundStyle(.white.opacity(0.5))
                }
                .frame(maxWidth: .infinity, minHeight: 80)
                .task { await foyer.rafraichir() }
            }
            motPourYanis
            if let t = foyer.toast {
                Text(t).font(.system(size: 12, weight: .bold)).foregroundStyle(.black.opacity(0.85))
                    .padding(.horizontal, 12).padding(.vertical, 7)
                    .frame(maxWidth: .infinity)
                    .background(.white, in: Capsule())
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.snappy(duration: 0.22), value: section)
        .animation(.snappy(duration: 0.22), value: carnet)
        .animation(.snappy(duration: 0.22), value: foyer.ecrire)
    }

    // MARK: Un mot pour Yanis (à sens unique : il le lit dans son notch, il ne peut pas répondre)

    private var nomYanis: String { Messages.shared.partner?.name ?? "Yanis" }

    @ViewBuilder
    private var motPourYanis: some View {
        if foyer.ecrire {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("💌 Un mot pour \(nomYanis)").font(.system(size: 12.5, weight: .bold)).foregroundStyle(.white.opacity(0.85))
                    Spacer()
                    Text("\(mot.count)/500").font(.system(size: 10, weight: .semibold).monospacedDigit())
                        .foregroundStyle(.white.opacity(mot.count > 500 ? 0.9 : 0.35))
                }
                TextEditor(text: $mot)
                    .font(.system(size: 13, weight: .medium))
                    .scrollContentBackground(.hidden)
                    .padding(6)
                    .frame(height: 74)
                    .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                HStack {
                    Text("Il le lira dans son notch.").font(.system(size: 10.5, weight: .medium)).foregroundStyle(.white.opacity(0.4))
                    Spacer()
                    Button("Annuler") { foyer.ecrire = false }.buttonStyle(PillStyle())
                    Button(envoi ? "…" : "Envoyer") { envoyer() }.buttonStyle(PillStyle(primary: true))
                        .disabled(envoi || mot.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || mot.count > 500)
                }
            }
            .padding(10)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(alignment: .topTrailing) {
                Text("💌").font(.system(size: 26))
                    .offset(x: envole ? 40 : -150, y: envole ? -120 : 40)
                    .scaleEffect(envole ? 0.5 : 1.1)
                    .rotationEffect(.degrees(envole ? 25 : -10))
                    .opacity(envole ? 0 : (envoi ? 1 : 0))
                    .allowsHitTesting(false)
            }
            .transition(.opacity.combined(with: .move(edge: .bottom)))
        } else {
            Button { foyer.ecrire = true } label: {
                HStack(spacing: 8) {
                    Text("💌").font(.system(size: 14))
                    Text(mot.isEmpty ? "Écrire un mot à \(nomYanis)" : "Reprendre ton mot pour \(nomYanis)")
                        .font(.system(size: 12, weight: .bold)).foregroundStyle(.white.opacity(0.8))
                    Spacer()
                    Image(systemName: "chevron.right").font(.system(size: 9, weight: .bold)).foregroundStyle(.white.opacity(0.35))
                }
                .padding(.horizontal, 12).padding(.vertical, 9)
                .background(Theme.card, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .contentShape(Rectangle())
            }
            .buttonStyle(PressStyle())
        }
    }

    private func envoyer() {
        let texte = mot.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !texte.isEmpty else { return }
        envoi = true
        Task {
            let ok = await coach.envoyerMot(texte)
            if ok {
                withAnimation(.easeIn(duration: 0.7)) { envole = true }
                try? await Task.sleep(for: .seconds(0.8))
                mot = ""
                foyer.ecrire = false
                foyer.dire("Envoyé 💌 \(nomYanis) le verra dans son notch")
            }
            envoi = false
            envole = false
        }
    }

    // MARK: Boubou, son niveau, ses jauges

    private func carte(_ e: FoyerEtat, _ j: FoyerJeu) -> some View {
        HStack(spacing: 12) {
            ZStack(alignment: .topTrailing) {
                Boule(mood: e.dort ? .sleepy : e.mood, size: 40, shadow: false, accessoire: e.accessoire, malade: e.malade, sale: e.stat("toilette") < 20)
                    .frame(width: 64, height: 56)
                if let b = e.besoin { Text(b).font(.system(size: 13)).offset(x: 2, y: -4) }
            }
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline) {
                    Text(e.niveau.nom).font(.system(size: 14, weight: .heavy)).foregroundStyle(.white)
                    if e.malade { Text("enrhumé").font(.system(size: 10, weight: .bold)).foregroundStyle(Theme.soft) }
                    Spacer()
                    Text("⭐ \(e.etoiles)").font(.system(size: 12, weight: .heavy).monospacedDigit()).foregroundStyle(.white.opacity(0.85))
                        .contentTransition(.numericText(value: Double(e.etoiles))).animation(.snappy, value: e.etoiles)
                        .help("Gagne des étoiles en cochant ta liste")
                }
                if let s = e.niveau.suivant {
                    barre(Double(e.xp - e.niveau.xp) / Double(max(1, s.xp - e.niveau.xp)), couleur: Color(red: 1, green: 0.82, blue: 0.4))
                        .help("Encore \(s.xp - e.xp) pour passer \(s.nom)")
                }
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible())], spacing: 5) {
                    jauge("🍽️", e.stat("ventre"), "Ventre"); jauge("❤️", e.stat("calins"), "Câlins")
                    jauge("🛁", e.stat("toilette"), "Toilette"); jauge("⚡", e.stat("energie"), "Énergie")
                }
            }
        }
        .padding(10)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .modifier(Relief(force: 6))
    }

    private func jauge(_ icone: String, _ v: Int, _ nom: String) -> some View {
        HStack(spacing: 5) {
            Text(icone).font(.system(size: 10))
            barre(Double(v) / 100, couleur: v < 25 ? Theme.soft : Theme.done)
        }
        .help("\(nom) : \(v) %")
    }

    private func barre(_ p: Double, couleur: Color) -> some View {
        GeometryReader { g in
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.08))
                Capsule().fill(couleur).frame(width: max(4, g.size.width * min(1, max(0, p))))
            }
        }
        .frame(height: 5)
        .animation(.spring(response: 0.5, dampingFraction: 0.8), value: p)
    }

    // MARK: Les gestes

    private func gestes(_ e: FoyerEtat, _ j: FoyerJeu) -> some View {
        let plats = j.trie(e.frigo.keys.filter { (e.frigo[$0] ?? 0) > 0 })
        let crus = j.trie(e.inventaire.keys.filter { (e.inventaire[$0] ?? 0) > 0 && j.cru?[$0] != nil })
        return HStack(spacing: 6) {
            Menu {
                if plats.isEmpty && crus.isEmpty { Text("Le frigo est vide : cuisine ou ramasse des carottes") }
                if !plats.isEmpty {
                    Section("Le frigo") {
                        ForEach(plats, id: \.self) { p in
                            Button("\(j.emoji(p))  \(j.plat(p)?.nom ?? p) ×\(e.frigo[p] ?? 0)") { Task { await coach.nourrir(plat: p) } }
                        }
                    }
                }
                if !crus.isEmpty {
                    Section("Tel quel") {
                        ForEach(crus, id: \.self) { i in
                            Button("\(j.emoji(i))  \(j.ingredients[i]?.nom ?? i) ×\(e.inventaire[i] ?? 0)") { Task { await coach.nourrir(ingredient: i) } }
                        }
                    }
                }
            } label: { chipLabel("fork.knife", "Nourrir") }
            .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden)
            chip("heart.fill", "Câlin") { Task { await coach.calinFoyer() } }
            chip("bathtub.fill", "Bain") { Task { await coach.bain() } }
            chip("bubbles.and.sparkles", "Jouer") { coach.onClosePanel(); BubbleGame.shared.start() }
            chip(e.dort ? "sun.max.fill" : "moon.zzz.fill", e.dort ? "Réveil" : "Dodo") {
                if coach.sleeping { coach.wake() } else { coach.onClosePanel(); coach.sleep() }
            }
        }
        .disabled(false)
    }

    private func chipLabel(_ icon: String, _ label: String) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon).font(.system(size: 13, weight: .semibold))
            Text(label).font(.system(size: 10.5, weight: .bold)).lineLimit(1)
        }
        .foregroundStyle(.white.opacity(0.85))
        .frame(maxWidth: .infinity).padding(.vertical, 8)
        .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
        .contentShape(Rectangle())
        .modifier(Relief(force: 16))
    }

    private func chip(_ icon: String, _ label: String, _ run: @escaping () -> Void) -> some View {
        Button(action: run) { chipLabel(icon, label) }.buttonStyle(PressStyle())
    }

    // MARK: Les sous-onglets

    private func onglets(_ e: FoyerEtat) -> some View {
        let pret = e.potager.contains { $0?.prete == true }
        let items: [(String, String, String)] = [("potager", "🌱", "Potager"), ("cuisine", "🍳", "Cuisine"), ("epicerie", "🧺", "Épicerie"),
                                                 ("garde", "🎀", "Garde-robe"), ("journal", "📖", "Journal")]
        return HStack(spacing: 4) {
            ForEach(items, id: \.0) { id, emoji, nom in
                Button { section = id } label: {
                    HStack(spacing: 3) {
                        Text(emoji).font(.system(size: 11))
                        if section == id { Text(nom).font(.system(size: 10.5, weight: .bold)).lineLimit(1) }
                    }
                    .foregroundStyle(section == id ? .black : .white.opacity(0.7))
                    .padding(.horizontal, section == id ? 9 : 7).padding(.vertical, 5)
                    .background(section == id ? Color.white : Color.white.opacity(0.06), in: Capsule())
                    .overlay(alignment: .topTrailing) {
                        if id == "potager" && pret && section != id { Circle().fill(Theme.done).frame(width: 6, height: 6).offset(x: 1, y: -1) }
                    }
                }
                .buttonStyle(PressStyle()).help(nom)
            }
            Spacer(minLength: 0)
        }
    }

    // MARK: Potager

    private func potager(_ e: FoyerEtat, _ j: FoyerJeu) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            TimelineView(.periodic(from: .now, by: 30)) { _ in
                let now = foyer.maintenant
                JardinInteractif(
                    cases: e.potager.map { c in
                        c.map { c in
                            let fait = min(1, max(0, (now - c.plantee) / max(1, c.fin - c.plantee)))
                            return CaseJardin(emoji: j.emoji(c.plante), pousse: fait, arrosee: c.arrosee, prete: c.prete || fait >= 1,
                                              reste: duree((c.fin - now) / 60000))
                        }
                    },
                    graines: j.trie(j.plantes.keys).map { Graine(id: $0, emoji: j.emoji($0), duree: duree((j.plantes[$0]?.heures ?? 1) * 60)) },
                    width: 312, height: 196,
                    planter: { i, p in Task { await coach.planter(i, p) } },
                    arroser: { i in Task { await coach.arroser(i) } },
                    recolter: { i in Task { await coach.recolter(i) } })
            }
            let reste = (e.prochainRamassage - foyer.maintenant) / 60000
            Text(reste <= 0 ? "🥕 Une carotte sauvage peut pousser à côté de moi, garde l'œil ouvert !"
                            : "🥕 Prochaine carotte sauvage dans \(duree(reste))")
                .font(.system(size: 11, weight: .medium)).foregroundStyle(.white.opacity(0.45))
        }
    }

    private func duree(_ minutes: Double) -> String {
        let m = max(1, Int(minutes.rounded(.up)))
        return m < 60 ? "\(m) min" : m % 60 == 0 ? "\(m / 60) h" : "\(m / 60) h \(String(format: "%02d", m % 60))"
    }

    // MARK: Cuisine

    private func cuisine(_ e: FoyerEtat, _ j: FoyerJeu) -> some View {
        let dispo = j.trie(e.inventaire.keys.filter { (e.inventaire[$0] ?? 0) > 0 && $0 != "carotte_doree" })
        let plats = j.trie(e.frigo.keys.filter { (e.frigo[$0] ?? 0) > 0 })
        return VStack(alignment: .leading, spacing: 9) {
            CuisineInteractive(
                ingredients: dispo.map { i in
                    IngredientDispo(id: i, emoji: j.emoji(i), nom: j.ingredients[i]?.nom ?? i,
                                    n: (e.inventaire[i] ?? 0) - marmite.filter { $0 == i }.count)
                },
                marmite: $marmite, emoji: { j.emoji($0) }, width: 312, height: 178,
                cuisiner: {
                    let liste = marmite
                    marmite = []
                    Task { await coach.cuisiner(liste) }
                })
            .padding(.vertical, 2)

            if !plats.isEmpty {
                HStack(spacing: 6) {
                    Text("Frigo").font(.system(size: 11, weight: .bold)).foregroundStyle(.white.opacity(0.45))
                    ForEach(plats, id: \.self) { p in
                        Button { Task { await coach.nourrir(plat: p) } } label: {
                            Text("\(j.emoji(p))\((e.frigo[p] ?? 0) > 1 ? " ×\(e.frigo[p]!)" : "")")
                                .font(.system(size: 13, weight: .bold)).foregroundStyle(.white.opacity(0.85))
                                .padding(.horizontal, 7).padding(.vertical, 3).background(.white.opacity(0.08), in: Capsule())
                        }
                        .buttonStyle(PressStyle()).help("Donner \(j.plat(p)?.un ?? j.plat(p)?.nom ?? p) à Boubou")
                    }
                    Spacer(minLength: 0)
                }
            }

            Button { carnet.toggle() } label: {
                HStack {
                    Text("📖 Carnet de recettes").font(.system(size: 11.5, weight: .bold))
                    Text("\(e.recettes.count)/\(j.recettes.count)").font(.system(size: 11, weight: .heavy)).foregroundStyle(.white.opacity(0.5))
                    Spacer()
                    Image(systemName: carnet ? "chevron.up" : "chevron.down").font(.system(size: 9, weight: .bold))
                }
                .foregroundStyle(.white.opacity(0.7)).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if carnet {
                ScrollView {
                    VStack(alignment: .leading, spacing: 5) {
                        ForEach(j.recettes) { r in
                            let connu = e.recettes.contains(r.id)
                            let ings = (r.ingredients ?? [:]).flatMap { k, n in Array(repeating: k, count: n) }
                            HStack(spacing: 8) {
                                Text(connu ? r.emoji : "❓").font(.system(size: 14)).frame(width: 20)
                                Text(connu ? r.nom : "Recette secrète").font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(.white.opacity(connu ? 0.9 : 0.4))
                                if r.soigne == true && connu { Text("soigne").font(.system(size: 9, weight: .bold)).foregroundStyle(Theme.done) }
                                Spacer()
                                Text(connu ? j.trie(ings).map { j.emoji($0) }.joined()
                                           : "\(ings.count) ingr. dont \(j.emoji(j.trie(ings).first ?? ""))")
                                    .font(.system(size: 11)).foregroundStyle(.white.opacity(0.55))
                            }
                        }
                    }
                }
                .frame(maxHeight: 150)
            }
        }
    }

    // MARK: Épicerie

    private func epicerie(_ e: FoyerEtat, _ j: FoyerJeu) -> some View {
        let rayon = j.trie(j.ingredients.keys.filter { j.ingredients[$0]?.prix != nil })
        return VStack(alignment: .leading, spacing: 8) {
            Text("Tes étoiles se gagnent en cochant ta liste : tâche +2, révision +3, focus +3, défi +2, bulles et respiration +1.")
                .font(.system(size: 11, weight: .medium)).foregroundStyle(.white.opacity(0.45))
                .fixedSize(horizontal: false, vertical: true)
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 6), GridItem(.flexible())], spacing: 6) {
                ForEach(rayon, id: \.self) { i in
                    let prix = j.ingredients[i]?.prix ?? 0
                    Button { Task { await coach.acheter(i) } } label: {
                        HStack(spacing: 6) {
                            Text(j.emoji(i)).font(.system(size: 15))
                            Text(j.ingredients[i]?.nom ?? i).font(.system(size: 11.5, weight: .semibold)).foregroundStyle(.white.opacity(0.85)).lineLimit(1)
                            Spacer(minLength: 0)
                            Text("\(prix)⭐").font(.system(size: 11, weight: .heavy)).foregroundStyle(.white.opacity(e.etoiles >= prix ? 0.85 : 0.3))
                        }
                        .padding(.horizontal, 9).padding(.vertical, 7)
                        .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                    .buttonStyle(PressStyle()).disabled(e.etoiles < prix).opacity(e.etoiles < prix ? 0.5 : 1)
                }
            }
            Text(e.coursesFaites ? "🛒 Yanis a déjà fait les courses aujourd'hui" : "🛒 Yanis peut faire les courses une fois par jour depuis son notch")
                .font(.system(size: 11, weight: .medium)).foregroundStyle(.white.opacity(0.45))
        }
    }

    // MARK: Garde-robe

    private func garde(_ e: FoyerEtat, _ j: FoyerJeu) -> some View {
        let ids = j.accessoires.keys.sorted { (j.accessoires[$0]?.niveau ?? 9, $0) < (j.accessoires[$1]?.niveau ?? 9, $1) }
        return LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 4), spacing: 6) {
            vetement(nil, nom: "Blouse", ouvert: true, porte: e.accessoire == nil, j: j)
            ForEach(ids, id: \.self) { a in
                vetement(a, nom: j.accessoires[a]?.nom ?? a, ouvert: e.accessoires.contains(a), porte: e.accessoire == a, j: j)
            }
        }
    }

    private func vetement(_ a: String?, nom: String, ouvert: Bool, porte: Bool, j: FoyerJeu) -> some View {
        let niveau = a.flatMap { j.accessoires[$0]?.niveau }.flatMap { n in j.niveaux.first { $0.n == n }?.nom } ?? ""
        return Button { Task { await coach.habiller(a) } } label: {
            VStack(spacing: 2) {
                Boule(mood: .happy, size: 26, shadow: false, accessoire: a).frame(width: 44, height: 38)
                    .opacity(ouvert ? 1 : 0.25)
                    .overlay { if !ouvert { Image(systemName: "lock.fill").font(.system(size: 11)).foregroundStyle(.white.opacity(0.6)) } }
                Text(ouvert ? nom : niveau).font(.system(size: 9, weight: .bold)).lineLimit(1).minimumScaleFactor(0.7)
                    .foregroundStyle(.white.opacity(ouvert ? 0.75 : 0.35))
            }
            .frame(maxWidth: .infinity).padding(.vertical, 5)
            .background(.white.opacity(porte ? 0.14 : 0.05), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(porte ? Theme.done : .clear, lineWidth: 1.5))
        }
        .buttonStyle(PressStyle()).disabled(!ouvert)
        .modifier(Relief(force: 16))
        .help(ouvert ? nom : "Débloqué quand Boubou passe \(niveau)")
    }

    // MARK: Journal à deux

    private func journal(_ e: FoyerEtat) -> some View {
        let f = RelativeDateTimeFormatter(); f.locale = Locale(identifier: "fr_FR"); f.unitsStyle = .short
        return ScrollView {
            VStack(alignment: .leading, spacing: 6) {
                if e.journal.isEmpty {
                    Text("Rien encore. Chaque geste de toi ou de Yanis s'écrira ici.").font(.system(size: 11.5)).foregroundStyle(.white.opacity(0.45))
                }
                ForEach(e.journal.prefix(15)) { ev in
                    HStack(alignment: .top, spacing: 8) {
                        Text(ev.emoji).font(.system(size: 13)).frame(width: 18)
                        Text(ev.texte).font(.system(size: 12, weight: .medium))
                            .foregroundStyle(ev.qui == "yanis" ? Theme.done : .white.opacity(0.85))
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 4)
                        Text(f.localizedString(for: Date(timeIntervalSince1970: ev.quand / 1000), relativeTo: Date()))
                            .font(.system(size: 10, weight: .medium)).foregroundStyle(.white.opacity(0.35))
                    }
                }
            }
        }
        .frame(maxHeight: 210)
        .fixedSize(horizontal: false, vertical: true)
    }
}

// MARK: - La carotte sauvage, qui pousse à côté de Boubou sur le bureau

@MainActor
final class CarrotController {
    static let shared = CarrotController()
    weak var mascot: MascotController?
    private var panel: FloatingPanel?
    private var hideTask: Task<Void, Never>?
    var visible: Bool { panel?.isVisible == true }

    func show() {
        guard !visible, let m = mascot else { return }
        let size = NSSize(width: 46, height: 52)
        let p = panel ?? FloatingPanel(size: size)
        panel = p
        let model = CarrotModel()
        let host = NSHostingView(rootView: CarrotButton(model: model) { [weak self] in self?.pull(model) })
        host.frame = NSRect(origin: .zero, size: size)
        p.contentView = host
        let b = m.bodyFrame, right = Store.shared.settings.corner.right
        p.setFrame(NSRect(x: right ? b.minX - size.width - 2 : b.maxX + 2, y: b.minY - 2, width: size.width, height: size.height), display: true)
        p.alphaValue = 0
        p.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { $0.duration = 0.3; p.animator().alphaValue = 1 }
        Coach.shared.setMood(.curious, arms: .rest, for: 3)
        hideTask?.cancel()
        hideTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(15 * 60))
            guard !Task.isCancelled else { return }
            self?.hide()
        }
    }

    private func pull(_ model: CarrotModel) {
        guard !model.arrachee else { return }
        model.arrachee = true
        hideTask?.cancel()
        Task {
            let r = await Foyer.shared.geste("ramasser")
            let doree = r?.resultat?.recolte?["carotte_doree"] != nil
            model.doree = doree
            if r?.ok == true {
                let n = r?.resultat?.recolte?.values.first ?? 1
                Coach.shared.carotte(doree: doree, n: n)
            }
            try? await Task.sleep(for: .seconds(1.1))
            self.hide()
        }
    }

    func hide() {
        guard let p = panel, p.isVisible else { return }
        NSAnimationContext.runAnimationGroup({ $0.duration = 0.25; p.animator().alphaValue = 0 }) {
            MainActor.assumeIsolated { p.orderOut(nil) }
        }
    }
}

@MainActor final class CarrotModel: ObservableObject {
    @Published var arrachee = false
    @Published var doree = false
}

private struct CarrotButton: View {
    @ObservedObject var model: CarrotModel
    var pull: () -> Void
    var body: some View {
        CarrotSprout(size: 40, arrachee: model.arrachee, doree: model.doree)
            .frame(width: 46, height: 52, alignment: .bottom)
            .contentShape(Rectangle())
            .onTapGesture { pull() }
            .help("Une carotte ! Clique pour l'arracher")
    }
}

// MARK: - Aperçu hors écran (captures de l'onglet Boubou)

enum FoyerApercu {
    @MainActor static func run(etat: URL, jeu: URL, to dir: URL) throws {
        _ = NSApplication.shared
        let e = try JSONDecoder().decode(FoyerEtat.self, from: Data(contentsOf: etat))
        let j = try JSONDecoder().decode(FoyerJeu.self, from: Data(contentsOf: jeu))
        Foyer.shared.injecter(etat: e, jeu: j)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        UserDefaults.standard.set("boubou", forKey: "BoubouOnglet")
        for (section, ecrire) in [("potager", false), ("cuisine", false), ("epicerie", false), ("garde", false), ("journal", false), ("potager", true)] {
            UserDefaults.standard.set(section, forKey: "BoubouSection")
            Foyer.shared.ecrire = ecrire
            let host = NSHostingView(rootView: QuickPanel().padding(10).background(Color(white: 0.3)))
            let w = NSWindow(contentRect: NSRect(x: -3000, y: 0, width: 364, height: 900), styleMask: [.borderless], backing: .buffered, defer: false)
            w.contentView = host
            host.layoutSubtreeIfNeeded()
            let size = host.fittingSize
            w.setContentSize(size); host.frame = NSRect(origin: .zero, size: size)
            w.orderFrontRegardless()
            RunLoop.main.run(until: Date().addingTimeInterval(0.6))
            host.layoutSubtreeIfNeeded()
            guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { continue }
            host.cacheDisplay(in: host.bounds, to: rep)
            try rep.representation(using: .png, properties: [:])?.write(to: dir.appendingPathComponent("\(section)\(ecrire ? "-mot" : "").png"))
            w.orderOut(nil)
        }
        // et la mascotte telle qu'elle apparaît sur le bureau
        let r = ImageRenderer(content: HStack(spacing: 18) {
            Boule(mood: e.mood, size: 46, accessoire: e.accessoire, malade: e.malade, sale: e.stat("toilette") < 20)
            Boule(mood: .worried, size: 46, accessoire: "echarpe", malade: true)
            Boule(mood: .worried, size: 46, sale: true)
            BathView(size: 96); PotView(size: 92); CarrotSprout(size: 40, arrachee: false, doree: false)
        }.padding(20).background(Color(white: 0.85)))
        r.scale = 2
        if let img = r.nsImage, let t = img.tiffRepresentation, let b = NSBitmapImageRep(data: t) {
            try b.representation(using: .png, properties: [:])?.write(to: dir.appendingPathComponent("mascotte.png"))
        }
    }
}

// MARK: - Essai du client contre un serveur local (`BOUBOU_API=http://127.0.0.1:3083 Boubou essai-foyer`)

enum FoyerEssai {
    @MainActor static func run() async -> Bool {
        guard let api = ProcessInfo.processInfo.environment["BOUBOU_API"], api.contains("127.0.0.1") else {
            print("BOUBOU_API doit pointer vers un serveur local"); return false
        }
        Link.desactive = true
        let f = Foyer.shared
        await f.rafraichir()
        guard f.inscrit, let j = f.jeu, f.etat != nil else { print("inscription/lecture KO"); return false }
        print("inscrit, jeu: \(j.recettes.count) recettes, niveau \(f.etat!.niveau.nom)")
        var ok = true
        func essai(_ t: String, _ p: [String: Any] = [:], attendu: Bool = true) async -> FoyerReponse? {
            let r = await f.geste(t, p)
            let bon = (r?.ok ?? false) == attendu
            if !bon { ok = false }
            print("\(bon ? "✓" : "✗") \(t) \(p) → ok=\(r?.ok as Any) \(r?.erreur ?? "")")
            return r
        }
        for raison in ["tache", "revision", "focus", "defi"] { _ = await essai("etoiles", ["raison": raison]) }
        _ = await essai("acheter", ["ingredient": "farine", "n": 1])
        _ = await essai("acheter", ["ingredient": "oeuf", "n": 1])
        _ = await essai("acheter", ["ingredient": "lait", "n": 1])
        let c = await essai("cuisiner", ["ingredients": ["farine", "oeuf", "lait"]])
        print("  plat=\(c?.resultat?.plat ?? "-") nouvelle=\(c?.resultat?.nouvelle as Any)")
        _ = await essai("nourrir", ["plat": "crepes"])
        _ = await essai("calin"); _ = await essai("bain")
        _ = await essai("jouer", ["score": 30])
        _ = await essai("planter", ["case": 0, "plante": "carotte"])
        _ = await essai("arroser", ["case": 0])
        _ = await essai("recolter", ["case": 0], attendu: false)
        _ = await essai("ramasser")
        _ = await essai("habiller", ["accessoire": "toque"])
        _ = await essai("habiller", ["accessoire": NSNull()])
        _ = await essai("mot", ["texte": "Coucou depuis l'essai 💌"])
        _ = await essai("courses", attendu: false)
        // jusqu'au passage de niveau : beaucoup de câlins
        var passage: FoyerReponse.Passage?
        for _ in 0..<40 where passage == nil {
            if let r = await f.geste("calin"), let n = r.resultat?.niveau { passage = n }
        }
        print(passage.map { "✓ passage de niveau décodé : \($0.nom), cadeau \($0.cadeau ?? "-")" } ?? "✗ pas de passage de niveau")
        if passage == nil { ok = false }
        _ = await essai("dodo"); _ = await essai("nourrir", ["ingredient": "carotte"], attendu: false); _ = await essai("reveil")
        print("journal[0] = \(f.etat?.journal.first?.texte ?? "-") ; mots = \(f.etat?.mots.count ?? 0)")
        return ok
    }
}

// MARK: - Relief : la carte penche vers la souris, comme une vraie carte en 3D

struct Relief: ViewModifier {
    var force: Double = 8
    @State private var pos: CGPoint?
    @State private var taille: CGSize = .zero

    func body(content: Content) -> some View {
        let dx = pos.map { Double($0.x / max(1, taille.width)) - 0.5 } ?? 0
        let dy = pos.map { Double($0.y / max(1, taille.height)) - 0.5 } ?? 0
        content
            .rotation3DEffect(.degrees(-dy * force), axis: (x: 1, y: 0, z: 0), perspective: 0.5)
            .rotation3DEffect(.degrees(dx * force), axis: (x: 0, y: 1, z: 0), perspective: 0.5)
            .scaleEffect(pos == nil ? 1 : 1.025)
            .shadow(color: .black.opacity(pos == nil ? 0 : 0.35), radius: pos == nil ? 0 : 8, x: -dx * 6, y: 4 - dy * 4)
            .background(GeometryReader { g in Color.clear.onAppear { taille = g.size }.onChange(of: g.size) { _, n in taille = n } })
            .onContinuousHover { phase in
                switch phase {
                case .active(let p): pos = p
                case .ended: pos = nil
                }
            }
            .animation(.spring(response: 0.35, dampingFraction: 0.7), value: pos)
    }
}

// MARK: - La scène qui flotte à côté de Boubou sur le bureau

@MainActor
final class StageController {
    static let shared = StageController()
    weak var mascot: MascotController?
    private var panel: FloatingPanel?
    private var fin: Task<Void, Never>?
    static let largeur: CGFloat = 290

    /// Joue une scène ; Boubou quitte son coin le temps de la scène et y revient après.
    func jouer(_ spec: SceneSpec) {
        guard let m = mascot else { return }
        let w = Self.largeur, size = NSSize(width: w, height: w * SceneFrame.ratio)
        let p = panel ?? FloatingPanel(size: size)
        panel = p
        p.ignoresMouseEvents = true
        let host = NSHostingView(rootView: SceneAnimee(spec: spec, width: w))
        host.frame = NSRect(origin: .zero, size: size)
        p.contentView = host
        let f = m.panel.frame, c = Store.shared.settings.corner
        var o = NSPoint(x: c.right ? f.maxX - size.width : f.minX, y: c.bottom ? f.minY : f.maxY - size.height)
        if let v = (m.panel.screen ?? NSScreen.main)?.visibleFrame {
            o.x = min(max(o.x, v.minX), v.maxX - size.width)
            o.y = min(max(o.y, v.minY), v.maxY - size.height)
        }
        p.setFrame(NSRect(origin: o, size: size), display: true)
        p.alphaValue = 1
        p.orderFrontRegardless()
        withAnimation(.easeOut(duration: 0.2)) { Coach.shared.scene = spec.kind.rawValue }
        fin?.cancel()
        fin = Task { [weak self] in
            try? await Task.sleep(for: .seconds(spec.kind.duree))
            guard !Task.isCancelled else { return }
            self?.panel?.orderOut(nil)
            withAnimation(.spring(response: 0.45, dampingFraction: 0.7)) { Coach.shared.scene = nil }
            Coach.shared.hop += 1
        }
    }
}
