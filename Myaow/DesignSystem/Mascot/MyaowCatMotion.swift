import Foundation

/// A sampled pose has no timers or retained callbacks. The view owns the animation clock.
struct MyaowCatMotion: Equatable {
    var blinkScaleY: CGFloat = 1
    var breathingScale: CGFloat = 1
    var earFlex: CGFloat = 0
    var headTiltAngle: Double = 0
    var bounceOffset: CGFloat = 0
    var scaleX: CGFloat = 1
    var scaleY: CGFloat = 1
    var gazeOffset: CGFloat = 0
    var connectingRotation: Double = 0
    var radarWaveScale: CGFloat = 0.8
    var radarWaveOpacity: Double = 0.8
    var beaconPulseScale: CGFloat = 1
    var beaconPulseOpacity: Double = 0.8
    var zzzOffset1: CGFloat = 0
    var zzzOpacity1: Double = 0
    var zzzOffset2: CGFloat = 0
    var zzzOpacity2: Double = 0
    var shieldGlowOpacity: Double = 0.4
    var isPurringActive = false
    var purrVibrationOffset: CGFloat = 0
    var purrHeartOffset1: CGFloat = 0
    var purrHeartOpacity1: Double = 0
    var angrySteamOffset: CGFloat = 0
    var angrySteamOpacity: Double = 0
    var angryTremor: CGFloat = 0
    var tearDropOffset: CGFloat = 0
    var tearDropOpacity: Double = 0
    var thoughtDotScale1: CGFloat = 0.5
    var thoughtDotScale2: CGFloat = 0.5
    var thoughtDotScale3: CGFloat = 0.5
    var ideaSparkleOpacity: Double = 0
    var ideaSparkleScale: CGFloat = 0.8
    var drunkenSway: Double = 0
    var drunkenHiccup: CGFloat = 0
    var starsRotation: Double = 0
    var dizzyPupilOffset: CGFloat = 0
    var curiousWobble: Double = 0
    var questionMarkOffset: CGFloat = 0
    var questionMarkOpacity: Double = 0
    var playfulHop: CGFloat = 0
    var ninjaGlow: Double = 0.5
    var busyGlassesGlow: Double = 0.6
    var busyGearRotation: Double = 0
    var surpriseGaspScale: CGFloat = 1
    var zenWaveOpacity: Double = 0.3
    var sweatDropOffset: CGFloat = 0
    var sweatDropOpacity: Double = 0.8
    var boredYawnScale: CGFloat = 0.2
    var boredBubbleScale: CGFloat = 0.1
    var boredBubbleOffset: CGFloat = 0
    var boredBubbleOpacity: Double = 0
    var gossipPupilShift: CGFloat = 0
    var gossipPeekingOffset: CGFloat = 0
    var gossipMagnifierScale: CGFloat = 1
    var coolGleamOffset: CGFloat = -22
    var coolGleamOpacity: Double = 0
    var coolSwaggerSway: Double = -2.5
    var hungryTongueOffset: CGFloat = 0
    var hungryTongueScale: CGFloat = 0.4
    var hungryFishFloatOffset: CGFloat = -2
    var heartEyesBeatScale: CGFloat = 1
    var inLoveHeartsOffset: CGFloat = 0
    var inLoveHeartsOpacity: Double = 0

