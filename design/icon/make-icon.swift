// Draws the PrtSc "Keycap" app icon as vector artwork and writes PNGs.
//
// Usage: swift design/icon/make-icon.swift <output-dir> [palette ...]
//   Writes <palette>.png (1024×1024) for each palette (default: all) and preview.png, a sheet
//   showing every palette large and at 64/32/16 px. Palettes: sunset, ocean, grape.
//
//        swift design/icon/make-icon.swift --appiconset PrtSc/Resources/Assets.xcassets/AppIcon.appiconset ocean
//   Regenerates the app's icon (every macOS size + Contents.json). The shipped icon is "ocean".
//
// The design: a flat white keyboard keycap with a coloured "capture" glyph (four corner brackets around
// a dot), on a bright gradient squircle. Deliberately simple so it reads at 16×16.
import AppKit
import CoreGraphics

struct Palette {
    let name: String
    let top: (CGFloat, CGFloat, CGFloat)      // gradient start (top-left)
    let bottom: (CGFloat, CGFloat, CGFloat)   // gradient end (bottom-right)
    let glyph: (CGFloat, CGFloat, CGFloat)    // glyph colour on the white key
}

let palettes: [Palette] = [
    Palette(name: "sunset", top: (1.00, 0.62, 0.20), bottom: (0.93, 0.18, 0.47), glyph: (0.93, 0.27, 0.36)),
    Palette(name: "ocean", top: (0.20, 0.85, 0.95), bottom: (0.16, 0.36, 0.96), glyph: (0.15, 0.45, 0.95)),
    Palette(name: "grape", top: (0.62, 0.45, 1.00), bottom: (0.93, 0.25, 0.70), glyph: (0.55, 0.30, 0.95)),
]

func color(_ c: (CGFloat, CGFloat, CGFloat), _ alpha: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: c.0, green: c.1, blue: c.2, alpha: alpha)
}

/// Apple-style continuous-curvature rounded square, approximated by a superellipse (n = 5).
func squircle(in rect: CGRect, exponent n: CGFloat = 5) -> CGPath {
    let path = CGMutablePath()
    let a = rect.width / 2, b = rect.height / 2
    let steps = 720
    for i in 0...steps {
        let t = CGFloat(i) / CGFloat(steps) * 2 * .pi
        let c = cos(t), s = sin(t)
        let x = rect.midX + a * (c < 0 ? -1 : 1) * pow(abs(c), 2 / n)
        let y = rect.midY + b * (s < 0 ? -1 : 1) * pow(abs(s), 2 / n)
        if i == 0 { path.move(to: CGPoint(x: x, y: y)) } else { path.addLine(to: CGPoint(x: x, y: y)) }
    }
    path.closeSubpath()
    return path
}

/// Draws the icon for `palette` into a 1024-unit square (CG coordinates: origin bottom-left).
/// `scale` is pixels per design unit: CoreGraphics applies shadow offset and blur in device pixels,
/// ignoring the CTM, so they must be scaled by hand or small renders get a grey haze.
func drawIcon(_ ctx: CGContext, _ palette: Palette, scale: CGFloat) {
    // macOS icon grid: the body is 824×824, centred, leaving room for the system shadow.
    let body = CGRect(x: 100, y: 100, width: 824, height: 824)
    let bodyPath = squircle(in: body)

    // Soft drop shadow under the body.
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -10 * scale), blur: 24 * scale, color: CGColor(gray: 0, alpha: 0.30))
    ctx.addPath(bodyPath)
    ctx.setFillColor(color(palette.bottom))
    ctx.fillPath()
    ctx.restoreGState()

    // Gradient body.
    ctx.saveGState()
    ctx.addPath(bodyPath)
    ctx.clip()
    let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
                              colors: [color(palette.top), color(palette.bottom)] as CFArray,
                              locations: [0, 1])!
    ctx.drawLinearGradient(gradient, start: CGPoint(x: body.minX, y: body.maxY),
                           end: CGPoint(x: body.maxX, y: body.minY), options: [])
    // A gentle top sheen keeps it from looking flat-printed.
    let sheen = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
                           colors: [CGColor(gray: 1, alpha: 0.22), CGColor(gray: 1, alpha: 0)] as CFArray,
                           locations: [0, 1])!
    ctx.drawLinearGradient(sheen, start: CGPoint(x: 0, y: body.maxY), end: CGPoint(x: 0, y: body.midY),
                           options: [])
    ctx.restoreGState()

    // The keycap: a darker skirt below a white face, offset to suggest the key's height.
    let face = CGRect(x: 512 - 270, y: 512 - 215 + 28, width: 540, height: 430)
    let skirt = face.offsetBy(dx: 0, dy: -46)
    let radius: CGFloat = 96

    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -18 * scale), blur: 30 * scale, color: CGColor(gray: 0, alpha: 0.22))
    ctx.addPath(CGPath(roundedRect: skirt, cornerWidth: radius, cornerHeight: radius, transform: nil))
    ctx.setFillColor(CGColor(srgbRed: 0.86, green: 0.87, blue: 0.91, alpha: 1))
    ctx.fillPath()
    ctx.restoreGState()

    ctx.addPath(CGPath(roundedRect: face, cornerWidth: radius, cornerHeight: radius, transform: nil))
    ctx.setFillColor(CGColor(gray: 1, alpha: 1))
    ctx.fillPath()

    // The capture glyph: four corner brackets around a rounded dot, in the palette colour.
    let glyphColor = color(palette.glyph)
    let frame = CGRect(x: face.midX - 165, y: face.midY - 128, width: 330, height: 256)
    let arm: CGFloat = 86, stroke: CGFloat = 38
    ctx.setStrokeColor(glyphColor)
    ctx.setLineWidth(stroke)
    ctx.setLineCap(.round)
    ctx.setLineJoin(.round)
    let corners: [(CGPoint, CGFloat, CGFloat)] = [
        (CGPoint(x: frame.minX, y: frame.maxY), 1, -1),   // top-left
        (CGPoint(x: frame.maxX, y: frame.maxY), -1, -1),  // top-right
        (CGPoint(x: frame.minX, y: frame.minY), 1, 1),    // bottom-left
        (CGPoint(x: frame.maxX, y: frame.minY), -1, 1),   // bottom-right
    ]
    for (corner, dx, dy) in corners {
        ctx.move(to: CGPoint(x: corner.x + dx * arm, y: corner.y))
        ctx.addLine(to: corner)
        ctx.addLine(to: CGPoint(x: corner.x, y: corner.y + dy * arm))
    }
    ctx.strokePath()

    let dot = CGRect(x: frame.midX - 50, y: frame.midY - 50, width: 100, height: 100)
    ctx.addPath(CGPath(roundedRect: dot, cornerWidth: 26, cornerHeight: 26, transform: nil))
    ctx.setFillColor(glyphColor)
    ctx.fillPath()
}

