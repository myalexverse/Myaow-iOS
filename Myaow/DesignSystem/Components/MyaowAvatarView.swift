//
//  MyaowAvatarView.swift
//  Myaow
//
//  Created for Myaow - "Tecnología que se siente cercana"
//

import SwiftUI

public enum AvatarSource: Equatable {
    case cat(state: MyaowCatState, style: MyaowCatStyle)
    case initials(String, Color)
    case systemIcon(String, Color)
    case image(Image)
    case data(Data)
    
    public static func == (lhs: AvatarSource, rhs: AvatarSource) -> Bool {
        switch (lhs, rhs) {
        case (.cat(let s1, let st1), .cat(let s2, let st2)):
            return s1 == s2 && st1 == st2
        case (.initials(let a, _), .initials(let b, _)):
            return a == b
        case (.systemIcon(let a, _), .systemIcon(let b, _)):
            return a == b
        case (.data(let a), .data(let b)):
            return a == b
        default:
            return false
        }
    }
}

public struct MyaowAvatarView: View {
    public let source: AvatarSource
    public let size: CGFloat
    public let isOnlineMesh: Bool
    public let showStatusBadge: Bool
    
    public init(
        source: AvatarSource = .cat(state: .neutral, style: .darkOnOrange),
        size: CGFloat = 48,
        isOnlineMesh: Bool = true,
        showStatusBadge: Bool = false
    ) {
        self.source = source
        self.size = size
        self.isOnlineMesh = isOnlineMesh
        self.showStatusBadge = showStatusBadge
    }
    
    public var body: some View {
        ZStack(alignment: .bottomTrailing) {
            avatarContent
                .frame(width: size, height: size)
                .clipShape(Circle())
            
            if showStatusBadge {
                Circle()
                    .fill(isOnlineMesh ? MyaowColor.statusGreen : MyaowColor.textTertiary)
                    .frame(width: max(10, size * 0.24), height: max(10, size * 0.24))
                    .overlay(
                        Circle()
                            .stroke(MyaowColor.charcoal, lineWidth: 2)
                    )
                    .offset(x: 2, y: 2)
            }
        }
    }
    
    @ViewBuilder
    private var avatarContent: some View {
        switch source {
        case .cat(let state, let style):
            MyaowCatView(state: state, style: style, size: size)
            
        case .initials(let initials, let bg):
            ZStack {
                Circle().fill(bg)
                Text(initials.prefix(2).uppercased())
                    .font(.system(size: size * 0.4, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
            }
            
        case .systemIcon(let name, let bg):
            ZStack {
                Circle().fill(bg)
                Image(systemName: name)
                    .font(.system(size: size * 0.44, weight: .semibold))
                    .foregroundColor(.white)
            }
            
        case .image(let img):
            img
                .resizable()
                .scaledToFill()
                
        case .data(let data):
            #if canImport(UIKit)
            if let uiImage = UIImage(data: data) {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFill()
            } else {
                MyaowCatView(state: .friendly, style: .darkOnOrange, size: size)
            }
            #else
            MyaowCatView(state: .friendly, style: .darkOnOrange, size: size)
            #endif
        }
    }
}
