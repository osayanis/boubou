import AppKit

/// `PETITEBOULE_DEMO=matin|question|bien|bof|mal|respire|mot|soir|cabinet|revisions|cava|reglages|accueil`
/// déclenche une scène tout de suite (pour essayer et faire des captures).
enum Demo {
    @MainActor static func run(_ app: AppDelegate) {
        guard let scene = ProcessInfo.processInfo.environment["PETITEBOULE_DEMO"] else { return }
        let coach = Coach.shared
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            switch scene {
            case "accueil": break
            case "matin": coach.morning()
            case "question": coach.checkin()
            case "bien": coach.answer(2)
            case "bof": coach.answer(1)
            case "mal": coach.answer(0)
            case "respire": coach.breathe()
            case "mot": coach.nudge()
            case "doux": coach.loveNote()
            case "pas": coach.smallStep()
            case "cabinet": app.openCabinet(.today)
            case "revisions": app.openCabinet(.reviews)
            case "cava": app.openCabinet(.mood)
            case "reglages": app.openCabinet(.settings)
            default: break
            }
        }
    }
}
