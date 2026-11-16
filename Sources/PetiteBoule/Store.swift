import Foundation
import SwiftUI

/// Les jours sont des clés « 2026-11-16 » (heure locale) : simples à comparer et à enregistrer.
enum Day {
    private static let f: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()
    static func key(_ d: Date = Date()) -> String { f.string(from: d) }
    static func date(_ k: String) -> Date { f.date(from: k) ?? Date() }
    static func add(_ n: Int, to k: String) -> String {
        key(Calendar.current.date(byAdding: .day, value: n, to: date(k)) ?? Date())
    }
    static func between(_ a: String, _ b: String) -> Int {
        Calendar.current.dateComponents([.day], from: date(a), to: date(b)).day ?? 0
    }
    /// « aujourd'hui », « demain », « dans 3 jours », « jeudi 20 nov. »
    static func label(_ k: String) -> String {
        let n = between(key(), k)
        switch n {
        case ..<0: return "en retard"
        case 0: return "aujourd'hui"
        case 1: return "demain"
        case 2...6: return "dans \(n) jours"
        default:
            let f = DateFormatter(); f.locale = Locale(identifier: "fr_FR"); f.dateFormat = "EEE d MMM"
            return f.string(from: date(k))
        }
    }
    static func longToday() -> String {
        let f = DateFormatter(); f.locale = Locale(identifier: "fr_FR"); f.dateFormat = "EEEE d MMMM"
        let t = f.string(from: Date())
        return t.prefix(1).uppercased() + t.dropFirst()
    }
}

struct Todo: Codable, Identifiable, Equatable {
    var id = UUID()
    var title: String
    var day: String
    var done = false
    var carried = false
}

struct Review: Codable, Equatable {
    var day: String
    var j: Int
    var done = false
}

/// Un cours appris, et ses révisions espacées (méthode des J).
struct Course: Codable, Identifiable, Equatable {
    var id = UUID()
    var subject: String
    var title: String
    var learned: String
    var reviews: [Review]
    var doneOn: String? = nil
    var next: Review? { reviews.first { !$0.done } }
}

struct MoodEntry: Codable, Equatable {
    var date: Date
    var level: Int        // 2 bien, 1 bof, 0 pas top
}

enum Rhythm: String, Codable, CaseIterable, Identifiable {
    case rare, normal, often
    var id: String { rawValue }
    var minutes: Double { switch self { case .rare: 180; case .normal: 120; case .often: 70 } }
    var label: String { switch self { case .rare: "Rarement"; case .normal: "Normalement"; case .often: "Souvent" } }
    var hint: String { switch self { case .rare: "toutes les 3 h environ"; case .normal: "toutes les 2 h environ"; case .often: "toutes les heures environ" } }
}

enum Corner: Int, Codable, CaseIterable {
    case bottomRight, bottomLeft, topRight, topLeft
    var right: Bool { self == .bottomRight || self == .topRight }
    var bottom: Bool { self == .bottomRight || self == .bottomLeft }
}

struct Settings: Codable, Equatable {
    var name = ""
    var startHour = 8
    var endHour = 21
    var rhythm = Rhythm.normal
    var corner = Corner.bottomRight
    var screen: String? = nil
    var intervals = [1, 3, 7, 14, 30]
    var onboarded = false

    init() {}
    // Lecture tolérante : une version plus récente qui ajoute un réglage ne perd pas les autres.
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        var s = Settings()
        s.name = (try? c.decodeIfPresent(String.self, forKey: .name)) ?? s.name
        s.startHour = (try? c.decodeIfPresent(Int.self, forKey: .startHour)) ?? s.startHour
        s.endHour = (try? c.decodeIfPresent(Int.self, forKey: .endHour)) ?? s.endHour
        s.rhythm = (try? c.decodeIfPresent(Rhythm.self, forKey: .rhythm)) ?? s.rhythm
        s.corner = (try? c.decodeIfPresent(Corner.self, forKey: .corner)) ?? s.corner
        s.screen = (try? c.decodeIfPresent(String.self, forKey: .screen)) ?? nil
        s.intervals = (try? c.decodeIfPresent([Int].self, forKey: .intervals)) ?? s.intervals
        s.onboarded = (try? c.decodeIfPresent(Bool.self, forKey: .onboarded)) ?? s.onboarded
        self = s
    }
}

