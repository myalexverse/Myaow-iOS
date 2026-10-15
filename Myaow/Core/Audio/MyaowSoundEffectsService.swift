//
//  MyaowSoundEffectsService.swift
//  Myaow
//
//  Created for Myaow - "Tecnología que se siente cercana"
//

import SwiftUI
import AVFoundation
import AudioToolbox

/// Servicio de efectos de sonido nativos, síntesis de audio y respuestas hápticas para interacciones y zumbidos en Myaow
@MainActor
public final class MyaowSoundEffectsService {
    public static let shared = MyaowSoundEffectsService()
    
    private init() {
        setupAudioSession()
    }
    
    private func setupAudioSession() {
        #if os(iOS)
        do {
            try AVAudioSession.sharedInstance().setCategory(.ambient, mode: .default, options: [.mixWithOthers])
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            print("⚠️ [AudioSession] Advertencia de audio ambient: \(error)")
        }
        #endif
    }
    
    // MARK: - Efectos Nítidos para Mensajería & Zumbidos
    
    /// Sonido suave y háptico al enviar mensaje con éxito (Pop sutil)
    public func playMessageSentEffect() {
        AudioServicesPlaySystemSound(1004) // Pop nativo iOS
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.impactOccurred(intensity: 0.7)
    }
    
    /// Sonido armónico al recibir un nuevo mensaje (Tono sutil sin zumbido de fondo)
    public func playMessageReceivedEffect() {
        AudioServicesPlaySystemSound(1007) // Chime corto y elegante
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.impactOccurred(intensity: 0.85)
    }
    
    /// 1. Ronroneo Cálido & Sonoro (Purr Sound Effect para Zumbidos e Interacciones)
    public func playPurrEffect() {
        AudioServicesPlaySystemSound(1057) // Tono armónico cálido
        
        let generator = UIImpactFeedbackGenerator(style: .heavy)
        generator.impactOccurred(intensity: 0.8)
        
        for i in 0..<4 {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(i) * 0.12) {
                let softGen = UIImpactFeedbackGenerator(style: (i % 2 == 0 ? .soft : .medium))
                softGen.impactOccurred(intensity: 0.6)
            }
        }
    }
    
    /// 2. Zumbido con Ronroneo Vibrante (Purr Nudge)
    public func playPurrNudgeEffect() {
        AudioServicesPlaySystemSound(1057)
        let notifGen = UINotificationFeedbackGenerator()
        notifGen.notificationOccurred(.success)
        
        for i in 0..<6 {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(i) * 0.10) {
                let gen = UIImpactFeedbackGenerator(style: .heavy)
                gen.impactOccurred(intensity: 0.75)
            }
        }
    }
    
    /// 3. Zarpazo Eléctrico (Spark / Zap)
    public func playElectricSparkEffect() {
        AudioServicesPlaySystemSound(1104) // Sonido de chispa/tecla corta
        let heavyGen = UIImpactFeedbackGenerator(style: .rigid)
        heavyGen.impactOccurred(intensity: 1.0)
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
            let medGen = UIImpactFeedbackGenerator(style: .light)
            medGen.impactOccurred(intensity: 0.7)
        }
    }
    
    /// 4. Lanzar Ovillo de Lana (Yarn Toss)
    public func playYarnTossEffect() {
        AudioServicesPlaySystemSound(1004)
        let gen = UIImpactFeedbackGenerator(style: .medium)
        gen.impactOccurred()
    }
    
    /// 5. Ofrecer Pescadito (Fish Snack / Crunch)
    public func playFishCrunchEffect() {
        AudioServicesPlaySystemSound(1105)
        let gen = UIImpactFeedbackGenerator(style: .medium)
        gen.impactOccurred(intensity: 0.9)
    }
    
    /// 6. Zumbido / Miau Fuerte (Nudge Buzzer)
    public func playMeowBuzzerEffect() {
        AudioServicesPlaySystemSound(1016) // Sonido de alerta / zumbido activo
        let notifGen = UINotificationFeedbackGenerator()
        notifGen.notificationOccurred(.warning)
    }
    
    /// 7. Radar Ping Blip
    public func playRadarPingEffect() {
        AudioServicesPlaySystemSound(1103)
        let gen = UIImpactFeedbackGenerator(style: .soft)
        gen.impactOccurred(intensity: 0.3)
    }
}
