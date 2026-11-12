import Foundation
import Dispatch
import Darwin
import CabinePCCKit

// cabine-pccd: a headless PCC for Cabine cabs.
//
// It listens for cabs on TCP (docs/cabine-link.md), keeps a library of lines, runs the one its operator
// puts it on and hands it to the cabs, drives the automatic rames on it and supervises the cabs. Lines
// read from standard input are the operator's commands, so that a script can drive it.

// Line-buffer stdout so that what is printed shows promptly when piped to a file or a pager.
setvbuf(stdout, nil, _IOLBF, 0)

let options = Options.parse(Array(CommandLine.arguments.dropFirst()))

if options.selfTest {
    exit(SelfTest.run(fixtures: options.fixtures) ? 0 : 1)
}
if options.dumpLine {
    // The built-in line as a `.line.json` file would hold it: a package, with no source.
    let package = CabineWire.LinePackage(description: CabinePCC.testLine)
    FileHandle.standardOutput.write((try? package.encodedForFile()) ?? Data())
    exit(0)
}

let daemon = Daemon(options: options)
daemon.run()
dispatchMain()
