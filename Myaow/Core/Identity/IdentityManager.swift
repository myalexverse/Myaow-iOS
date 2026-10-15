//
//  IdentityManager.swift
//  Myaow
//
//  Created for Myaow - "Tecnología que se siente cercana"
//

import SwiftUI
import CoreImage.CIFilterBuiltins

@MainActor
@Observable
public final class IdentityManager {
    public static let shared = IdentityManager()
    
    public var currentIdentity: UserIdentity
    public private(set) var privateKeyHex: String
    public private(set) var isInitialized: Bool = false
    public private(set) var storageError: String?
    private var vault: IdentityVault { IdentityVault(defaults: .standard, secrets: KeychainSecurityService.shared) }
    public var hasCompletedOnboarding: Bool {
        didSet {
            UserDefaults.standard.set(hasCompletedOnboarding, forKey: onboardingDefaultsKey)
        }
    }
    
    public var isDirectoryRegistrationPending: Bool {
        get { UserDefaults.standard.bool(forKey: "myaow_directory_registration_pending") }
        set { UserDefaults.standard.set(newValue, forKey: "myaow_directory_registration_pending") }
    }

    private let userDefaultsKey = "myaow_local_identity"
    private let privKeyDefaultsKey = "myaow_private_key"
    private let onboardingDefaultsKey = "myaow_has_completed_onboarding"
    
    private init() {
        self.hasCompletedOnboarding = UserDefaults.standard.bool(forKey: onboardingDefaultsKey)
        self.profilePhotoData = UserDefaults.standard.data(forKey: "myaow_profile_photo")
        self.profilePhotoUrl = UserDefaults.standard.string(forKey: "myaow_profile_url")
        
        self.currentIdentity = UserIdentity(myaowId: "", publicKeyHex: "")
        self.privateKeyHex = ""
        reloadIdentity()
    }

    public func reloadIdentity() {
        do {
            let record = try vault.loadOrCreate()
            currentIdentity = record.identity
            privateKeyHex = SecureHex.encode(record.privateKey)
            storageError = nil
            isInitialized = true
        } catch {
            isInitialized = false
            storageError = "No pudimos abrir tu identidad de forma segura. Tus datos siguen guardados. Desbloquea el iPhone y vuelve a intentar."
        }
    }

    public func completeRegistration(
        displayName: String,
        customUsername: String?,
        avatarStateName: String,
        avatarImageData: Data?
    ) {
        currentIdentity.displayName = displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Usuario Myaow" : displayName
        currentIdentity.customUsername = customUsername?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        currentIdentity.avatarStateName = avatarStateName
        currentIdentity.avatarImageData = avatarImageData
        self.profilePhotoData = avatarImageData
        saveIdentity()
        self.hasCompletedOnboarding = true
        // The photo is uploaded after the WebSocket session is authenticated.

    }
    
    public func updateDisplayName(_ newName: String) {
        currentIdentity.displayName = newName
        saveIdentity()
    }
    
    public func updateUsername(_ newUsername: String) {
        currentIdentity.customUsername = newUsername.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        saveIdentity()
    }
    
    public func updateAvatarState(_ stateName: String) {
        currentIdentity.avatarStateName = stateName
        currentIdentity.avatarImageData = nil // Reset custom image to use vector mascot
        saveIdentity()
        OnlineMessagingService.shared.broadcastAvatarStateUpdate(newStateName: stateName)
    }
    
    public var profilePhotoData: Data? {
        didSet {
            UserDefaults.standard.set(profilePhotoData, forKey: "myaow_profile_photo")
        }
    }
    
    public var profilePhotoUrl: String? {
        didSet {
            UserDefaults.standard.set(profilePhotoUrl, forKey: "myaow_profile_url")
        }
    }
    
    public func saveProfilePhoto(_ data: Data) {
        self.profilePhotoData = data
        uploadProfilePhoto()
    }
    
    public func removeProfilePhoto() {
        self.profilePhotoData = nil
        self.profilePhotoUrl = nil
    }
    
    public func uploadProfilePhoto() {
        guard let data = profilePhotoData else { return }
        Task { await uploadProfilePicture(data) }
    }

    public func updateAvatarImage(_ data: Data?) {
        profilePhotoData = data
        if data == nil { profilePhotoUrl = nil }
        currentIdentity.avatarImageData = data
        saveIdentity()
        if let data = data {
            Task { await uploadProfilePicture(data) }
        }
    }
    
    public func uploadProfilePicture(_ imageData: Data) async {
        let ownerID = currentIdentity.myaowId
        guard let base = RelayEndpoint(OnlineMessagingService.shared.relayHost)?.httpURL else { return }
        var request = URLRequest(url: base.appendingPathComponent("api/v1/profile/avatar"))
        request.httpMethod = "POST"
        request.httpBody = imageData
        request.setValue("image/jpeg", forHTTPHeaderField: "Content-Type")
        OnlineMessagingService.shared.authenticatedRequest(&request)
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return }
            struct AvatarResponse: Decodable { let avatarUrl: String }
            let result = try JSONDecoder().decode(AvatarResponse.self, from: data)
            // An older upload must not restore a removed or replaced photo.
            guard currentIdentity.myaowId == ownerID, profilePhotoData == imageData else { return }
            self.profilePhotoUrl = result.avatarUrl
            OnlineMessagingService.shared.broadcastAvatarStateUpdate(newStateName: currentIdentity.avatarStateName)
        } catch {
            // The local photo remains available; the next authenticated connection retries it.
        }
    }

    // Identity replacement requires a separate, explicit recovery flow.
    private func saveIdentity() {
        guard isInitialized else { return }
        do {
            try vault.save(.init(identity: currentIdentity, privateKey: SecureHex.decode(privateKeyHex, bytes: 32)))
            storageError = nil
        } catch {
            storageError = "No pudimos guardar tu identidad de forma segura. Libera espacio y vuelve a intentar."
            isInitialized = false
            OnlineMessagingService.shared.stopConnection()
        }
    }

    /// Genera la imagen del código QR para compartir la identidad local
    public func generateQRCodeImage(size: CGFloat = 220) -> Image? {
        guard let payload = currentIdentity.toQRPayload() else { return nil }
        
        let filter = CIFilter.qrCodeGenerator()
        filter.setValue(Data(payload.utf8), forKey: "inputMessage")
        filter.setValue("M", forKey: "inputCorrectionLevel")
        
        guard let ciImage = filter.outputImage else { return nil }
        
        // Escalar la imagen QR nítidamente
        let transform = CGAffineTransform(scaleX: 10, y: 10)
        let scaledCIImage = ciImage.transformed(by: transform)
        
        let context = CIContext()
        guard let cgImage = context.createCGImage(scaledCIImage, from: scaledCIImage.extent) else { return nil }
        
        #if canImport(UIKit)
        let uiImage = UIImage(cgImage: cgImage)
        return Image(uiImage: uiImage)
        #else
        return nil
        #endif
    }
}
