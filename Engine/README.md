# The cabinePCC engine

The PCC end of the Cabine link: a dependency-free SwiftPM package (Foundation and Network.framework
only) that keeps a library of lines and runs one of them for the cabs of **Cabine**, the metro driving
simulator seen from the cab. The wire it speaks is specified in
[`docs/cabine-link.md`](../docs/cabine-link.md), protocol version 1; that page is the contract, and this
package is the engine behind it.

It has two products:

- **`CabinePCCKit`**, a library: the wire, the simulation and the server. It is the part the cabinePCC
  app hosts.
- **`cabine-pccd`**, an executable: the same engine with no window, driven from standard input.

The lines are the PCC's. It keeps a library of them, each a package of the description its engine runs
and the source a Cabine builds the line from; its operator puts it on one of them, and it hands that
line to every cab that asks for it. On that line it seeds automatic rames, drives them (even when only
one cab is connected), keeps every train apart in moving block, sends each cab the other trains five
times a second and its own movement authority, and puts what the cabs do in front of an operator.

## Build and run

```bash
cd Engine
swift build
swift run cabine-pccd --library ../Lines --line 21    # the repository's lines, on Ligne 21: port 5289, Bonjour
swift run cabine-pccd --library ../Lines              # the same library, on no line until it is told
swift run cabine-pccd --loopback --no-bonjour --verbose --line ../Lines/ligne-4.line.json
swift run cabine-pccd --dump-line                     # the built-in test line, as a line package
swift run cabine-pccd --selftest                      # exit status 0 or 1 (CI)
```

| Option | |
|---|---|
| `--port <n>` | Port to listen on. Default 5289; any free port if it is taken (the daemon says which); 0 lets the system choose |
| `--loopback` | Listen on 127.0.0.1 only |
| `--no-bonjour` | Do not advertise `_cabinepcc._tcp` |
| `--name <text>` | The PCC's name, in its `hello` and in Bonjour. Default `PCC <this Mac>` |
| `--headway <seconds>` | Seconds between trains each way that the fleet is sized for. Default 150 |
| `--rames <n>` | Fix the number of trains on the line, cabs included, instead of sizing it from the headway |
| `--turnback <seconds>` | Seconds a rame spends out of sight beyond a terminus. Default 60 |
| `--library <dir>` | Keep every `*.line.json` of a directory in the library at launch. A file that is not a good line is named, with the reason, and left out |
| `--line <id>` | Take up the line of the library that has that id, at launch |
| `--line <file>` | Keep the line of a `.line.json` file, and take it up at launch |
| `--seed <n>` | Seed of the random draws (dwell times): the same seed gives the same run. Default 1 |
| `--verbose` | Print the status table every 5 seconds |
| `--dump-line` | Print the built-in test line as a line package, and exit |
| `--selftest` | Run the self-test and exit |
| `--fixtures <dir>` | Where the self-test looks for `*.line.json`. Default `../Lines`, the repository's |

With no `--line` the PCC is on no line, and says so: it listens, answers `hello` and `lineRequest`,
and waits for `line <id>`.

Lines read from standard input are the operator's commands, so a script can drive the daemon. What
happens on the line (a line taken up, a cab connecting, joining, falling silent, reporting) is printed
as it happens, with the line's time of day.

| Command | |
|---|---|
| `status` | The line, every rame (number, kind, track, uM, speed, phase, doors, station) and every connection, with the line each cab holds |
| `lines` | The library: each line's id, revision, stations, length, whether it has a source, its name and its two ends; a star marks the one the PCC is on |
| `line <id>` | Take up the line of the library that has that id (refused while a cab is in service) |
| `line <file>` | Keep the line of a `.line.json` file, and take it up |
| `line none` | Close the line: the PCC is on none (refused while a cab is in service) |
| `start`, `stop` | Line service on, off |
| `hold <rame>`, `release <rame>` | Keep a rame at the platform it is at, or the next it reaches; let it go |
| `brake <rame>`, `unbrake <rame>` | Emergency brake of one rame |
| `brake all`, `unbrake all` | The general emergency stop |
| `msg <rame> <text>` | Words for a cab's display, 120 characters at most |
| `call <rame>` | Ring a cab's driver |
| `headway <seconds>` | Size the fleet for another headway |
| `rames <n>`, `rames auto` | Fix the number of trains, or size it from the headway again |
| `help` | The options and the commands |
| `quit [seconds]` | Tell the cabs the PCC is closing, close the line and exit |

