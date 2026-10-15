//
//  ProfileCardView.swift
//  Myaow
//
//  Created for Myaow - "Tecnología que se siente cercana"
//

import SwiftUI

public struct ProfileCardView: View {
    public let identity: UserIdentity
    public var onEdit: () -> Void
    
    public var body: some View {
        Button(action: {
            let generator = UIImpactFeedbackGenerator(style: .light)
            generator.impactOccurred()
            onEdit()
        }) {
            HStack(spacing: 16) {
                if let data = identity.avatarImageData {
                    MyaowAvatarView(source: .data(data), size: 58)
                } else {
                    let catState = MyaowCatState(rawValue: identity.avatarStateName) ?? .happy
                    MyaowAvatarView(
                        source: .cat(state: catState, style: .darkOnOrange),
                        size: 58
                    )
                }
                
                VStack(alignment: .leading, spacing: 3) {
                    Text(identity.displayName)
                        .font(.myaowHeadline)
                        .foregroundColor(MyaowColor.textPrimary)
                    
                    if let username = identity.customUsername, !username.isEmpty {
                        Text("@\(username)")
                            .font(.myaowCaption)
                            .foregroundColor(MyaowColor.orange)
                    }
                    
                    Text("ID: \(identity.myaowId)")
                        .font(.myaowMono)
                        .foregroundColor(MyaowColor.textSecondary)
                }
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(MyaowColor.textTertiary)
            }
            .padding(16)
            .background(MyaowColor.surface)
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(MyaowColor.borderSubtle, lineWidth: 1)
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
}
