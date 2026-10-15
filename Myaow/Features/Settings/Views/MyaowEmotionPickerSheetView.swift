//
//  MyaowEmotionPickerSheetView.swift
//  Myaow
//
//  Created for Myaow - "Tecnología que se siente cercana"
//

import SwiftUI

public enum EmotionCategory: String, CaseIterable, Identifiable {
    case all = "Todas"
    case human = "Emociones"
    case playful = "Actitud"
    case status = "Estados"
    
    public var id: String { rawValue }
}

public struct MyaowEmotionPickerSheetView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var identityManager = IdentityManager.shared
    @State private var selectedCategory: EmotionCategory = .all
    
    public init() {}
    
    private var currentCatState: MyaowCatState {
        MyaowCatState(rawValue: identityManager.currentIdentity.avatarStateName) ?? .friendly
    }
    
    private var filteredStates: [MyaowCatState] {
        switch selectedCategory {
        case .all:
            return MyaowCatState.allCases
        case .human:
            return [.happy, .purring, .calm, .friendly, .inLove, .sad, .angry, .surprised, .laughing, .shy, .crying]
        case .playful:
            return [.playful, .curious, .cool, .gossiping, .hungry, .party, .ninja, .thinking, .drunk, .skeptical, .mischievous]
        case .status:
            return [.busy, .exhausted, .bored, .sleeping, .connecting, .connected, .protected, .neutral, .openingEyes]
        }
    }
    
    public var body: some View {
        ZStack {
            MyaowColor.charcoal
                .ignoresSafeArea()
            
            VStack(spacing: 16) {
                // Indicador de arrastre
                Capsule()
                    .fill(MyaowColor.surfaceSecondary)
                    .frame(width: 36, height: 4)
                    .padding(.top, 12)
                
                // 1. Tarjeta Hero con la Emoción Actual en Vivo
                HStack(spacing: 16) {
                    MyaowCatView(
                        state: currentCatState,
                        style: .darkOnOrange,
                        size: 64,
                        isInteractive: true
                    )
                    .shadow(color: MyaowColor.orange.opacity(0.35), radius: 10, x: 0, y: 4)
                    
                    VStack(alignment: .leading, spacing: 3) {
                        Text("EMOCIÓN ACTIVA")
                            .font(.system(size: 10, weight: .bold, design: .rounded))
                            .foregroundColor(MyaowColor.orange)
                            .tracking(0.8)
                        
                        Text(currentCatState.displayName)
                            .font(.system(size: 20, weight: .black, design: .rounded))
                            .foregroundColor(MyaowColor.textPrimary)
                        
                        Text("Visible para tus contactos en el chat y en tu perfil.")
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .foregroundColor(MyaowColor.textSecondary)
                            .lineLimit(1)
                    }
                    
                    Spacer()
                }
                .padding(16)
                .background(MyaowColor.surfaceElevated)
                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .stroke(MyaowColor.borderSubtle, lineWidth: 1)
                )
                .padding(.horizontal, 20)
                
                // 2. Filtros de Categoría
                HStack(spacing: 8) {
                    ForEach(EmotionCategory.allCases) { cat in
                        let isSelected = selectedCategory == cat
                        Button(action: {
                            guard selectedCategory != cat else { return }
                            let generator = UIImpactFeedbackGenerator(style: .light)
                            generator.impactOccurred()
                            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) {
                                selectedCategory = cat
                            }
                        }) {
                            Text(cat.rawValue)
                                .font(.system(size: 12, weight: isSelected ? .bold : .medium, design: .rounded))
                                .foregroundColor(isSelected ? .white : MyaowColor.textSecondary)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 8)
                                .background(isSelected ? MyaowColor.orange : MyaowColor.surface)
                                .clipShape(Capsule())
                        }
                        .buttonStyle(MyaowScaleButtonStyle())
                    }
                }
                .padding(.horizontal, 20)
                
                HStack {
                    Text("31 FORMAS DE SER TÚ").font(.system(size: 10, weight: .bold)).tracking(1.4)
                    Spacer()
                    Text("\(filteredStates.count) expresiones").font(.caption)
                }.foregroundStyle(MyaowColor.textSecondary).padding(.horizontal, 22)
                // 3. Cuadrícula de 3 Columnas con Todas las Emociones
                ScrollView(showsIndicators: false) {
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                        ForEach(filteredStates) { catState in
                            let isSelected = identityManager.currentIdentity.avatarStateName == catState.rawValue
                            
                            Button(action: {
                                guard !isSelected else { return }
                                let generator = UIImpactFeedbackGenerator(style: .medium)
                                generator.impactOccurred()
                                withAnimation(reduceMotion ? nil : .spring(response: 0.34, dampingFraction: 0.82)) {
                                    identityManager.updateAvatarState(catState.rawValue)
                                }
                            }) {
                                VStack(spacing: 8) {
                                    MyaowCatView(
                                        state: catState,
                                        style: .darkOnOrange,
                                        size: 72,
                                        isInteractive: false
                                    )
                                    .scaleEffect(isSelected && !reduceMotion ? 1.08 : 1.0)
                                    
                                    Text(catState.displayName)
                                        .font(.system(size: 11, weight: isSelected ? .bold : .medium, design: .rounded))
                                        .foregroundColor(isSelected ? MyaowColor.orange : MyaowColor.textPrimary)
                                        .lineLimit(1)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(isSelected ? MyaowColor.surfaceElevated : MyaowColor.surface)
                                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                                        .stroke(isSelected ? MyaowColor.orange : MyaowColor.borderSubtle, lineWidth: isSelected ? 2 : 1)
                                )
                                .shadow(color: isSelected ? MyaowColor.orange.opacity(0.3) : Color.clear, radius: 8, x: 0, y: 4)
                            }
                            .buttonStyle(MyaowScaleButtonStyle())
                            .accessibilityAddTraits(isSelected ? .isSelected : [])
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 24)
                }
            }
        }
        .presentationDetents([.fraction(0.72), .large])
    }
}
