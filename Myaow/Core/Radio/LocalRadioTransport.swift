import Foundation
import MultipeerConnectivity
import Observation

struct RadioNeighbor: Identifiable {
    let peer: MCPeerID
    let contact: RadioContactCredential
    var channel: Int?
    var id: String { peer.displayName }
    var name: String { contact.name }
}

@MainActor @Observable
final class LocalRadioTransport: NSObject {
    private(set) var isActive = false
    private(set) var nearby: [RadioNeighbor] = []
    private(set) var connected: [RadioNeighbor] = []
    private(set) var inviting: Set<String> = []
    private(set) var invitation: RadioNeighbor?
    private(set) var requestedContactID: String?
    var error: String?
    var onPacket: ((RadioPacket, RadioNeighbor) -> Void)?
    var onConnect: (() -> Void)?
    var onDisconnect: ((String) -> Void)?
    var channel = 1
    private(set) var localPeer = MCPeerID(displayName: "radio-" + UUID().uuidString.lowercased())
    private var session: MCSession?
    private var advertiser: MCNearbyServiceAdvertiser?
    private var browser: MCNearbyServiceBrowser?
    private var approved: [String: RadioNeighbor] = [:]
    private var invitationHandler: ((Bool, MCSession?) -> Void)?
    private var invitationExpiry: Task<Void, Never>?
    private var contacts: [RadioContactCredential] = []
    private var privateKey = Data()
    private var usedInvitations: Set<String> = []
    private var sendSequence: UInt64 = 0
    private var replayWindow = RadioReplayWindow()
    private let serviceType = "myaow-radio"

