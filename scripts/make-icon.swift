import AppKit

// App icon: a Safari-style compass in a mini window, pinned top-right like the app itself

let violet = NSColor(red: 0.36, green: 0.27, blue: 0.98, alpha: 1)
let rose = NSColor(red: 0.85, green: 0.38, blue: 0.92, alpha: 1)
let peche = NSColor(red: 1.0, green: 0.62, blue: 0.55, alpha: 1)

func compass(_ c: NSPoint, _ R: CGFloat, _ s: CGFloat) {
  // Cadran en dégradé violet → rose → pêche
  let dial = NSBezierPath(ovalIn: NSRect(x: c.x - R, y: c.y - R, width: 2 * R, height: 2 * R))
  NSGradient(colors: [violet, rose, peche])!.draw(in: dial, angle: -60)

  // Graduations
  NSColor.white.withAlphaComponent(0.85).setStroke()
  for i in 0..<48 {
    let a = CGFloat(i) / 48 * 2 * .pi
    let long = i % 4 == 0
    let r1 = R * 0.9, r2 = R * (long ? 0.76 : 0.83)
    let p = NSBezierPath()
    p.move(to: NSPoint(x: c.x + cos(a) * r1, y: c.y + sin(a) * r1))
    p.line(to: NSPoint(x: c.x + cos(a) * r2, y: c.y + sin(a) * r2))
    p.lineWidth = R * (long ? 0.025 : 0.0125)
    p.stroke()
  }

  // Aiguille inclinée (nord-est blanc, sud-ouest rouge)
  let angle: CGFloat = .pi / 4 + .pi / 2 * 0.0 + .pi / 2   // pointe vers le haut-droite
  let dir = NSPoint(x: cos(angle - .pi / 2), y: sin(angle - .pi / 2))
  let n = NSPoint(x: -dir.y, y: dir.x)
  let len = R * 0.72, w = R * 0.13
  func half(_ sign: CGFloat, _ color: NSColor) {
    let p = NSBezierPath()
    p.move(to: NSPoint(x: c.x + sign * dir.x * len, y: c.y + sign * dir.y * len))
    p.line(to: NSPoint(x: c.x + n.x * w, y: c.y + n.y * w))
    p.line(to: NSPoint(x: c.x - n.x * w, y: c.y - n.y * w))
    p.close()
    color.setFill(); p.fill()
  }
  NSGraphicsContext.saveGraphicsState()
  let sh2 = NSShadow(); sh2.shadowColor = NSColor.black.withAlphaComponent(0.25)
  sh2.shadowBlurRadius = R * 0.05; sh2.shadowOffset = NSSize(width: 0, height: -R * 0.02); sh2.set()
  half(1, NSColor(red: 1, green: 0.23, blue: 0.27, alpha: 1))
  half(-1, .white)
  NSGraphicsContext.restoreGraphicsState()
}

func draw(_ px: Int) -> Data {
  let s = CGFloat(px)
  let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8,
                             samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                             bytesPerRow: 0, bitsPerPixel: 0)!
  NSGraphicsContext.saveGraphicsState()
  NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

  // Rounded macOS tile with the gradient background
  let inset = s * 0.1
  let rect = NSRect(x: inset, y: inset, width: s - 2 * inset, height: s - 2 * inset)
  let tile = NSBezierPath(roundedRect: rect, xRadius: rect.width * 0.225, yRadius: rect.width * 0.225)
  NSGraphicsContext.saveGraphicsState()
  let sh = NSShadow(); sh.shadowColor = NSColor.black.withAlphaComponent(0.25)
  sh.shadowBlurRadius = s * 0.02; sh.shadowOffset = NSSize(width: 0, height: -s * 0.01); sh.set()
  NSColor.white.setFill(); tile.fill()
  NSGraphicsContext.restoreGraphicsState()
  NSGradient(colors: [violet, rose, peche])!.draw(in: tile, angle: -55)

  // Mini window floating in the top-right corner, holding the compass
  let w = rect.width * 0.52
  let win = NSRect(x: rect.maxX - w - rect.width * 0.1, y: rect.maxY - w - rect.width * 0.1, width: w, height: w)
  let winPath = NSBezierPath(roundedRect: win, xRadius: w * 0.18, yRadius: w * 0.18)
  NSGraphicsContext.saveGraphicsState()
  let sw = NSShadow(); sw.shadowColor = NSColor.black.withAlphaComponent(0.3)
  sw.shadowBlurRadius = s * 0.04; sw.shadowOffset = NSSize(width: 0, height: -s * 0.015); sw.set()
  NSColor.white.setFill(); winPath.fill()
  NSGraphicsContext.restoreGraphicsState()
  compass(NSPoint(x: win.midX, y: win.midY), w * 0.36, s)
  NSGraphicsContext.restoreGraphicsState()
  return rep.representation(using: .png, properties: [:])!
}

let dir = NSTemporaryDirectory() + "AppIcon.iconset"
try? FileManager.default.removeItem(atPath: dir)
try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
for base in [16, 32, 128, 256, 512] {
  try! draw(base).write(to: URL(fileURLWithPath: "\(dir)/icon_\(base)x\(base).png"))
  try! draw(base * 2).write(to: URL(fileURLWithPath: "\(dir)/icon_\(base)x\(base)@2x.png"))
}
try! draw(512).write(to: URL(fileURLWithPath: "docs/icon.png"))
print(dir)
