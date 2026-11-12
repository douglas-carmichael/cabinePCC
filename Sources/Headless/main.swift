import Foundation

// cabinepcc-headless -- the PCC with no window.
//
// The same core as the app (Sources/CabinePCC/Core): the node, the link to
// the engine, the DCL shell and its telnet server. What the app does from
// its application delegate, this does from its command line:
//
//   --serve      the PCC and the telnet DCL, until it is told to stop
//   --selftest   the DCL's SELFTEST, then a scenario with scripted cabs
//   --dcl        one command against a fresh node, printed as a terminal
//                would show it
//
// Everything runs on the main actor, as in the app, and the main run loop
// gives the node its timers.

let options: HeadlessOptions
do {
    options = try HeadlessOptions(Array(CommandLine.arguments.dropFirst()))
} catch let problem as HeadlessOptions.Problem {
    FileHandle.standardError.write(Data(("cabinepcc-headless: " + problem.text + "\n\n" + HeadlessOptions.usage).utf8))
    exit(2)
}

// A reader that has gone away must not end a server: a write to it fails,
// and that is all.
signal(SIGPIPE, SIG_IGN)
// Lines of output are whole when they are written, to a file as to a terminal.
setvbuf(stdout, nil, _IOLBF, 0)

Task { @MainActor in
    let status: Int32
    switch options.mode {
    case .help:
        print(HeadlessOptions.usage)
        status = 0
    case .serve:
        status = await Headless.serve(options)
    case .selfTest:
        status = await SelfTest(options).run()
    case .dcl:
        status = await Headless.dcl(options)
    }
    exit(status)
}

// The run loop needs something to wait on before the node has started.
let keepAlive = Timer(timeInterval: 3_600, repeats: true) { _ in }
RunLoop.main.add(keepAlive, forMode: .common)
RunLoop.main.run()
