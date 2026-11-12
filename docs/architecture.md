# Architecture

How cabinePCC is put together: the two programs and the core they share, the node that runs whether or
not a window is open, the link to the engine, the DCL shell, the windows, and the headless tool with its
self-test. What the PCC does on the wire is in [cabine-link.md](cabine-link.md); the engine's own account
of itself is in [Engine/README.md](../Engine/README.md).

## Two programs, one core

`project.yml` generates `CabinePCC.xcodeproj` with two targets, and both compile the same core.

| Target | Sources | Is |
|---|---|---|
| `CabinePCC` | `Sources/CabinePCC/Core` and `Sources/CabinePCC/App` | The app: the PCC Dispatcher and the DCL Terminal windows |
| `cabinepcc-headless` | `Sources/CabinePCC/Core` and `Sources/Headless` | A command-line tool: the same PCC with no window, its self-test, and a way to print what a command shows |

Everything but the windows is in Core, so everything but the windows can be run and checked on a Mac
with nobody at it. Core has no view in it and waits for none.

Both link two local packages: `Engine` (the product `CabinePCCKit`: the wire, the simulation and the
server) and `DCLixKit` (a git submodule: the system-management layer of the shell). The engine's package
and its namespace are both called `CabinePCC`, so the app's module is `CabinePCCApp` and the tool's
`CabinePCCHeadless`, and Core names the engine's types in full: `CabinePCC.Server`,
`CabineWire.LinePackage`.

The `Lines/` folder goes into the app's resources as a folder, and beside the tool in the build
products, so each finds the library it was built with ([lines.md](lines.md)).

```
Sources/CabinePCC/Core/
    Node/           PCCNode, PCCEnvironment, PCCWorld
    Link/           PCCLink, LineLibrary, PCCText
    DCL/            the shell: DCLEngine and its extensions
    Networking/     DCLTelnetServer, LineDiscipline
    Localization/   AppLanguage, Strings
    Theme/          RetroTheme
Sources/CabinePCC/App/
    CabinePCCApp.swift, Views/
Sources/Headless/
    main, HeadlessOptions, Headless, HeadlessTerminal, VTScreen, ScriptedCab, SelfTest
```

## The node

`PCCNode` is one PCC: all that runs whether or not a window is open. It owns

| | |
|---|---|
| `environment` | Where the node keeps what it keeps, and what it listens on |
| `language` | `AppLanguage`: English or French, and the display skin |
| `world` | `PCCWorld`: who this node is, and the SCADA alarm log |
| `link` | `PCCLink`: the engine's host and its operator's desk |
| `telnet` | `DCLTelnetServer`: the shell on loopback |
| `sessions` | `DCLSessionCoordinator`: the DCL sessions that are open, windows and telnet alike |

`start()` starts the link (the PCC, its library, its line) and the telnet server; `stop()` tells the cabs
the PCC is closing and closes both. `makeSession(_:)` makes a `DCLEngine` for a window or a telnet
connection, and `attach(_:)` gives it the world, the link and the language.

**The services start when the program launches, not when a window appears.** The app's
`AppDelegate.applicationDidFinishLaunching` makes the node and starts it; the windows are handed the node
and only look at it. On a Mac whose screen is locked no window ever appears, and the PCC runs all the
same. The delegate also sees to it that one instance runs on a Mac (a second says so and quits), and
`applicationWillTerminate` stops the node. The headless tool does from its command line what the delegate
does.

### Where things are kept

`PCCEnvironment` is the only place in Core that knows of the user's preferences or home. It carries the
settings store, the root of the node's files, the folder of the lines the program was built with, the
two ports, and the names the node and its operator go by.

| | The app | The headless tool |
|---|---|---|
| Settings | `DefaultsSettings`: the app's own preferences domain, `net.dcarmichael.CabinePCC` | `MemorySettings`: they last as long as the process, and come from the command line |
| Files | `~/Library/Application Support/CabinePCC/` | `--serve`: the same folder, or `--store`. `--selftest` and `--dcl`: a scratch folder of their own, removed afterwards |
| PCC port | 5289, or any free port if it is taken | `--serve`: the same, or `--port`. Otherwise one the system chooses |
| Telnet port | 2324, on loopback | `--serve`: the same, or `--telnet`. Otherwise one the system chooses |

The settings are five, under `pcc.`: `enabled`, `lan`, `headway`, `name`, and `line`, the id of the line
the PCC was last on. The files are three folders: `COM/` (the command procedures and the mailbox),
`DCLix/` (DCLixKit's own) and `Lines/` (the operator's lines).

