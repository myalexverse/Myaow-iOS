import SwiftUI

/// Facial marks are vectors, so an expression remains legible in a contact avatar.
struct MyaowExpressionEye: View {
    let state: MyaowCatState
    let isLeft: Bool
    let color: Color
    var eyeProgress: Double = 1
    var body: some View {
        Canvas { context, size in
            context.scaleBy(x: size.width / 160, y: size.height / 180)
            context.translateBy(x: 30, y: 40)
            func stroke(_ points: [CGPoint], width: Double = 12, tint: Color? = nil) {
                var p = Path(); p.addLines(points)
                context.stroke(p, with: .color(tint ?? color), style: StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round))
            }
            func oval(_ rect: CGRect, tint: Color? = nil) { context.fill(Path(ellipseIn: rect), with: .color(tint ?? color)) }
            func arc(_ from: CGPoint, _ control: CGPoint, _ end: CGPoint, width: Double = 12) {
                var p = Path(); p.move(to: from); p.addQuadCurve(to: end, control: control)
                context.stroke(p, with: .color(color), style: StrokeStyle(lineWidth: width, lineCap: .round))
            }
            switch state {
            case .laughing:
                stroke(isLeft ? [.init(x: 12,y: 18), .init(x: 78,y: 50), .init(x: 12,y: 80)] : [.init(x: 88,y: 18), .init(x: 22,y: 50), .init(x: 88,y: 80)], width: 15)
            case .shy:
                oval(.init(x: 22, y: 28, width: 57, height: 60), tint: color.opacity(0.55))
                oval(.init(x: isLeft ? 48 : 19, y: 48, width: 37, height: 48))
                arc(.init(x: 12,y: 8), .init(x: 50,y: isLeft ? -4 : 14), .init(x: 86,y: 12), width: 8)
            case .crying:
                arc(.init(x: 5,y: 49), .init(x: 50,y: 95), .init(x: 95,y: 36), width: 14)
                stroke([.init(x: 18,y: 63), .init(x: 18,y: 108)], width: 18, tint: Color(hex: "74D7FF"))
                stroke([.init(x: 15,y: 0), .init(x: 83,y: isLeft ? -16 : 12)], width: 9)
            case .skeptical:
                if isLeft {
                    oval(.init(x: 5,y: 39,width: 88,height: 38), tint: color.opacity(0.55))
                    oval(.init(x: 57,y: 44,width: 25,height: 32))
                    stroke([.init(x: 2,y: 35), .init(x: 96,y: 35)], width: 11)
                } else {
                    oval(.init(x: 18,y: 15,width: 68,height: 75), tint: color.opacity(0.55))
                    oval(.init(x: 51,y: 30,width: 27,height: 52))
                    arc(.init(x: 2,y: -13), .init(x: 45,y: -45), .init(x: 94,y: -12), width: 9)
                }
            case .mischievous:
                oval(.init(x: 2,y: 24,width: 96,height: 67), tint: color.opacity(0.65))
                oval(.init(x: isLeft ? 58 : 20,y: 37,width: 23,height: 45))
                stroke([.init(x: 0,y: isLeft ? 15 : 50), .init(x: 100,y: isLeft ? 50 : 15)], width: 17)
            case .party:
                var star = Path()
                for i in 0..<10 {
                    let angle = Double(i) * .pi / 5 - .pi / 2
                    let radius = i.isMultiple(of: 2) ? 57.0 : 25.0
                    let p = CGPoint(x: 50 + cos(angle)*radius, y: 50 + sin(angle)*radius)
                    if i == 0 { star.move(to:p) } else { star.addLine(to:p) }
                }
                star.closeSubpath(); context.fill(star, with: .color(color))
            case .surprised:
                context.stroke(Path(ellipseIn: .init(x: -8,y: -8,width: 116,height: 116)), with: .color(color), lineWidth: 11)
                oval(.init(x: 38,y: 35,width: 25,height: 30))
                arc(.init(x: 5,y: -30), .init(x: 50,y: -50), .init(x: 95,y: -30), width: 8)
            case .thinking:
                oval(.init(x: 2,y: 20,width: 96,height: 65), tint: color.opacity(0.55))
                oval(.init(x: 55,y: 10,width: 32,height: 49))
                stroke([.init(x: 0,y: isLeft ? 2 : -9), .init(x: 92,y: isLeft ? -10 : 5)], width: 10)
            case .purring:
                arc(.init(x: -5,y: 36), .init(x: 50,y: 70), .init(x: 105,y: 36), width: 14)
                stroke([.init(x: 15,y: 75),.init(x: 7,y: 87)], width: 6)
                stroke([.init(x: 40,y: 80),.init(x: 33,y: 92)], width: 6)
            case .connected:
                oval(.init(x: 0,y: 0,width: 100,height: 100), tint: color.opacity(0.24))
                stroke([.init(x: 16,y: 50),.init(x: 41,y: 72),.init(x: 86,y: 19)], width: 13)
            case .connecting:
                var ring = Path(); ring.addArc(center: .init(x: 50,y: 50), radius: 42, startAngle: .degrees(isLeft ? 35 : 215), endAngle: .degrees(isLeft ? 305 : 485), clockwise: false)
                context.stroke(ring, with: .color(color), style: StrokeStyle(lineWidth: 10, lineCap: .round, dash: [9, 10]))
                oval(.init(x: 40,y: 30,width: 20,height: 40))
            case .protected:
                var eye = Path(); eye.addLines([.init(x: 0,y: 35),.init(x: 50,y: 12),.init(x: 100,y: 35),.init(x: 75,y: 72),.init(x: 25,y: 72)]); eye.closeSubpath()
                context.stroke(eye, with: .color(color), style: StrokeStyle(lineWidth: 10,lineJoin: .round))
                oval(.init(x: 43,y: 26,width: 14,height: 33))
            case .openingEyes:
                let h = max(10, 90 * eyeProgress)
                oval(.init(x: 13,y: 50-h/2,width: 74,height: h))
                oval(.init(x: 47,y: 22,width: 19,height: max(4, 20*eyeProgress)), tint: .white)
                arc(.init(x: 5,y: -20), .init(x: 45,y: -40), .init(x: 95,y: -20), width: 7)
            default: break
            }
        }
    }
}

