//
//  AppleSignInManager.swift
//  Myaow
//
//  Created for Myaow - "Tecnología que se siente cercana"
//

import SwiftUI
import AuthenticationServices
import CryptoKit

@MainActor
@Observable
public final class AppleSignInManager: NSObject {
    public static let shared = AppleSignInManager()
    
    public var isSignedInWithApple: Bool = false
    public var appleUserIdentifier: String? = nil
    public var appleEmail: String? = nil
    public var appleFullName: String? = nil
    
    public override init() {
        super.init()
        // Restore Apple Sign In state from Keychain
        if let savedIdData = KeychainSecurityService.shared.loadSecret(key: "apple_user_sub_id"),
           let savedId = String(data: savedIdData, encoding: .utf8) {
            self.appleUserIdentifier = savedId
            // Validate credential state with Apple
            let provider = ASAuthorizationAppleIDProvider()
            provider.getCredentialState(forUserID: savedId) { [weak self] state, _ in
                Task { @MainActor in
                    if state == .authorized {
                        self?.isSignedInWithApple = true
                        print("🍏 [Apple Sign In] Sesión restaurada")
                    } else {
                        self?.isSignedInWithApple = false
                        self?.appleUserIdentifier = nil
                        print("🍏 [Apple Sign In] Sesión expirada")
                    }
                }
            }
        }
        self.appleFullName = UserDefaults.standard.string(forKey: "apple_full_name")
        self.appleEmail = UserDefaults.standard.string(forKey: "apple_email")
    }
    
    /// Configura y procesa la autorización con Sign in with Apple
    public func handleAuthorizationResult(result: Result<ASAuthorization, Error>, onComplete: @escaping (String, String) -> Void) {
        switch result {
        case .success(let authorization):
            if let appleIDCredential = authorization.credential as? ASAuthorizationAppleIDCredential {
                let userIdentifier = appleIDCredential.user
                self.appleUserIdentifier = userIdentifier
                
                // Extraer nombre si está disponible (solo se entrega en el primer login)
                var resolvedName = self.appleFullName ?? "Usuario Apple"
                if let fullName = appleIDCredential.fullName {
                    let given = fullName.givenName ?? ""
                    let family = fullName.familyName ?? ""
                    let full = "\(given) \(family)".trimmingCharacters(in: .whitespaces)
                    if !full.isEmpty {
                        resolvedName = full
                    }
                }
                if resolvedName != "Usuario Apple" {
                    UserDefaults.standard.set(resolvedName, forKey: "apple_full_name")
                }
                if let email = appleIDCredential.email {
                    UserDefaults.standard.set(email, forKey: "apple_email")
                }
                
                self.appleFullName = resolvedName
                self.appleEmail = appleIDCredential.email ?? self.appleEmail
                self.isSignedInWithApple = true
                
                // Guardar en Keychain seguro
                KeychainSecurityService.shared.saveSecret(
                    key: "apple_user_sub_id",
                    data: Data(userIdentifier.utf8)
                )
                
                let sanitizedHandle = resolvedName
                    .folding(options: .diacriticInsensitive, locale: .current)
                    .lowercased()
                    .components(separatedBy: CharacterSet.alphanumerics.inverted)
                    .joined()
                
                print("🍏 [Apple Sign In] Autorización exitosa para \(resolvedName) (ID: \(userIdentifier.prefix(8))...)")
                onComplete(resolvedName, sanitizedHandle.isEmpty ? "myaowuser" : sanitizedHandle)
            }
            
        case .failure(let error):
            print("⚠️ [Apple Sign In] Autorización cancelada o fallida: \(error.localizedDescription)")
        }
    }
}
