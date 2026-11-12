import Foundation
import Combine

// One PCC node: everything that runs whether or not a window is open.
//
// The app makes one when it launches and starts it from its application
// delegate; the headless tool makes one and starts it from its command
// line. Nothing here is a view, and nothing here waits for one: a Mac whose
// screen is locked, or a tool with no window at all, runs the same PCC.
//
//   world      who this node is, and the SCADA alarm log
//   link       the PCC: the engine's host and its operator's desk
//   telnet     the DCL shell on loopback, for a terminal emulator
//   sessions   the DCL sessions that are open, windows and telnet alike
//   language   English or French, and the display skin
@MainActor
final class PCCNode: ObservableObject {
    let environment: PCCEnvironment
    let language: AppLanguage
    let world: PCCWorld
    let link: PCCLink
    let telnet = DCLTelnetServer()
    let sessions = DCLSessionCoordinator()

    private(set) var isStarted = false

    /// - Parameters:
    ///   - environment: where the node keeps what it keeps, and what it
    ///     listens on.
    ///   - language: the language it starts in; the Mac's when nil.
    init(environment: PCCEnvironment, language: AppLanguage? = nil) {
        self.environment = environment
        self.language = language ?? AppLanguage()
        let world = environment.nodeLabel.map { PCCWorld(label: $0) } ?? PCCWorld()
        self.world = world
        link = PCCLink(world: world, environment: environment)
        telnet.attach(node: self)
    }

    /// Starts the services: the PCC with its library and its line, and the
    /// telnet DCL. Called once, when the program has launched.
    func start() {
        guard !isStarted else { return }
        isStarted = true
        link.start()
        telnet.start(port: environment.telnetPort)
    }

    /// Stops the services, for the end of the program: the cabs are told
    /// that the PCC is closing.
    func stop() {
        guard isStarted else { return }
        isStarted = false
        telnet.stop()
        link.closeForQuit()
    }

    /// A DCL session of this node, not yet attached: a window of the app,
    /// or a telnet connection.
    func makeSession(_ kind: DCLEngine.TerminalKind) -> DCLEngine {
        DCLEngine(terminalKind: kind, nodeName: world.nodeName, store: DCLScriptStore(root: environment.comFolder),
                  username: environment.operatorName)
    }

    /// Attaches a session to the node: it prints its login banner, and
    /// joins the set of sessions one of which writes the in-universe mail.
    func attach(_ engine: DCLEngine) {
        engine.attach(world: world, link: link, language: language)
        sessions.register(engine)
    }
}
