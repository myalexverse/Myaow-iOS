import Foundation
@main struct CatSpeechChecks {
    static func main() {
        precondition(MyaowCatState.allCases.count == 31, "The released expression catalog has 31 states")
        var signatures = Set<String>()
        var samples = 0
        for state in MyaowCatState.allCases {
            precondition(MyaowCatSpeechMotion.sample(state: state, level: 0, time: 10, enabled: true) == .init())
            precondition(MyaowCatSpeechMotion.sample(state: state, level: 1, time: 10, enabled: false) == .init())
            precondition(MyaowCatSpeechMotion.sample(state: state, level: .nan, time: 10, enabled: true) == .init())
            let full = MyaowCatSpeechMotion.sample(state: state, level: 1, time: 0.7, enabled: true)
            let quiet = MyaowCatSpeechMotion.sample(state: state, level: 0.15, time: 0.7, enabled: true)
            precondition(full.mouthHeight > quiet.mouthHeight, "Louder speech must open the jaw more")
            let reduced = MyaowCatSpeechMotion.sample(state: state, level: 0.7, time: 0.7, enabled: true, reducedMotion: true)
            precondition(reduced.mouthHeight > 0 && reduced.headTilt == 0 && reduced.nod == 0 && reduced.gaze == 0 && reduced.eyeAsymmetry == 0)
            precondition(reduced == MyaowCatSpeechMotion.sample(state: state, level: 0.7, time: 20, enabled: true, reducedMotion: true), "Reduced motion only follows amplitude")
            for size in [44.0, 68, 96, 150, 190, 240] {
                let dimensions = full.mouthDimensions(faceWidth: size * 0.72, avatarSize: size)
                precondition(dimensions.width > size * 0.08 && dimensions.width < size * 0.24)
                precondition(dimensions.height > 0 && dimensions.height < size * 0.18)
                if size == 68 { precondition(dimensions.width >= 6.5, "Floating cat mouth must stay readable") }
            }
            signatures.insert(String(describing: full))
            for step in 0...100 {
                let level = Double(step) / 100
                for tick in 0...60 {
                    let pose = MyaowCatSpeechMotion.sample(state: state, level: level, time: Double(tick)/10, enabled: true)
                    precondition((0...1.8).contains(pose.mouthHeight) && (0...1.4).contains(pose.mouthWidth))
                    precondition(abs(pose.headTilt) <= 5.3 && abs(pose.nod) <= 2.5)
                    precondition((0.9...1.12).contains(pose.eyeLift))
                    precondition((0...0.85).contains(pose.mouthRoundness) && abs(pose.eyeAsymmetry) <= 0.045)
                    for field in Mirror(reflecting: pose).children { if let value = field.value as? Double { precondition(value.isFinite) } }
                    samples += 1
                }
            }
        }
        precondition(signatures.count == MyaowCatState.allCases.count, "Every emotion must have a distinct speaking performance")
        precondition(MyaowCatSpeechMotion().mouthDimensions(faceWidth: .nan, avatarSize: 68).width == 0)
        print("PASS: \(samples) speech poses; \(signatures.count) distinct emotion performances, silence, amplitude response, reduced motion, optical size compensation, finite values and bounded gestures.")
    }
}
