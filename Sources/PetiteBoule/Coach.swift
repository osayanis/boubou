import SwiftUI
import AppKit

struct BubbleAction: Identifiable {
    let id = UUID()
    var title: String
    var primary = false
    var run: () -> Void
}

/// Une bulle de Petite Boule : un texte, éventuellement une liste, des boutons, un champ.
struct BubbleModel: Identifiable {
    var id = UUID()
    var text: String
    var lines: [String] = []
    var footnote: String? = nil
    var actions: [BubbleAction] = []
    var autoHide: Double? = nil
    var input: ((String) -> Void)? = nil
    var inputPlaceholder = ""
}

/// Le cerveau : décide quand Petite Boule parle (visite du matin, « ça va ? », petits mots,
/// bilan du soir, « va dormir »), et ce qu'elle répond.
@MainActor
final class Coach: ObservableObject {
    static let shared = Coach()

    @Published var bubble: BubbleModel?
    @Published var mood: Boule.Mood = .calm
    @Published var arms: Boule.Arms = .rest
    @Published var hop = 0
    @Published var breath: CGFloat = 0
    @Published var look: CGSize = .zero
    @Published var hiddenUntil: Date? = nil

    var cabinetOpen = false
    var onOpenCabinet: (Cabinet.Tab) -> Void = { _ in }

    private let store = Store.shared
    private let msg = Messages.shared
    private var timer: Timer?
    private var hideTask: Task<Void, Never>?
    private var moodTask: Task<Void, Never>?
    private var breathTask: Task<Void, Never>?
    private var pauseTask: Task<Void, Never>?
    private var nextContact: Date = .distantPast
    private var launched = Date()

    var hidden: Bool { (hiddenUntil ?? .distantPast) > Date() }
    var breathing: Bool { breathTask != nil }

    func start() {
        planNext(from: store.data.lastContact ?? Date().addingTimeInterval(-3600))
        timer = Timer.scheduledTimer(withTimeInterval: 20, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { self.tick() }
    }

    // MARK: L'horloge

    private func planNext(from date: Date) {
        let m = store.settings.rhythm.minutes
        nextContact = date.addingTimeInterval(m * 60 * Double.random(in: 0.8...1.2))
    }

    /// Toutes les 20 s : est-ce le moment de dire quelque chose ?
    func tick() {
        if let h = hiddenUntil, h <= Date() { hiddenUntil = nil }
        store.rollOver()
        guard store.settings.onboarded else {
            if bubble == nil, !cabinetOpen { onboarding() }
            return
        }
        guard bubble == nil, !breathing, !hidden, !cabinetOpen, Presence.here, !Presence.busy else { return }

        let now = Date(), hour = Calendar.current.component(.hour, from: now)
        let today = Day.key(), s = store.settings

        if hour >= 5, store.data.lastBrief != today, hour < 23 {
            return morning()
        }
        if hour >= 23 || hour < 4 {
            let night = hour < 4 ? Day.add(-1, to: today) : today
            if store.data.lastLate != night, now.timeIntervalSince(launched) > 60 {
                store.data.lastLate = night
                return say(msg.pick("tard"), mood: .sleepy, autoHide: 25)
            }
            return
        }
        if hour >= max(s.endHour - 1, s.startHour), store.data.lastEvening != today, store.data.lastBrief == today {
            store.data.lastEvening = today
            return say(msg.pick("soir", ["faites": "\(store.doneToday)"]), mood: .happy, arms: .up, autoHide: 30)
        }
        guard hour >= s.startHour, hour < s.endHour, now >= nextContact else { return }
        let asked = store.data.checkins[today] ?? 0
        if asked < 4, Double.random(in: 0...1) < 0.6 {
            store.data.checkins[today] = asked + 1
            checkin()
        } else {
            nudge()
        }
    }

    private func contacted() {
        store.data.lastContact = Date()
        planNext(from: Date())
    }

    // MARK: Ce que dit Petite Boule

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
        setMood(.calm, arms: .rest)
    }

    /// Humeur affichée, qui revient au calme toute seule.
    func setMood(_ m: Boule.Mood, arms a: Boule.Arms = .rest, for seconds: Double? = nil) {
        moodTask?.cancel()
        mood = m; arms = a
        if let seconds {
            moodTask = Task { [weak self] in
                try? await Task.sleep(for: .seconds(seconds))
                guard !Task.isCancelled else { return }
                self?.mood = .calm; self?.arms = .rest
            }
        }
    }

