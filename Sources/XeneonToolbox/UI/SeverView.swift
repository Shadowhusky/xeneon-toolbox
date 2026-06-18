import SwiftUI
import AppKit

enum Assets {
    static func image(_ name: String, ext: String = "png", subdir: String) -> NSImage? {
        guard let url = Bundle.module.url(forResource: name, withExtension: ext, subdirectory: subdir) else { return nil }
        return NSImage(contentsOf: url)
    }
}

@MainActor
final class SeverModel: ObservableObject {
    enum Phase { case ready, playing, over }
    struct Entity: Identifiable {
        let id: Int
        var pos: CGPoint
        var vel: CGVector
        let r: Double
        let mine: Bool
        var angle: Double
    }

    @Published var phase: Phase = .ready
    @Published var entities: [Entity] = []
    @Published var trail: [CGPoint] = []
    @Published var score = 0
    @Published var combo = 0
    @Published var best = 0
    @Published var lives = 3
    @Published var wave = 1
    @Published var flash = 0.0   // screen hit flash

    private var nextID = 0
    private var spawnAccum = 0.0
    private var time = 0.0
    private var lastSlash = -10.0
    private var lastDrag = -10.0
    private var invulnUntil = 0.0
    private let demo = ProcessInfo.processInfo.environment["XENEON_DEMO"] != nil
    private var demoPrev: CGPoint?

    func startIfNeeded() {
        if phase != .playing {
            phase = .playing
            score = 0; combo = 0; lives = 3; wave = 1
            entities = []; trail = []
            spawnAccum = 0; time = 0; lastSlash = -10; invulnUntil = 0
        }
    }

    func drag(to p: CGPoint, from prev: CGPoint?) {
        lastDrag = time
        trail.insert(p, at: 0)
        if trail.count > 18 { trail.removeLast() }
        guard phase == .playing else { return }
        // Sample along the swipe so fast cuts still register.
        let samples = 5
        for i in 0...samples {
            let t = Double(i) / Double(samples)
            let q = prev.map { CGPoint(x: $0.x + (p.x - $0.x) * t, y: $0.y + (p.y - $0.y) * t) } ?? p
            slash(at: q)
        }
    }

    private func slash(at p: CGPoint) {
        for idx in entities.indices.reversed() {
            let e = entities[idx]
            if hypot(e.pos.x - p.x, e.pos.y - p.y) < e.r + 0.02 {
                if e.mine {
                    if time >= invulnUntil {
                        lives -= 1; combo = 0; flash = 1; invulnUntil = time + 0.8
                        if lives <= 0 { phase = .over; best = max(best, score) }
                    }
                } else {
                    combo += 1
                    score += 1 + combo / 3
                    lastSlash = time
                }
                entities.remove(at: idx)
            }
        }
    }

    func step(dt: Double = 1.0 / 60.0) {
        time += dt
        flash = max(0, flash - dt * 3)
        if time - lastDrag > 0.12 { trail.removeAll() }
        if time - lastSlash > 1.4 { combo = 0 }
        if demo {
            if phase != .playing { startIfNeeded() }
            let p = CGPoint(x: 0.5 + 0.4 * sin(time * 0.8), y: 0.5 + 0.26 * sin(time * 1.9))
            drag(to: p, from: demoPrev); demoPrev = p
        }
        guard phase == .playing else { return }
        wave = score / 12 + 1

        for i in entities.indices {
            entities[i].pos.x += entities[i].vel.dx * dt
            entities[i].pos.y += entities[i].vel.dy * dt
            entities[i].angle += dt * 1.5
        }
        entities.removeAll { $0.pos.x < -0.06 || $0.pos.x > 1.06 }

        spawnAccum += dt
        let interval = max(0.45, 1.0 - Double(wave) * 0.04)
        if spawnAccum >= interval { spawnAccum = 0; spawn() }
    }

    private func spawn() {
        let fromLeft = Bool.random()
        let mine = Double.random(in: 0...1) < 0.22
        let speed = (0.3 + Double(wave) * 0.025) * (mine ? 0.9 : 1)
        let e = Entity(id: nextID,
                       pos: CGPoint(x: fromLeft ? -0.04 : 1.04, y: Double.random(in: 0.15...0.85)),
                       vel: CGVector(dx: fromLeft ? speed : -speed, dy: Double.random(in: -0.04...0.04)),
                       r: mine ? 0.026 : 0.022, mine: mine, angle: 0)
        nextID += 1
        entities.append(e)
    }
}