    static func sample(state: MyaowCatState, time: Double, phase: Double,
                       size: CGFloat, animating: Bool, tapAge: Double? = nil) -> Self {
        var pose = Self()
        // Static poses also retain the accessories that identify each emotion.
        let t = animating ? max(0, time) + phase : 1.1
        let unit = max(0, size) / 80
        let energy = size < 64 ? 0.55 : 1.0
        let breathPeriod = [.sleeping, .calm, .sad, .bored, .exhausted].contains(state) ? 6.4 : 4.8
        if animating {
            pose.breathingScale = 1 + wave(t, period: breathPeriod) * 0.022 * energy
            let ear = pulse(t, period: 9.7, start: 6.1, duration: 0.65)
            pose.earFlex = ear * energy
            if ![.sleeping, .happy, .purring, .angry, .drunk, .laughing, .crying, .calm, .cool, .inLove, .bored, .openingEyes].contains(state) {
                let cycle = 5.6 + phase * 0.13
                let local = t.truncatingRemainder(dividingBy: cycle)
                let first = blink(local - 0.7)
                let second = Int(t / cycle) % 3 == 1 ? blink(local - 1.03) : 1
                pose.blinkScaleY = min(first, second)
            }
        }

        switch state {
        case .connecting:
            pose.connectingRotation = t.truncatingRemainder(dividingBy: 3.6) / 3.6 * 360
            let p = progress(t, period: 2.8)
            pose.radarWaveScale = 0.88 + p * 0.4
            pose.radarWaveOpacity = envelope(p) * 0.6
        case .connected:
            let p = progress(t, period: 3.6)
            pose.beaconPulseScale = 1 + p * 0.6
            pose.beaconPulseOpacity = envelope(p) * 0.45
        case .sleeping:
            let p = progress(t, period: 3.6)
            let q = progress(t + 1.8, period: 3.6)
            pose.zzzOffset1 = -24 * unit * p
            pose.zzzOffset2 = -32 * unit * q
            pose.zzzOpacity1 = envelope(p) * 0.85
            pose.zzzOpacity2 = envelope(q) * 0.8
        case .purring:
            let p = progress(t, period: 3.8)
            pose.purrHeartOffset1 = -24 * unit * p
            pose.purrHeartOpacity1 = envelope(p) * 0.85
            if animating { pose.purrVibrationOffset = sin(t * 9) * 0.3 * unit * energy * wave(t, period: 4) }
        case .protected:
            pose.shieldGlowOpacity = 0.4 + wave(t, period: 4.4) * 0.45
        case .angry:
            let p = progress(t, period: 4.2)
            pose.angrySteamOffset = -18 * unit * p
            pose.angrySteamOpacity = envelope(p) * 0.8
            if animating { pose.angryTremor = sin(t * 24) * 0.8 * unit * energy * pulse(t, period: 4.2, start: 0.6, duration: 0.7) }
        case .sad:
            let p = progress(t, period: 4.6)
            pose.tearDropOffset = 18 * unit * p * p
            pose.tearDropOpacity = envelope(p) * 0.8
        case .thinking:
            pose.thoughtDotScale1 = 0.65 + wave(t, period: 2) * 0.45
            pose.thoughtDotScale2 = 0.65 + wave(t - 0.2, period: 2) * 0.45
            pose.thoughtDotScale3 = 0.65 + wave(t - 0.4, period: 2) * 0.45
            let idea = pulse(t, period: 6, start: 2.2, duration: 2.8)
            pose.ideaSparkleOpacity = 0.3 + idea * 0.65
            pose.ideaSparkleScale = 0.9 + idea * 0.15
        case .drunk:
            pose.starsRotation = t.truncatingRemainder(dividingBy: 12) / 12 * 360
            if animating {
                pose.drunkenSway = sin(t * .pi / 1.8) * 5 * energy
                pose.drunkenHiccup = -3 * unit * energy * pulse(t, period: 4.5, start: 2, duration: 0.65)
                pose.dizzyPupilOffset = sin(t * .pi / 2.3) * 1.4 * unit
            }
        case .curious:
            let peek = pulse(t, period: 5.8, start: 1.2, duration: 3.4)
            pose.curiousWobble = animating ? peek * 7 * energy : 4
            pose.questionMarkOffset = -4 * unit * peek
            pose.questionMarkOpacity = 0.5 + peek * 0.4
            if animating { pose.gazeOffset = peek * 0.7 * unit }
        case .playful:
            if animating {
                // Anticipation, flight, landing, then a long rest instead of an endless pogo.
                let p = t.truncatingRemainder(dividingBy: 4.6)
                let crouch = pulse(p, period: 4.6, start: 0.6, duration: 0.28)
                let flight = pulse(p, period: 4.6, start: 0.88, duration: 0.62)
                let landing = pulse(p, period: 4.6, start: 1.5, duration: 0.3)
                pose.playfulHop = (crouch * 1.2 - flight * 7 + landing * 0.8) * unit * energy
                pose.scaleX = 1 + (crouch * 0.045 - flight * 0.02 + landing * 0.035) * energy
                pose.scaleY = 1 + (-crouch * 0.06 + flight * 0.045 - landing * 0.045) * energy
            }
        case .ninja:
            pose.ninjaGlow = 0.55 + wave(t, period: 5) * 0.35
        case .busy:
            pose.busyGearRotation = t.truncatingRemainder(dividingBy: 10) / 10 * 360
            pose.busyGlassesGlow = 0.65 + wave(t, period: 3.6) * 0.3
        case .surprised:
            pose.surpriseGaspScale = animating ? 1 + pulse(t, period: 6, start: 0.5, duration: 1.2) * 0.12 : 1.06
        case .calm:
            pose.zenWaveOpacity = 0.3 + wave(t, period: 6.4) * 0.35
        case .exhausted:
            let p = progress(t, period: 4.5)
            pose.sweatDropOffset = 10 * unit * p * p
            pose.sweatDropOpacity = 0.2 + envelope(p) * 0.6
        case .bored:
            pose.boredYawnScale = 0.2 + pulse(t, period: 7.5, start: 1.6, duration: 3.2) * 0.8
            let p = progress(t, period: 5.2)
            pose.boredBubbleScale = 0.3 + p * 0.8
            pose.boredBubbleOffset = -22 * unit * p
            pose.boredBubbleOpacity = envelope(p) * 0.7
        case .gossiping:
            let peek = pulse(t, period: 5.6, start: 1, duration: 3.2)
            pose.gossipPeekingOffset = -2.5 * unit * peek * energy
            pose.gossipMagnifierScale = 1 + peek * 0.06
            pose.gossipPupilShift = animating ? sin(t * .pi / 2.8) * 2 * unit : 0
        case .cool:
            let p = progress(t, period: 6)
            let gleam = min(1, p / 0.23)
            pose.coolGleamOffset = (-22 + 44 * gleam) * unit
            pose.coolGleamOpacity = p < 0.23 ? envelope(gleam) * 0.9 : 0
            pose.coolSwaggerSway = animating ? -1.5 + sin(t * .pi / 3.2) * 1.8 * energy : -1.5
        case .hungry:
            let lick = pulse(t, period: 4.6, start: 1.5, duration: 1)
            pose.hungryTongueOffset = 3.5 * unit * lick
            pose.hungryTongueScale = 0.4 + lick * 0.6
            pose.hungryFishFloatOffset = (-2 + 4 * wave(t, period: 3.8)) * unit
        case .inLove:
            let beat = pulse(t, period: 3.2, start: 0.3, duration: 0.3) + pulse(t, period: 3.2, start: 0.75, duration: 0.4) * 0.65
            pose.heartEyesBeatScale = 1 + beat * 0.16 * energy
            let p = progress(t, period: 3.8)
            pose.inLoveHeartsOffset = -22 * unit * p
            pose.inLoveHeartsOpacity = envelope(p) * 0.85
        case .party:
            pose.starsRotation = t.truncatingRemainder(dividingBy: 16) / 16 * 360
            if animating {
                let cheer = pulse(t, period: 5.4, start: 1, duration: 1.5)
                pose.bounceOffset = -3.5 * unit * cheer * energy
                pose.headTiltAngle = sin(t * 2.2) * 3 * cheer * energy
            }
        case .laughing:
            if animating {
                let laugh = pulse(t, period: 4.8, start: 0.7, duration: 2.2)
                pose.bounceOffset = -abs(sin(t * 9)) * 2.2 * unit * laugh * energy
                pose.scaleY = 1 - laugh * 0.045 * energy
                pose.headTiltAngle = -4 * laugh * energy
            }
        case .shy:
            if animating {
                let hide = pulse(t, period: 6.2, start: 1.2, duration: 3)
                pose.headTiltAngle = 3 * hide * energy
                pose.bounceOffset = 1.8 * hide * unit
                pose.gazeOffset = -0.9 * unit * hide
            }
        case .crying:
            let p = progress(t, period: 2.8)
            pose.tearDropOffset = 16 * unit * p
            pose.tearDropOpacity = envelope(p)
            if animating { pose.bounceOffset = -abs(sin(t * 5)) * unit * energy }
        case .skeptical:
            if animating {
                let judge = pulse(t, period: 6.8, start: 1.4, duration: 3.5)
                pose.headTiltAngle = -4 * judge * energy
                pose.gazeOffset = 1.2 * unit * judge
            }
        case .mischievous:
            if animating {
                let plot = pulse(t, period: 5.8, start: 0.8, duration: 2.8)
                pose.headTiltAngle = 3.5 * plot * energy
                pose.gazeOffset = sin(t * 1.7) * 1.1 * unit * plot
                pose.earFlex += plot * 0.6
            }
        case .happy:
            if animating { pose.bounceOffset = -1.3 * unit * energy * pulse(t, period: 5.6, start: 1, duration: 1.4) }
        case .friendly:
            if animating { pose.headTiltAngle = 2 * energy * pulse(t, period: 7.4, start: 1.4, duration: 2.8) }
        case .openingEyes:
            if animating { pose.earFlex += pulse(t, period: 6.4, start: 1, duration: 1.8) * 0.5 }
        case .neutral:
            break
        }

        if animating, let age = tapAge, age >= 0, age < 1.2 {
            // One bounded response; repeated taps restart it without spawning extra work.
            let press = pulse(age, period: 10, start: 0, duration: 0.18)
            let lift = pulse(age, period: 10, start: 0.12, duration: 0.45)
            let settle = pulse(age, period: 10, start: 0.57, duration: 0.3)
            pose.scaleX *= 1 + press * 0.065 - lift * 0.035 + settle * 0.02
            pose.scaleY *= 1 - press * 0.08 + lift * 0.07 - settle * 0.025
            pose.bounceOffset = (press - lift * 5) * unit
            pose.headTiltAngle = -5 * pulse(age, period: 10, start: 0.1, duration: 0.85)
            pose.earFlex += pulse(age, period: 10, start: 0.2, duration: 0.5)
            pose.isPurringActive = true
            pose.purrHeartOffset1 = -26 * unit * age / 1.2
            pose.purrHeartOpacity1 = envelope(age / 1.2) * 0.9
        }
        return pose
    }