func render(size: Int, _ draw: (CGContext, CGFloat) -> Void) -> CGImage {
    let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.interpolationQuality = .high
    ctx.scaleBy(x: CGFloat(size) / 1024, y: CGFloat(size) / 1024)
    draw(ctx, CGFloat(size) / 1024)
    return ctx.makeImage()!
}

func writePNG(_ image: CGImage, to url: URL) {
    let rep = NSBitmapImageRep(cgImage: image)
    try! rep.representation(using: .png, properties: [:])!.write(to: url)
}

// MARK: Main

let args = CommandLine.arguments.dropFirst()

// `--appiconset <AppIcon.appiconset> <palette>`: every macOS icon size plus Contents.json.
if args.first == "--appiconset" {
    let rest = Array(args.dropFirst())
    guard rest.count == 2, let palette = palettes.first(where: { $0.name == rest[1] }) else {
        FileHandle.standardError.write("usage: swift make-icon.swift --appiconset <dir> <palette>\n".data(using: .utf8)!)
        exit(64)
    }
    let dir = URL(fileURLWithPath: rest[0], isDirectory: true)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    var images: [[String: String]] = []
    for point in [16, 32, 128, 256, 512] {
        for scale in [1, 2] {
            let pixels = point * scale
            let name = "icon_\(point)x\(point)\(scale == 2 ? "@2x" : "").png"
            writePNG(render(size: pixels) { drawIcon($0, palette, scale: $1) }, to: dir.appendingPathComponent(name))
            images.append(["filename": name, "idiom": "mac", "scale": "\(scale)x", "size": "\(point)x\(point)"])
        }
    }
    let contents: [String: Any] = ["images": images, "info": ["author": "xcode", "version": 1]]
    let json = try JSONSerialization.data(withJSONObject: contents, options: [.prettyPrinted, .sortedKeys])
    try json.write(to: dir.appendingPathComponent("Contents.json"))
    print("Wrote \(images.count) \(palette.name) icons and Contents.json to \(dir.path)")
    exit(0)
}

guard let outPath = args.first else {
    FileHandle.standardError.write("usage: swift make-icon.swift <output-dir> [palette ...]\n".data(using: .utf8)!)
    exit(64)
}
let out = URL(fileURLWithPath: outPath, isDirectory: true)
try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
let wanted = Set(args.dropFirst())
let chosen = wanted.isEmpty ? palettes : palettes.filter { wanted.contains($0.name) }

var icons: [(Palette, CGImage)] = []
for palette in chosen {
    let image = render(size: 1024) { drawIcon($0, palette, scale: $1) }
    writePNG(image, to: out.appendingPathComponent("\(palette.name).png"))
    icons.append((palette, image))
}

// Preview sheet: each palette at 360 px, then rendered natively at 64, 32 and 16 px, on light and dark.
let cell: CGFloat = 400
let sheetW = Int(cell) * icons.count, sheetH = 640
let sheet = CGContext(data: nil, width: sheetW, height: sheetH, bitsPerComponent: 8, bytesPerRow: 0,
                      space: CGColorSpace(name: CGColorSpace.sRGB)!,
                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
sheet.setFillColor(CGColor(gray: 0.96, alpha: 1))
sheet.fill(CGRect(x: 0, y: 120, width: sheetW, height: 520))   // light: large icon + first small row
sheet.setFillColor(CGColor(gray: 0.12, alpha: 1))
sheet.fill(CGRect(x: 0, y: 0, width: sheetW, height: 120))     // dark: second small row
for (index, (palette, image)) in icons.enumerated() {
    let x = CGFloat(index) * cell
    sheet.draw(image, in: CGRect(x: x + 20, y: 260, width: 360, height: 360))
    var smallX = x + 60
    for (size, y) in [(64, 150), (32, 166), (16, 174)] as [(Int, CGFloat)] {
        let small = render(size: size) { drawIcon($0, palette, scale: $1) }
        sheet.draw(small, in: CGRect(x: smallX, y: y, width: CGFloat(size), height: CGFloat(size)))
        sheet.draw(small, in: CGRect(x: smallX, y: y - 120, width: CGFloat(size), height: CGFloat(size)))
        smallX += CGFloat(size) + 40
    }
}
writePNG(sheet.makeImage()!, to: out.appendingPathComponent("preview.png"))
print("Wrote \(icons.map { "\($0.0.name).png" }.joined(separator: ", ")) and preview.png to \(out.path)")
