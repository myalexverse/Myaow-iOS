//
//  MyaowCatView.swift
//  Myaow
//
//  Created for Myaow - "Tecnología que se siente cercana"
//

import SwiftUI

/// Vista vectorial nativa de la mascota Myaow con animaciones orgánicas de alta fidelidad,
/// expresiones faciales para sus emociones y estados, y reactividad táctil.
public struct MyaowCatView: View {
    public var state: MyaowCatState
    public var style: MyaowCatStyle
    public var size: CGFloat
    public var eyeProgress: Double // 0.0 (cerrados) a 1.0 (abiertos)
    public var isInteractive: Bool
    public var speakingLevel: Double
    public var showsCrossEyes: Bool
    public var allowsBackgroundSpeech: Bool
    
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isVisible = false
    @State private var isInViewport = true
    @State private var lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
    @State private var startedAt = ProcessInfo.processInfo.systemUptime
    @State private var phase = Double.random(in: 0...8)
    @State private var tappedAt: Double?

    private var isAnimating: Bool {
        isVisible && isInViewport && (scenePhase == .active || allowsBackgroundSpeech) && !reduceMotion && !lowPower && size >= 30
    }

    public init(
        state: MyaowCatState = .neutral,
        style: MyaowCatStyle = .orangeOnDark,
        size: CGFloat = 80,
        eyeProgress: Double = 1.0,
        isInteractive: Bool = true,
        speakingLevel: Double = 0,
        allowsBackgroundSpeech: Bool = false,
        showsCrossEyes: Bool = false
    ) {
        self.showsCrossEyes = showsCrossEyes
        self.state = state
        self.style = style
        self.size = size
        self.eyeProgress = eyeProgress
        self.isInteractive = isInteractive
        self.speakingLevel = speakingLevel
        self.allowsBackgroundSpeech = allowsBackgroundSpeech
    }
    
    public var body: some View {
        TimelineView(.animation(minimumInterval: size < 96 ? 1.0 / 30 : 1.0 / 60, paused: !isAnimating)) { _ in
            let now = ProcessInfo.processInfo.systemUptime
            let pose = MyaowCatMotion.sample(state: state, time: now - startedAt,
                                             phase: phase, size: size, animating: isAnimating,
                                             tapAge: tappedAt.map { now - $0 }).whileSpeaking(speakingLevel)
            let speech = MyaowCatSpeechMotion.sample(state: state, level: speakingLevel,
                time: now - startedAt + phase, enabled: isVisible && (scenePhase == .active || allowsBackgroundSpeech), reducedMotion: reduceMotion || lowPower)
            ZStack {
                MyaowCatArtwork(state: state, style: style, size: size, eyeProgress: eyeProgress, motion: pose, speech: speech, showsCrossEyes: showsCrossEyes)
                    .animation(.linear(duration: 0.075), value: speakingLevel)
                    .id(state)
                    .transition(.opacity)
            }
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: state)
        }
        .frame(width: size, height: size)
        .contentShape(Circle())
        .allowsHitTesting(isInteractive)
        .onTapGesture { reactToTouch() }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(state.displayName)
        .accessibilityAddTraits(isInteractive ? .isButton : .isImage)
        .accessibilityHidden(!isInteractive)
        .onAppear { isVisible = true }
        .onDisappear {
            isVisible = false
            tappedAt = nil
        }
        .onScrollVisibilityChange(threshold: 0.1) { isInViewport = $0 }
        .onChange(of: state) { _, _ in tappedAt = nil }
        .onChange(of: isAnimating) { _, active in
            if active { startedAt = ProcessInfo.processInfo.systemUptime }
            else { tappedAt = nil }
        }
        .onReceive(NotificationCenter.default.publisher(for: .NSProcessInfoPowerStateDidChange)) { _ in
            lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
        }
    }

    private func reactToTouch() {
        guard isInteractive else { return }
        UIImpactFeedbackGenerator(style: .soft).impactOccurred(intensity: 0.65)
        guard isAnimating else { return }
        let now = ProcessInfo.processInfo.systemUptime
        // Avoid a stuttering restart if several taps arrive within the same reaction.
        guard tappedAt.map({ now - $0 >= 0.32 }) ?? true else { return }
        tappedAt = now
    }
}

/// Existing vector artwork; animation only supplies a pose and never changes its identity.
private struct MyaowCatArtwork: View {
    let state: MyaowCatState
    let style: MyaowCatStyle
    let size: CGFloat
    let eyeProgress: Double
    let motion: MyaowCatMotion
    var speech = MyaowCatSpeechMotion()
    var showsCrossEyes = false

    var body: some View {
        ZStack {
            backgroundView
            backgroundEffectsView
            ZStack {
                catVectorFace
                    .frame(width: size * 0.72, height: size * 0.72)
                // Glasses, cheeks and headbands follow the same head transform.
                foregroundOverlayView
            }
            .frame(width: size, height: size)
            .scaleEffect(x: motion.breathingScale * motion.scaleX,
                         y: motion.breathingScale * motion.scaleY, anchor: .bottom)
            .rotationEffect(.degrees(resolvedHeadTilt + motion.headTiltAngle + speech.headTilt), anchor: .bottom)
            .offset(x: motion.angryTremor + motion.purrVibrationOffset + speech.lean * size / 80,
                    y: motion.bounceOffset + motion.drunkenHiccup + motion.playfulHop + motion.gossipPeekingOffset + speech.nod * size / 80)
        }
        .frame(width: size, height: size)
    }

