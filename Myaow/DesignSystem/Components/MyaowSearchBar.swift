//
//  MyaowSearchBar.swift
//  Myaow
//
//  Created for Myaow - "Tecnología que se siente cercana"
//

import SwiftUI

public struct MyaowSearchBar: View {
    @Binding public var text: String
    public var placeholder: String
    
    public init(text: Binding<String>, placeholder: String = "Buscar") {
        self._text = text
        self.placeholder = placeholder
    }
    
    public var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(MyaowColor.textSecondary)
            
            TextField(placeholder, text: $text)
                .font(.myaowBody)
                .foregroundColor(MyaowColor.textPrimary)
                .accentColor(MyaowColor.orange)
            
            if !text.isEmpty {
                Button(action: { text = "" }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 15))
                        .foregroundColor(MyaowColor.textSecondary)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(MyaowColor.surface)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(MyaowColor.borderSubtle, lineWidth: 1)
        )
    }
}
