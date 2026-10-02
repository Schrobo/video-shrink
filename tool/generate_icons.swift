// Generate the same Video Shrink clapperboard icon for all desktop targets and web.
import Cocoa

let root = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? ".")
func png(_ size: Int) -> Data {
    let image = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size,
        pixelsHigh: size, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
        isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    let context = NSGraphicsContext(bitmapImageRep: image)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    context.cgContext.scaleBy(x: CGFloat(size) / 64, y: CGFloat(size) / 64)
    NSColor(calibratedRed: 117/255, green: 22/255, blue: 248/255, alpha: 1).setFill()
    NSBezierPath(roundedRect: NSRect(x: 0, y: 0, width: 64, height: 64), xRadius: 18, yRadius: 18).fill()
    NSColor.white.setStroke()
    let frame = NSBezierPath(rect: NSRect(x: 17, y: 17, width: 30, height: 25))
    frame.lineWidth = 3.5
    frame.lineJoinStyle = .round
    frame.stroke()
    let bars = NSBezierPath()
    bars.lineWidth = 3.5
    bars.move(to: NSPoint(x: 17, y: 35)); bars.line(to: NSPoint(x: 47, y: 35))
    for x in [23, 33, 43] {
        bars.move(to: NSPoint(x: x, y: 42)); bars.line(to: NSPoint(x: x + 4, y: 35))
    }
    bars.stroke()
    let play = NSBezierPath()
    play.move(to: NSPoint(x: 29, y: 30)); play.line(to: NSPoint(x: 39, y: 25)); play.line(to: NSPoint(x: 29, y: 20)); play.close()
    NSColor.white.setFill(); play.fill()
    NSGraphicsContext.restoreGraphicsState()
    return image.representation(using: .png, properties: [:])!
}
func save(_ data: Data, _ path: String) throws {
    let target = root.appendingPathComponent(path)
    try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
    try data.write(to: target)
}
for size in [16, 32, 64, 128, 256, 512, 1024] {
    try save(png(size), "macos/Runner/Assets.xcassets/AppIcon.appiconset/app_icon_\(size).png")
}
for size in [192, 512] {
    try save(png(size), "web/icons/Icon-\(size).png")
    try save(png(size), "web/icons/Icon-maskable-\(size).png")
}
try save(png(32), "web/favicon.png")
try save(png(256), "linux/icon.png")
func little<T: FixedWidthInteger>(_ value: T) -> Data {
    var encoded = value.littleEndian
    return withUnsafeBytes(of: &encoded) { Data($0) }
}
let sizes = [16, 32, 48, 256]
let images = sizes.map(png)
var ico = Data([0, 0, 1, 0])
ico.append(little(UInt16(sizes.count)))
var offset = 6 + 16 * sizes.count
for (index, size) in sizes.enumerated() {
    ico.append(contentsOf: [UInt8(size == 256 ? 0 : size), UInt8(size == 256 ? 0 : size), 0, 0])
    ico.append(little(UInt16(1))); ico.append(little(UInt16(32)))
    ico.append(little(UInt32(images[index].count))); ico.append(little(UInt32(offset)))
    offset += images[index].count
}
for image in images { ico.append(image) }
try save(ico, "windows/runner/resources/app_icon.ico")
