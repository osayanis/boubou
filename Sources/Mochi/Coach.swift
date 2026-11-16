import SwiftUI
import AppKit

struct BubbleAction: Identifiable {
    let id = UUID()
    var title: String
    var primary = false
    var run: () -> Void
}

/// Une bulle de Mochi : un texte, éventuellement une liste, des boutons.
struct BubbleModel: Identifiable {
    var id = UUID()
    var text: String
    var lines: [String] = []
    var footnote: String? = nil
    var actions: [BubbleAction] = []
    var autoHide: Double? = nil
}

/// Le cerveau : décide quand Mochi parle (visite du matin, « ça va ? », petits mots, bilan du soir,
/// « va dormir »), comment il bouge (petites animations quand on ne s'occupe pas de lui) et ce qu'il
/// répond quand on joue avec lui (caresse, secousse, lit, focus, étirements, bulles, eau).
@MainActor
final class Coach: ObservableObject {
    static let shared = Coach()

    @Published var bubble: BubbleModel?
    @Published var mood: Boule.Mood = .calm
    @Published var arms: Boule.Arms = .rest
    @Published var hop = 0
    @Published var breath: CGFloat = 0
    @Published var tilt: Double = 0
    @Published var look: CGSize = .zero
    /// Regard « joué » par une animation (prioritaire sur la souris pendant un instant).
    @Published var idleLook: CGSize? = nil
    @Published var hiddenUntil: Date? = nil
    @Published var sleeping = false
    @Published var focusUntil: Date? = nil

    var panelOpen = false
    var onTogglePanel: () -> Void = {}
    var onClosePanel: () -> Void = {}

    private let store = Store.shared
    private let msg = Messages.shared
    private var timer: Timer?
    private var hideTask: Task<Void, Never>?
    private var moodTask: Task<Void, Never>?
    private var sessionTask: Task<Void, Never>?
    private var pauseTask: Task<Void, Never>?
    private var focusTask: Task<Void, Never>?
    private var nextContact: Date = .distantPast
    private var nextIdle = Date().addingTimeInterval(90)
    private let launched = Date()
    private var lastShake = Date.distantPast
    private var loveWhileAsleep = false

    var hidden: Bool { (hiddenUntil ?? .distantPast) > Date() }
    var inSession: Bool { sessionTask != nil }
    var focusing: Bool { (focusUntil ?? .distantPast) > Date() }
    var hat: Bool { msg.eventToday?.party == true }