    /// Called with local, explicitly authorized contacts and already-pinned keys only.
    func configure(privateKey: Data, contacts: [RadioContactCredential]) {
        guard self.privateKey != privateKey || self.contacts != contacts else { return }
        if isActive { stop(); error = "Cambió tu lista de contactos. Activa Radio de nuevo." }
        self.privateKey = privateKey
        self.contacts = contacts.filter { $0.publicKey.count == 32 }
    }
    func start(name: String = "") {
        guard !isActive else { return }
        guard let publicKey = try? RadioContactSecurity.publicKey(privateKey) else {
            error = "No se pudo verificar tu identidad. Vuelve a abrir Myaow."; return
        }
        guard !contacts.isEmpty else { error = "Primero permite Radio con uno de tus contactos."; return }
        error = nil
        // A new local peer identifier makes proofs from a previous activation unusable.
        localPeer = MCPeerID(displayName: "radio-" + UUID().uuidString.lowercased())
        let session = MCSession(peer: localPeer, securityIdentity: nil, encryptionPreference: .required)
        session.delegate = self; self.session = session
        advertiser = MCNearbyServiceAdvertiser(peer: localPeer,
            discoveryInfo: ["key": RadioContactSecurity.fingerprint(publicKey), "v": "2"], serviceType: serviceType)
        browser = MCNearbyServiceBrowser(peer: localPeer, serviceType: serviceType)
        advertiser?.delegate = self; browser?.delegate = self
        isActive = true
        advertiser?.startAdvertisingPeer(); browser?.startBrowsingForPeers()
    }
    func stop() {
        isActive = false; respond(false)
        advertiser?.stopAdvertisingPeer(); browser?.stopBrowsingForPeers()
        session?.disconnect(); session = nil; advertiser = nil; browser = nil
        nearby = []; connected = []; approved = [:]; inviting = []
        requestedContactID = nil; usedInvitations = []; sendSequence = 0; replayWindow = RadioReplayWindow()
    }
    func connect(contactID: String) {
        guard isActive, contacts.contains(where: { $0.id == contactID }), approved.isEmpty,
              invitation == nil else { return }
        error = nil; requestedContactID = contactID
        if let peer = nearby.first(where: { $0.contact.id == contactID }) { invite(peer) }
    }
    func invite(_ neighbor: RadioNeighbor) {
        guard isActive, let session, approved.isEmpty, invitation == nil,
              contacts.contains(neighbor.contact), nearby.contains(where: { $0.id == neighbor.id }),
              let context = try? RadioContactSecurity.invitation(privateKey: privateKey, contactKey: neighbor.contact.publicKey,
                  sender: localPeer.displayName, recipient: neighbor.id) else { return }
        requestedContactID = neighbor.contact.id
        approved[neighbor.id] = neighbor; inviting.insert(neighbor.id)
        browser?.invitePeer(neighbor.peer, to: session, withContext: context, timeout: 25)
        expireConnection(neighbor, session: session)
    }
    private func expireConnection(_ neighbor: RadioNeighbor, session: MCSession) {
        Task { [weak self, weak session] in
            try? await Task.sleep(for: .seconds(26))
            guard let self, self.session === session, self.inviting.contains(neighbor.id) else { return }
            self.stop()
            self.error = "No se completó la conexión. Ambos deben tenerse agregados, permitir Radio y mantenerla abierta."
        }
    }
    func respond(_ accepted: Bool) {
        invitationExpiry?.cancel(); invitationExpiry = nil
        let valid = accepted && invitation.map { contacts.contains($0.contact) } == true
        if valid, let invitation, let session {
            approved[invitation.id] = invitation; inviting.insert(invitation.id)
            requestedContactID = invitation.contact.id
            expireConnection(invitation, session: session)
        }
        invitationHandler?(valid, valid ? session : nil)
        invitation = nil; invitationHandler = nil
    }
    func announceChannel() { send(RadioPacket(.presence, channel: channel), all: true) }
    private func send(_ packet: RadioPacket, to neighbor: RadioNeighbor) -> Bool {
        guard sendSequence < UInt64.max else { return false }
        sendSequence += 1
        guard let session, contacts.contains(neighbor.contact), session.connectedPeers.contains(neighbor.peer),
              let json = try? JSONEncoder().encode(RadioPrivateMessage(sequence: sendSequence, packet: packet)),
              let sealed = try? RadioContactSecurity.seal(json, privateKey: privateKey, contactKey: neighbor.contact.publicKey,
                  sender: localPeer.displayName, recipient: neighbor.id) else { return false }
        do { try session.send(sealed, toPeers: [neighbor.peer], with: packet.kind == .audio ? .unreliable : .reliable); return true }
        catch { self.error = "Se perdió la conexión con tu contacto."; return false }
    }
    @discardableResult func send(_ packet: RadioPacket, all: Bool = false) -> Bool {
        guard isActive, packet.isValid else { return false }
        // One private conversation. Never broadcast audio to discovered devices.
        guard let neighbor = connected.first, all || neighbor.channel == packet.channel else { return false }
        return send(packet, to: neighbor)
    }
}

