// Draws Silicon Wallet's app icon: a silicon chip with a keyhole, on a teal-to-navy gradient.
// Original artwork, made only from shapes here. Run through `task icon`; it rewrites the PNGs in
// App/Resources/Assets.xcassets/AppIcon.appiconset.
//
//   swift scripts/make-icon.swift <appiconset directory>

import AppKit
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

enum Variant { case light, dark, tinted }

let output = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : ".")

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(
        srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
        blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
}

func linearGradient(_ context: CGContext, _ colors: [CGColor], from start: CGPoint, to end: CGPoint) {
    let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: colors as CFArray, locations: nil)!
    context.drawLinearGradient(gradient, start: start, end: end, options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
}

/// Draws the artwork into a square `rect`: background, then the chip and keyhole.
func drawArtwork(_ context: CGContext, in rect: CGRect, variant: Variant, clip: CGPath?) {
    let unit = rect.width / 1024
    func r(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> CGRect {
        CGRect(x: rect.minX + x * unit, y: rect.minY + y * unit, width: w * unit, height: h * unit)
    }

    context.saveGState()
    if let clip {
        context.addPath(clip)
        context.clip()
    }

    // Background.
    switch variant {
    case .light:
        linearGradient(context, [color(0x2A8FA8), color(0x1C3F6E), color(0x15213F)], from: CGPoint(x: rect.minX, y: rect.maxY), to: CGPoint(x: rect.maxX, y: rect.minY))
    case .dark:
        linearGradient(context, [color(0x0F2A36), color(0x0A1424)], from: CGPoint(x: rect.minX, y: rect.maxY), to: CGPoint(x: rect.maxX, y: rect.minY))
    case .tinted:
        context.setFillColor(color(0x000000))
        context.fill(rect)
    }

    // A soft glow behind the chip.
    if variant != .tinted {
        let glow = CGGradient(
            colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
            colors: [color(0x7FE3F0, variant == .dark ? 0.35 : 0.28), color(0x7FE3F0, 0)] as CFArray, locations: [0, 1])!
        let centre = CGPoint(x: rect.midX, y: rect.midY)
        context.drawRadialGradient(glow, startCenter: centre, startRadius: 0, endCenter: centre, endRadius: 470 * unit, options: [])
    }

    // Pins: five on each side.
    let pinColour: CGColor =
        switch variant {
        case .light: color(0xC9D3DD)
        case .dark: color(0x6FB8C8)
        case .tinted: color(0xB0B0B0)
        }
    context.setFillColor(pinColour)
    let pinLength: CGFloat = 92, pinWidth: CGFloat = 34, chipOrigin: CGFloat = 262, chipSize: CGFloat = 500
    for index in 0..<5 {
        let offset = chipOrigin + 70 + CGFloat(index) * 82.5 - pinWidth / 2
        for pin in [
            r(chipOrigin - pinLength + 12, offset, pinLength, pinWidth),  // left
            r(chipOrigin + chipSize - 12, offset, pinLength, pinWidth),  // right
            r(offset, chipOrigin - pinLength + 12, pinWidth, pinLength),  // bottom
            r(offset, chipOrigin + chipSize - 12, pinWidth, pinLength),  // top
        ] {
            context.addPath(CGPath(roundedRect: pin, cornerWidth: 10 * unit, cornerHeight: 10 * unit, transform: nil))
        }
    }
    context.fillPath()

    // The chip body.
    let body = CGPath(
        roundedRect: r(chipOrigin, chipOrigin, chipSize, chipSize), cornerWidth: 72 * unit, cornerHeight: 72 * unit,
        transform: nil)
    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: -14 * unit), blur: 40 * unit, color: color(0x000000, 0.35))
    context.addPath(body)
    context.setFillColor(color(0xFFFFFF))
    context.fillPath()
    context.restoreGState()

    context.saveGState()
    context.addPath(body)
    context.clip()
    switch variant {
    case .light:
        linearGradient(context, [color(0xF4F7FA), color(0xB7C3CF)], from: CGPoint(x: rect.midX, y: r(0, 762, 0, 0).minY), to: CGPoint(x: rect.midX, y: r(0, 262, 0, 0).minY))
    case .dark:
        linearGradient(context, [color(0x2C4A5C), color(0x172838)], from: CGPoint(x: rect.midX, y: r(0, 762, 0, 0).minY), to: CGPoint(x: rect.midX, y: r(0, 262, 0, 0).minY))
    case .tinted:
        linearGradient(context, [color(0xF0F0F0), color(0xC8C8C8)], from: CGPoint(x: rect.midX, y: r(0, 762, 0, 0).minY), to: CGPoint(x: rect.midX, y: r(0, 262, 0, 0).minY))
    }
    context.restoreGState()

    // The die outline inside the chip.
    let die = CGPath(roundedRect: r(318, 318, 388, 388), cornerWidth: 40 * unit, cornerHeight: 40 * unit, transform: nil)
    context.addPath(die)
    context.setLineWidth(10 * unit)
    context.setStrokeColor(variant == .dark ? color(0x6FB8C8, 0.55) : color(0x6B7C8F, variant == .tinted ? 0.6 : 0.45))
    context.strokePath()

    // The keyhole: a circle and a tapered slot, filled separately so their overlap stays solid.
    let keyhole = CGMutablePath()
    keyhole.move(to: CGPoint(x: rect.minX + 488 * unit, y: rect.minY + 520 * unit))
    keyhole.addLine(to: CGPoint(x: rect.minX + 536 * unit, y: rect.minY + 520 * unit))
    keyhole.addLine(to: CGPoint(x: rect.minX + 566 * unit, y: rect.minY + 392 * unit))
    keyhole.addLine(to: CGPoint(x: rect.minX + 458 * unit, y: rect.minY + 392 * unit))
    keyhole.closeSubpath()
    switch variant {
    case .light: context.setFillColor(color(0x1C3F6E))
    case .dark: context.setFillColor(color(0x7FE3F0))
    case .tinted: context.setFillColor(color(0x202020))
    }
    context.addPath(keyhole)
    context.fillPath()
    context.addEllipse(in: r(512 - 66, 548 - 66, 132, 132))
    context.fillPath()

    context.restoreGState()
}