struct SeverView: View {
    @StateObject private var model = SeverModel()
    @State private var prev: CGPoint?
    private let tick = Timer.publish(every: 1.0 / 60.0, on: .main, in: .common).autoconnect()

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            ZStack {
                NeonBackground()
                Color.red.opacity(model.flash * 0.28)

                ForEach(model.entities) { e in
                    EntityShape(mine: e.mine)
                        .frame(width: e.r * 2 * w, height: e.r * 2 * w)
                        .rotationEffect(.radians(e.angle))
                        .position(x: e.pos.x * w, y: e.pos.y * h)
                }

                BladeTrail(points: model.trail.map { CGPoint(x: $0.x * w, y: $0.y * h) })

                hud
                if model.phase != .playing { overlay }
            }
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { v in
                    if model.phase != .playing { model.startIfNeeded() }
                    let p = CGPoint(x: v.location.x / w, y: v.location.y / h)
                    model.drag(to: p, from: prev)
                    prev = p
                }
                .onEnded { _ in prev = nil })
            .onReceive(tick) { _ in model.step() }
        }
    }

    private var hud: some View {
        VStack {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 0) {
                    Text("SCORE").font(.deck(12, .bold)).tracking(2).foregroundStyle(Theme.textFaint)
                    Text("\(model.score)").font(.readout(46, .bold)).foregroundStyle(Theme.textPrimary)
                }
                Spacer()
                if model.combo > 1 {
                    Text("\(model.combo)× COMBO")
                        .font(.deck(22, .bold)).foregroundStyle(Theme.cpu)
                        .rotationEffect(.degrees(-4))
                        .shadow(color: Theme.cpu.opacity(0.7), radius: 8)
                }
                Spacer()
                HStack(spacing: 7) {
                    ForEach(0..<3, id: \.self) { i in
                        Image(systemName: i < model.lives ? "bolt.fill" : "bolt")
                            .foregroundStyle(i < model.lives ? Theme.netUp : Theme.textFaint)
                    }
                }.font(.system(size: 20, weight: .bold))
            }
            .padding(26)
            Spacer()
        }
    }

    private var overlay: some View {
        ZStack {
            Color.black.opacity(0.55)
            VStack(spacing: 12) {
                Text("SEVER").font(.system(size: 64, weight: .black, design: .rounded))
                    .foregroundStyle(Theme.cpu).tracking(6)
                    .shadow(color: Theme.cpu.opacity(0.8), radius: 16)
                if model.phase == .over {
                    Text("Score \(model.score) · Best \(model.best)")
                        .font(.deck(22, .semibold)).foregroundStyle(Theme.textPrimary)
                }
                Text(model.phase == .over ? "Swipe to run it back" : "Swipe to slice the data-shards · avoid the red ICE")
                    .font(.deck(17)).foregroundStyle(Theme.textSecondary)
            }
        }
    }
}

private struct EntityShape: View {
    let mine: Bool
    var body: some View {
        ZStack {
            if mine {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Theme.batteryLow)
                    .overlay(Image(systemName: "xmark").font(.system(size: 14, weight: .black)).foregroundStyle(.black.opacity(0.7)))
                    .shadow(color: Theme.batteryLow.opacity(0.9), radius: 14)
            } else {
                Diamond()
                    .fill(LinearGradient(colors: [Theme.cpu, Theme.memory], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .overlay(Diamond().stroke(.white.opacity(0.7), lineWidth: 1.5))
                    .shadow(color: Theme.cpu.opacity(0.8), radius: 12)
            }
        }
    }
}

private struct Diamond: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.midX, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.midY))
        p.addLine(to: CGPoint(x: r.midX, y: r.maxY))
        p.addLine(to: CGPoint(x: r.minX, y: r.midY))
        p.closeSubpath()
        return p
    }
}

private struct BladeTrail: View {
    let points: [CGPoint]
    var body: some View {
        ZStack {
            if points.count > 1 {
                Path { p in
                    p.move(to: points[0])
                    for pt in points.dropFirst() { p.addLine(to: pt) }
                }
                .stroke(LinearGradient(colors: [.white, Theme.cpu.opacity(0)], startPoint: .leading, endPoint: .trailing),
                        style: StrokeStyle(lineWidth: 6, lineCap: .round, lineJoin: .round))
                .shadow(color: Theme.cpu.opacity(0.9), radius: 10)
            }
        }
        .allowsHitTesting(false)
    }
}

struct NeonBackground: View {
    var body: some View {
        ZStack {
            if let img = Assets.image("neon-city", subdir: "Resources/bg") {
                Image(nsImage: img).resizable().scaledToFill()
            } else {
                LinearGradient(colors: [Color(red: 0.06, green: 0.03, blue: 0.12), Theme.backgroundEdge],
                               startPoint: .top, endPoint: .bottom)
            }
            LinearGradient(colors: [.black.opacity(0.45), .black.opacity(0.2)], startPoint: .top, endPoint: .bottom)
        }
        .clipped()
    }
}
