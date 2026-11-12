# The DCL

cabinePCC's terminal is an OpenVMS DCL shell: the emulation metroSystem has, carried over whole, with a
layered product of its own where metroSystem's railway was. The product is **LPD PCC-CABINE**, and its
commands are the PCC's. Each of them reads the engine or gives it an order through the same link the PCC
Dispatcher window uses, so what a command prints is what the engine holds at that moment, and what it
orders is done or refused with the reason.

There are three ways in:

- a **DCL Terminal** window of the app, as many as are wanted;
- `telnet localhost 2324`, into the app or into `cabinepcc-headless --serve`;
- `cabinepcc-headless --dcl "command"`, which carries out commands against a fresh node and prints what a
  terminal would show ([architecture.md](architecture.md#the-headless-tool)).

Every sample on this page was made the third way and is what the program printed. The node is named
PCCVL1 and its operator OPERATOR; the PCC is on Cabine's Ligne 21, with a cab in service as train 21 (two
cabs for the screens). The cabs are scripts that speak the wire, not Cabines: what they say of themselves
(the name Alma, PA, 212 passengers) is what the script says.

- [Conventions](#conventions)
- [The PCC](#the-pcc): `SHOW PCC`, `SET PCC`
- [The library and the line](#the-library-and-the-line): `SHOW LINES`, `SHOW LINE`, `SET LINE`
- [The line's orders](#the-lines-orders): `SET LINE`, `START LINE`, `STOP LINE`, `EMERGENCY`, `RESUME`
- [The trains](#the-trains): `SHOW RAMES`, `SHOW RAME`, `SET RAME`, `START RAME`, `STOP RAME`
- [The cabs and the connections](#the-cabs-and-the-connections): `SHOW CABS`, `SHOW CONNECTIONS`
- [The journal](#the-journal): `SHOW JOURNAL`
- [The alarms](#the-alarms): `SHOW ALARMS`, `ACKNOWLEDGE`, `SHELVE`, `UNSHELVE`
- [Short forms](#short-forms)
- [The monitors](#the-monitors): `MONITOR LINE`, `CABS`, `RAMES`, `CONNECTIONS`
- [The forms](#the-forms): `RUN RAME_DIR`, `RUN LIGNE_DIR`
- [Command procedures](#command-procedures): `F$PCC`, `F$RAME`, the built-in symbols, `$STATUS`
- [In French](#in-french)
- [The rest of the shell](#the-rest-of-the-shell)
- [HELP and SELFTEST](#help-and-selftest)

## Conventions

**Abbreviation.** Verbs, keywords and qualifiers may be cut short as DCL allows: `SH PCC`, `SHO RAM 21`,
`SET RAM 21 /HOL`, `MON CAB`. Two words are told apart by being whole: `SHOW LINES` and `SHOW RAMES` are
the lists, and anything shorter is `SHOW LINE` and `SHOW RAME`.

**Qualifiers compose.** `SET RAME 21 /HOLD /MESSAGE="…"` holds a train and tells its driver why. A verb
carries its qualifiers out in an order of its own, given with each verb below, whatever the order they
were typed in.

**What a command answers.** An order that is carried out answers `%PCC-S-` and a word for what was done.
One that cannot be answers `%PCC-W-REFUSED,` and the reason, in the language of the session:

| | |
|---|---|
| `The PCC is not running: SET PCC /ENABLE starts it.` | The PCC is disabled, or its listener has yet to start |
| `The PCC is on no line: put it on one of its library first.` | An order for a line or a train, with no line |
| `No train 77 on the line: SHOW RAMES lists them.` | |
| `Train 03 is not a cab: only a cab takes a message or a call.` | `/MESSAGE` or `/CALL` for an automatic train |
| `The cab of train 21 is not connected.` | Its train is held on the line, but its connection has gone |
| `A headway lies between 30 and 3600 seconds.` | |
| `A fleet is 2 to 52 trains, cabs included, or AUTO.` | |
| `A message needs words.` | |
| `A message is 120 characters at most: this one is 131.` | A long message is refused, not cut |
| `A PCC needs a name.` | |
| `A cab is in service on the present line: the PCC changes line only when none is.` | `/LOAD` or `/CLOSE` |
| `The library holds no line 99.` | |
| `Refused: …` | Anything else, in the engine's words |

A command that is not well formed answers with what it expected: `%PCC-W-MISSQUAL` (no qualifier),
`%PCC-W-IVVALUE` (a value that is not one), `%PCC-W-NORAME` (no train number), `%PCC-W-NOSUCHRAME`,
`%PCC-W-MISSPARM`.

**`$STATUS`.** A refusal leaves a warning in `$STATUS` (`%X000080D0`), a success `%X00000001`, so that a
command procedure can tell what became of its order ([below](#command-procedures)):

```
{{en-cab|SET RAME 77 /HOLD|2}}
{{en-cab|SHOW SYMBOL $STATUS|1}}
```

**Two languages.** The session speaks the language of the app, English or French, and can be switched
while it runs. OpenVMS's own verbs and output are the same in both, as on a real system. The railway's
words follow the language, and only that language's spelling is accepted:

| English | French |
|---|---|
| `LINE`, `LINES` | `LIGNE`, `LIGNES` |
| `CABS` | `CABINES` |
| `/LOAD`, `/CLOSE`, `/REREAD` | `/CHARGER`, `/FERMER`, `/RELIRE` |
| `/EMERGENCY`, `/HEADWAY` | `/URGENCE`, `/INTERVALLE` |
| `/HOLD`, `/RELEASE` | `/RETENIR`, `/LIBERER` |
| `/BRAKE`, `/UNBRAKE` | `/FREINER`, `/DEFREINER` |
| `/CALL` | `/APPELER` |
| `EMERGENCY`, `RESUME` | `URGENCE`, `REPRISE` |

`PCC`, `RAME`, `RAMES`, `CONNECTIONS`, `JOURNAL`, `ALARMS`, `/SERVICE`, `/RAMES`, `/MESSAGE`, `/STATIONS`,
`/SOURCE`, `/LAST`, `/ENABLE`, `/DISABLE`, `/LAN` and `/NAME` read the same in both and are fixed. What
the product prints is in the session's language; the `%PCC-S-HOLD` in front of a message is an
identifier, and is not translated. [In French](#in-french) has the same desk in French.

**Under `SELFTEST`** a command that would change the PCC, its line, a train or the alarm log says what it
would do and does not do it.

## The PCC

### SHOW PCC

```
SHOW PCC
```

The listener and its port, the network it listens on, the PCC's name, the address to give a Cabine, how
long it has listened, the line it is on, its connections by standing, and how many lines its library
holds.

```
{{en-cab|SHOW PCC}}
```

The listener is `STARTING`, `LISTENING ON PORT n`, `DISABLED` or `FAILED` with the system's reason. A
PCC listens on port 5289 by preference and on any free port when that one is taken, which is why the
port is shown: the samples run on a port the system chose. A PCC that has yet to listen after five
seconds says what that may mean on every interface: that macOS has not given the program the local
network, which System Settings grants under Privacy & Security, Local Network. (Listening on every
interface has not been tried on a real network yet, so that hint is a guess at the cause.)

### SET PCC

```
SET PCC /ENABLE
        /DISABLE
        /LAN={ON|OFF}
        /NAME="name"
```

| | |
|---|---|
| `/ENABLE` | Starts the PCC: it listens, reads its library and takes up the line it was last on |
| `/DISABLE` | Tells the cabs the PCC is closing and closes their connections. The line goes with it |
| `/LAN=ON` | Every interface, and advertised by Bonjour as `_cabinepcc._tcp` |
| `/LAN=OFF` | This Mac only (loopback), and not advertised |
| `/NAME="name"` | The name the cabs and Bonjour show, 64 characters at most |

They are carried out in that order but for `/DISABLE`, which comes last. `/LAN` and `/NAME` take effect
on a PCC that is running by closing it and starting it again on the line it was on: the cabs' connections
are closed, the line's trains are seeded afresh and its clock starts again. All three are settings, kept
for the next launch.

```
{{en-library|SET PCC /NAME="PCC NORD"}}
{{en-library|SET PCC /DISABLE}}
{{en-library|SHOW PCC|2}}
{{en-library|SET PCC /ENABLE}}
{{en-library|WAIT 00:00:02}}
{{en-library|SHOW PCC|3}}
{{en-library|SET PCC /LAN=OFF}}
{{en-library|SET PCC}}
```

The mail is OPCOM's, to the operator's mailbox: the line has been taken up again.

## The library and the line

The lines are the PCC's ([lines.md](lines.md)). It keeps a library of them, is on one of them or on none,
and hands the one it is on to every cab that does not hold it.

### SHOW LINES

```
SHOW LINES
```

Every line of the library: its id, name and revision, how many stations it has, the length of a track,
whether its package carries the line's source, and its two ends. A star marks the line the PCC is on.

```
{{en-cab|SHOW LINES|1}}
```

### SHOW LINE

```
SHOW LINE [/STATIONS] [/SOURCE]
```

The line the PCC is on: its name, id and revision; the length of each track and the stations; service,
mode and the line's clock; the headway, how the fleet is sized and the time of a lap; the trains; and the
stock they are made of.

```
{{en-cab|SHOW LINE|1}}
```

The mode is `NORMAL`, `SERVICE STOPPED` or `EMERGENCY STOP`. The line's clock starts at 08:42:00 when
the PCC takes the line up, and runs in real time. "15 automatic (15 wanted)" is the fleet coming to its
size: trains join and leave at the tails, so the two differ for a while after a headway is changed.

`/STATIONS` lists every station with the stop of each track, in metres from the start of that track:

```
{{en-cab|SHOW LINE /STATIONS}}
```

`/SOURCE` says where the line's data came from, with the credits its licences ask for, and whether the
package carries the source a Cabine builds the line from. Ligne 4:

```
{{en-library|SHOW LINE /SOURCE|1}}
```

and Ligne 21, which is invented:

```
{{en-library|SHOW LINE /SOURCE|2}}
```

### SET LINE: which line

```
SET LINE /LOAD=id
         /CLOSE
         /REREAD
```

| | |
|---|---|
| `/LOAD=id` | Puts the PCC on the line of its library that has that id. Where the library holds two revisions of one id, it is the one kept last, the operator's own |
| `/CLOSE` | Puts the PCC on no line. Its trains are withdrawn, and its cabs wait for a line |
| `/REREAD` | Reads the library again: what is new or changed in the Lines folder is kept, without closing the PCC |

`/REREAD` is carried out first, then `/CLOSE`, then `/LOAD`, then [the line's orders](#the-lines-orders)
if the same command gives any.

The PCC changes line only while no cab is in service on the one it is on. When it does, it withdraws its
automatic trains and seeds them afresh on the new line, starts the line's clock again, clears a general
emergency stop and puts the line in service; every cab is told, and follows. The line is remembered: the
next launch takes it up again.

```
{{en-library|SET LINE /LOAD=4}}
{{en-library|SHOW LINE|1}}
{{en-library|SET LINE /LOAD=99}}
{{en-library|SET LINE /CLOSE}}
{{en-library|SHOW LINE|2}}
{{en-library|SET LINE /REREAD}}
{{en-library|SET LINE /LOAD=21}}
{{en-library|SET LINE}}
```

With a cab in service:

```
{{en-cab|SET LINE /LOAD=4}}
```

## The line's orders

### SET LINE

```
SET LINE /SERVICE={ON|OFF}
         /EMERGENCY={ON|OFF}
         /HEADWAY=seconds
         /RAMES={n|AUTO}
```

| | |
|---|---|
| `/SERVICE=OFF` | Line service off: the trains come to a stand where they can, and a cab's authority ends for the reason `service`. `ON` starts it again |
| `/EMERGENCY=ON` | The general emergency stop: every train is braked. `OFF` releases it; the trains the operator has braked one by one stay braked |
| `/HEADWAY=seconds` | Sizes the fleet for a train every so many seconds each way, 30 to 3600. The fleet comes to it as trains reach the tails |
| `/RAMES=n` | Fixes the number of trains on the line, cabs included, 2 to 52 |
| `/RAMES=AUTO` | Sizes the fleet from the headway again |

They are carried out in that order.

```
{{en-cab|SET LINE /HEADWAY=120}}
{{en-cab|SET LINE /HEADWAY=5}}
{{en-cab|SET LINE /RAMES=12}}
{{en-cab|SET LINE /RAMES=AUTO}}
{{en-cab|SET LINE /SERVICE=MAYBE}}
```

### START LINE, STOP LINE

```
START LINE
STOP LINE
```

Line service on and off: `SET LINE /SERVICE=ON` and `=OFF`.

```
{{en-cab|STOP LINE}}
{{en-cab|SHOW LINE|2}}
{{en-cab|START LINE}}
```

### EMERGENCY, RESUME

```
EMERGENCY
RESUME
```

The general emergency stop and its release: `SET LINE /EMERGENCY=ON` and `=OFF`. The stop raises the
critical alarm `LIGNE AU`, which returns to normal when it is released.

```
{{en-cab|EMERGENCY}}
{{en-cab|SHOW STATUS}}
{{en-cab|SHOW ALARMS|2}}
{{en-cab|RESUME}}
```

`SHOW STATUS` is OpenVMS's, with a line of the product's at its foot.

## The trains

A train is a **rame**, known by its number, 01 to 99. The automatic ones are the PCC's own; a cab's is
the train of a Cabine in service.

### SHOW RAMES

```
SHOW RAMES
```

Every train of the line by number: its kind, its track, where its nose is along that track, its speed,
its state, its doors, and the station it stands at or runs to. A train the operator holds or has braked
says so at the end of its row.

```
{{en-cab|SHOW RAMES}}
```

| State | |
|---|---|
| `RUNNING` | |
| `AT PLATFORM` | Standing at a platform with its doors open or opening |
| `DEPARTING` | Its doors closing, or just closed |
| `HELD` | Kept at a platform by the operator, or on its way to the one it will be kept at |
| `EB` | Braked: by the operator, by its own cab, or because its cab has fallen silent |
| `TURNING BACK` | Out of sight beyond a terminus, between one track and the other |

The doors are `OPEN`, `CLOSED` or, on the way, a percentage.

### SHOW RAME

```
SHOW RAME [number]
```

One train in full. For a cab's train it adds all that is known of the cab: its name and the id it keeps
from one launch to the next; its connection, where it comes from and the program it runs; its link and
the round trip of its last ping; the driving mode, CM, PA or CA, and whether the automatic driver has the
train; its passengers and its timetable; its emergency brake, with the cause in the cab's own words; its
movement authority and what ends it; and the driver's last report. With no number it lists every train,
as `SHOW RAMES` does.

```
{{en-cab|SHOW RAME 21|1}}
{{en-cab|SHOW RAME 3}}
```

A movement authority ends for one of six reasons: the train ahead (with its number and how far its rear
is), nothing within reach, the end of the track, the operator's hold, a line out of service, or the
general emergency stop.

### SET RAME

```
SET RAME number /HOLD
                /RELEASE
                /BRAKE
                /UNBRAKE
                /MESSAGE="text"
                /CALL
```

| | |
|---|---|
| `/HOLD` | Keeps the train at the platform it is at, or the next it reaches, until it is released. A cab is sent the order, and once it stands at the platform its authority ends at its nose |
| `/RELEASE` | Lets it go |
| `/BRAKE` | Orders its emergency brake: an automatic train is braked to a stand, and a cab is sent the order |
| `/UNBRAKE` | Releases it |
| `/MESSAGE="text"` | Words for the display of a cab's driver, 120 characters at most |
| `/CALL` | Rings a cab's driver |

They are carried out in that order. `/HOLD` and `/BRAKE` work on any train; `/MESSAGE` and `/CALL` need a
cab.

```
{{en-cab|SET RAME 21 /HOLD /MESSAGE="WAIT FOR THE DEPARTURE SIGNAL"}}
{{en-cab|SHOW CABS|2}}
{{en-cab|SET RAME 21 /RELEASE|1}}
{{en-cab|SET RAME 3 /MESSAGE="HELLO"}}
{{en-cab|SET RAME 77 /HOLD|1}}
{{en-cab|SET RAME 21}}
{{en-cab|SET RAME 21 /CALL}}
```

A brake the PCC has ordered is a standing alarm until it is released:

```
{{en-cab|SET RAME 21 /BRAKE}}
{{en-cab|SHOW ALARMS|1}}
{{en-cab|SET RAME 21 /UNBRAKE}}
```

### START RAME, STOP RAME

```
STOP RAME number
START RAME number
```

The emergency brake of one train, and its release: `SET RAME number /BRAKE` and `/UNBRAKE`.

```
{{en-cab|STOP RAME 5}}
{{en-cab|SHOW RAME 5}}
{{en-cab|START RAME 5}}
```

## The cabs and the connections

### SHOW CABS

```
SHOW CABS
```

The cabs in service: link and round trip, driving mode and automatic driver, track, position and speed,
and where each one's movement authority ends and why. What the operator has ordered of a cab, and an
emergency brake that is applied, follow in brackets.

```
{{en-cab|SHOW CABS|1}}
```

### SHOW CONNECTIONS

```
SHOW CONNECTIONS
```

Every connection to the PCC, whatever its standing: its number, its standing, its train if it has one,
the cab's name and its program; where it comes from, the line it holds, when it was last heard and the
round trip of its last ping.

```
{{en-cab|SHOW CONNECTIONS}}
```

| Standing | |
|---|---|
| `CONNECTED, NOT YET ANNOUNCED` | The connection is open and has not said `hello` |
| `CONNECTED, NOT ON THE PCC'S LINE` | It holds another line, or none: it is sent the PCC's when it asks |
| `ON THE LINE` | It holds the PCC's line, and is sent the traffic |
| `IN SERVICE` | Its train is on the line |

## The journal

```
SHOW JOURNAL [/LAST=n]
```

What has happened, the newest last, by the line's clock: the library read, lines taken up and closed,
cabs connecting, a line handed to a cab that asked for it, cabs coming on the line, entering service,
leaving, falling silent and being heard again, their emergency brakes, the drivers' reports, calls and
acknowledgements, orders a cab refused, and line files that were refused. `/LAST` gives how many lines to
show, 20 when it is left out; the journal keeps the last 200. The operator's own orders are not in it:
the terminal or the window they were given in has answered each.

```
{{en-cab|SHOW JOURNAL}}
{{en-cab|SHOW JOURNAL /LAST=3}}
```

"In place of 01" is the automatic train that stood where the cab's train entered service: the cab has
taken its place.

## The alarms

The PCC raises its alarms into the SCADA log, which is metroSystem's, with ISA-18.2's behaviour. The
same log feeds the annunciator of the PCC Dispatcher.

| Source | Point | Severity | |
|---|---|---|---|
| `LIGNE` | `AU` | Critical | The general emergency stop is on |
| `CABINE nn` | `LIAISON` | Major | The cab of train nn has fallen silent: its train is held where it was last seen |
| `CABINE nn` | `FU` | Major | The emergency brake of cab nn is applied, by the cab or by the PCC |
| `RAME nn` | `FU` | Major | The PCC has braked automatic train nn |
| `CABINE #n` | `REVISION` | Minor | Connection #n holds another revision of the PCC's line, and cannot come on it |
| `PCC` | `ECOUTE` | Critical | The listener failed: no cab can connect |
| `CABINE nn` | `RADIO` | By the report | A driver's coded report: passenger taken ill and technical fault are major; stopped at a signal and asking to be called, minor; radio check, ready to depart and incident over, advisory |
| `CABINE nn` | `APPEL` | Minor | A driver calls the PCC |
| `PCC` | `FICHIER` | Minor | A line file was refused when the library was read: the journal names it |
| `PCC` | `LIGNE` | Minor | The line last run is not in the library: the PCC is on no line |

The first six are **process-driven**: each stands while its cause does and returns to normal with it,
whatever the operator does. The last four are **events**: each stands until the operator has acknowledged
and cleared it. The sources and points are identifiers, the same in both languages; the messages are
translated.

```
SHOW ALARMS [/ALL]
ACKNOWLEDGE ALARM {id|ALL} [/CLEAR]
SHELVE ALARM id
UNSHELVE ALARM id
```

| | |
|---|---|
| `SHOW ALARMS` | The alarms that stand. `/ALL` adds those that have returned to normal or been cleared |
| `ACKNOWLEDGE ALARM` | Acknowledges one alarm by its id, or all. `/CLEAR` clears an event as well; a process-driven point is not cleared by hand, and says so |
| `SHELVE ALARM` | Takes a nuisance alarm off the annunciator while it stays in the log; `UNSHELVE` puts it back |

A node that found two files in its Lines folder that are not line packages, and then had a general
emergency stop: both alarms are acknowledged; the stop is not cleared by hand, the files' alarm is; and
the stop returns to normal when it is released.

```
{{en-alarms|SHOW ALARMS|1}}
{{en-alarms|EMERGENCY}}
{{en-alarms|ACKNOWLEDGE ALARM ALL}}
{{en-alarms|SHOW ALARMS|2}}
{{en-alarms|ACKNOWLEDGE ALARM 2 /CLEAR}}
{{en-alarms|ACKNOWLEDGE ALARM 1 /CLEAR}}
{{en-alarms|RESUME}}
{{en-alarms|SHOW ALARMS/ALL}}
```

The states are `UNACK`, `ACK`, `RTN` for an alarm that returned to normal before it was acknowledged,
`SHLVD` and `CLEARED`. A shelved alarm leaves the list of those that stand and stays in the log:

```
{{en-alarms|SET RAME 21 /BRAKE}}
{{en-alarms|SHELVE ALARM 3}}
{{en-alarms|SHOW ALARMS|3}}
{{en-alarms|UNSHELVE ALARM 3}}
{{en-alarms|SHOW ALARMS|4}}
{{en-alarms|SET RAME 21 /UNBRAKE}}
```

## Short forms

Seven words stand for a whole command. They follow the language too.

| English | French | Is |
|---|---|---|
| `TRAIN n` | `RAME n` | `SHOW RAME n` |
| `FLEET` | `FLOTTE` | `SHOW RAMES` |
| `LINE` | `LIGNE` | `SHOW LINE` |
| `STATIONS` | `GARES` | `SHOW LINE /STATIONS` |
| `CABS` | `CABINES` | `SHOW CABS` |
| `EMERGENCY` | `URGENCE` | `SET LINE /EMERGENCY=ON` |
| `RESUME` | `REPRISE` | `SET LINE /EMERGENCY=OFF` |

In French `AIDE` is `HELP` as well. A short form of the other language is not a command.

## The monitors

Four live displays of the product's own, drawn on its screen in the session's language. They are built on
the SMG pasteboard metroSystem's line monitor had: bordered displays, painted once and then updated row
by row, so that a slow terminal sees only what changed.

```
MONITOR LINE        [/INTERVAL=seconds]
MONITOR CABS        [/INTERVAL=seconds]
MONITOR RAMES       [/INTERVAL=seconds]
MONITOR CONNECTIONS [/INTERVAL=seconds]
```

They refresh every half second, or every `/INTERVAL` seconds down to a quarter. CTRL/Z leaves, CTRL/W
repaints, CTRL/Y interrupts, and ESC ESC does for a telnet client that keeps the control keys to itself.
A table longer than the screen turns its pages by itself, every five seconds.

### MONITOR LINE

The line as a mimic board, with the most pressing alarm and a row for each cab.

```
{{en-screens|MONITOR LINE|1}}
```

Track 1 runs from left to right on the upper rail and track 2 from right to left on the lower, so that a
station is at one place on both and the two ends are the turn-backs. The stations are ticked, and named
above and below as there is room. A train is its number and a mark at its nose. Where two trains are too
close for both numbers, one of them is its mark alone: a cab keeps its number, and so does a train that
is held or braked.

| | |
|---|---|
| `03>`, `<14` | An automatic train, running to the right on track 1 and to the left on track 2 |
| `21»`, `«21` | A cab, in reverse video |
| `21H` | A train the operator holds |
| `22!` | A train that is braked, flashing |
| `08·` | A train turning back in a tail |
| `╌` | The tail tracks, beyond the last platforms |

With a cab held and another braked:

```
{{en-screens|MONITOR LINE|2}}
```

### MONITOR CABS

Every cab in service, four rows each: its number and name, its link and the round trip of its last ping,
the driving mode and whether the automatic driver has the train; its track, position, speed, state and
station; what the PCC has ordered of it, its doors, its emergency brake, its timetable and its
passengers; and its movement authority with what ends it. A cab that has fallen silent says for how long,
flashing. A row too long for the screen loses its last items whole, and an emergency brake that is
applied comes first, with its cause in the cab's own words.

```
{{en-screens|MONITOR CABS|2}}
```

### MONITOR RAMES

Every train of the line: number, kind, track, position, speed, state, doors, the operator's hold (`H`)
and brake (`!`), and the station it stands at or runs to.

```
{{en-screens|MONITOR RAMES}}
```

### MONITOR CONNECTIONS

The listener, and every connection whatever its standing: its train, its cab's name, the line it holds
(id, and the first eight figures of the revision), when it was last heard, the round trip of its last
ping and where it comes from.

```
{{en-screens|MONITOR CONNECTIONS}}
```

### The system's classes

OpenVMS's own Monitor Utility is there beside them, in English as it always was: `MONITOR SYSTEM`,
`MODES`, `PROCESSES`, `IO`, `PAGE`, `STATES`, `DISK`, `LOCK`, `FCP` and `ALL_CLASSES`, every three seconds
or every `/INTERVAL`. Its figures are the Mac's own. The PCC shows in it as the processes an OpenVMS node
would run it in: the engine, the listener, the alarm server, and a link for each cab in service.

```
{{en-screens|MONITOR PROCESSES}}
{{en-screens|SHOW SYSTEM}}
```

metroSystem's `MONITOR CLUSTER` and `MONITOR DYNAMICS` are gone with what they showed.

## The forms

Two full-screen forms in the manner of DECforms, built on the machinery of metroSystem's board
catalogue: a list on the left with a cursor bar, the record of what the bar is on to the right, and the
orders on keys. **Every order asks before it acts**: Y carries it out, and any other key takes it back.
What the order came to is on the row above the keys until the next key is pressed.

| | |
|---|---|
| Up, Down | Move the cursor bar |
| 0 to 9 | Find by number or id: the list narrows to what matches. DEL takes a figure back, CTRL/U all of them |
| Tab, Next Screen, Prev Screen | The pages of the record |
| CTRL/W | Repaint |
| CTRL/Z | Leave; while the form is asking something, take the question back. ESC ESC over telnet |

### RUN RAME_DIR

```
RUN RAME_DIR
```

The trains and the cabs, with their orders.

| English | French | |
|---|---|---|
| H | R (retenir) | Hold the train at its next platform |
| R | L (libérer) | Release it |
| B | F (freiner) | Order its emergency brake |
| U | D (défreiner) | Release its emergency brake |
| M | M | A message for a cab: its words, RETURN, then the question |
| C | A (appeler) | Call a cab's driver |
| Y | O | Yes, to the question |

```
{{en-screens|RUN RAME_DIR|1}}
```

`21` finds train 21, and Tab turns to its cab's page:

```
{{en-screens|RUN RAME_DIR|2}}
```

`H` asks:

```
{{en-screens|RUN RAME_DIR|3}}
```

and `Y` holds the train:

```
{{en-screens|RUN RAME_DIR|4}}
```

An order that cannot be carried out is refused on the form as at the prompt. `M` on train 05:

```
{{en-screens|RUN RAME_DIR|5}}
```

### RUN LIGNE_DIR

```
RUN LIGNE_DIR
```

The line library. A dot marks the line the PCC is on, and the form opens on it. The record of a line has
its name, id, revision, length and ends; then where its data came from; then its stations, with the stop
on each track.

| English | French | |
|---|---|---|
| L | C (charger) | Put the PCC on the line under the cursor bar |
| C | F (fermer) | Put the PCC on no line |
| R | R (relire) | Read the library again |
| Y | O | Yes, to the question |

```
{{en-screens|RUN LIGNE_DIR|1}}
```

`4` finds Ligne 4 (and Ligne 14), and Tab turns to where its data came from:

```
{{en-screens|RUN LIGNE_DIR|2}}
```

Tab again turns to its stations:

```
{{en-screens|RUN LIGNE_DIR|3}}
```

`L` and `Y` would put the PCC on it. With cabs in service it is refused, and says why:

```
{{en-screens|RUN LIGNE_DIR|4}}
```

Any other image is refused to the operator's account: `RUN PROG.EXE` answers `%SYSTEM-F-NOPRIV`.

## Command procedures

The shell runs command procedures as metroSystem's does: `@NAME` runs `NAME.COM` from the command store
with up to eight parameters, P1 to P8, and inside one there are symbols, `IF`, `GOTO`, `GOSUB`, `WAIT`
and substitution with apostrophes, of a symbol (`'N'`, and `''N'` inside a string) or of a lexical
function (`''F$TIME()'`): `HELP SCRIPTING` and `HELP TUTORIAL` teach it. Two lexical functions and five
built-in symbols let a procedure read the engine, and `$STATUS` tells it what became of an order.

### F$PCC

```
F$PCC(item)
```

| Item | |
|---|---|
| `LISTENING` | `TRUE` while the PCC listens |
| `PORT` | The port it listens on, 0 when it does not |
| `NAME` | Its name |
| `LAN` | `TRUE` on every interface, `FALSE` on loopback only |
| `LINE` | The id of the line it is on, empty on none |
| `LINE_NAME` | That line's name |
| `LINES` | How many lines the library holds |
| `MODE` | `NORMAL`, `STOPPED` or `EMERGENCY`; empty on no line |
| `SERVICE` | `TRUE` while line service is on |
| `EMERGENCY` | `TRUE` while the general emergency stop is on |
| `CLOCK` | The line's time of day, hh:mm:ss |
| `HEADWAY` | Seconds between trains each way |
| `RAMES` | How many trains are on the line |
| `FIRST_RAME` | The lowest train number, 0 with none |
| `CABS` | How many cabs are in service |
| `FIRST_CAB` | The lowest number of a cab's train, 0 with none |
| `CONNECTIONS` | How many connections the PCC has |
| `ALARMS` | How many alarms stand |
| `UNACKED` | How many of them are not acknowledged |

### F$RAME

```
F$RAME(number,item)
```

| Item | |
|---|---|
| `EXISTS` | `TRUE` when the line has a train of that number |
| `KIND` | `AUTO` or `CAB` |
| `IS_CAB` | `TRUE` for a cab's train |
| `TRACK` | 1 or 2 |
| `POSITION` | Metres along its track, to the metre |
| `SPEED` | km/h, to the unit |
| `PHASE` | `RUNNING`, `DWELLING`, `DEPARTING`, `HELD`, `EMERGENCY` or `TAIL` |
| `STATION` | The station it stands at or runs to |
| `HELD` | `TRUE` while the PCC holds it |
| `BRAKED` | `TRUE` while the PCC has it braked |
| `CAB` | Its cab's name |
| `LINK` | `LIVE` or `SILENT` |
| `MODE` | `CM`, `PA` or `CA` |
| `AUTOMATIC` | `TRUE` while the automatic driver has it |
| `EB` | `TRUE` while its emergency brake is applied |

Every item but `EXISTS` is empty when there is no such train. The values of both functions are
identifiers, the same in both languages. The number is a numeral: a symbol goes in with apostrophes,
`F$RAME('N',"HELD")`.

`WRITE SYS$OUTPUT` prints a function's value at the prompt as in a procedure:

```
{{en-cab|WRITE SYS$OUTPUT F$PCC("LINE_NAME")}}
{{en-cab|WRITE SYS$OUTPUT F$PCC("CABS")}}
{{en-cab|WRITE SYS$OUTPUT F$PCC("FIRST_CAB")}}
{{en-cab|WRITE SYS$OUTPUT F$RAME(21,"STATION")}}
{{en-cab|WRITE SYS$OUTPUT F$RAME(21,"IS_CAB")}}
{{en-cab|WRITE SYS$OUTPUT F$RAME(3,"KIND")}}
```

### The built-in symbols

Five symbols are always there, read live, and cannot be given another value:

| | |
|---|---|
| `PCC$LANGUAGE` | `EN` or `FR`: a procedure branches on it to give its orders in the operator's spelling |
| `PCC$LINE` | The id of the line the PCC is on, empty on none |
| `PCC$MODE` | `NORMAL`, `STOPPED` or `EMERGENCY` |
| `PCC$RAMES` | How many trains are on the line |
| `PCC$CABS` | How many cabs are in service |

```
{{en-cab|SHOW SYMBOL PCC$MODE}}
{{en-cab|SHOW SYMBOL PCC$LINE}}
```

### $STATUS, and what is true

`$STATUS` is the condition value the last command left, and `$SEVERITY` its severity. An expression with
no operator is true as DCL has it: an integer when it is odd, a string when it begins with T or Y. So
`IF $STATUS` is true after a success and false after a refusal, and the `TRUE` and `FALSE` of the two
functions test as themselves. A procedure of the operator's own:

```
{{en-cab|TYPE ORDERS.COM}}
{{en-cab|@ORDERS}}
```

### The procedures in the store

The command store is seeded with five procedures the first time a node runs: `LOGIN.COM`, which every
session runs as it logs in; `STARTUP.COM`, the node's own, run with `@STARTUP`; `HELLO.COM` and
`DEMO.COM`, which are examples; and `WAITCAB.COM`, which waits for a cab to enter service, holds it at
its next platform and tells its driver why. They are the operator's to change: `EDIT WAITCAB.COM` opens
EDT on it.

```
{{en-screens|TYPE WAITCAB.COM}}
{{en-cab|@WAITCAB 5}}
```

The procedure language is a procedure's: at the prompt a line is a command, and neither an assignment nor
an `IF`.

## In French

The same desk with the app in French. The words that are gated answer only in their own language, and
what the product prints is French; OpenVMS's own messages stay as they are.

```
{{fr|SHOW LIGNE}}
{{fr|SET RAME 21 /RETENIR /MESSAGE="ATTENDEZ LE SIGNAL DE DEPART"}}
{{fr|SET RAME 21 /HOLD}}
{{fr|SHOW LINE}}
{{fr|SET LIGNE /CHARGER=4}}
{{fr|MONITOR CABINES}}
{{fr|URGENCE}}
{{fr|SHOW ALARMS}}
{{fr|REPRISE}}
```

## The rest of the shell

Everything else is metroSystem's OpenVMS emulation, as it was: nothing of it was written for the PCC, and
it reads the Mac where it reads anything.

| | |
|---|---|
| The process and the system | `SHOW PROCESS`, `SYSTEM`, `USERS`, `MEMORY`, `CPU`, `DEVICES`, `TIME`, `NETWORK`, `VERSION`, `LICENSE`, `QUOTA`, `WORKING_SET`, `ERROR`, `STATUS`, `CLUSTER`, `AUDIT`, `INTRUSION`, `PROTECTION`, `RMS_DEFAULT`, `TERMINAL`, `DEFAULT`; `SET DEFAULT`, `TERMINAL`, `PROMPT`, `PROCESS`, `PASSWORD` |
| Files | `DIRECTORY`, `TYPE`, `CREATE`, `COPY`, `RENAME`, `APPEND`, `DELETE`, `PURGE`, `SEARCH`, `DIFFERENCES`, `PRINT`, `BACKUP`, `MOUNT`, `DISMOUNT`, `INITIALIZE`, `ALLOCATE`, `DEALLOCATE` |
| The editor | `EDIT file`: EDT, in line mode and in screen mode |
| Mail | `MAIL`: OPCOM and the alarm server write to the operator when the line changes and when an alarm is raised |
| Symbols and logical names | `SHOW SYMBOL`, `SHOW LOGICAL`, `ASSIGN`, `DEFINE`, `DEASSIGN`; `PCC$ROOT`, `PCC$LINES` and `PCC$JOURNAL` are defined |
| Procedures | `@file`, `SUBMIT`, `WAIT`, `WRITE`, `SET ON`, `SET NOON`, `SET VERIFY`; `IF`, `GOTO`, `GOSUB`, `RETURN` and `EXIT` inside one |
| The operator | `REPLY`, `REQUEST`, `ACCOUNTING`, `INSTALL`, `PRODUCT`, `ANALYZE`, `PATCH`, `DEPOSIT`, `EXAMINE`, `SPAWN`, `ATTACH`, `PHONE`, `FINGER`, `RECALL`, `CONTINUE`, `LOGOUT` |
| DCLix | The system-management layer of the DCLixKit package: `SYSMAN`, `AUTHORIZE`, `SYSMGR`, `CLUSTERUI`, `MCR`, and the compilers, `FORTRAN` to `MACRO` |

```
{{en-library|DIRECTORY}}
{{en-library|SHOW LICENSE}}
```

`/PAGE` on any command pages its output: `SHOW RAMES/PAGE`.

Gone with metroSystem's railway: `VALCP` and every noun of it, `OPEN` and `CLOSE`, `DIAGNOSE`, the brake,
door and tyre utilities and the board catalogue of `RUN`, `SET STANDARD`, and `SHOW` and `SET` for
`MODBUS`, `HARDWARE`, `BACKEND`, `PRATIC`, `PUPITRE`, `PAX` and the cluster of peers. Each is now an
unrecognised verb or keyword, as on a node that never had the product.

## HELP and SELFTEST

`HELP` is OpenVMS's, a library of topics browsed at a `Topic?` prompt, and every command on this page has
its topic: `HELP PCC` is the product's own, with a first turn at the desk, the vocabulary of the two
languages, the lines and the alarms; `HELP LEXICALS` has the two functions; `HELP UTILITIES` the
monitors and the forms.

`SELFTEST` drives every documented verb once and says how each went. It is the shell's own check that
nothing is documented and not there: a verb or a keyword the dispatch does not know fails it.

```
{{selftest-en|SELFTEST|1|6..4}}
```

The headless tool's `--selftest` runs it in both languages, checks that every verb it drives has its
`HELP` topic, and then does what `SELFTEST` cannot: it gives the orders for real, to an engine with
scripted cabs, and checks what each one did ([architecture.md](architecture.md#the-self-test)).
