//
//  ScheduleMessageModalView.swift
//  Myaow
//
//  Created for Myaow - "Tecnología que se siente cercana"
//

import SwiftUI

public struct ScheduleMessageModalView: View {
    @Environment(\.dismiss) private var dismiss
    public let messageText: String
    public let recipientName: String
    public let onConfirm: (Date) async throws -> Void
    
    @State private var saving = false
    @State private var saveError: String?
    @State private var selectedDate: Date = Calendar.current.date(byAdding: .minute, value: 30, to: Date()) ?? Date()
    @State private var showCustomPicker: Bool = false
    
    public init(messageText: String, recipientName: String, onConfirm: @escaping (Date) async throws -> Void) {
        self.messageText = messageText
        self.recipientName = recipientName
        self.onConfirm = onConfirm
    }
    
    public var body: some View {
        ZStack {
            MyaowColor.charcoal
                .ignoresSafeArea()
            
            VStack(spacing: 20) {
                // Barra de agarre
                Capsule()
                    .fill(MyaowColor.surfaceSecondary)
                    .frame(width: 36, height: 4)
                    .padding(.top, 12)
                
                // Header
                HStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(MyaowColor.orange.opacity(0.15))
                            .frame(width: 44, height: 44)
                        Image(systemName: "clock.badge.checkmark.fill")
                            .font(.system(size: 20))
                            .foregroundColor(MyaowColor.orange)
                    }
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Programar mensaje")
                            .font(.system(size: 18, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                        
                        Text("Para \(recipientName)")
                            .font(.system(size: 12, weight: .regular, design: .rounded))
                            .foregroundColor(Color(hex: "#8E8E93"))
                    }
                    Spacer()
                    Button { dismiss() } label: {
                        Image(systemName: "xmark").font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(MyaowColor.textSecondary).frame(width: 44, height: 44)
                            .background(MyaowColor.surface, in: Circle())
                    }.accessibilityLabel("Cerrar programación")
                }
                .padding(.horizontal, 20)
                
                // Previsualización del Mensaje
                VStack(alignment: .leading, spacing: 6) {
                    Text("MENSAJE")
                        .font(.myaowMicro)
                        .foregroundColor(MyaowColor.textSecondary)
                    
                    HStack {
                        Text(messageText)
                            .font(.system(size: 14, weight: .regular, design: .rounded))
                            .foregroundColor(.white)
                            .lineLimit(2)
                        Spacer()
                    }
                    .padding(14)
                    .background(Color(hex: "#18181A"))
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(Color.white.opacity(0.06), lineWidth: 1)
                    )
                }
                .padding(.horizontal, 20)
                
                // Opciones Rápidas de Horario
                VStack(spacing: 8) {
                    quickOptionRow(title: "En 30 minutos", subtitle: formattedFutureDate(minutes: 30), date: datePlus(minutes: 30))
                    quickOptionRow(title: Calendar.current.component(.hour, from: Date()) < 18 ? "Hoy a las 18:00" : "Próximas 18:00", subtitle: "18:00", date: dateTodayAt(hour: 18))
                    quickOptionRow(title: "Mañana por la mañana", subtitle: "09:00", date: dateTomorrowAt(hour: 9))
                }
                .padding(.horizontal, 20)
                
                // Selector de Fecha Personalizada
                if showCustomPicker {
                    DatePicker("", selection: $selectedDate, in: Date()...Date().addingTimeInterval(30 * 86400), displayedComponents: [.date, .hourAndMinute])
                        .datePickerStyle(.wheel)
                        .labelsHidden()
                        .colorScheme(.dark)
                        .frame(maxHeight: 140)
                        .clipped()
                        .padding(.horizontal, 20)
                } else {
                    Button(action: {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                            showCustomPicker = true
                        }
                    }) {
                        HStack {
                            Image(systemName: "calendar")
                                .foregroundColor(MyaowColor.orange)
                            Text("Seleccionar fecha y hora exacta")
                                .font(.system(size: 14, weight: .medium, design: .rounded))
                                .foregroundColor(.white)
                            Spacer()
                            Image(systemName: "chevron.down")
                                .font(.system(size: 12))
                                .foregroundColor(Color(hex: "#8E8E93"))
                        }
                        .padding(14)
                        .background(Color(hex: "#18181A"))
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .padding(.horizontal, 20)
                }
                
                VStack(alignment: .leading, spacing: 5) {
                    Text(selectedDate.formatted(date: .abbreviated, time: .shortened))
                        .font(.system(size: 14, weight: .semibold)).foregroundStyle(.white)
                    Text("Hora de tu dispositivo · \(TimeZone.current.identifier.replacingOccurrences(of: "_", with: " "))")
                        .font(.system(size: 12)).foregroundStyle(MyaowColor.textSecondary)
                }.frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 20)
                Spacer(minLength: 0)
                
