// FixLineWrapsIcon.swift — draw the "Fix Line Wraps" app icon and write it as a 1024 px PNG.
//
//   swift Packaging/FixLineWrapsIcon.swift <outdir>      (Packaging/render-icon.sh does this and makes the .icns)
//
// Dark slate squircle, ivory and gold.
// The picture is the job: ragged ivory lines on top, the pairs a hard wrap leaves, becoming
// full even gold lines below. Added 2026-10-18.
import AppKit

let size: CGFloat = 1024
let outDir = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : FileManager.default.currentDirectoryPath)

func render() -> NSImage {
    let img = NSImage(size: NSSize(width: size, height: size))
    img.lockFocus()
    NSGraphicsContext.current?.imageInterpolation = .high
    guard let ctx = NSGraphicsContext.current?.cgContext else { return img }

    let inset: CGFloat = 100
    let rect = CGRect(x: inset, y: inset, width: size - 2*inset, height: size - 2*inset)
    let squircle = NSBezierPath(roundedRect: rect, xRadius: rect.width * 0.225, yRadius: rect.height * 0.225)

    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -14), blur: 40, color: NSColor.black.withAlphaComponent(0.35).cgColor)
    NSColor(calibratedRed: 0.12, green: 0.16, blue: 0.22, alpha: 1).setFill()
    squircle.fill()
    ctx.restoreGState()

    squircle.addClip()
    let bg = NSGradient(colors: [
        NSColor(calibratedRed: 0.22, green: 0.28, blue: 0.36, alpha: 1),
        NSColor(calibratedRed: 0.08, green: 0.11, blue: 0.16, alpha: 1)])!
    bg.draw(in: rect, angle: -90)

    let gold = NSColor(calibratedRed: 0.89, green: 0.70, blue: 0.25, alpha: 1)
    let ivory = NSColor(calibratedRed: 0.95, green: 0.95, blue: 0.92, alpha: 1)

    // Text block geometry
    let left: CGFloat = 236, right: CGFloat = size - 236
    let full = right - left
    let bar: CGFloat = 46           // line thickness
    let gap: CGFloat = 74           // baseline to baseline

    func line(y: CGFloat, w: CGFloat, color: NSColor) {
        let r = CGRect(x: left, y: y - bar/2, width: w, height: bar)
        color.setFill()
        NSBezierPath(roundedRect: r, xRadius: bar/2, yRadius: bar/2).fill()
    }

    // Top: the ragged wrap, a long line then a short remainder, twice.
    var y: CGFloat = 746
    line(y: y, w: full, color: ivory.withAlphaComponent(0.85)); y -= gap
    line(y: y, w: full * 0.30, color: ivory.withAlphaComponent(0.55)); y -= gap
    line(y: y, w: full * 0.92, color: ivory.withAlphaComponent(0.85)); y -= gap
    line(y: y, w: full * 0.18, color: ivory.withAlphaComponent(0.55)); y -= gap

    // The turn: a short gold return-arrow between the two blocks.
    y -= 6
    let ax = left + full * 0.5
    let arrow = NSBezierPath()
    arrow.move(to: CGPoint(x: ax, y: y + 26))
    arrow.line(to: CGPoint(x: ax, y: y - 30))
    arrow.move(to: CGPoint(x: ax - 40, y: y + 6))
    arrow.line(to: CGPoint(x: ax, y: y - 34))
    arrow.line(to: CGPoint(x: ax + 40, y: y + 6))
    arrow.lineWidth = 26; arrow.lineCapStyle = .round; arrow.lineJoinStyle = .round
    gold.setStroke(); arrow.stroke()
    y -= 86

    // Bottom: the flowed result, even full lines in gold.
    for _ in 0..<3 { line(y: y, w: full, color: gold); y -= gap }

    img.unlockFocus()
    return img
}

let image = render()
guard let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
      let png = rep.representation(using: .png, properties: [:]) else { fatalError("could not encode PNG") }
let pngURL = outDir.appendingPathComponent("_reflow_icon_1024.png")
try! png.write(to: pngURL)
print("wrote \(pngURL.path)")