`hold` and `brake` work on automatic rames as well as on cabs; `msg` and `call` are for cabs. Where the
library holds several revisions of a line, `line <id>` takes the one kept last.

Anything that speaks the wire can stand in for a cab. By hand, a cab that holds no line, asks for the
PCC's, and says `hello` again once it has it (the `rev` is the one in `Lines/ligne-21.line.json`):

```bash
swift run cabine-pccd --loopback --no-bonjour --library ../Lines --line 21 &
nc 127.0.0.1 5289
{"type":"hello","protocol":1,"cab":{"id":"essai","name":"nc"}}
{"type":"lineRequest","id":"l1"}
{"type":"hello","protocol":1,"cab":{"id":"essai","name":"nc"},"line":{"id":"21","rev":"25030a0dde1f0c8b"}}
{"type":"join","id":"j1","track":1,"uM":279.5,"station":0,"rame":21}
```

## Line files

A `.line.json` file holds a line **package**, as the specification sets it out:
`{"format":1,"description":{ … },"source":{ … }}`. The repository's are in [`Lines/`](../Lines), beside
this package: Cabine writes them, and the app is built with them. `CabineWire.LinePackage.decode(file:)`
reads a package, and also a bare description (what these files held before there were packages: it
makes a package with no source) and a whole `line` message. `encodedForFile()` writes a package on one
line, its keys in alphabetical order, ended by a line feed.

The **description** is read into `CabineWire.LineDescription`, field by field, and it is all the engine
works on. The **source** is not read: it is kept as a `CabineWire.JSONValue`, any JSON value, and handed
on. A number in it is held as the `Double` it reads as and written in the shortest form that reads as
that same `Double`, and an object's keys are written in alphabetical order. So a source does not leave
the PCC byte for byte as it came (`103.0` leaves as `103`, and its keys may be in another order), but it
reads to the same values, every key and every number to its last digit. The self-test holds every line
of `Lines/` to that, with a reader of its own.

## The three layers

`Sources/CabinePCCKit` keeps three things apart, because an app hosts the same code:

| Folder | What | Knows of |
|---|---|---|
| `Wire/` | A `Codable` type for every message of the specification (`CabineWire`), the line package (`CabineWire.LinePackage`: a `LineDescription`, and the source as a `JSONValue`), the newline-JSON codec (`CabineWire.Codec`) and the line framing with its 1 MiB limit (`CabineWire.Framer`) | Nothing else. The same files can serve the other end of the link |
| `Engine/` | The simulation (`CabinePCC.Engine`): the library, the line and its checks (`CabinePCC.Line`), the automatic rames and their driver, the moving block, the cabs, their authorities, the operator's orders, the snapshot and the journal | The wire's types. No sockets, no clock: it is stepped with a `dt` and handed what each connection sends |
| `Server/` | `CabinePCC.Server`: the listener, Bonjour, one connection a cab, and the timers | The engine |

The codec writes a message's `type` first and its other keys in alphabetical order. An optional field
that is absent is left out, never written as `null`. A field or a word this version does not know does
not stop a message being read, and a `type` it does not know is answered with `result` `unknownType`.

### Hosting the kit

```swift
import CabinePCCKit

var settings = CabinePCC.Settings()
settings.name = "PCC LIGNE 21"
let server = CabinePCC.Server(settings: settings, queue: .main)   // or no queue: it makes its own

let package = try CabineWire.LinePackage.decode(file: url)        // a package, or a bare description
try server.keep(package)                                          // into the library
try server.takeUp(held: package.identity)                         // the PCC is on that line
server.start()

let snapshot = server.snapshot()        // the line, the clock, every rame, every connection, the library
let journal = server.takeJournal()      // what happened since the last call
try server.hold(rame: 21, true)         // the operator's orders
try server.closeLine()                  // on no line, once no cab is in service
```