    // MARK: Premier lancement

    private var onboardingShown = false
    func onboarding() {
        guard !onboardingShown else { return }
        onboardingShown = true
        var b = BubbleModel(text: "Coucou ! Moi c'est Petite Boule, ton assistante de garde 🩺\nJe reste dans mon coin, et je passe te voir de temps en temps. Comment tu t'appelles ?")
        b.inputPlaceholder = "Ton prénom"
        b.input = { [weak self] name in
            guard let self else { return }
            let n = name.trimmingCharacters(in: .whitespaces)
            guard !n.isEmpty else { return }
            self.store.settings.name = n
            self.store.settings.onboarded = true
            self.store.data.lastBrief = Day.key()
            LoginItem.enable()
            self.say("Enchantée \(n) ! Chaque matin je te montre ta journée : tes tâches, tes révisions (méthode des J) et un petit défi pour toi. Clique sur moi quand tu veux.",
                     mood: .happy, arms: .up,
                     actions: [BubbleAction(title: "Ajouter ma journée", primary: true) { [weak self] in self?.dismiss(); self?.onOpenCabinet(.today) },
                               BubbleAction(title: "Plus tard") { [weak self] in self?.dismiss() }],
                     autoHide: 60)
        }
        bubble = b
        setMood(.excited, arms: .wave)
        hop += 1
    }

    // MARK: Le matin

