import Foundation
import CoreGraphics
import CoreText
import ImageIO
import UniformTypeIdentifiers

/// Ten original motion compositions. Rendered offline, never in the app's UI loop.
extension ExportVideoWallpapers {
    static let cinemaStyles = ["Eclipse", "Titan", "NeonRain", "BinaryDunes", "OrbitalGarden", "Vertigo", "SilverScreen", "Deco", "CosmicOpera", "AlienCrystal"]

    static func cinemaSheet(root: URL) throws {
        let names = ["Eclipse de cobre", "Mar de Titán", "Lluvia neón", "Dunas binarias", "Jardín orbital", "Vértigo", "Proyector nocturno", "Palacio art déco", "Ópera cósmica", "Cristal alienígena"]
        let cw = 1460, ch = 1160
        let c = CGContext(data: nil, width: cw, height: ch, bitsPerComponent: 8, bytesPerRow: cw * 4,
                          space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
        c.setFillColor(color(0x090C12)); c.fill(CGRect(x: 0, y: 0, width: cw, height: ch))
        func label(_ text: String, x: CGFloat, y: CGFloat, size: CGFloat, tint: UInt32) {
            let attrs: [NSAttributedString.Key: Any] = [NSAttributedString.Key(kCTFontAttributeName as String): CTFontCreateWithName("HelveticaNeue-Medium" as CFString, size, nil), NSAttributedString.Key(kCTForegroundColorAttributeName as String): color(tint)]
            c.textPosition = CGPoint(x: x, y: CGFloat(ch) - y)
            CTLineDraw(CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: attrs)), c)
        }
        label("MYAOW  /  CINE & FUTUROS", x: 30, y: 48, size: 25, tint: 0xE7DCCC)
        label("10 composiciones originales · movimiento ambiental · octubre 2026", x: 30, y: 77, size: 15, tint: 0x8894A3)
        for (index, style) in cinemaStyles.enumerated() {
            let x = CGFloat(30 + index % 5 * 286), y = CGFloat(102 + index / 5 * 524)
            c.saveGState()
            c.translateBy(x: x, y: CGFloat(ch) - y); c.scaleBy(x: 0.5, y: -0.5)
            c.clip(to: CGRect(x: 0, y: 0, width: width, height: height))
            draw(c, style: style, phase: 0)
            c.restoreGState()
            label(names[index], x: x, y: y + 504, size: 16, tint: 0xCCD2DC)
        }
        let folder = root.appendingPathComponent("Review/2026-10-11/Cine")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appendingPathComponent("coleccion.png")
        let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(dest, c.makeImage()!, nil)
        guard CGImageDestinationFinalize(dest) else { throw CocoaError(.fileWriteUnknown) }
    }

    static func stroke(_ c: CGContext, _ points: [CGPoint], tint: UInt32, alpha: CGFloat, width: CGFloat = 1) {
        guard let first = points.first else { return }
        c.beginPath(); c.move(to: first)
        for point in points.dropFirst() { c.addLine(to: point) }
        c.setStrokeColor(color(tint, alpha)); c.setLineWidth(width); c.strokePath()
    }
    static func polygon(_ c: CGContext, _ points: [CGPoint], tint: UInt32, alpha: CGFloat = 1) {
        guard let first = points.first else { return }
        c.beginPath(); c.move(to: first)
        for point in points.dropFirst() { c.addLine(to: point) }
        c.closePath(); c.setFillColor(color(tint, alpha)); c.fillPath()
    }
    static func wash(_ c: CGContext, top: UInt32, bottom: UInt32) {
        let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: [color(top), color(bottom)] as CFArray, locations: [0, 1])!
        c.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: 0, y: height), options: [])
    }
    static func stars(_ c: CGContext, t: CGFloat, count: Int = 65, limit: CGFloat = 960, tint: UInt32 = 0xB5CFDF) {
        for i in 0..<count {
            let n = CGFloat(i), r: CGFloat = i % 13 == 0 ? 1.8 : 0.8
            let x = CGFloat((i * 173 + 31) % 540) + sin(t + n) * 1.6
            let y = CGFloat((i * 241 + 17) % Int(limit)) + cos(t + n) * 1.6
            c.setFillColor(color(tint, 0.23 + 0.09 * sin(t + n)))
            c.fillEllipse(in: CGRect(x: x, y: y, width: r, height: r))
        }
    }
    static func disk(_ c: CGContext, center: CGPoint, radius: CGFloat, light: UInt32, dark: UInt32) {
        c.saveGState()
        c.addEllipse(in: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)); c.clip()
        let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: [color(light), color(dark)] as CFArray, locations: [0, 1])!
        c.drawLinearGradient(gradient, start: CGPoint(x: center.x - radius, y: center.y - radius), end: CGPoint(x: center.x + radius * 0.8, y: center.y + radius * 0.4), options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
        c.restoreGState()
    }
    static func drawCinema(_ c: CGContext, style: String, phase: Double) {
        let w = CGFloat(width), h = CGFloat(height), t = CGFloat(phase)
        switch style {
        case "Eclipse":
            wash(c, top: 0x080F1A, bottom: 0x100C12)
            stars(c, t: t)
            let center = CGPoint(x: w * 0.65 + sin(t) * 5, y: h * 0.31 + cos(t) * 4)
            let radius: CGFloat = 150
            glow(c, x: center.x, y: center.y, radius: 295, tint: 0x9A502A, alpha: 0.58)
            for layer in (1...16).reversed() {
                c.setStrokeColor(color(0xF1A76A, 0.016 + 0.003 * CGFloat(16 - layer)))
                c.setLineWidth(CGFloat(layer) * 3)
                c.strokeEllipse(in: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))
            }
            disk(c, center: center, radius: radius, light: 0x18171F, dark: 0x070A10)
            // Grazing corona light travels slowly around the limb.
            for i in 0..<200 {
                let a = CGFloat(i) / 200 * .pi * 2, b = a + .pi / 100
                let light = pow(max(0, cos(a + 0.8 + sin(t) * 0.45)), 7)
                stroke(c, [CGPoint(x: center.x + cos(a) * radius, y: center.y + sin(a) * radius), CGPoint(x: center.x + cos(b) * radius, y: center.y + sin(b) * radius)], tint: 0xFFD1A2, alpha: 0.2 + light * 0.65, width: 1.8)
            }
            glow(c, x: w * 0.02, y: h * 0.96, radius: 430, tint: 0x233751, alpha: 0.25)
        case "Titan":
            wash(c, top: 0x111322, bottom: 0x183A42)
            stars(c, t: t, count: 48, limit: 560)
            let center = CGPoint(x: w * 0.31, y: h * 0.27 + sin(t) * 4)
            c.saveGState(); c.translateBy(x: center.x, y: center.y); c.rotate(by: -0.35)
            for ring in 0..<38 {
                let n = CGFloat(ring), rx = 133 + n * 1.8
                c.setStrokeColor(color(ring % 6 == 0 ? 0xE5B293 : 0x927A73, 0.10 + 0.07 * sin(n * 0.5 + t)))
                c.setLineWidth(1.2); c.strokeEllipse(in: CGRect(x: -rx, y: -rx * 0.29, width: rx * 2, height: rx * 0.58))
            }
            c.restoreGState()
            disk(c, center: center, radius: 96, light: 0xC9A68A, dark: 0x1A2534)
            glow(c, x: w * 0.65, y: h * 0.64, radius: 270, tint: 0x65A4A3, alpha: 0.22)
            let horizon = h * 0.64
            c.setFillColor(color(0x07151E)); c.fill(CGRect(x: 0, y: horizon, width: w, height: h - horizon))
            for line in 0..<70 {
                let n = CGFloat(line), v = n / 69, y = horizon + pow(v, 1.8) * (h - horizon)
                var points = [CGPoint]()
                for step in 0...90 {
                    let x = CGFloat(step) / 90 * w
                    points.append(CGPoint(x: x, y: y + sin(x * 0.019 + n * 0.7 + sin(t) * 0.6) * (1 + v * 4)))
                }
                stroke(c, points, tint: line % 4 == 0 ? 0xB49D80 : 0x437F89, alpha: (0.13 + 0.08 * sin(n + t)) * (1 - v * 0.55))
            }
        case "NeonRain":
            wash(c, top: 0x111122, bottom: 0x091A23)
            glow(c, x: w * 0.08, y: h * 0.48, radius: 360, tint: 0x9E336A, alpha: 0.40)
            glow(c, x: w * 0.95, y: h * 0.25, radius: 280, tint: 0x267F9A, alpha: 0.30)
            for building in 0..<12 {
                let n = CGFloat(building), x = n * 51 - 20, roof = CGFloat(180 + (building * 137) % 280)
                c.setFillColor(color(building % 2 == 0 ? 0x0A101C : 0x101522)); c.fill(CGRect(x: x, y: roof, width: 46, height: h - roof))
                for floor in 0..<15 {
                    let y = roof + 15 + CGFloat(floor) * 28
                    for col in 0..<3 where (building + floor * 7 + col * 3) % 5 < 2 {
                        c.setFillColor(color(building % 3 == 0 ? 0xD47886 : 0x7BBAC1, 0.16))
                        c.fill(CGRect(x: x + 8 + CGFloat(col) * 11, y: y, width: 3, height: 8))
                    }
                }
                if building % 3 == 0 {
                    let tint: UInt32 = building % 2 == 0 ? 0xE07F9D : 0x61C3CF
                    glow(c, x: x + 37, y: roof + 90, radius: 60, tint: tint, alpha: 0.23)
                    stroke(c, [CGPoint(x: x + 37, y: roof + 20), CGPoint(x: x + 37, y: roof + 145)], tint: tint, alpha: 0.50, width: 2)
                }
            }
            // Out-of-focus rain sliding down glass; bounded harmonic motion has no reset jump.
            for drop in 0..<60 {
                let n = CGFloat(drop), x = CGFloat((drop * 137 + 17) % 540)
                let y = CGFloat((drop * 197 + 11) % 960) + sin(t + n * 0.27) * 22
                stroke(c, [CGPoint(x: x, y: y), CGPoint(x: x - 3, y: y + 16)], tint: drop % 3 == 0 ? 0xC78AAB : 0x76AFC5, alpha: 0.10 + 0.04 * cos(t + n), width: 1.1)
            }
            glow(c, x: w * 0.12 + sin(t) * 18, y: h * 0.87, radius: 130, tint: 0xAC4377, alpha: 0.28)
        case "BinaryDunes":
            wash(c, top: 0x201526, bottom: 0x594131)
            stars(c, t: t, count: 32, limit: 400, tint: 0xC6A99B)
            let sun = CGPoint(x: w * 0.73 + sin(t) * 3, y: h * 0.29)
            glow(c, x: sun.x, y: sun.y, radius: 160, tint: 0xB87848, alpha: 0.36)
            disk(c, center: sun, radius: 45, light: 0xE2B580, dark: 0x996848)
            disk(c, center: CGPoint(x: w * 0.46, y: h * 0.36 + cos(t) * 2), radius: 21, light: 0xADA5B6, dark: 0x6C667D)
            for ridge in 0..<6 {
                let n = CGFloat(ridge)
                var points = [CGPoint(x: -10, y: h + 10)]
                for step in 0...100 {
                    let x = CGFloat(step) / 100 * (w + 20) - 10
                    let y = h * (0.50 + n * 0.087) + sin(x / w * 3.8 + n * 1.2) * (35 + n * 6) + sin(t + n * 0.5) * 2
                    points.append(CGPoint(x: x, y: y))
                }
                points.append(CGPoint(x: w + 10, y: h + 10))
                polygon(c, points, tint: [0x5A4140, 0x49363A, 0x352B32, 0x28232B, 0x1A1B24, 0x11141E][ridge])
                stroke(c, Array(points.dropFirst().dropLast()), tint: 0xB28A66, alpha: 0.18, width: 1)
            }
        case "OrbitalGarden":
            wash(c, top: 0x07191E, bottom: 0x09111F)
            glow(c, x: w * 0.85, y: h * 0.15, radius: 350, tint: 0x2C5E6A, alpha: 0.50)
            disk(c, center: CGPoint(x: w * 0.76, y: h * 0.18), radius: 51, light: 0x628A91, dark: 0x102331)
            for branch in 0..<7 {
                let n = CGFloat(branch), left = branch % 2 == 0
                let baseX = left ? -30 : w + 30
                let baseY = h * (0.30 + CGFloat(branch / 2) * 0.25) + sin(n * 2.1) * 32
                let reach = 125 + CGFloat((branch * 43 + 71) % 110)
                let rise = 95 + CGFloat((branch * 61 + 29) % 125)
                let direction: CGFloat = left ? 1 : -1
                let sway = sin(t + n * 0.6) * 0.035
                let stem = (0...60).map { step -> CGPoint in
                    let v = CGFloat(step) / 60
                    return CGPoint(x: baseX + direction * reach * v, y: baseY - rise * v * v + sin(v * .pi) * sway * 150)
                }
                stroke(c, stem, tint: 0x65A6A0, alpha: 0.26, width: 1.3)
                for leaf in 1..<15 {
                    let v = CGFloat(leaf) / 15, p = stem[Int(v * 60)]
                    let length = sin(v * .pi) * (42 + CGFloat((branch * 13) % 32))
                    for side: CGFloat in [-1, 1] {
                        let path = CGMutablePath(); path.move(to: p)
                        let tip = CGPoint(x: p.x + direction * length * 0.55, y: p.y + side * length - 15)
                        path.addQuadCurve(to: tip, control: CGPoint(x: p.x + direction * length * 0.80, y: p.y + side * length * 0.1))
                        path.addQuadCurve(to: p, control: CGPoint(x: p.x + direction * length * 0.15, y: p.y + side * length * 0.65))
                        c.addPath(path); c.setFillColor(color(branch % 3 == 0 ? 0x53748D : 0x37786F, 0.25)); c.fillPath()
                    }
                }
            }
            for mote in 0..<22 {
                let n = CGFloat(mote)
                glow(c, x: CGFloat((mote * 197) % 540) + sin(t + n) * 10, y: CGFloat((mote * 283) % 960) + cos(t + n) * 12, radius: 5, tint: 0x9CD3AF, alpha: 0.23)
            }
        case "Vertigo":
            wash(c, top: 0x191318, bottom: 0x0C1018)
            let cx = w * 0.72, cy = h * 0.31
            glow(c, x: cx, y: cy, radius: 360, tint: 0x8A4228, alpha: 0.24)
            // Offset spirals evoke hand-cut optical title sequences, without text or logos.
            for ribbon in 0..<3 {
                var points = [CGPoint]()
                for step in 0...720 {
                    let v = CGFloat(step) / 720, angle = v * .pi * 9 + CGFloat(ribbon) * .pi * 2 / 3 + sin(t) * 0.10
                    let radius = 14 + pow(v, 1.6) * 600
                    points.append(CGPoint(x: cx + cos(angle) * radius, y: cy + sin(angle) * radius * 1.14))
                }
                stroke(c, points, tint: ribbon == 0 ? 0xBE784E : 0x61535C, alpha: ribbon == 0 ? 0.38 : 0.22, width: ribbon == 0 ? 5 : 2)
            }
        case "SilverScreen":
            wash(c, top: 0x111721, bottom: 0x080C13)
            let source = CGPoint(x: w * 1.08, y: h * 0.22), sway = sin(t) * 28
            for layer in (1...32).reversed() {
                let spread = CGFloat(layer) * 3
                polygon(c, [source, CGPoint(x: -40, y: h * 0.40 + sway - spread), CGPoint(x: -40, y: h * 0.64 + sway + spread)], tint: 0xA9B9C6, alpha: 0.008)
            }
            glow(c, x: source.x, y: source.y, radius: 200, tint: 0xBACBD5, alpha: 0.22)
            // Venetian-blind shadows make this a noir composition, not a blank gradient.
            for slat in 0..<8 {
                let y = CGFloat(slat) * 120 - 180 + sin(t) * 5
                polygon(c, [CGPoint(x: 0, y: y), CGPoint(x: w, y: y + 270), CGPoint(x: w, y: y + 292), CGPoint(x: 0, y: y + 22)], tint: 0x03070D, alpha: 0.5)
            }
            stars(c, t: t, count: 90, tint: 0xBFC9CD)
        case "Deco":
            wash(c, top: 0x141C24, bottom: 0x090D16)
            glow(c, x: w * 0.5, y: h * 0.17, radius: 310, tint: 0x906C3B, alpha: 0.30)
            for tier in (0..<10).reversed() {
                let n = CGFloat(tier), inset = 32 + n * 18, top = 75 + n * 29
                let points = [CGPoint(x: inset, y: h), CGPoint(x: inset, y: top + 82), CGPoint(x: w * 0.5, y: top), CGPoint(x: w - inset, y: top + 82), CGPoint(x: w - inset, y: h)]
                stroke(c, points, tint: 0xB9945D, alpha: 0.10 + 0.13 * pow(max(0, cos(n * 0.55 - t)), 4), width: tier % 3 == 0 ? 2 : 1)
            }
            for i in 0..<11 {
                let n = CGFloat(i), angle = -.pi * 0.83 + n / 10 * .pi * 0.66
                stroke(c, [CGPoint(x: w * 0.5, y: h * 0.90), CGPoint(x: w * 0.5 + cos(angle) * 680, y: h * 0.90 + sin(angle) * 680)], tint: 0x806C50, alpha: 0.11)
            }
        case "CosmicOpera":
            wash(c, top: 0x160D1C, bottom: 0x080D17)
            stars(c, t: t, count: 45)
            disk(c, center: CGPoint(x: w * 0.52, y: h * 0.27), radius: 47, light: 0xA2919C, dark: 0x202338)
            for side in 0..<2 {
                for line in 0..<160 {
                    let v = CGFloat(line) / 159, direction: CGFloat = side == 0 ? 1 : -1
                    var points = [CGPoint]()
                    for step in 0...100 {
                        let y = CGFloat(step) / 100 * h
                        let opening = 0.09 + pow(y / h, 0.7) * 0.26
                        let x = (side == 0 ? 0 : w) + direction * w * (v * opening + sin(y / h * 4 + sin(t) * 0.3) * 0.018)
                        points.append(CGPoint(x: x, y: y))
                    }
                    let fold = pow(max(0, sin(v * .pi * 11 + sin(t) * 0.28)), 3)
                    stroke(c, points, tint: 0xAC3A59, alpha: 0.06 + fold * 0.38, width: 2.6)
                }
            }
            glow(c, x: w * 0.50, y: h * 1.04, radius: 370, tint: 0x6E3655, alpha: 0.28)
        default: // AlienCrystal
            wash(c, top: 0x0D1828, bottom: 0x090D1B)
            let cx = w * 0.60 + sin(t) * 6, cy = h * 0.40 + cos(t) * 8
            glow(c, x: cx, y: cy, radius: 300, tint: 0x395BB4, alpha: 0.42)
            let tip = CGPoint(x: cx - 25, y: cy - 225), foot = CGPoint(x: cx + 30, y: cy + 240)
            let vertices = [CGPoint(x: cx - 117, y: cy - 75), CGPoint(x: cx - 37, y: cy - 112), CGPoint(x: cx + 79, y: cy - 60), CGPoint(x: cx + 130, y: cy + 60), CGPoint(x: cx + 20, y: cy + 105), CGPoint(x: cx - 103, y: cy + 63)]
            let colors: [UInt32] = [0x41618C, 0x6B70AA, 0x284659, 0x1B405C, 0x29427A, 0x387381]
            for i in 0..<6 {
                let a = vertices[i], b = vertices[(i + 1) % 6], apex = i < 3 ? tip : foot
                polygon(c, [apex, a, b], tint: colors[i], alpha: 0.50 + sin(t + CGFloat(i) * 0.7) * 0.10)
                stroke(c, [apex, a, b], tint: 0x9EBAD4, alpha: 0.18, width: 0.8)
            }
            polygon(c, vertices, tint: 0x446A9D, alpha: 0.22)
            stroke(c, [tip, vertices[1], vertices[4], foot], tint: 0xB0C7E6, alpha: 0.34, width: 1.2)
            stars(c, t: t, count: 44)
        }
    }
}
