import Foundation

/// A speaking performance layered over the original expression. Zero audio means zero speech motion.
struct MyaowCatSpeechMotion: Equatable {
    var mouthWidth = 0.0
    var mouthHeight = 0.0
    var smile = 0.0
    var mouthSlant = 0.0
    var headTilt = 0.0
    var nod = 0.0
    var lean = 0.0
    var eyeLift = 1.0
    var gaze = 0.0
    var earLift = 0.0
    var cheekLift = 0.0
    var tongue = false
    var articulation = 0.0
    var jawDrop = 0.0
    var mouthRoundness = 0.0
    var eyeAsymmetry = 0.0
    var browLift = 0.0
    var squint = 0.0

    private struct Performance {
        let width, opening, smile, tilt, nod, pace, gaze: Double
        let tongue: Bool
        init(_ width: Double, _ opening: Double, _ smile: Double, _ tilt: Double,
             _ nod: Double, _ pace: Double, _ gaze: Double, _ tongue: Bool = false) {
            self.width = width; self.opening = opening; self.smile = smile; self.tilt = tilt
            self.nod = nod; self.pace = pace; self.gaze = gaze; self.tongue = tongue
        }
    }
    private static func performance(_ state: MyaowCatState) -> Performance {
        // Keep a distinct rhythm and silhouette for every emotion, including the quieter ones.
        switch state {
        case .happy:      .init(1.28, 0.90, 0.80, 2.8, 1.9, 2.4, 0.5, true)
        case .purring:    .init(0.94, 0.56, 0.65, 1.4, 0.5, 1.0, 0.2)
        case .playful:    .init(1.22, 1.10, 0.70, 4.3, 2.4, 3.3, 0.8, true)
        case .curious:    .init(0.86, 1.05, 0.15, 5.2, 1.2, 1.7, 1.4)
        case .busy:       .init(0.90, 0.70, 0.05, 0.9, 1.1, 3.0, 0.3)
        case .thinking:   .init(0.78, 0.65, 0.05, 3.5, 0.7, 1.2, 1.0)
        case .bored:      .init(1.05, 0.48, -0.20, 1.6, 0.45, 0.65, 0.4)
        case .gossiping:  .init(0.72, 0.90, 0.40, 3.8, 1.6, 2.8, 1.6)
        case .cool:       .init(1.20, 0.58, 0.45, 2.6, 0.8, 1.1, 0.5)
        case .hungry:     .init(1.05, 1.13, 0.20, 2.0, 1.4, 2.2, 0.7, true)
        case .inLove:     .init(1.02, 0.72, 0.95, 3.3, 0.9, 0.9, 0.4, true)
        case .sad:        .init(0.81, 0.52, -0.75, 1.3, 0.6, 0.8, 0.2)
        case .angry:      .init(1.30, 0.98, -0.50, 1.8, 2.1, 3.7, 0.3)
        case .exhausted:  .init(0.92, 0.63, -0.30, 1.9, 0.4, 0.6, 0.2)
        case .party:      .init(1.35, 1.18, 0.85, 4.6, 2.2, 2.7, 0.9, true)
        case .ninja:      .init(0.78, 0.54, 0.02, 0.8, 0.7, 1.8, 0.6)
        case .calm:       .init(1.00, 0.58, 0.50, 1.6, 0.55, 0.75, 0.3)
        case .surprised:  .init(0.80, 1.35, 0.02, 2.5, 1.8, 2.5, 0.7)
        case .friendly:   .init(1.15, 0.85, 0.75, 2.4, 1.1, 1.7, 0.6, true)
        case .neutral:    .init(1.00, 0.80, 0.20, 1.7, 0.9, 1.9, 0.4)
        case .drunk:      .init(1.08, 0.82, 0.30, 5.1, 1.7, 0.72, 1.2, true)
        case .laughing:   .init(1.38, 1.20, 0.90, 3.6, 2.3, 3.1, 0.4, true)
        case .shy:        .init(0.70, 0.51, 0.55, 2.9, 0.65, 1.15, 0.8)
        case .crying:     .init(1.18, 1.22, -0.90, 2.7, 1.6, 2.6, 0.2)
        case .skeptical:  .init(0.84, 0.60, -0.15, 3.1, 0.5, 1.3, 1.3)
        case .mischievous: .init(1.26, 0.81, 0.65, 3.9, 1.3, 2.3, 1.1, true)
        case .connecting: .init(0.92, 0.76, 0.10, 2.1, 0.8, 2.0, 0.8)
        case .connected:  .init(1.12, 0.88, 0.60, 2.2, 1.0, 2.1, 0.5)
        case .sleeping:   .init(0.74, 0.62, 0.12, 1.0, 0.3, 0.55, 0.1)
        case .protected:  .init(0.98, 0.68, 0.35, 1.2, 0.8, 1.5, 0.3)
        case .openingEyes: .init(0.88, 0.92, 0.45, 2.0, 1.3, 1.6, 0.7)
        }
    }
    static func sample(state: MyaowCatState, level: Double, time: Double, enabled: Bool,
                       reducedMotion: Bool = false) -> Self {
        guard enabled, level.isFinite, time.isFinite, level > 0.025 else { return Self() }
        let a = min(1, max(0, level)), p = performance(state)
        // A soft knee keeps quiet voices readable. Articulation is stylized, not inferred phonemes.
        let energy = pow(a, 0.72)
        let syllable = reducedMotion ? 0.5 : 0.5 + 0.5 * sin(time * (8.5 + p.pace))
        let emphasis = energy * energy
        let beat = sin(time * p.pace * 0.85)
        var pose = Self()
        pose.articulation = energy
        pose.mouthWidth = min(1.4, p.width * (0.86 + 0.14 * energy) * (1 - 0.22 * syllable))
        pose.mouthHeight = min(1.65, p.opening * (0.08 + energy * (0.77 + 0.29 * syllable)))
        pose.smile = p.smile
        pose.mouthRoundness = (0.20 + 0.65 * syllable) * energy
        pose.jawDrop = energy * (0.45 + 0.55 * syllable)
        pose.tongue = p.tongue
        guard !reducedMotion else { return pose }
        pose.mouthSlant = (state == .cool || state == .gossiping ? -7 : p.tilt * 0.35) * energy
        // Deliberate, slower head accents; the jaw carries the quicker syllables.
        pose.headTilt = beat * p.tilt * energy * 0.72
        pose.nod = -emphasis * p.nod * (0.35 + 0.65 * max(0, beat))
        pose.lean = sin(time * 0.85) * p.tilt * 0.13 * energy
        pose.eyeLift = 1 + emphasis * 0.10
        pose.eyeAsymmetry = sin(time * 1.3) * 0.045 * energy
        pose.squint = max(0, p.smile) * energy * syllable * 0.12
        pose.browLift = energy * (0.28 + emphasis * 0.72)
        pose.gaze = sin(time * 0.65) * p.gaze * energy * 0.75
        pose.earLift = energy * (0.15 + p.nod * 0.10)
        pose.cheekLift = max(0, p.smile) * energy
        return pose
    }

    /// Mouth dimensions relative to the face, independent of the tiny nose.
    /// Extra optical weight keeps the 68-point floating cat legible.
    func mouthDimensions(faceWidth: Double, avatarSize: Double) -> (width: Double, height: Double) {
        guard mouthHeight > 0, faceWidth.isFinite, avatarSize.isFinite, faceWidth > 0, avatarSize > 0 else { return (0, 0) }
        let optical = avatarSize < 96 ? 1.12 : 1.0
        return (faceWidth * 0.20 * max(0.62, mouthWidth) * optical, faceWidth * 0.125 * mouthHeight * optical)
    }
}