    func morning() {
        store.rollOver()
        store.data.lastBrief = Day.key()
        let hour = Calendar.current.component(.hour, from: Date())
        let todos = store.todayTodos.filter { !$0.done }
        let reviews = store.dueReviews
        var lines: [String] = []
        for t in todos.prefix(4) { lines.append("☐  \(t.title)\(t.carried ? "  (d'hier)" : "")") }
        if todos.count > 4 { lines.append("   + \(todos.count - 4) autre(s)") }
        for r in reviews.prefix(3) { lines.append("📚  \(r.course.title) · J\(r.review.j)") }
        if reviews.count > 3 { lines.append("   + \(reviews.count - 3) révision(s)") }
        var foot: String? = nil
        if let c = store.challenge(from: msg.list("defis")) { foot = "🌱 Défi du jour : \(c)" }
        let hello = msg.pick(hour < 11 ? "bonjour" : "bonjourTard")
        let text = lines.isEmpty ? hello + "\n" + msg.pick("journeeVide") : hello
        say(text, lines: lines, footnote: foot, mood: .happy, arms: .wave,
            actions: [BubbleAction(title: "C'est parti !", primary: true) { [weak self] in
                          self?.dismiss(); self?.hop += 1
                      },
                      BubbleAction(title: "Voir ma journée") { [weak self] in self?.dismiss(); self?.onOpenCabinet(.today) }],
            autoHide: 180)
    }

    // MARK: « Alors, ça se passe bien ? »

    func checkin() {
        say(msg.pick("questions"), mood: .curious, arms: .wave,
            actions: [BubbleAction(title: "Oui !", primary: true) { [weak self] in self?.answer(2) },
                      BubbleAction(title: "Bof…") { [weak self] in self?.answer(1) },
                      BubbleAction(title: "Pas top") { [weak self] in self?.answer(0) }],
            autoHide: 120)
    }

    func answer(_ level: Int) {
        store.recordMood(level)
        switch level {
        case 2:
            say(msg.pick("reponsesBien"), mood: .happy, arms: .up, autoHide: 9)
            setMood(.happy, arms: .up, for: 9)
        case 1:
            say(msg.pick("reponsesBof"), mood: .calm, arms: .hug,
                actions: [BubbleAction(title: "Respirer 1 min", primary: true) { [weak self] in self?.breathe() },
                          BubbleAction(title: "Pause 5 min") { [weak self] in self?.pause() },
                          BubbleAction(title: "Ça ira, merci") { [weak self] in self?.dismiss() }],
                autoHide: 60)
        default:
            var foot: String? = nil
            if store.hardDays >= 3 {
                foot = "Ça fait plusieurs jours que c'est dur. En parler, ce n'est pas un échec : SPS écoute les étudiants en santé, gratuitement, 24h/24 → 0 805 23 23 36."
            }
            say(msg.pick("reponsesMal"), footnote: foot, mood: .worried, arms: .hug,
                actions: [BubbleAction(title: "Respirer avec moi", primary: true) { [weak self] in self?.breathe() },
                          BubbleAction(title: "Un tout petit pas") { [weak self] in self?.smallStep() },
                          BubbleAction(title: "En parler") { [weak self] in self?.dismiss(); self?.onOpenCabinet(.mood) }],
                autoHide: 90)
        }
    }

    func smallStep() {
        say(msg.pick("petitsPas"), mood: .calm, arms: .rest,
            actions: [BubbleAction(title: "Ok, je fais ça", primary: true) { [weak self] in
                          self?.say("Je suis fière de toi. Un pas, puis un autre.", mood: .happy, arms: .up, autoHide: 8)
                      },
                      BubbleAction(title: "Autre chose") { [weak self] in self?.smallStep() }],
            autoHide: 60)
    }

    func nudge() {
        let notes = msg.list("motsDoux")
        if !notes.isEmpty, Double.random(in: 0...1) < 0.15 {
            say(msg.pick("motsDoux"), mood: .happy, arms: .hug, autoHide: 16)
        } else {
            say(msg.pick("petitsMots"), mood: .calm, arms: .wave, autoHide: 14)
        }
    }

    func loveNote() {
        guard !msg.list("motsDoux").isEmpty else { return }
        say(msg.pick("motsDoux"), mood: .happy, arms: .hug, autoHide: 16)
    }

    // MARK: Respiration (cohérence cardiaque : 5 s inspire, 5 s expire, 1 minute)

    func breathe() {
        breathTask?.cancel()
        pauseTask?.cancel()
        hideTask?.cancel()
        let stop = BubbleAction(title: "Arrêter") { [weak self] in self?.stopBreathing() }
        bubble = BubbleModel(text: "On respire ensemble. Suis-moi : je gonfle, tu inspires ; je dégonfle, tu expires.", actions: [stop])
        setMood(.calm, arms: .rest)
        breathTask = Task { [weak self] in
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
            self.breathTask = nil
            self.say("Voilà. Ton cœur a ralenti un peu. Tu peux y retourner tout doucement 💛", mood: .happy, arms: .up, autoHide: 12)
        }
    }

    func stopBreathing() {
        breathTask?.cancel(); breathTask = nil
        withAnimation(.easeOut(duration: 0.6)) { breath = 0 }
        dismiss()
    }

    // MARK: Pause

    func pause(minutes: Int = 5) {
        pauseTask?.cancel()
        say("Pause ! Lève-toi, bois un verre d'eau, regarde par la fenêtre. Je te fais signe dans \(minutes) minutes.",
            mood: .sleepy, arms: .rest, autoHide: 12)
        pauseTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(Double(minutes) * 60))
            guard !Task.isCancelled, let self else { return }
            self.say("La pause est finie ! On s'y remet tout doucement ? Commence par le plus facile.", mood: .happy, arms: .wave, autoHide: 30)
        }
    }

    // MARK: Célébrations (depuis le cabinet)

    func celebrate() {
        let allTodos = store.todayTodos.allSatisfy(\.done)
        let allReviews = store.dueReviews.isEmpty
        if allTodos, allReviews, !store.todayTodos.isEmpty {
            say(msg.pick("toutFait"), mood: .excited, arms: .up, autoHide: 10)
        } else {
            hop += 1
            setMood(.happy, arms: .up, for: 2.5)
            if Double.random(in: 0...1) < 0.35 { say(msg.pick("tacheFaite"), mood: .happy, arms: .up, autoHide: 3.5) }
        }
    }

    func hide(hours: Double) {
        dismiss()
        hiddenUntil = Date().addingTimeInterval(hours * 3600)
    }

    func hideUntilTomorrow() {
        dismiss()
        let cal = Calendar.current
        let tomorrow = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: Date()))!
        hiddenUntil = cal.date(bySettingHour: 5, minute: 0, second: 0, of: tomorrow)
    }

    func show() { hiddenUntil = nil }

    func updated(to version: String) {
        say("J'ai fait peau neuve ✨ (version \(version))", mood: .excited, arms: .up, autoHide: 8)
    }
}

/// Est-ce qu'elle est devant l'écran, et pas en plein film ou en présentation ?
enum Presence {
    /// Une action (souris, clavier) il y a moins de 90 s, et la session n'est pas verrouillée.
    static var here: Bool {
        let any = CGEventType(rawValue: ~0)!
        let idle = CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: any)
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
            let size = CGSize(width: b["Width"] ?? 0, height: b["Height"] ?? 0)
            if screens.contains(where: { abs($0.width - size.width) < 2 && abs($0.height - size.height) < 2 }) { return true }
        }
        return false
    }
}
