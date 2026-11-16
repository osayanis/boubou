import SwiftUI
import AppKit

// MARK: - Particules (cœurs, confettis, étincelles, gouttes) qui jaillissent de Boubou

enum BurstKind { case hearts, bigHearts, confetti, sparkles, drops }

struct Burst: Identifiable {
    let id = UUID()
    let kind: BurstKind
    let start = Date()
    var duration: Double { kind == .confetti || kind == .bigHearts ? 3.4 : 2.2 }
    var count: Int {
        switch kind { case .hearts: 7; case .bigHearts: 26; case .confetti: 46; case .sparkles: 10; case .drops: 8 }
    }
}

@MainActor
final class FX: ObservableObject {
    static let shared = FX()
    static let size = NSSize(width: 320, height: 420)
    @Published var bursts: [Burst] = []
    let panel = FloatingPanel(size: FX.size)
    weak var mascot: MascotController?

    private init() {
        panel.ignoresMouseEvents = true
        panel.level = .floating
        panel.contentView = NSHostingView(rootView: FXView(fx: self))
    }

    func burst(_ k: BurstKind) {
        guard let m = mascot?.panel.frame, mascot?.panel.isVisible == true else { return }
        // le bas du panneau d'effets au niveau de Boubou, centré sur lui (et dans l'écran)
        var o = NSPoint(x: m.midX - Self.size.width / 2, y: m.minY + 10)
        if let v = mascot?.panel.screen?.visibleFrame {
            o.x = min(max(o.x, v.minX), v.maxX - Self.size.width)
            o.y = min(max(o.y, v.minY), v.maxY - Self.size.height)
        }
        panel.setFrameOrigin(o)
        anchor = CGPoint(x: m.midX - o.x, y: Self.size.height - (m.midY - o.y))
        let b = Burst(kind: k)
        bursts.append(b)
        panel.orderFrontRegardless()
        DispatchQueue.main.asyncAfter(deadline: .now() + b.duration + 0.1) { [weak self] in
            guard let self else { return }
            self.bursts.removeAll { $0.id == b.id }
            if self.bursts.isEmpty { self.panel.orderOut(nil) }
        }
    }

    /// Le centre de Boubou, dans les coordonnées du panneau (origine en haut à gauche).
    var anchor = CGPoint(x: 160, y: 380)
}

