import SwiftUI
import AppKit

/// Le cabinet de Petite Boule : la fenêtre qui s'ouvre quand on clique sur elle.
struct Cabinet: View {
    enum Tab: String, CaseIterable, Identifiable {
        case today, reviews, mood, settings
        var id: String { rawValue }
        var label: String { switch self { case .today: "Aujourd'hui"; case .reviews: "Révisions"; case .mood: "Ça va ?"; case .settings: "Réglages" } }
    }

    @ObservedObject var store = Store.shared
    @ObservedObject var nav: CabinetNav

    var body: some View {
        VStack(spacing: 0) {
            header
            tabs.padding(.horizontal, 18).padding(.bottom, 12)
            ScrollView {
                Group {
                    switch nav.tab {
                    case .today: TodayTab()
                    case .reviews: ReviewsTab()
                    case .mood: MoodTab()
                    case .settings: SettingsTab()
                    }
                }
                .padding(.horizontal, 18).padding(.bottom, 18)
            }
            .scrollIndicators(.never)
        }
        .frame(width: 440, height: 620)
        .background(Theme.bg)
        .preferredColorScheme(.dark)
    }

    private var header: some View {
        HStack(spacing: 12) {
            Boule(mood: .happy, size: 34, shadow: false).frame(width: 54, height: 44)
            VStack(alignment: .leading, spacing: 2) {
                Text(store.name.isEmpty ? "Le cabinet" : "Coucou \(store.name)").font(.system(size: 18, weight: .bold)).foregroundStyle(.white)
                Text(Day.longToday()).font(.system(size: 12, weight: .semibold)).foregroundStyle(.white.opacity(0.45))
            }
            Spacer()
            progress
        }
        .padding(.horizontal, 18).padding(.top, 4).padding(.bottom, 14)
    }

    private var progress: some View {
        let total = store.todayTodos.count + store.dueReviews.count + store.data.courses.filter { $0.doneOn == Day.key() }.count
        let done = store.todayTodos.filter(\.done).count + store.data.courses.filter { $0.doneOn == Day.key() }.count
        let f = total == 0 ? 0 : Double(done) / Double(total)
        return ZStack {
            Circle().stroke(.white.opacity(0.08), lineWidth: 4)
            Circle().trim(from: 0, to: f).stroke(Theme.done, style: StrokeStyle(lineWidth: 4, lineCap: .round)).rotationEffect(.degrees(-90))
            Text("\(done)/\(total)").font(.system(size: 11, weight: .bold)).foregroundStyle(.white.opacity(0.8))
        }
        .frame(width: 44, height: 44)
        .animation(.spring(response: 0.5, dampingFraction: 0.8), value: f)
        .opacity(total == 0 ? 0 : 1)
    }