    private var resolvedHeadTilt: Double {
        switch state {
        case .curious:
            return motion.curiousWobble
        case .playful:
            return -5.0
        case .thinking:
            return 8.0
        case .sad:
            return -4.0
        case .drunk:
            return motion.drunkenSway
        case .friendly:
            return -2.5
        case .shy: return 7
        case .skeptical: return -6
        case .mischievous: return -3
        case .crying: return -2
        case .laughing: return -4
        case .exhausted:
            return 3.0
        case .bored:
            return -3.5
        case .gossiping:
            return 4.0
        case .cool:
            return motion.coolSwaggerSway
        case .hungry:
            return 2.5
        case .inLove:
            return 3.0
        default:
            return 0
        }
    }
    
    // MARK: - Background Effects
    @ViewBuilder
    private var backgroundEffectsView: some View {
        switch state {
        case .connecting:
            ZStack {
                Circle()
                    .stroke(
                        AngularGradient(
                            gradient: Gradient(colors: [MyaowColor.orange.opacity(0.8), MyaowColor.orange.opacity(0.1), Color.clear]),
                            center: .center
                        ),
                        lineWidth: 2
                    )
                    .frame(width: size * 0.94, height: size * 0.94)
                    .rotationEffect(Angle(degrees: motion.connectingRotation))
                
                Circle()
                    .stroke(MyaowColor.orange.opacity(motion.radarWaveOpacity), lineWidth: 1.5)
                    .frame(width: size * 0.94, height: size * 0.94)
                    .scaleEffect(motion.radarWaveScale)
            }
            
        case .calm:
            Circle()
                .stroke(Color(hex: "#8E8E93").opacity(motion.zenWaveOpacity), lineWidth: 1.5)
                .frame(width: size * 0.92, height: size * 0.92)
                .scaleEffect(1.05)
            
        case .party, .drunk:
            ZStack {
                ForEach(0..<4) { i in
                    let angle = Double(i) * (.pi / 2)
                    Text(i % 2 == 0 ? "💫" : "✨")
                        .font(.system(size: size * 0.16))
                        .offset(
                            x: (size * 0.46) * cos(angle),
                            y: (size * 0.38) * sin(angle)
                        )
                }
            }
            .rotationEffect(Angle(degrees: motion.starsRotation))
            
        case .inLove:
            // Resplandor cálido de amor
            Circle()
                .fill(RadialGradient(colors: [Color(hex: "#FF2D55").opacity(0.22), Color.clear], center: .center, startRadius: 10, endRadius: size * 0.48))
                .frame(width: size * 0.96, height: size * 0.96)
            
        default:
            EmptyView()
        }
    }
    
    // MARK: - Foreground Overlays
    @ViewBuilder
    private var foregroundOverlayView: some View {
        switch state {
        case .connected:
            VStack {
                Spacer()
                HStack {
                    Spacer()
                    ZStack {
                        Circle()
                            .fill(MyaowColor.statusGreen.opacity(motion.beaconPulseOpacity))
                            .frame(width: size * 0.22, height: size * 0.22)
                            .scaleEffect(motion.beaconPulseScale)
                        
                        Circle()
                            .fill(MyaowColor.statusGreen)
                            .frame(width: size * 0.20, height: size * 0.20)
                            .overlay(Circle().stroke(MyaowColor.charcoal, lineWidth: 2))
                            .shadow(color: MyaowColor.statusGreen.opacity(0.6), radius: 4)
                    }
                    .padding(size * 0.02)
                }
            }
            
        case .bored:
            // 🥱 Burbujita de pereza que flota y patita sosteniendo la mejilla
            ZStack {
                // Patita sosteniendo la barbilla/mejilla
                Circle()
                    .fill(faceFeatureColor)
                    .frame(width: size * 0.14, height: size * 0.10)
                    .offset(x: -size * 0.22, y: size * 0.20)
                
                // Burbuja transparente flotando
                Circle()
                    .stroke(Color(hex: "#81D4FA").opacity(motion.boredBubbleOpacity), lineWidth: 1.5)
                    .background(Circle().fill(Color(hex: "#E1F5FE").opacity(motion.boredBubbleOpacity * 0.3)))
                    .frame(width: size * 0.18, height: size * 0.18)
                    .scaleEffect(motion.boredBubbleScale)
                    .offset(x: size * 0.18, y: size * 0.05 + motion.boredBubbleOffset)
            }
            
        case .gossiping:
            // 👀 Lupa / Prismáticos curiosos
            ZStack {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: size * 0.22, weight: .bold))
                    .foregroundColor(MyaowColor.orange)
                    .scaleEffect(motion.gossipMagnifierScale)
                    .offset(x: size * 0.32, y: size * 0.18)
                    .shadow(color: MyaowColor.orange.opacity(0.6), radius: 4)
            }
            
