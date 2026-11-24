import SwiftUI
import AppKit
import Combine

/// Panneau transparent, sans bord, qui ne vole pas le focus de l'app en cours.
final class FloatingPanel: NSPanel {
    var keyable = false
    init(size: NSSize) {
        super.init(contentRect: NSRect(origin: .zero, size: size),
                   styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = .floating
        // tous les bureaux, mais jamais par-dessus une app en plein écran (film, cours en visio…)
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        isMovable = false
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
    }
    override var canBecomeKey: Bool { keyable }
    override var canBecomeMain: Bool { false }
}

// MARK: - Boubou

private struct MascotView: View {
    @ObservedObject var coach: Coach
    @ObservedObject var foyer = Foyer.shared
    var body: some View {
        ZStack(alignment: .bottom) {
            if coach.sleeping {
                BedView(size: 96)
                    .transition(.scale(scale: 0.6, anchor: .bottom).combined(with: .opacity))
            } else if coach.scene == "bain" {
                BathView(size: 96)
                    .transition(.scale(scale: 0.6, anchor: .bottom).combined(with: .opacity))
            } else if coach.scene == "cuisine" {
                PotView(size: 92)
                    .transition(.scale(scale: 0.6, anchor: .bottom).combined(with: .opacity))
            } else {
                let e = foyer.etat
                // l'humeur du foyer quand rien d'autre ne se passe (faim, rhume, fatigue…)
                Boule(mood: coach.mood == .calm ? (e?.mood ?? .calm) : coach.mood, arms: coach.arms, look: coach.look,
                      size: MascotController.bodySize,
                      hop: coach.hop, breath: coach.breath, tilt: coach.tilt, hat: coach.hat,
                      accessoire: e?.accessoire, malade: e?.malade ?? false, sale: (e?.stat("toilette") ?? 100) < 20)
                    .transition(.scale(scale: 0.6, anchor: .bottom).combined(with: .opacity))
                    .padding(.bottom, 2)
            }
            if let b = foyer.etat?.besoin, !coach.sleeping, coach.scene == nil, coach.focusUntil == nil, coach.bubble == nil {
                Text(b).font(.system(size: 12))
                    .padding(4)
                    .background(.white, in: Circle())
                    .shadow(color: .black.opacity(0.25), radius: 3, y: 1)
                    .offset(x: 22, y: -52)
                    .transition(.scale.combined(with: .opacity))
                    .help("Boubou a besoin de toi")
            }
            if let end = coach.focusUntil, !coach.sleeping {
                TimelineView(.periodic(from: .now, by: 1)) { tl in
                    let left = max(0, Int(end.timeIntervalSince(tl.date)))
                    Text(String(format: "%d:%02d", left / 60, left % 60))
                        .font(.system(size: 10.5, weight: .heavy).monospacedDigit())
                        .foregroundStyle(.black.opacity(0.8))
                        .padding(.horizontal, 7).padding(.vertical, 2.5)
                        .background(.white, in: Capsule())
                        .shadow(color: .black.opacity(0.25), radius: 3, y: 1)
                }
                .offset(y: -60)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .animation(.spring(response: 0.45, dampingFraction: 0.75), value: coach.sleeping)
        .animation(.spring(response: 0.45, dampingFraction: 0.75), value: foyer.etat?.besoin)
    }
}

/// Clics, double-clics, glisser-déposer, caresses et secousses. Ne capte la souris que sur Boubou
/// (ou son lit) : le reste du panneau laisse passer les clics vers les fenêtres derrière.
private final class TouchView: NSView {
    var hitRect: () -> NSRect = { .zero }
    var onClick: () -> Void = {}
    var onDoubleClick: () -> Void = {}
    var onRightClick: (NSEvent) -> Void = { _ in }
    var onDrag: (NSPoint) -> Void = { _ in }
    var onDrop: (_ shaken: Bool) -> Void = { _ in }
    var onShake: () -> Void = {}
    var onPet: () -> Void = {}

    private var start: NSPoint?
    private var origin: NSPoint = .zero
    private var dragged = false
    private var pending: DispatchWorkItem?
    // secousse : demi-tours rapides pendant le glisser
    private var lastX: CGFloat = 0, dir: CGFloat = 0, flips: [Date] = [], shook = false
    // caresse : va-et-vient de la souris au-dessus de lui
    private var petX: CGFloat = 0, petDir: CGFloat = 0, petFlips: [Date] = [], lastPet = Date.distantPast

    override func hitTest(_ point: NSPoint) -> NSView? {
        hitRect().contains(convert(point, from: superview)) ? self : nil
    }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseMoved, .activeAlways, .inVisibleRect], owner: self))
    }

    override func mouseMoved(with e: NSEvent) {
        let p = convert(e.locationInWindow, from: nil)
        guard hitRect().contains(p) else { return }
        let dx = p.x - petX
        petX = p.x
        guard abs(dx) > 1.5 else { return }
        let d: CGFloat = dx > 0 ? 1 : -1
        if d != petDir {
            petDir = d
            petFlips.append(Date())
            petFlips.removeAll { Date().timeIntervalSince($0) > 1.6 }
            if petFlips.count >= 5, Date().timeIntervalSince(lastPet) > 3 {
                petFlips.removeAll(); lastPet = Date(); onPet()
            }
        }
    }

    override func mouseDown(with e: NSEvent) {
        start = NSEvent.mouseLocation
        origin = window?.frame.origin ?? .zero
        dragged = false; shook = false; flips = []; dir = 0; lastX = start!.x
    }

    override func mouseDragged(with e: NSEvent) {
        guard let start else { return }
        let p = NSEvent.mouseLocation
        if !dragged, hypot(p.x - start.x, p.y - start.y) < 4 { return }
        dragged = true
        pending?.cancel()
        NSCursor.closedHand.set()
        onDrag(NSPoint(x: origin.x + p.x - start.x, y: origin.y + p.y - start.y))
        let dx = p.x - lastX
        lastX = p.x
        if abs(dx) > 6 {
            let d: CGFloat = dx > 0 ? 1 : -1
            if d != dir {
                dir = d
                flips.append(Date())
                flips.removeAll { Date().timeIntervalSince($0) > 1.2 }
                if flips.count >= 5, !shook { shook = true; onShake() }
            }
        }
    }

    override func mouseUp(with e: NSEvent) {
        defer { start = nil }
        if dragged { NSCursor.arrow.set(); onDrop(shook); return }
        if e.clickCount >= 2 {
            pending?.cancel(); pending = nil
            onDoubleClick()
        } else {
            // on attend de savoir si c'est un double-clic
            let w = DispatchWorkItem { [weak self] in self?.onClick() }
            pending = w
            DispatchQueue.main.asyncAfter(deadline: .now() + NSEvent.doubleClickInterval, execute: w)
        }
    }

    override func rightMouseDown(with e: NSEvent) { onRightClick(e) }
}

