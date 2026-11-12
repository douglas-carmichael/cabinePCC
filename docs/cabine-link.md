# The Cabine link

How a PCC and the cabs of **Cabine** talk. Cabine is the metro driving simulator seen from the cab; a
Cabine "in PCC mode" takes its line, the other trains of that line and its own movement authority from a
PCC instead of working them out for itself. The PCC is then the simulation engine behind every Cabine
connected to it: it keeps the lines and hands each cab the one it is running, runs that line, drives the
automatic rames (even when only one cab is connected, so that the line is never empty), keeps every
train apart in moving block, and supervises the cabs.

This page is the specification of the wire, **protocol version 1**. The PCC is the server and owns it.
The engine that speaks it is the package in `Engine/` of this repository (`Engine/README.md`); the app
built on it is cabinePCC.

Its conventions are those of metroSystem's pupitre link (the `PCC_API.md` of VALPupitreSim):
newline-delimited JSON over TCP, a string `type` in every object, units in the field names, optional
fields left out rather than `null`, unknown fields and unknown event names ignored, a request's `id`
echoed in its `result`. The roles are the reverse of that link's: here the PCC listens and each cab dials
it.

## Transport

| | |
|---|---|
| Server | The PCC. TCP, all interfaces (or loopback only) |
| Port | **5289** by preference; any free port if it is taken. Bonjour says which |
| Bonjour | `_cabinepcc._tcp`, domain `local.`. TXT: `proto` = `1`, `name` = the PCC's name, `line` = the id of the line it is running, or empty |
| Client | A Cabine, given the PCC's host and port in its settings: Cabine does not browse for a PCC, and the advertisement is there for a client that does. Anything else that speaks the wire: a script, `nc` |
| TCP | No TLS. `noDelay`; keepalive on |
| Framing | One JSON object a line, UTF-8, ended by LF. A CR before the LF is ignored, and so are blank lines. A line may be up to **1 MiB** (the description of a long line is some tens of kilobytes); a longer one is an error and the connection is closed |
| Authentication | None. It is a link for a local network |
| Version | `1`, in the TXT `proto` and in both `hello`s. Changes that only add fields keep it. A `hello` that declares another version is answered with `error` `unsupportedProtocol`, and the connection is closed |

## Positions, tracks and time

- A line has two tracks. **Track 1** is the forward direction, from the line's first station to its last;
  **track 2** is the way back. Trains run on the right, and never change track except beyond a terminus.
- A position is `uM`: the metres the **nose** of a train has travelled along its track, from the buffer
  stops that track starts at. On both tracks `uM` grows in the direction of travel, from 0 to the line's
  `lengthM`. The train lies behind its nose: its tail is at `uM − lengthM` of the train.
- The two tracks are the two halves of a loop: a train that runs off the end of one, beyond the last
  platform, turns back out of sight and comes out on the other. While it does it is in the **tail**.
- Speeds are m/s along the track, never negative. Accelerations are m/s².
- `tS` is the sender's own clock in seconds, counted from when it pleases: it only puts the messages of
  one sender in order and lets the other end extrapolate between two of them. `clockS` is the line's
  time of day in seconds since midnight, the PCC's.
