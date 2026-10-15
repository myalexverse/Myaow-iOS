import SwiftUI

/// A finite, noninteractive effect drawn over the current screen. It never moves chat text.
struct MyaowNudgeScreenEffect: View {
    let sound: CatVocalSynthesizer.CatSoundType
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var began = ProcessInfo.processInfo.systemUptime
    @State private var lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
    @State private var finished = false

    var body: some View {
        TimelineView(.animation(minimumInterval: lowPower ? 1.0 / 15 : 1.0 / 30, paused: finished || reduceMotion || scenePhase != .active)) { _ in
            let age = max(0, ProcessInfo.processInfo.systemUptime - began)
            let fade = min(1, age / 0.22) * max(0, min(1, (3.5 - age) / 0.65))
            GeometryReader { geometry in
                ZStack {
                    RoundedRectangle(cornerRadius: 40)
                        .stroke(tint.opacity(reduceMotion ? 0.24 : fade * 0.48), lineWidth: reduceMotion ? 2 : 4)
                        .blur(radius: reduceMotion ? 0 : 14)
                        .padding(5)
                    if !reduceMotion {
                        Canvas { context, size in
                            guard age < 3.5 else { return }
                            let center = CGPoint(x: size.width * 0.5, y: min(190, size.height * 0.26))
                            if [.classic, .echo, .purr, .lazy].contains(sound) {
                                for index in 0..<3 {
                                    let progress = max(0, min(1, (age - Double(index) * 0.24) / 2.7))
                                    let radius = 36 + progress * min(size.width, size.height) * 0.95
                                    let rect = CGRect(x: center.x-radius, y: center.y-radius, width: radius*2, height: radius*2)
                                    context.stroke(Path(ellipseIn: rect), with: .color(tint.opacity((1-progress) * 0.48 * fade)), lineWidth: 1.5)
                                }
                            }
                            if sound == .hiss {
                                for index in 0..<3 {
                                    let p = max(0, min(1, (age - Double(index)*0.1) / 0.32))
                                    var slash = Path()
                                    let x = size.width * (0.27 + Double(index) * 0.17)
                                    let y = size.height * 0.32
                                    slash.move(to: CGPoint(x: x+36, y: y))
                                    slash.addQuadCurve(to: CGPoint(x: x-34*p, y: y+size.height*0.22*p), control: CGPoint(x: x-6, y: y+size.height*0.09))
                                    context.stroke(slash, with: .color(tint.opacity(fade * 0.78)), style: StrokeStyle(lineWidth: 3.5, lineCap: .round))
                                }
                            }
                            for index in 0..<(lowPower ? 8 : 15) {
                                let seed = Double(index)
                                let delay = seed.truncatingRemainder(dividingBy: 5) * 0.08
                                let p = max(0, min(1, (age-delay) / 3.0))
                                guard p > 0 && p < 1 else { continue }
                                let baseX = (seed * 0.61803398875).truncatingRemainder(dividingBy: 1)
                                let direction = index.isMultiple(of: 2) ? 1.0 : -1.0
                                let x: Double
                                let y: Double
                                switch sound {
                                case .party, .giggle:
                                    x = size.width * (0.5 + direction * p * (0.2 + baseX * 0.55))
                                    y = center.y + (p*p*size.height*0.8 - sin(p * .pi) * 90) + seed*4
                                case .purr, .kiss, .admiration:
                                    x = size.width * (0.12 + baseX * 0.76) + sin(p * 5 + seed) * 20
                                    y = size.height * (0.9 - p*0.72) + seed*3
                                case .electric, .hiss:
                                    x = size.width * (index.isMultiple(of: 2) ? 0.1 : 0.9) + direction * sin(p * .pi) * 18
                                    y = size.height * (0.18 + baseX*0.65) - p*30
                                case .sleepy, .lazy:
                                    x = size.width * (0.1 + baseX*0.8) + sin(p*2+seed)*12
                                    y = size.height*(0.8-p*0.4)
                                default:
                                    let angle = baseX * .pi * 2
                                    x = center.x + cos(angle) * (35+p*size.width*0.65)
                                    y = center.y + sin(angle) * (35+p*size.height*0.45) + p*80
                                }
                                let symbol = sound == .party ? (index.isMultiple(of: 3) ? "sparkle" : "circle.fill") : sound == .hiss ? "pawprint.fill" : sound.effectSymbol
                                let color = sound == .party && index.isMultiple(of: 3) ? Color(hex: "FFCE70") : tint
                                var resolved = context.resolve(Image(systemName: symbol))
                                resolved.shading = .color(color)
                                let side = (sound == .party ? 9 : 16) + baseX * 15
                                var particle = context
                                particle.opacity = sin(p * .pi) * fade * 0.82
                                particle.translateBy(x: x, y: y)
                                particle.rotate(by: .degrees(direction * p * (sound == .party ? 190 : 25)))
                                particle.draw(resolved, in: CGRect(x: -side/2, y: -side/2, width: side, height: side))
                            }
                        }
                    }
                }.frame(width: geometry.size.width, height: geometry.size.height)
            }
        }
        .allowsHitTesting(false).accessibilityHidden(true)
        .task {
            try? await Task.sleep(for: .milliseconds(3500))
            guard !Task.isCancelled else { return }
            finished = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .NSProcessInfoPowerStateDidChange)) { _ in lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled }
    }
    private var tint: Color {
        switch sound {
        case .purr, .kiss, .admiration: Color(hex: "FF738E")
        case .sleepy, .echo: Color(hex: "A79AFF")
        case .hiss: Color(hex: "FF6B46")
        case .melodic: Color(hex: "F4BF62")
        default: MyaowColor.orange
        }
    }
}

struct MyaowNudgeEffectPreview: View {
    let sound: CatVocalSynthesizer.CatSoundType
    @Environment(\.dismiss) private var dismiss
    @State private var replay = UUID()
    var body: some View {
        ZStack {
            MyaowColor.charcoal.ignoresSafeArea()
            VStack(spacing: 18) {
                Text("VISTA PREVIA").font(.caption.weight(.semibold)).tracking(2).foregroundStyle(MyaowColor.orange)
                MyaowCatView(state: sound.catState, style: .darkOnOrange, size: 158, isInteractive: false)
                Text(sound.displayName).font(.largeTitle.bold())
                Text(sound.subtitle).foregroundStyle(MyaowColor.textSecondary)
                Button("Repetir efecto", systemImage: "arrow.clockwise") { replay = UUID(); _ = CatVocalSynthesizer.shared.playCatSound(sound) }
                    .buttonStyle(.bordered).tint(MyaowColor.orange).padding(.top, 24)
                Text("Así se verá dentro de Myaow al recibirlo.").font(.footnote).foregroundStyle(.secondary)
            }.padding(24)
            MyaowNudgeScreenEffect(sound: sound).id(replay).ignoresSafeArea()
            VStack { HStack { Spacer(); Button("Listo") { dismiss() }.padding(20) }; Spacer() }
        }.foregroundStyle(.white).preferredColorScheme(.dark)
            .onAppear { _ = CatVocalSynthesizer.shared.playCatSound(sound) }
            .onDisappear { CatVocalSynthesizer.shared.stop() }
    }
}
