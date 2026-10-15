//
//  MyaowLogoView.swift
//  Myaow
//
//  Created for Myaow - "Tecnología que se siente cercana"
//

import SwiftUI

/// Renderiza el logo oficial e isotipo de Myaow con la tipografía y el punto naranja característico en la 'o'
public struct MyaowLogoView: View {
    public var size: CGFloat
    public var showWordmark: Bool
    public var showTagline: Bool
    public var style: MyaowLogoStyle
    
    public enum MyaowLogoStyle {
        /// Halo naranja con gato blanco / oscuro (Identidad principal)
        case orange
        /// Halo oscuro con gato blanco
        case dark
        /// Halo blanco con gato oscuro
        case light
    }
    
    public init(
        size: CGFloat = 120,
        showWordmark: Bool = true,
        showTagline: Bool = true,
        style: MyaowLogoStyle = .orange
    ) {
        self.size = size
        self.showWordmark = showWordmark
        self.showTagline = showTagline
        self.style = style
    }
    
    public var body: some View {
        VStack(spacing: size * 0.12) {
            // Isotipo Oficial (Mascota con el halo y cola arqueada)
            MyaowOfficialIsotype(size: size, style: style)
            
            if showWordmark {
                VStack(spacing: 4) {
                    // Tipografía oficial "myaow" con punto naranja en la 'o'
                    MyaowWordmarkView(fontSize: size * 0.28)
                    
                    if showTagline {
                        Text("Mensajería. Privada. Local. Segura.")
                            .font(.system(size: max(10, size * 0.10), weight: .regular, design: .rounded))
                            .foregroundColor(MyaowColor.textSecondary)
                    }
                }
            }
        }
    }
}

/// Isotipo oficial de Myaow (Gato frontal + Halo con cola derecha)
public struct MyaowOfficialIsotype: View {
    public var size: CGFloat
    public var style: MyaowLogoView.MyaowLogoStyle
    public var eyeProgress: Double = 1.0
    public var state: MyaowCatState = .neutral
    
    public init(size: CGFloat = 100, style: MyaowLogoView.MyaowLogoStyle = .orange, eyeProgress: Double = 1.0, state: MyaowCatState = .neutral) {
        self.size = size
        self.style = style
        self.eyeProgress = eyeProgress
        self.state = state
    }
    
    private var haloColor: Color {
        switch style {
        case .orange: return MyaowColor.orange
        case .dark: return MyaowColor.charcoal
        case .light: return .white
        }
    }
    
    private var catBodyColor: Color {
        switch style {
        case .orange: return .white
        case .dark: return .white
        case .light: return MyaowColor.charcoal
        }
    }
    
    private var featureColor: Color {
        switch style {
        case .orange, .dark: return MyaowColor.charcoal
        case .light: return .white
        }
    }
    
    public var body: some View {
        ZStack {
            // 1. Halo exterior con la cola arqueada a la derecha
            MyaowOfficialHaloShape()
                .fill(haloColor)
                .frame(width: size, height: size)
            
            // 2. Silueta de la cabeza del gato (encajada en el halo)
            MyaowOfficialCatHeadShape()
                .fill(catBodyColor)
                .frame(width: size * 0.65, height: size * 0.65)
                .offset(y: size * 0.08)
            
            // 3. Rasgos faciales oficiales (Ojos, Bigotes, Nariz, Marcas)
            facialFeatures
                .frame(width: size * 0.65, height: size * 0.65)
                .offset(y: size * 0.08)
        }
        .frame(width: size, height: size)
    }
    