Everything the server does happens on one serial queue: the one it is given, or its own. `snapshot()`,
`takeJournal()`, the library's calls and the orders can be called from any thread, before `start()` as
well as after; each runs on that queue and waits for it, or runs at once when the caller is already on
it (a main-actor host that gives it `.main`). The server holds a `ProcessInfo` activity while it runs, so
that App Nap does not slow a PCC in the background. `stop()` has stopped, and runs its completion, once
the listener has let go of its port: another server can then be started on that port at once.

A host that wants no sockets uses `CabinePCC.Engine` itself, as the self-test does: the same calls for
the library and the orders, `open`, `receive` and `close` for each connection, `step(dt)`,
`broadcastTraffic()`, `broadcastInfo()` and `broadcastPing()` at their periods, and `takeOutbox()` for
what is to be sent. The engine is not safe to use from two threads at once.

## The library

The same calls on `CabinePCC.Server` and on `CabinePCC.Engine`. Those that can be refused throw a
`CabinePCC.OrderError`.

| Call | |
|---|---|
| `keep(_ package:)` | Keeps a line, without taking it up. Refused with `.badLine` and the reason when the package is of a format other than 1, when its description fails the checks the specification lists, or when it could not go to a cab as one line of the wire (1 MiB). A line already held under the same `id` and `rev` is replaced where it stands |
| `heldPackage(_:)` | A line of the library, as it was kept; nil if it holds none of that `id` and `rev` |
| `forget(_:)` | Takes a line out of the library: `.noSuchLine` if it is not there, and refused for the line the PCC is on |
| `takeUp(held:)` | Puts the PCC on a line of the library: `.noSuchLine` if it is not there, `.lineInUse` while a cab is in service |
| `takeUp(_ package:)` | `keep`, then `takeUp(held:)` |
| `closeLine()` | Puts the PCC on no line: `.lineInUse` while a cab is in service |
| `snapshot().library` | The lines held, in the order they were kept, each a `CabinePCC.HeldLine`: its identity, how many stations, its length, whether it has a source, its two ends |
| `keep(_ description:)`, `heldDescription(_:)`, `takeUp(_ description:)` | The same for a line of which there is only the description. Kept over a line that has a source, a bare description keeps that source |

- **What it holds.** 64 lines at most (`Settings.libraryLimit`), in memory. A full library refuses one
  more; it drops none to make room. A line is known by its `id` and its `rev` together, whatever its
  name, so two revisions of a line are two lines.
- **The line the PCC is on** is one of the library's. It cannot be forgotten, and its description cannot
  be replaced by another under the same `id` and `rev`; its source can.
- **Taking up a line.** The automatic rames are withdrawn and seeded afresh on the new line, the clock
  starts again at 08:42:00, a general emergency stop is cleared, the line is in service
  (`Settings.serviceOnAtTakeUp`), and every connection that has said `hello` is sent `event` `line`. A
  cab is then on the line or not by the line its last `hello` named: one that already held the new line
  is on it at once. Taking up the line the PCC is already on starts it afresh in the same way.
- **While a cab is in service** the line can neither be changed nor closed. A train held on the line
  for a cab that has fallen silent counts, until it is handed back to automation.
- **On no line** there are no rames, no service to give and no general emergency stop; the clock stands
  at 08:42:00; `info` says `stopped`; orders for a train are refused with `.noLine`. Every connection
  that has said `hello` is sent `event` `line` with no `line` in it when the line is closed. Closing a
  line leaves no entry in the journal: the host that ordered it knows.
- **What a cab is sent.** `lineRequest` is answered with `line` and the package as it was kept: that of
  the line the PCC is on when none is named, of any line of the library when one is named by its `id`
  and `rev`; the journal says which line went to which cab. Otherwise `result` `noLine` (on no line,
  and none named) or `noSuchLine` (not in the library; this one goes in the journal too).
- **Nothing comes from a cab.** A cab's `hello` names the line it holds, or none, and that is all the
  PCC takes from it: there is no message by which a cab gives the PCC a line.

