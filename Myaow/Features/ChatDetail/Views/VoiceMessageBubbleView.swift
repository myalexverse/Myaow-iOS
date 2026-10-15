//
//  VoiceMessageBubbleView.swift
//  Myaow
//
//  Created for Myaow - "Tecnología que se siente cercana"
//

import SwiftUI

public struct VoiceMessageBubbleView: View {
    public let message: MessageModel
    public var isOutgoing: Bool
    
    @State private var playbackService = VoicePlaybackService.shared
    
    // Muestras de onda por defecto si el mensaje no tiene muestras personalizadas
    private let defaultSamples: [CGFloat] = [
        0.2, 0.4, 0.7, 0.9, 0.6, 0.3, 0.5, 0.8, 0.95, 0.7,
        0.4, 0.6, 0.85, 0.5, 0.3, 0.6, 0.75, 0.9, 0.4, 0.3,
        0.5, 0.8, 0.6, 0.4, 0.2
    ]
    
    public init(message: MessageModel, isOutgoing: Bool) {
        self.message = message
        self.isOutgoing = isOutgoing
    }
    
    private var isCurrentlyPlaying: Bool {
        playbackService.activeMessageId == message.id && playbackService.isPlaying
    }
    
    private var currentProgress: Double {
        if playbackService.activeMessageId == message.id {
            return playbackService.playbackProgress
        }
        return 0.0
    }
    
    public var body: some View {
        HStack(spacing: 12) {
            // Botón Play / Pause Circular
            Button(action: {
                playbackService.togglePlay(messageId: message.id, audioData: message.mediaData)
            }) {
                ZStack {
                    Circle()
                        .fill(isOutgoing ? Color.white : MyaowColor.orange)
                        .frame(width: 40, height: 40)
                    
                    Image(systemName: isCurrentlyPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(isOutgoing ? MyaowColor.orange : .white)
                        .offset(x: isCurrentlyPlaying ? 0 : 1)
                }
            }
            
            // Visualizador de Onda Sonora y Duración
            VStack(alignment: .leading, spacing: 5) {
                // Onda de Audio Interactiva
                HStack(spacing: 3) {
                    ForEach(0..<defaultSamples.count, id: \.self) { idx in
                        let sampleHeight = max(6.0, defaultSamples[idx] * 24.0)
                        let barProgress = Double(idx) / Double(defaultSamples.count)
                        let isPlayed = barProgress <= currentProgress
                        
                        RoundedRectangle(cornerRadius: 2)
                            .fill(barColor(isPlayed: isPlayed))
                            .frame(width: 3, height: sampleHeight)
                    }
                }
                .frame(height: 28)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            let width: CGFloat = CGFloat(defaultSamples.count * 6)
                            let newProgress = min(1.0, max(0.0, Double(value.location.x / width)))
                            if playbackService.activeMessageId == message.id { playbackService.seek(progress: newProgress) }
                        }
                )
                
                // Duración y Velocidad
                HStack {
                    Text(message.text.contains(":") ? message.text : "Nota de voz")
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundColor(isOutgoing ? Color.white.opacity(0.85) : MyaowColor.textSecondary)
                    
                    Spacer()
                    
                    if isCurrentlyPlaying || playbackService.activeMessageId == message.id {
                        Button(action: {
                            playbackService.cyclePlaybackSpeed()
                        }) {
                            Text(String(format: "%.1fx", playbackService.playbackSpeed))
                                .font(.system(size: 10, weight: .bold, design: .rounded))
                                .foregroundColor(isOutgoing ? MyaowColor.orange : .white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(isOutgoing ? Color.white : MyaowColor.orange)
                                .clipShape(Capsule())
                        }
                    }
                }
            }
            .frame(width: 155)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(isOutgoing ? MyaowColor.orange : MyaowColor.surfaceElevated)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .alert("Nota de voz", isPresented: Binding(get: { playbackService.activeMessageId == message.id && playbackService.lastError != nil }, set: { if !$0 { playbackService.lastError = nil } })) {
            Button("Entendido", role: .cancel) { playbackService.lastError = nil }
        } message: { Text(playbackService.lastError ?? "") }
    }
    
    private func barColor(isPlayed: Bool) -> Color {
        if isOutgoing {
            return isPlayed ? Color.white : Color.white.opacity(0.4)
        } else {
            return isPlayed ? MyaowColor.orange : MyaowColor.textTertiary.opacity(0.5)
        }
    }
}
