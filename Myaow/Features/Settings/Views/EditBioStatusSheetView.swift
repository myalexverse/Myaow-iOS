//
//  EditBioStatusSheetView.swift
//  Myaow
//
//  Created for Myaow - "Tecnología que se siente cercana"
//

import SwiftUI

public struct EditBioStatusSheetView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var identityManager = IdentityManager.shared
    @State private var statusInput: String = ""
    
    private let quickSuggestions = [
        "Disponible para hablar 😸",
        "En modo concentrado 🧠",
        "Paseando un rato 🌿",
        "En el trabajo 💻",
        "Con ganas de un café ☕️",
        "Desconectado del mundo 🌙"
    ]
    
    public init() {}
    
    public var body: some View {
        NavigationStack {
            ZStack {
                MyaowColor.charcoal
                    .ignoresSafeArea()
                
                VStack(spacing: 20) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("TU ESTADO ACTUAL")
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .foregroundColor(MyaowColor.orange)
                            .tracking(0.6)
                        
                        TextField("¿Qué estás haciendo o cómo te sientes?", text: $statusInput)
                            .font(.system(size: 16, weight: .medium, design: .rounded))
                            .foregroundColor(.white)
                            .padding(14)
                            .background(MyaowColor.surfaceElevated)
                            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .stroke(MyaowColor.borderSubtle, lineWidth: 1)
                            )
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 16)
                    
                    VStack(alignment: .leading, spacing: 10) {
                        Text("SUGERENCIAS RÁPIDAS")
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .foregroundColor(MyaowColor.textSecondary)
                        
                        ForEach(quickSuggestions, id: \.self) { suggestion in
                            Button(action: {
                                statusInput = suggestion
                            }) {
                                HStack {
                                    Text(suggestion)
                                        .font(.system(size: 14, weight: .medium, design: .rounded))
                                        .foregroundColor(.white)
                                    Spacer()
                                    Image(systemName: "arrow.up.left")
                                        .font(.system(size: 12))
                                        .foregroundColor(MyaowColor.textTertiary)
                                }
                                .padding(.vertical, 10)
                                .padding(.horizontal, 14)
                                .background(MyaowColor.surface)
                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                    }
                    .padding(.horizontal, 20)
                    
                    Spacer()
                    
                    Button(action: {
                        saveStatus()
                    }) {
                        Text("Guardar Estado")
                            .font(.system(size: 16, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(MyaowColor.orange)
                            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 16)
                }
            }
            .navigationTitle("Mi Estado")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") {
                        dismiss()
                    }
                    .foregroundColor(MyaowColor.orange)
                }
            }
            .onAppear {
                statusInput = identityManager.currentIdentity.bioStatus ?? "Disponible en Myaow"
            }
        }
    }
    
    private func saveStatus() {
        let gen = UIImpactFeedbackGenerator(style: .medium)
        gen.impactOccurred()
        
        identityManager.currentIdentity.bioStatus = statusInput.trimmingCharacters(in: .whitespacesAndNewlines)
        dismiss()
    }
}