        case .cool:
            // 🕶️ Gafas de sol negras obsidian con destello brillante
            ZStack {
                CoolSunglassesView(size: size, faceFeatureColor: faceFeatureColor)
                
                // Destello que viaja por la lente
                Image(systemName: "sparkle")
                    .font(.system(size: size * 0.15, weight: .bold))
                    .foregroundColor(.white)
                    .offset(x: motion.coolGleamOffset, y: -size * 0.05)
                    .opacity(motion.coolGleamOpacity)
            }
            
        case .hungry:
            // 🤤 Pescadito dorado flotante
            ZStack {
                Image(systemName: "fish.fill")
                    .font(.system(size: size * 0.20))
                    .foregroundColor(Color(hex: "#FFD600"))
                    .offset(x: size * 0.30, y: -size * 0.28 + motion.hungryFishFloatOffset)
                    .shadow(color: Color(hex: "#FFD600").opacity(0.7), radius: 5)
            }
            
        case .inLove:
            // 🥰 Mejillas sonrojadas y lluvia de corazones
            ZStack {
                HStack(spacing: size * 0.36) {
                    Circle().fill(Color(hex: "#FF2D55").opacity(0.75)).frame(width: size * 0.13, height: size * 0.09)
                    Circle().fill(Color(hex: "#FF2D55").opacity(0.75)).frame(width: size * 0.13, height: size * 0.09)
                }
                .offset(y: size * 0.08)
                
                Text("💖")
                    .font(.system(size: size * 0.18))
                    .offset(x: size * 0.30, y: -size * 0.22 + motion.inLoveHeartsOffset)
                    .opacity(motion.inLoveHeartsOpacity)
                
                Text("💕")
                    .font(.system(size: size * 0.15))
                    .offset(x: -size * 0.32, y: -size * 0.18 + motion.inLoveHeartsOffset)
                    .opacity(motion.inLoveHeartsOpacity)
            }
            
        case .purring:
            ZStack {
                HStack(spacing: size * 0.36) {
                    Circle().fill(Color(hex: "#FF4081").opacity(0.75)).frame(width: size * 0.12, height: size * 0.08)
                    Circle().fill(Color(hex: "#FF4081").opacity(0.75)).frame(width: size * 0.12, height: size * 0.08)
                }
                .offset(y: size * 0.08)
                
                Text("💖")
                    .font(.system(size: size * 0.18))
                    .offset(x: size * 0.30, y: -size * 0.22 + motion.purrHeartOffset1)
                    .opacity(motion.purrHeartOpacity1)
            }
            
        case .drunk, .shy:
            HStack(spacing: size * 0.36) {
                Circle().fill(Color(hex: "#FF5252").opacity(0.65)).frame(width: size * 0.12, height: size * 0.08)
                Circle().fill(Color(hex: "#FF5252").opacity(0.65)).frame(width: size * 0.12, height: size * 0.08)
            }
            .offset(y: size * 0.10)
            
        case .busy:
            VStack {
                Spacer()
                HStack {
                    Spacer()
                    ZStack {
                        Circle().fill(MyaowColor.charcoal).frame(width: size * 0.26, height: size * 0.26)
                        Image(systemName: "gearshape.fill")
                            .font(.system(size: size * 0.20))
                            .foregroundColor(MyaowColor.orange)
                            .rotationEffect(Angle(degrees: motion.busyGearRotation))
                    }
                    .padding(size * 0.02)
                }
            }
            
        case .sleeping:
            ZStack {
                Text("z")
                    .font(.system(size: size * 0.18, weight: .bold, design: .rounded))
                    .foregroundColor(faceFeatureColor.opacity(0.8))
                    .offset(x: size * 0.28, y: -size * 0.20 + motion.zzzOffset1)
                    .opacity(motion.zzzOpacity1)
                
                Text("Z")
                    .font(.system(size: size * 0.26, weight: .black, design: .rounded))
                    .foregroundColor(faceFeatureColor.opacity(0.9))
                    .offset(x: size * 0.38, y: -size * 0.30 + motion.zzzOffset2)
                    .opacity(motion.zzzOpacity2)
            }
            
        case .protected:
            VStack {
                Spacer()
                HStack {
                    Spacer()
                    ZStack {
                        Circle().fill(MyaowColor.charcoal).frame(width: size * 0.30, height: size * 0.30)
                        Image(systemName: "checkmark.shield.fill")
                            .font(.system(size: size * 0.26))
                            .foregroundColor(MyaowColor.orange)
                            .shadow(color: MyaowColor.orange.opacity(motion.shieldGlowOpacity), radius: 6)
                    }
                    .padding(size * 0.01)
                }
            }
            
        case .angry:
            Image(systemName: "smoke.fill")
                .font(.system(size: size * 0.18))
                .foregroundColor(Color.white.opacity(motion.angrySteamOpacity))
                .offset(x: size * 0.32, y: -size * 0.28 + motion.angrySteamOffset)
            
        case .crying:
            HStack(spacing: size * 0.26) {
                ForEach(0..<2) { _ in
                    Capsule().fill(Color(hex: "74D7FF").opacity(0.65 + motion.tearDropOpacity * 0.3))
                        .frame(width: size * 0.035, height: size * 0.13)
                }
            }.offset(y: size * 0.16 + motion.tearDropOffset * 0.15)
        case .sad:
            Circle()
                .fill(Color(hex: "#29B6F6"))
                .frame(width: size * 0.08, height: size * 0.11)
                .offset(x: size * 0.16, y: size * 0.12 + motion.tearDropOffset)
                .opacity(motion.tearDropOpacity)
            
