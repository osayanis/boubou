import AppKit

/// `BOUBOU_DEMO=<scène>` déclenche une scène tout de suite (pour essayer et faire des captures) :
/// accueil matin question bien bof mal respire etire bulles focus dodo reveil caresse secoue yanis
/// anniversaire eau panneau · foyer : bain cuisine courses repas potager carotte niveau foyer mot
enum Demo {
    @MainActor static func run(_ app: AppDelegate) {
        guard let scene = ProcessInfo.processInfo.environment["BOUBOU_DEMO"] else { return }
        let coach = Coach.shared
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            switch scene {
            case "matin": coach.morning()
            case "question": coach.checkin()
            case "bien": coach.answer(2)
            case "bof": coach.answer(1)
            case "mal": coach.answer(0)
            case "respire": coach.breathe()
            case "etire": coach.stretch()
            case "bulles": BubbleGame.shared.start()
            case "focus": coach.startFocus(minutes: 0.5)
            case "dodo": coach.sleep()
            case "reveil": coach.sleep(); DispatchQueue.main.asyncAfter(deadline: .now() + 3) { coach.wake() }
            case "caresse": coach.petted()
            case "secoue": coach.shaking(); DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { coach.shaken() }
            case "yanis": coach.yanisLove("Yanis")
            case "anniversaire": coach.celebrateEvent(Messages.shared.fill("Joyeux anniversaire de couple, {prenom} & Yanis ! 💕🎉"))
            case "eau": coach.drink()
            case "panneau": app.quick.open()
            case "idle": coach.idle()
            case "bain": StageController.shared.jouer(SceneSpec(kind: .bain))
            case "cuisine": StageController.shared.jouer(SceneSpec(kind: .cuisine, emojis: ["🥚", "🌾", "🥛"], resultat: "🥞"))
            case "courses": StageController.shared.jouer(SceneSpec(kind: .courses))
            case "repas": StageController.shared.jouer(SceneSpec(kind: .repas, emojis: ["🥞"]))
            case "potager": StageController.shared.jouer(SceneSpec(kind: .recolter, emojis: ["🥕"]))
            case "carotte": CarrotController.shared.show()
            case "niveau": coach.niveau("Externe", cadeau: "Écharpe")
            case "foyer": UserDefaults.standard.set("boubou", forKey: "BoubouOnglet"); app.quick.open()
            case "mot": UserDefaults.standard.set("boubou", forKey: "BoubouOnglet"); Foyer.shared.ecrire = true; app.quick.open()
            default: break
            }
        }
    }
}