                // Botón de Confirmación
                Button(action: {
                    guard !saving else { return }
                    saving = true
                    Task {
                        defer { saving = false }
                        do { try await onConfirm(selectedDate); dismiss() }
                        catch { saveError = error.localizedDescription }
                    }
                }) {
                    HStack(spacing: 8) {
                        Image(systemName: "timer")
                        Text(saving ? "Guardando…" : "Programar mensaje")
                    }
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 15)
                    .background(MyaowColor.orange)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .shadow(color: MyaowColor.orange.opacity(0.35), radius: 8, x: 0, y: 4)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 24)
            }
        }
        .disabled(saving)
        .interactiveDismissDisabled(saving)
        .alert("No se confirmó la programación", isPresented: Binding(get: { saveError != nil }, set: { if !$0 { saveError = nil } })) {
            Button("Entendido", role: .cancel) {}
        } message: { Text(saveError ?? "") }
        .presentationDetents([.large])
    }
    
    private func quickOptionRow(title: String, subtitle: String, date: Date) -> some View {
        let isSelected = Calendar.current.isDate(selectedDate, equalTo: date, toGranularity: .minute)
        
        return Button(action: {
            let gen = UIImpactFeedbackGenerator(style: .light)
            gen.impactOccurred()
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                selectedDate = date
                showCustomPicker = false
            }
        }) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 14, weight: isSelected ? .bold : .medium, design: .rounded))
                        .foregroundColor(.white)
                    Text(subtitle)
                        .font(.system(size: 12, weight: .regular, design: .rounded))
                        .foregroundColor(Color(hex: "#8E8E93"))
                }
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(MyaowColor.orange)
                }
            }
            .padding(12)
            .background(isSelected ? Color(hex: "#261D16") : Color(hex: "#18181A"))
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(isSelected ? MyaowColor.orange.opacity(0.5) : Color.white.opacity(0.05), lineWidth: 1)
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    private func datePlus(minutes: Int) -> Date {
        Calendar.current.date(byAdding: .minute, value: minutes, to: Date()) ?? Date()
    }
    
    private func dateTodayAt(hour: Int) -> Date {
        let now = Date()
        var components = Calendar.current.dateComponents([.year, .month, .day], from: now)
        components.hour = hour
        components.minute = 0
        let target = Calendar.current.date(from: components) ?? now
        if target <= now {
            return Calendar.current.date(byAdding: .day, value: 1, to: target) ?? now
        }
        return target
    }
    
    private func dateTomorrowAt(hour: Int) -> Date {
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: Date()) ?? Date()
        var components = Calendar.current.dateComponents([.year, .month, .day], from: tomorrow)
        components.hour = hour
        components.minute = 0
        return Calendar.current.date(from: components) ?? tomorrow
    }
    
    private func formattedFutureDate(minutes: Int) -> String {
        let d = datePlus(minutes: minutes)
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f.string(from: d)
    }
}

struct ScheduledMessagesListView: View {
    @Environment(\.dismiss) private var dismiss
    let conversationId: String
    @State private var service = ScheduledMessagesService.shared
    @State private var busy: UUID?
    @State private var error: String?
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Los mensajes confirmados se envían a la hora elegida aunque cierres la app. “En el servidor” significa que esperan la conexión del destinatario; no confirma la lectura.")
                        .font(.system(size: 14)).foregroundStyle(MyaowColor.textSecondary)
                    if let issue = service.lastError { Text(issue).foregroundStyle(.orange) }
                    let items = service.scheduledMessagesFor(conversationId: conversationId)
                    if items.isEmpty && service.isRefreshing { ProgressView("Consultando mensajes…").tint(MyaowColor.orange) }
                    else if items.isEmpty {
                        MyaowEmptyState(title: service.lastError == nil ? "Nada programado" : "No pudimos cargar la lista",
                            message: service.lastError == nil ? "Escribe un mensaje y abre las opciones de programación." : "Vuelve a conectar para consultar los mensajes guardados en el servidor.",
                            symbol: service.lastError == nil ? "clock" : "wifi.slash", actionTitle: service.lastError == nil ? nil : "Volver a intentar",
                            action: { Task { await service.refresh() } })
                    }
                    ForEach(items) { item in
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Label(item.state == "delivered" ? "Entregado" : item.state == "queued" ? "En el servidor" : item.state == "attention" ? "Requiere revisión" : item.state == "unconfirmed" ? "Sin confirmar" : "Programado", systemImage: "clock")
                                    .font(.system(size: 12, weight: .semibold)).foregroundStyle(MyaowColor.orange)
                                Spacer()
                            }
                            Text(item.text).font(.system(size: 16)).textSelection(.enabled)
                            Text(item.scheduledDate.formatted(date: .abbreviated, time: .shortened)).font(.system(size: 12)).foregroundStyle(MyaowColor.textSecondary)
                            if item.state == "attention" { Text("Cambió el grupo o los permisos. Cancela y programa otra vez para revisar los destinatarios.").font(.system(size: 13)).foregroundStyle(MyaowColor.textSecondary) }
                            if item.state == "unconfirmed" {
                                Button("Confirmar programación") { perform(item.id) { try await service.retryConfirmation(id: item.id) } }.tint(MyaowColor.orange)
                            }
                            if item.state != "queued" && item.state != "delivered" {
                                Button("Cancelar mensaje", role: .destructive) { perform(item.id) { try await service.cancelScheduledMessage(id: item.id) } }
                            }
                        }.padding(18).background(MyaowColor.surface, in: RoundedRectangle(cornerRadius: 20)).disabled(busy != nil)
                    }
                }.padding(22)
            }.background(MyaowColor.background).foregroundStyle(.white)
                .navigationTitle("Mensajes programados").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Listo") { dismiss() } } }
                .refreshable { await service.refresh() }
                .task {
                    while !Task.isCancelled {
                        if UIApplication.shared.applicationState == .active { await service.refresh() }
                        do { try await Task.sleep(for: .seconds(OnlineMessagingService.shared.isRealtimeActive ? 60 : 15)) } catch { break }
                    }
                }
                .onChange(of: OnlineMessagingService.shared.collaborationRevision) { _, _ in Task { await service.refresh() } }
                .alert("No se completó la acción", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
                    Button("Entendido", role: .cancel) {}
                } message: { Text(error ?? "") }
        }.preferredColorScheme(.dark)
    }
    private func perform(_ id: UUID, operation: @escaping () async throws -> Void) {
        guard busy == nil else { return }
        busy = id
        Task { defer { busy = nil }; do { try await operation() } catch { self.error = error.localizedDescription } }
    }
}
