// Dessine l'icône de mSILENCE : ondes radio barrées sur fond sombre, à plat (Socle).
// Usage : swift scripts/make_icon.swift <sortie.png>
import AppKit

let size: CGFloat = 1024
let blue = NSColor(red: 0.22, green: 0.74, blue: 0.97, alpha: 1)
let amber = NSColor(red: 0.984, green: 0.749, blue: 0.141, alpha: 1)
let background = NSColor(white: 0.118, alpha: 1)
guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size), bitsPerSample: 8,
                                    samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                    bytesPerRow: 0, bitsPerPixel: 0),
      let context = NSGraphicsContext(bitmapImageRep: bitmap) else { exit(1) }
NSGraphicsContext.current = context
let cg = context.cgContext

// Gabarit macOS : carré arrondi de 824 px centré.
cg.addPath(CGPath(roundedRect: CGRect(x: 100, y: 100, width: 824, height: 824), cornerWidth: 185, cornerHeight: 185, transform: nil))
cg.setFillColor(background.cgColor)
cg.fillPath()

// Ondes : trois arcs de 100° autour d'un point, comme un signal qui rayonne.
let center = CGPoint(x: 512, y: 330)
cg.setLineCap(.round)
cg.setStrokeColor(blue.cgColor)
for (r, w) in [(110.0, 70.0), (255.0, 70.0), (400.0, 70.0)] as [(CGFloat, CGFloat)] {
    cg.setLineWidth(w)
    cg.addArc(center: center, radius: r, startAngle: .pi / 2 - 0.88, endAngle: .pi / 2 + 0.88, clockwise: false)
    cg.strokePath()
}
cg.setFillColor(blue.cgColor)
cg.fillEllipse(in: CGRect(x: center.x - 52, y: center.y - 52, width: 104, height: 104))

// Barre : le silence. Contour de la couleur du fond pour la détacher des ondes.
let a = CGPoint(x: 270, y: 760), b = CGPoint(x: 754, y: 270)
cg.setLineCap(.round)
cg.setStrokeColor(background.cgColor); cg.setLineWidth(150)
cg.move(to: a); cg.addLine(to: b); cg.strokePath()
cg.setStrokeColor(amber.cgColor); cg.setLineWidth(66)
cg.move(to: a); cg.addLine(to: b); cg.strokePath()

NSGraphicsContext.current = nil
guard let png = bitmap.representation(using: .png, properties: [:]) else { exit(1) }
try png.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