Because nothing else reaches for either, the self-test can run a whole node with scripted cabs and leave
the user's preferences and files exactly as they were. It checks that it has.

### The world

`PCCWorld` is what is left of metroSystem's `MetroWorld` once its railway is gone: the node's identity
(an id, a label, an OpenVMS node name made from the label) and the alarm log. The log keeps ISA-18.2's
behaviour: an alarm is raised unacknowledged, acknowledged, shelved and unshelved; a **process-driven**
point is raised again each scan while its cause stands (which raises nothing new) and returns to normal
when the scan no longer holds it; an **event** stands until the operator has acknowledged and cleared
it. Messages are stored in English and translated when they are shown, through
`Strings.alarmMessageKeys`.

The trains are not the world's. They are the engine's, and are read from its snapshot.

## The link

`PCCLink` hosts one `CabinePCC.Server` and is the desk between it and everything that shows or orders
the PCC. None of the simulation is done in it.

- **The server.** Started with the node unless the operator has disabled the PCC. It listens on every
  interface and advertises `_cabinepcc._tcp`, or on loopback only. It runs the engine on a queue of its
  own; the link asks it for a snapshot and gives it orders from the main actor, and each call waits for
  that queue. How it listens and the name it gives are fixed when a server is made, so a change to
  either makes a new one, on the line the old one was on. The new one starts when the old has let go of
  its port, and not before: started sooner it would find the port taken and settle on another, where no
  cab would look for it.
- **The library.** At each start the link reads every `*.line.json` the program was built with, then
  every one in the store's `Lines/` folder, and keeps each in the engine. A file that is not a good
  package is put in the journal with the reason, raises the alarm `PCC FICHIER`, and is skipped. Then the
  line the PCC was last on is taken up; if the library no longer holds it, the PCC is on no line and says
  so (`PCC LIGNE`). From each package's source the link reads one thing, `source.source`: where the data
  came from, which the licences ask to be shown.
- **The picture.** Four times a second it publishes the server's snapshot (the line, its clock, every
  train, every connection, the library), how the listener stands, and what the journal has gathered. The
  windows observe it; a DCL command asks for a fresh one first, so that what it prints is the moment it
  was typed.
- **The orders.** Which line; service, the general emergency stop, headway and fleet size; and for one
  train hold, emergency brake, message and call. Each returns an `Outcome`: done, or refused with a
  `Refusal`. Neither is text.