    func start() {
        sleeping = store.data.sleepingSince != nil
        planNext(from: store.data.lastContact ?? Date().addingTimeInterval(-3600))
        timer = Timer.scheduledTimer(withTimeInterval: 20, repeats: true) { _ in
            MainActor.assumeIsolated { Coach.shared.tick() }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { self.tick() }
    }

    private func planNext(from date: Date) {
        nextContact = date.addingTimeInterval(store.settings.rhythm.minutes * 60 * Double.random(in: 0.8...1.2))
    }

    // MARK: L'horloge (toutes les 20 s)

    func tick() {
        if let h = hiddenUntil, h <= Date() { hiddenUntil = nil }
        store.rollOver()
        let now = Date(), cal = Calendar.current
        let hour = cal.component(.hour, from: now), minute = cal.component(.minute, from: now)

        // Endormi la veille : il se réveille tout seul à 5 h pour la visite du matin.
        if sleeping, let since = store.data.sleepingSince,
           let five = cal.date(bySettingHour: 5, minute: 0, second: 0, of: now), since < five, now >= five {
            wake(silent: true)
        }
        guard store.settings.onboarded else {
            if bubble == nil, !panelOpen { onboarding() }
            return
        }
        guard bubble == nil, !inSession, !hidden, !sleeping, !focusing, !panelOpen, !BubbleGame.shared.running,
              Presence.here, !Presence.busy else { return }

        let today = Day.key(), s = store.settings

        // Jour de fête (8 octobre…) : avant tout le reste, une fois.
        if let e = msg.eventToday, store.data.lastEvent != today, hour >= 5 {
            store.data.lastEvent = today
            return celebrateEvent(e.text)
        }
        if hour >= 5, store.data.lastBrief != today, !(hour == 22 && minute >= 30), hour < 23 {
            return morning()
        }
        let late = (hour == 22 && minute >= 30) || hour >= 23 || hour < 4
        if late {
            let night = hour < 4 ? Day.add(-1, to: today) : today
            if store.data.lastLate != night, now.timeIntervalSince(launched) > 60 {
                store.data.lastLate = night
                return say(msg.pick("tard"), mood: .sleepy, arms: .rest, autoHide: 25)
            }
        }
        if !late, hour >= max(s.endHour - 1, s.startHour), store.data.lastEvening != today, store.data.lastBrief == today {
            store.data.lastEvening = today
            say(msg.pick("soir", ["faites": "\(store.doneToday)"]), mood: .happy, arms: .up, autoHide: 30)
            return FX.shared.burst(.sparkles)
        }
        if !late, hour >= s.startHour, hour < s.endHour, now >= nextContact {
            let asked = store.data.checkins[today] ?? 0
            if asked < 4, Double.random(in: 0...1) < 0.6 {
                store.data.checkins[today] = asked + 1
                return checkin()
            }
            return nudge()
        }
        if now >= nextIdle { idle() }
    }

    private func contacted() {
        store.data.lastContact = Date()
        planNext(from: Date())
    }

    // MARK: Parler

    func say(_ text: String, lines: [String] = [], footnote: String? = nil, mood: Boule.Mood = .calm, arms: Boule.Arms = .wave,
             actions: [BubbleAction] = [], autoHide: Double? = 14) {
        hideTask?.cancel()
        bubble = BubbleModel(text: text, lines: lines, footnote: footnote, actions: actions, autoHide: autoHide)
        setMood(mood, arms: arms)
        hop += 1
        contacted()
        if let t = autoHide { scheduleHide(after: t) }
    }

    private func scheduleHide(after t: Double) {
        hideTask?.cancel()
        let id = bubble?.id
        hideTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(t))
            guard !Task.isCancelled, let self, self.bubble?.id == id else { return }
            self.dismiss()
        }
    }

    func dismiss() {
        hideTask?.cancel()
        bubble = nil
        if !inSession { setMood(.calm, arms: .rest) }
    }

    func setMood(_ m: Boule.Mood, arms a: Boule.Arms = .rest, for seconds: Double? = nil) {
        moodTask?.cancel()
        mood = m; arms = a
        if let seconds {
            moodTask = Task { [weak self] in
                try? await Task.sleep(for: .seconds(seconds))
                guard !Task.isCancelled, let self else { return }
                self.mood = self.sleeping ? .sleepy : .calm; self.arms = .rest
            }
        }
    }

    // MARK: Premier lancement

    private var onboardingShown = false
    func onboarding() {
        guard !onboardingShown else { return }
        onboardingShown = true
        say(msg.pick("accueil"), mood: .excited, arms: .wave,
            actions: [BubbleAction(title: "Enchantée !", primary: true) { [weak self] in
                guard let self else { return }
                self.store.settings.onboarded = true
                self.store.data.lastBrief = nil
                LoginItem.enable()
                self.dismiss()
                FX.shared.burst(.hearts)
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { self.morning() }
            }],
            autoHide: nil)
    }

    // MARK: Le matin

    func morning() {
        store.rollOver()
        store.data.lastBrief = Day.key()
        let hour = Calendar.current.component(.hour, from: Date())
        let todos = store.todayTodos.filter { !$0.done }
        let reviews = store.dueReviews
        var lines: [String] = []
        for t in todos.prefix(4) { lines.append("•  \(t.title)\(t.carried ? "  (d'hier)" : "")") }
        if todos.count > 4 { lines.append("   + \(todos.count - 4) autre(s)") }
        for r in reviews.prefix(3) { lines.append("📚  \(r.course.title) · J\(r.review.j)") }
        if reviews.count > 3 { lines.append("   + \(reviews.count - 3) révision(s)") }
        let foot = store.challenge(from: msg.list("defis")).map { "🌱 Défi : \($0)" }
        let hello = msg.pick(hour < 11 ? "bonjour" : "bonjourTard")
        say(lines.isEmpty ? hello + "\n" + msg.pick("journeeVide") : hello, lines: lines, footnote: foot, mood: .happy, arms: .wave,
            actions: [BubbleAction(title: "C'est parti !", primary: true) { [weak self] in
                self?.dismiss(); self?.hop += 1; FX.shared.burst(.sparkles)
            }],
            autoHide: 180)
    }

    // MARK: « Alors, ça se passe bien ? »

    func checkin() {
        say(msg.pick("questions"), mood: .curious, arms: .wave,
            actions: [BubbleAction(title: "😊 Oui", primary: true) { [weak self] in self?.answer(2) },
                      BubbleAction(title: "😐 Bof") { [weak self] in self?.answer(1) },
                      BubbleAction(title: "😟 Pas top") { [weak self] in self?.answer(0) }],
            autoHide: 120)
    }

    func answer(_ level: Int) {
        store.recordMood(level)
        switch level {
        case 2:
            say(msg.pick("reponsesBien"), mood: .happy, arms: .up, autoHide: 7)
            setMood(.happy, arms: .up, for: 7)
            FX.shared.burst(.sparkles)
        case 1:
            say(msg.pick("reponsesBof"), mood: .calm, arms: .hug,
                actions: [BubbleAction(title: "Respirer 1 min", primary: true) { [weak self] in self?.breathe() },
                          BubbleAction(title: "Pause 5 min") { [weak self] in self?.pause() }],
                autoHide: 45)
        default:
            let foot = store.hardDays >= 3
                ? "Ça fait plusieurs jours que c'est dur. En parler n'est pas un échec : SPS écoute les étudiants en santé, gratuit, 24h/24 → 0 805 23 23 36."
                : nil
            say(msg.pick("reponsesMal"), footnote: foot, mood: .worried, arms: .hug,
                actions: [BubbleAction(title: "Respirer avec moi", primary: true) { [weak self] in self?.breathe() },
                          BubbleAction(title: "Un tout petit pas") { [weak self] in self?.smallStep() }],
                autoHide: 90)
        }
    }

    func smallStep() {
        say(msg.pick("petitsPas"), mood: .calm, arms: .rest,
            actions: [BubbleAction(title: "Ok, je fais ça", primary: true) { [weak self] in
                          self?.say("Fier de toi. Un pas, puis un autre.", mood: .happy, arms: .up, autoHide: 6)
                      },
                      BubbleAction(title: "Autre chose") { [weak self] in self?.smallStep() }],
            autoHide: 60)
    }

    func nudge() {
        if !msg.list("motsDoux").isEmpty, Double.random(in: 0...1) < 0.15 { return loveNote() }
        say(msg.pick("petitsMots"), mood: .calm, arms: .wave, autoHide: 14)
    }

    func loveNote() {
        guard !msg.list("motsDoux").isEmpty else { return }
        say(msg.pick("motsDoux"), mood: .love, arms: .hug, autoHide: 14)
        FX.shared.burst(.hearts)
    }

    // MARK: Les petites animations quand on ne s'occupe pas de lui (toutes les 4 à 8 min)

    func idle() {
        nextIdle = Date().addingTimeInterval(.random(in: 240...480))
        let hour = Calendar.current.component(.hour, from: Date())
        var choices = ["etire", "regarde", "saut", "danse", "coucou"]
        if (13...16).contains(hour) || hour >= 21 { choices += ["baille", "baille"] }
        let pick = choices.randomElement()!
        Task { [weak self] in
            guard let self else { return }
            func wait(_ s: Double) async { try? await Task.sleep(for: .seconds(s)) }
            switch pick {
            case "etire":
                self.setMood(.happy, arms: .up); await wait(1.6); self.setMood(.calm)
            case "regarde":
                for l in [CGSize(width: -1, height: 0), CGSize(width: 1, height: -0.3), CGSize(width: 0, height: 0.6)] {
                    self.idleLook = l; await wait(0.9)
                }
                self.idleLook = nil
            case "saut":
                self.hop += 1; await wait(0.6); self.hop += 1
            case "danse":
                self.setMood(.happy, arms: .up)
                for t in [10.0, -10, 10, -10, 0] { self.tilt = t; await wait(0.35) }
                self.setMood(.calm)
            case "coucou":
                self.setMood(.calm, arms: .wave); await wait(2.2); self.setMood(.calm)
            default: // bâillement
                self.setMood(.sleepy, arms: .up); await wait(1.8); self.setMood(.calm)
            }
        }
    }

    // MARK: Jouer avec Mochi

    /// La souris passe et repasse sur lui : il adore.
    func petted() {
        guard !sleeping else { return }
        setMood(.love, arms: .hug, for: 2.5)
        hop += 1
        FX.shared.burst(.hearts)
        if bubble == nil, Double.random(in: 0...1) < 0.4 { say(msg.pick("caresse"), mood: .love, arms: .hug, autoHide: 3) }
    }

    /// Secoué pendant qu'elle le tient.
    func shaking() { setMood(.dizzy, arms: .up) }

    /// Lâché après avoir été secoué : il a le tournis… et prévient Yanis qu'elle pense à lui.
    func shaken() {
        guard Date().timeIntervalSince(lastShake) > 20 else {
            return say(msg.pick("tournis"), mood: .dizzy, arms: .up, autoHide: 4)
        }
        lastShake = Date()
        let dizzy = msg.pick("tournis")
        say(dizzy, mood: .dizzy, arms: .up, autoHide: 8)
        setMood(.dizzy, arms: .up, for: 3)
        Link.shared.sendThought { [weak self] ok in
            guard let self else { return }
            let line = self.msg.pick(ok ? "penseEnvoye" : "penseEnAttente")
            self.say(dizzy, footnote: line, mood: ok ? .love : .dizzy, arms: .hug, autoHide: 7)
            if ok { FX.shared.burst(.hearts) }
        }
    }

    /// Yanis a cliqué plusieurs fois sur la mascotte de son OsaNotch : pirouette + fontaine de cœurs.
    func yanisLove(_ name: String) {
        if sleeping {
            // On ne réveille pas : des cœurs au-dessus du lit, et elle le saura au réveil.
            loveWhileAsleep = true
            return FX.shared.burst(.hearts)
        }
        bubble = nil
        setMood(.love, arms: .up)
        FX.shared.burst(.bigHearts)
        Task { [weak self] in
            guard let self else { return }
            for t in [0.0, 360] { self.tilt = t; try? await Task.sleep(for: .milliseconds(30)) }
            withAnimation(.spring(response: 0.9, dampingFraction: 0.7)) { self.tilt = 360 }
            try? await Task.sleep(for: .seconds(1))
            var noAnim = Transaction(); noAnim.disablesAnimations = true
            withTransaction(noAnim) { self.tilt = 0 }
            self.hop += 1
            self.say(self.msg.fill(self.msg.pick("yanisPense"), [:]).replacingOccurrences(of: self.msg.from, with: name),
                     mood: .love, arms: .hug, autoHide: 9)
            self.setMood(.love, arms: .hug, for: 9)
        }
    }

    // MARK: Le lit (double-clic) : il la laisse tranquille

    func sleep() {
        guard !sleeping else { return }
        endSession()
        stopFocus(silent: true)
        bubble = nil
        sleeping = true
        store.data.sleepingSince = Date()
        setMood(.sleepy)
    }

    func wake(silent: Bool = false) {
        guard sleeping else { return }
        sleeping = false
        store.data.sleepingSince = nil
        nextIdle = Date().addingTimeInterval(240)
        if silent { setMood(.calm); return }
        setMood(.happy, arms: .up, for: 2)
        hop += 1
        if loveWhileAsleep {
            loveWhileAsleep = false
            say(msg.pick("yanisPendantSieste"), mood: .love, arms: .hug, autoHide: 8)
            FX.shared.burst(.hearts)
        } else {
            say(msg.pick("reveil"), mood: .sleepy, arms: .up, autoHide: 4)
        }
    }

    // MARK: Focus 25 min : silence, puis la pause

    func startFocus(minutes: Double = 25) {
        endSession()
        bubble = nil
        focusUntil = Date().addingTimeInterval(minutes * 60)
        setMood(.calm)
        hop += 1
        focusTask?.cancel()
        focusTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(minutes * 60))
            guard !Task.isCancelled, let self else { return }
            self.focusUntil = nil
            if self.sleeping { return }
            FX.shared.burst(.confetti)
            self.say(self.msg.pick("focusFin"), mood: .excited, arms: .up,
                     actions: [BubbleAction(title: "Pause 5 min", primary: true) { [weak self] in self?.pause() },
                               BubbleAction(title: "Encore 25 min") { [weak self] in self?.startFocus() }],
                     autoHide: 120)
        }
    }

    func stopFocus(silent: Bool = false) {
        guard focusUntil != nil else { return }
        focusTask?.cancel(); focusTask = nil
        focusUntil = nil
        if !silent { say("Focus arrêté. Pas grave, chaque minute compte !", mood: .calm, arms: .rest, autoHide: 5) }
    }

    // MARK: Respiration (cohérence cardiaque : 5 s inspire, 5 s expire, 1 minute)

    func breathe() {
        endSession()
        pauseTask?.cancel()
        hideTask?.cancel()
        bubble = BubbleModel(text: "On respire ensemble. Je gonfle : tu inspires. Je dégonfle : tu expires.",
                             actions: [BubbleAction(title: "Arrêter") { [weak self] in self?.endSession(); self?.dismiss() }])
        setMood(.calm)
        sessionTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(3))
            for cycle in 0..<6 {
                for inhale in [true, false] {
                    guard !Task.isCancelled, let self else { return }
                    self.bubble?.text = inhale ? "Inspire… (\(cycle + 1)/6)" : "Expire…"
                    self.mood = inhale ? .calm : .sleepy
                    withAnimation(.easeInOut(duration: 5)) { self.breath = inhale ? 1 : 0 }
                    try? await Task.sleep(for: .seconds(5))
                }
            }
            guard !Task.isCancelled, let self else { return }
            self.sessionTask = nil
            self.say("Voilà. Ton cœur a ralenti un peu. Tu peux y retourner tout doucement 💛", mood: .happy, arms: .up, autoHide: 8)
        }
    }

    // MARK: Étirements guidés (environ 40 s)

    func stretch() {
        endSession()
        hideTask?.cancel()
        let steps: [(String, Boule.Arms, Double, Int)] = [
            ("Debout ! Bras vers le ciel, étire-toi tout en haut…", .up, 0, 0),
            ("Penche-toi doucement à droite…", .up, 14, 0),
            ("…et à gauche.", .up, -14, 0),
            ("Monte les épaules vers les oreilles… et relâche. 5 fois !", .rest, 0, 5),
            ("Fais rouler tes épaules vers l'arrière, tranquille.", .hug, 0, 0),
            ("Regarde au loin par la fenêtre. Tes yeux se reposent.", .rest, 0, 0),
        ]
        bubble = BubbleModel(text: steps[0].0, actions: [BubbleAction(title: "Arrêter") { [weak self] in self?.endSession(); self?.dismiss() }])
        sessionTask = Task { [weak self] in
            for (i, s) in steps.enumerated() {
                guard !Task.isCancelled, let self else { return }
                self.bubble?.text = "\(i + 1)/\(steps.count) · " + s.0
                self.setMood(.happy, arms: s.1)
                self.tilt = s.2
                if i == steps.count - 1 { self.idleLook = CGSize(width: -1, height: -0.6) }
                if s.3 > 0 {
                    for _ in 0..<s.3 { self.hop += 1; try? await Task.sleep(for: .seconds(1.2)) }
                } else {
                    try? await Task.sleep(for: .seconds(6.5))
                }
            }
            guard !Task.isCancelled, let self else { return }
            self.tilt = 0; self.idleLook = nil
            self.sessionTask = nil
            FX.shared.burst(.sparkles)
            self.say("Et voilà ! Toute neuve ✨", mood: .happy, arms: .up, autoHide: 6)
        }
    }

    func endSession() {
        sessionTask?.cancel(); sessionTask = nil
        withAnimation(.easeOut(duration: 0.6)) { breath = 0 }
        tilt = 0; idleLook = nil
    }

    // MARK: Pause, eau, bulles

    func pause(minutes: Int = 5) {
        pauseTask?.cancel()
        say("Pause ! Lève-toi, bois un verre d'eau, regarde par la fenêtre. Je te fais signe dans \(minutes) minutes.",
            mood: .sleepy, arms: .rest, autoHide: 10)
        pauseTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(Double(minutes) * 60))
            guard !Task.isCancelled, let self, !self.sleeping else { return }
            self.say("La pause est finie ! On s'y remet tout doucement ? Commence par le plus facile.", mood: .happy, arms: .wave, autoHide: 30)
        }
    }

    func drink() {
        store.drink()
        FX.shared.burst(.drops)
        hop += 1
        if store.waterToday == 8 {
            say(msg.pick("eauObjectif"), mood: .excited, arms: .up, autoHide: 6)
            FX.shared.burst(.confetti)
        } else {
            setMood(.happy, arms: .up, for: 1.5)
        }
    }

    func bubblesDone(_ n: Int) {
        say(msg.pick("bulles", ["n": "\(n)"]), mood: .happy, arms: .up, autoHide: 7)
        if n >= 25 { FX.shared.burst(.confetti) }
    }

    // MARK: Fêtes et célébrations

    func celebrateEvent(_ text: String) {
        bubble = nil
        FX.shared.burst(.confetti)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { FX.shared.burst(.bigHearts) }
        say(text, mood: .excited, arms: .up, autoHide: 40)
        setMood(.excited, arms: .up, for: 6)
        Task { [weak self] in
            for t in [10.0, -10, 10, -10, 10, 0] { self?.tilt = t; try? await Task.sleep(for: .milliseconds(300)) }
        }
    }

    func celebrate() {
        let allTodos = store.todayTodos.allSatisfy(\.done)
        if allTodos, store.dueReviews.isEmpty, !store.todayTodos.isEmpty {
            onClosePanel()
            say(msg.pick("toutFait"), mood: .excited, arms: .up, autoHide: 8)
            FX.shared.burst(.confetti)
        } else {
            hop += 1
            setMood(.happy, arms: .up, for: 2)
            FX.shared.burst(.sparkles)
        }
    }

    func hide(hours: Double) { dismiss(); hiddenUntil = Date().addingTimeInterval(hours * 3600) }
    func show() { hiddenUntil = nil }

    func updated(to version: String) {
        say("J'ai fait peau neuve ✨ (version \(version))", mood: .excited, arms: .up, autoHide: 10)
        FX.shared.burst(.sparkles)
    }
}

/// Est-ce qu'elle est devant l'écran, et pas en plein film ou en présentation ?
enum Presence {
    static var here: Bool {
        let idle = CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: CGEventType(rawValue: ~0)!)
        if let d = CGSessionCopyCurrentDictionary() as? [String: Any], d["CGSSessionScreenIsLocked"] as? Bool == true { return false }
        return idle < 90
    }

    /// Une fenêtre occupe tout un écran (vidéo, Keynote, jeu en plein écran) : on ne dérange pas.
    static var busy: Bool {
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else { return false }
        let screens = NSScreen.screens.map { $0.frame.size }
        let me = ProcessInfo.processInfo.processIdentifier
        for w in list {
            guard (w[kCGWindowLayer as String] as? Int) == 0, (w[kCGWindowOwnerPID as String] as? Int32) != me,
                  let b = w[kCGWindowBounds as String] as? [String: CGFloat] else { continue }
            if screens.contains(where: { abs($0.width - (b["Width"] ?? 0)) < 2 && abs($0.height - (b["Height"] ?? 0)) < 2 }) { return true }
        }
        return false
    }
}
