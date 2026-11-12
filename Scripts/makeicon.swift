import AppKit

// Draws the app's icon and writes it as an icon set:
//
//     swift Scripts/makeicon.swift Resources/Assets.xcassets/AppIcon.appiconset
//
// The icon is the PCC's mimic board on a phosphor screen: the two tracks of
// a line as a loop, track 1 above and track 2 below, joined at each end by
// a turn-back; the stations as ticks across them; two automatic trains in
// green; and a cab in cyan with its movement authority running ahead of it
// to the rear of the train in front. It is drawn offscreen, at each size in
// turn, so that every size is crisp.

func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> NSColor {
    NSColor(deviceRed: r, green: g, blue: b, alpha: a)
}

// The app's palette (RetroTheme).
let amber       = rgb(1.00, 0.72, 0.20)
let amberBright = rgb(1.00, 0.86, 0.45)
let amberDim    = rgb(0.62, 0.45, 0.12)
let green       = rgb(0.36, 1.00, 0.42)
let cyan        = rgb(0.45, 0.95, 1.00)

/// Draws the icon at `px`×`px`. All geometry is authored in a 1024 grid and
/// scaled by k, so every size renders natively (crisp, not downscaled).
func makeIcon(_ px: Int) -> Data {
    let S = CGFloat(px)
    let k = S / 1024.0
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px,
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                               isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = NSSize(width: px, height: px)
    NSGraphicsContext.saveGraphicsState()
    let gctx = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.current = gctx
    let ctx = gctx.cgContext

    // --- The rounded "screen" ---
    let margin: CGFloat = 96 * k
    let body = CGRect(x: margin, y: margin, width: S - 2 * margin, height: S - 2 * margin)
    let radius = 182 * k
    let bodyPath = NSBezierPath(roundedRect: body, xRadius: radius, yRadius: radius)

    ctx.saveGState()
    bodyPath.addClip()
    // Dark phosphor, a little bluer towards the top.
    NSGradient(colors: [rgb(0.03, 0.03, 0.045), rgb(0.07, 0.09, 0.13)])!
        .draw(in: body, angle: 90)
    // A soft amber bloom along the line.
    let bloom = CGPoint(x: 512 * k, y: 500 * k)
    NSGradient(colors: [rgb(1.0, 0.72, 0.20, 0.14), rgb(1.0, 0.72, 0.20, 0.0)])!
        .draw(fromCenter: bloom, radius: 0, toCenter: bloom, radius: 460 * k, options: [])
    // Faint CRT scanlines.
    rgb(0, 0, 0, 0.16).set()
    var y = body.minY
    while y < body.maxY {
        NSBezierPath(rect: CGRect(x: body.minX, y: y, width: body.width, height: 3 * k)).fill()
        y += 9 * k
    }
    ctx.restoreGState()

    // --- The line: two tracks and their turn-backs ---
    let left: CGFloat = 262 * k, right: CGFloat = 762 * k
    let upper: CGFloat = 622 * k, lower: CGFloat = 398 * k         // track 1 above, track 2 below
    let turn = (upper - lower) / 2
    let loop = NSBezierPath()
    loop.move(to: CGPoint(x: left, y: upper))
    loop.line(to: CGPoint(x: right, y: upper))
    loop.appendArc(withCenter: CGPoint(x: right, y: lower + turn), radius: turn, startAngle: 90, endAngle: -90, clockwise: true)
    loop.line(to: CGPoint(x: left, y: lower))
    loop.appendArc(withCenter: CGPoint(x: left, y: lower + turn), radius: turn, startAngle: 270, endAngle: 90, clockwise: true)
    loop.close()
    ctx.setShadow(offset: .zero, blur: 40 * k, color: amber.withAlphaComponent(0.9).cgColor)
    amber.set()
    loop.lineWidth = 28 * k
    loop.stroke()
    ctx.setShadow(offset: .zero, blur: 0, color: nil)
    amberBright.set()
    loop.lineWidth = 10 * k
    loop.stroke()

    // --- The stations: a tick across both tracks ---
    ctx.setShadow(offset: .zero, blur: 14 * k, color: amberBright.withAlphaComponent(0.8).cgColor)
    for x in stride(from: CGFloat(292), through: 732, by: 110) {
        amberBright.set()
        let tick = NSBezierPath()
        tick.move(to: CGPoint(x: x * k, y: upper + 40 * k))
        tick.line(to: CGPoint(x: x * k, y: lower - 40 * k))
        tick.lineWidth = 8 * k
        tick.lineCapStyle = .round
        tick.stroke()
    }
    ctx.setShadow(offset: .zero, blur: 0, color: nil)

    /// A train: a bar with a pointed nose, `towards` +1 for a nose to the
    /// right and -1 to the left.
    func train(nose: CGFloat, level: CGFloat, towards: CGFloat, colour: NSColor) {
        let length = 178 * k, half = 36 * k, point = 40 * k
        let rear = nose - towards * length
        let shape = NSBezierPath()
        shape.move(to: CGPoint(x: rear, y: level - half))
        shape.line(to: CGPoint(x: nose - towards * point, y: level - half))
        shape.line(to: CGPoint(x: nose, y: level))
        shape.line(to: CGPoint(x: nose - towards * point, y: level + half))
        shape.line(to: CGPoint(x: rear, y: level + half))
        shape.close()
        ctx.setShadow(offset: .zero, blur: 30 * k, color: colour.withAlphaComponent(0.95).cgColor)
        colour.set()
        shape.fill()
        ctx.setShadow(offset: .zero, blur: 0, color: nil)
    }

    // --- The cab's movement authority: from its nose to the rear of the
    //     train ahead, less the margin ---
    let authority = NSBezierPath()
    authority.move(to: CGPoint(x: 456 * k, y: upper + 76 * k))
    authority.line(to: CGPoint(x: 566 * k, y: upper + 76 * k))
    authority.move(to: CGPoint(x: 566 * k, y: upper + 50 * k))
    authority.line(to: CGPoint(x: 566 * k, y: upper + 102 * k))
    authority.lineWidth = 12 * k
    authority.lineCapStyle = .round
    ctx.setShadow(offset: .zero, blur: 16 * k, color: cyan.withAlphaComponent(0.9).cgColor)
    cyan.set()
    authority.stroke()
    ctx.setShadow(offset: .zero, blur: 0, color: nil)

    // --- The trains: a cab and an automatic train on track 1, an
    //     automatic train on track 2, running the other way ---
    train(nose: 446 * k, level: upper, towards: 1, colour: cyan)
    train(nose: 772 * k, level: upper, towards: 1, colour: green)
    train(nose: 400 * k, level: lower, towards: -1, colour: green)

    // Thin screen bezel.
    amber.withAlphaComponent(0.30).set()
    let bezel = NSBezierPath(roundedRect: body.insetBy(dx: 6 * k, dy: 6 * k),
                             xRadius: radius - 6 * k, yRadius: radius - 6 * k)
    bezel.lineWidth = 4 * k
    bezel.stroke()

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

// The icon set of a Mac app: five sizes, each at 1x and 2x.
let outDir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "."
try FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)
var images: [[String: String]] = []
for points in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let name = "icon_\(points)x\(points)" + (scale == 2 ? "@2x" : "") + ".png"
        try makeIcon(points * scale).write(to: URL(fileURLWithPath: outDir).appendingPathComponent(name))
        images.append(["size": "\(points)x\(points)", "idiom": "mac", "filename": name, "scale": "\(scale)x"])
        print("wrote \(name)")
    }
}
let contents: [String: Any] = ["images": images, "info": ["version": 1, "author": "xcode"]]
let json = try JSONSerialization.data(withJSONObject: contents, options: [.prettyPrinted, .sortedKeys])
try json.write(to: URL(fileURLWithPath: outDir).appendingPathComponent("Contents.json"))
print("wrote Contents.json")
