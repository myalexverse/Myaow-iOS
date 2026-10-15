//
//  MomentsReelView.swift
//  Myaow
//
//  Created for Myaow - "Tecnología que se siente cercana"
//

import SwiftUI
import SwiftData

public struct MomentsReelView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \MomentModel.createdAt, order: .reverse) private var allMoments: [MomentModel]
    
    @State private var identityManager = IdentityManager.shared
    @State private var showingCreateMomentSheet = false
    @State private var selectedMomentToView: MomentModel? = nil
    
    public init() {}
    
    private var activeMoments: [MomentModel] {
        allMoments.filter { !$0.isExpired }
    }
    
    private var myActiveMoments: [MomentModel] {
        activeMoments.filter { $0.isMine || $0.authorMyaowId == identityManager.currentIdentity.myaowId }
    }
    
    private var contactsMoments: [MomentModel] {
        activeMoments.filter { !$0.isMine && $0.authorMyaowId != identityManager.currentIdentity.myaowId }
    }
    
    private var currentCatState: MyaowCatState {
        MyaowCatState(rawValue: identityManager.currentIdentity.avatarStateName) ?? .friendly
    }
    
    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("MOMENTOS")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundColor(MyaowColor.orange)
                    .tracking(0.6)
                
                Text("• Comparte con tu gente")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundColor(MyaowColor.textTertiary)
                
                Spacer()
                
                if !activeMoments.isEmpty {
                    Text("\(activeMoments.count) activos")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .foregroundColor(MyaowColor.textSecondary)
                }
            }
            .padding(.horizontal, 24)
            
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 14) {
                    // 1. Botón "+ Tu Momento" / Ver Mi Momento
                    Button(action: {
                        let gen = UIImpactFeedbackGenerator(style: .medium)
                        gen.impactOccurred()
                        if let myMoment = myActiveMoments.first {
                            selectedMomentToView = myMoment
                        } else {
                            showingCreateMomentSheet = true
                        }
                    }) {
                        VStack(spacing: 6) {
                            ZStack {
                                if !myActiveMoments.isEmpty {
                                    // Aro de Momento Activo
                                    Circle()
                                        .stroke(
                                            LinearGradient(
                                                colors: [MyaowColor.orange, Color(hex: "FF9500")],
                                                startPoint: .topLeading,
                                                endPoint: .bottomTrailing
                                            ),
                                            lineWidth: 2.2
                                        )
                                        .frame(width: 62, height: 62)
                                } else {
                                    Circle()
                                        .stroke(Color.white.opacity(0.12), lineWidth: 1.5)
                                        .frame(width: 60, height: 60)
                                }
                                
                                MyaowCatView(
                                    state: currentCatState,
                                    style: .darkOnOrange,
                                    size: 46,
                                    isInteractive: false
                                )
                                
                                // Botón '+' pequeño si no hay momento o para añadir más
                                VStack {
                                    Spacer()
                                    HStack {
                                        Spacer()
                                        ZStack {
                                            Circle()
                                                .fill(MyaowColor.orange)
                                                .frame(width: 20, height: 20)
                                                .overlay(
                                                    Circle().stroke(MyaowColor.charcoal, lineWidth: 2)
                                                )
                                            
                                            Image(systemName: "plus")
                                                .font(.system(size: 10, weight: .bold))
                                                .foregroundColor(.white)
                                        }
                                    }
                                }
                                .frame(width: 58, height: 58)
                            }
                            
                            Text("Tu momento")
                                .font(.system(size: 11, weight: .semibold, design: .rounded))
                                .foregroundColor(myActiveMoments.isEmpty ? MyaowColor.textSecondary : .white)
                                .lineLimit(1)
                            
                            Text(myActiveMoments.isEmpty ? "Añadir" : (myActiveMoments.first?.formattedTimeAgo ?? ""))
                                .font(.system(size: 9, weight: .regular, design: .rounded))
                                .foregroundColor(MyaowColor.textTertiary)
                        }
                        .frame(width: 68)
                    }
                    .buttonStyle(PlainButtonStyle())
                    
                    // 2. Momentos de Contactos
                    ForEach(contactsMoments) { moment in
                        let catState = MyaowCatState(rawValue: moment.authorAvatarCatState) ?? .friendly
                        
                        Button(action: {
                            let gen = UIImpactFeedbackGenerator(style: .light)
                            gen.impactOccurred()
                            selectedMomentToView = moment
                        }) {
                            VStack(spacing: 6) {
                                ZStack {
                                    // Aro Gradiente Unread / Transperente Seen
                                    Circle()
                                        .stroke(
                                            moment.isSeen ?
                                            LinearGradient(colors: [Color.white.opacity(0.18)], startPoint: .top, endPoint: .bottom) :
                                            LinearGradient(colors: [MyaowColor.orange, Color(hex: "FF2D55")], startPoint: .topLeading, endPoint: .bottomTrailing),
                                            lineWidth: moment.isSeen ? 1.5 : 2.4
                                        )
                                        .frame(width: 62, height: 62)
                                    
                                    MyaowCatView(
                                        state: catState,
                                        style: .darkOnOrange,
                                        size: 46,
                                        isInteractive: false
                                    )
                                }
                                
                                Text(moment.authorDisplayName)
                                    .font(.system(size: 11, weight: moment.isSeen ? .medium : .bold, design: .rounded))
                                    .foregroundColor(moment.isSeen ? MyaowColor.textSecondary : .white)
                                    .lineLimit(1)
                                
                                Text(moment.formattedTimeAgo)
                                    .font(.system(size: 9, weight: .regular, design: .rounded))
                                    .foregroundColor(MyaowColor.textTertiary)
                            }
                            .frame(width: 68)
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 4)
            }
        }
        .sheet(isPresented: $showingCreateMomentSheet) {
            CreateMomentSheetView()
        }
        .fullScreenCover(item: $selectedMomentToView) { moment in
            MomentViewerModalView(moment: moment)
        }
        .onAppear {
            fetchRemoteMoments()
        }
    }
    
    private func fetchRemoteMoments() {
        Task {
            let host = OnlineMessagingService.shared.relayHost
                .replacingOccurrences(of: "ws://", with: "")
                .replacingOccurrences(of: "http://", with: "")
            let myId = IdentityManager.shared.currentIdentity.myaowId
            guard let url = URL(string: "http://\(host)/api/v1/moments/feed/\(myId)") else { return }
            
            do {
                let (data, _) = try await URLSession.shared.data(from: url)
                guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let moments = json["moments"] as? [[String: Any]] else { return }
                
                await MainActor.run {
                    for m in moments {
                        let momentId = (m["id"] as? String) ?? UUID().uuidString
                        // Skip if already exists locally
                        if allMoments.contains(where: { $0.id == momentId }) { continue }
                        
                        let formatter = ISO8601DateFormatter()
                        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                        
                        // Fallback formatter for strings without fractional seconds
                        let fallbackFormatter = ISO8601DateFormatter()
                        
                        let expiresAtStr = m["expires_at"] as? String ?? ""
                        let createdAtStr = m["created_at"] as? String ?? ""
                        
                        let expiresAt = formatter.date(from: expiresAtStr) ?? fallbackFormatter.date(from: expiresAtStr) ?? Date().addingTimeInterval(86400)
                        let createdAt = formatter.date(from: createdAtStr) ?? fallbackFormatter.date(from: createdAtStr) ?? Date()
                        
                        let moment = MomentModel(
                            id: momentId,
                            authorMyaowId: (m["author_id"] as? String) ?? "",
                            authorDisplayName: (m["author_name"] as? String) ?? "Anónimo",
                            captionText: (m["caption"] as? String) ?? "",
                            catEmotionRaw: (m["cat_emotion"] as? String) ?? "friendly",
                            backgroundGradientIndex: (m["background_index"] as? Int) ?? 0,
                            createdAt: createdAt,
                            expiresAt: expiresAt,
                            isSeen: false,
                            isMine: false
                        )
                        moment.authorAvatarCatState = (m["author_avatar_state"] as? String) ?? "friendly"
                        
                        // Download media if available
                        if let mediaUrlStr = m["media_url"] as? String, !mediaUrlStr.isEmpty {
                            Task {
                                if let mediaData = await MediaUploadService.shared.downloadMedia(from: mediaUrlStr) {
                                    await MainActor.run {
                                        moment.mediaData = mediaData
                                        try? modelContext.save()
                                    }
                                }
                            }
                        }
                        
                        modelContext.insert(moment)
                    }
                    try? modelContext.save()
                }
            } catch {
                print("⚠️ [Moments] Error fetching remote moments: \(error)")
            }
        }
    }
}
