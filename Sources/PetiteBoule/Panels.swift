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

// MARK: - La mascotte

private struct MascotView: View {
    @ObservedObject var coach: Coach
    var body: some View {
        Boule(mood: coach.mood, arms: coach.arms, look: coach.look, size: MascotController.bodySize, hop: coach.hop, breath: coach.breath)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            .padding(.bottom, 2)
    }
}

/// Reçoit clics et glisser-déposer pour toute la mascotte.
private final class DragView: NSView {
    var onClick: () -> Void = {}
    var onRightClick: (NSEvent) -> Void = { _ in }
    var onDrag: (NSPoint) -> Void = { _ in }
    var onDrop: () -> Void = {}
    private var start: NSPoint?
    private var origin: NSPoint = .zero
    private var dragged = false

    override func hitTest(_ point: NSPoint) -> NSView? { frame.contains(point) ? self : nil }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with e: NSEvent) {
        start = NSEvent.mouseLocation
        origin = window?.frame.origin ?? .zero
        dragged = false
    }
    override func mouseDragged(with e: NSEvent) {
        guard let start else { return }
        let p = NSEvent.mouseLocation
        if !dragged, hypot(p.x - start.x, p.y - start.y) < 4 { return }
        dragged = true
        NSCursor.closedHand.set()
        onDrag(NSPoint(x: origin.x + p.x - start.x, y: origin.y + p.y - start.y))
    }
    override func mouseUp(with e: NSEvent) {
        if dragged { NSCursor.arrow.set(); onDrop() } else { onClick() }
        start = nil
    }
    override func rightMouseDown(with e: NSEvent) { onRightClick(e) }
}

@MainActor
final class MascotController {
    static let bodySize: CGFloat = 46
    static let panelSize = NSSize(width: 84, height: 84)
    private static let margin: CGFloat = 6

    let panel = FloatingPanel(size: panelSize)
    private let coach = Coach.shared
    private let store = Store.shared
    private var lookTimer: Timer?
    private var bag = Set<AnyCancellable>()
    var onClick: () -> Void = {}
    var menu: () -> NSMenu = { NSMenu() }

    init() {
        let drag = DragView(frame: NSRect(origin: .zero, size: Self.panelSize))
        let host = NSHostingView(rootView: MascotView(coach: coach))
        host.frame = drag.bounds
        host.autoresizingMask = [.width, .height]
        drag.addSubview(host)
        drag.onClick = { [weak self] in self?.onClick() }
        drag.onRightClick = { [weak self] e in
            guard let self else { return }
            NSMenu.popUpContextMenu(self.menu(), with: e, for: drag)
        }
        drag.onDrag = { [weak self] p in
            self?.panel.setFrameOrigin(p)
            BubbleController.shared.follow()
        }
        drag.onDrop = { [weak self] in self?.snap() }
        panel.contentView = drag
        panel.setAccessibilityLabel("Petite Boule")

        place(animated: false)
        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.place(animated: false) }
        }
        coach.$hiddenUntil.receive(on: RunLoop.main).sink { [weak self] _ in
            DispatchQueue.main.async { self?.updateVisibility() }
        }.store(in: &bag)

        // Elle suit la souris des yeux quand on passe près d'elle (4 fois par seconde : presque rien).
        lookTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.updateLook() }
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

    func place(animated: Bool) {
        let o = origin(for: store.settings.corner, on: screen)
        if animated {
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.25
                ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
                panel.animator().setFrameOrigin(o)
            } completionHandler: {
                MainActor.assumeIsolated { BubbleController.shared.follow() }
            }
        } else {
            panel.setFrameOrigin(o)
            BubbleController.shared.follow()
        }
    }

    /// Lâchée : elle file au coin le plus proche (de l'écran où on l'a posée).
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

    func setCorner(_ c: Corner) {
        store.settings.corner = c
        place(animated: true)
    }

    private func updateLook() {
        guard panel.isVisible else { return }
        let m = NSEvent.mouseLocation
        let dx = m.x - panel.frame.midX, dy = m.y - panel.frame.midY
        var target = CGSize.zero
        if hypot(dx, dy) < 420 {
            target = CGSize(width: max(-1, min(1, dx / 220)), height: max(-1, min(1, -dy / 220)))
        } else if coach.bubble != nil {
            // pendant qu'elle parle, elle regarde vers sa bulle
            target = CGSize(width: store.settings.corner.right ? -0.6 : 0.6, height: store.settings.corner.bottom ? -0.3 : 0.3)
        }
        let r = CGSize(width: (target.width * 4).rounded() / 4, height: (target.height * 4).rounded() / 4)
        if r != coach.look { coach.look = r }
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
    @State private var typed = ""
    @FocusState private var focused: Bool

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
            if let input = model.input {
                HStack(spacing: 6) {
                    TextField("", text: $typed, prompt: Text(model.inputPlaceholder).foregroundStyle(ink.opacity(0.4)))
                        .textFieldStyle(.plain)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(ink)
                        .padding(.horizontal, 10).padding(.vertical, 7)
                        .background(ink.opacity(0.06), in: Capsule())
                        .focused($focused)
                        .onSubmit { input(typed) }
                    Button { input(typed) } label: { Text("OK") }
                        .buttonStyle(PillStyle(primary: true, onLight: true))
                        .disabled(typed.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                .onAppear { DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { focused = true } }
            }
            if !model.actions.isEmpty {
                FlowButtons(actions: model.actions)
            }
        }
        .padding(14)
        .frame(width: 268, alignment: .leading)
        .background {
            BubbleShape(tailRight: tailRight, tailBottom: tailBottom)
                .fill(.white)
                .shadow(color: .black.opacity(0.22), radius: 12, y: 4)
        }
        .padding(EdgeInsets(top: 10, leading: tailRight ? 14 : 24, bottom: 14, trailing: tailRight ? 24 : 14))
        .contentShape(Rectangle())
        .onTapGesture { if model.actions.isEmpty && model.input == nil { Coach.shared.dismiss() } }
        .scaleEffect(appear ? 1 : 0.6, anchor: UnitPoint(x: tailRight ? 1 : 0, y: tailBottom ? 1 : 0))
        .opacity(appear ? 1 : 0)
        .onAppear { withAnimation(.spring(response: 0.35, dampingFraction: 0.72)) { appear = true } }
    }
}