    private var facialFeatures: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            
            ZStack {
                // Ojos
                HStack(spacing: w * 0.28) {
                    singleEye(width: w * 0.15, height: w * 0.15)
                    singleEye(width: w * 0.15, height: w * 0.15)
                }
                .position(x: w * 0.5, y: h * 0.52)
                
                // Naricita oficial
                PolygonTriangle()
                    .fill(featureColor)
                    .frame(width: w * 0.10, height: w * 0.08)
                    .rotationEffect(.degrees(180))
                    .position(x: w * 0.5, y: h * 0.65)
                
                // Marcas verticales sutiles bajo los ojos
                HStack(spacing: w * 0.30) {
                    Capsule()
                        .fill(featureColor)
                        .frame(width: max(2, w * 0.035), height: w * 0.09)
                    Capsule()
                        .fill(featureColor)
                        .frame(width: max(2, w * 0.035), height: w * 0.09)
                }
                .position(x: w * 0.5, y: h * 0.69)
                
                // Bigotes oficiales: 2 a la izquierda, 2 a la derecha
                // Bigotes Izquierda
                VStack(spacing: w * 0.05) {
                    Capsule().fill(featureColor).frame(width: w * 0.18, height: max(1.5, w * 0.03))
                    Capsule().fill(featureColor).frame(width: w * 0.18, height: max(1.5, w * 0.03))
                }
                .position(x: w * 0.06, y: h * 0.65)
                
                // Bigotes Derecha
                VStack(spacing: w * 0.05) {
                    Capsule().fill(featureColor).frame(width: w * 0.18, height: max(1.5, w * 0.03))
                    Capsule().fill(featureColor).frame(width: w * 0.18, height: max(1.5, w * 0.03))
                }
                .position(x: w * 0.94, y: h * 0.65)
            }
        }
    }
    
    @ViewBuilder
    private func singleEye(width: CGFloat, height: CGFloat) -> some View {
        switch state {
        case .happy:
            HappyEyeArc()
                .stroke(featureColor, style: StrokeStyle(lineWidth: max(2, width * 0.22), lineCap: .round))
                .frame(width: width, height: height * 0.7)
        case .sleeping:
            SleepingEyeArc()
                .stroke(featureColor, style: StrokeStyle(lineWidth: max(2, width * 0.2), lineCap: .round))
                .frame(width: width, height: height * 0.4)
        default:
            Circle()
                .fill(featureColor)
                .frame(width: width, height: max(height * 0.1, height * CGFloat(eyeProgress)))
        }
    }
}

/// Tipografía oficial "myaow" con el punto naranja dentro de la letra "o"
public struct MyaowWordmarkView: View {
    public var fontSize: CGFloat = 34
    public var textColor: Color = .white
    
    public var body: some View {
        HStack(spacing: 0) {
            Text("mya")
                .font(.system(size: fontSize, weight: .bold, design: .rounded))
                .foregroundColor(textColor)
            
            // Letra 'o' con el punto naranja oficial
            ZStack {
                Text("o")
                    .font(.system(size: fontSize, weight: .bold, design: .rounded))
                    .foregroundColor(textColor)
                
                Circle()
                    .fill(MyaowColor.orange)
                    .frame(width: fontSize * 0.20, height: fontSize * 0.20)
                    .offset(y: fontSize * 0.05)
            }
            
            Text("w")
                .font(.system(size: fontSize, weight: .bold, design: .rounded))
                .foregroundColor(textColor)
        }
    }
}

// MARK: - Official Geometric Shapes

/// Halo oficial con arco superior y cola arqueada en la derecha
public struct MyaowOfficialHaloShape: Shape {
    public func path(in rect: CGRect) -> Path {
        var path = Path()
        let w = rect.width
        let h = rect.height
        
        // Arco exterior circular principal
        path.move(to: CGPoint(x: w * 0.16, y: h * 0.75))
        
        // Curva lateral izquierda hacia la cima del halo
        path.addCurve(
            to: CGPoint(x: w * 0.50, y: h * 0.02),
            control1: CGPoint(x: w * 0.06, y: h * 0.42),
            control2: CGPoint(x: w * 0.22, y: h * 0.02)
        )
        
        // Cima hacia lateral derecho
        path.addCurve(
            to: CGPoint(x: w * 0.94, y: h * 0.46),
            control1: CGPoint(x: w * 0.78, y: h * 0.02),
            control2: CGPoint(x: w * 0.94, y: h * 0.20)
        )
        
        // Cola estilizada a la derecha que desciende y se curva hacia afuera
        path.addCurve(
            to: CGPoint(x: w * 0.88, y: h * 0.88),
            control1: CGPoint(x: w * 0.94, y: h * 0.65),
            control2: CGPoint(x: w * 0.96, y: h * 0.78)
        )
        
        // Punta redondeada de la cola y curva interior hacia la cabeza
        path.addCurve(
            to: CGPoint(x: w * 0.72, y: h * 0.76),
            control1: CGPoint(x: w * 0.80, y: h * 0.88),
            control2: CGPoint(x: w * 0.74, y: h * 0.82)
        )
        
        // Arco interior que recorta el espacio del gato
        path.addCurve(
            to: CGPoint(x: w * 0.16, y: h * 0.75),
            control1: CGPoint(x: w * 0.72, y: h * 0.35),
            control2: CGPoint(x: w * 0.28, y: h * 0.35)
        )
        
        path.closeSubpath()
        return path
    }
}

