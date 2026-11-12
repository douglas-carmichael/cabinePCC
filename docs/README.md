# cabinePCC: the pages

cabinePCC is the control centre of the Cabine cabs: a PCC that keeps a library of lines, runs one of
them, and is the simulation behind every Cabine connected to it. The [README](../README.md) at the root
says what it is and how to build and run it. These pages go further.

| Page | What it is |
|---|---|
| [cabine-link.md](cabine-link.md) | **The wire**, protocol version 1: how a PCC and the cabs of Cabine talk. The transport, positions and time, the line package, the life of a connection, every message of each end, and what a cab can count on the PCC to do. It is the contract between the two programs |
| [dcl.md](dcl.md) | **The DCL**: every command of the PCC with its grammar and a sample of what it prints, the four monitors and the two forms with a frame of each, the lexical functions and symbols a command procedure reads the engine with, the same desk in French, and what is left of metroSystem's shell |
| [lines.md](lines.md) | **The lines**: what a package is, the six the program is built with, where the library is read from, how a line gets into it, and the sources and licences of the real lines' data |
| [architecture.md](architecture.md) | **How it is put together**: the two programs and the core they share, the node, the link to the engine, the shell, the windows, the headless tool and its self-test, and what came from metroSystem |
| [Engine/README.md](../Engine/README.md) | **The engine**: the package that speaks the wire and runs the line, its daemon, and how an app hosts it |
| [Lines/README.md](../Lines/README.md) | **The line files**, and the credits of their data beside them |

## Where to start

- To run a PCC for a Cabine: the [README](../README.md#build-and-run), then
  [dcl.md](dcl.md#the-pcc).
- To write the other end of the link, or to see what a cab is told: [cabine-link.md](cabine-link.md).
- To give a PCC a line it was not built with: [lines.md](lines.md#how-a-line-gets-into-the-library).
- To change the program: [architecture.md](architecture.md).

## The pictures and the samples

Three pictures of the app as it runs are in this folder, and the [README](../README.md) shows them: the
PCC Dispatcher in English (`pcc-dispatcher-en.png`) and in French (`pcc-dispatcher-fr.png`), and a DCL
Terminal on `MONITOR LINE` (`dcl-terminal.png`). They are of Ligne 21 with one cab in service as train
21. That cab is a real Cabine driven by its own windowless test tool, which is the name it goes by.

They are of the built app, launched on this Mac only with a name for its node and its operator, so that
they show neither the Mac's name nor its user's, and with a terminal opened on the monitor:

```sh
open -n CabinePCC.app --args -pcc.lan NO -pcc.name "PCC LIGNE 21" -node PCCVL1 -user OPERATOR \
     -dcl "MONITOR LINE"
open -n CabinePCC.app --args -pcc.lan NO -pcc.name "PCC LIGNE 21" -node PCCVL1 -user OPERATOR \
     -AppleLanguages "(fr)"
```

Each window was then photographed with `screencapture -l`, once the cab was under way.

The samples of [dcl.md](dcl.md) are what the terminal shows, character for character, made by the
headless tool: that page is not written by hand, and
[architecture.md](architecture.md#the-page-of-the-dcl) says how it is made.