    private static func wave(_ t: Double, period: Double) -> Double {
        (1 - cos(t * 2 * .pi / period)) / 2
    }
    private static func progress(_ t: Double, period: Double) -> Double {
        t.truncatingRemainder(dividingBy: period) / period
    }
    private static func pulse(_ t: Double, period: Double, start: Double, duration: Double) -> Double {
        let p = (t.truncatingRemainder(dividingBy: period) - start) / duration
        guard p > 0, p < 1 else { return 0 }
        return pow(sin(p * .pi), 2)
    }
    /// Both ends are transparent, so particles never teleport while visible.
    private static func envelope(_ p: Double) -> Double {
        let enter = min(1, max(0, p / 0.18))
        let leave = min(1, max(0, (1 - p) / 0.32))
        return smooth(enter) * smooth(leave)
    }
    private static func smooth(_ p: Double) -> Double { p * p * (3 - 2 * p) }
    private static func blink(_ t: Double) -> Double {
        guard t >= 0, t < 0.255 else { return 1 }
        if t < 0.08 { return 1 - smooth(t / 0.08) * 0.94 }
        if t < 0.105 { return 0.06 }
        return 0.06 + smooth((t - 0.105) / 0.15) * 0.94
    }
}

extension MyaowCatMotion {
    /// Keep emotional props and blinks, but let the speech performance lead the head.
    func whileSpeaking(_ level: Double) -> Self {
        guard level.isFinite, level > 0.025 else { return self }
        var pose = self
        let restraint = 1 - min(1, level * 3) * 0.75
        pose.playfulHop *= restraint; pose.bounceOffset *= restraint
        pose.drunkenHiccup *= restraint; pose.drunkenSway *= restraint
        pose.gossipPeekingOffset *= restraint; pose.angryTremor *= restraint
        pose.curiousWobble *= restraint; pose.headTiltAngle *= restraint
        return pose
    }
}
