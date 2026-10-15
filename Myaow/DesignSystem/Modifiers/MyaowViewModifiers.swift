//
//  MyaowViewModifiers.swift
//  Myaow
//
//  Created for Myaow - "Tecnología que se siente cercana"
//

import SwiftUI

public struct MyaowScreenBackground: ViewModifier {
    public func body(content: Content) -> some View {
        ZStack {
            MyaowColor.charcoal
                .ignoresSafeArea()
            
            content
        }
        .preferredColorScheme(.dark)
    }
}

public extension View {
    func myaowBackground() -> some View {
        self.modifier(MyaowScreenBackground())
    }
}
