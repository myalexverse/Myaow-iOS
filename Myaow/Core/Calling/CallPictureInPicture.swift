import AVKit
import SwiftUI

/// iOS owns the floating window outside Myaow; in-app minimization uses the cat bubble.
@MainActor @Observable
final class CallPictureInPicture: NSObject, AVPictureInPictureControllerDelegate {
    static let shared = CallPictureInPicture()
    private var controller: AVPictureInPictureController?
    private var content: AVPictureInPictureVideoCallViewController?
    private var host: UIHostingController<CallPictureInPictureContent>?
    private weak var sourceView: UIView?
    private(set) var isActive = false
    var notice: String?
    func attach(_ view: UIView) {
        guard sourceView !== view, AVPictureInPictureController.isPictureInPictureSupported() else { return }
        sourceView = view
        let content = AVPictureInPictureVideoCallViewController()
        content.preferredContentSize = CGSize(width: 240, height: 240)
        let host = UIHostingController(rootView: CallPictureInPictureContent())
        content.addChild(host); content.view.addSubview(host.view); host.didMove(toParent: content)
        host.view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            host.view.leadingAnchor.constraint(equalTo: content.view.leadingAnchor), host.view.trailingAnchor.constraint(equalTo: content.view.trailingAnchor),
            host.view.topAnchor.constraint(equalTo: content.view.topAnchor), host.view.bottomAnchor.constraint(equalTo: content.view.bottomAnchor)
        ])
        let source = AVPictureInPictureController.ContentSource(activeVideoCallSourceView: view, contentViewController: content)
        let controller = AVPictureInPictureController(contentSource: source)
        controller.delegate = self; controller.canStartPictureInPictureAutomaticallyFromInline = true
        self.content = content; self.host = host; self.controller = controller
    }
    func start() {
        guard CallSessionService.shared.callState == .connected, let controller, controller.isPictureInPicturePossible else {
            notice = "iPhone no puede abrir la ventana flotante ahora. Puedes minimizar dentro de Myaow."; return
        }
        notice = nil; CallSessionService.shared.stopRadioTransmission(); controller.startPictureInPicture()
    }
    func stop() { controller?.canStartPictureInPictureAutomaticallyFromInline = false; controller?.stopPictureInPicture(); notice = nil }
    func pictureInPictureControllerDidStartPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        guard CallSessionService.shared.callState == .connected else { stop(); return }
        isActive = true
        CallSessionService.shared.minimize()
    }
    func pictureInPictureControllerDidStopPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) { isActive = false }
    func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController, failedToStartPictureInPictureWithError error: Error) {
        isActive = false
        notice = "No se pudo abrir la ventana flotante. La llamada sigue activa en Myaow."
    }
    func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController, restoreUserInterfaceForPictureInPictureStopWithCompletionHandler completionHandler: @escaping (Bool) -> Void) {
        CallSessionService.shared.isMinimized = false; completionHandler(true)
    }
}

struct CallPictureInPictureAnchor: UIViewRepresentable {
    func makeUIView(context: Context) -> UIView { UIView() }
    func updateUIView(_ uiView: UIView, context: Context) {
        DispatchQueue.main.async { if uiView.window != nil { CallPictureInPicture.shared.attach(uiView) } }
    }
}
private struct CallPictureInPictureContent: View {
    @State private var call = CallSessionService.shared
    @State private var peer = WebRTCPeerService.shared
    var body: some View {
        VStack(spacing: 8) {
            MyaowCatView(state: call.activeCallCatState, style: .darkOnOrange, size: 150, isInteractive: false, speakingLevel: peer.remoteSpeakingLevel, allowsBackgroundSpeech: CallPictureInPicture.shared.isActive)
            Text(call.activeCallContactName).font(.caption).lineLimit(1)
            Text(call.durationFormatted).font(.caption2.monospacedDigit())
        }.frame(maxWidth: .infinity, maxHeight: .infinity).background(Color.black).foregroundStyle(.white)
            .task(id: CallPictureInPicture.shared.isActive) {
                guard CallPictureInPicture.shared.isActive else { return }
                while !Task.isCancelled {
                    peer.sampleRemoteVoice()
                    do { try await Task.sleep(for: .milliseconds(100)) } catch { break }
                }
            }
    }
}
