#if DEBUG && targetEnvironment(simulator) && canImport(WebRTC)
import SwiftUI
import CoreImage
@preconcurrency import WebRTC

nonisolated final class FilterFrameProbe: NSObject, RTCVideoRenderer, @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    private var corner = 0.0
    func setSize(_ size: CGSize) {}
    func renderFrame(_ frame: RTCVideoFrame?) {
        guard let frame else { return }
        let buffer = frame.buffer.toI420()
        var sum = 0.0
        for y in 0..<min(12, Int(buffer.height)) { for x in 0..<min(12, Int(buffer.width)) { sum += Double(buffer.dataY[y * Int(buffer.strideY) + x]) } }
        lock.lock(); count += 1; corner = sum / 144; lock.unlock()
    }
    func snapshot() -> (count: Int, corner: Double) { lock.lock(); defer { lock.unlock() }; return (count, corner) }
}

@MainActor @Observable final class CallFilterSimulatorCheck {
    var status = "Preparando filtros…"
    var previews: [VideoCallFilterType: UIImage] = [:]
    var result = ""
    func run() async {
        guard DesignPreviewData.isEnabled else { return }
        let documents = URL.documentsDirectory
        let folder = documents.appending(path: "filter-check", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let context = CIContext()
        let format = UIGraphicsImageRendererFormat(); format.scale = 1
        let rawImage = UIGraphicsImageRenderer(size: CGSize(width: 360, height: 640), format: format).image { renderer in
            let c = renderer.cgContext
            UIColor(red: 0.35, green: 0.66, blue: 0.71, alpha: 1).setFill(); c.fill(CGRect(x: 0, y: 0, width: 360, height: 640))
            UIColor(red: 0.17, green: 0.33, blue: 0.38, alpha: 1).setFill(); c.fill(CGRect(x: 0, y: 460, width: 360, height: 180))
            UIColor(red: 0.94, green: 0.54, blue: 0.28, alpha: 1).setFill(); c.fillEllipse(in: CGRect(x: 35, y: 390, width: 290, height: 330))
            UIColor(red: 0.21, green: 0.12, blue: 0.14, alpha: 1).setFill(); c.fillEllipse(in: CGRect(x: 75, y: 165, width: 210, height: 255))
            UIColor(red: 0.95, green: 0.74, blue: 0.57, alpha: 1).setFill(); c.fillEllipse(in: CGRect(x: 95, y: 210, width: 170, height: 220))
            UIColor(red: 0.21, green: 0.12, blue: 0.14, alpha: 1).setFill(); c.fillEllipse(in: CGRect(x: 125, y: 290, width: 12, height: 20)); c.fillEllipse(in: CGRect(x: 220, y: 290, width: 12, height: 20))
            c.fillEllipse(in: CGRect(x: 162, y: 350, width: 36, height: 12))
            ("CÁMARA DE PRUEBA" as NSString).draw(at: CGPoint(x: 30, y: 45), withAttributes: [.font: UIFont.systemFont(ofSize: 24, weight: .bold), .foregroundColor: UIColor.white])
        }
        let raw = CIImage(cgImage: rawImage.cgImage!)
        let renderer = CallFilterRenderer()
        var checks: [String: Bool] = [:]
        var times: [String: Double] = [:]
        for filter in VideoCallFilterType.allCases {
            let start = ProcessInfo.processInfo.systemUptime
            if let pixel = renderer.render(raw, settings: .init(type: filter), time: 2, gift: (.star, 1)), let cg = context.createCGImage(CIImage(cvPixelBuffer: pixel), from: raw.extent) {
                let image = UIImage(cgImage: cg); previews[filter] = image
                try? image.pngData()?.write(to: folder.appending(path: "\(filter.rawValue).png"))
                checks["render_\(filter.rawValue)"] = true
            } else { checks["render_\(filter.rawValue)"] = false }
            times[filter.rawValue] = (ProcessInfo.processInfo.systemUptime - start) * 1000
        }
        guard let rawBuffer = renderer.render(raw, settings: .init(), time: 0) else { status = "Falló la imagen de prueba"; return }
        let rotated = renderer.upright(buffer: rawBuffer, rotation: ._90)
        checks["orientation_90"] = rotated.extent.width == 640 && rotated.extent.height == 360
        let a = WebRTCPeerService(testAudioDevice: SimulatorPCMDevice(transmits: false))
        let b = WebRTCPeerService(testAudioDevice: SimulatorPCMDevice(transmits: false))
        defer { a.endCall(); b.endCall() }
        let config = CallICEConfiguration(iceServers: [], expiresAt: Date().timeIntervalSince1970 + 180, iceTransportPolicy: "relay")
        a.configureICE(config); b.configureICE(config)
        a.onLocalSDPGenerated = { type, sdp in if type == "offer" { b.handleRemoteOffer(sdp: sdp, isVideo: true) } }
        b.onLocalSDPGenerated = { type, sdp in if type == "answer" { a.handleRemoteAnswer(sdp: sdp) } }
        a.onIceCandidateGenerated = { mid, line, candidate in b.handleRemoteIceCandidate(sdpMid: mid, sdpMLineIndex: Int32(line), candidate: candidate) }
        b.onIceCandidateGenerated = { mid, line, candidate in a.handleRemoteIceCandidate(sdpMid: mid, sdpMLineIndex: Int32(line), candidate: candidate) }
        a.startCall(isVideo: true)
        var serial: Int64 = 0
        func pump(_ frames: Int) async {
            for _ in 0..<frames {
                serial += 1
                let frame = RTCVideoFrame(buffer: RTCCVPixelBuffer(pixelBuffer: rawBuffer), rotation: ._0, timeStampNs: Int64(ProcessInfo.processInfo.systemUptime * 1_000_000_000))
                a.injectFilterTestFrame(frame)
                try? await Task.sleep(for: .milliseconds(90))
            }
        }
        status = "Conectando dos extremos de video locales…"
        await pump(40)
        let remote = FilterFrameProbe(), preview = FilterFrameProbe()
        b.remoteVideoTrack?.add(remote); a.filterPreviewTrack?.add(preview)
        defer { b.remoteVideoTrack?.remove(remote); a.filterPreviewTrack?.remove(preview) }
        await pump(20)
        let natural = remote.snapshot()
        checks["remote_video"] = natural.count > 0
        a.previewFilter(.init(type: .catverse))
        await pump(30)
        checks["preview_only"] = preview.snapshot().count > 0 && preview.snapshot().corner < 45 && abs(remote.snapshot().corner - natural.corner) < 12
        a.closeFilterPreview()
        for filter in VideoCallFilterType.allCases where filter != .normal {
            status = "Verificando envío: \(filter.title)…"
            let before = remote.snapshot().count
            a.applyFilter(.init(type: filter)); await pump(30)
            checks["transmitted_\(filter.rawValue)"] = remote.snapshot().count > before + 3
            if filter == .catverse { checks["catverse_replaces_camera"] = remote.snapshot().corner < 45 }
        }
        status = "Comprobando consentimiento del portal…"
        checks["effects_channel"] = a.effectsReady && b.effectsReady
        a.inviteToPortal(); await pump(5)
        if case .invited = b.portalSession.phase { checks["portal_invitation"] = true } else { checks["portal_invitation"] = false }
        checks["portal_requires_consent"] = !a.portalSession.connected && !b.portalSession.connected && b.videoFilter.type == .normal
        b.answerPortal(accept: true, reducedMotion: false); await pump(5)
        checks["portal_accepted"] = a.portalSession.connected && b.portalSession.connected && b.videoFilter.type == .duoPortal
        a.sendPortalGift(.fish); await pump(5)
        checks["portal_gift"] = b.portalNotice == "Recibiste: Pez"
        a.leavePortal(); await pump(5)
        checks["portal_closed_restores_camera"] = !a.portalSession.connected && !b.portalSession.connected && b.videoFilter.type == .normal
        a.previewFilter(.init(type: .catverse)); await pump(5)
        a.setCameraEnabled(false); await pump(5)
        let stopped = preview.snapshot().count
        await pump(10)
        checks["camera_off_stops_preview"] = preview.snapshot().count == stopped
        a.setCameraEnabled(true); await pump(10)
        checks["camera_on_resumes"] = preview.snapshot().count > stopped
        a.endCall(); b.endCall()
        checks["cleanup"] = a.localVideoTrack == nil && a.filterPreviewTrack == nil && a.videoFilter.type == .normal && a.portalSession.phase == .idle && !a.effectsReady
        let passed = checks.values.allSatisfy { $0 }
        let report: [String: Any] = ["passed": passed, "checks": checks, "firstRenderMilliseconds": times, "date": Date().ISO8601Format(), "scope": "Synthetic frames, local WebRTC peers, no camera, microphone or external server"]
        if let data = try? JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]) { try? data.write(to: folder.appending(path: "result.json")) }
        result = "\(passed ? "PASS" : "FAIL") · \(checks.values.filter { $0 }.count)/\(checks.count)"
        status = passed ? "Filtros verificados en video local" : "Revisar comprobaciones fallidas"
    }
}

struct CallFilterSimulatorCheckView: View {
    @State private var check = CallFilterSimulatorCheck()
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("MYAOW / PRIMERA COLECCIÓN").font(.caption.weight(.semibold)).tracking(2).foregroundStyle(MyaowColor.orange)
                Text("Otra forma de verte.").font(.largeTitle.bold())
                Text(check.status).font(.subheadline).foregroundStyle(.secondary)
                if !check.result.isEmpty { Text(check.result).font(.headline.monospaced()).foregroundStyle(check.result.hasPrefix("PASS") ? .green : .red) }
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 16) {
                    ForEach(VideoCallFilterType.allCases.filter { $0 != .normal }) { filter in
                        VStack(alignment: .leading, spacing: 8) {
                            if let image = check.previews[filter] { Image(uiImage: image).resizable().scaledToFit().clipShape(RoundedRectangle(cornerRadius: 18)) }
                            Text(filter.title).font(.subheadline.bold())
                        }
                    }
                }
                Text("Imagen ilustrada de prueba. El seguimiento del rostro requiere validación con cámara en iPhone.").font(.caption).foregroundStyle(.secondary)
            }.padding(24)
        }.background(MyaowColor.charcoal).foregroundStyle(.white).task { await check.run() }
    }
}
#endif