extension LocalRadioTransport: MCNearbyServiceBrowserDelegate, MCNearbyServiceAdvertiserDelegate, MCSessionDelegate {
    nonisolated func browser(_ browser: MCNearbyServiceBrowser, foundPeer peerID: MCPeerID, withDiscoveryInfo info: [String: String]?) {
        let fingerprint = info?["key"]; let compatible = info?["v"] == "2"
        Task { @MainActor in
            guard self.browser === browser, self.isActive, compatible,
                  let contact = self.contacts.first(where: { $0.fingerprint == fingerprint }),
                  self.nearby.count < 128 else { return }
            let neighbor = RadioNeighbor(peer: peerID, contact: contact)
            if !self.nearby.contains(where: { $0.id == neighbor.id }) { self.nearby.append(neighbor) }
            if self.requestedContactID == contact.id { self.invite(neighbor) }
        }
    }
    nonisolated func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {
        Task { @MainActor in
            guard self.browser === browser else { return }
            self.nearby.removeAll { $0.peer == peerID }
        }
    }
    nonisolated func browser(_ browser: MCNearbyServiceBrowser, didNotStartBrowsingForPeers error: Error) {
        Task { @MainActor in
            guard self.browser === browser else { return }
            self.stop(); self.error = "Activa Wi-Fi, Bluetooth y el permiso de red local en Ajustes."
        }
    }
    nonisolated func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didNotStartAdvertisingPeer error: Error) {
        Task { @MainActor in
            guard self.advertiser === advertiser else { return }
            self.stop(); self.error = "No pudimos activar Radio. Revisa el permiso de red local en Ajustes."
        }
    }
    nonisolated func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didReceiveInvitationFromPeer peerID: MCPeerID, withContext context: Data?, invitationHandler: @escaping (Bool, MCSession?) -> Void) {
        Task { @MainActor in
            guard self.advertiser === advertiser, self.isActive, self.invitation == nil,
                  self.approved.isEmpty, let context, context.count <= 512,
                  let proof = try? JSONDecoder().decode(RadioContactSecurity.Invitation.self, from: context),
                  let contact = self.contacts.first(where: { $0.fingerprint == proof.fingerprint }),
                  RadioContactSecurity.verifyInvitation(context, privateKey: self.privateKey, contactKey: contact.publicKey,
                      sender: peerID.displayName, recipient: self.localPeer.displayName) else {
                invitationHandler(false, nil); return
            }
            guard self.usedInvitations.count < 512,
                  self.usedInvitations.insert(RadioContactSecurity.fingerprint(context)).inserted else {
                invitationHandler(false, nil); return
            }
            // A valid proof is not consent: the saved contact must still accept the conversation.
            self.invitation = RadioNeighbor(peer: peerID, contact: contact)
            self.invitationHandler = invitationHandler
            self.invitationExpiry = Task { [weak owner = self] in
                try? await Task.sleep(for: .seconds(24))
                guard !Task.isCancelled else { return }; owner?.respond(false)
            }
        }
    }
    nonisolated func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        Task { @MainActor in
            guard self.session === session, self.isActive else { return }
            if state == .connected {
                guard let neighbor = self.approved[peerID.displayName], self.contacts.contains(neighbor.contact) else { return }
                // Not shown as connected until a contact-key-authenticated presence is received.
                _ = self.send(RadioPacket(.presence, channel: self.channel), to: neighbor)
            } else if state == .notConnected {
                let hadLink = self.approved[peerID.displayName] != nil
                self.connected.removeAll { $0.peer == peerID }
                self.inviting.remove(peerID.displayName); self.approved.removeValue(forKey: peerID.displayName)
                if hadLink { self.stop(); self.onDisconnect?(peerID.displayName) }
            }
        }
    }
    nonisolated func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        guard data.count >= 28, data.count <= 8192 else { return }
        Task { @MainActor in
            guard self.session === session, self.isActive, session.connectedPeers.contains(peerID),
                  let neighbor = self.approved[peerID.displayName], self.contacts.contains(neighbor.contact),
                  let json = try? RadioContactSecurity.open(data, privateKey: self.privateKey, contactKey: neighbor.contact.publicKey,
                      sender: peerID.displayName, recipient: self.localPeer.displayName),
                  json.count <= 4096,
                  let message = try? JSONDecoder().decode(RadioPrivateMessage.self, from: json),
                  message.packet.isValid, self.replayWindow.accept(message.sequence) else { return }
            let packet = message.packet
            if packet.kind == .presence {
                let first = self.connected.isEmpty
                self.connected = [RadioNeighbor(peer: peerID, contact: neighbor.contact, channel: packet.channel)]
                self.inviting.remove(peerID.displayName)
                if first { self.announceChannel(); self.onConnect?() }
            } else if let authenticated = self.connected.first(where: { $0.peer == peerID }) {
                self.onPacket?(packet, authenticated)
            }
        }
    }
    nonisolated func session(_ session: MCSession, didReceive stream: InputStream, withName streamName: String, fromPeer peerID: MCPeerID) { stream.close() }
    nonisolated func session(_ session: MCSession, didStartReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, with progress: Progress) { progress.cancel() }
    nonisolated func session(_ session: MCSession, didFinishReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, at localURL: URL?, withError error: Error?) {}
}
