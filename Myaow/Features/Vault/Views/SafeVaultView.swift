//
//  SafeVaultView.swift
//  Myaow
//
//  Created for Myaow - "Tecnología que se siente cercana"
//

import SwiftUI
import SwiftData

public struct SafeVaultView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(filter: #Predicate<MessageModel> { $0.isSavedToVault }, sort: \.timestamp, order: .reverse)
    private var vaultMessages: [MessageModel]
    
    @State private var searchText: String = ""
    @State private var selectedFilter: String = "Todo"
    
    private let filters = ["Todo", "🔑 Claves & Passwords", "🔗 Enlaces & Cuentas", "📝 Notas Seguras"]
    
    private var filteredVault: [MessageModel] {
        var list = vaultMessages
        
        if selectedFilter == "🔑 Claves & Passwords" {
            list = list.filter { $0.text.lowercased().contains("clave") || $0.text.lowercased().contains("pass") || $0.text.lowercased().contains("código") || $0.text.lowercased().contains("pin") }
        } else if selectedFilter == "🔗 Enlaces & Cuentas" {
            list = list.filter { $0.text.lowercased().contains("http") || $0.text.lowercased().contains("@") || $0.text.lowercased().contains(".com") }
        }
        
        if !searchText.isEmpty {
            list = list.filter { $0.text.localizedCaseInsensitiveContains(searchText) }
        }
        
        return list
    }
    
    public init() {}
    
    public var body: some View {
        NavigationStack {
            ZStack {
                MyaowColor.charcoal
                    .ignoresSafeArea()
                
                VStack(spacing: 16) {
                    // Header Informativo
                    HStack(spacing: 12) {
                        ZStack {
                            Circle()
                                .fill(MyaowColor.orange.opacity(0.18))
                                .frame(width: 44, height: 44)
                            Image(systemName: "lock.shield.fill")
                                .font(.system(size: 20))
                                .foregroundColor(MyaowColor.orange)
                        }
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Baúl Seguro Personal")
                                .font(.myaowHeadline)
                                .foregroundColor(MyaowColor.textPrimary)
                            Text("Tus claves, contraseñas y mensajes destacados protegidos localmente.")
                                .font(.myaowMicro)
                                .foregroundColor(MyaowColor.textSecondary)
                        }
                        Spacer()
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    
                    // Barra de Búsqueda
                    HStack(spacing: 8) {
                        Image(systemName: "magnifyingglass")
                            .foregroundColor(MyaowColor.textTertiary)
                        
                        TextField("Buscar claves, tokens o notas...", text: $searchText)
                            .font(.myaowBody)
                            .foregroundColor(MyaowColor.textPrimary)
                    }
                    .padding(12)
                    .background(MyaowColor.surface)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .padding(.horizontal, 16)
                    
                    // Filtros
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(filters, id: \.self) { filter in
                                Button(action: {
                                    selectedFilter = filter
                                }) {
                                    Text(filter)
                                        .font(.myaowCaptionMedium)
                                        .foregroundColor(selectedFilter == filter ? .white : MyaowColor.textSecondary)
                                        .padding(.horizontal, 14)
                                        .padding(.vertical, 8)
                                        .background(selectedFilter == filter ? MyaowColor.orange : MyaowColor.surface)
                                        .clipShape(Capsule())
                                }
                            }
                        }
                        .padding(.horizontal, 16)
                    }
                    
                    if filteredVault.isEmpty {
                        emptyVaultView
                    } else {
                        List {
                            ForEach(filteredVault) { item in
                                vaultItemRow(item)
                                    .listRowBackground(Color.clear)
                                    .listRowSeparator(.hidden)
                                    .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                            }
                        }
                        .listStyle(.plain)
                        .scrollContentBackground(.hidden)
                    }
                }
            }
            .navigationTitle("Baúl Seguro (🔐 \(vaultMessages.count))")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cerrar") {
                        dismiss()
                    }
                    .font(.myaowCallout)
                    .foregroundColor(MyaowColor.orange)
                }
            }
        }
    }
    
    private var emptyVaultView: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "lock.slash.fill")
                .font(.system(size: 44))
                .foregroundColor(MyaowColor.textTertiary)
            
            Text("Tu Baúl está Vacío")
                .font(.myaowHeadline)
                .foregroundColor(MyaowColor.textPrimary)
            
            Text("En cualquier chat con tu jefe o amigos, mantén presionado un mensaje con una clave o dato importante y toca 'Guardar en mi Baúl Seguro 🔐'.")
                .font(.myaowBody)
                .multilineTextAlignment(.center)
                .foregroundColor(MyaowColor.textSecondary)
                .padding(.horizontal, 32)
            
            Spacer()
        }
    }
    
    private func vaultItemRow(_ item: MessageModel) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "lock.fill")
                        .foregroundColor(MyaowColor.orange)
                        .font(.system(size: 11))
                    
                    Text(item.senderName)
                        .font(.myaowCaptionMedium)
                        .foregroundColor(MyaowColor.textSecondary)
                }
                
                Spacer()
                
                Text(formatDate(item.timestamp))
                    .font(.myaowMicro)
                    .foregroundColor(MyaowColor.textTertiary)
            }
            
            Text(item.text)
                .font(.system(size: 15, weight: .regular, design: .monospaced))
                .foregroundColor(MyaowColor.textPrimary)
                .textSelection(.enabled)
            
            HStack(spacing: 14) {
                Button(action: {
                    UIPasteboard.general.string = item.text
                    let generator = UINotificationFeedbackGenerator()
                    generator.notificationOccurred(.success)
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "doc.on.doc")
                        Text("Copiar Clave")
                    }
                    .font(.myaowMicro)
                    .foregroundColor(MyaowColor.orange)
                }
                
                Spacer()
                
                Button(action: {
                    withAnimation {
                        item.isSavedToVault = false
                        try? modelContext.save()
                    }
                }) {
                    Text("Quitar")
                        .font(.myaowMicro)
                        .foregroundColor(MyaowColor.textTertiary)
                }
            }
            .padding(.top, 4)
        }
        .padding(14)
        .background(MyaowColor.surface)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(MyaowColor.borderSubtle, lineWidth: 1)
        )
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "dd/MM/yyyy HH:mm"
        return formatter.string(from: date)
    }
}

#Preview {
    SafeVaultView()
        .modelContainer(for: [MessageModel.self], inMemory: true)
}