/// Cabeza oficial del gato con orejas perky pulidas y contorno orgánico continuo
public struct MyaowOfficialCatHeadShape: Shape {
    public func path(in rect: CGRect) -> Path {
        var path = Path()
        let w = rect.width
        let h = rect.height
        
        // 1. Base inferior de la barbilla
        path.move(to: CGPoint(x: w * 0.50, y: h * 0.94))
        
        // 2. Curva mejilla izquierda (suave y redondeada)
        path.addCurve(
            to: CGPoint(x: w * 0.10, y: h * 0.56),
            control1: CGPoint(x: w * 0.28, y: h * 0.94),
            control2: CGPoint(x: w * 0.10, y: h * 0.76)
        )
        
        // 3. Oreja izquierda: transición de mejilla a punta perky suave
        path.addCurve(
            to: CGPoint(x: w * 0.22, y: h * 0.08),
            control1: CGPoint(x: w * 0.10, y: h * 0.36),
            control2: CGPoint(x: w * 0.14, y: h * 0.16)
        )
        
        // 4. Oreja izquierda: punta redondeada pulida descendiendo hacia la corona
        path.addCurve(
            to: CGPoint(x: w * 0.38, y: h * 0.30),
            control1: CGPoint(x: w * 0.27, y: h * 0.08),
            control2: CGPoint(x: w * 0.32, y: h * 0.20)
        )
        
        // 5. Corona superior suave entre orejas (depresión orgánica elegante)
        path.addCurve(
            to: CGPoint(x: w * 0.62, y: h * 0.30),
            control1: CGPoint(x: w * 0.44, y: h * 0.34),
            control2: CGPoint(x: w * 0.56, y: h * 0.34)
        )
        
        // 6. Oreja derecha: subida hacia la punta
        path.addCurve(
            to: CGPoint(x: w * 0.78, y: h * 0.08),
            control1: CGPoint(x: w * 0.68, y: h * 0.20),
            control2: CGPoint(x: w * 0.73, y: h * 0.08)
        )
        
        // 7. Oreja derecha: punta redondeada descendiendo a la mejilla
        path.addCurve(
            to: CGPoint(x: w * 0.90, y: h * 0.56),
            control1: CGPoint(x: w * 0.86, y: h * 0.16),
            control2: CGPoint(x: w * 0.90, y: h * 0.36)
        )
        
        // 8. Mejilla derecha cerrando en la barbilla
        path.addCurve(
            to: CGPoint(x: w * 0.50, y: h * 0.94),
            control1: CGPoint(x: w * 0.90, y: h * 0.76),
            control2: CGPoint(x: w * 0.72, y: h * 0.94)
        )
        
        path.closeSubpath()
        return path
    }
}

#Preview {
    ZStack {
        Color.myaowCharcoal.ignoresSafeArea()
        
        VStack(spacing: 40) {
            MyaowLogoView(size: 140, showWordmark: true, showTagline: true, style: .orange)
            
            HStack(spacing: 24) {
                MyaowOfficialIsotype(size: 70, style: .orange)
                MyaowOfficialIsotype(size: 70, style: .dark)
                MyaowOfficialIsotype(size: 70, style: .light)
            }
        }
    }
}