@MainActor
final class MascotController {
    static let bodySize: CGFloat = 46
    static let panelSize = NSSize(width: 116, height: 116)
    private static let margin: CGFloat = 2

    let panel = FloatingPanel(size: panelSize)
    private let coach = Coach.shared
    private let store = Store.shared
    private var lookTimer: Timer?
    private var bag = Set<AnyCancellable>()
    var onClick: () -> Void = {}
    var menu: () -> NSMenu = { NSMenu() }

    init() {
        let touch = TouchView(frame: NSRect(origin: .zero, size: Self.panelSize))
        let host = NSHostingView(rootView: MascotView(coach: coach))
        host.frame = touch.bounds
        host.autoresizingMask = [.width, .height]
        touch.addSubview(host)
        touch.hitRect = { [weak self] in
            guard let self else { return .zero }
            let w = Self.panelSize.width
            return self.coach.sleeping ? NSRect(x: (w - 100) / 2, y: 0, width: 100, height: 80)
                                       : NSRect(x: (w - 70) / 2, y: 0, width: 70, height: 66)
        }
        touch.onClick = { [weak self] in self?.clicked() }
        touch.onDoubleClick = { [weak self] in self?.doubleClicked() }
        touch.onRightClick = { [weak self] e in
            guard let self else { return }
            NSMenu.popUpContextMenu(self.menu(), with: e, for: touch)
        }
        touch.onDrag = { [weak self] p in
            guard let self, !self.coach.sleeping else { return }
            self.panel.setFrameOrigin(p)
            BubbleController.shared.follow()
        }
        touch.onShake = { [weak self] in self?.coach.shaking() }
        touch.onDrop = { [weak self] shaken in
            guard let self, !self.coach.sleeping else { return }
            self.snap()
            if shaken { self.coach.shaken() }
        }
        touch.onPet = { [weak self] in self?.coach.petted() }
        panel.contentView = touch
        panel.acceptsMouseMovedEvents = true
        panel.setAccessibilityLabel("Boubou")

        place(animated: false)
        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { AppDelegate.shared?.mascot.place(animated: false) }
        }
        coach.$hiddenUntil.receive(on: RunLoop.main).sink { [weak self] _ in
            DispatchQueue.main.async { self?.updateVisibility() }
        }.store(in: &bag)
        coach.$sleeping.dropFirst().receive(on: RunLoop.main).sink { [weak self] _ in
            DispatchQueue.main.async { self?.place(animated: true) }
        }.store(in: &bag)

        lookTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { _ in
            MainActor.assumeIsolated { AppDelegate.shared?.mascot.updateLook() }
        }
    }

    private func clicked() {
        if coach.sleeping { return coach.wake() }
        onClick()
    }

    private func doubleClicked() {
        if coach.sleeping { return coach.wake() }
        coach.onClosePanel()
        coach.say(Messages.shared.pick("dodo"), mood: .sleepy, arms: .wave, autoHide: 1.8)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) { [weak self] in
            self?.coach.dismiss()
            self?.coach.sleep()
        }
    }

    func updateVisibility() {
        if coach.hidden { panel.orderOut(nil) } else { place(animated: false); panel.orderFrontRegardless() }
    }

    private var screen: NSScreen {
        let name = store.settings.screen
        return NSScreen.screens.first { $0.localizedName == name } ?? NSScreen.screens.first ?? NSScreen.main!
    }

    private func origin(for corner: Corner, on screen: NSScreen) -> NSPoint {
        let v = screen.visibleFrame, s = Self.panelSize, m = Self.margin
        return NSPoint(x: corner.right ? v.maxX - s.width - m : v.minX + m,
                       y: corner.bottom ? v.minY + m : v.maxY - s.height - m)
    }

    /// À sa place : son coin, ou le lit en bas à droite de l'écran principal quand il dort.
    func place(animated: Bool) {
        let o = coach.sleeping ? origin(for: .bottomRight, on: NSScreen.screens.first ?? screen)
                               : origin(for: store.settings.corner, on: screen)
        if animated {
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.35
                ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                panel.animator().setFrameOrigin(o)
            } completionHandler: {
                MainActor.assumeIsolated { BubbleController.shared.follow() }
            }
        } else {
            panel.setFrameOrigin(o)
            BubbleController.shared.follow()
        }
    }

    /// Lâché : il file au coin le plus proche (de l'écran où on l'a posé).
    private func snap() {
        let c = NSPoint(x: panel.frame.midX, y: panel.frame.midY)
        let scr = NSScreen.screens.first { $0.frame.contains(c) } ?? screen
        let v = scr.visibleFrame
        let right = c.x > v.midX, bottom = c.y < v.midY
        store.settings.corner = right ? (bottom ? .bottomRight : .topRight) : (bottom ? .bottomLeft : .topLeft)
        store.settings.screen = scr.localizedName
        place(animated: true)
        coach.hop += 1
    }

    func updateLook() {
        guard panel.isVisible, !coach.sleeping else { return }
        if let l = coach.idleLook { if l != coach.look { coach.look = l }; return }
        let m = NSEvent.mouseLocation
        let dx = m.x - panel.frame.midX, dy = m.y - (panel.frame.minY + 35)
        var target = CGSize.zero
        if hypot(dx, dy) < 420 {
            target = CGSize(width: max(-1, min(1, dx / 220)), height: max(-1, min(1, -dy / 220)))
        } else if coach.bubble != nil {
            target = CGSize(width: store.settings.corner.right ? -0.6 : 0.6, height: store.settings.corner.bottom ? -0.3 : 0.3)
        }
        let r = CGSize(width: (target.width * 4).rounded() / 4, height: (target.height * 4).rounded() / 4)
        if r != coach.look { coach.look = r }
    }

    /// Le corps de Boubou, en coordonnées écran (pour coller la bulle et le panneau à côté).
    var bodyFrame: NSRect {
        let f = panel.frame
        return NSRect(x: f.midX - 38, y: f.minY, width: 76, height: 70)
    }
}

// MARK: - La bulle

private struct BubbleHost: View {
    @ObservedObject var coach: Coach
    let tailRight: Bool
    let tailBottom: Bool
    var body: some View {
        if let b = coach.bubble {
            BubbleCard(model: b, tailRight: tailRight, tailBottom: tailBottom)
                .id(b.id)
                .fixedSize()
        }
    }
}