        case .exhausted:
            Image(systemName: "drop.fill")
                .font(.system(size: size * 0.15))
                .foregroundColor(Color(hex: "#4FC3F7"))
                .offset(x: size * 0.28, y: -size * 0.20 + motion.sweatDropOffset)
                .opacity(motion.sweatDropOpacity)
            
        case .thinking:
            ZStack {
                HStack(spacing: 3) {
                    Circle().fill(faceFeatureColor).frame(width: 4, height: 4).scaleEffect(motion.thoughtDotScale1)
                    Circle().fill(faceFeatureColor).frame(width: 4, height: 4).scaleEffect(motion.thoughtDotScale2)
                    Circle().fill(faceFeatureColor).frame(width: 4, height: 4).scaleEffect(motion.thoughtDotScale3)
                }
                .offset(x: size * 0.28, y: -size * 0.26)
                
                Image(systemName: "lightbulb.fill")
                    .font(.system(size: size * 0.20))
                    .foregroundColor(Color(hex: "#FFD600"))
                    .scaleEffect(motion.ideaSparkleScale)
                    .offset(x: size * 0.36, y: -size * 0.40)
                    .opacity(motion.ideaSparkleOpacity)
                    .shadow(color: Color(hex: "#FFD600").opacity(0.8), radius: 6)
            }
            
        case .curious:
            Text("?")
                .font(.system(size: size * 0.26, weight: .black, design: .rounded))
                .foregroundColor(MyaowColor.orange)
                .offset(x: size * 0.32, y: -size * 0.30 + motion.questionMarkOffset)
                .opacity(motion.questionMarkOpacity)
                .shadow(color: MyaowColor.orange.opacity(0.6), radius: 4)
            
        case .ninja:
            NinjaHeadbandShape()
                .fill(faceFeatureColor)
                .frame(width: size * 0.58, height: size * 0.12)
                .offset(y: -size * 0.18)
            
