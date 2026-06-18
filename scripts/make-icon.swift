import AppKit

// Procedural app icon: dark squircle + neon ring-gauge (the toolbox's motif).
let S: CGFloat = 1024
let img = NSImage(size: NSSize(width: S, height: S))
img.lockFocus()
let ctx = NSGraphicsContext.current!.cgContext
ctx.clear(CGRect(x: 0, y: 0, width: S, height: S))

let pad = S * 0.085
let rect = CGRect(x: pad, y: pad, width: S - 2 * pad, height: S - 2 * pad)
let corner = rect.width * 0.235
let squircle = NSBezierPath(roundedRect: rect, xRadius: corner, yRadius: corner)

// Base gradient fill.
squircle.addClip()
let bg = NSGradient(colors: [NSColor(srgbRed: 0.10, green: 0.11, blue: 0.15, alpha: 1),
                             NSColor(srgbRed: 0.03, green: 0.035, blue: 0.05, alpha: 1)])!
bg.draw(in: rect, angle: -90)

// Top hue glow.
let glow = NSGradient(colors: [NSColor(srgbRed: 0.33, green: 0.84, blue: 0.92, alpha: 0.30),
                               NSColor.clear])!
glow.draw(in: rect, relativeCenterPosition: NSPoint(x: 0, y: 0.75))
ctx.resetClip()

// Neon ring gauge.
let center = CGPoint(x: rect.midX, y: rect.midY)
let radius = rect.width * 0.30
let lw = rect.width * 0.085

let track = NSBezierPath()
track.appendArc(withCenter: center, radius: radius, startAngle: 0, endAngle: 360)
track.lineWidth = lw
NSColor.white.withAlphaComponent(0.07).setStroke()
track.stroke()

ctx.setShadow(offset: .zero, blur: 36, color: NSColor(srgbRed: 0.33, green: 0.84, blue: 0.92, alpha: 0.9).cgColor)
let arc = NSBezierPath()
arc.appendArc(withCenter: center, radius: radius, startAngle: 130, endAngle: 50, clockwise: true)
arc.lineWidth = lw
arc.lineCapStyle = .round
NSColor(srgbRed: 0.36, green: 0.86, blue: 0.95, alpha: 1).setStroke()
arc.stroke()

// Magenta accent tick.
ctx.setShadow(offset: .zero, blur: 24, color: NSColor(srgbRed: 0.56, green: 0.49, blue: 1, alpha: 0.9).cgColor)
let tick = NSBezierPath()
tick.appendArc(withCenter: center, radius: radius, startAngle: 60, endAngle: 40, clockwise: true)
tick.lineWidth = lw
tick.lineCapStyle = .round
NSColor(srgbRed: 0.58, green: 0.5, blue: 1, alpha: 1).setStroke()
tick.stroke()

// Core dot.
ctx.setShadow(offset: .zero, blur: 30, color: NSColor(srgbRed: 0.33, green: 0.84, blue: 0.92, alpha: 1).cgColor)
let core = rect.width * 0.075
NSColor.white.setFill()
NSBezierPath(ovalIn: CGRect(x: center.x - core, y: center.y - core, width: core * 2, height: core * 2)).fill()

img.unlockFocus()

let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "/tmp/icon-1024.png"
if let tiff = img.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
   let png = rep.representation(using: .png, properties: [:]) {
    try? png.write(to: URL(fileURLWithPath: out))
    print("wrote \(out)")
}
