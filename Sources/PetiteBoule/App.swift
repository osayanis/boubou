import SwiftUI
import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    static var shared: AppDelegate?

    let mascot = MascotController()
    private let coach = Coach.shared
    private let nav = CabinetNav()
    private var cabinet: NSWindow?
    private var status: NSStatusItem!

    func applicationDidFinishLaunching(_ n: Notification) {
        Self.shared = self

        // Une seule Petite Boule à la fois.
        let others = NSRunningApplication.runningApplications(withBundleIdentifier: Bundle.main.bundleIdentifier ?? "")
            .filter { $0 != .current }
        if !others.isEmpty, Bundle.main.bundleIdentifier != nil { NSApp.terminate(nil); return }

        BubbleController.shared.mascot = mascot
        mascot.onClick = { [weak self] in self?.mascotClicked() }
        mascot.menu = { [weak self] in self?.buildMenu() ?? NSMenu() }
        mascot.updateVisibility()
        coach.onOpenCabinet = { [weak self] tab in self?.openCabinet(tab) }

        // Un petit stéthoscope dans la barre des menus : pour la retrouver si elle est cachée.
        status = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        status.button?.image = NSImage(systemSymbolName: "stethoscope", accessibilityDescription: "Petite Boule")
        status.menu = NSMenu()
        status.menu?.delegate = self

        Messages.shared.refresh()
        Timer.scheduledTimer(withTimeInterval: 3 * 3600, repeats: true) { _ in
            MainActor.assumeIsolated { Messages.shared.refresh() }
        }
        coach.start()
        Updater.shared.start()

        if CommandLine.arguments.contains("--mise-a-jour") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 4) { self.coach.updated(to: Updater.currentVersion) }
        }
        Demo.run(self)
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        coach.show(); mascot.updateVisibility()
        openCabinet(nav.tab)
        return false
    }

    private func mascotClicked() {
        // Une bulle sans bouton : un clic la ferme. Sinon le clic ouvre / ferme le cabinet.
        if let b = coach.bubble, b.actions.isEmpty, b.input == nil { coach.dismiss(); return }
        if cabinet?.isVisible == true { cabinet?.close() } else { openCabinet(.today) }
    }

    func openCabinet(_ tab: Cabinet.Tab) {
        nav.tab = tab
        if cabinet == nil {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 440, height: 620),
                             styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView], backing: .buffered, defer: false)
            w.titleVisibility = .hidden
            w.titlebarAppearsTransparent = true
            w.isMovableByWindowBackground = true
            w.backgroundColor = NSColor(red: 0.04, green: 0.04, blue: 0.06, alpha: 1)
            w.appearance = NSAppearance(named: .darkAqua)
            w.title = "Petite Boule"
            w.contentViewController = NSHostingController(rootView: Cabinet(nav: nav))
            w.isReleasedWhenClosed = false
            w.delegate = self
            cabinet = w
        }
        guard let w = cabinet else { return }
        if !w.isVisible {
            // Le cabinet s'ouvre à côté de la mascotte, pas au milieu de l'écran.
            let m = mascot.panel.frame
            let v = (mascot.panel.screen ?? NSScreen.main!).visibleFrame
            let c = Store.shared.settings.corner
            var o = NSPoint(x: c.right ? m.minX - w.frame.width + 10 : m.maxX - 10,
                            y: c.bottom ? m.minY : m.maxY - w.frame.height)
            o.x = min(max(o.x, v.minX + 8), v.maxX - w.frame.width - 8)
            o.y = min(max(o.y, v.minY + 8), v.maxY - w.frame.height - 8)
            w.setFrameOrigin(o)
        }
        coach.cabinetOpen = true
        NSApp.setActivationPolicy(.accessory)
        NSApp.activate(ignoringOtherApps: true)
        w.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ n: Notification) {
        if (n.object as? NSWindow) === cabinet { coach.cabinetOpen = false }
    }

    fileprivate func buildMenu() -> NSMenu {
        let m = NSMenu()
        func item(_ t: String, _ run: @escaping () -> Void) {
            let i = ClosureItem(title: t, run: run)
            m.addItem(i)
        }
        item("Ouvrir le cabinet") { self.openCabinet(.today) }
        item("Comment ça va ?") { self.coach.show(); self.mascot.updateVisibility(); self.coach.checkin() }
        item("Revoir ma journée") { self.coach.show(); self.mascot.updateVisibility(); self.coach.morning() }
        item("Respirer 1 minute") { self.coach.show(); self.mascot.updateVisibility(); self.coach.breathe() }
        m.addItem(.separator())
        if coach.hidden {
            item("Faire revenir Petite Boule") { self.coach.show() }
        } else {
            item("Me cacher 1 heure") { self.coach.hide(hours: 1) }
            item("Me cacher jusqu'à demain") { self.coach.hideUntilTomorrow() }
        }
        m.addItem(.separator())
        item("Réglages…") { self.openCabinet(.settings) }
        item("Quitter Petite Boule") { NSApp.terminate(nil) }
        return m
    }
}

extension AppDelegate: NSMenuDelegate {
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        for i in buildMenu().items { i.menu?.removeItem(i); menu.addItem(i) }
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
