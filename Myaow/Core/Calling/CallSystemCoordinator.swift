import Foundation
import CallKit
import PushKit
import AVFoundation
import SwiftData

/// Owns the system call interface even when SwiftUI has not been created yet.
@MainActor
final class CallSystemCoordinator: NSObject, CXProviderDelegate, PKPushRegistryDelegate {
    static let shared = CallSystemCoordinator()
    private let provider: CXProvider
    private let controller = CXCallController()
    private var registry: PKPushRegistry?
    private var reported = Set<UUID>()
    private var activeID: UUID?
    private var outgoingIDs = Set<UUID>()
    private var contactResolutionTask: Task<Void, Never>?
    private var contactRevision = UUID()
    private struct Contact: Codable { let name: String; let key: Data; var catState: String? = nil }
    private var snapshotKey: String { "call_contacts_v1_" + IdentityManager.shared.currentIdentity.myaowId }
    private var contacts: [String: Contact] {
        guard let data = KeychainSecurityService.shared.loadSecret(key: snapshotKey),
              let result = try? JSONDecoder().decode([String: Contact].self, from: data) else { return [:] }
        return result
    }
    var allowedCallers: [String] { contacts.keys.filter { !ContactBlockingService.shared.isBlocked($0) }.sorted() }
    private override init() {
        let config = CXProviderConfiguration()
        config.supportsVideo = true
        config.maximumCallGroups = 1
        config.maximumCallsPerCallGroup = 1
        config.supportedHandleTypes = [.generic]
        config.includesCallsInRecents = false
        provider = CXProvider(configuration: config)
        super.init()
        provider.setDelegate(self, queue: .main)
    }
    func start() {
        guard registry == nil, IdentityManager.shared.hasCompletedOnboarding, !DesignPreviewData.isEnabled else { return }
        registry = PKPushRegistry(queue: .main)
        registry?.delegate = self
        registry?.desiredPushTypes = [.voIP]
    }
    func updateContacts(_ records: [ContactModel]) {
        contactResolutionTask?.cancel()
        let revision = UUID(); contactRevision = revision
        let owner = IdentityManager.shared.currentIdentity.myaowId
        let candidates = records.filter { !$0.myaowId.isEmpty && $0.myaowId != owner }
            .map { (id: $0.myaowId, name: $0.displayName, key: $0.publicKeyHex, catState: $0.avatarCatState) }
        var snapshot: [String: Contact] = [:]
        for record in candidates where !ContactBlockingService.shared.isBlocked(record.id) {
            // The saved identity pin always wins over a later directory/contact update.
            let key = (try? SecureMessagingService.shared.cachedPeerKey(for: record.id)) ??
                (try? SecureHex.decode(record.key, bytes: 32))
            if let key { snapshot[record.id] = Contact(name: record.name, key: key, catState: record.catState) }
        }
        saveContacts(snapshot)
        guard !DesignPreviewData.isEnabled else { return }
        // Contacts added by ID or QR may have no key yet. Resolve them when saved,
        // not only after sending the first message or starting an outgoing call.
        contactResolutionTask = Task { @MainActor in
            for record in candidates where snapshot[record.id] == nil {
                guard !Task.isCancelled, contactRevision == revision,
                      IdentityManager.shared.currentIdentity.myaowId == owner else { return }
                guard !ContactBlockingService.shared.isBlocked(record.id) else { continue }
                do {
                    let key = try await SecureMessagingService.shared.peerKey(for: record.id,
                        suppliedKey: record.key.isEmpty ? nil : record.key)
                    guard !Task.isCancelled, contactRevision == revision,
                          IdentityManager.shared.currentIdentity.myaowId == owner,
                          !ContactBlockingService.shared.isBlocked(record.id) else { return }
                    snapshot[record.id] = Contact(name: record.name, key: key, catState: record.catState)
                    saveContacts(snapshot)
                } catch { /* Leave unresolved identities unauthorized; retry on the next foreground refresh. */ }
            }
        }
    }
    private func saveContacts(_ snapshot: [String: Contact]) {
        if let data = try? JSONEncoder().encode(snapshot) {
            _ = KeychainSecurityService.shared.saveSecret(key: snapshotKey, data: data)
        }
        APNsNotificationManager.shared.synchronizeDevice()
    }
    func contactCatState(_ id: String) -> MyaowCatState { contacts[id]?.catState.flatMap(MyaowCatState.init(rawValue:)) ?? .friendly }
    func contactName(_ id: String) -> String? {
        guard !ContactBlockingService.shared.isBlocked(id) else { return nil }
        return contacts[id]?.name
    }
    func pushRegistry(_ registry: PKPushRegistry, didUpdate pushCredentials: PKPushCredentials, for type: PKPushType) {
        APNsNotificationManager.shared.handleVoIPToken(pushCredentials.token)
    }
    func pushRegistry(_ registry: PKPushRegistry, didInvalidatePushTokenFor type: PKPushType) {
        APNsNotificationManager.shared.handleVoIPToken(nil)
    }
    func pushRegistry(_ registry: PKPushRegistry, didReceiveIncomingPushWith payload: PKPushPayload, for type: PKPushType, completion: @escaping () -> Void) {
        receive(payload.dictionaryPayload, pushCompletion: completion)
    }
    func receive(_ packet: [AnyHashable: Any], pushCompletion: (() -> Void)? = nil) {
        let fallbackID = UUID(uuidString: packet["callId"] as? String ?? "") ?? UUID()
        do {
            guard IdentityManager.shared.isInitialized,
                  let sender = packet["senderMyaowId"] as? String, let contact = contacts[sender],
                  !ContactBlockingService.shared.isBlocked(sender) else { throw SecureMessageError.invalidEnvelope }
            let verified = try VerifiedCallSignal.open(packet, owner: IdentityManager.shared.currentIdentity.myaowId,
                privateKey: SecureHex.decode(IdentityManager.shared.privateKeyHex, bytes: 32), peerKey: contact.key, requiresOffer: pushCompletion != nil)
            let uuid = verified.callID, signal = verified.data, type = verified.type
            if let pushCompletion {
                reportIncoming(uuid, name: contact.name, video: (signal["callType"] as? String) == CallType.video.rawValue, completion: pushCompletion)
            }
            CallSessionService.shared.handleSignalingEvent(type: type, senderMyaowId: sender, senderName: contact.name, data: signal)
            // A valid but busy/duplicate/obsolete offer must not leave a second system call ringing.
            if pushCompletion != nil, CallSessionService.shared.currentCallUUID != uuid { end(uuid, reason: .unanswered) }
            OnlineMessagingService.shared.startConnectionHeartbeat()
        } catch {
            // PushKit requires reporting each VoIP push immediately, including unusable/expired offers.
            if let pushCompletion {
                let update = CXCallUpdate(); update.localizedCallerName = "Llamada de Myaow"
                provider.reportNewIncomingCall(with: fallbackID, update: update) { [weak self] _ in
                    Task { @MainActor in self?.provider.reportCall(with: fallbackID, endedAt: Date(), reason: .failed); pushCompletion() }
                }
            }
        }
    }
    func reportIncoming(_ id: UUID, name: String, video: Bool, completion: (() -> Void)? = nil) {
        if reported.contains(id), completion == nil { return }
        let alreadyReported = reported.contains(id)
        if !alreadyReported { reported.insert(id); activeID = id }
        let update = CXCallUpdate()
        update.remoteHandle = CXHandle(type: .generic, value: name)
        update.localizedCallerName = name; update.hasVideo = video
        update.supportsHolding = false; update.supportsGrouping = false; update.supportsUngrouping = false
        provider.reportNewIncomingCall(with: id, update: update) { [weak self] error in
            Task { @MainActor in
                completion?()
                #if DEBUG
                if let error { print("[CallKit] incoming report failed: \((error as NSError).code)") }
                #endif
                if error != nil, !alreadyReported, self?.activeID == id {
                    self?.activeID = nil
                    CallSessionService.shared.systemCallFailed(id)
                }
            }
        }
    }
    func startOutgoing(_ id: UUID, name: String, video: Bool) {
        activeID = id; outgoingIDs.insert(id)
        let action = CXStartCallAction(call: id, handle: CXHandle(type: .generic, value: name)); action.isVideo = video
        controller.request(CXTransaction(action: action)) { error in
            if error != nil { Task { @MainActor in CallSessionService.shared.systemCallFailed(id) } }
        }
    }
    func requestAnswer(_ id: UUID) {
        controller.request(CXTransaction(action: CXAnswerCallAction(call: id))) { error in
            if error != nil { Task { @MainActor in CallSessionService.shared.systemCallFailed(id) } }
        }
    }
    func connected(_ id: UUID) {
        if outgoingIDs.contains(id) { provider.reportOutgoingCall(with: id, connectedAt: Date()) }
    }
    func end(_ id: UUID, reason: CXCallEndedReason = .remoteEnded) {
        provider.reportCall(with: id, endedAt: Date(), reason: reason)
        outgoingIDs.remove(id)
        if activeID == id { activeID = nil }
        // Keep duplicate suppression bounded. Call UUIDs are never intentionally reused.
        if reported.count > 256 { reported = [id] }
    }
    func providerDidReset(_ provider: CXProvider) {
        #if DEBUG
        print("[CallKit] provider reset")
        #endif
        activeID = nil; outgoingIDs.removeAll(); reported.removeAll()
        CallSessionService.shared.endCall()
    }
    func provider(_ provider: CXProvider, perform action: CXStartCallAction) {
        guard activeID == action.callUUID else { action.fail(); return }
        do { try WebRTCPeerService.shared.prepareSystemAudio(video: CallSessionService.shared.callType == .video) }
        catch { action.fail(); CallSessionService.shared.systemCallFailed(action.callUUID); return }
        provider.reportOutgoingCall(with: action.callUUID, startedConnectingAt: Date()); action.fulfill()
    }
    func provider(_ provider: CXProvider, perform action: CXAnswerCallAction) {
        guard CallSessionService.shared.currentCallUUID == action.callUUID else { action.fail(); return }
        do { try WebRTCPeerService.shared.prepareSystemAudio(video: CallSessionService.shared.callType == .video) }
        catch { action.fail(); CallSessionService.shared.systemCallFailed(action.callUUID); return }
        CallSessionService.shared.acceptCall(fromSystem: true); action.fulfill()
    }
    func provider(_ provider: CXProvider, perform action: CXEndCallAction) {
        #if DEBUG
        print("[CallKit] end action")
        #endif
        guard CallSessionService.shared.currentCallUUID == action.callUUID else { action.fulfill(); return }
        CallSessionService.shared.endCall(); action.fulfill()
    }
    func provider(_ provider: CXProvider, perform action: CXSetMutedCallAction) {
        guard CallSessionService.shared.currentCallUUID == action.callUUID else { action.fail(); return }
        CallSessionService.shared.setMuted(action.isMuted); action.fulfill()
    }
    func provider(_ provider: CXProvider, timedOutPerforming action: CXAction) {
        if let call = action as? CXCallAction { CallSessionService.shared.systemCallFailed(call.callUUID) }
    }
    func provider(_ provider: CXProvider, didActivate audioSession: AVAudioSession) { WebRTCPeerService.shared.systemAudioActivated(audioSession); CallSessionService.shared.systemAudioChanged(active: true) }
    func provider(_ provider: CXProvider, didDeactivate audioSession: AVAudioSession) { WebRTCPeerService.shared.systemAudioDeactivated(audioSession); CallSessionService.shared.systemAudioChanged(active: false) }
}
