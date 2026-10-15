//
//  MyaowStatusBadge.swift
//  Myaow
//
//  Created for Myaow - "Tecnología que se siente cercana"
//

import SwiftUI

public struct MyaowMeshStatusBanner: View {
    public let nodeCount: Int
    public let isConnected: Bool
    public let action: (() -> Void)?
    
    public init(nodeCount: Int, isConnected: Bool = true, action: (() -> Void)? = nil) {
        self.nodeCount = nodeCount
        self.isConnected = isConnected
        self.action = action
    }
    
    public var body: some View {
        Button(action: {
            action?()
        }) {
            HStack(spacing: 8) {
                Circle()
                    .fill(isConnected ? MyaowColor.statusGreen : MyaowColor.statusOrange)
                    .frame(width: 7, height: 7)
                
                Text(isConnected ? "RED LOCAL" : "RECONECTANDO")
                    .font(.myaowMicro)
                    .foregroundColor(MyaowColor.textSecondary)
                    .tracking(0.5)
                
                Text("•")
                    .font(.myaowMicro)
                    .foregroundColor(MyaowColor.textTertiary)
                
                Text("\(nodeCount) \(nodeCount == 1 ? "nodo conectado" : "nodos conectados")")
                    .font(.myaowCaptionMedium)
                    .foregroundColor(MyaowColor.textPrimary)
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(MyaowColor.textTertiary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(MyaowColor.surface)
            .clipShape(Capsule())
            .overlay(
                Capsule()
                    .stroke(MyaowColor.borderSubtle, lineWidth: 1)
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
}

public struct MyaowUnreadBadge: View {
    public let count: Int
    
    public init(count: Int) {
        self.count = count
    }
    
    public var body: some View {
        if count > 0 {
            Text("\(count)")
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundColor(.white)
                .padding(.horizontal, count > 9 ? 6 : 5)
                .padding(.vertical, 2)
                .background(MyaowColor.orange)
                .clipShape(Capsule())
        }
    }
}
