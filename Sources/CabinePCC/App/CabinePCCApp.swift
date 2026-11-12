import SwiftUI
import AppKit

// Cabine PCC -- the control centre of Cabine cabs, as an app.
//
// The app is a node (Core/Node/PCCNode.swift) and its windows. The node is
// what runs: the PCC with its library of lines and the engine behind it,
// the SCADA alarm log, the DCL shell and its telnet server. It is started
// by the application delegate when the app has launched, not by a window
// when it appears: on a Mac whose screen is locked no window appears, and
// the cabs must find their PCC all the same.
@main
struct CabinePCCApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        WindowGroup("PCC Dispatcher", id: "control") {
            PCCDispatcherWindow()
                .environmentObject(delegate.node.language)
                .environmentObject(delegate.node.world)
                .environmentObject(delegate.node.link)
                .environmentObject(delegate.node.telnet)
        }
        .windowResizability(.contentMinSize)
        .defaultSize(width: 1200, height: 1080)
        .restorationDisabled()
        .commands {
            // Replace the standard File > New with an opener that spawns a
            // fresh DCL terminal session (each carries its own DCLEngine).
            CommandGroup(replacing: .newItem) {
                NewTerminalCommand(language: delegate.node.language)
            }
        }

        // Data-driven group keyed by DCLSessionID: each distinct session id
        // opens a separate window, and DCLShellWindow gives each one its own
        // DCLEngine -- so terminals are fully independent logins (separate
        // transcript / symbols / history / MAIL browse state), the same way
        // each telnet connection already gets its own engine.
        WindowGroup("DCL Terminal", id: "dcl", for: DCLSessionID.self) { _ in
            DCLShellWindow(node: delegate.node)
                .environmentObject(delegate.node.language)
        } defaultValue: {
            DCLSessionID()
        }
        .windowResizability(.contentMinSize)
        .restorationDisabled()
    }
}

/// Starts the node when the app has launched, and stops it when the app
/// quits. Nothing here waits for a window.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    /// The node of this app: made on first use, which is before any window.
    private(set) lazy var node = PCCNode(environment: .app())

    func applicationDidFinishLaunching(_ notification: Notification) {
        if let other = otherRunningInstance() {
            refuseDuplicateLaunch(other: other)
            return
        }
        node.start()
    }

    /// The cabs are told that the PCC is closing.
    func applicationWillTerminate(_ notification: Notification) {
        node.stop()
    }

    /// The PCC runs on with its windows closed: its cabs are still on the
    /// line. A click on the Dock icon opens the dispatcher again.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    /// Looks for another running Cabine PCC on this Mac. A second instance
    /// would fail to bind the telnet port, settle on another port for the
    /// cabs and fight over the shared store, so refuse the duplicate launch
    /// outright.
    ///
    /// `isFinishedLaunching` filters out app entries that NSWorkspace
    /// reports transiently during macOS session restore -- if we don't
    /// require the other instance to be fully launched, a system-restored
    /// ghost can cause every fresh launch to false-positive on itself.
    private func otherRunningInstance() -> NSRunningApplication? {
        guard let bundleId = Bundle.main.bundleIdentifier else { return nil }
        let mine = ProcessInfo.processInfo.processIdentifier
        return NSRunningApplication.runningApplications(withBundleIdentifier: bundleId)
            .first { $0.processIdentifier != mine && $0.isFinishedLaunching }
    }

    private func refuseDuplicateLaunch(other: NSRunningApplication) {
        // Defer the modal + terminate so we're running OUTSIDE the AppKit
        // launch sequence that called us: an alert run from inside it can
        // be dropped.
        let pid = other.processIdentifier
        let french = (Locale.preferredLanguages.first ?? "en").hasPrefix("fr")
        DispatchQueue.main.async {
            let alert = NSAlert()
            alert.alertStyle = .critical
            alert.messageText = Strings.lookup("launch.duplicate.title", lang: french ? .fr : .en)
            alert.informativeText = String(format: Strings.lookup("launch.duplicate.text", lang: french ? .fr : .en), Int(pid))
            alert.addButton(withTitle: Strings.lookup("launch.duplicate.quit", lang: french ? .fr : .en))
            alert.addButton(withTitle: Strings.lookup("launch.duplicate.activate", lang: french ? .fr : .en))
            let response = alert.runModal()
            if response == .alertSecondButtonReturn {
                other.activate()
            }
            NSApp.terminate(nil)
        }
    }
}

private extension Scene {
    // Opts each WindowGroup out of macOS session restore so the app
    // launches in its declared layout rather than reopening whatever the
    // user last had on screen.
    func restorationDisabled() -> some Scene {
        self.restorationBehavior(.disabled)
    }
}

/// Identifies one DCL terminal window. Each distinct value drives a
/// separate window in the "dcl" WindowGroup; the fresh UUID means every
/// open request spawns a new, independent session rather than re-focusing
/// an existing one (SwiftUI only reuses a window when the presented value
/// matches one already on screen).
struct DCLSessionID: Hashable, Codable {
    var id: UUID = UUID()
}

/// File menu command that opens a brand-new DCL terminal session. Lives in
/// a view so it can read the `openWindow` action from the environment.
private struct NewTerminalCommand: View {
    @ObservedObject var language: AppLanguage
    @Environment(\.openWindow) private var openWindow
    var body: some View {
        Button(language.t("menu.newterminal")) {
            openWindow(id: "dcl", value: DCLSessionID())
        }
        .keyboardShortcut("t", modifiers: [.command, .shift])
    }
}