/// Les boutons de la bulle, à la ligne quand ils ne tiennent pas.
private struct FlowButtons: View {
    let actions: [BubbleAction]
    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 6) { buttons }
            VStack(alignment: .leading, spacing: 6) { buttons }
        }
    }
    @ViewBuilder private var buttons: some View {
        ForEach(actions) { a in
            Button(a.title) { a.run() }.buttonStyle(PillStyle(primary: a.primary, onLight: true))
        }
    }
}

/// Bulle de BD avec sa petite queue vers la mascotte.
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
            .sink { [weak self] b in
                // après la mise à jour de la vue (le sink est appelé avant le changement effectif)
                DispatchQueue.main.async { self?.update(b) }
            }
            .store(in: &bag)
    }

    private func update(_ b: BubbleModel?) {
        guard let b, let mascot, !Coach.shared.hidden else {
            NSAnimationContext.runAnimationGroup { $0.duration = 0.18; panel.animator().alphaValue = 0 } completionHandler: {
                MainActor.assumeIsolated { if Coach.shared.bubble == nil { self.panel.orderOut(nil) } }
            }
            return
        }
        let corner = Store.shared.settings.corner
        if host == nil || side != (corner.right, corner.bottom) {
            side = (corner.right, corner.bottom)
            let h = NSHostingView(rootView: BubbleHost(coach: Coach.shared, tailRight: corner.right, tailBottom: corner.bottom))
            panel.contentView = h
            host = h
        }
        panel.keyable = b.input != nil
        follow()
        panel.alphaValue = 1
        if b.input != nil {
            NSApp.activate(ignoringOtherApps: true)
            panel.makeKeyAndOrderFront(nil)
        } else {
            panel.orderFrontRegardless()
        }
        _ = mascot
    }

    /// Recolle la bulle à côté de la mascotte, à la bonne taille.
    func follow() {
        guard let host, let m = mascot?.panel.frame else { return }
        host.layoutSubtreeIfNeeded()
        let size = host.fittingSize
        guard size.width > 1, size.height > 1 else { return }
        let x = side.right ? m.minX - size.width + 18 : m.maxX - 18
        let y = side.bottom ? m.minY + 18 : m.maxY - size.height - 18
        var f = NSRect(x: x, y: y, width: size.width, height: size.height)
        if let scr = mascot?.panel.screen?.visibleFrame {
            f.origin.y = min(max(f.origin.y, scr.minY), scr.maxY - f.height)
            f.origin.x = min(max(f.origin.x, scr.minX), scr.maxX - f.width)
        }
        panel.setFrame(f, display: true)
    }
}
