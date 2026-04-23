#!/usr/bin/swift

import AppKit

struct IconSpec {
    let filename: String
    let size: Int
}

let specs = [
    IconSpec(filename: "icon_16x16.png", size: 16),
    IconSpec(filename: "icon_16x16@2x.png", size: 32),
    IconSpec(filename: "icon_32x32.png", size: 32),
    IconSpec(filename: "icon_32x32@2x.png", size: 64),
    IconSpec(filename: "icon_128x128.png", size: 128),
    IconSpec(filename: "icon_128x128@2x.png", size: 256),
    IconSpec(filename: "icon_256x256.png", size: 256),
    IconSpec(filename: "icon_256x256@2x.png", size: 512),
    IconSpec(filename: "icon_512x512.png", size: 512),
    IconSpec(filename: "icon_512x512@2x.png", size: 1024)
]

let fileManager = FileManager.default
let rootURL = URL(fileURLWithPath: fileManager.currentDirectoryPath)
let resourcesURL = rootURL
    .appendingPathComponent("MailClient")
    .appendingPathComponent("Resources")
let brandSourceURL = resourcesURL
    .appendingPathComponent("Brand")
    .appendingPathComponent("AppIcon")
    .appendingPathComponent("Source")
    .appendingPathComponent("MailStrea-icon.png")
let outputURL = resourcesURL
    .appendingPathComponent("Assets.xcassets")
    .appendingPathComponent("AppIcon.appiconset", isDirectory: true)
let icnsURL = resourcesURL
    .appendingPathComponent("AppIcon.icns")

try fileManager.createDirectory(at: outputURL, withIntermediateDirectories: true)
try fileManager.createDirectory(
    at: brandSourceURL.deletingLastPathComponent(),
    withIntermediateDirectories: true
)

if fileManager.fileExists(atPath: brandSourceURL.path) == false {
    let bootstrapSource = renderFallbackIcon(size: 1024)
    try writePNG(image: bootstrapSource, to: brandSourceURL)
    print("generated \(brandSourceURL.lastPathComponent)")
}

for spec in specs {
    let image = try renderIcon(size: CGFloat(spec.size))
    let destination = outputURL.appendingPathComponent(spec.filename)
    try writePNG(image: image, to: destination)
    print("generated \(spec.filename)")
}

try buildICNS()
print("generated \(icnsURL.lastPathComponent)")

func renderIcon(size: CGFloat) throws -> NSImage {
    guard let sourceImage = NSImage(contentsOf: brandSourceURL) else {
        throw NSError(domain: "IconGeneration", code: 3, userInfo: [
            NSLocalizedDescriptionKey: "Unable to load \(brandSourceURL.lastPathComponent)"
        ])
    }

    return rasterize(sourceImage, size: size)
}

func rasterize(_ sourceImage: NSImage, size: CGFloat) -> NSImage {
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()

    NSColor.clear.setFill()
    NSRect(x: 0, y: 0, width: size, height: size).fill()

    sourceImage.draw(
        in: NSRect(x: 0, y: 0, width: size, height: size),
        from: .zero,
        operation: .sourceOver,
        fraction: 1
    )

    image.unlockFocus()
    return image
}

func renderFallbackIcon(size: CGFloat) -> NSImage {
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()

    guard let context = NSGraphicsContext.current?.cgContext else {
        fatalError("Failed to acquire graphics context.")
    }

    context.interpolationQuality = .high
    context.setAllowsAntialiasing(true)
    context.setShouldAntialias(true)

    let scale = size / 1024.0
    context.saveGState()
    context.scaleBy(x: scale, y: scale)

    drawBackground()
    drawEnvelope()
    drawBird()

    context.restoreGState()
    image.unlockFocus()
    return image
}

