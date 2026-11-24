import Foundation

/// Le fil entre Boubou (chez Jeanne) et l'OsaNotch de Yanis, par le relais « Amis » du serveur
/// OsaDrop (socket.io) : Boubou écoute sur son propre code à 6 chiffres et écrit au code de Yanis
/// (champ « lien » de messages.json). Messages :
///   → OsaNotch : mochi_hello {code, name, foyer} (appairage automatique + secret du foyer), mochi_pense {code, name}
///   ↔ boubou_maj {code, name, quoi} : « l'état du foyer a changé, relis-le » (voir boubou-site/docs/foyer.md)
///   ← OsaNotch : notch_love {name}, notch_hello {name}
/// Un message qui n'a pas pu partir (Mac de Yanis éteint) repart quand son OsaNotch se reconnecte.
@MainActor
final class Link: NSObject, URLSessionWebSocketDelegate {
    static let shared = Link()

    private static let url = URL(string: "wss://osadrop.osalabs.fr/socket.io/?EIO=4&transport=websocket")!
    let myCode: String
    private var session: URLSession!
    private var task: URLSessionWebSocketTask?
    private var connected = false
    private var retry: TimeInterval = 2
    private var ackID = 0
    private var acks: [Int: (Bool) -> Void] = [:]
    private var pendingThought: Date? {
        get { UserDefaults.standard.object(forKey: "BoubouPenseEnAttente") as? Date }
        set { UserDefaults.standard.set(newValue, forKey: "BoubouPenseEnAttente") }
    }
    private var lastLove = Date.distantPast
    /// Pour `Boubou essai-foyer` : ne jamais parler au vrai OsaNotch de Yanis.
    static var desactive = false
    var onLove: (String) -> Void = { _ in }

    override init() {
        if let c = UserDefaults.standard.string(forKey: "BoubouCode"), c.count == 6 { myCode = c }
        else { myCode = String(Int.random(in: 100000...999999)); UserDefaults.standard.set(myCode, forKey: "BoubouCode") }
        super.init()
        session = URLSession(configuration: .default, delegate: self, delegateQueue: .main)
    }

    func start() {
        guard !Self.desactive else { return }
        connect()
        // Un message en attente (Mac de Yanis éteint) : on réessaie toutes les 2 minutes.
        Timer.scheduledTimer(withTimeInterval: 120, repeats: true) { _ in
            MainActor.assumeIsolated { Link.shared.flush() }
        }
    }

    private var partner: (code: String, name: String)? { Messages.shared.partner }
    private var name: String { Store.shared.name.isEmpty ? "Jeanne" : Store.shared.name }

    /// Elle a secoué Boubou : « Jeanne pense à vous » dans l'OsaNotch de Yanis.
    func sendThought(done: @escaping (Bool) -> Void) {
        guard let p = partner else { return done(false) }
        send(to: p.code, ["type": "mochi_pense", "name": name, "code": myCode]) { [weak self] ok in
            if !ok { self?.pendingThought = Date() }
            done(ok)
        }
    }

    private func flush() {
        guard let t = pendingThought else { return }
        // au-delà de 12 h, le message n'a plus de sens
        if Date().timeIntervalSince(t) > 12 * 3600 { pendingThought = nil; return }
        guard let p = partner else { return }
        send(to: p.code, ["type": "mochi_pense", "name": name, "code": myCode]) { [weak self] ok in
            if ok { self?.pendingThought = nil }
        }
    }

    private func received(_ d: [String: Any]) {
        guard let type = d["type"] as? String else { return }
        switch type {
        case "notch_love":
            // pas plus d'une animation toutes les 4 s, même s'il clique comme un fou
            guard Date().timeIntervalSince(lastLove) > 4 else { return }
            lastLove = Date()
            onLove(String((d["name"] as? String ?? partner?.name ?? "Yanis").prefix(30)))
        case "notch_hello":
            hello(); flush()
        case "boubou_maj":
            Task { await Foyer.shared.rafraichir() }
        default: break
        }
    }

