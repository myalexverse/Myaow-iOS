//
//  MyaowPillButton.swift
//  Myaow
//
//  Created for Myaow - "Tecnología que se siente cercana"
//

import SwiftUI

public enum MyaowButtonStyle {
    case primary      // Naranja Myaow con texto blanco/oscuro
    case secondary    // Superficie elevada (#242424) con borde sutil
    case ghost        // Fondo transparente con texto naranja o blanco
    case destructive  // Rojo sutil
}

public struct MyaowPillButton: View {
    public let title: String
    public let icon: String?
    public let style: MyaowButtonStyle
    public let isFullWidth: Bool
    public let action: () -> Void
    
    public init(
        _ title: String,
        icon: String? = nil,
        style: MyaowButtonStyle = .primary,
        isFullWidth: Bool = false,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.icon = icon
        self.style = style
        self.isFullWidth = isFullWidth
        self.action = action
    }
    
    public var body: some View {
        Button(action: {
            let generator = UIImpactFeedbackGenerator(style: .light)
            generator.impactOccurred()
            action()
        }) {
            HStack(spacing: 8) {
                if let icon = icon {
                    Image(systemName: icon)
                        .font(.system(size: 15, weight: .semibold))
                }
                
                Text(title)
                    .font(.myaowCallout)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 13)
            .frame(maxWidth: isFullWidth ? .infinity : nil)
            .background(backgroundView)
            .foregroundColor(foregroundColor)
            .clipShape(Capsule())
            .overlay(
                Capsule()
                    .stroke(borderColor, lineWidth: 1)
            )
        }
        .buttonStyle(MyaowScaleButtonStyle())
    }
    
    @ViewBuilder
    private var backgroundView: some View {
        switch style {
        case .primary:
            MyaowColor.orange
        case .secondary:
            MyaowColor.surfaceElevated
        case .ghost:
            Color.clear
        case .destructive:
            MyaowColor.statusRed.opacity(0.18)
        }
    }
    
    private var foregroundColor: Color {
        switch style {
        case .primary:
            return .white
        case .secondary:
            return MyaowColor.textPrimary
        case .ghost:
            return MyaowColor.orange
        case .destructive:
            return MyaowColor.statusRed
        }
    }
    
    private var borderColor: Color {
        switch style {
        case .primary:
            return Color.clear
        case .secondary:
            return MyaowColor.borderSubtle
        case .ghost:
            return Color.clear
        case .destructive:
            return MyaowColor.statusRed.opacity(0.3)
        }
    }
}

/// Efecto de escala elástica sutil al presionar botones
public struct MyaowScaleButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.965 : 1.0)
            .opacity(configuration.isPressed ? 0.86 : 1.0)
            .animation(reduceMotion ? .easeOut(duration: 0.1) :
                (configuration.isPressed ? .easeOut(duration: 0.1) : .spring(response: 0.3, dampingFraction: 0.76)),
                value: configuration.isPressed)
    }
}
