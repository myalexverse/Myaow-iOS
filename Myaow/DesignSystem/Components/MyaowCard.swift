//
//  MyaowCard.swift
//  Myaow
//
//  Created for Myaow - "Tecnología que se siente cercana"
//

import SwiftUI

public struct MyaowCard<Content: View>: View {
    public let cornerRadius: CGFloat
    public let padding: CGFloat
    public let backgroundColor: Color
    public let content: () -> Content
    
    public init(
        cornerRadius: CGFloat = 20,
        padding: CGFloat = 16,
        backgroundColor: Color = MyaowColor.surface,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.cornerRadius = cornerRadius
        self.padding = padding
        self.backgroundColor = backgroundColor
        self.content = content
    }
    
    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            content()
        }
        .padding(padding)
        .background(backgroundColor)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .stroke(MyaowColor.borderSubtle, lineWidth: 1)
        )
    }
}
