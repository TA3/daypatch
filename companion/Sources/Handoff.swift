// Passkey handoff (daypatch://handoff, sent by Dia ✦ as it quits). Passkeys from
// Apple Passwords only work in Dia's own, unmodified app, so DayPatch opens the
// original Dia on the same profile, shows a small "Back to Dia ✦" panel, and
// reopens Dia ✦ when the user clicks it or quits the original.
import AppKit
import SwiftUI

@MainActor
final class Handoff: ObservableObject {
    static let shared = Handoff()

    private(set) var isActive = false
    private var original: NSRunningApplication?
    private var panel: NSPanel?
    private var observer: NSObjectProtocol?
    /// Called when the handoff ends (so DayPatch can quit if it has nothing else to do).
    var onFinish: (() -> Void)?

    /// The untouched, Dia-signed app: the backup when Dia itself is patched, the
    /// regular Dia in copy mode.
    static var originalApp: URL? {
        let url = PatchEngine.mode == .inPlace ? PatchEngine.backup : PatchEngine.source
        guard FileManager.default.fileExists(atPath: url.path), !PatchEngine.isPatched(url) else { return nil }
        return url
    }

    func start() {
        if isActive { panel?.orderFrontRegardless(); return }
        guard let app = Self.originalApp else {
            notifyUser("Couldn't open the original Dia", "Patch Dia once with DayPatch, then try again.")
            return
        }
        isActive = true
        Task {
            // Dia ✦ is quitting. Chromium locks the profile until it has fully exited;
            // if it doesn't quit (e.g. the link came from somewhere else), do nothing.
            for _ in 0..<150 where PatchEngine.patchedIsRunning { try? await Task.sleep(nanoseconds: 200_000_000) }
            guard !PatchEngine.patchedIsRunning else { finish(reopen: false); return }
            do {
                let cfg = NSWorkspace.OpenConfiguration()
                cfg.activates = true
                let running = try await NSWorkspace.shared.openApplication(at: app, configuration: cfg)
                original = running
                observer = NSWorkspace.shared.notificationCenter.addObserver(
                    forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main
                ) { [weak self] note in
                    guard let quit = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                          quit.processIdentifier == running.processIdentifier else { return }
                    MainActor.assumeIsolated { self?.finish(reopen: true) }
                }
                showPanel()
            } catch {
                notifyUser("Couldn't open the original Dia", error.localizedDescription)
                finish(reopen: true)
            }
        }
    }

    /// Quits the original Dia; its exit brings Dia ✦ back.
    func back() {
        guard let o = original, !o.isTerminated else { finish(reopen: true); return }
        o.terminate()
    }

    private func finish(reopen: Bool) {
        if let observer { NSWorkspace.shared.notificationCenter.removeObserver(observer) }
        observer = nil
        original = nil
        panel?.close()
        panel = nil
        Task {
            if reopen {
                try? await Task.sleep(nanoseconds: 500_000_000)   // let the profile lock go
                _ = try? await NSWorkspace.shared.openApplication(at: PatchEngine.destination, configuration: .init())
            }
            isActive = false
            onFinish?()
        }
    }

    private func showPanel() {
        let host = NSHostingView(rootView: HandoffPanelView(back: { [weak self] in self?.back() }))
        host.frame.size = host.fittingSize
        let p = NSPanel(contentRect: host.frame, styleMask: [.nonactivatingPanel, .borderless], backing: .buffered, defer: false)
        p.isFloatingPanel = true
        p.level = .floating
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        p.backgroundColor = .clear
        p.isOpaque = false
        p.hasShadow = true
        p.isMovableByWindowBackground = true
        p.contentView = host
        if let screen = NSScreen.main {
            let v = screen.visibleFrame
            p.setFrameOrigin(NSPoint(x: v.midX - host.frame.width / 2, y: v.maxY - host.frame.height - 12))
        }
        p.orderFrontRegardless()
        panel = p
    }
}

private struct HandoffPanelView: View {
    let back: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(nsImage: DayPatchIcon.appIcon(size: 64)).resizable().frame(width: 28, height: 28)
            VStack(alignment: .leading, spacing: 1) {
                Text("Original Dia is open for passkeys").font(.system(size: 13, weight: .semibold))
                Text("Sign in, then go back.").font(.system(size: 11)).foregroundStyle(.secondary)
            }
            Button("Back to \(PatchEngine.appName)", action: back)
                .keyboardShortcut(.defaultAction)
                .controlSize(.regular)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Color.primary.opacity(0.08)))
        .padding(1)
    }
}
