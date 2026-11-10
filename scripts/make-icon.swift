// Draws the app icon: a cushion-shaded treemap inside a rounded square.
// Usage: swift scripts/make-icon.swift <out.iconset>
import AppKit
import CoreGraphics

struct Tile { var rect: CGRect; var color: (Double, Double, Double) }

let colors: [(Double, Double, Double)] = [
    (0.25, 0.25, 1.00), (1.00, 0.25, 0.25), (0.25, 0.95, 0.25), (0.15, 0.90, 0.90),
    (0.95, 0.15, 0.95), (0.95, 0.95, 0.15), (0.50, 0.50, 0.90), (0.90, 0.50, 0.50),
]

/// A fixed hand-made treemap in unit space, so the icon reads at 16 px.
let layout: [(CGRect, Int)] = [
    (CGRect(x: 0.00, y: 0.00, width: 0.58, height: 0.62), 0),
    (CGRect(x: 0.00, y: 0.62, width: 0.34, height: 0.38), 2),
    (CGRect(x: 0.34, y: 0.62, width: 0.24, height: 0.38), 5),
    (CGRect(x: 0.58, y: 0.00, width: 0.42, height: 0.36), 1),
    (CGRect(x: 0.58, y: 0.36, width: 0.22, height: 0.34), 3),
    (CGRect(x: 0.80, y: 0.36, width: 0.20, height: 0.34), 4),
    (CGRect(x: 0.58, y: 0.70, width: 0.24, height: 0.30), 6),
    (CGRect(x: 0.82, y: 0.70, width: 0.18, height: 0.30), 7),
]

func render(size px: Int) -> CGImage {
    let space = CGColorSpaceCreateDeviceRGB()
    let ctx = CGContext(data: nil, width: px, height: px, bitsPerComponent: 8, bytesPerRow: 0,
                        space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    let s = Double(px)
    // macOS icon grid: 824/1024 body, centred.
    let inset = s * 100 / 1024
    let body = CGRect(x: inset, y: inset, width: s - 2 * inset, height: s - 2 * inset)
    let radius = body.width * 0.225
    let path = CGPath(roundedRect: body, cornerWidth: radius, cornerHeight: radius, transform: nil)

    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -s * 0.01), blur: s * 0.025,
                  color: CGColor(gray: 0, alpha: 0.35))
    ctx.addPath(path); ctx.setFillColor(CGColor(gray: 0.12, alpha: 1)); ctx.fillPath()
    ctx.restoreGState()

    // Cushion pixels into a buffer for the inner area.
    let frame = body.insetBy(dx: body.width * 0.07, dy: body.width * 0.07)
    let w = Int(frame.width.rounded()), h = Int(frame.height.rounded())
    var pixels = [UInt8](repeating: 0, count: w * h * 4)
    let light = { () -> (Double, Double, Double) in
        let v = (-1.0, -1.0, 10.0); let n = (v.0 * v.0 + v.1 * v.1 + v.2 * v.2).squareRoot()
        return (v.0 / n, v.1 / n, v.2 / n)
    }()
    let gap = max(1.0, Double(w) * 0.012)
    for (unit, ci) in layout {
        let r = CGRect(x: unit.minX * Double(w), y: unit.minY * Double(h),
                       width: unit.width * Double(w), height: unit.height * Double(h))
            .insetBy(dx: gap / 2, dy: gap / 2)
        let c = colors[ci]
        // Parabolic cushion: the slope grows linearly from the tile's centre to its edges.
        let steepness = 1.8
        for py in Int(r.minY)..<min(h, Int(r.maxY)) {
            let y = Double(py) + 0.5
            let ny = steepness * (2 * y - r.minY - r.maxY) / Double(r.height)
            for pxi in Int(r.minX)..<min(w, Int(r.maxX)) {
                let x = Double(pxi) + 0.5
                let nx = steepness * (2 * x - r.minX - r.maxX) / Double(r.width)
                let cosine = (nx * light.0 + ny * light.1 + light.2) / (nx * nx + ny * ny + 1).squareRoot()
                let i = 40.0 / 255 + 215.0 / 255 * max(0, cosine)
                let o = (py * w + pxi) * 4
                pixels[o] = UInt8(min(255, c.0 * i * 255))
                pixels[o + 1] = UInt8(min(255, c.1 * i * 255))
                pixels[o + 2] = UInt8(min(255, c.2 * i * 255))
                pixels[o + 3] = 255
            }
        }
    }
    let provider = CGDataProvider(data: Data(pixels) as CFData)!
    let tiles = CGImage(width: w, height: h, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: w * 4,
                        space: space, bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                        provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)!
    ctx.saveGState()
    let innerRadius = radius * 0.7
    ctx.addPath(CGPath(roundedRect: frame, cornerWidth: innerRadius, cornerHeight: innerRadius, transform: nil))
    ctx.clip()
    ctx.draw(tiles, in: frame)

    // Yellow selection outline around the big tile, as in the app.
    let big = layout[0].0
    let sel = CGRect(x: frame.minX + big.minX * frame.width,
                     y: frame.maxY - big.maxY * frame.height,
                     width: big.width * frame.width, height: big.height * frame.height)
        .insetBy(dx: gap / 2, dy: gap / 2)
    ctx.setStrokeColor(CGColor(red: 1, green: 0.85, blue: 0.1, alpha: 1))
    ctx.setLineWidth(max(1, s * 0.012))
    ctx.stroke(sel.insetBy(dx: s * 0.006, dy: s * 0.006))
    ctx.restoreGState()
    return ctx.makeImage()!
}

let out = URL(filePath: CommandLine.arguments[1])
try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
for base in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let name = scale == 1 ? "icon_\(base)x\(base).png" : "icon_\(base)x\(base)@2x.png"
        let rep = NSBitmapImageRep(cgImage: render(size: base * scale))
        try rep.representation(using: .png, properties: [:])!.write(to: out.appending(path: name))
    }
}