func drawBackground() {
    let canvas = NSRect(x: 0, y: 0, width: 1024, height: 1024)
    NSColor(calibratedWhite: 0.99, alpha: 1).setFill()
    canvas.fill()

    radialGradient(
        colors: [
            NSColor(calibratedRed: 0.77, green: 0.88, blue: 1.0, alpha: 0.95),
            NSColor(calibratedRed: 0.87, green: 0.93, blue: 1.0, alpha: 0.18),
            .clear
        ],
        locations: [0.0, 0.58, 1.0],
        startCenter: NSPoint(x: 320, y: 270),
        endCenter: NSPoint(x: 320, y: 270),
        startRadius: 10,
        endRadius: 730
    )

    radialGradient(
        colors: [
            NSColor(calibratedRed: 0.72, green: 0.84, blue: 1.0, alpha: 0.36),
            .clear
        ],
        locations: [0.0, 1.0],
        startCenter: NSPoint(x: 645, y: 700),
        endCenter: NSPoint(x: 645, y: 700),
        startRadius: 20,
        endRadius: 520
    )
}

func drawEnvelope() {
    let envelopeRect = NSRect(x: 180, y: 145, width: 640, height: 530)
    let cornerRadius: CGFloat = 86
    let envelopePath = NSBezierPath(roundedRect: envelopeRect, xRadius: cornerRadius, yRadius: cornerRadius)

    NSGraphicsContext.current?.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor(calibratedRed: 0.57, green: 0.74, blue: 1.0, alpha: 0.34)
    shadow.shadowBlurRadius = 46
    shadow.shadowOffset = NSSize(width: 0, height: -8)
    shadow.set()
    NSColor.white.setFill()
    envelopePath.fill()
    NSGraphicsContext.current?.restoreGraphicsState()

    NSGraphicsContext.current?.saveGraphicsState()
    envelopePath.addClip()

    linearGradient(
        colors: [
            NSColor(calibratedRed: 0.51, green: 0.75, blue: 1.0, alpha: 1.0),
            NSColor(calibratedRed: 0.83, green: 0.91, blue: 1.0, alpha: 1.0),
            NSColor.white
        ],
        locations: [0.0, 0.58, 1.0],
        startPoint: NSPoint(x: envelopeRect.minX, y: envelopeRect.midY),
        endPoint: NSPoint(x: envelopeRect.maxX, y: envelopeRect.midY)
    )

    let leftPanel = NSBezierPath()
    leftPanel.move(to: NSPoint(x: envelopeRect.minX, y: envelopeRect.maxY))
    leftPanel.line(to: NSPoint(x: envelopeRect.minX, y: envelopeRect.minY))
    leftPanel.line(to: NSPoint(x: envelopeRect.midX - 58, y: envelopeRect.midY + 10))
    leftPanel.close()
    NSColor(calibratedRed: 0.22, green: 0.53, blue: 0.96, alpha: 0.82).setFill()
    leftPanel.fill()

    let rightPanel = NSBezierPath()
    rightPanel.move(to: NSPoint(x: envelopeRect.maxX, y: envelopeRect.maxY))
    rightPanel.line(to: NSPoint(x: envelopeRect.maxX, y: envelopeRect.minY))
    rightPanel.line(to: NSPoint(x: envelopeRect.midX + 54, y: envelopeRect.midY + 2))
    rightPanel.close()
    linearGradient(
        colors: [
            NSColor(calibratedWhite: 1.0, alpha: 0.0),
            NSColor(calibratedRed: 0.72, green: 0.84, blue: 1.0, alpha: 0.58),
            NSColor.white
        ],
        locations: [0.0, 0.48, 1.0],
        startPoint: NSPoint(x: envelopeRect.midX + 20, y: envelopeRect.midY + 90),
        endPoint: NSPoint(x: envelopeRect.maxX, y: envelopeRect.minY + 12),
        clipPath: rightPanel
    )

    let bottomPanel = NSBezierPath()
    bottomPanel.move(to: NSPoint(x: envelopeRect.minX + 12, y: envelopeRect.minY + 10))
    bottomPanel.line(to: NSPoint(x: envelopeRect.maxX - 12, y: envelopeRect.minY + 10))
    bottomPanel.line(to: NSPoint(x: envelopeRect.midX, y: envelopeRect.midY + 4))
    bottomPanel.close()
    linearGradient(
        colors: [
            NSColor(calibratedRed: 0.64, green: 0.80, blue: 1.0, alpha: 0.78),
            NSColor(calibratedWhite: 1.0, alpha: 0.72)
        ],
        locations: [0.0, 1.0],
        startPoint: NSPoint(x: envelopeRect.minX + 70, y: envelopeRect.minY + 40),
        endPoint: NSPoint(x: envelopeRect.maxX - 70, y: envelopeRect.minY + 40),
        clipPath: bottomPanel
    )

    let flap = NSBezierPath()
    flap.move(to: NSPoint(x: envelopeRect.minX + 10, y: envelopeRect.maxY - 48))
    flap.line(to: NSPoint(x: envelopeRect.midX - 42, y: envelopeRect.midY + 12))
    flap.curve(
        to: NSPoint(x: envelopeRect.midX + 42, y: envelopeRect.midY + 12),
        controlPoint1: NSPoint(x: envelopeRect.midX - 18, y: envelopeRect.midY - 34),
        controlPoint2: NSPoint(x: envelopeRect.midX + 18, y: envelopeRect.midY - 34)
    )
    flap.line(to: NSPoint(x: envelopeRect.maxX - 10, y: envelopeRect.maxY - 48))
    flap.close()
    linearGradient(
        colors: [
            NSColor(calibratedRed: 0.71, green: 0.86, blue: 1.0, alpha: 0.98),
            NSColor.white
        ],
        locations: [0.0, 1.0],
        startPoint: NSPoint(x: envelopeRect.minX + 80, y: envelopeRect.maxY - 40),
        endPoint: NSPoint(x: envelopeRect.maxX - 80, y: envelopeRect.midY + 90),
        clipPath: flap
    )

    NSGraphicsContext.current?.restoreGraphicsState()

    NSColor(calibratedWhite: 1.0, alpha: 0.96).setStroke()
    envelopePath.lineWidth = 5
    envelopePath.stroke()

    let seam = NSBezierPath()
    seam.move(to: NSPoint(x: envelopeRect.minX + 12, y: envelopeRect.minY + 12))
    seam.line(to: NSPoint(x: envelopeRect.midX, y: envelopeRect.midY + 4))
    seam.line(to: NSPoint(x: envelopeRect.maxX - 12, y: envelopeRect.minY + 12))
    seam.move(to: NSPoint(x: envelopeRect.minX + 10, y: envelopeRect.maxY - 46))
    seam.line(to: NSPoint(x: envelopeRect.midX, y: envelopeRect.midY + 4))
    seam.line(to: NSPoint(x: envelopeRect.maxX - 10, y: envelopeRect.maxY - 46))
    seam.lineCapStyle = .round
    seam.lineJoinStyle = .round
    seam.lineWidth = 5
    seam.stroke()
}

