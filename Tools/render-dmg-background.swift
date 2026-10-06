import AppKit

// Renders the DMG window background (1120x680 @2x for a 560x340 window):
// deep-navy gradient + soft blur orbs (the app's own effect, as art) +
// one giant faint dashed ring echoing the logo. Abstract on purpose —
// no positional elements, so Finder icon layout can never clash with it.
let W = 1120, H = 680
let img = NSImage(size: NSSize(width: W, height: H))
img.lockFocus()
guard let ctx = NSGraphicsContext.current?.cgContext else { fatalError("no ctx") }

// Base vertical gradient: icon-navy top -> near-black bottom.
do {
    let cs = CGColorSpaceCreateDeviceRGB()
    let grad = CGGradient(colorsSpace: cs, colors: [
        NSColor(red: 0x26/255.0, green: 0x2A/255.0, blue: 0x45/255.0, alpha: 1).cgColor,
        NSColor(red: 0x14/255.0, green: 0x16/255.0, blue: 0x24/255.0, alpha: 1).cgColor,
    ] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(grad, start: CGPoint(x: 0, y: H), end: CGPoint(x: 0, y: 0), options: [])
}

// Soft orbs: radial white-core trick with brand colors, heavy alpha falloff.
func orb(cx: CGFloat, cy: CGFloat, r: CGFloat, color: NSColor, peak: CGFloat = 0.55) {
    let cs = CGColorSpaceCreateDeviceRGB()
    let c = color
    let grad = CGGradient(colorsSpace: cs, colors: [
        c.withAlphaComponent(peak).cgColor,
        c.withAlphaComponent(0.0).cgColor,
    ] as CFArray, locations: [0, 1])!
    ctx.drawRadialGradient(grad,
        startCenter: CGPoint(x: cx, y: cy), startRadius: 0,
        endCenter: CGPoint(x: cx, y: cy), endRadius: r,
        options: [.drawsAfterEndLocation])
}
orb(cx: 300, cy: 470, r: 330, color: NSColor(red: 0x5B/255.0, green: 0x6C/255.0, blue: 0xB4/255.0, alpha: 1)) // iris blue, upper-left
orb(cx: 880, cy: 220, r: 300, color: NSColor(red: 0x3A/255.0, green: 0x45/255.0, blue: 0x8F/255.0, alpha: 1)) // deep violet, lower-right
orb(cx: 620, cy: 700, r: 190, color: NSColor(red: 0xE8/255.0, green: 0x9A/255.0, blue: 0x5A/255.0, alpha: 1), peak: 0.30) // faint warm kiss, mostly off top edge

// Giant faint dashed ring, off-center right — the logo at wallpaper scale.
do {
    ctx.saveGState()
    ctx.setStrokeColor(NSColor.white.withAlphaComponent(0.07).cgColor)
    ctx.setLineWidth(7)
    ctx.setLineDash(phase: 0, lengths: [34, 22])
    ctx.strokeEllipse(in: CGRect(x: 640, y: -140, width: 560, height: 560))
    ctx.restoreGState()
}

// Label spotlights: Finder icon labels are always black, so lift two soft
// pools under the icon columns (CG coords, origin bottom-left: the label
// band sits low in the frame). Warm-white, gentle — stage lighting.
orb(cx: 300, cy: 160, r: 150, color: NSColor(red: 0xD8/255.0, green: 0xDC/255.0, blue: 0xF0/255.0, alpha: 1), peak: 0.30)
orb(cx: 820, cy: 160, r: 150, color: NSColor(red: 0xD8/255.0, green: 0xDC/255.0, blue: 0xF0/255.0, alpha: 1), peak: 0.30)

// Gentle top light + bottom vignette for depth.
do {
    let cs = CGColorSpaceCreateDeviceRGB()
    let top = CGGradient(colorsSpace: cs, colors: [
        NSColor.white.withAlphaComponent(0.05).cgColor,
        NSColor.white.withAlphaComponent(0.0).cgColor,
    ] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(top, start: CGPoint(x: 0, y: H), end: CGPoint(x: 0, y: H - 260), options: [])
    let vig = CGGradient(colorsSpace: cs, colors: [
        NSColor.black.withAlphaComponent(0.0).cgColor,
        NSColor.black.withAlphaComponent(0.28).cgColor,
    ] as CFArray, locations: [0.55, 1])!
    let c = CGPoint(x: W / 2, y: H / 2)
    ctx.drawRadialGradient(vig, startCenter: c, startRadius: 0, endCenter: c,
        endRadius: CGFloat(H) * 0.75, options: [.drawsAfterEndLocation])
}
img.unlockFocus()

let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil, pixelsWide: W, pixelsHigh: H,
    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
img.draw(at: .zero, from: NSRect(x: 0, y: 0, width: W, height: H), operation: .copy, fraction: 1)
NSGraphicsContext.restoreGraphicsState()
try! rep.representation(using: .png, properties: [:])!
    .write(to: URL(fileURLWithPath: "/tmp/dmg-bg/background.png"))
print("wrote /tmp/dmg-bg/background.png")
