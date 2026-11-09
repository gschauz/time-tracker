import AppKit
import Foundation

let directory = URL(fileURLWithPath: CommandLine.arguments[1])
try Foundation.FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
func render(_ pixels: Int) -> Data {
    let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
                                  bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                  isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
    let scale = CGFloat(pixels) / 1024
    let transform = NSAffineTransform()
    transform.scale(by: scale)
    transform.concat()
    let panel = NSBezierPath(roundedRect: NSRect(x: 70, y: 70, width: 884, height: 884), xRadius: 196, yRadius: 196)
    NSColor(white: 0.14, alpha: 1).setFill(); panel.fill()
    let gradient = NSGradient(starting: NSColor(white: 0.26, alpha: 1), ending: NSColor(white: 0.10, alpha: 1))!
    gradient.draw(in: panel, angle: -90)
    NSColor(white: 0.4, alpha: 0.5).setStroke(); panel.lineWidth = 3; panel.stroke()
    let ring = NSBezierPath(ovalIn: NSRect(x: 272, y: 232, width: 480, height: 480))
    NSColor.white.setStroke(); ring.lineWidth = 43; ring.stroke()
    let cap = NSBezierPath(roundedRect: NSRect(x: 446, y: 771, width: 132, height: 43), xRadius: 14, yRadius: 14)
    NSColor.white.setFill(); cap.fill()
    let stem = NSBezierPath(rect: NSRect(x: 492, y: 716, width: 40, height: 62)); stem.fill()
    let hand = NSBezierPath()
    hand.move(to: NSPoint(x: 512, y: 634)); hand.line(to: NSPoint(x: 512, y: 472)); hand.line(to: NSPoint(x: 610, y: 420))
    hand.lineWidth = 39; hand.lineCapStyle = .round; hand.lineJoinStyle = .round; hand.stroke()
    NSGraphicsContext.restoreGraphicsState()
    return bitmap.representation(using: .png, properties: [:])!
}
for size in [16, 32, 128, 256, 512] {
    try render(size).write(to: directory.appendingPathComponent("icon_\(size)x\(size).png"))
    try render(size * 2).write(to: directory.appendingPathComponent("icon_\(size)x\(size)@2x.png"))
}

// PNG-backed ICNS elements avoid relying on iconutil's image conversion services.
func be32(_ value: Int) -> Data {
    var number = UInt32(value).bigEndian
    return withUnsafeBytes(of: &number) { Data($0) }
}
var elements = Data()
for (type, size) in [("icp4", 16), ("icp5", 32), ("icp6", 64), ("ic07", 128), ("ic08", 256), ("ic09", 512), ("ic10", 1024)] {
    let png = render(size)
    elements.append(Data(type.utf8))
    elements.append(be32(png.count + 8))
    elements.append(png)
}
var icon = Data("icns".utf8)
icon.append(be32(elements.count + 8))
icon.append(elements)
try icon.write(to: URL(fileURLWithPath: CommandLine.arguments[2]))
