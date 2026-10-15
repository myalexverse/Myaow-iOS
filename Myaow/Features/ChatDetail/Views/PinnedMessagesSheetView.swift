//
//  PinnedMessagesSheetView.swift
//  Myaow
//
//  Created for Myaow - "Tecnología que se siente cercana"
//

import SwiftUI
import SwiftData

public struct PinnedMessagesSheetView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    
    public var conversation: ConversationModel
    public var onSelectMessage: ((MessageModel) -> Void)?
    
    @State private var searchText: String = ""
    @State private var selectedFilter: String = "Todos"
    
    private let filterCategories = ["Todos", "🔐 Claves / Códigos", "💼 Tareas", "📌 Destacados"]
    
    private var filteredPinnedMessages: [MessageModel] {
        var list = conversation.messages.filter { $0.isPinned }
        
        if selectedFilter == "🔐 Claves / Códigos" {
            list = list.filter { $0.text.lowercased().contains("clave") || $0.text.lowercased().contains("password") || $0.text.lowercased().contains("código") || $0.text.lowercased().contains("http") || $0.text.lowercased().contains("key") }
        } else if selectedFilter == "💼 Tareas" {
            list = list.filter { $0.text.lowercased().contains("hacer") || $0.text.lowercased().contains("tarea") || $0.text.lowercased().contains("revisar") || $0.text.lowercased().contains("reunión") }
        }
        
        if !searchText.isEmpty {
            list = list.filter { $0.text.localizedCaseInsensitiveContains(searchText) }
        }
        
        return list.sorted(by: { ($0.pinnedTimestamp ?? $0.timestamp) > ($1.pinnedTimestamp ?? $1.timestamp) })
    }
    
    public var body: some View {
        NavigationStack {
            ZStack {
                MyaowColor.charcoal
                    .ignoresSafeArea()
                
                VStack(spacing: 16) {
                    // Barra de Búsqueda
                    HStack(spacing: 8) {
                        Image(systemName: "magnifyingglass")
                            .foregroundColor(MyaowColor.textTertiary)
                        
                        TextField("Buscar en anclados y claves...", text: $searchText)
                            .font(.myaowBody)
                            .foregroundColor(MyaowColor.textPrimary)
                    }
                    .padding(12)
                    .background(MyaowColor.surface)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    
                    // Categorías de Filtro Rápido
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(filterCategories, id: \.self) { cat in
                                Button(action: {
                                    selectedFilter = cat
                                }) {
                                    Text(cat)
                                        .font(.myaowCaptionMedium)
                                        .foregroundColor(selectedFilter == cat ? .white : MyaowColor.textSecondary)
                                        .padding(.horizontal, 14)
                                        .padding(.vertical, 8)
                                        .background(selectedFilter == cat ? MyaowColor.orange : MyaowColor.surface)
                                        .clipShape(Capsule())
                                }
                            }
                        }
                        .padding(.horizontal, 16)
                    }
                    
                    if filteredPinnedMessages.isEmpty {
                        emptyStateView
                    } else {
                        List {
                            ForEach(filteredPinnedMessages) { msg in
                                pinnedMessageRow(msg)
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
            .navigationTitle("Mensajes Anclados (📌 \(conversation.pinnedMessages.count))")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Listo") {
                        dismiss()
                    }
                    .font(.myaowCallout)
                    .foregroundColor(MyaowColor.orange)
                }
            }
        }
    }
    
    private var emptyStateView: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "pin.slash")
                .font(.system(size: 44))
                .foregroundColor(MyaowColor.textTertiary)
            
            Text("Sin Mensajes Anclados")
                .font(.myaowHeadline)
                .foregroundColor(MyaowColor.textPrimary)
            
            Text("Mantén presionado cualquier mensaje importante en el chat y toca 'Anclar Mensaje' para guardarlo aquí a la mano.")
                .font(.myaowBody)
                .multilineTextAlignment(.center)
                .foregroundColor(MyaowColor.textSecondary)
                .padding(.horizontal, 32)
            
            Spacer()
        }
    }
    
    private func pinnedMessageRow(_ msg: MessageModel) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "pin.fill")
                        .foregroundColor(MyaowColor.orange)
                        .font(.system(size: 11))
                    
                    Text(msg.senderName)
                        .font(.myaowCaptionMedium)
                        .foregroundColor(MyaowColor.textSecondary)
                }
                
                Spacer()
                
                Text(formatDate(msg.timestamp))
                    .font(.myaowMicro)
                    .foregroundColor(MyaowColor.textTertiary)
            }
            
            Text(msg.text)
                .font(.myaowBody)
                .foregroundColor(MyaowColor.textPrimary)
                .textSelection(.enabled)
            
            HStack(spacing: 12) {
                Button(action: {
                    UIPasteboard.general.string = msg.text
                    let generator = UIImpactFeedbackGenerator(style: .light)
                    generator.impactOccurred()
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "doc.on.doc")
                        Text("Copiar")
                    }
                    .font(.myaowMicro)
                    .foregroundColor(MyaowColor.textSecondary)
                }
                
                Button(action: {
                    dismiss()
                    onSelectMessage?(msg)
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.up.left.and.arrow.down.right")
                        Text("Ir al Chat")
                    }
                    .font(.myaowMicro)
                    .foregroundColor(MyaowColor.orange)
                }
                
                Spacer()
                
                Button(action: {
                    withAnimation {
                        msg.isPinned = false
                        try? modelContext.save()
                    }
                }) {
                    Text("Desanclar")
                        .font(.myaowMicro)
                        .foregroundColor(MyaowColor.statusRed)
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