struct BubbleCard: View {
    let model: BubbleModel
    let tailRight: Bool
    let tailBottom: Bool
    @State private var appear = false
    private let ink = Color(red: 0.11, green: 0.11, blue: 0.14)

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(model.text)
                .font(.system(size: 13.5, weight: .semibold))
                .foregroundStyle(ink)
                .fixedSize(horizontal: false, vertical: true)
                .contentTransition(.opacity)
                .animation(.easeInOut(duration: 0.3), value: model.text)
            if !model.lines.isEmpty {
                VStack(alignment: .leading, spacing: 5) {
                    ForEach(Array(model.lines.enumerated()), id: \.offset) { _, l in
                        Text(l).font(.system(size: 12.5, weight: .medium)).foregroundStyle(ink.opacity(0.8))
                            .lineLimit(2).fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(ink.opacity(0.05), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            if let f = model.footnote {
                Text(f).font(.system(size: 12, weight: .medium)).foregroundStyle(ink.opacity(0.7))
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !model.actions.isEmpty {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 6) { buttons }
                    VStack(alignment: .leading, spacing: 6) { buttons }
                }
            }
        }
        .padding(14)
        .frame(width: 262, alignment: .leading)
        .background {
            BubbleShape(tailRight: tailRight, tailBottom: tailBottom)
                .fill(.white)
                .shadow(color: .black.opacity(0.22), radius: 12, y: 4)
        }
        .padding(EdgeInsets(top: 10, leading: tailRight ? 14 : 24, bottom: 14, trailing: tailRight ? 24 : 14))
        .contentShape(Rectangle())
        .onTapGesture { if model.actions.isEmpty { Coach.shared.dismiss() } }
        .scaleEffect(appear ? 1 : 0.6, anchor: UnitPoint(x: tailRight ? 1 : 0, y: tailBottom ? 1 : 0))
        .opacity(appear ? 1 : 0)
        .onAppear { withAnimation(.spring(response: 0.35, dampingFraction: 0.72)) { appear = true } }
    }

    @ViewBuilder private var buttons: some View {
        ForEach(model.actions) { a in
            Button(a.title) { a.run() }.buttonStyle(PillStyle(primary: a.primary, onLight: true))
        }
    }
}

/// Bulle de BD avec sa petite queue vers Boubou.
struct BubbleShape: Shape {
    var tailRight: Bool
    var tailBottom: Bool
    func path(in r: CGRect) -> Path {
        var p = Path(roundedRect: r, cornerRadius: 16, style: .continuous)
        let y = tailBottom ? r.maxY - 26 : r.minY + 26
        let x = tailRight ? r.maxX : r.minX
        let d: CGFloat = tailRight ? 1 : -1
        var t = Path()
        t.move(to: CGPoint(x: x - d * 2, y: y - 9))
        t.addQuadCurve(to: CGPoint(x: x + d * 12, y: y + (tailBottom ? 10 : -10) + 4), control: CGPoint(x: x + d * 4, y: y + 2))
        t.addQuadCurve(to: CGPoint(x: x - d * 2, y: y + 9), control: CGPoint(x: x + d * 2, y: y + 8))
        t.closeSubpath()
        p.addPath(t)
        return p
    }
}

@MainActor
final class BubbleController {
    static let shared = BubbleController()
    let panel = FloatingPanel(size: NSSize(width: 300, height: 120))
    private var host: NSHostingView<BubbleHost>?
    private var bag = Set<AnyCancellable>()
    weak var mascot: MascotController?
    private var side: (right: Bool, bottom: Bool) = (true, true)

    private init() {
        Coach.shared.$bubble
            .receive(on: RunLoop.main)
            .sink { [weak self] b in DispatchQueue.main.async { self?.update(b) } }
            .store(in: &bag)
    }

    private var currentSide: (right: Bool, bottom: Bool) {
        if Coach.shared.sleeping { return (true, true) }
        let c = Store.shared.settings.corner
        return (c.right, c.bottom)
    }

    private func update(_ b: BubbleModel?) {
        guard b != nil, mascot != nil, !Coach.shared.hidden else {
            NSAnimationContext.runAnimationGroup { $0.duration = 0.18; panel.animator().alphaValue = 0 } completionHandler: {
                MainActor.assumeIsolated { if Coach.shared.bubble == nil { self.panel.orderOut(nil) } }
            }
            return
        }
        let s = currentSide
        if host == nil || side != s {
            side = s
            let h = NSHostingView(rootView: BubbleHost(coach: Coach.shared, tailRight: s.right, tailBottom: s.bottom))
            panel.contentView = h
            host = h
        }
        follow()
        panel.alphaValue = 1
        panel.orderFrontRegardless()
    }

    /// Recolle la bulle à côté de Boubou, à la bonne taille.
    func follow() {
        guard let host, let m = mascot?.bodyFrame else { return }
        host.layoutSubtreeIfNeeded()
        let size = host.fittingSize
        guard size.width > 1, size.height > 1 else { return }
        let x = side.right ? m.minX - size.width + 14 : m.maxX - 14
        let y = side.bottom ? m.minY + 16 : m.maxY - size.height - 16
        var f = NSRect(x: x, y: y, width: size.width, height: size.height)
        if let scr = mascot?.panel.screen?.visibleFrame {
            f.origin.y = min(max(f.origin.y, scr.minY), scr.maxY - f.height)
            f.origin.x = min(max(f.origin.x, scr.minX), scr.maxX - f.width)
        }
        panel.setFrame(f, display: true)
    }
}