        default:
            if motion.isPurringActive {
                Text("💖")
                    .font(.system(size: size * 0.20))
                    .offset(x: size * 0.35, y: -size * 0.35 + motion.purrHeartOffset1)
                    .opacity(motion.purrHeartOpacity1)
            }
        }
    }
    
    // MARK: - Background
    @ViewBuilder
    private var backgroundView: some View {
        switch style {
        case .orangeOnDark:
            Circle().fill(MyaowColor.surfaceElevated)
        case .darkOnOrange:
            Circle().fill(MyaowColor.orange)
        case .whiteOnTransparent, .orangeOnTransparent:
            Color.clear
        case .custom(_, let bg):
            if let bg = bg {
                Circle().fill(bg)
            } else {
                Color.clear
            }
        }
    }
    
    // MARK: - Colors Resolution
    private var catBodyColor: Color {
        switch style {
        case .orangeOnDark, .orangeOnTransparent:
            return MyaowColor.orange
        case .darkOnOrange:
            return MyaowColor.charcoal
        case .whiteOnTransparent:
            return MyaowColor.white
        case .custom(let fg, _):
            return fg
        }
    }
    
    private var faceFeatureColor: Color {
        switch style {
        case .orangeOnDark, .orangeOnTransparent:
            return MyaowColor.charcoal
        case .darkOnOrange:
            return MyaowColor.orange
        case .whiteOnTransparent:
            return MyaowColor.charcoal
        case .custom(let fg, let bg):
            return bg ?? (fg == MyaowColor.orange ? MyaowColor.charcoal : MyaowColor.white)
        }
    }
    
    // MARK: - Cat Silhouette & Facial Features
    private var catVectorFace: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            
            ZStack {
                MyaowHeadSilhouetteShape(earFlex: motion.earFlex + speech.earLift)
                    .fill(catBodyColor)
                    .overlay {
                        if size >= 44 {
                            MyaowHeadSilhouetteShape(earFlex: motion.earFlex + speech.earLift)
                                .fill(LinearGradient(colors: [.white.opacity(0.18), .clear, .black.opacity(0.24)], startPoint: .topLeading, endPoint: .bottomTrailing))
                            MyaowHeadSilhouetteShape(earFlex: motion.earFlex + speech.earLift)
                                .stroke(LinearGradient(colors: [.white.opacity(0.32), .clear, .black.opacity(0.35)], startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: size * 0.012)
                        }
                    }
                    .shadow(color: .black.opacity(size >= 44 ? 0.35 : 0), radius: size * 0.025, x: size * 0.01, y: size * 0.035)
                
                VStack(spacing: 0) {
                    eyesView(width: w, height: h)
                        .scaleEffect(y: motion.blinkScaleY, anchor: UnitPoint.center)
                        .scaleEffect(x: 1, y: speech.eyeLift - speech.squint)
                        .offset(x: motion.gazeOffset + speech.gaze * size / 80, y: -(speech.cheekLift * 0.003 + speech.browLift * 0.007) * size)
                        .padding(.top, h * 0.42)
                    
                    muzzleView(width: w, height: h)
                        .padding(.top, h * 0.05)
                }
            }
        }
    }
    
    // MARK: - Eyes View
    @ViewBuilder
    private func eyesView(width: CGFloat, height: CGFloat) -> some View {
        let eyeWidth: CGFloat = width * 0.15
        let eyeHeight: CGFloat = width * 0.15
        let eyeSpacing: CGFloat = width * 0.22
        
        HStack(spacing: eyeSpacing) {
            singleEyeView(isLeft: true, width: eyeWidth, height: eyeHeight)
                .scaleEffect(y: 1 + speech.eyeAsymmetry, anchor: .bottom)
                .rotationEffect(.degrees(-speech.browLift * 2))
            singleEyeView(isLeft: false, width: eyeWidth, height: eyeHeight)
                .scaleEffect(y: 1 - speech.eyeAsymmetry, anchor: .bottom)
                .rotationEffect(.degrees(speech.browLift * 2))
        }
    }
    
    @ViewBuilder
    private func singleEyeView(isLeft: Bool, width: CGFloat, height: CGFloat) -> some View {
        if showsCrossEyes {
            Image(systemName: "xmark").font(.system(size: width * 1.25, weight: .black)).foregroundStyle(faceFeatureColor)
        } else {
        switch state {
        case .neutral:
            ZStack {
                Capsule()
                    .fill(faceFeatureColor)
                    .frame(width: width, height: height * 0.85 * max(0.05, eyeProgress))
                
                if eyeProgress > 0.6 {
                    Circle()
                        .fill(Color.white.opacity(0.65))
                        .frame(width: width * 0.32, height: width * 0.32)
                        .offset(x: width * 0.16, y: -height * 0.16)
                }
            }
            
        case .friendly:
            ZStack {
                Circle()
                    .fill(faceFeatureColor)
                    .frame(width: width * 1.15, height: height * 1.15)
                
                Circle()
                    .fill(Color.white.opacity(0.9))
                    .frame(width: width * 0.42, height: width * 0.42)
                    .offset(x: width * 0.18, y: -height * 0.18)
                
                Circle()
                    .fill(Color.white.opacity(0.6))
                    .frame(width: width * 0.22, height: width * 0.22)
                    .offset(x: -width * 0.18, y: height * 0.18)
            }
            
        case .bored:
            // 🥱 Aburrido: párpados pesados caídos mirando hacia un lado con desgana
            ZStack {
                Capsule()
                    .fill(faceFeatureColor)
                    .frame(width: width * 1.1, height: height * 0.35)
                
                Circle()
                    .fill(faceFeatureColor)
                    .frame(width: width * 0.55, height: width * 0.55)
                    .offset(x: isLeft ? width * 0.25 : width * 0.25, y: height * 0.12)
            }
            
        case .gossiping:
            // 👀 Chismoso: pupilas que escanean rápido de izquierda a derecha
            ZStack {
                Circle()
                    .fill(faceFeatureColor.opacity(0.2))
                    .frame(width: width * 1.25, height: height * 1.25)
                
                Circle()
                    .fill(faceFeatureColor)
                    .frame(width: width * 0.85, height: height * 0.85)
                    .offset(x: motion.gossipPupilShift, y: 0)
                
                Circle()
                    .fill(Color.white)
                    .frame(width: width * 0.32, height: width * 0.32)
                    .offset(x: motion.gossipPupilShift + width * 0.15, y: -height * 0.15)
            }
            
        case .cool:
            // 🕶️ Fachero: Ojos cubiertos por gafas oscuras en el overlay
            Capsule()
                .fill(Color.clear)
                .frame(width: width, height: height)
            
        case .hungry:
            // 🤤 Hambriento: ojos gigantes y tiernos suplicantes estilo Gato con Botas
            ZStack {
                Circle()
                    .fill(faceFeatureColor)
                    .frame(width: width * 1.4, height: height * 1.4)
                
                Circle()
                    .fill(Color.white)
                    .frame(width: width * 0.55, height: width * 0.55)
                    .offset(x: width * 0.22, y: -height * 0.22)
                
                Circle()
                    .fill(Color.white.opacity(0.85))
                    .frame(width: width * 0.28, height: width * 0.28)
                    .offset(x: -width * 0.22, y: height * 0.22)
            }
            
        case .inLove:
            // 🥰 Enamorado: corazones palpitantes en lugar de pupilas
            HeartShape()
                .fill(Color(hex: "#FF2D55"))
                .frame(width: width * 1.25, height: height * 1.25)
                .scaleEffect(motion.heartEyesBeatScale)
                .shadow(color: Color(hex: "#FF2D55").opacity(0.8), radius: 4)
            
        case .calm:
            CalmZenEyeArc()
                .stroke(faceFeatureColor, style: StrokeStyle(lineWidth: max(2.2, width * 0.22), lineCap: .round))
                .frame(width: width * 1.1, height: height * 0.45)
            
        case .happy:
            HappyEyeArc()
                .stroke(faceFeatureColor, style: StrokeStyle(lineWidth: max(2.2, width * 0.22), lineCap: .round))
                .frame(width: width * 1.15, height: height * 0.75)
            
        case .curious:
            if isLeft {
                ZStack {
                    Circle()
                        .fill(faceFeatureColor)
                        .frame(width: width * 1.3, height: height * 1.3)
                    
                    Circle()
                        .fill(Color.white)
                        .frame(width: width * 0.48, height: width * 0.48)
                        .offset(x: width * 0.22, y: -height * 0.22)
                }
            } else {
                Capsule()
                    .fill(faceFeatureColor)
                    .frame(width: width * 0.85, height: height * 0.65)
            }
            
        case .busy:
            ZStack {
                Circle()
                    .stroke(faceFeatureColor, lineWidth: max(1.8, width * 0.18))
                    .frame(width: width * 1.4, height: height * 1.4)
                    .shadow(color: MyaowColor.orange.opacity(motion.busyGlassesGlow), radius: 3)
                
                Circle()
                    .fill(faceFeatureColor)
                    .frame(width: width * 0.65, height: height * 0.65)
            }
            
        case .ninja:
            NinjaEyeArc(isLeft: isLeft)
                .stroke(faceFeatureColor, style: StrokeStyle(lineWidth: max(2.6, width * 0.26), lineCap: .round))
                .frame(width: width * 1.25, height: height * 0.45)
                .shadow(color: MyaowColor.orange.opacity(motion.ninjaGlow), radius: 4)
            
        case .exhausted:
            Capsule()
                .fill(faceFeatureColor)
                .frame(width: width * 1.05, height: height * 0.38)
            
        case .drunk:
            if isLeft {
                ZStack {
                    Circle()
                        .stroke(faceFeatureColor, lineWidth: max(2, width * 0.2))
                        .frame(width: width * 1.1, height: height * 1.1)
                    
                    Circle()
                        .fill(faceFeatureColor)
                        .frame(width: width * 0.45, height: width * 0.45)
                        .offset(x: motion.dizzyPupilOffset, y: -motion.dizzyPupilOffset)
                }
            } else {
                DizzyWinkEyeArc()
                    .stroke(faceFeatureColor, style: StrokeStyle(lineWidth: max(2.2, width * 0.22), lineCap: .round))
                    .frame(width: width * 1.1, height: height * 0.5)
            }
            
        case .playful:
            if isLeft {
                SleepingEyeArc()
                    .stroke(faceFeatureColor, style: StrokeStyle(lineWidth: max(2, width * 0.2), lineCap: .round))
                    .frame(width: width, height: height * 0.4)
            } else {
                ZStack {
                    Circle().fill(faceFeatureColor).frame(width: width * 1.1, height: height * 1.1)
                    Circle().fill(Color.white.opacity(0.85)).frame(width: width * 0.38, height: width * 0.38).offset(x: width * 0.18, y: -height * 0.18)
                }
            }
            
        case .angry:
            AngryEyeArc(isLeft: isLeft)
                .stroke(faceFeatureColor, style: StrokeStyle(lineWidth: max(2.4, width * 0.24), lineCap: .round))
                .frame(width: width * 1.15, height: height * 0.55)
            
        case .sad:
            SadEyeArc(isLeft: isLeft)
                .stroke(faceFeatureColor, style: StrokeStyle(lineWidth: max(2, width * 0.2), lineCap: .round))
                .frame(width: width * 1.1, height: height * 0.5)
            
        case .sleeping:
            SleepingEyeArc()
                .stroke(faceFeatureColor, style: StrokeStyle(lineWidth: max(2, width * 0.2), lineCap: .round))
                .frame(width: width * 1.05, height: height * 0.45)
            
        case .laughing, .shy, .crying, .skeptical, .mischievous, .party,
             .purring, .surprised, .thinking, .connected, .connecting, .protected, .openingEyes:
            MyaowExpressionEye(state: state, isLeft: isLeft, color: faceFeatureColor, eyeProgress: eyeProgress)
                .frame(width: width * 1.6, height: height * 1.8)
                .frame(width: width, height: height)

        }
    }
    
    }

    // MARK: - Muzzle & Nose & Mouth View
    @ViewBuilder
    private func muzzleView(width: CGFloat, height: CGFloat) -> some View {
        let noseSize = width * 0.08
        
        VStack(spacing: 2) {
            PolygonTriangle()
                .fill(faceFeatureColor)
                .frame(width: noseSize, height: noseSize * 0.7)
                .rotationEffect(Angle(degrees: 180))
            
            if speech.mouthHeight > 0 {
                let dimensions = speech.mouthDimensions(faceWidth: width, avatarSize: size)
                let shape = MyaowSpeechMouth(smile: speech.smile, roundness: speech.mouthRoundness)
                shape.fill(Color(hex: "#180D16"))
                    .overlay(alignment: .bottom) {
                        if speech.tongue && speech.mouthHeight > 0.28 {
                            Ellipse().fill(LinearGradient(colors: [Color(hex: "#FA879A"), Color(hex: "#C94B76")], startPoint: .top, endPoint: .bottom))
                                .frame(width: dimensions.width * 0.58, height: dimensions.height * 0.38)
                                .offset(y: dimensions.height * 0.04)
                        }
                    }
                    .clipShape(shape)
                    .overlay(shape.stroke(faceFeatureColor, style: StrokeStyle(lineWidth: max(1.2, size * 0.012), lineCap: .round, lineJoin: .round)))
                    .frame(width: dimensions.width, height: dimensions.height)
                    .rotationEffect(.degrees(speech.mouthSlant))
                    .offset(y: speech.jawDrop * width * 0.014)
                    .frame(width: width * 0.38, height: width * 0.17, alignment: .top)
            } else {
                MyaowExpressionMouth(state: state, color: faceFeatureColor, motion: motion)
                    .frame(width: width * 0.23, height: width * 0.13)
                    .frame(width: width * 0.38, height: width * 0.17, alignment: .top)
            }
        }
    }
}