private struct FXView: View {
    @ObservedObject var fx: FX
    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60, paused: fx.bursts.isEmpty)) { tl in
            Canvas { ctx, size in
                let heart = ctx.resolve(Image(systemName: "heart.fill"))
                let sparkle = ctx.resolve(Image(systemName: "sparkle"))
                let drop = ctx.resolve(Image(systemName: "drop.fill"))
                for b in fx.bursts {
                    let t = tl.date.timeIntervalSince(b.start)
                    guard t >= 0, t < b.duration else { continue }
                    var rng = Seeded(seed: UInt64(bitPattern: Int64(b.id.hashValue)))
                    for i in 0..<b.count {
                        let r1 = rng.next(), r2 = rng.next(), r3 = rng.next(), r4 = rng.next()
                        let delay = b.kind == .bigHearts ? Double(i) * 0.07 : r4 * 0.15
                        let lt = t - delay
                        guard lt > 0 else { continue }
                        let life = b.duration - delay
                        let fade = max(0, 1 - lt / life)
                        var p = fx.anchor
                        let ctxCopy = ctx
                        var c = ctxCopy
                        switch b.kind {
                        case .hearts, .bigHearts:
                            p.x += (r1 - 0.5) * 60 + sin(lt * 4 + r2 * 6) * 14
                            p.y -= 20 + lt * (90 + r3 * 70)
                            let s = (b.kind == .bigHearts ? 14 : 10) + r2 * 10
                            c.opacity = fade
                            c.translateBy(x: p.x, y: p.y)
                            c.rotate(by: .degrees((r1 - 0.5) * 40))
                            var h = heart
                            h.shading = .color(i % 3 == 0 ? Color(red: 1, green: 0.42, blue: 0.55) : Boule.cheek)
                            c.draw(h, in: CGRect(x: -s / 2, y: -s / 2, width: s, height: s))
                        case .confetti:
                            let angle = -Double.pi / 2 + (r1 - 0.5) * 2.2
                            let speed = 260 + r2 * 220
                            p.x += cos(angle) * speed * lt
                            p.y += sin(angle) * speed * lt + 0.5 * 520 * lt * lt
                            c.opacity = fade
                            c.translateBy(x: p.x, y: p.y)
                            c.rotate(by: .radians(lt * (4 + r3 * 8)))
                            let colors: [Color] = [Boule.cheek, Boule.scrub, .white, Color(red: 1, green: 0.8, blue: 0.35), Color(red: 0.55, green: 0.6, blue: 1)]
                            c.fill(Path(CGRect(x: -4, y: -2.5, width: 8, height: 5)), with: .color(colors[i % colors.count]))
                        case .sparkles:
                            let angle = Double(i) / Double(b.count) * 2 * .pi + r1
                            p.x += cos(angle) * (30 + lt * 60)
                            p.y += sin(angle) * (30 + lt * 60) - 10
                            let s = 8 + r2 * 8
                            c.opacity = fade
                            var sp = sparkle
                            sp.shading = .color(i % 2 == 0 ? .white : Color(red: 1, green: 0.85, blue: 0.4))
                            c.draw(sp, in: CGRect(x: p.x - s / 2, y: p.y - s / 2, width: s, height: s))
                        case .drops:
                            p.x += (r1 - 0.5) * 70
                            p.y -= 30 + lt * 50 - lt * lt * 40
                            let s = 9 + r2 * 6
                            c.opacity = fade
                            var d = drop
                            d.shading = .color(Color(red: 0.45, green: 0.75, blue: 1))
                            c.draw(d, in: CGRect(x: p.x - s / 2, y: p.y - s / 2, width: s, height: s))
                        }
                    }
                }
            }
        }
        .frame(width: FX.size.width, height: FX.size.height)
        .allowsHitTesting(false)
    }
}

/// Petit générateur pseudo-aléatoire reproductible (chaque particule garde sa trajectoire d'une image à l'autre).
struct Seeded {
    var state: UInt64
    init(seed: UInt64) { state = seed &+ 0x9E3779B97F4A7C15 }
    mutating func next() -> Double {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return Double((state >> 33) & 0xFFFFFF) / Double(0xFFFFFF)
    }
}

// MARK: - Bulles anti-stress : 30 secondes pour en éclater un maximum

@MainActor
final class BubbleGame: ObservableObject {
    static let shared = BubbleGame()
    struct Bubble: Identifiable { let id = UUID(); var x: CGFloat; var y: CGFloat; let size: CGFloat; let speed: CGFloat; let phase: Double; let born = Date() }
    struct Pop: Identifiable { let id = UUID(); let x: CGFloat; let y: CGFloat; let at = Date() }

    @Published var bubbles: [Bubble] = []
    @Published var pops: [Pop] = []
    @Published var score = 0
    @Published var remaining = 30
    static let size = NSSize(width: 300, height: 400)
    let panel = FloatingPanel(size: BubbleGame.size)
    private var timer: Timer?
    private var tickCount = 0
    weak var mascot: MascotController?
    var running: Bool { timer != nil }

    private init() {
        panel.level = .floating
        panel.contentView = NSHostingView(rootView: BubbleGameView(game: self))
    }

