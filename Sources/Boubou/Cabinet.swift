import SwiftUI
import AppKit

/// Le panneau de Boubou : un seul écran, pour aller vite. Sa liste du jour (tâches, révisions, défi),
/// un champ pour ajouter, les pauses en un clic, et « ça va ? ». Le reste est replié.
struct QuickPanel: View {
    @ObservedObject var store = Store.shared
    @ObservedObject var msg = Messages.shared
    @ObservedObject var coach = Coach.shared
    @State private var text = ""
    @State private var showHelp = false
    @State private var showSettings = false
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            list
            addRow
            pauses
            moodRow
            if showHelp { help.transition(.opacity.combined(with: .move(edge: .top))) }
            if showSettings { SettingsBlock().transition(.opacity.combined(with: .move(edge: .top))) }
        }
        .padding(16)
        .frame(width: 344)
        .background(Theme.bg, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(Theme.stroke))
        .preferredColorScheme(.dark)
        .animation(.snappy(duration: 0.22), value: showHelp)
        .animation(.snappy(duration: 0.22), value: showSettings)
        .onAppear { focused = true }
    }

    // MARK: En-tête

    private var header: some View {
        let total = store.todayTodos.count + store.dueReviews.count + store.reviewsDoneToday.count
        let done = store.todayTodos.filter(\.done).count + store.reviewsDoneToday.count
        return HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(store.name.isEmpty ? "Coucou" : "Coucou \(store.name)").font(.system(size: 16, weight: .bold)).foregroundStyle(.white)
            Text(Day.longToday()).font(.system(size: 11.5, weight: .semibold)).foregroundStyle(.white.opacity(0.4))
            Spacer()
            if total > 0 {
                Text("\(done)/\(total)").font(.system(size: 11.5, weight: .heavy)).foregroundStyle(done == total ? Theme.done : .white.opacity(0.6))
            }
            Button { showSettings.toggle(); showHelp = false } label: {
                Image(systemName: "gearshape.fill").font(.system(size: 12)).foregroundStyle(.white.opacity(showSettings ? 0.9 : 0.35))
            }
            .buttonStyle(.plain).help("Réglages")
        }
    }

    // MARK: La liste du jour

    private var list: some View {
        let todos = store.todayTodos.sorted { !$0.done && $1.done }
        let due = store.dueReviews, doneRev = store.reviewsDoneToday
        let challenge = store.challenge(from: msg.list("defis"))
        let empty = todos.isEmpty && due.isEmpty && doneRev.isEmpty
        return VStack(spacing: 0) {
            if empty {
                Text("Rien pour l'instant. Tape ce que tu as à faire juste en dessous ⤵︎")
                    .font(.system(size: 12.5, weight: .medium)).foregroundStyle(.white.opacity(0.45))
                    .frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 6)
            }
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(todos.filter { !$0.done }) { t in TodoRow(todo: t) }
                    ForEach(due, id: \.course.id) { r in ReviewRow(course: r.course, review: r.review, done: false) }
                    if let c = challenge { ChallengeRow(text: c) }
                    ForEach(todos.filter(\.done)) { t in TodoRow(todo: t) }
                    ForEach(doneRev, id: \.course.id) { r in ReviewRow(course: r.course, review: r.review, done: true) }
                }
            }
            .scrollIndicators(.never)
            .frame(maxHeight: 250)
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 12).padding(.vertical, 6)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    // MARK: Ajouter (Entrée = tâche ; « Cours » = révisions J1 → J30)

    private var addRow: some View {
        HStack(spacing: 6) {
            Field(placeholder: "Ajouter…", text: $text) { addTodo() }
                .focused($focused)
            Button("Tâche") { addTodo() }.buttonStyle(PillStyle(primary: true))
                .help("Entrée")
            Button("Cours") { addCourse() }.buttonStyle(PillStyle())
                .help("Cours appris aujourd'hui : je te le ressors à J\(store.settings.intervals.map(String.init).joined(separator: ", J"))")
        }
        .disabled(false)
    }

    private func addTodo() {
        guard !text.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        store.addTodo(text); text = ""; coach.hop += 1
    }

    private func addCourse() {
        guard !text.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        store.addCourse(subject: "", title: text); text = ""
        coach.setMood(.happy, arms: .up, for: 1.5); coach.hop += 1
        FX.shared.burst(.sparkles)
    }

    // MARK: Pauses en un clic

    private var pauses: some View {
        HStack(spacing: 6) {
            chip("wind", "Respirer") { close(); coach.breathe() }
            chip("figure.cooldown", "S'étirer") { close(); coach.stretch() }
            chip("bubbles.and.sparkles", "Bulles") { close(); BubbleGame.shared.start() }
            if coach.focusing {
                chip("stop.circle", "Stop") { coach.stopFocus() }
            } else {
                chip("timer", "Focus") { close(); coach.startFocus() }
            }
            chip("drop.fill", "\(store.waterToday)") { coach.drink() }
                .help("Un verre d'eau de plus")
        }
    }

    private func chip(_ icon: String, _ label: String, _ run: @escaping () -> Void) -> some View {
        Button(action: run) {
            VStack(spacing: 4) {
                Image(systemName: icon).font(.system(size: 14, weight: .semibold))
                Text(label).font(.system(size: 10.5, weight: .bold)).lineLimit(1)
            }
            .foregroundStyle(.white.opacity(0.85))
            .frame(maxWidth: .infinity).padding(.vertical, 8)
            .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle())
    }

    // MARK: Ça va ?

    private var moodRow: some View {
        HStack(spacing: 6) {
            Text("Ça va ?").font(.system(size: 12, weight: .bold)).foregroundStyle(.white.opacity(0.5))
            ForEach([(2, Boule.Mood.happy), (1, .calm), (0, .sad)], id: \.0) { level, mood in
                Button { close(); coach.answer(level) } label: {
                    Boule(mood: mood, size: 20, shadow: false).frame(width: 34, height: 28)
                        .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                }
                .buttonStyle(PressStyle())
            }
            Spacer()
            Button(showHelp ? "Fermer" : "Besoin de parler ?") { showHelp.toggle(); showSettings = false }
                .buttonStyle(.plain).font(.system(size: 11.5, weight: .semibold)).foregroundStyle(.white.opacity(0.45))
        }
    }

    private var help: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Tu n'as pas à porter ça seule. Gratuit et confidentiel :")
                .font(.system(size: 11.5, weight: .medium)).foregroundStyle(.white.opacity(0.55))
            line("0 805 23 23 36", "SPS · étudiants en santé, 24h/24")
            line("3040", "Écoute étudiante")
            line("3114", "Idées noires, 24h/24")
            line("15", "Urgence")
        }
        .padding(12)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func line(_ number: String, _ hint: String) -> some View {
        HStack {
            Text(number).font(.system(size: 13, weight: .heavy)).foregroundStyle(.white).textSelection(.enabled)
            Text(hint).font(.system(size: 11, weight: .medium)).foregroundStyle(.white.opacity(0.45))
            Spacer()
        }
    }

    private func close() { coach.onClosePanel() }
}

