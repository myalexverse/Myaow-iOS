import Foundation
import CoreGraphics

/// The same mascot geometry is used in every edition, at every exported size.
/// Full-bleed, opaque artwork; iOS supplies the Home Screen corner mask.
nonisolated enum MyaowIconRenderer {
    static let variants = ["oledNoir", "cyberNeon", "furry", "liquidGlass", "pixel8bit", "holoSpace", "matcha", "magma", "gold"]
    struct Palette {
        let background: [String]
        let hood: [String]
        let face: [String]
        let accent: String
        let feature: String
        let edge: String
    }
    static func palette(_ variant: String) -> Palette {
        switch variant {
        case "oledNoir":
            return Palette(background: ["08090B", "020203"], hood: ["30343B", "111319", "1C1E24"], face: ["F6F4EB", "C7CDD5"], accent: "F6A445", feature: "12151A", edge: "555D68")
        case "cyberNeon":
            return Palette(background: ["1C1637", "090C1B"], hood: ["3D3766", "141731", "1D1939"], face: ["C5F9F5", "6DD4DA"], accent: "B292FF", feature: "19203B", edge: "8B7CC9")
        case "furry":
            return Palette(background: ["9E5E47", "60372E"], hood: ["594036", "2E241F", "3D2D25"], face: ["F7EBDD", "D9B8A0"], accent: "C77C50", feature: "3C2922", edge: "AF8061")
        case "liquidGlass":
            return Palette(background: ["1A3C50", "071521"], hood: ["6695A7", "214153", "163246"], face: ["F0FDFF", "A6D4E1"], accent: "60ACD5", feature: "15384D", edge: "C5E5EC")
        case "pixel8bit":
            return Palette(background: ["272348", "16142D"], hood: ["5C557C", "39334F"], face: ["F5EAD5", "E9D8B9"], accent: "F19A65", feature: "302640", edge: "9789BB")
        case "holoSpace":
            return Palette(background: ["202E34", "141324"], hood: ["82B8A7", "596B97", "684D79"], face: ["F4F5E9", "C9C1E2"], accent: "A385CB", feature: "303147", edge: "C8D8C8")
        case "matcha":
            return Palette(background: ["A6B49A", "6C8569"], hood: ["4F6350", "263E36", "354B3D"], face: ["F3EEDA", "DAD9B8"], accent: "A5AC76", feature: "293F34", edge: "98AD86")
        case "magma":
            return Palette(background: ["292025", "0D1016"], hood: ["644637", "252126", "342A2A"], face: ["F6CB9D", "C38660", "DCAC85"], accent: "AA593C", feature: "362922", edge: "AE7956")
        default:
            return Palette(background: ["242624", "080C10"], hood: ["6C6250", "272A28", "34342D"], face: ["F4DFAC", "C4A46C", "E5CC98"], accent: "A4824F", feature: "2A2B25", edge: "B8A072")
        }
    }
    static func color(_ hex: String, alpha: CGFloat = 1) -> CGColor {
        let number = UInt32(hex, radix: 16) ?? 0
        return CGColor(srgbRed: CGFloat((number >> 16) & 255) / 255, green: CGFloat((number >> 8) & 255) / 255,
                       blue: CGFloat(number & 255) / 255, alpha: alpha)
    }
    static func image(variant: String, size: Int = 1024) -> CGImage? {
        let renderSize = variant == "pixel8bit" ? 64 : size
        guard let context = CGContext(data: nil, width: renderSize, height: renderSize, bitsPerComponent: 8, bytesPerRow: renderSize * 4,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return nil }
        context.translateBy(x: 0, y: CGFloat(renderSize)); context.scaleBy(x: CGFloat(renderSize) / 1024, y: -CGFloat(renderSize) / 1024)
        context.setShouldAntialias(variant != "pixel8bit")
        if variant == "pixel8bit" { drawArcade(in: context) }
        else { draw(in: context, variant: variant) }
        guard let rendered = context.makeImage() else { return nil }
        if renderSize == size { return rendered }
        guard let enlarged = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: size * 4,
                                       space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return nil }
        enlarged.interpolationQuality = .none
        enlarged.draw(rendered, in: CGRect(x: 0, y: 0, width: size, height: size))
        return enlarged.makeImage()
    }
    /// Purpose-drawn 64 × 64 sprite. Every step and feature lands on the grid;
    /// no rasterized curves, fractional strokes or interpolated gradients.
    private static func drawArcade(in context: CGContext) {
        context.saveGState()
        context.scaleBy(x: 16, y: 16)
        func block(_ x: Int, _ y: Int, _ w: Int, _ h: Int, _ hex: String) {
            context.setFillColor(color(hex))
            context.fill(CGRect(x: x, y: y, width: w, height: h))
        }
        func shape(_ points: [(Int, Int)], _ hex: String) {
            let path = CGMutablePath()
            for (i, point) in points.enumerated() {
                let p = CGPoint(x: point.0, y: point.1)
                if i == 0 { path.move(to: p) } else { path.addLine(to: p) }
            }
            path.closeSubpath(); context.addPath(path); context.setFillColor(color(hex)); context.fillPath()
        }
        block(0, 0, 64, 64, "14131F")
        // A single dark plinth separates the sprite from the background.
        block(17, 52, 32, 2, "0C0B12")
        shape([(12,43),(12,25),(13,25),(13,21),(15,21),(15,17),(18,17),(18,14),
               (22,14),(22,11),(27,11),(27,10),(37,10),(37,11),(42,11),(42,14),
               (46,14),(46,17),(49,17),(49,21),(51,21),(51,25),(52,25),(52,51),
               (48,51),(48,50),(42,50),(42,48),(32,48),(32,46),(22,46),(22,44),(12,44)], "9D4C36")
        shape([(13,42),(13,25),(14,25),(14,21),(16,21),(16,17),(19,17),(19,14),
               (23,14),(23,12),(28,12),(28,11),(36,11),(36,12),(41,12),(41,15),
               (45,15),(45,18),(48,18),(48,22),(50,22),(50,26),(51,26),(51,49),
               (47,49),(47,48),(41,48),(41,46),(31,46),(31,44),(21,44),(21,42)], "EC834A")
        shape([(14,31),(14,24),(15,24),(15,21),(17,21),(17,17),(20,17),(20,15),
               (24,15),(24,13),(28,13),(28,12),(36,12),(36,13),(40,13),(40,14),
               (26,14),(26,16),(22,16),(22,18),(19,18),(19,22),(17,22),(17,26),(16,26),(16,31)], "FFB66D")
        // The asymmetrical hood, pointed ears and forehead oval identify Myaow.
        shape([(18,36),(18,32),(19,32),(19,27),(20,27),(20,22),(22,22),(22,24),
               (24,24),(24,26),(27,26),(27,27),(37,27),(37,26),(40,26),(40,24),
               (42,24),(42,22),(44,22),(44,27),(45,27),(45,32),(46,32),(46,41),
               (45,41),(45,44),(43,44),(43,47),(40,47),(40,49),(36,49),(36,50),
               (28,50),(28,49),(24,49),(24,47),(21,47),(21,44),(19,44),(19,41),(18,41)], "252130")
        shape([(19,36),(19,32),(20,32),(20,27),(21,27),(21,24),(22,24),(22,26),
               (24,26),(24,28),(28,28),(28,29),(36,29),(36,28),(40,28),(40,26),
               (42,26),(42,24),(43,24),(43,29),(44,29),(44,33),(45,33),(45,41),
               (44,41),(44,44),(42,44),(42,46),(39,46),(39,48),(35,48),(35,49),
               (29,49),(29,48),(25,48),(25,46),(22,46),(22,43),(20,43),(20,40),(19,40)], "F4E9D3")
        shape([(20,40),(21,40),(21,43),(23,43),(23,45),(26,45),(26,47),
               (38,47),(38,46),(42,46),(42,44),(44,44),(44,41),(45,41),
               (45,44),(43,44),(43,46),(40,46),(40,48),(35,48),(35,49),
               (29,49),(29,48),(25,48),(25,46),(22,46),(22,43),(20,43)], "D4BDA1")
        block(28,30,8,1,"E99455"); block(26,31,12,2,"E99455"); block(28,33,8,1,"E99455")
        for x in [24, 35] {
            block(x+1,36,3,1,"252130"); block(x,37,5,3,"252130"); block(x+1,40,3,1,"252130")
            block(x+2,43,1,3,"252130")
        }
        block(30,42,4,1,"252130"); block(31,43,2,2,"252130")
        for x in [15, 44] { block(x,40,5,1,"252130"); block(x,43,5,1,"252130") }
        context.restoreGState()
    }
    private static func gradient(_ colors: [String], path: CGPath? = nil, from: CGPoint = CGPoint(x: 160, y: 80), to: CGPoint = CGPoint(x: 860, y: 990), in context: CGContext) {
        context.saveGState()
        if let path { context.addPath(path); context.clip() }
        let values = colors.map { color($0) } as CFArray
        if let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: values, locations: nil) {
            context.drawLinearGradient(gradient, start: from, end: to, options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
        }
        context.restoreGState()
    }
    private static func draw(in context: CGContext, variant: String) {
        let p = palette(variant)
        gradient(p.background, in: context)
        let pixel = variant == "pixel8bit"
        // Preserve the original asymmetric hood, ears, oval forehead mark and teardrops.
        let hood = CGMutablePath()
        hood.move(to: CGPoint(x: 227, y: 684)); hood.addLine(to: CGPoint(x: 227, y: 474))
        hood.addCurve(to: CGPoint(x: 512, y: 189), control1: CGPoint(x: 227, y: 317), control2: CGPoint(x: 355, y: 189))
        hood.addCurve(to: CGPoint(x: 797, y: 474), control1: CGPoint(x: 670, y: 189), control2: CGPoint(x: 797, y: 317))
        hood.addLine(to: CGPoint(x: 797, y: 774)); hood.addLine(to: CGPoint(x: 777, y: 774))
        hood.addLine(to: CGPoint(x: 280, y: 684)); hood.closeSubpath()
        let face = CGMutablePath()
        face.move(to: CGPoint(x: 320, y: 585)); face.addLine(to: CGPoint(x: 381, y: 384))
        face.addQuadCurve(to: CGPoint(x: 642, y: 384), control: CGPoint(x: 512, y: 474))
        face.addLine(to: CGPoint(x: 704, y: 585))
        face.addCurve(to: CGPoint(x: 512, y: 776), control1: CGPoint(x: 704, y: 691), control2: CGPoint(x: 618, y: 776))
        face.addCurve(to: CGPoint(x: 320, y: 585), control1: CGPoint(x: 402, y: 776), control2: CGPoint(x: 320, y: 691))
        face.closeSubpath()

        context.saveGState()
        context.translateBy(x: 512, y: 488); context.scaleBy(x: 1.10, y: 1.10); context.translateBy(x: -512, y: -488)
        if !pixel {
            context.saveGState(); context.setShadow(offset: CGSize(width: 0, height: 18), blur: 40, color: color("000000", alpha: 0.38))
            context.addPath(hood); context.setFillColor(color(p.hood.last!)); context.fillPath(); context.restoreGState()
        }
        gradient(p.hood, path: hood, from: CGPoint(x: 280, y: 180), to: CGPoint(x: 750, y: 790), in: context)
        context.addPath(hood); context.setStrokeColor(color(p.edge, alpha: pixel ? 1 : 0.65)); context.setLineWidth(pixel ? 12 : 2); context.strokePath()
        if variant == "liquidGlass" || variant == "holoSpace" {
            context.saveGState(); context.addPath(hood); context.clip()
            let sheen = CGMutablePath()
            sheen.move(to: CGPoint(x: 200, y: 160)); sheen.addLine(to: CGPoint(x: 690, y: 160))
            sheen.addLine(to: CGPoint(x: 200, y: 675)); sheen.closeSubpath()
            context.addPath(sheen); context.setFillColor(color("FFFFFF", alpha: 0.08)); context.fillPath(); context.restoreGState()
        }
        if !pixel {
            context.saveGState(); context.setShadow(offset: CGSize(width: 0, height: 5), blur: 10, color: color("000000", alpha: 0.2))
            context.addPath(face); context.setFillColor(color(p.face.last!)); context.fillPath(); context.restoreGState()
        }
        gradient(p.face, path: face, from: CGPoint(x: 385, y: 390), to: CGPoint(x: 680, y: 815), in: context)
        if !pixel {
            context.addPath(face); context.setStrokeColor(color("FFFFFF", alpha: 0.24)); context.setLineWidth(1.5); context.strokePath()
        }
        // A restrained satin finish, clipped to the face rather than decorative noise around the mark.
        if variant == "gold" || variant == "magma" {
            context.saveGState(); context.addPath(face); context.clip(); context.setLineWidth(0.6)
            for y in stride(from: 380, to: 780, by: 3) {
                context.setStrokeColor(color(y % 2 == 0 ? "FFFFFF" : "372A1E", alpha: 0.055))
                context.move(to: CGPoint(x: 315, y: y)); context.addLine(to: CGPoint(x: 708, y: y)); context.strokePath()
            }
            context.restoreGState()
        }
        context.setFillColor(color(p.accent)); context.fillEllipse(in: CGRect(x: 430, y: 454, width: 164, height: 70))
        context.setFillColor(color(p.feature))
        context.fillEllipse(in: CGRect(x: 405, y: 559, width: 70, height: 70))
        context.fillEllipse(in: CGRect(x: 549, y: 559, width: 70, height: 70))
        let nose = CGMutablePath(); nose.move(to: CGPoint(x: 490, y: 629)); nose.addLine(to: CGPoint(x: 534, y: 629))
        nose.addLine(to: CGPoint(x: 512, y: 665)); nose.closeSubpath(); context.addPath(nose); context.fillPath()
        for rect in [CGRect(x: 432, y: 649, width: 16, height: 40), CGRect(x: 576, y: 649, width: 16, height: 40),
                     CGRect(x: 275, y: 623, width: 75, height: 16), CGRect(x: 275, y: 653, width: 75, height: 16),
                     CGRect(x: 674, y: 623, width: 75, height: 16), CGRect(x: 674, y: 653, width: 75, height: 16)] {
            context.addPath(CGPath(roundedRect: rect, cornerWidth: 8, cornerHeight: 8, transform: nil)); context.fillPath()
        }
        context.restoreGState()
    }
}