struct Saved: Codable {
    var todos: [Todo] = []
    var courses: [Course] = []
    var moods: [MoodEntry] = []
    var settings = Settings()
    var lastBrief: String? = nil
    var lastEvening: String? = nil
    var lastLate: String? = nil
    var challengeDone: String? = nil
    var lastContact: Date? = nil
    var checkins: [String: Int] = [:]

    init() {}
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        todos = (try? c.decodeIfPresent([Todo].self, forKey: .todos)) ?? []
        courses = (try? c.decodeIfPresent([Course].self, forKey: .courses)) ?? []
        moods = (try? c.decodeIfPresent([MoodEntry].self, forKey: .moods)) ?? []
        settings = (try? c.decodeIfPresent(Settings.self, forKey: .settings)) ?? Settings()
        lastBrief = try? c.decodeIfPresent(String.self, forKey: .lastBrief)
        lastEvening = try? c.decodeIfPresent(String.self, forKey: .lastEvening)
        lastLate = try? c.decodeIfPresent(String.self, forKey: .lastLate)
        challengeDone = try? c.decodeIfPresent(String.self, forKey: .challengeDone)
        lastContact = try? c.decodeIfPresent(Date.self, forKey: .lastContact)
        checkins = (try? c.decodeIfPresent([String: Int].self, forKey: .checkins)) ?? [:]
    }
}

/// Tout ce que Petite Boule retient, dans ~/Library/Application Support/PetiteBoule/donnees.json.
/// (Rien ne quitte le Mac.)
@MainActor
final class Store: ObservableObject {
    static let shared = Store()

    @Published var data = Saved() { didSet { save() } }

    let folder: URL
    private var file: URL { folder.appendingPathComponent("donnees.json") }

    private init() {
        if let custom = ProcessInfo.processInfo.environment["PETITEBOULE_DOSSIER"] {
            folder = URL(fileURLWithPath: custom)
        } else {
            folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("PetiteBoule")
        }
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        if let d = try? Data(contentsOf: file) {
            let dec = JSONDecoder(); dec.dateDecodingStrategy = .iso8601
            if let s = try? dec.decode(Saved.self, from: d) { data = s }
            else { try? FileManager.default.copyItem(at: file, to: folder.appendingPathComponent("donnees-illisibles-\(Int(Date().timeIntervalSince1970)).json")) }
        }
        rollOver()
    }

    private func save() {
        let enc = JSONEncoder(); enc.dateEncodingStrategy = .iso8601; enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let d = try? enc.encode(data) else { return }
        try? d.write(to: file, options: .atomic)
    }

    var settings: Settings {
        get { data.settings }
        set { data.settings = newValue }
    }
    var name: String { data.settings.name.trimmingCharacters(in: .whitespaces) }

    // MARK: Tâches

    /// Ce qui n'a pas été fait les jours d'avant passe à aujourd'hui.
    func rollOver() {
        let today = Day.key()
        var changed = false
        var t = data.todos
        for i in t.indices where !t[i].done && t[i].day < today {
            t[i].day = today; t[i].carried = true; changed = true
        }
        // on oublie les tâches faites il y a plus de 30 jours
        let old = Day.add(-30, to: today)
        let before = t.count
        t.removeAll { $0.done && $0.day < old }
        if changed || t.count != before { data.todos = t }
    }

    var todayTodos: [Todo] { data.todos.filter { $0.day == Day.key() } }

    func addTodo(_ title: String) {
        let t = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        data.todos.append(Todo(title: t, day: Day.key()))
    }

    /// Renvoie vrai si la tâche vient d'être cochée.
    @discardableResult
    func toggle(_ todo: Todo) -> Bool {
        guard let i = data.todos.firstIndex(where: { $0.id == todo.id }) else { return false }
        data.todos[i].done.toggle()
        return data.todos[i].done
    }

    func delete(_ todo: Todo) { data.todos.removeAll { $0.id == todo.id } }