- **SCADA.** Each scan the link holds the process-driven points whose causes stand in the snapshot, and
  lets go of those whose causes have gone; a driver's report or call, read from the journal, is raised as
  an event ([dcl.md](dcl.md#the-alarms) has the table).
- **Settings.** Enabled, LAN, headway, name and the line last run, written through the node's settings
  store as they change.

`PCCText` puts all of it in the operator's words: a refusal, a journal line, a train's state, a cab's
authority, a line's credits. The Dispatcher and the DCL both go through it, so a window and a terminal
say the same thing of the same train, in the same language.

## The DCL shell

`DCLEngine` is one session: metroSystem's OpenVMS emulation, with its railway taken out and the PCC put
in. It lives on the main actor, as the link does.

| File | Holds |
|---|---|
| `DCLEngine.swift` | The session: `submit` (a line typed), `execute` (the dispatch, by prefix), the parser, the transcript and the terminal, `$STATUS`, the login banner and splash, the gated short forms |
| `DCLPCC.swift` | **The PCC's verbs**: `SHOW` and `SET` for `PCC`, `LINE`, `RAME`; `SHOW LINES`, `RAMES`, `CABS`, `CONNECTIONS`, `JOURNAL`; `START` and `STOP`; `F$PCC` and `F$RAME`; the PCC as OpenVMS processes |
| `DCLPasteboard.swift` | The SMG pasteboard: bordered displays, painted once and then updated row by row |
| `DCLMonitorPCC.swift` | The four monitors of the PCC, and the mimic board |
| `DCLForms.swift` | The two DECforms-style forms |
| `DCLMonitor.swift` | `MONITOR`: the PCC's classes, and OpenVMS's own |
| `DCLShow.swift`, `DCLSet.swift` | `SHOW` and `SET`: the dispatch of both, and the system's subjects |
| `DCLOperator.swift` | `ACKNOWLEDGE`, `SHELVE`, `UNSHELVE`, `REPLY`, `REQUEST`, `RUN` |
| `DCLFiles.swift`, `DCLEdt.swift`, `DCLMail.swift` | Files, the EDT editor, MAIL and the in-universe mail |
| `DCLScripting.swift`, `DCLScriptStore.swift` | Command procedures: symbols, `IF`, `GOTO`, substitution, lexical functions; the store and what it is seeded with |
| `DCLHelp.swift`, `DCLHelpText.swift`, `DCLHelpLibrary.swift` | `HELP`, its library of topics, and `SELFTEST` |
| `DCLixBridge.swift`, `HostStats.swift` | The bridge to DCLixKit; the Mac's own figures for `SHOW` and `MONITOR` |
| `DCLSessionCoordinator.swift` | Which of the open sessions writes the in-universe mail, so that it is written once |

**A command.** `execute` parses the line, resolves a short form (`TRAIN`, `LIGNE`) or a symbol, and
dispatches on the verb by prefix. A PCC verb asks the link for a fresh picture or gives it an order, and
prints what `PCCText` makes of the answer. A refusal sets a warning in `$STATUS`. Under `SELFTEST`
(`dryRun`) an order is named and not carried out.

**Two languages.** `tr(key)` reads the string table in the session's language. The words that differ
between the languages are gated: `matchesLoc(token, en:, fr:)` and `locQual(en:, fr:)` accept one
spelling of a pair, the session's. The short forms are built in and gated the same way, and a short form
of the other language is not handed to the symbol expander, so that nothing gets round the gate.

**A display that has the screen.** `LiveMode` says what does: nothing, a monitor, a form, or the screen
editor. While one does, `LineDiscipline` sends keys to it instead of the command line, and a timer calls
`refreshLiveDisplay()`. The PCC's monitors and forms build their rows as text and hand them to
`paint(_:)`, which writes only the rows that changed. They are the same code in a window and over
telnet.

**The rule of the shell**, which is metroSystem's: every documented verb is in `SELFTEST` and in the
`HELP` library. To add one, add a case to `DCLEngine.execute()`, write it in the right `DCL*.swift`, add
it to `selfTestLines` in `DCLHelp.swift`, and add its topic to `DCLHelpText.swift`. If it gives the
engine an order, it goes through `PCCLink`, answers with `pccMessage(_:_:)`, does nothing under `dryRun`,
and has its check in the headless self-test. Its place in [dcl.md](dcl.md) is made as
[the page is](#the-page-of-the-dcl).

`DCLTelnetServer` listens on loopback and gives each connection a session of its own. `LineDiscipline`
is the terminal's line editing and key handling, shared by the windows and telnet.

## The windows

`CabinePCCApp` has two scenes. Each window is handed the node by the application delegate.

- **PCC Dispatcher** (`PCCDispatcherWindow`, with `DispatcherPanels` and `AlarmPanel`). Fixed at the
  top: the banner, the status strip (node, listener, line, trains, cabs, telnet sessions, mode, alarms),
  the line's controls with a button for each line of the library, and the SCADA annunciator. Scrolling
  beneath: the PCC and its listener, the line diagram, a card for each cab with its orders, the
  connections, the trains, the journal, and the library with each line's credits. The foot opens a DCL
  Terminal, the credits and the help, and switches language and skin. An order that is refused says why,
  in red, where it was given.
- **DCL Terminal** (`DCLShellWindow`, `VTShellView`, `RetroTerminalView`). A VT320 drawn by hand, one
  session a window. The Dispatcher's foot and File ▸ New DCL Terminal open one; so does `-openDCL`
  given to the app at launch, beside the Dispatcher, and `-dcl "command"` opens one and types that
  command in it, through the same line discipline as a key. VT323 has no box-drawing characters and no
  geometric shapes: they come from a fallback font, wider than a cell. A rule is left to overlap the
  next cell, which is what joins it without a seam; a shape (a station's marker on the mimic board) is
  condensed to its cell.

`-node NAME` and `-user NAME` at launch name the node and its operator in place of the Mac and its user,
as `--node` and `--user` do for the headless tool; `-theme iso` starts in the ISA-101 skin. The pictures
in [README.md](README.md#the-pictures-and-the-samples) were taken with them.

The windows give their orders to the same `PCCLink` the DCL does and read the same published picture, so
neither knows anything the other does not.

`RetroTheme` and `RetroComponents` are metroSystem's look: amber phosphor on black in the VT323
typeface, and an ISA-101 skin beside it. The typeface is in `Resources/Fonts` with its licence, and is
registered through `ATSApplicationFontsPath`. The icon is drawn by `Scripts/makeicon.swift`:

```sh
swift Scripts/makeicon.swift Resources/Assets.xcassets/AppIcon.appiconset
```

## The headless tool

```
cabinepcc-headless --serve [--port n] [--telnet n] [--loopback] [--line id] [--name "name"]
                   [--store folder] [--lang en|fr] [--node name] [--user name]
cabinepcc-headless --selftest [--verbose] [--store folder]
cabinepcc-headless --dcl "command" [--keys "keys"] [--dcl "command" ...] [--lang en|fr]
                   [--line id] [--cabs n] [--settle seconds] [--store folder]
                   [--name "name"] [--node name] [--user name]
cabinepcc-headless --help
```

**`--serve`** runs the PCC and the telnet DCL until it is interrupted (CTRL/C, or SIGTERM), and then
tells the cabs that the PCC is closing. It is a real way to run the PCC.

| | |
|---|---|
| `--port n` | The port the cabs dial: 5289, and another if that one is taken |
| `--telnet n` | The port of the telnet DCL, on loopback: 2324 |
| `--loopback` | Listen on this Mac only, and do not advertise by Bonjour |
| `--line id` | The line to take up: 21 |
| `--name "name"` | The PCC's name, for the cabs' displays and for Bonjour |
| `--store folder` | Where the node keeps its files: `~/Library/Application Support/CabinePCC` |
| `--lang en\|fr` | The language the DCL sessions start in: English |
| `--node name`, `--user name` | The node's name and the operator's, in place of the Mac's and the user's |

Its settings are its command line: it reads nothing from the app's preferences and writes nothing to
them, so what `SET PCC` changes lasts as long as it runs.

It says where it listens, and then nothing until it is told to stop (the store's path is cut short
here):

```
$ cabinepcc-headless --serve --loopback --port 52891 --telnet 52324 --name "PCC LIGNE 21" --store …/store
cabinepcc-headless: store …/store
cabinepcc-headless: PCC "PCC LIGNE 21" listening on port 52891, loopback only
cabinepcc-headless: library: 6 lines; on Ligne 21 (21, rev 25030a0dde1f0c8b)
cabinepcc-headless: DCL on telnet: telnet localhost 52324
^C
cabinepcc-headless: closing
```

**`--dcl`** carries out commands, in order, against a fresh node on loopback, and prints what a terminal
would show. A command that takes over the screen prints one frame of it. `--cabs n` puts scripted cabs
in service first, `--settle s` lets the line run before the first command, and `--keys` presses keys in
the display of the command before it, ahead of the frame: characters, and `<TAB>`, `<UP>`, `<DOWN>`,
`<NEXT>`, `<PREV>`, `<RET>`, `<DEL>`, `<CTRL/W>`. The samples of [dcl.md](dcl.md) are made with it:

```sh
cabinepcc-headless --cabs 1 --settle 20 --dcl "SHOW CABS" --dcl "RUN RAME_DIR" --keys "21<TAB>"
```

What makes it possible is `HeadlessTerminal`: a DCL session with no terminal emulator behind it. What
the shell writes goes into `VTScreen`, a plain model of a VT220's screen that keeps the characters and
the cursor and drops the colours; what an operator would type goes in through the same `LineDiscipline`
the windows and telnet use. `ScriptedCab` is the other end of the wire: a socket that says `hello`,
asks for the line, joins, reports where it is and what it does, and keeps what the PCC sends it.

### The self-test

`--selftest` exits with 0 when every check passes and with 1 otherwise. It runs on ports of its own, with
its settings in memory and its files in a scratch folder that it removes, and its last checks are that
the user's store was neither made nor touched. `--verbose` prints what each command printed.

| Section | Checks |
|---|---|
| The DCL's `SELFTEST`, in English and in French; every verb it drives has its `HELP` topic | 5 |
| Launch: the library read, with a file that is refused; the line last run taken up | 15 |
| A PCC whose port is taken, and one whose line is not in the library: the alarms of both | 9 |
| The line: `SHOW LINES`, `SHOW LINE`, `SET LINE`, `START`, `STOP`, `EMERGENCY`, `RESUME` | 52 |
| The trains: `SHOW RAMES`, `SHOW RAME`, `SET RAME`, `START RAME`, `STOP RAME` | 30 |
| A cab: the line handed to it as a package and the journal saying so, `SHOW CABS`, `SHOW CONNECTIONS`, every order as the cab received it | 35 |
| The cab's alarms, each raised and returned to normal or cleared | 28 |
| Command procedures: `F$PCC`, `F$RAME`, the built-in symbols, `$STATUS`, `@WAITCAB` | 25 |
| The same desk in French: the gated words, the messages | 49 |
| A frame of each monitor, in both languages | 47 |
| The two forms: finding, the pages, every order asked and carried out | 41 |
| The cab leaves; `SET PCC`; the line changes, by command and on the form | 27 |
| The DCL over telnet | 4 |
| Nothing of the user's is touched | 3 |

370 checks at this writing. Each order is checked three ways: what the command printed, what the engine's
snapshot then held, and, for a cab, what the scripted cab received on the wire.

It does not check the windows. Nothing in it draws a SwiftUI view or reads a real terminal window: the
monitors and forms are checked as the characters they put on a VT220's screen, and the Dispatcher is not
checked at all. It also keeps to loopback: `SET PCC /LAN=ON`, Bonjour and the local network's permission
are not exercised.

## The page of the DCL

[dcl.md](dcl.md) is not written by hand. Its words are in `Scripts/dcl.template.md`, and each sample in
it is a placeholder there: `{{en-cab|SHOW CABS}}` is what the tool printed for `SHOW CABS` in the
scenario `en-cab`, from the line of its prompt to the next command's. `{{en-cab|SHOW CABS|2}}` is the
second time the scenario gives that command, and `{{selftest-en|SELFTEST|1|6..4}}` keeps the first six
lines and the last four of an output too long to quote whole.

```sh
Scripts/makedocs.sh [path to cabinepcc-headless]
```

runs the headless tool once for each scenario, a fresh node each time on loopback with its files in a
scratch folder, and `Scripts/filldocs.py` then fills the template and writes the page. Without an
argument the tool is looked for in `build/Build/Products/Debug`, where the build commands of the README
put it when they are given `-derivedDataPath build`. It takes a minute or two. There are six scenarios:
a cab in service (`en-cab`), the library and the PCC's own settings (`en-library`), the monitors and the
forms with two cabs (`en-screens`), the same desk in French (`fr`), the alarms (`en-alarms`), and
`SELFTEST` (`selftest-en`).

To change what the page says, change the template. To show a command the page does not have yet, add it
to a scenario in `Scripts/makedocs.sh` and put its placeholder in the template. A placeholder whose
command no scenario runs stops the build, so the page cannot go on quoting what the program no longer
prints. The node is named PCCVL1 and its operator OPERATOR in every scenario, so that the page shows
neither the Mac's name nor its user's. The times, the ports, and where each train is are those of the
run: they change from one run to the next, and nothing in the page's words depends on them.

## Continuous integration

Two workflows. `.github/workflows/engine.yml` builds the engine package and runs its own self-test.
`.github/workflows/app.yml` generates the project, builds both targets, and runs
`cabinepcc-headless --selftest`.

## What came from metroSystem

cabinePCC is a program of its own. It takes metroSystem's look and its shell by copy, and owns them from
here on; it is not built on metroSystem and does not follow it.

| | |
|---|---|
| **Kept as it was** | `RetroTheme`, `RetroComponents`, `KeyboardHost`; the string table's rules and `AppLanguage`; the OpenVMS emulation: files, EDT, MAIL, command procedures and the command store, `HELP` and its library, the system's `SHOW` and `SET` subjects and its `MONITOR` classes, `HostStats`, the DCLix bridge, the session coordinator |
| **Kept and changed** | The alarm log, now `PCCWorld`'s. `RetroTerminalView`, which condenses a shape from the fallback font to its cell, and `VTShellView`, which can be given a command to type at launch. The telnet server, on port 2324 and started by the node. `DCLEngine`, which takes its node name, its store and its operator from the node. The SMG pasteboard and the forms' machinery, which drew metroSystem's line monitor and board catalogue and now draw the PCC's. `SELFTEST`, which also fails a verb that is not recognised. `$STATUS`, which a command now reads as the command before left it, and `IF`, which takes an odd integer or a T or a Y for true, as DCL does. The system `MONITOR` classes, which now fit the screen they are given |
| **New** | `PCCNode`, `PCCEnvironment`, `PCCLink`, `LineLibrary`, `PCCText`; the PCC's verbs, lexical functions, monitors and forms; the Dispatcher's panels; the headless tool and its self-test |
| **Dropped** | The Lille loop and all that ran on it: `Train`, `Sim`, the fleet of `MetroWorld`; the VAL, CBTC and PRATIC backends; the hardware bridge and Modbus; the peer network and the cluster; the pupitre link; the 3D synoptic, Train Detail and Train Dynamics; `VALCP`, `OPEN`, `CLOSE`, `DIAGNOSE`, the brake, door and tyre utilities, the board catalogue, the TP training procedures; and every string and `HELP` topic that went with them |