- A rame is known by its number, `rame`, an integer from 1 to 99 (Cabine's fleet is 01 to 52).

## Lines: the PCC's library

The lines are the PCC's. It keeps a **library** of them, runs one at a time, and hands that one to every
cab that does not hold it already. Its operator chooses which; the cabs follow.

A line of the library is a **package** of two things:

```json
{"format":1,
 "description":{"id":"4","name":"Ligne 4","rev":"c4f41e9d8fbc77b4","lengthM":13710.0, … },
 "source":{"format":1,"id":"4","name":"Ligne 4","length":13224.5,"stations":[ … ],"heading":[ … ], … }}
```

- **`description`** is the line as the PCC runs it: its two tracks, where trains stop on each, the speed
  limits, the beacons, and the figures of its stock and its moving block. The PCC's engine works on
  nothing else.
- **`source`** is the line as a Cabine builds it: the geometry and the station data of Cabine's own line
  files (`ligne-<id>.json`, format 1, set out in Cabine's `docs/lines.md`): the stations and where each
  is, the heading of the track every few metres, the ground and rail levels, the stretches in the open
  air, the recorded speed limits, and where the data came from. The PCC does not read it: it keeps it and
  hands it on, as the same JSON value: every key, and every number to the last digit it was written with,
  though not byte for byte (`103.0` leaves as `103`, and an object's keys in alphabetical order). A package
  with no `source` is a line that every Cabine has built in under that `id` (Cabine's invented Ligne 21).

The two go together: the description is what Cabine itself works out of the source (`Cabine --lines
--export` writes the package), and `description.rev` is the revision of that working out. A cab that has
built a line from a source holds the PCC's line only if the description it works out has the same `rev`:
two ends with the same `id` and `rev` mean the same line to the metre.

`format` is 1, and counts as 1 when it is left out. The description is read field by field, so a field of
it that the PCC does not know is not handed on; only the source goes through untouched. A package must fit
one line of the wire, 1 MiB, to be kept.

In the library a line is known by its `id` and `rev` together: two revisions of one `id` are two lines,
and a package kept under an `id` and `rev` already there takes that line's place. The line the PCC is on
cannot be dropped from the library, nor given another description.

The description (here Cabine's Ligne 21, cut down to its first two stations):

```json
{"id":"21","name":"Ligne 21","rev":"9f3c2a7d5e1b0c44","lengthM":7617.5,
 "colour":"E4572E","textColour":"FFFFFF","lineSpeedMS":19.444,
 "train":{"lengthM":75,"maxSpeedMS":19.444,"accelerationMS2":1.25,"serviceBrakeMS2":1.25,
          "emergencyBrakeMS2":1.78,"approachDecelMS2":0.6,"marginMS":1.3,"capacity":560},
 "cbtc":{"safetyMarginM":25,"stoppingShortM":6,"horizonM":1500,"departureRoomM":40,
         "uncertaintyBaseM":1.5,"uncertaintyPerM":0.02,"uncertaintyMaxM":8},
 "dwell":{"minS":17,"maxS":27,"terminusS":30,"doorsOpenS":2.2,"doorsCloseS":2.4,"departS":4.2},
 "endBufferM":28,
 "stations":[{"name":"Porte du Levant"},{"name":"Rue des Tanneurs"}],
 "tracks":[
   {"track":1,"stopsM":[279.5,877.9],
    "zones":[{"fromM":355.0,"toM":521.0,"limitMS":15.28}],
    "beaconsM":[186.0,326.0,471.0]},
   {"track":2,"stopsM":[6816.6,7415.0],
    "zones":[{"fromM":7096.5,"toM":7262.5,"limitMS":15.28}],
    "beaconsM":[6648.0,6865.0]}]}
```

| Field | Meaning | Required |
|---|---|---|
| `id`, `name`, `rev` | Which line, and which revision of its geometry | Yes |
| `lengthM` | Length of each track, tail tracks included: 100 to 100 000 | Yes |
| `stations[]` | The stations, in the order track 1 meets them: `name` | Yes, 2 to 128 |
| `tracks[]` | Exactly two, `track` 1 and `track` 2 | Yes |
| `tracks[].stopsM[]` | Where the nose of a train comes to rest at each station, as `uM` on that track, **in the order of travel**: on track 1 the stop of `stations[i]` is `stopsM[i]`; on track 2 the stop of `stations[i]` is `stopsM[n − 1 − i]`. Strictly rising | Yes, one for each station |
| `tracks[].zones[]` | Speed limits lower than the line's: from `fromM` to `toM` on that track the limit is `limitMS`. A limit holds while any part of a train is inside the zone | No: none |
| `tracks[].beaconsM[]` | Where a train sets its position right (Cabine has one at each lineside signal). Rising | No: none |
| `lineSpeedMS` | The limit outside every zone | No: `train.maxSpeedMS` |
| `train` | The stock of the line, which the automatic rames are made of: its length, its top speed, what it accelerates and brakes at, the deceleration its automatic driver comes down to a limit or a stop with, how far under a limit it settles, and its places | No: the values shown |
| `cbtc` | The figures of the moving block, as Cabine applies them: the margin kept behind the train ahead, how far short of the end of its authority an automatic driver stops, how far an authority reaches at most, the room a train needs ahead of it to leave a platform, and what a train's report of its position may be out by (a base, more for every metre run since its last beacon, and a ceiling) | No: the values shown |
| `dwell` | A station stop of an automatic rame: the range its doors stay open, the stop at a terminus, how long the doors take to open and to close, and the pause before it moves off | No: the values shown |
| `endBufferM` | How far short of the end of a track a train stops before it turns back | No: 28 |
| `colour`, `textColour` | The line's roundel, RRGGBB | No |

The PCC checks a description before it keeps it, and refuses a package whose description fails: the
counts and the order above; the first stop of a track at least a train's length and `endBufferM` from
its start, and the last at least `endBufferM` from its end; a `lengthM` long enough to turn a train in;
`train.approachDecelMS2` no more than either brake; limits between 1 and 100 m/s; colours of six
hexadecimal digits. A zone that reaches beyond its track is cut to it.

## The life of a connection

```
Cabine                                                        PCC
  │── connect ────────────────────────────────────────────────▶│
  │── hello {protocol, app, cab{id,name}, line?{id,rev,name}} ▶│
  │◀── hello {protocol, app, name, line?, onLine, link{…}} ─────│
  │── lineRequest {id} ───────────────────────────────────────▶│   only if the cab does not hold the line
  │◀── line {id, package{description, source?}} ────────────────│
  │── hello {…, line{id,rev,name}} ───────────────────────────▶│   once it has built the line
  │◀── hello {…, onLine: true} ─────────────────────────────────│
  │◀── traffic · info · ping ──────────────────────────────────│   from here on, to every cab on the line
  │── pong ───────────────────────────────────────────────────▶│
  │── join {id, track, uM, station, rame} ────────────────────▶│   when a service starts
  │◀── result {id, ok, rame} ──────────────────────────────────│
  │── position · status · event ──────────────────────────────▶│
  │◀── authority · command ────────────────────────────────────│
  │── leave {id, reason} ─────────────────────────────────────▶│   when the service ends
  │◀── result {id, ok} ────────────────────────────────────────│
```

A cab is in one of three states to the PCC:

- **Connected**, but not on the PCC's line: it gets `hello`, `info`, `event` and, when it asks, `line`.
  This is a cab that has yet to build the PCC's line, or a PCC that is on no line.
- **On the line**: it also gets `traffic`, five times a second: every rame of the line but its own.
- **In service** (after `join`): it reports `position` and `status`, and gets its `authority`.

### Which line

The PCC runs one line at a time, out of its library, and it is its operator who puts it on one.

- The PCC's `hello` names the line it is on: `id`, `rev` and `name`. It names none while it is on none,
  and a cab then waits: `info` goes on telling it so, and an `event` `line` tells it when that changes.
- A cab's `hello` names the line it holds, if it holds one. It is **on the line** when that is the PCC's
  line, `id` and `rev` both: `onLine: true`.
- A cab that does not hold the PCC's line gets it: one it has built in, or has kept from another time,
  it takes from where it has it; otherwise it asks for it with `lineRequest` and the PCC sends the
  package in a `line` message. It builds the line, and says `hello` again, naming it.
- A cab may say `hello` again on the same connection at any time, and the PCC answers as it did the
  first. A cab that names another line, or another cab, in a later `hello` has left the service it was
  in.
- The PCC changes line only while no cab is in service on the one it is on; a train still held for a cab
  that has fallen silent counts as in service until it is handed back. When it has changed, it withdraws
  its automatic rames and seeds them afresh on the new line, starts the line's clock again, clears a
  general emergency stop, puts the line in service, and says so with an `event` `line` to every cab that
  has said `hello`. A cab whose last `hello` named that line is on it at once; each of the others gets the
  line as above. Put again on the line it is already on, the PCC starts that line afresh and says so in
  the same way.
- The PCC can be put on no line: its rames are withdrawn, and it says so with an `event` `line` that names
  none.
- A cab whose own working out of a line does not give the package's `rev` is not on the line: it is
  another version of Cabine than the one the package was made with. It tells its driver so, and to the
  PCC it is a cab that stays connected, holding the line it held before.

## Messages from the cab

### `hello`

```json
{"type":"hello","protocol":1,"app":"Cabine","appVersion":"1.0",
 "cab":{"id":"5F0C4F0E-2B1A-4E57-9C55-0D6A3E1B7C21","name":"Mac mini"},
 "line":{"id":"21","rev":"9f3c2a7d5e1b0c44","name":"Ligne 21"}}
```

`cab.id` is a UUID that stays the same from one launch of that Cabine to the next. `cab.name` is for the
PCC's displays. `line` is the line the cab holds at that moment, and is left out by a cab that holds none;
in it `id` and `rev` are required and may not be empty, and `name` is the id when it is left out. A
`protocol` left out counts as 1, and a `cab` left out is named after its connection. Anything but `hello`,
`ping` or `pong` before `hello` is answered with `result` `badMessage`.

### `lineRequest`

```json
{"type":"lineRequest","id":"l1"}
{"type":"lineRequest","id":"l2","line":{"id":"4","rev":"c4f41e9d8fbc77b4"}}
```

Asks the PCC for a line of its library: the one it is on, or the one named. Answered by `line` with the
package and the same `id`, or by `result` refusing it: `noLine` when the PCC is on no line and none was
named, `noSuchLine` when it holds no line of that `id` and `rev`.

### `join`

```json
{"type":"join","id":"j1","track":1,"uM":279.5,"station":0,"rame":21}
```

The cab's train enters service where it stands: `track`, `uM` (its nose), and `station`, the index in
that track's order of travel of the station it stands at or runs to next. `rame` is the number it would
like; `station` and `rame` may be left out. Answered by `result` with the `rame` it has: the one asked
for, unless another cab holds it. An automatic rame that holds the number is given another; an automatic
rame that stands where the cab's train is, or within the moving-block margin of it, is withdrawn: the cab
has taken its place. So is one coming up behind that could no longer stop short of it. The cab's first
`authority` comes with the answer.

A cab is in service with one train. If it still had one, held on the line since its connection dropped,
that is the very train it now says where to find: it is taken off the line as the cab joins, and not
left behind as a rame of its own.

Refused with `notOnLine` or `badValue`: a track that is not 1 or 2, a place off the track, a station or a
number that does not exist, or a place where another cab's train stands.

### `position`, five times a second

```json
{"type":"position","seq":812,"tS":162.417,"track":1,"uM":1834.52,"speedMS":13.61,"accelerationMS2":-0.42}
```

The PCC takes the cab's word for where its train is, track included. Between two reports it carries the
train on as it last said it moved, for half a second at most, so that five reports a second do not show
as jerks in what the other cabs are sent. A `position` or a `status` from a cab that is not in service,
or with a value out of range, is answered by a `result` with no `id` (`notInService`, `badValue`), once a
second at most.

### `status`, about three times a second

```json
{"type":"status","seq":271,"tS":162.4,"mode":"PA","automatic":true,
 "doors":{"phase":"closed","side":"right","open":0},
 "emergencyBrake":{"applied":false},
 "passengers":212,"station":{"index":4,"atPlatform":false},
 "deviationS":-4,"held":false,"paused":false,"underControl":true}
```

| Field | Meaning |
|---|---|
| `mode` | The cab's CONDUITE selector: `CM` (by hand), `PA`, `CA` |
| `automatic` | True while the automatic driver has the train |
| `doors` | `phase`: `closed`, `opening`, `open`, `warning`, `closing`; `side`: `right` or `left`; `open` from 0 to 1 |
| `emergencyBrake` | `applied`, and when it is a `cause` in Cabine's words |
| `passengers` | Aboard |
| `station` | `index` of the station it is at or runs to, in its track's order; `atPlatform` |
| `deviationS` | Seconds late (positive) or early on its timetable |
| `held` | The train is kept at its platform |
| `paused` | The player has paused the game: the train stands |
| `underControl` | The train holds a movement authority and runs on it |

### `event`

```json
{"type":"event","event":"report","code":"passengerIll","text":"MALAISE VOYAGEUR"}
{"type":"event","event":"call"}
{"type":"event","event":"acknowledge"}
{"type":"event","event":"emergencyBrake","applied":true,"cause":"FREINAGE D'URGENCE CONDUCTEUR"}
```

`report` is one of the driver's coded radio reports (`code`: `radioCheck`, `readyToDepart`,
`stoppedAtSignal`, `passengerIll`, `technicalFault`, `incidentOver`, `requestCall`), `call` the driver
calling the centre, `acknowledge` the driver acknowledging a message. The PCC puts them in front of its
operator.

### `leave`

```json
{"type":"leave","id":"v1","reason":"finished"}
```

The service is over (`finished`: it reached its terminus; `ended`: the player ended it; `quit`). The
PCC hands the train back to automation where it stands, and it runs on as an automatic rame.

### `pong`

Answers the PCC's `ping`, with its `id` and `tS`.

## Messages from the PCC

### `hello`

```json
{"type":"hello","protocol":1,"app":"CabinePCC","name":"PCC LIGNE 21","pcc":{"id":"…"},
 "line":{"id":"21","rev":"9f3c2a7d5e1b0c44","name":"Ligne 21"},"onLine":true,
 "link":{"positionPeriodS":0.2,"statusPeriodS":0.3,"trafficPeriodS":0.2,"authorityPeriodS":0.6,
         "infoPeriodS":0.4,"pingPeriodS":0.5,"timeoutS":3,"staleHoldS":30}}
```

`line` is the line the PCC is on (absent while it is on none), and `onLine` whether it is the line the cab
named. `link` gives the periods it sends at and would like to be sent at, and the two times that matter
when things go wrong.

### `result`

```json
{"type":"result","id":"j1","ok":true,"rame":21}
{"type":"result","id":"l1","ok":false,"error":"noSuchLine","message":"no line 9 in the library"}
```

Answers `join`, `leave`, a `lineRequest` it cannot meet, and any message it could not act on. Error
codes: `badMessage`, `unknownType`, `unsupportedProtocol`, `noLine`, `noSuchLine`, `notOnLine`,
`notInService`, `badValue`, `tooManySessions`. A message of a known type with a field missing or of the
wrong kind is answered with `result` `badMessage`, with its `id` when that could be read, and the
connection is kept.

### `line`

```json
{"type":"line","id":"l1","package":{"format":1,"description":{ … },"source":{ … }}}
```

A line of the library, in answer to `lineRequest`: the package set out under
[Lines](#lines-the-pccs-library). A package is some tens of kilobytes.

### `traffic`, five times a second

```json
{"type":"traffic","tS":8123.4,"trains":[
  {"rame":12,"kind":"auto","track":1,"uM":2390.4,"speedMS":0,"accelerationMS2":0,"doors":1,
   "phase":"dwelling","station":4,"lengthM":75},
  {"rame":31,"kind":"cab","name":"Mac mini","track":2,"uM":5120.0,"speedMS":14.2,"accelerationMS2":0.3,
   "doors":0,"phase":"running","station":7,"lengthM":75},
  {"rame":8,"kind":"auto","track":2,"uM":7589.5,"speedMS":0,"doors":0,"phase":"tail","lengthM":75}]}
```

The whole picture each time, without the recipient's own train. A cab drops a picture that has not been
renewed for `timeoutS`.

| Field | Meaning |
|---|---|
| `rame` | Its number |
| `kind` | `auto`, a rame the PCC drives; `cab`, another Cabine's |
| `name` | For a cab, its name |
| `track`, `uM`, `speedMS`, `accelerationMS2` | Where its nose is and how it moves |
| `doors` | 0 shut to 1 open |
| `phase` | `running`, under way, or at a stand with its doors shut and nothing keeping it there (a cab's train stopped short of the end of its authority is `running` at 0 m/s); `dwelling`, at a platform with its doors open or opening; `departing`, doors closing or just closed; `held`, kept at a platform (a cab's train is `held` when its cab reports it so, or once it stands at a platform under a hold order); `emergency`, braked, or a cab's train whose cab has fallen silent; `tail`, turning back beyond a terminus: it stands `endBufferM` short of the end of the track it has left, which is still its `track`, until it comes out on the other; it occupies the tail and is not to be drawn |
| `station` | Index, in its track's order of travel, of the station it stands at or runs to next; absent in the tail, and on the way to it from the last stop |
| `lengthM` | Its length |

### `authority`, to a cab in service: every 0.6 s, and at once when it changes for the worse or for another reason

```json
{"type":"authority","seq":93,"tS":8123.6,"track":1,"endM":2284.0,"reason":"train","rame":12,"gapM":31.4,"validS":3}
```

Leave to run as far as `endM` on the cab's track, and no further. `reason` says what ends it:

| `reason` | |
|---|---|
| `train` | The train ahead: `endM` is its rear, less what its report of its position may be out by, less the safety margin. `rame` is its number and `gapM` the metres from the cab's nose to its rear |
| `horizon` | Nothing within reach: `endM` is the cab's nose plus `cbtc.horizonM` |
| `end` | The end of the track |
| `hold` | The operator is holding the train at the platform it stands at: `endM` is its nose |
| `service` | The line is not in service |
| `emergency` | A general emergency stop |

"For the worse" is an `endM` 5 cm or more nearer than the last; a change of `reason` or of `track` is sent
at once too. `endM` is rounded down to the millimetre.

When the line goes out of service or a general emergency stop is given, a train at a stand has its
authority end at its nose. One caught on the move is left the room to come to a stand without tripping
its own protection: its speed squared over twice `train.approachDecelMS2`, two seconds of travel,
`cbtc.stoppingShortM` and 5 m more; and once it stands, its authority ends at its nose.

An authority stands for `validS` seconds. One that is not renewed in that time is no authority at all:
what the cab does then is its own rule (Cabine brakes the train to a stand and has its driver carry on
by hand on the lineside signals).

### `info`, every 0.4 s

```json
{"type":"info","tS":8123.6,"clockS":31337.2,"mode":"normal","rames":17,"cabs":2,"numbers":[3,8,12,31]}
```

`mode`: `normal`, `stopped` (the line is not in service) or `emergency`. `rames` and `cabs` count the
trains of the line and those of them that are cabs; `numbers` lists the numbers in use, so that a cab can
ask for a free one. It goes to every cab that has said hello, on the line or not; a PCC on no line says
08:42:00, `stopped` and no rames.

### `ping`, every 0.5 s

```json
{"type":"ping","id":41,"tS":8123.5}
```

The cab answers `{"type":"pong","id":41,"tS":8123.5}`, which gives the PCC the round trip. Any line at
all from the other end counts as a sign of life. `ping` goes to the cabs on the line; a cab that is not on
it has `info` for its sign of life. A cab may send a `ping` of its own, which is answered with `pong`.

### `command`

```json
{"type":"command","id":"c7","command":"message","value":"REPRENEZ LA MARCHE NORMALE"}
```

| `command` | `value` | |
|---|---|---|
| `emergencyBrake` | bool | Brake the train to a stand, and release it. It is the order alone: the train's authority is unchanged |
| `hold` | bool | Keep the train at the platform it is at, or the next it reaches, until released. Once it stands at a platform its authority ends at its nose, with the reason `hold`; until then it keeps the authority it has |
| `message` | string, up to 120 characters | Words from the PCC's operator for the driver's display. Longer ones are refused to the operator, not cut |
| `call` | none | The PCC's operator rings the driver |

The cab answers with `result`.

### `event`

```json
{"type":"event","event":"line","line":{"id":"21","rev":"9f3c2a7d5e1b0c44","name":"Ligne 21"}}
{"type":"event","event":"peer","rame":31,"name":"Mac mini","state":"joined"}
{"type":"event","event":"closing","inS":5}
```

`line`: the PCC is now on this line, or on none when `line` is left out; it goes to every cab that has
said `hello`, on the line or not. `peer`: another cab has entered service (`joined`), or its train
has been handed back to automation (`left`): on its `leave`, when its silence has lasted too long, or when
it says hello for another line. `closing`: the PCC is about to quit, in `inS` seconds; a PCC that only
closes its line says so with `line`.

### `error`

```json
{"type":"error","error":"lineTooLong","message":"a line may be 1 MiB at most"}
```

Something wrong with the stream itself: `badMessage` (a line that is not a JSON object with a string
`type`), `lineTooLong`, `unsupportedProtocol`, `tooManySessions`. After the last three the connection is
closed.

## What the PCC does

This is what a cab can count on, whatever engine is behind the wire.

- **The library.** The PCC holds the lines it can run, each as a package, and is on one of them or on
  none. Its operator chooses; it changes line only while no cab is in service. It hands the package of a
  line to any cab that asks for it.
- **The line as a loop.** The PCC lays the two tracks end to end: track 1 from 0 to `lengthM`, then track
  2. An automatic rame runs round it for ever. It calls at every stop of a track in order; beyond the
  last it runs on to `endBufferM` short of the end of the track and goes into the tail, where it turns
  back out of sight; then it comes out on the other track, its tail `endBufferM` clear of the buffers,
  and runs to that track's first stop.
- **Moving block.** No train is given leave to run nearer the rear of the train ahead than
  `cbtc.safetyMarginM`. An automatic rame stops `cbtc.stoppingShortM` short of the end of its leave. A cab's
  `authority` ends at the rear of the train ahead, less what that train's position may be out by
  (`cbtc.uncertaintyBaseM`, and `cbtc.uncertaintyPerM` more for each metre run since its last beacon, or
  since the buffers where it has passed none, up to `cbtc.uncertaintyMaxM`), less the margin. A cab in
  service occupies the track like any other train: the automatic rames stop behind it.
- **A station stop.** An automatic rame stops with its nose at the stop, opens its doors, keeps them open
  between `dwell.minS` and `dwell.maxS` (`dwell.terminusS` at the last stop of a track), closes them, and
  leaves once it has `cbtc.departureRoomM` of clear way.
- **Speed.** It keeps under `lineSpeedMS` and every zone, by `train.marginMS`, and comes down to a lower
  limit or to a stop at `train.approachDecelMS2`.
- **The fleet.** As many trains as give about a train every 150 s each way: the time of a lap divided by
  the headway, cabs included, so that a cab takes the place of an automatic rame; and never fewer than two
  automatic rames, with one cab or with ten. They are numbered from the fleet, never with a number a cab
  holds. The fleet grows and shrinks at the tails: a rame the line has no more use for goes no further
  than the next tail it reaches, and one that is wanted comes out of one.
- **A cab that falls silent.** A cab in service that has sent nothing for `timeoutS` is held where it was
  last seen, at a stand, as an obstacle. If it is still silent after `staleHoldS` its train is handed back
  to automation. A connection that closes without a `leave` counts as silence at once, and the
  `staleHoldS` run from the last line heard. A cab that speaks again on the same connection within that
  time is a cab again, without a `join`. One that has had to dial again is not in service: it must `join`
  again, and the train it left, while it is still held, is taken up again by that `join`. After
  `staleHoldS` that train is an automatic rame like any other, and the cab's `position` and `status` are
  answered `notInService` until it joins.
- **The clock.** `clockS` starts at 08:42:00 when the PCC takes up a line, and runs in real time.