    // MARK: Méthode des J

    func addCourse(subject: String, title: String, learned: Date = Date()) {
        let t = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        let start = Day.key(learned)
        let today = Day.key()
        var reviews = data.settings.intervals.sorted().map { Review(day: Day.add($0, to: start), j: $0) }
        // Ajouté après coup : les J déjà passés ne s'accumulent pas tous aujourd'hui,
        // seul le dernier passé reste à faire.
        let past = reviews.indices.filter { reviews[$0].day < today }
        for i in past.dropLast() { reviews[i].done = true }
        data.courses.append(Course(subject: subject.trimmingCharacters(in: .whitespaces), title: t, learned: start, reviews: reviews))
    }

    func deleteCourse(_ c: Course) { data.courses.removeAll { $0.id == c.id } }

    /// Les révisions à faire aujourd'hui (et celles en retard).
    var dueReviews: [(course: Course, review: Review)] {
        let today = Day.key()
        return data.courses.compactMap { c in
            guard let r = c.next, r.day <= today else { return nil }
            return (c, r)
        }
        .sorted { $0.review.day < $1.review.day }
    }

    /// Révisions cochées aujourd'hui (pour les garder visibles, barrées, dans la liste du jour).
    var reviewsDoneToday: [(course: Course, review: Review)] {
        let today = Day.key()
        return data.courses.compactMap { c in
            guard c.doneOn == today, let r = c.reviews.last(where: \.done) else { return nil }
            return (c, r)
        }
    }

    @discardableResult
    func toggleReview(_ course: Course) -> Bool {
        guard let i = data.courses.firstIndex(where: { $0.id == course.id }) else { return false }
        if let j = data.courses[i].reviews.firstIndex(where: { !$0.done }), data.courses[i].reviews[j].day <= Day.key() {
            data.courses[i].reviews[j].done = true
            data.courses[i].doneOn = Day.key()
            return true
        }
        // décocher : seulement la révision cochée aujourd'hui
        if data.courses[i].doneOn == Day.key(), let j = data.courses[i].reviews.lastIndex(where: { $0.done }) {
            data.courses[i].reviews[j].done = false
            data.courses[i].doneOn = nil
        }
        return false
    }

    var subjects: [String] {
        Array(Set(data.courses.map(\.subject).filter { !$0.isEmpty })).sorted()
    }

    // MARK: Défi bien-être

    func challenge(from list: [String]) -> String? {
        guard !list.isEmpty else { return nil }
        let k = Day.key()
        let n = k.unicodeScalars.reduce(7) { ($0 &* 31 &+ Int($1.value)) & 0xFFFFFF }
        return list[n % list.count]
    }
    var challengeDone: Bool {
        get { data.challengeDone == Day.key() }
        set { data.challengeDone = newValue ? Day.key() : nil }
    }

    // MARK: Humeur

    func recordMood(_ level: Int) {
        data.moods.append(MoodEntry(date: Date(), level: level))
        let limit = Date().addingTimeInterval(-60 * 86400)
        data.moods.removeAll { $0.date < limit }
    }

    /// Moyenne par jour, des 7 derniers jours (nil = pas de réponse ce jour-là).
    var week: [(day: String, level: Double?)] {
        (0..<7).reversed().map { back in
            let k = Day.add(-back, to: Day.key())
            let l = data.moods.filter { Day.key($0.date) == k }.map { Double($0.level) }
            return (k, l.isEmpty ? nil : l.reduce(0, +) / Double(l.count))
        }
    }

    /// Nombre de jours, parmi les 5 derniers, où elle a répondu « pas top » au moins une fois.
    var hardDays: Int {
        let since = Day.add(-4, to: Day.key())
        return Set(data.moods.filter { $0.level == 0 && Day.key($0.date) >= since }.map { Day.key($0.date) }).count
    }

    /// Ce qui a été coché aujourd'hui (tâches + révisions + défi).
    var doneToday: Int {
        todayTodos.filter(\.done).count + data.courses.filter { $0.doneOn == Day.key() }.count + (challengeDone ? 1 : 0)
    }
}
