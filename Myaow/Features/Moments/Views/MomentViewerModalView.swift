//
//  MomentViewerModalView.swift
//  Myaow
//
//  Created for Myaow - "Tecnología que se siente cercana"
//

import SwiftUI
import SwiftData

public struct MomentViewerModalView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    
    public var moment: MomentModel
    
    @State private var progress: CGFloat = 0.0
    @State private var isPaused: Bool = false
    @State private var reactionFloatingSymbol: String? = nil
    @State private var quickReplyText: String = ""
    @State private var timer: Timer? = nil
    
    public init(moment: MomentModel) {
        self.moment = moment
    }
    
    private let gradients: [[Color]] = [
        [Color(hex: "#FF6B00"), Color(hex: "#FF2D55")],
        [Color(hex: "#8A2387"), Color(hex: "#E94057"), Color(hex: "#F27121")],
        [Color(hex: "#1D2671"), Color(hex: "#C33764")],
        [Color(hex: "#0F2027"), Color(hex: "#203A43"), Color(hex: "#2C5364")],
        [Color(hex: "#11998E"), Color(hex: "#38EF7D")]
    ]
    
    private var authorCatState: MyaowCatState {
        MyaowCatState(rawValue: moment.authorAvatarCatState) ?? .friendly
    }
    
    private var momentCatEmotion: MyaowCatState {
        MyaowCatState(rawValue: moment.catEmotionRaw) ?? authorCatState
    }
    
    public var body: some View {
        ZStack {
            // Fondo con el gradiente del momento
            LinearGradient(
                colors: gradients[moment.backgroundGradientIndex % gradients.count],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
            
            VStack(spacing: 0) {
                // 1. Barra de Progreso Superior
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color.white.opacity(0.3))
                            .frame(height: 3)
                        
                        Capsule()
                            .fill(Color.white)
                            .frame(width: geo.size.width * progress, height: 3)
                    }
                }
                .frame(height: 3)
                .padding(.horizontal, 16)
                .padding(.top, 10)
                
                // 2. Cabecera del Autor
                HStack(spacing: 12) {
                    MyaowCatView(
                        state: authorCatState,
                        style: .darkOnOrange,
                        size: 40,
                        isInteractive: false
                    )
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text(moment.authorDisplayName)
                            .font(.system(size: 15, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                        
                        Text(moment.formattedTimeAgo)
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                            .foregroundColor(Color.white.opacity(0.8))
                    }
                    
                    Spacer()
                    
                    Button(action: {
                        dismiss()
                    }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(.white)
                            .frame(width: 36, height: 36)
                            .background(Color.black.opacity(0.4))
                            .clipShape(Circle())
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                
                Spacer()
                
                // 3. Contenido Central del Momento
                VStack(spacing: 20) {
                    if let data = moment.mediaData, let uiImage = UIImage(data: data) {
                        Image(uiImage: uiImage)
                            .resizable()
                            .scaledToFit()
                            .frame(maxHeight: 440)
                            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                            .shadow(color: Color.black.opacity(0.4), radius: 16, x: 0, y: 8)
                            .padding(.horizontal, 16)
                    } else {
                        // Momento de Mascota / Emocional
                        MyaowCatView(
                            state: momentCatEmotion,
                            style: .darkOnOrange,
                            size: 120,
                            isInteractive: true
                        )
                        .shadow(color: Color.black.opacity(0.35), radius: 18, x: 0, y: 8)
                        
                        Text(momentCatEmotion.displayName)
                            .font(.system(size: 28, weight: .black, design: .rounded))
                            .foregroundColor(.white)
                    }
                    
                    if !moment.captionText.isEmpty {
                        Text(moment.captionText)
                            .font(.system(size: 18, weight: .semibold, design: .rounded))
                            .foregroundColor(.white)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 28)
                            .shadow(color: Color.black.opacity(0.4), radius: 4, x: 0, y: 2)
                    }
                }
                
                Spacer()
                
                // 4. Reacciones Rápidas & Respuestas
                HStack(spacing: 12) {
                    ForEach(["🐾", "💖", "⚡️", "🤤", "😸"], id: \.self) { symbol in
                        Button(action: {
                            sendReaction(symbol)
                        }) {
                            Text(symbol)
                                .font(.system(size: 26))
                                .padding(8)
                                .background(Color.black.opacity(0.35))
                                .clipShape(Circle())
                        }
                    }
                }
                .padding(.bottom, 24)
            }
            
            // Reacción Flotante Animada
            if let reaction = reactionFloatingSymbol {
                Text(reaction)
                    .font(.system(size: 72))
                    .transition(.scale.combined(with: .opacity))
                    .shadow(radius: 10)
            }
        }
        .onAppear {
            moment.isSeen = true
            try? modelContext.save()
            startStoryTimer()
        }
        .onDisappear {
            timer?.invalidate()
        }
    }
    
    private func startStoryTimer() {
        let totalDuration: Double = 6.0
        let interval: Double = 0.05
        let increment = CGFloat(interval / totalDuration)
        
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { t in
            guard !isPaused else { return }
            if progress < 1.0 {
                progress += increment
            } else {
                t.invalidate()
                dismiss()
            }
        }
    }
    
    private func sendReaction(_ symbol: String) {
        let gen = UIImpactFeedbackGenerator(style: .medium)
        gen.impactOccurred()
        
        // Sonido festivo felino
        CatVocalSynthesizer.shared.playCatSound(.purr)
        
        withAnimation(.spring(response: 0.35, dampingFraction: 0.6)) {
            reactionFloatingSymbol = symbol
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            withAnimation {
                reactionFloatingSymbol = nil
            }
        }
    }
}
