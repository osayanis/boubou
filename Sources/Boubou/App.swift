import SwiftUI
import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    static var shared: AppDelegate?

    let mascot = MascotController()
    let quick = PanelController()
    private let coach = Coach.shared
    private var status: NSStatusItem!

    func applicationDidFinishLaunching(_ n: Notification) {
        Self.shared = self

        // Un seul Boubou à la fois.
        let others = NSRunningApplication.runningApplications(withBundleIdentifier: Bundle.main.bundleIdentifier ?? "")
            .filter { $0 != .current }
        if !others.isEmpty, Bundle.main.bundleIdentifier != nil { NSApp.terminate(nil); return }

        BubbleController.shared.mascot = mascot
        FX.shared.mascot = mascot
        BubbleGame.shared.mascot = mascot
        quick.mascot = mascot
        mascot.onClick = { [weak self] in self?.mascotClicked() }
        mascot.menu = { [weak self] in self?.buildMenu() ?? NSMenu() }
        mascot.updateVisibility()
        coach.onTogglePanel = { [weak self] in self?.quick.toggle() }
        coach.onClosePanel = { [weak self] in self?.quick.close() }

        // Un petit stéthoscope dans la barre des menus : pour le retrouver s'il est caché.
        status = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        status.button?.image = NSImage(systemSymbolName: "stethoscope", accessibilityDescription: "Boubou")
        status.menu = NSMenu()
        status.menu?.delegate = self

        Messages.shared.refresh()
        Timer.scheduledTimer(withTimeInterval: 3 * 3600, repeats: true) { _ in
            MainActor.assumeIsolated { Messages.shared.refresh() }
        }
        Link.shared.onLove = { name in Coach.shared.yanisLove(name) }
        Link.shared.start()
        coach.start()
        Updater.shared.start()

        if CommandLine.arguments.contains("--mise-a-jour") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 4) { self.coach.updated(to: Updater.currentVersion) }
        }
        Demo.run(self)
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        coach.show(); mascot.updateVisibility()
        if coach.sleeping { coach.wake() } else { quick.open() }
        return false
    }

    private func mascotClicked() {
        // Une bulle sans bouton : un clic la ferme. Sinon le clic ouvre / ferme le panneau.
        if let b = coach.bubble, b.actions.isEmpty { coach.dismiss(); return }
        quick.toggle()
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        for i in buildMenu().items { i.menu?.removeItem(i); menu.addItem(i) }
    }

    fileprivate func buildMenu() -> NSMenu {
        let m = NSMenu()
        func item(_ t: String, _ run: @escaping () -> Void) { m.addItem(ClosureItem(title: t, run: run)) }
        func awake(_ run: @escaping () -> Void) -> () -> Void {
            { self.coach.show(); self.mascot.updateVisibility(); self.coach.wake(silent: true); run() }
        }
        item("Ma journée") { awake { self.quick.open() }() }
        item(coach.sleeping ? "Réveiller Boubou" : "Boubou va dormir (double-clic)") {
            self.coach.sleeping ? self.coach.wake() : self.coach.sleep()
        }
        m.addItem(.separator())
        item("Respirer 1 minute", awake { self.coach.breathe() })
        item("S'étirer", awake { self.coach.stretch() })
        item("Bulles anti-stress", awake { BubbleGame.shared.start() })
        item(coach.focusing ? "Arrêter le focus" : "Focus 25 minutes", awake { self.coach.focusing ? self.coach.stopFocus() : self.coach.startFocus() })
        m.addItem(.separator())
        if coach.hidden {
            item("Faire revenir Boubou") { self.coach.show() }
        } else {
            item("Cacher Boubou 1 heure") { self.coach.hide(hours: 1) }
        }
        item("Quitter Boubou") { NSApp.terminate(nil) }
        return m
    }
}

final class ClosureItem: NSMenuItem {
    private let run: () -> Void
    init(title: String, run: @escaping () -> Void) {
        self.run = run
        super.init(title: title, action: #selector(fire), keyEquivalent: "")
        target = self
    }
    required init(coder: NSCoder) { fatalError() }
    @objc private func fire() { run() }
}
