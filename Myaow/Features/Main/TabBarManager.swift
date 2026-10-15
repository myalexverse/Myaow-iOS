//
//  TabBarManager.swift
//  Myaow
//
//  Created for Myaow - "Tecnología que se siente cercana"
//

import SwiftUI

@MainActor
@Observable
public final class TabBarManager {
    public static let shared = TabBarManager()
    
    public var isHidden: Bool = false
    
    private init() {}
    
    public func hide() {
        // Avoid resizing the destination's transcript with a spring during navigation.
        isHidden = true
    }
    
    public func show() {
        isHidden = false
    }
}