func drawBird() {
    let bird = NSBezierPath()
    bird.move(to: NSPoint(x: 605, y: 792))
    bird.curve(
        to: NSPoint(x: 675, y: 744),
        controlPoint1: NSPoint(x: 628, y: 790),
        controlPoint2: NSPoint(x: 650, y: 772)
    )
    bird.curve(
        to: NSPoint(x: 716, y: 714),
        controlPoint1: NSPoint(x: 692, y: 730),
        controlPoint2: NSPoint(x: 703, y: 710)
    )
    bird.curve(
        to: NSPoint(x: 777, y: 733),
        controlPoint1: NSPoint(x: 740, y: 716),
        controlPoint2: NSPoint(x: 760, y: 736)
    )
    bird.curve(
        to: NSPoint(x: 731, y: 699),
        controlPoint1: NSPoint(x: 768, y: 726),
        controlPoint2: NSPoint(x: 751, y: 710)
    )
    bird.curve(
        to: NSPoint(x: 682, y: 682),
        controlPoint1: NSPoint(x: 715, y: 690),
        controlPoint2: NSPoint(x: 700, y: 682)
    )
    bird.curve(
        to: NSPoint(x: 626, y: 687),
        controlPoint1: NSPoint(x: 664, y: 682),
        controlPoint2: NSPoint(x: 646, y: 683)
    )
    bird.curve(
        to: NSPoint(x: 671, y: 717),
        controlPoint1: NSPoint(x: 641, y: 695),
        controlPoint2: NSPoint(x: 657, y: 706)
    )
    bird.curve(
        to: NSPoint(x: 605, y: 792),
        controlPoint1: NSPoint(x: 641, y: 735),
        controlPoint2: NSPoint(x: 620, y: 762)
    )
    bird.close()

    let gradient = NSGradient(colors: [
        NSColor(calibratedRed: 0.20, green: 0.50, blue: 0.93, alpha: 1.0),
        NSColor(calibratedRed: 0.50, green: 0.74, blue: 1.0, alpha: 1.0)
    ])!

    gradient.draw(in: bird, angle: 0)
}