    private var tabs: some View {
        HStack(spacing: 4) {
            ForEach(Tab.allCases) { t in
                Button { withAnimation(.snappy(duration: 0.2)) { nav.tab = t } } label: {
                    Text(t.label)
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(nav.tab == t ? .black : .white.opacity(0.6))
                        .frame(maxWidth: .infinity).padding(.vertical, 7)
                        .background { if nav.tab == t { Capsule().fill(.white) } }
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(.white.opacity(0.06), in: Capsule())
    }
}

final class CabinetNav: ObservableObject {
    @Published var tab: Cabinet.Tab = .today
}

// MARK: - Aujourd'hui

private struct TodayTab: View {
    @ObservedObject var store = Store.shared
    @ObservedObject var msg = Messages.shared
    @State private var newTodo = ""

    var body: some View {
        VStack(spacing: 12) {
            Card(title: "À faire", trailing: count) {
                VStack(spacing: 2) {
                    ForEach(store.todayTodos) { t in TodoRow(todo: t) }
                }
                Field(placeholder: "Ajouter une tâche… (Entrée)", text: $newTodo) {
                    store.addTodo(newTodo); newTodo = ""
                }
            }
            Card(title: "Révisions du jour", trailing: "méthode des J") {
                let due = store.dueReviews, done = store.reviewsDoneToday
                if due.isEmpty && done.isEmpty {
                    Text("Aucune révision prévue aujourd'hui. Ajoute tes cours dans l'onglet Révisions : je te les ressortirai au bon moment.")
                        .font(.system(size: 12.5, weight: .medium)).foregroundStyle(.white.opacity(0.5))
                        .fixedSize(horizontal: false, vertical: true)
                }
                ForEach(due, id: \.course.id) { item in ReviewRow(course: item.course, review: item.review, done: false) }
                ForEach(done, id: \.course.id) { item in ReviewRow(course: item.course, review: item.review, done: true) }
            }
            if let c = store.challenge(from: msg.list("defis")) {
                Card(title: "Défi bien-être du jour") {
                    Button {
                        store.challengeDone.toggle()
                        if store.challengeDone { Coach.shared.celebrate() }
                    } label: {
                        HStack(spacing: 10) {
                            CheckCircle(on: store.challengeDone)
                            Text(c).font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(.white.opacity(store.challengeDone ? 0.45 : 0.9))
                                .strikethrough(store.challengeDone, color: .white.opacity(0.4))
                                .multilineTextAlignment(.leading)
                            Spacer()
                            Text("🌱")
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var count: String? {
        let t = store.todayTodos
        return t.isEmpty ? nil : "\(t.filter(\.done).count)/\(t.count)"
    }
}

private struct TodoRow: View {
    let todo: Todo
    @State private var hover = false
    var body: some View {
        HStack(spacing: 10) {
            Button {
                if Store.shared.toggle(todo) { Coach.shared.celebrate() }
            } label: {
                HStack(spacing: 10) {
                    CheckCircle(on: todo.done)
                    Text(todo.title).font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white.opacity(todo.done ? 0.4 : 0.92))
                        .strikethrough(todo.done, color: .white.opacity(0.4))
                        .multilineTextAlignment(.leading)
                    if todo.carried && !todo.done {
                        Text("d'hier").font(.system(size: 10, weight: .bold)).foregroundStyle(.white.opacity(0.5))
                            .padding(.horizontal, 6).padding(.vertical, 2).background(.white.opacity(0.08), in: Capsule())
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            Button { withAnimation { Store.shared.delete(todo) } } label: {
                Image(systemName: "xmark").font(.system(size: 10, weight: .bold)).foregroundStyle(.white.opacity(0.4))
            }
            .buttonStyle(.plain).opacity(hover ? 1 : 0).help("Supprimer")
        }
        .padding(.vertical, 5)
        .onHover { hover = $0 }
    }
}

private struct ReviewRow: View {
    let course: Course
    let review: Review
    let done: Bool
    var body: some View {
        Button {
            if Store.shared.toggleReview(course) { Coach.shared.celebrate() }
        } label: {
            HStack(spacing: 10) {
                CheckCircle(on: done)
                VStack(alignment: .leading, spacing: 1) {
                    Text(course.title).font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white.opacity(done ? 0.4 : 0.92))
                        .strikethrough(done, color: .white.opacity(0.4))
                    if !course.subject.isEmpty {
                        Text(course.subject).font(.system(size: 11, weight: .medium)).foregroundStyle(.white.opacity(0.4))
                    }
                }
                Spacer()
                if review.day < Day.key() && !done {
                    Text("en retard").font(.system(size: 10, weight: .bold)).foregroundStyle(Theme.soft.opacity(0.9))
                }
                Text("J\(review.j)").font(.system(size: 11, weight: .heavy)).foregroundStyle(.black.opacity(0.8))
                    .padding(.horizontal, 7).padding(.vertical, 3).background(.white.opacity(done ? 0.35 : 0.85), in: Capsule())
            }
            .padding(.vertical, 5)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Révisions (méthode des J)

private struct ReviewsTab: View {
    @ObservedObject var store = Store.shared
    @State private var subject = ""
    @State private var title = ""
    @State private var learned = Date()

    var body: some View {
        VStack(spacing: 12) {
            Card(title: "J'ai appris un cours") {
                Text("Ajoute un cours le jour où tu l'apprends : je te le ressors à \(store.settings.intervals.sorted().map { "J\($0)" }.joined(separator: ", ")). Revoir au bon moment, c'est ce qui fait tenir la mémoire.")
                    .font(.system(size: 12, weight: .medium)).foregroundStyle(.white.opacity(0.5))
                    .fixedSize(horizontal: false, vertical: true)
                Field(placeholder: "Matière (ex. Cardiologie)", text: $subject)
                if !store.subjects.isEmpty && subject.isEmpty {
                    ScrollView(.horizontal) {
                        HStack(spacing: 5) {
                            ForEach(store.subjects, id: \.self) { s in
                                Button(s) { subject = s }.buttonStyle(PillStyle())
                            }
                        }
                    }
                    .scrollIndicators(.never)
                }
                Field(placeholder: "Cours (ex. Insuffisance cardiaque)", text: $title) { add() }
                HStack {
                    DatePicker("Appris le", selection: $learned, in: ...Date(), displayedComponents: .date)
                        .datePickerStyle(.compact).font(.system(size: 12, weight: .semibold)).foregroundStyle(.white.opacity(0.6))
                        .environment(\.locale, Locale(identifier: "fr_FR"))
                    Spacer()
                    Button("Ajouter") { add() }.buttonStyle(PillStyle(primary: true))
                        .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            let courses = store.data.courses.sorted { ($0.next?.day ?? "9999") < ($1.next?.day ?? "9999") }
            Card(title: "Mes cours", trailing: courses.isEmpty ? nil : "\(courses.count)") {
                if courses.isEmpty {
                    Text("Pas encore de cours. Le premier, c'est le plus dur à ajouter !")
                        .font(.system(size: 12.5, weight: .medium)).foregroundStyle(.white.opacity(0.5))
                }
                ForEach(courses) { c in CourseRow(course: c) }
            }
        }
    }

    private func add() {
        store.addCourse(subject: subject, title: title, learned: learned)
        title = ""
        learned = Date()
        Coach.shared.hop += 1
    }
}

private struct CourseRow: View {
    let course: Course
    @State private var hover = false
    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text(course.title).font(.system(size: 13, weight: .semibold)).foregroundStyle(.white.opacity(0.92))
                HStack(spacing: 6) {
                    if !course.subject.isEmpty {
                        Text(course.subject).font(.system(size: 11, weight: .medium)).foregroundStyle(.white.opacity(0.4))
                    }
                    HStack(spacing: 3) {
                        ForEach(Array(course.reviews.enumerated()), id: \.offset) { _, r in
                            Circle()
                                .fill(r.done ? Theme.done : (r.day <= Day.key() ? Color.white : .clear))
                                .overlay(Circle().strokeBorder(.white.opacity(r.done ? 0 : 0.35), lineWidth: 1))
                                .frame(width: 7, height: 7)
                                .help("J\(r.j)")
                        }
                    }
                }
            }
            Spacer()
            if let n = course.next {
                Text("J\(n.j) \(Day.label(n.day))").font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(n.day <= Day.key() ? .white : .white.opacity(0.45))
            } else {
                Text("terminé ✓").font(.system(size: 11, weight: .bold)).foregroundStyle(Theme.done)
            }
            Button { withAnimation { Store.shared.deleteCourse(course) } } label: {
                Image(systemName: "xmark").font(.system(size: 10, weight: .bold)).foregroundStyle(.white.opacity(0.4))
            }
            .buttonStyle(.plain).opacity(hover ? 1 : 0).help("Supprimer ce cours")
        }
        .padding(.vertical, 5)
        .onHover { hover = $0 }
    }
}

// MARK: - Ça va ?

private struct MoodTab: View {
    @ObservedObject var store = Store.shared
    @ObservedObject var msg = Messages.shared
    @State private var copied: String?

    var body: some View {
        VStack(spacing: 12) {
            Card(title: "Là, maintenant, tu te sens comment ?") {
                HStack(spacing: 8) {
                    moodButton(2, "Bien", .happy)
                    moodButton(1, "Bof", .calm)
                    moodButton(0, "Pas top", .sad)
                }
            }
            Card(title: "Ta semaine") {
                HStack(spacing: 0) {
                    ForEach(store.week, id: \.day) { d in
                        VStack(spacing: 6) {
                            Circle()
                                .fill(color(d.level))
                                .overlay(Circle().strokeBorder(.white.opacity(d.level == nil ? 0.2 : 0), lineWidth: 1))
                                .frame(width: 18, height: 18)
                            Text(letter(d.day)).font(.system(size: 10.5, weight: .bold))
                                .foregroundStyle(.white.opacity(d.day == Day.key() ? 0.9 : 0.4))
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
                Text("Vert : ça allait · blanc : bof · rose : journée difficile")
                    .font(.system(size: 10.5, weight: .medium)).foregroundStyle(.white.opacity(0.35))
            }
            Card(title: "Boîte à outils") {
                tool("wind", "Respirer 1 minute avec moi", "cohérence cardiaque, 5 s / 5 s") { Coach.shared.breathe() }
                tool("cup.and.saucer", "Pause de 5 minutes", "je te fais signe quand c'est fini") { Coach.shared.pause() }
                tool("shoeprints.fill", "Un tout petit pas", "quand la montagne paraît trop haute") { Coach.shared.smallStep() }
                if !msg.list("motsDoux").isEmpty {
                    tool("heart", "Un mot de \(msg.from)", "pour quand tu en as besoin") { Coach.shared.loveNote() }
                }
            }
            Card(title: "Si c'est trop lourd") {
                Text("Tu n'as pas à porter ça seule. Ces lignes sont gratuites et confidentielles :")
                    .font(.system(size: 12.5, weight: .medium)).foregroundStyle(.white.opacity(0.6))
                    .fixedSize(horizontal: false, vertical: true)
                line("SPS", "0 805 23 23 36", "Soignants et étudiants en santé · psychologues, 24h/24, anonyme")
                line("Étudiants", "3040", "Ligne nationale d'écoute pour les étudiants")
                line("Idées noires", "3114", "Prévention du suicide, 24h/24, pour toi ou un proche")
                line("Urgence", "15", "SAMU")
            }
        }
    }

    private func moodButton(_ level: Int, _ label: String, _ mood: Boule.Mood) -> some View {
        Button { Coach.shared.answer(level) } label: {
            VStack(spacing: 2) {
                Boule(mood: mood, size: 30, shadow: false).frame(width: 50, height: 40)
                Text(label).font(.system(size: 12, weight: .bold)).foregroundStyle(.white.opacity(0.85))
            }
            .frame(maxWidth: .infinity).padding(.vertical, 8)
            .background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func tool(_ icon: String, _ title: String, _ hint: String, _ run: @escaping () -> Void) -> some View {
        Button(action: run) {
            HStack(spacing: 12) {
                Image(systemName: icon).font(.system(size: 14, weight: .semibold)).foregroundStyle(.white.opacity(0.8)).frame(width: 22)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).font(.system(size: 13, weight: .semibold)).foregroundStyle(.white.opacity(0.92))
                    Text(hint).font(.system(size: 11, weight: .medium)).foregroundStyle(.white.opacity(0.4))
                }
                Spacer()
                Image(systemName: "chevron.right").font(.system(size: 10, weight: .bold)).foregroundStyle(.white.opacity(0.3))
            }
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func line(_ who: String, _ number: String, _ hint: String) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    Text(number).font(.system(size: 14, weight: .heavy)).foregroundStyle(.white)
                    Text(who).font(.system(size: 11, weight: .bold)).foregroundStyle(.white.opacity(0.45))
                }
                Text(hint).font(.system(size: 11, weight: .medium)).foregroundStyle(.white.opacity(0.4))
            }
            Spacer()
            Button(copied == number ? "Copié" : "Copier") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(number.replacingOccurrences(of: " ", with: ""), forType: .string)
                copied = number
            }
            .buttonStyle(PillStyle())
        }
        .padding(.vertical, 3)
    }

    private func color(_ l: Double?) -> Color {
        guard let l else { return .clear }
        if l >= 1.5 { return Theme.done }
        if l >= 0.75 { return .white.opacity(0.75) }
        return Theme.soft
    }

    private func letter(_ k: String) -> String {
        let f = DateFormatter(); f.locale = Locale(identifier: "fr_FR"); f.dateFormat = "EEEEE"
        return f.string(from: Day.date(k)).uppercased()
    }
}

// MARK: - Réglages

private struct SettingsTab: View {
    @ObservedObject var store = Store.shared
    @ObservedObject var updater = Updater.shared
    @State private var intervals = ""
    @State private var login = LoginItem.enabled

    var body: some View {
        VStack(spacing: 12) {
            Card(title: "Toi") {
                Field(placeholder: "Ton prénom", text: Binding(get: { store.settings.name }, set: { store.settings.name = $0 }))
            }
            Card(title: "Petite Boule passe te voir") {
                HStack(spacing: 4) {
                    ForEach(Rhythm.allCases) { r in
                        Button { store.settings.rhythm = r } label: {
                            Text(r.label).font(.system(size: 12, weight: .bold))
                                .foregroundStyle(store.settings.rhythm == r ? .black : .white.opacity(0.6))
                                .frame(maxWidth: .infinity).padding(.vertical, 7)
                                .background { if store.settings.rhythm == r { Capsule().fill(.white) } }
                                .contentShape(Capsule())
                        }.buttonStyle(.plain)
                    }
                }
                .padding(3).background(.white.opacity(0.06), in: Capsule())
                Text(store.settings.rhythm.hint + ", seulement quand tu es devant l'écran et jamais pendant un film en plein écran.")
                    .font(.system(size: 11.5, weight: .medium)).foregroundStyle(.white.opacity(0.45))
                    .fixedSize(horizontal: false, vertical: true)
                HStack {
                    Text("Entre").foregroundStyle(.white.opacity(0.6))
                    Stepper("\(store.settings.startHour) h", value: Binding(get: { store.settings.startHour },
                                                                       set: { store.settings.startHour = min($0, store.settings.endHour - 1) }), in: 5...22)
                    Text("et").foregroundStyle(.white.opacity(0.6))
                    Stepper("\(store.settings.endHour) h", value: Binding(get: { store.settings.endHour },
                                                                     set: { store.settings.endHour = max($0, store.settings.startHour + 1) }), in: 6...23)
                }
                .font(.system(size: 12.5, weight: .semibold))
            }
            Card(title: "Où elle se range") {
                HStack(spacing: 14) {
                    VStack(spacing: 6) {
                        HStack(spacing: 6) { cornerButton(.topLeft); cornerButton(.topRight) }
                        HStack(spacing: 6) { cornerButton(.bottomLeft); cornerButton(.bottomRight) }
                    }
                    Text("Tu peux aussi la faire glisser vers n'importe quel coin, même sur un autre écran.")
                        .font(.system(size: 11.5, weight: .medium)).foregroundStyle(.white.opacity(0.45))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Card(title: "Méthode des J") {
                HStack {
                    Field(placeholder: "1, 3, 7, 14, 30", text: $intervals) { saveIntervals() }
                    Button("OK") { saveIntervals() }.buttonStyle(PillStyle(primary: true))
                }
                Text("Les jours de révision après avoir appris un cours (pour les prochains cours ajoutés).")
                    .font(.system(size: 11.5, weight: .medium)).foregroundStyle(.white.opacity(0.45))
            }
            Card(title: "L'app") {
                Toggle(isOn: $login) {
                    Text("Ouvrir Petite Boule au démarrage du Mac").font(.system(size: 12.5, weight: .semibold)).foregroundStyle(.white.opacity(0.85))
                }
                .toggleStyle(.switch).tint(Theme.done)
                .onChange(of: login) { _, v in v ? LoginItem.enable() : LoginItem.disable(); login = LoginItem.enabled }
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Version \(Updater.currentVersion)").font(.system(size: 12.5, weight: .semibold)).foregroundStyle(.white.opacity(0.85))
                        Text(updater.status).font(.system(size: 11, weight: .medium)).foregroundStyle(.white.opacity(0.4))
                    }
                    Spacer()
                    Button("Vérifier") { updater.check(manual: true) }.buttonStyle(PillStyle())
                }
                HStack {
                    Button("Me cacher 1 h") { Coach.shared.hide(hours: 1) }.buttonStyle(PillStyle())
                    Button("Jusqu'à demain") { Coach.shared.hideUntilTomorrow() }.buttonStyle(PillStyle())
                    Spacer()
                    Button("Quitter") { NSApp.terminate(nil) }.buttonStyle(PillStyle())
                }
            }
        }
        .onAppear { intervals = store.settings.intervals.sorted().map(String.init).joined(separator: ", ") }
    }

    private func cornerButton(_ c: Corner) -> some View {
        Button { AppDelegate.shared?.mascot.setCorner(c) } label: {
            RoundedRectangle(cornerRadius: 4)
                .fill(store.settings.corner == c ? Color.white : Color.white.opacity(0.1))
                .frame(width: 26, height: 17)
        }
        .buttonStyle(.plain)
    }

    private func saveIntervals() {
        let n = intervals.split(whereSeparator: { !$0.isNumber }).compactMap { Int($0) }.filter { $0 > 0 && $0 <= 365 }
        if !n.isEmpty { store.settings.intervals = Array(Set(n)).sorted() }
        intervals = store.settings.intervals.map(String.init).joined(separator: ", ")
    }
}