func render(size: Int, variant: Variant, mac: Bool) -> CGImage {
    let side = CGFloat(size)
    let context = CGContext(
        data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: mac || variant == .tinted
            ? CGImageAlphaInfo.premultipliedLast.rawValue : CGImageAlphaInfo.noneSkipLast.rawValue)!
    context.interpolationQuality = .high
    if mac {
        // The macOS grid: an 824-point rounded square, centred, with a drop shadow.
        let scale = side / 1024
        let plate = CGRect(x: 100 * scale, y: 100 * scale, width: 824 * scale, height: 824 * scale)
        let shape = CGPath(roundedRect: plate, cornerWidth: 185 * scale, cornerHeight: 185 * scale, transform: nil)
        context.saveGState()
        context.setShadow(offset: CGSize(width: 0, height: -10 * scale), blur: 28 * scale, color: color(0x000000, 0.3))
        context.addPath(shape)
        context.setFillColor(color(0x1C3F6E))
        context.fillPath()
        context.restoreGState()
        drawArtwork(context, in: plate, variant: variant, clip: shape)
    } else {
        drawArtwork(context, in: CGRect(x: 0, y: 0, width: side, height: side), variant: variant, clip: nil)
    }
    return context.makeImage()!
}

func write(_ image: CGImage, _ name: String) {
    let url = output.appendingPathComponent(name)
    let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else { fatalError("couldn't write \(name)") }
}

write(render(size: 1024, variant: .light, mac: false), "icon-ios.png")
write(render(size: 1024, variant: .dark, mac: false), "icon-ios-dark.png")
write(render(size: 1024, variant: .tinted, mac: false), "icon-ios-tinted.png")
for points in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        write(render(size: points * scale, variant: .light, mac: true), "icon-mac-\(points)@\(scale)x.png")
    }
}

let macImages = [16, 32, 128, 256, 512].flatMap { points in
    [1, 2].map { scale in
        """
            {
              "filename" : "icon-mac-\(points)@\(scale)x.png",
              "idiom" : "mac",
              "scale" : "\(scale)x",
              "size" : "\(points)x\(points)"
            }
        """
    }
}
let contents = """
    {
      "images" : [
        {
          "filename" : "icon-ios.png",
          "idiom" : "universal",
          "platform" : "ios",
          "size" : "1024x1024"
        },
        {
          "appearances" : [ { "appearance" : "luminosity", "value" : "dark" } ],
          "filename" : "icon-ios-dark.png",
          "idiom" : "universal",
          "platform" : "ios",
          "size" : "1024x1024"
        },
        {
          "appearances" : [ { "appearance" : "luminosity", "value" : "tinted" } ],
          "filename" : "icon-ios-tinted.png",
          "idiom" : "universal",
          "platform" : "ios",
          "size" : "1024x1024"
        },
    \(macImages.joined(separator: ",\n"))
      ],
      "info" : {
        "author" : "xcode",
        "version" : 1
      }
    }

    """
try! contents.write(to: output.appendingPathComponent("Contents.json"), atomically: true, encoding: .utf8)
print("wrote \(output.path)")