## What the engine does, where the specification leaves it to the engine

- **The loop.** A train on track 1 at `uM` is at `uM` round the loop, and one on track 2 at
  `lengthM + uM`. Which train is ahead of which, and how far, is worked out round the loop.
- **The tail.** A rame runs beyond the last stop to `endBufferM` short of the end of the track, stops,
  and from then is `tail`: it stands there, occupying the end of that track, for `--turnback` seconds
  (60). Then it comes out on the other track, at a stand, with its rear `endBufferM` clear of the buffer
  stops, once no train on that track has its rear within `safetyMarginM + stoppingShortM` of the first
  stop; until then it waits.
- **Moving block.** An automatic rame is given leave as far as `safetyMarginM` short of the rear of the
  train ahead, round the loop, and stops `stoppingShortM` short of that. After a stop it waits for
  `departureRoomM` of leave before it moves off.
- **A cab's authority** ends at the nearest of: the train ahead on its own track (its rear, less what
  that train's position may be out by, less the margin; a rame in the tail of that track counts); the end
  of its track at `lengthM − endBufferM`; and its nose plus `horizonM`. It is sent every 0.6 s, and at
  once when it ends 5 cm or more nearer or for another reason.
- **Hold, service, emergency.** While line service is off or a general emergency stop is on, a cab's
  authority ends where its train stands. A train caught on the move is left the room to stop on the
  line's approach deceleration, and the end is pulled back to its nose once it stands. The operator's
  hold takes a train at the platform it is at or the next it reaches: its authority is cut back, with
  `hold`, from the moment it stands there. An emergency brake ordered for one cab is a `command` to it and
  leaves its authority as it was.
- **Joining.** The cab takes the place of every automatic rame whose length comes within
  `safetyMarginM + stoppingShortM` of its train, and of one coming up behind that could no longer stop
  short of it. An automatic rame that bears the number the cab asks for is renumbered; only another cab
  bearing it makes the PCC give a different one. A join where another cab's train stands is refused with
  `badValue`.
- **The fleet.** The time one rame alone takes round the loop is measured when the line is taken up, by
  running one in simulated time with average stops. The line is to carry `lap ÷ headway` trains, cabs
  included: the automatic rames make up the number, at least 2 of them, never more than 52 less the cabs,
  and no more than the loop can hold with room to move. They are seeded standing at platforms spread
  round the loop, part-way through their stops, numbered from 1. When there are too few (fewer platforms
  than rames, a join that took the place of two, a shorter headway) more come out of the tails; when
  there are too many, the next to reach a tail goes no further.
- **Silence.** A cab in service that has sent nothing for `timeoutS`, or whose connection has gone, is
  held where it was last seen, at a stand, with `phase` `emergency`. After `staleHoldS` of silence its
  train is handed back. A train handed back, then or on `leave`, keeps its number if it is one of the
  fleet's, runs on from where it is at the speed it had, and calls at the first stop it can still make.
- **Between two reports** a cab's train is carried on as it last said it was moving, for half a second at
  most, so that five reports a second do not show as jerks in the picture the other cabs are sent.
- **A `hello`** whose `line` has no `id` or no `rev`, or an empty one, is answered with `result`
  `badMessage`, and the connection stands as it did.

The automatic rames move as Cabine's own traffic does: the driver and the train's motion follow
Cabine's `AutoDriver` and `TrainBody`. Every figure the line description carries is taken from it
(`train`, `cbtc`, `dwell`, `endBufferM`). The few it does not carry are Cabine's own, in `Driver.swift`
and `Engine.swift`: the driver's gain, foresight and arrival speed, rolling and air resistance, the
speed above which the drive is limited by its power, and how often and for how long a stop is prolonged
(14 %, 15 to 32 s).

## The self-test

```bash
swift run cabine-pccd --selftest                       # on the built-in line and every line of ../Lines
swift run cabine-pccd --selftest --fixtures <dir>      # on the built-in line and every line of <dir>
```