// MARK: - Componentes Visuales Especializados

/// Gafas de sol Fachero Myaow
public struct CoolSunglassesView: View {
    public let size: CGFloat
    public let faceFeatureColor: Color
    
    public var body: some View {
        HStack(spacing: size * 0.06) {
            // Lente Izquierda
            RoundedRectangle(cornerRadius: size * 0.04, style: .continuous)
                .fill(faceFeatureColor)
                .frame(width: size * 0.26, height: size * 0.16)
            
            // Puente
            Rectangle()
                .fill(faceFeatureColor)
                .frame(width: size * 0.06, height: size * 0.03)
                .offset(y: -size * 0.03)
            
            // Lente Derecha
            RoundedRectangle(cornerRadius: size * 0.04, style: .continuous)
                .fill(faceFeatureColor)
                .frame(width: size * 0.26, height: size * 0.16)
        }
        .offset(y: -size * 0.04)
        .shadow(color: Color.black.opacity(0.4), radius: 3)
    }
}

// MARK: - Custom Shapes

/// Silueta pulida de la cabeza y orejas de gato
public struct MyaowHeadSilhouetteShape: Shape {
    var earFlex: CGFloat = 0
    public var animatableData: CGFloat {
        get { earFlex }
        set { earFlex = newValue }
    }