func linearGradient(
    colors: [NSColor],
    locations: [CGFloat],
    startPoint: NSPoint,
    endPoint: NSPoint,
    clipPath: NSBezierPath? = nil
) {
    let gradient = NSGradient(colors: colors, atLocations: locations, colorSpace: .deviceRGB)!
    NSGraphicsContext.current?.saveGraphicsState()
    clipPath?.addClip()
    gradient.draw(from: startPoint, to: endPoint, options: [])
    NSGraphicsContext.current?.restoreGraphicsState()
}

func radialGradient(
    colors: [NSColor],
    locations: [CGFloat],
    startCenter: NSPoint,
    endCenter: NSPoint,
    startRadius: CGFloat,
    endRadius: CGFloat
) {
    let gradient = NSGradient(colors: colors, atLocations: locations, colorSpace: .deviceRGB)!
    gradient.draw(
        fromCenter: startCenter,
        radius: startRadius,
        toCenter: endCenter,
        radius: endRadius,
        options: []
    )
}

func writePNG(image: NSImage, to destination: URL) throws {
    guard
        let tiffData = image.tiffRepresentation,
        let bitmap = NSBitmapImageRep(data: tiffData),
        let pngData = bitmap.representation(using: .png, properties: [:])
    else {
        throw NSError(domain: "IconGeneration", code: 1, userInfo: [
            NSLocalizedDescriptionKey: "Failed to encode PNG for \(destination.lastPathComponent)"
        ])
    }

    try pngData.write(to: destination)
}

func buildICNS() throws {
    let tempIconset = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".iconset", isDirectory: true)
    try fileManager.createDirectory(at: tempIconset, withIntermediateDirectories: true)
    defer { try? fileManager.removeItem(at: tempIconset) }

    for spec in specs {
        let source = outputURL.appendingPathComponent(spec.filename)
        let destination = tempIconset.appendingPathComponent(spec.filename)
        if fileManager.fileExists(atPath: destination.path) {
            try fileManager.removeItem(at: destination)
        }
        try fileManager.copyItem(at: source, to: destination)
    }

    if fileManager.fileExists(atPath: icnsURL.path) {
        try fileManager.removeItem(at: icnsURL)
    }

    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
    process.arguments = ["-c", "icns", tempIconset.path, "-o", icnsURL.path]
    try process.run()
    process.waitUntilExit()

    guard process.terminationStatus == 0 else {
        throw NSError(domain: "IconGeneration", code: 2, userInfo: [
            NSLocalizedDescriptionKey: "iconutil failed with exit code \(process.terminationStatus)"
        ])
    }
}
