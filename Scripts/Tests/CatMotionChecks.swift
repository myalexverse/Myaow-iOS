import Foundation

@main
struct CatMotionChecks {
    static func main() {
        var samples = 0
        for state in MyaowCatState.allCases {
            for size: CGFloat in [16, 32, 54, 80, 160] {
                let still = MyaowCatMotion.sample(state: state, time: 0, phase: 0, size: size, animating: false)
                let later = MyaowCatMotion.sample(state: state, time: 99, phase: 7, size: size, animating: false, tapAge: 0.3)
                precondition(still == later, "Paused/reduced motion must remain static: \(state)")
                precondition(still.blinkScaleY == 1 && still.breathingScale == 1)
                for tick in 0...1200 {
                    let t = Double(tick) / 60
                    let pose = MyaowCatMotion.sample(state: state, time: t, phase: 0.37, size: size, animating: true, tapAge: t)
                    precondition((0.80...1.20).contains(pose.scaleX * pose.breathingScale))
                    precondition((0.80...1.20).contains(pose.scaleY * pose.breathingScale))
                    precondition((0.059...1.001).contains(pose.blinkScaleY))
                    for field in Mirror(reflecting: pose).children {
                        if let value = field.value as? Double {
                            precondition(value.isFinite, "Non-finite \(field.label ?? "pose")")
                            if field.label?.contains("Opacity") == true {
                                precondition((0...1).contains(value), "Opacity outside bounds")
                            }
                        }
                    }
                    let speaking = pose.whileSpeaking(0.8)
                    precondition(abs(speaking.playfulHop) <= abs(pose.playfulHop))
                    precondition(abs(speaking.drunkenSway) <= abs(pose.drunkenSway))
                    precondition(speaking.blinkScaleY == pose.blinkScaleY, "Speech must preserve independent blinks")
                    precondition(pose.whileSpeaking(0) == pose && pose.whileSpeaking(.nan) == pose)
                    samples += 1
                }
                let afterTap = MyaowCatMotion.sample(state: state, time: 8, phase: 1, size: size, animating: true, tapAge: 1.21)
                let idle = MyaowCatMotion.sample(state: state, time: 8, phase: 1, size: size, animating: true)
                precondition(afterTap == idle, "Touch must fully settle without lingering state")
            }
        }
        let rest = MyaowCatMotion.sample(state: .playful, time: 3, phase: 0, size: 80, animating: true)
        let crouch = MyaowCatMotion.sample(state: .playful, time: 0.74, phase: 0, size: 80, animating: true)
        let flight = MyaowCatMotion.sample(state: .playful, time: 1.19, phase: 0, size: 80, animating: true)
        precondition(rest.playfulHop == 0 && rest.scaleX == 1 && rest.scaleY == 1)
        precondition(crouch.playfulHop > 0 && crouch.scaleY < 1)
        precondition(flight.playfulHop < -6 && flight.scaleY > 1)
        let before = MyaowCatMotion.sample(state: .sleeping, time: 3.59999, phase: 0, size: 80, animating: true)
        let after = MyaowCatMotion.sample(state: .sleeping, time: 3.60001, phase: 0, size: 80, animating: true)
        precondition(before.zzzOpacity1 < 0.001 && after.zzzOpacity1 < 0.001, "Particles must be invisible at their loop boundary")
        let a = MyaowCatMotion.sample(state: .neutral, time: 0.78, phase: 0, size: 80, animating: true)
        let b = MyaowCatMotion.sample(state: .neutral, time: 0.78, phase: 3, size: 80, animating: true)
        precondition(a.blinkScaleY < 0.1 && b.blinkScaleY == 1, "Avatars must not blink in sync")
        print("PASS: \(samples) poses across \(MyaowCatState.allCases.count) states and 5 sizes; static mode, bounds, settling, anticipation, particle continuity and independent blinking.")
    }
}
