// Renders the app icon into ExcaliApp/Assets.xcassets/AppIcon.appiconset.
// Lives outside ExcaliApp/ so Xcode's synchronized group does not compile it
// into the app target. Run: Scripts/make-icon.sh
//
// The artwork is deliberately full-bleed — a plain square with no rounded
// corners and no padding. macOS 27 masks app icons to its own squircle and
// adds the shadow and edge highlight itself; handing it art that already has
// a rounded shape makes it shrink that art onto a second grey plate, so the
// icon ends up nested inside another icon.
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let topColor = CGColor(red: 0.506, green: 0.471, blue: 0.957, alpha: 1)      // #8178F4
let bottomColor = CGColor(red: 0.310, green: 0.275, blue: 0.788, alpha: 1)   // #4F46C9

/// Stroke weight as a fraction of the canvas, so the glyph keeps identical
/// weight in every slot from 1024 down to 16.
let strokeRatio: CGFloat = 0.072
/// Tilt keeps the glyph from reading as a second rectangle lined up inside
/// the icon's own rounded square.
let tiltDegrees: CGFloat = -7

/// One edge of the square. Endpoints are canvas fractions; `bow` pushes the
/// midpoint sideways so the line is never quite straight. The small
/// irregularities are the point — this should look drawn, not constructed.
struct Stroke {
    let from: CGPoint
    let to: CGPoint
    let bow: CGFloat
}

let glyph: [Stroke] = [
    Stroke(from: CGPoint(x: 0.283, y: 0.289), to: CGPoint(x: 0.720, y: 0.281), bow:  0.013),
    Stroke(from: CGPoint(x: 0.718, y: 0.284), to: CGPoint(x: 0.724, y: 0.717), bow: -0.011),
    Stroke(from: CGPoint(x: 0.722, y: 0.720), to: CGPoint(x: 0.280, y: 0.723), bow:  0.010),
    Stroke(from: CGPoint(x: 0.282, y: 0.721), to: CGPoint(x: 0.280, y: 0.287), bow: -0.012),
]

/// Bows a straight line by offsetting its control point perpendicular to it.
func bowedPath(_ stroke: Stroke, canvas: CGFloat) -> CGPath {
    func place(_ p: CGPoint) -> CGPoint {
        CGPoint(x: p.x * canvas, y: (1 - p.y) * canvas)
    }
    let from = place(stroke.from)
    let to = place(stroke.to)
    let mid = CGPoint(x: (from.x + to.x) / 2, y: (from.y + to.y) / 2)
    let dx = to.x - from.x, dy = to.y - from.y
    let length = max(sqrt(dx * dx + dy * dy), 0.0001)
    let offset = stroke.bow * canvas
    let control = CGPoint(x: mid.x - dy / length * offset, y: mid.y + dx / length * offset)

    let path = CGMutablePath()
    path.move(to: from)
    path.addQuadCurve(to: to, control: control)
    return path
}

func renderIcon(pixels: Int) -> CGImage {
    let size = CGFloat(pixels)
    let context = CGContext(
        data: nil, width: pixels, height: pixels, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!
    context.setAllowsAntialiasing(true)

    let gradient = CGGradient(
        colorsSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
        colors: [topColor, bottomColor] as CFArray, locations: [0, 1]
    )!
    context.drawLinearGradient(
        gradient,
        start: CGPoint(x: size / 2, y: size),
        end: CGPoint(x: size / 2, y: 0),
        options: []
    )

    context.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
    context.setLineCap(.round)
    context.setLineWidth(size * strokeRatio)

    context.translateBy(x: size / 2, y: size / 2)
    context.rotate(by: tiltDegrees * .pi / 180)
    context.translateBy(x: -size / 2, y: -size / 2)
    for stroke in glyph {
        context.addPath(bowedPath(stroke, canvas: size))
        context.strokePath()
    }

    return context.makeImage()!
}

func write(_ image: CGImage, to url: URL) {
    let destination = CGImageDestinationCreateWithURL(
        url as CFURL, UTType.png.identifier as CFString, 1, nil
    )!
    CGImageDestinationAddImage(destination, image, nil)
    precondition(CGImageDestinationFinalize(destination), "failed to write \(url.lastPathComponent)")
}

let outputDirectory = URL(filePath: CommandLine.arguments[1])
let slots: [(points: Int, scale: Int)] = [
    (16, 1), (16, 2), (32, 1), (32, 2), (128, 1),
    (128, 2), (256, 1), (256, 2), (512, 1), (512, 2),
]
var cache: [Int: CGImage] = [:]

for slot in slots {
    let pixels = slot.points * slot.scale
    let image = cache[pixels] ?? renderIcon(pixels: pixels)
    cache[pixels] = image
    let suffix = slot.scale == 1 ? "" : "@2x"
    let name = "icon_\(slot.points)x\(slot.points)\(suffix).png"
    write(image, to: outputDirectory.appending(path: name))
    print("  \(name)  \(pixels)x\(pixels)")
}
print("done")
