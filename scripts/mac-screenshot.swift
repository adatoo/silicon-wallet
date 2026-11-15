// Helpers for the Mac App Store screenshots (scripts/mac-screenshots.sh, `task screenshots:mac`).
//
//   swift scripts/mac-screenshot.swift window <pid>       prints the app's main window number
//   swift scripts/mac-screenshot.swift frame <in> <out>   puts a window capture on the backdrop
//
// The backdrop is 2880×1800 (16:10), the size App Store Connect takes for the Mac, with the
// same soft blue gradient as the 1.0 screenshots.

import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

struct Failure: Error, CustomStringConvertible {
    let description: String
}

/// Waits up to ten seconds for a normal-level window of `pid` that's larger than a toolbar.
func window(pid: Int32) throws -> Int {
    for _ in 0..<40 {
        let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
        for window in windows where (window[kCGWindowOwnerPID as String] as? Int32) == pid {
            let bounds = window[kCGWindowBounds as String] as? [String: Double] ?? [:]
            if (window[kCGWindowLayer as String] as? Int) == 0, (bounds["Height"] ?? 0) > 200,
                let number = window[kCGWindowNumber as String] as? Int
            {
                return number
            }
        }
        Thread.sleep(forTimeInterval: 0.25)
    }
    throw Failure(description: "No window for process \(pid)")
}

func frame(input: String, output: String) throws {
    let width = 2880
    let height = 1800
    guard let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: input) as CFURL, nil),
        let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
    else { throw Failure(description: "Can't read \(input)") }
    let space = CGColorSpace(name: CGColorSpace.sRGB)!
    guard
        let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: space,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    else { throw Failure(description: "Can't make the backdrop") }

    // Top #E8F0F6 to bottom #CDDBE6. CoreGraphics' origin is the bottom left.
    let colours = [
        CGColor(srgbRed: 0xCD / 255, green: 0xDB / 255, blue: 0xE6 / 255, alpha: 1),
        CGColor(srgbRed: 0xE8 / 255, green: 0xF0 / 255, blue: 0xF6 / 255, alpha: 1),
    ]
    let gradient = CGGradient(colorsSpace: space, colors: colours as CFArray, locations: [0, 1])!
    context.drawLinearGradient(
        gradient, start: .zero, end: CGPoint(x: 0, y: height), options: [])

    // The window, shadow included, fits a box a little above the middle.
    let box = CGSize(width: 2480, height: 1640)
    let scale = min(1, box.width / CGFloat(image.width), box.height / CGFloat(image.height))
    let size = CGSize(width: CGFloat(image.width) * scale, height: CGFloat(image.height) * scale)
    let origin = CGPoint(x: (CGFloat(width) - size.width) / 2, y: (CGFloat(height) - size.height) / 2 + 30)
    context.interpolationQuality = .high
    context.draw(image, in: CGRect(origin: origin, size: size))

    guard let result = context.makeImage(),
        let destination = CGImageDestinationCreateWithURL(
            URL(fileURLWithPath: output) as CFURL, UTType.png.identifier as CFString, 1, nil)
    else { throw Failure(description: "Can't write \(output)") }
    CGImageDestinationAddImage(destination, result, nil)
    guard CGImageDestinationFinalize(destination) else { throw Failure(description: "Can't write \(output)") }
}

let arguments = Array(CommandLine.arguments.dropFirst())
do {
    switch arguments.first {
    case "window" where arguments.count == 2:
        guard let pid = Int32(arguments[1]) else { throw Failure(description: "Not a process ID: \(arguments[1])") }
        print(try window(pid: pid))
    case "frame" where arguments.count == 3:
        try frame(input: arguments[1], output: arguments[2])
    default:
        throw Failure(description: "Usage: mac-screenshot.swift window <pid> | frame <in> <out>")
    }
} catch {
    FileHandle.standardError.write(Data("error: \(error)\n".utf8))
    exit(1)
}