    public func path(in rect: CGRect) -> Path {
        var path = Path()
        let w = rect.width
        let h = rect.height
        
        path.move(to: CGPoint(x: w * 0.50, y: h * 0.94))
        path.addCurve(
            to: CGPoint(x: w * 0.10, y: h * 0.54),
            control1: CGPoint(x: w * 0.28, y: h * 0.94),
            control2: CGPoint(x: w * 0.10, y: h * 0.74)
        )
        path.addCurve(
            to: CGPoint(x: w * (0.22 - earFlex * 0.012), y: h * (0.08 + earFlex * 0.025)),
            control1: CGPoint(x: w * 0.10, y: h * 0.36),
            control2: CGPoint(x: w * 0.14, y: h * 0.16)
        )
        path.addCurve(
            to: CGPoint(x: w * 0.38, y: h * 0.30),
            control1: CGPoint(x: w * 0.27, y: h * (0.08 + earFlex * 0.025)),
            control2: CGPoint(x: w * 0.32, y: h * 0.20)
        )
        path.addCurve(
            to: CGPoint(x: w * 0.62, y: h * 0.30),
            control1: CGPoint(x: w * 0.44, y: h * 0.34),
            control2: CGPoint(x: w * 0.56, y: h * 0.34)
        )
        path.addCurve(
            to: CGPoint(x: w * (0.78 + earFlex * 0.006), y: h * (0.08 + earFlex * 0.012)),
            control1: CGPoint(x: w * 0.68, y: h * 0.20),
            control2: CGPoint(x: w * 0.73, y: h * (0.08 + earFlex * 0.012))
        )
        path.addCurve(
            to: CGPoint(x: w * 0.90, y: h * 0.54),
            control1: CGPoint(x: w * 0.86, y: h * 0.16),
            control2: CGPoint(x: w * 0.90, y: h * 0.36)
        )
        path.addCurve(
            to: CGPoint(x: w * 0.50, y: h * 0.94),
            control1: CGPoint(x: w * 0.90, y: h * 0.74),
            control2: CGPoint(x: w * 0.72, y: h * 0.94)
        )
        path.closeSubpath()
        return path
    }
}

/// Forma de corazón para ojos y partículas
public struct HeartShape: Shape {
    public func path(in rect: CGRect) -> Path {
        var path = Path()
        let w = rect.width
        let h = rect.height
        
        path.move(to: CGPoint(x: w * 0.5, y: h * 0.85))
        path.addCurve(
            to: CGPoint(x: 0, y: h * 0.3),
            control1: CGPoint(x: w * 0.2, y: h * 0.65),
            control2: CGPoint(x: 0, y: h * 0.5)
        )
        path.addArc(
            center: CGPoint(x: w * 0.25, y: h * 0.25),
            radius: w * 0.25,
            startAngle: .degrees(180),
            endAngle: .degrees(0),
            clockwise: false
        )
        path.addArc(
            center: CGPoint(x: w * 0.75, y: h * 0.25),
            radius: w * 0.25,
            startAngle: .degrees(180),
            endAngle: .degrees(0),
            clockwise: false
        )
        path.addCurve(
            to: CGPoint(x: w * 0.5, y: h * 0.85),
            control1: CGPoint(x: w, y: h * 0.5),
            control2: CGPoint(x: w * 0.8, y: h * 0.65)
        )
        path.closeSubpath()
        return path
    }
}

/// Ojo Zen tranquilo curvado hacia arriba
public struct CalmZenEyeArc: Shape {
    public func path(in rect: CGRect) -> Path {
        var path = Path()
        let w = rect.width
        let h = rect.height
        path.move(to: CGPoint(x: 0, y: h * 0.3))
        path.addQuadCurve(to: CGPoint(x: w, y: h * 0.3), control: CGPoint(x: w * 0.5, y: h * 0.9))
        return path
    }
}