struct PressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.93 : 1)
            .animation(.spring(response: 0.2, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

// MARK: - Lignes

private struct TodoRow: View {
    let todo: Todo
    @State private var hover = false
    var body: some View {
        HStack(spacing: 10) {
            Button {
                withAnimation(.snappy) { if Store.shared.toggle(todo) { Coach.shared.celebrate() } }
            } label: {
                HStack(spacing: 10) {
                    CheckCircle(on: todo.done)
                    Text(todo.title).font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white.opacity(todo.done ? 0.35 : 0.92))
                        .strikethrough(todo.done, color: .white.opacity(0.35))
                        .multilineTextAlignment(.leading)
                    if todo.carried && !todo.done {
                        Text("d'hier").font(.system(size: 9.5, weight: .bold)).foregroundStyle(.white.opacity(0.5))
                            .padding(.horizontal, 5).padding(.vertical, 1.5).background(.white.opacity(0.08), in: Capsule())
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            Button { withAnimation(.snappy) { Store.shared.delete(todo) } } label: {
                Image(systemName: "xmark").font(.system(size: 9, weight: .bold)).foregroundStyle(.white.opacity(0.4))
            }
            .buttonStyle(.plain).opacity(hover ? 1 : 0)
        }
        .padding(.vertical, 6)
        .onHover { hover = $0 }
    }
}

private struct ReviewRow: View {
    let course: Course
    let review: Review
    let done: Bool
    @State private var hover = false
    var body: some View {
        HStack(spacing: 10) {
            Button {
                withAnimation(.snappy) { if Store.shared.toggleReview(course) { Coach.shared.celebrate() } }
            } label: {
                HStack(spacing: 10) {
                    CheckCircle(on: done)
                    Text(course.title).font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white.opacity(done ? 0.35 : 0.92))
                        .strikethrough(done, color: .white.opacity(0.35))
                    Spacer(minLength: 0)
                    Text("J\(review.j)").font(.system(size: 10.5, weight: .heavy)).foregroundStyle(.black.opacity(0.8))
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(review.day < Day.key() && !done ? Theme.soft : .white.opacity(done ? 0.3 : 0.85), in: Capsule())
                        .help(review.day < Day.key() && !done ? "En retard" : "Révision J\(review.j)")
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            Button { withAnimation(.snappy) { Store.shared.deleteCourse(course) } } label: {
                Image(systemName: "xmark").font(.system(size: 9, weight: .bold)).foregroundStyle(.white.opacity(0.4))
            }
            .buttonStyle(.plain).opacity(hover ? 1 : 0).help("Supprimer ce cours (toutes ses révisions)")
        }
        .padding(.vertical, 6)
        .onHover { hover = $0 }
    }
}

private struct ChallengeRow: View {
    let text: String
    @ObservedObject var store = Store.shared
    var body: some View {
        Button {
            withAnimation(.snappy) { store.challengeDone.toggle() }
            if store.challengeDone { Coach.shared.celebrate() }
        } label: {
            HStack(spacing: 10) {
                CheckCircle(on: store.challengeDone)
                Text("🌱 \(text)").font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(.white.opacity(store.challengeDone ? 0.35 : 0.7))
                    .strikethrough(store.challengeDone, color: .white.opacity(0.35))
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 0)
            }
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Réglages (repliés derrière la roue dentée)

private struct SettingsBlock: View {
    @ObservedObject var store = Store.shared
    @ObservedObject var updater = Updater.shared
    @State private var login = LoginItem.enabled

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 4) {
                Text("Boubou passe").font(.system(size: 11.5, weight: .bold)).foregroundStyle(.white.opacity(0.5))
                ForEach(Rhythm.allCases) { r in
                    Button { store.settings.rhythm = r } label: {
                        Text(r.label).font(.system(size: 11, weight: .bold))
                            .foregroundStyle(store.settings.rhythm == r ? .black : .white.opacity(0.6))
                            .padding(.horizontal, 9).padding(.vertical, 5)
                            .background(store.settings.rhythm == r ? Color.white : Color.white.opacity(0.06), in: Capsule())
                    }.buttonStyle(.plain)
                }
            }
            Toggle(isOn: $login) {
                Text("Ouvrir Boubou au démarrage").font(.system(size: 12, weight: .semibold)).foregroundStyle(.white.opacity(0.8))
            }
            .toggleStyle(.switch).controlSize(.small).tint(Theme.done)
            .onChange(of: login) { _, v in v ? LoginItem.enable() : LoginItem.disable(); login = LoginItem.enabled }
            Text("Glisse-moi vers un autre coin · double-clic : je dors · secoue-moi : \(Messages.shared.partner?.name ?? "Yanis") reçoit un 💕")
                .font(.system(size: 10.5, weight: .medium)).foregroundStyle(.white.opacity(0.4))
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 6) {
                Text("v\(Updater.currentVersion) · \(updater.status)").font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(.white.opacity(0.35)).lineLimit(1)
                Spacer()
                Button("MAJ") { updater.check(manual: true) }.buttonStyle(PillStyle())
                Button("Quitter") { NSApp.terminate(nil) }.buttonStyle(PillStyle())
            }
        }
        .padding(12)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

// MARK: - La fenêtre du panneau : à côté de Boubou, se ferme dès qu'on clique ailleurs

@MainActor
final class PanelController: NSObject, NSWindowDelegate {
    private var panel: FloatingPanel?
    weak var mascot: MascotController?
    var isOpen: Bool { panel?.isVisible == true }

    func toggle() { isOpen ? close() : open() }

    func open() {
        let p: FloatingPanel
        if let existing = panel { p = existing } else {
            p = FloatingPanel(size: NSSize(width: 344, height: 400))
            p.keyable = true
            p.hasShadow = true
            p.level = .floating
            let host = NSHostingController(rootView: QuickPanel())
            host.sizingOptions = [.preferredContentSize]
            p.contentViewController = host
            p.delegate = self
            panel = p
        }
        Coach.shared.panelOpen = true
        Coach.shared.dismiss()
        p.contentViewController?.view.layoutSubtreeIfNeeded()
        position(p)
        p.alphaValue = 0
        p.makeKeyAndOrderFront(nil)
        NSAnimationContext.runAnimationGroup { $0.duration = 0.15; p.animator().alphaValue = 1 }
    }

    private func position(_ p: NSWindow) {
        guard let m = mascot?.bodyFrame, let v = (mascot?.panel.screen ?? NSScreen.main)?.visibleFrame else { return }
        let size = p.contentViewController?.view.fittingSize ?? p.frame.size
        let c = Store.shared.settings.corner
        var o = NSPoint(x: c.right ? m.minX - size.width - 4 : m.maxX + 4,
                        y: c.bottom ? m.minY + 4 : m.maxY - size.height - 4)
        o.x = min(max(o.x, v.minX + 6), v.maxX - size.width - 6)
        o.y = min(max(o.y, v.minY + 6), v.maxY - size.height - 6)
        p.setFrame(NSRect(origin: o, size: size), display: true)
    }

    func close() {
        guard let p = panel, p.isVisible else { return }
        Coach.shared.panelOpen = false
        p.orderOut(nil)
    }

    func windowDidResignKey(_ n: Notification) { close() }

    func windowDidResize(_ n: Notification) {
        // le panneau grandit (réglages, aide) : il reste collé à Boubou et dans l'écran
        guard let p = panel, let v = (mascot?.panel.screen ?? NSScreen.main)?.visibleFrame else { return }
        var f = p.frame
        f.origin.y = min(max(f.origin.y, v.minY + 6), v.maxY - f.height - 6)
        if f != p.frame { p.setFrame(f, display: true) }
    }
}

extension FloatingPanel {
    override func cancelOperation(_ sender: Any?) { if keyable { orderOut(nil); Coach.shared.panelOpen = false } }
}