    func start() {
        stop(silent: true)
        score = 0; remaining = 30; bubbles = []; pops = []; tickCount = 0
        if let m = mascot?.panel.frame, let v = mascot?.panel.screen?.visibleFrame {
            let right = Store.shared.settings.corner.right
            var o = NSPoint(x: right ? m.minX - Self.size.width + 10 : m.maxX - 10, y: m.minY)
            o.x = min(max(o.x, v.minX + 6), v.maxX - Self.size.width - 6)
            o.y = min(max(o.y, v.minY + 6), v.maxY - Self.size.height - 6)
            panel.setFrameOrigin(o)
        }
        panel.orderFrontRegardless()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30, repeats: true) { _ in
            MainActor.assumeIsolated { BubbleGame.shared.step() }
        }
    }

    private func step() {
        tickCount += 1
        if tickCount % 30 == 0 { remaining -= 1; if remaining <= 0 { return stop(silent: false) } }
        if tickCount % 14 == 0 || bubbles.count < 3 {
            let s = CGFloat.random(in: 34...62)
            bubbles.append(Bubble(x: .random(in: s / 2 + 8...Self.size.width - s / 2 - 8), y: Self.size.height + s,
                                  size: s, speed: .random(in: 1.3...2.6), phase: .random(in: 0...6)))
        }
        for i in bubbles.indices { bubbles[i].y -= bubbles[i].speed }
        bubbles.removeAll { $0.y < -$0.size }
        pops.removeAll { Date().timeIntervalSince($0.at) > 0.4 }
    }

    func pop(_ b: Bubble) {
        bubbles.removeAll { $0.id == b.id }
        pops.append(Pop(x: b.x + sin(Date().timeIntervalSince(b.born) * 2 + b.phase) * 10, y: b.y))
        score += 1
        if let s = NSSound(named: "Pop")?.copy() as? NSSound { s.volume = 0.25; s.play() }
    }

    func stop(silent: Bool) {
        timer?.invalidate(); timer = nil
        panel.orderOut(nil)
        if !silent { Coach.shared.bubblesDone(score) }
    }
}

private struct BubbleGameView: View {
    @ObservedObject var game: BubbleGame
    var body: some View {
        ZStack(alignment: .top) {
            RoundedRectangle(cornerRadius: 22, style: .continuous).fill(.black.opacity(0.28))
            ForEach(game.bubbles) { b in
                let wobble = sin(Date().timeIntervalSince(b.born) * 2 + b.phase) * 10
                Circle()
                    .fill(RadialGradient(colors: [.white.opacity(0.05), Color(red: 0.6, green: 0.85, blue: 1).opacity(0.25), .white.opacity(0.35)],
                                         center: .center, startRadius: 0, endRadius: b.size / 2))
                    .overlay(Circle().strokeBorder(.white.opacity(0.7), lineWidth: 1.2))
                    .overlay(Ellipse().fill(.white.opacity(0.8)).frame(width: b.size * 0.22, height: b.size * 0.12)
                        .rotationEffect(.degrees(-35)).offset(x: -b.size * 0.18, y: -b.size * 0.2))
                    .frame(width: b.size, height: b.size)
                    .contentShape(Circle())
                    .position(x: b.x + wobble, y: b.y)
                    .onTapGesture { game.pop(b) }
            }
            ForEach(game.pops) { p in PopRing().position(x: p.x, y: p.y) }
            HStack {
                Text("🫧 \(game.score)").font(.system(size: 13, weight: .heavy)).foregroundStyle(.white)
                Spacer()
                Text("0:\(String(format: "%02d", max(0, game.remaining)))").font(.system(size: 12, weight: .bold).monospacedDigit()).foregroundStyle(.white.opacity(0.7))
                Button { game.stop(silent: false) } label: {
                    Image(systemName: "xmark").font(.system(size: 10, weight: .black)).foregroundStyle(.black.opacity(0.75))
                        .frame(width: 20, height: 20).background(.white, in: Circle())
                }.buttonStyle(.plain)
            }
            .padding(12)
        }
        .frame(width: BubbleGame.size.width, height: BubbleGame.size.height)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
    }
}

private struct PopRing: View {
    @State private var go = false
    var body: some View {
        Circle().strokeBorder(.white, lineWidth: go ? 0.5 : 3)
            .frame(width: go ? 64 : 24, height: go ? 64 : 24)
            .opacity(go ? 0 : 0.9)
            .onAppear { withAnimation(.easeOut(duration: 0.35)) { go = true } }
            .allowsHitTesting(false)
    }
}