    private func hello() {
        guard let p = partner else { return }
        var m = ["type": "mochi_hello", "name": name, "code": myCode]
        // le secret du foyer, seulement une fois que le serveur l'a accepté
        if Foyer.shared.inscrit { m["foyer"] = Foyer.shared.secret }
        send(to: p.code, m) { _ in }
    }

    /// Le foyer vient d'être inscrit : on redonne le secret à OsaNotch.
    func helloFoyer() { if connected { hello() } }

    /// Un geste de Jeanne : l'OsaNotch de Yanis relit l'état tout de suite (sinon il le verra au prochain passage).
    func nudge(_ quoi: String) {
        guard let p = partner else { return }
        send(to: p.code, ["type": "boubou_maj", "name": name, "code": myCode, "quoi": quoi]) { _ in }
    }

    // MARK: socket.io minimal (Engine.IO v4), comme FriendBridge d'OsaNotch

    private func connect() {
        task?.cancel(with: .goingAway, reason: nil)
        connected = false
        let t = session.webSocketTask(with: Self.url)
        task = t
        t.resume()
        listen(t)
    }

    private func listen(_ t: URLSessionWebSocketTask) {
        t.receive { [weak self] result in
            DispatchQueue.main.async {
                guard let self, t === self.task else { return }
                switch result {
                case .success(.string(let s)): self.handle(s); self.listen(t)
                case .success: self.listen(t)
                case .failure: self.dropped()
                }
            }
        }
    }

    private func handle(_ s: String) {
        guard let kind = s.first else { return }
        switch kind {
        case "0": raw("40")
        case "2": raw("3")
        case "4": packet(String(s.dropFirst()))
        default: break
        }
    }

    private func packet(_ p: String) {
        guard let kind = p.first else { return }
        let rest = p.dropFirst()
        switch kind {
        case "0":
            connected = true; retry = 2
            emit(["friend-listen", myCode])
            hello(); flush()
        case "2":
            guard let arr = json(String(rest.drop(while: \.isNumber))) as? [Any],
                  arr.first as? String == "friend-msg", let msg = arr.dropFirst().first as? [String: Any] else { return }
            received(msg)
        case "3":
            let id = Int(String(rest.prefix(while: \.isNumber))) ?? -1
            let args = json(String(rest.drop(while: \.isNumber))) as? [Any]
            acks.removeValue(forKey: id)?(args?.first as? Bool ?? false)
        case "4": dropped()
        default: break
        }
    }

    private func send(to code: String, _ msg: [String: String], done: @escaping (Bool) -> Void) {
        if Self.desactive { return done(false) }
        guard connected else {
            if task == nil { connect() }
            return done(false)
        }
        ackID += 1
        let id = ackID
        acks[id] = done
        emit(["friend-send", ["to": code, "msg": msg]], ack: id)
        DispatchQueue.main.asyncAfter(deadline: .now() + 6) { [weak self] in self?.acks.removeValue(forKey: id)?(false) }
    }

    private func emit(_ items: [Any], ack: Int? = nil) {
        guard let d = try? JSONSerialization.data(withJSONObject: items), let s = String(data: d, encoding: .utf8) else { return }
        raw("42" + (ack.map(String.init) ?? "") + s)
    }

    private func raw(_ s: String) {
        task?.send(.string(s)) { [weak self] err in
            if err != nil { DispatchQueue.main.async { self?.dropped() } }
        }
    }

    private func json(_ s: String) -> Any? { s.data(using: .utf8).flatMap { try? JSONSerialization.jsonObject(with: $0) } }

    private func dropped() {
        connected = false
        acks.values.forEach { $0(false) }; acks.removeAll()
        task?.cancel(); task = nil
        DispatchQueue.main.asyncAfter(deadline: .now() + retry) { [weak self] in self?.connect() }
        retry = min(retry * 2, 60)
    }

    nonisolated func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didCloseWith closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) {
        DispatchQueue.main.async { [weak self] in
            if webSocketTask === self?.task { self?.dropped() }
        }
    }
}