/// Diadema ninja
public struct NinjaHeadbandShape: Shape {
    public func path(in rect: CGRect) -> Path {
        var path = Path()
        let w = rect.width
        let h = rect.height
        path.addRoundedRect(in: CGRect(x: 0, y: 0, width: w, height: h), cornerSize: CGSize(width: h * 0.4, height: h * 0.4))
        return path
    }
}

/// Ojo feliz curvado hacia arriba
public struct HappyEyeArc: Shape {
    public func path(in rect: CGRect) -> Path {
        var path = Path()
        let w = rect.width
        let h = rect.height
        path.move(to: CGPoint(x: 0, y: h * 0.8))
        path.addQuadCurve(to: CGPoint(x: w, y: h * 0.8), control: CGPoint(x: w * 0.5, y: 0))
        return path
    }
}

/// Ojo durmiendo
public struct SleepingEyeArc: Shape {
    public func path(in rect: CGRect) -> Path {
        var path = Path()
        let w = rect.width
        let h = rect.height
        path.move(to: CGPoint(x: 0, y: h * 0.4))
        path.addQuadCurve(to: CGPoint(x: w, y: h * 0.4), control: CGPoint(x: w * 0.5, y: 0.8))
        return path
    }
}

/// Ojo enojado en diagonal
public struct AngryEyeArc: Shape {
    public let isLeft: Bool
    public func path(in rect: CGRect) -> Path {
        var path = Path()
        let w = rect.width
        let h = rect.height
        if isLeft {
            path.move(to: CGPoint(x: 0, y: 0))
            path.addLine(to: CGPoint(x: w, y: h * 0.7))
        } else {
            path.move(to: CGPoint(x: 0, y: h * 0.7))
            path.addLine(to: CGPoint(x: w, y: 0))
        }
        return path
    }
}

/// Ojo triste inclinado hacia abajo
public struct SadEyeArc: Shape {
    public let isLeft: Bool
    public func path(in rect: CGRect) -> Path {
        var path = Path()
        let w = rect.width
        let h = rect.height
        if isLeft {
            path.move(to: CGPoint(x: 0, y: h * 0.8))
            path.addQuadCurve(to: CGPoint(x: w, y: h * 0.3), control: CGPoint(x: w * 0.5, y: 0.4))
        } else {
            path.move(to: CGPoint(x: 0, y: h * 0.3))
            path.addQuadCurve(to: CGPoint(x: w, y: h * 0.8), control: CGPoint(x: w * 0.5, y: 0.4))
        }
        return path
    }
}

/// Ojo ninja rasgado
public struct NinjaEyeArc: Shape {
    public let isLeft: Bool
    public func path(in rect: CGRect) -> Path {
        var path = Path()
        let w = rect.width
        let h = rect.height
        if isLeft {
            path.move(to: CGPoint(x: 0, y: h * 0.6))
            path.addLine(to: CGPoint(x: w, y: h * 0.2))
        } else {
            path.move(to: CGPoint(x: 0, y: h * 0.2))
            path.addLine(to: CGPoint(x: w, y: h * 0.6))
        }
        return path
    }
}

/// Ojo ondulado / guiño mareado de borrachón
public struct DizzyWinkEyeArc: Shape {
    public func path(in rect: CGRect) -> Path {
        var path = Path()
        let w = rect.width
        let h = rect.height
        
        path.move(to: CGPoint(x: 0, y: h * 0.5))
        path.addCurve(
            to: CGPoint(x: w, y: h * 0.5),
            control1: CGPoint(x: w * 0.35, y: 0),
            control2: CGPoint(x: w * 0.65, y: h)
        )
        return path
    }
}

/// Triángulo pequeño para la nariz
public struct PolygonTriangle: Shape {
    public func path(in rect: CGRect) -> Path {
        var path = Path()
        let w = rect.width
        let h = rect.height
        path.move(to: CGPoint(x: w * 0.5, y: 0))
        path.addLine(to: CGPoint(x: w, y: h))
        path.addLine(to: CGPoint(x: 0, y: h))
        path.closeSubpath()
        return path
    }
}

/// The original speaking silhouette, without a tooth overlay.
private struct MyaowSpeechMouth: Shape {
    var smile: Double
    var roundness: Double
    var animatableData: AnimatablePair<Double, Double> {
        get { AnimatablePair(smile, roundness) }
        set { smile = newValue.first; roundness = newValue.second }
    }
    func path(in rect: CGRect) -> Path {
        let w = rect.width, h = rect.height
        let corner = 0.24 - smile * 0.14 + roundness * 0.12
        var path = Path()
        path.move(to: CGPoint(x: 0, y: h * corner))
        path.addQuadCurve(to: CGPoint(x: w, y: h * corner), control: CGPoint(x: w * 0.5, y: h * (0.18 + smile * 0.34 - roundness * 0.46)))
        path.addCurve(to: CGPoint(x: 0, y: h * corner), control1: CGPoint(x: w * 0.96, y: h * 1.0), control2: CGPoint(x: w * 0.04, y: h * 1.0))
        path.closeSubpath()
        return path
    }
}
