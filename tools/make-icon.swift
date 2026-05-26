// Generates a macOS .iconset from a source image, applying the standard
// rounded-rect ("squircle") mask + padding so it reads as a native app icon.
// Usage: swift tools/make-icon.swift <source.png> <out.iconset-dir>
import AppKit
import Foundation

let args = CommandLine.arguments
guard args.count >= 3 else { FileHandle.standardError.write(Data("usage: make-icon <source> <iconset-dir>\n".utf8)); exit(1) }
guard let src = NSImage(contentsOfFile: args[1]) else { FileHandle.standardError.write(Data("cannot load source image\n".utf8)); exit(1) }
let outDir = URL(fileURLWithPath: args[2])
try? FileManager.default.removeItem(at: outDir)
try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

func renderPNG(_ size: Int) -> Data? {
    let n = CGFloat(size)
    guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
                                     bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                     colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { return nil }
    rep.size = NSSize(width: n, height: n)
    guard let ctx = NSGraphicsContext(bitmapImageRep: rep) else { return nil }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = ctx
    let cg = ctx.cgContext
    cg.clear(CGRect(x: 0, y: 0, width: n, height: n))

    let inset = (n * 0.085).rounded()
    let body = CGRect(x: inset, y: inset, width: n - 2 * inset, height: n - 2 * inset)
    let radius = body.width * 0.2237   // macOS app-icon corner radius
    cg.addPath(CGPath(roundedRect: body, cornerWidth: radius, cornerHeight: radius, transform: nil))
    cg.clip()
    src.draw(in: body, from: .zero, operation: .copy, fraction: 1.0,
             respectFlipped: true, hints: [.interpolation: NSImageInterpolation.high])

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])
}

let specs: [(String, Int)] = [
    ("icon_16x16", 16), ("icon_16x16@2x", 32),
    ("icon_32x32", 32), ("icon_32x32@2x", 64),
    ("icon_128x128", 128), ("icon_128x128@2x", 256),
    ("icon_256x256", 256), ("icon_256x256@2x", 512),
    ("icon_512x512", 512), ("icon_512x512@2x", 1024),
]
for (name, size) in specs {
    guard let data = renderPNG(size) else { FileHandle.standardError.write(Data("render failed: \(name)\n".utf8)); exit(1) }
    try data.write(to: outDir.appendingPathComponent("\(name).png"))
}
print("wrote \(specs.count) sizes to \(outDir.path)")