/// Mouth silhouettes give each state a readable expression even without its accessories.
struct MyaowExpressionMouth: View {
    let state: MyaowCatState
    let color: Color
    let motion: MyaowCatMotion
    var body: some View {
        Canvas { context, size in
            context.scaleBy(x: size.width/100, y: size.height/60)
            func curve(_ x1: Double, _ y1: Double, _ cx: Double, _ cy: Double, _ x2: Double, _ y2: Double, width: Double = 7) {
                var p = Path(); p.move(to:.init(x:x1,y:y1)); p.addQuadCurve(to:.init(x:x2,y:y2),control:.init(x:cx,y:cy))
                context.stroke(p, with:.color(color),style:.init(lineWidth:width,lineCap:.round))
            }
            func oval(_ rect: CGRect, _ tint: Color? = nil) { context.fill(Path(ellipseIn:rect),with:.color(tint ?? color)) }
            func grin(_ width: Double, _ depth: Double, tongue: Bool = false, fang: Bool = false) {
                var p = Path(); p.move(to:.init(x:50-width/2,y:8)); p.addQuadCurve(to:.init(x:50+width/2,y:8),control:.init(x:50,y:18)); p.addQuadCurve(to:.init(x:50-width/2,y:8),control:.init(x:50,y:depth)); p.closeSubpath()
                context.fill(p,with:.color(color))
                if tongue { oval(.init(x:38,y:depth*0.42,width:24,height:11),Color(hex:"FF8B8B")) }
                if fang {
                    var f = Path(); f.addLines([.init(x:62,y:12),.init(x:76,y:12),.init(x:66,y:29)]); f.closeSubpath(); context.fill(f,with:.color(.white))
                }
            }
            switch state {
            case .happy: grin(85, 67)
            case .friendly: curve(8,10,28,39,50,14); curve(50,14,72,39,92,10)
            case .purring: curve(20,12,36,29,50,13,width:5); curve(50,13,66,29,80,12,width:5)
            case .playful: grin(66,54,tongue:true)
            case .curious: oval(.init(x:56,y:10,width:23,height:28))
            case .busy: curve(16,19,50,19,84,19,width:8); curve(80,19,84,24,84,30,width:5)
            case .thinking: curve(46,12,77,1,87,19); curve(58,24,79,24,87,19,width:5)
            case .bored: oval(.init(x:36,y:7,width:30*motion.boredYawnScale,height:38*motion.boredYawnScale))
            case .gossiping: oval(.init(x:50,y:6,width:22,height:39)); curve(14,20,21,25,31,20,width:4)
            case .cool: curve(28,24,67,30,85,3,width:8)
            case .hungry: grin(65,37); oval(.init(x:46,y:18,width:24,height:25+motion.hungryTongueScale*15),Color(hex:"FF7799"))
            case .inLove: curve(19,8,50,53,81,8,width:8)
            case .sad: curve(20,34,50,1,80,34,width:8)
            case .angry: grin(87,38,fang:true); curve(8,8,50,-6,94,8,width:6)
            case .exhausted: curve(15,20,34,6,49,20); curve(49,20,69,34,86,20)
            case .party: grin(95,81,tongue:true)
            case .ninja: curve(25,17,50,23,75,17,width:5)
            case .calm: curve(32,13,50,26,68,13,width:5)
            case .surprised: context.stroke(Path(ellipseIn:.init(x:31,y:1,width:38,height:48)),with:.color(color),lineWidth:7)
            case .neutral: curve(33,16,50,16,67,16,width:6)
            case .connecting: oval(.init(x:26,y:13,width:11,height:11)); oval(.init(x:45,y:13,width:11,height:11)); oval(.init(x:64,y:13,width:11,height:11))
            case .connected: curve(15,4,50,47,85,4,width:8)
            case .sleeping: oval(.init(x:38,y:8,width:24,height:20))
            case .protected: curve(17,15,50,27,83,15,width:9)
            case .openingEyes: grin(47,40)
            case .drunk: curve(10,12,35,42,57,19,width:8); oval(.init(x:51,y:16,width:23,height:29),Color(hex:"FF8998"))
            case .laughing: grin(100,94,tongue:true)
            case .shy: curve(35,12,50,29,65,12,width:5)
            case .crying:
                var p = Path(); p.move(to:.init(x:12,y:39)); p.addQuadCurve(to:.init(x:88,y:39),control:.init(x:50,y:-28)); p.addQuadCurve(to:.init(x:12,y:39),control:.init(x:50,y:25)); p.closeSubpath(); context.fill(p,with:.color(color))
            case .skeptical: curve(28,27,52,11,76,15,width:7)
            case .mischievous: grin(86,48,fang:true)
            }
        }
    }
}
