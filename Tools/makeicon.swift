import AppKit

// Renders the app icon at every size the .iconset needs.
// Concept: a menu bar with a notch bitten out of it, and a chevron pulling what fell off
// back into view.

func draw(size S: CGFloat) -> NSBitmapImageRep {
    let px = Int(S)
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px,
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                               isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = NSSize(width: S, height: S)
    NSGraphicsContext.saveGraphicsState()
    let ctx = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.current = ctx
    let g = ctx.cgContext

    // macOS icons sit inset inside their canvas rather than filling it.
    let inset = S * 0.085
    let body = CGRect(x: inset, y: inset, width: S - inset * 2, height: S - inset * 2)
    let radius = body.width * 0.225

    let squircle = CGPath(roundedRect: body, cornerWidth: radius, cornerHeight: radius, transform: nil)
    g.saveGState()
    g.addPath(squircle)
    g.clip()

    // Deep slate, lit from the top.
    let colors = [NSColor(srgbRed: 0.20, green: 0.23, blue: 0.31, alpha: 1).cgColor,
                  NSColor(srgbRed: 0.09, green: 0.10, blue: 0.15, alpha: 1).cgColor] as CFArray
    let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                              colors: colors, locations: [0, 1])!
    g.drawLinearGradient(gradient,
                         start: CGPoint(x: body.midX, y: body.maxY),
                         end: CGPoint(x: body.midX, y: body.minY), options: [])

    // The menu bar strip, with a notch bitten out of its top centre.
    let barH = body.height * 0.20
    let barRect = CGRect(x: body.minX, y: body.maxY - barH, width: body.width, height: barH)
    let notchW = body.width * 0.26
    let notchH = barH * 0.55
    let notch = CGRect(x: body.midX - notchW / 2, y: barRect.maxY - notchH,
                       width: notchW, height: notchH + 1)

    let strip = CGMutablePath()
    strip.addRect(barRect)
    g.addPath(strip)
    g.setFillColor(NSColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.18).cgColor)
    g.fillPath()

    // Punch the notch back out to the gradient underneath. Square at the top where it meets the
    // screen edge, rounded only at the bottom, otherwise it reads as a floating pill.
    let nr = min(notchH * 0.45, notchW * 0.22)
    let notchPath = CGMutablePath()
    notchPath.move(to: CGPoint(x: notch.minX, y: notch.maxY))
    notchPath.addLine(to: CGPoint(x: notch.minX, y: notch.minY + nr))
    notchPath.addQuadCurve(to: CGPoint(x: notch.minX + nr, y: notch.minY),
                           control: CGPoint(x: notch.minX, y: notch.minY))
    notchPath.addLine(to: CGPoint(x: notch.maxX - nr, y: notch.minY))
    notchPath.addQuadCurve(to: CGPoint(x: notch.maxX, y: notch.minY + nr),
                           control: CGPoint(x: notch.maxX, y: notch.minY))
    notchPath.addLine(to: CGPoint(x: notch.maxX, y: notch.maxY))
    notchPath.closeSubpath()

    g.saveGState()
    g.addPath(notchPath)
    g.clip()
    g.drawLinearGradient(gradient,
                         start: CGPoint(x: body.midX, y: body.maxY),
                         end: CGPoint(x: body.midX, y: body.minY), options: [])
    g.restoreGState()

    // Status items to the right of the notch; the leftmost is dimmed, the one falling off.
    let dotD = barH * 0.34
    let gap = dotD * 1.55
    let alphas: [CGFloat] = [0.25, 0.55, 0.85]
    for (i, a) in alphas.enumerated() {
        let x = barRect.maxX - body.width * 0.10 - CGFloat(alphas.count - 1 - i) * gap - dotD
        let r = CGRect(x: x, y: barRect.midY - dotD / 2, width: dotD, height: dotD)
        g.setFillColor(NSColor(white: 1, alpha: a).cgColor)
        g.addPath(CGPath(roundedRect: r, cornerWidth: dotD * 0.3, cornerHeight: dotD * 0.3, transform: nil))
        g.fillPath()
    }

    // The chevron.
    let cw = body.width * 0.42
    let ch = cw * 0.46
    let cx = body.midX
    let cy = body.midY - body.height * 0.10
    let lw = max(S * 0.055, 1.5)

    let chevron = CGMutablePath()
    chevron.move(to: CGPoint(x: cx - cw / 2, y: cy + ch / 2))
    chevron.addLine(to: CGPoint(x: cx, y: cy - ch / 2))
    chevron.addLine(to: CGPoint(x: cx + cw / 2, y: cy + ch / 2))

    g.setStrokeColor(NSColor.white.cgColor)
    g.setLineWidth(lw)
    g.setLineCap(.round)
    g.setLineJoin(.round)
    g.addPath(chevron)
    g.strokePath()

    g.restoreGState()

    // Hairline rim so the icon reads on light backgrounds.
    g.addPath(squircle)
    g.setStrokeColor(NSColor(white: 1, alpha: 0.10).cgColor)
    g.setLineWidth(max(S * 0.006, 0.5))
    g.strokePath()

    NSGraphicsContext.restoreGraphicsState()
    return rep
}

let out = CommandLine.arguments[1]
for (name, size) in [("icon_16x16", 16.0), ("icon_16x16@2x", 32.0),
                     ("icon_32x32", 32.0), ("icon_32x32@2x", 64.0),
                     ("icon_128x128", 128.0), ("icon_128x128@2x", 256.0),
                     ("icon_256x256", 256.0), ("icon_256x256@2x", 512.0),
                     ("icon_512x512", 512.0), ("icon_512x512@2x", 1024.0)] {
    let rep = draw(size: CGFloat(size))
    let data = rep.representation(using: .png, properties: [:])!
    try! data.write(to: URL(fileURLWithPath: "\(out)/\(name).png"))
}
print("wrote iconset to \(out)")
