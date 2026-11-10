import CoreGraphics
import Foundation

/// Shades treemap tiles as cushions: each pixel's brightness comes from the surface normal
/// of its tile's cushion lit by a fixed light from the upper left.
public enum CushionRenderer {
    /// Ambient and diffuse light intensities.
    static let ambient: Float = 40.0 / 255
    static let diffuse: Float = 215.0 / 255
    /// Light direction in view coordinates (y grows downward), normalised.
    static let light: SIMD3<Double> = {
        let v = SIMD3<Double>(-1, -1, 10)
        return v / (v * v).sum().squareRoot()
    }()

    /// - Parameters:
    ///   - size: canvas size in points; tile rects are in the same space.
    ///   - scale: pixels per point.
    public static func render(_ tiles: [TreemapTile], size: CGSize, scale: CGFloat,
                              color: (FileNode) -> RGB) -> CGImage? {
        let width = Int((size.width * scale).rounded()), height = Int((size.height * scale).rounded())
        guard width > 0, height > 0 else { return nil }
        var pixels = [UInt32](repeating: 0xFF00_0000, count: width * height)
        let s = Double(scale)

        pixels.withUnsafeMutableBufferPointer { buffer in
            for tile in tiles {
                let rgb = color(tile.node)
                let x0 = max(0, Int((Double(tile.rect.minX) * s).rounded()))
                let x1 = min(width, Int((Double(tile.rect.maxX) * s).rounded()))
                let y0 = max(0, Int((Double(tile.rect.minY) * s).rounded()))
                let y1 = min(height, Int((Double(tile.rect.maxY) * s).rounded()))
                guard x1 > x0, y1 > y0 else { continue }
                let surface = tile.surface

                for py in y0..<y1 {
                    let y = (Double(py) + 0.5) / s
                    let ny = -(2 * surface.c * y + surface.d)
                    let row = py * width
                    for px in x0..<x1 {
                        let x = (Double(px) + 0.5) / s
                        let nx = -(2 * surface.a * x + surface.b)
                        let cosine = (nx * light.x + ny * light.y + light.z) / (nx * nx + ny * ny + 1).squareRoot()
                        let intensity = ambient + diffuse * Float(max(0, cosine))
                        buffer[row + px] = pack(rgb, intensity)
                    }
                }
            }
        }
        return makeImage(pixels, width: width, height: height)
    }

    /// A single cushion, for colour swatches in tables.
    public static func swatch(_ rgb: RGB, size: CGSize, scale: CGFloat) -> CGImage? {
        let rect = CGRect(origin: .zero, size: size)
        var surface = CushionSurface()
        surface.addRidge(rect, height: 0.5)
        let node = FileNode(name: "", type: .file)
        return render([TreemapTile(node: node, rect: rect, surface: surface)], size: size, scale: scale) { _ in rgb }
    }

    @inline(__always)
    private static func pack(_ rgb: RGB, _ intensity: Float) -> UInt32 {
        func channel(_ value: Float) -> UInt32 { UInt32(min(255, max(0, value * intensity * 255))) }
        // Little-endian BGRA with alpha first in memory order → 0xAARRGGBB as a UInt32.
        return 0xFF00_0000 | channel(rgb.r) << 16 | channel(rgb.g) << 8 | channel(rgb.b)
    }

    private static func makeImage(_ pixels: [UInt32], width: Int, height: Int) -> CGImage? {
        let data = pixels.withUnsafeBufferPointer { Data(buffer: $0) } as CFData
        guard let provider = CGDataProvider(data: data) else { return nil }
        return CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
                       space: CGColorSpace(name: CGColorSpace.sRGB)!,
                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipFirst.rawValue
                                                | CGBitmapInfo.byteOrder32Little.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
    }
}

