import SwiftUI

/// Compact feline mark with two closed eyes and a clean, symmetrical smile.
/// No animation clock is needed in the composer toolbar.
struct MyaowMaullidosMark: View {
    var size: CGFloat = 26
    var body: some View {
        Canvas { context, canvas in
            context.scaleBy(x: canvas.width / 100, y: canvas.height / 100)
            let head = MyaowHeadSilhouetteShape().path(in: CGRect(x: 0, y: 0, width: 100, height: 100))
            context.fill(head, with: .color(MyaowColor.orange))
            let ink = MyaowColor.charcoal
            for x: CGFloat in [23, 59] {
                var eye = Path()
                eye.move(to: .init(x: x, y: 57))
                eye.addQuadCurve(to: .init(x: x + 18, y: 57), control: .init(x: x + 9, y: 46))
                context.stroke(eye, with: .color(ink), style: .init(lineWidth: 5, lineCap: .round))
            }
            var mouth = Path(); mouth.move(to: .init(x: 39,y: 72)); mouth.addQuadCurve(to: .init(x: 61,y: 72), control: .init(x: 50,y: 85))
            context.stroke(mouth, with: .color(ink), style: .init(lineWidth: 4,lineCap: .round))
        }.frame(width: size, height: size).accessibilityHidden(true)
    }
}