It prints one line a check and ends with `SELFTEST PASSED` or `SELFTEST FAILED (n)`. It uses the kit
only through what the kit makes public, as a host would, and holds it to:

1. **The wire.** Each of the specification's examples, and a `line` message with a whole package, is
   read, written again and compared as JSON; unknown fields, unknown words and unknown types do no harm;
   a `hello` that names no line, and the `event` of a PCC that has closed its line; the framing.
2. **Line descriptions and packages.** Good descriptions pass; ones with stops out of order, a missing
   track, a station count that does not match, absurd lengths and so on are refused with a reason, and
   the library keeps none of them. A file is read in each of its three shapes, and one that is not a
   package says what is wrong with it. Each line that came from a file is written back and read again:
   the same package, its source the same to the last bit of every number, by a JSON reader of the test's
   own. Each is kept in a library, and a cab that asks for it is sent it as it was kept.
3. **The engine alone**, for an hour of simulated time or a lap and a quarter if that is longer: no two
   trains ever nearer than the safety margin round the loop; every automatic rame calls at every stop in
   order, nose within 1 m, doors fully open; none ever over a zone's limit or the line speed; both tails
   turned in and the loop gone round; the fleet what the headway asks for; the same seed, the same run.
4. **A cab, without sockets**: it joins where an automatic rame stands, drives down the line stopping
   at each stop inside its authority, and every authority it is sent is judged. Then the rame behind it
   stops short of it; hold, the general emergency stop and line service pull its authority back to
   where it stands; it falls silent, is held, and is handed back; it joins again and leaves.
5. **Over TCP** on 127.0.0.1, on a port the system chooses, with scripted clients that use none of the
   kit. A cab that holds no line meets a PCC on none: `hello`, `info`, `noLine`. The operator fills the
   library and takes up a line: `event` `line`, `lineRequest`, `line` with the package, `hello` again,
   then `traffic`, `info`, `ping`, `join`, reports, `authority`. A second cab that holds another line:
   `noSuchLine`, `notOnLine`. A third on the same line that sees the first as `cab`. The source of a
   real line across the socket, compared number by number with its file. The line that cannot be changed
   or closed while a cab is in service, then is: every cab told, one of them following, and the line
   closed. The three errors that close a connection, and the port let go when the server stops.
6. **The library and which line, two cabs on one track, and the fleet to order**: the rules of "Which
   line" and of the library one by one; one cab's authority behind another's train; and the fleet brought
   to another headway or size through the tails.

Everything runs on the line built in code (`CabinePCC.testLine`: six invented stations over five
kilometres) and on every `*.line.json` of the repository's `Lines/`, or of the directory `--fixtures`
names. The test passes with that directory empty or absent, and assumes nothing of the lines in it. With
the six lines of `Lines/` it takes about a minute and a half in a debug build on the Mac it was written
on, and a quarter of a minute in release (`swift run -c release cabine-pccd --selftest`); on the built-in
line alone, some ten seconds.

## What is not here

- **The app's side.** How the cabinePCC app hosts the kit, and what it shows of the line, is the app's
  own and is not in this package.
- **A library on disk.** The engine holds its library in memory. Reading packages in is its host's
  work: the daemon reads a directory at launch and a file on command, and writes nothing back.
- **The source, read.** The engine keeps a source and hands it on. It does not read it, and does not
  check that it is the source its description was worked out of: a cab finds that out by working the
  `rev` out for itself, as the specification has it.
- **Taking a train up again.** A cab that reconnects, or speaks again after its train was handed back,
  is not in service: it must `join` again. Its old train, if it is still held, is the one it then says
  where to find, and is not left behind; one that has already been handed back runs on as an automatic
  rame.
- **Regulation.** There is no timetable and no holding of trains for spacing: the automatic rames are
  kept apart by the moving block and spread by their stops, as Cabine's own traffic is.
- **The track's relief.** Gradients and the drag of curves are not modelled; a line's curves reach the
  PCC as its speed zones.
- **Anything but two tracks end to end**: crossovers, intermediate turn-backs, depots, a second line at
  the same time.
- **Passengers** aboard the automatic rames.
- **Authentication and encryption**: the specification has none.
