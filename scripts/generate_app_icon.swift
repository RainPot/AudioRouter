import AppKit

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let output = root.appendingPathComponent("Resources/AppIcon.icns")

let size: CGFloat = 1024
let image = NSImage(size: NSSize(width: size, height: size))

image.lockFocus()
let rect = NSRect(x: 0, y: 0, width: size, height: size)
NSGraphicsContext.current?.imageInterpolation = .high

let bgPath = NSBezierPath(roundedRect: rect.insetBy(dx: 52, dy: 52), xRadius: 220, yRadius: 220)
NSGradient(colors: [
    NSColor(red: 0.04, green: 0.08, blue: 0.16, alpha: 1),
    NSColor(red: 0.02, green: 0.37, blue: 0.46, alpha: 1),
    NSColor(red: 0.10, green: 0.86, blue: 0.72, alpha: 1),
])!.draw(in: bgPath, angle: 315)

NSColor.white.withAlphaComponent(0.18).setStroke()
bgPath.lineWidth = 10
bgPath.stroke()

func circle(_ center: CGPoint, _ radius: CGFloat, _ color: NSColor) {
    color.setFill()
    NSBezierPath(ovalIn: NSRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)).fill()
}

func line(_ from: CGPoint, _ to: CGPoint, width: CGFloat) {
    let path = NSBezierPath()
    path.move(to: from)
    path.line(to: to)
    path.lineCapStyle = .round
    path.lineJoinStyle = .round
    path.lineWidth = width
    NSColor.white.withAlphaComponent(0.86).setStroke()
    path.stroke()
}

let source = CGPoint(x: 315, y: 512)
let targets = [
    CGPoint(x: 705, y: 710),
    CGPoint(x: 755, y: 512),
    CGPoint(x: 705, y: 314),
]

for target in targets {
    line(source, target, width: 68)
}

circle(source, 122, NSColor(red: 0.98, green: 0.99, blue: 1.0, alpha: 1))
circle(source, 62, NSColor(red: 0.04, green: 0.50, blue: 0.58, alpha: 1))

for target in targets {
    circle(target, 94, NSColor.white.withAlphaComponent(0.96))
    circle(target, 43, NSColor(red: 0.06, green: 0.16, blue: 0.24, alpha: 1))
}

NSColor.white.withAlphaComponent(0.18).setFill()
NSBezierPath(ovalIn: NSRect(x: 150, y: 150, width: 724, height: 724)).fill()

image.unlockFocus()

guard let tiff = image.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff) else {
    fatalError("无法生成图标位图")
}

let specs: [(String, Int)] = [("ic07", 128), ("ic08", 256), ("ic09", 512), ("ic10", 1024)]
var icns = Data("icns".utf8) + UInt32(0).bigEndianData

for (type, pixels) in specs {
    let resized = NSImage(size: NSSize(width: pixels, height: pixels))
    resized.lockFocus()
    NSGraphicsContext.current?.imageInterpolation = .high
    image.draw(in: NSRect(x: 0, y: 0, width: pixels, height: pixels), from: .zero, operation: .copy, fraction: 1)
    resized.unlockFocus()

    guard let data = resized.tiffRepresentation,
          let rep = NSBitmapImageRep(data: data),
          let png = rep.representation(using: .png, properties: [:]) else {
        fatalError("无法生成 \(type)")
    }

    let blockLength = UInt32(8 + png.count)
    icns.append(Data(type.utf8))
    icns.append(blockLength.bigEndianData)
    icns.append(png)
}

let totalLength = UInt32(icns.count).bigEndianData
icns.replaceSubrange(4..<8, with: totalLength)
try icns.write(to: output)

private extension UInt32 {
    var bigEndianData: Data {
        var value = self.bigEndian
        return Data(bytes: &value, count: MemoryLayout<UInt32>.size)
    }
}
