<!-- Made by Scripts/makedocs.sh from Scripts/dcl.template.md: change the template, not this page. -->
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
$ SET RAME 77 /HOLD
%PCC-W-REFUSED, No train 77 on the line: SHOW RAMES lists them.
$ SHOW SYMBOL $STATUS
  $STATUS = "%X000080D0"
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
$ SHOW PCC

  LPD PCC-CABINE V1.0 on node PCCVL1 -- PCC of the Cabine cabs

  Listener:             LISTENING ON PORT 62000
  Network:              THIS MAC ONLY (LOOPBACK)
  Name:                 PCC LIGNE 21
  Address for Cabine:   localhost port 62000
  Listening for:        0 00:00:20
  Line:                 Ligne 21 (21, rev 25030a0dde1f0c8b)
  Connections:          1 -- in service: 1, on the line: 0, others: 0
  Library:              6 lines (SHOW LINES)
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
$ SET PCC /NAME="PCC NORD"

New mail on node PCCVL1 from OPCOM
%PCC-S-NAME, the PCC is named PCC NORD
$ SET PCC /DISABLE
%PCC-S-DISABLED, PCC disabled: the cabs were told, and their connections are closed
$ SHOW PCC

  LPD PCC-CABINE V1.0 on node PCCVL1 -- PCC of the Cabine cabs

  Listener:             DISABLED
  Network:              THIS MAC ONLY (LOOPBACK)
  Name:                 PCC NORD
  Headway:              150 s

  The PCC is disabled: SET PCC /ENABLE in a DCL terminal starts it.
$ SET PCC /ENABLE
%PCC-S-ENABLED, PCC enabled: SHOW PCC says where it listens
$ WAIT 00:00:02

New mail on node PCCVL1 from OPCOM
$ SHOW PCC

  LPD PCC-CABINE V1.0 on node PCCVL1 -- PCC of the Cabine cabs

  Listener:             LISTENING ON PORT 62004
  Network:              THIS MAC ONLY (LOOPBACK)
  Name:                 PCC NORD
  Address for Cabine:   localhost port 62004
  Listening for:        0 00:00:02
  Line:                 Ligne 21 (21, rev 25030a0dde1f0c8b)
  Connections:          0 -- in service: 0, on the line: 0, others: 0
  Library:              6 lines (SHOW LINES)
$ SET PCC /LAN=OFF
%PCC-S-LAN, the PCC listens on this Mac only (loopback) and is not advertised
$ SET PCC
%PCC-W-MISSQUAL, expected /ENABLE, /DISABLE, /LAN= or /NAME= -- see HELP SET PCC
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
$ SHOW LINES

  Library of lines: 6 held.  The PCC is on Ligne 21 (marked *).
     Id     Name             Revision         Stations     Length  Source  From -- to
     ------ ---------------- ---------------- -------- ----------  ------- ----------------------------------------
     1      Ligne 1          54031a242d1d2b6a       25   16.87 km  yes     La Défense (Grande Arche) -- Château de Vincennes
     4      Ligne 4          c4f41e9d8fbc77b4       29   13.71 km  yes     Porte de Clignancourt -- Bagneux – Lucie Aubrac
     6      Ligne 6          8aed083cbb6a5806       28   14.11 km  yes     Charles de Gaulle – Étoile -- Nation
     11     Ligne 11         524d18bb8a29d7b5       19   12.66 km  yes     Châtelet -- Rosny-Bois-Perrier
     14     Ligne 14         76f90530f0c30026       21   28.25 km  yes     Saint-Denis – Pleyel -- Aéroport d'Orly
   * 21     Ligne 21         25030a0dde1f0c8b       11    7.62 km  no      Porte du Levant -- Porte du Couchant

  SET LINE /LOAD=id puts the PCC on a line; RUN LIGNE_DIR browses the library.
```

### SHOW LINE

```
SHOW LINE [/STATIONS] [/SOURCE]
```

The line the PCC is on: its name, id and revision; the length of each track and the stations; service,
mode and the line's clock; the headway, how the fleet is sized and the time of a lap; the trains; and the
stock they are made of.

```
$ SHOW LINE

  Ligne 21 (21, rev 25030a0dde1f0c8b)
  Track:                7617.5 m a track, 11 stations
  From -- to:           Porte du Levant -- Porte du Couchant
  Service:              ON   Mode: NORMAL   Line clock: 08:42:20
  Headway:              150 s   Fleet: FROM THE HEADWAY   Lap: 39 min 10 s
  Trains:               16 -- 15 automatic (15 wanted), cabs: 1
  Stock:                75 m, 70.0 km/h, 560 places

  SHOW LINE /STATIONS lists the stations, /SOURCE says where the data came from; SET LINE gives the orders.
```

The mode is `NORMAL`, `SERVICE STOPPED` or `EMERGENCY STOP`. The line's clock starts at 08:42:00 when
the PCC takes the line up, and runs in real time. "15 automatic (15 wanted)" is the fleet coming to its
size: trains join and leave at the tails, so the two differ for a while after a headway is changed.

`/STATIONS` lists every station with the stop of each track, in metres from the start of that track:

```
$ SHOW LINE /STATIONS

  Ligne 21 (21, rev 25030a0dde1f0c8b)
  Stations, with the stop on each track (metres from the start of the track):
     No  Station                              Track 1     Track 2
    ---  ------------------------------    ----------  ----------
      1  Porte du Levant                      279.5 m    7415.0 m
      2  Rue des Tanneurs                     877.9 m    6816.6 m
      3  Place de l'Horloge                  1659.6 m    6034.9 m
      4  Jardin d'Hiver                      2225.4 m    5469.1 m
      5  Pont aux Cygnes                     3205.2 m    4489.3 m
      6  Halle aux Blés                      3809.8 m    3884.7 m
      7  Carrefour Saint-Aubin               4505.2 m    3189.3 m
      8  Passage des Lanternes               5345.6 m    2348.9 m
      9  Cour des Messageries                5863.6 m    1830.9 m
     10  Les Trois Moulins                   6746.8 m     947.7 m
     11  Porte du Couchant                   7414.9 m     279.6 m
```

`/SOURCE` says where the line's data came from, with the credits its licences ask for, and whether the
package carries the source a Cabine builds the line from. Ligne 4:

```
$ SHOW LINE /SOURCE

  Ligne 4 (4, rev c4f41e9d8fbc77b4)
  Sources of the line's data:
    Track:     Île-de-France Mobilités, Tracés du réseau ferré (Licence Ouverte 2.0)
    Stations:  OpenStreetMap relation 123767, © OpenStreetMap contributors (ODbL)
    Ground:    IGN RGE ALTI (Licence Ouverte 2.0)
    Extract of 2026-11-10
  The package carries the line's source: a Cabine that has not built this line in is sent it.
```

and Ligne 21, which is invented:

```
$ SHOW LINE /SOURCE

  Ligne 21 (21, rev 25030a0dde1f0c8b)
  Sources of the line's data:
    An invented line, built into every Cabine: it has no outside data to credit.
  The package carries no source: every Cabine has this line built in.
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
$ SET LINE /LOAD=4

New mail on node PCCVL1 from OPCOM
%PCC-S-LOAD, the PCC is on Ligne 4: its trains are seeded afresh, and every cab follows
$ SHOW LINE

  Ligne 4 (4, rev c4f41e9d8fbc77b4)
  Track:                13710.0 m a track, 29 stations
  From -- to:           Porte de Clignancourt -- Bagneux – Lucie Aubrac
  Service:              ON   Mode: NORMAL   Line clock: 08:42:00
  Headway:              150 s   Fleet: FROM THE HEADWAY   Lap: 84 min 45 s
  Trains:               34 -- 34 automatic (34 wanted), cabs: 0
  Stock:                75 m, 70.0 km/h, 560 places

  SHOW LINE /STATIONS lists the stations, /SOURCE says where the data came from; SET LINE gives the orders.
$ SET LINE /LOAD=99
%PCC-W-REFUSED, The library holds no line 99.
$ SET LINE /CLOSE

New mail on node PCCVL1 from OPCOM
%PCC-S-CLOSE, the PCC is on no line: its cabs wait for one
$ SHOW LINE

  The PCC is on no line: SET LINE /LOAD=id puts it on one of its library (SHOW LINES).
$ SET LINE /REREAD
%PCC-S-REREAD, library read again: 6 lines held
$ SET LINE /LOAD=21

New mail on node PCCVL1 from OPCOM
%PCC-S-LOAD, the PCC is on Ligne 21: its trains are seeded afresh, and every cab follows
$ SET LINE
%PCC-W-MISSQUAL, expected /LOAD=, /CLOSE, /REREAD, /SERVICE=, /EMERGENCY=, /HEADWAY= or /RAMES= -- see HELP SET LINE
```

With a cab in service:

```
$ SET LINE /LOAD=4
%PCC-W-REFUSED, A cab is in service on the present line: the PCC changes line only when none is.
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
$ SET LINE /HEADWAY=120
%PCC-S-HEADWAY, headway set to 120 s -- the fleet comes to it as trains reach the tails
$ SET LINE /HEADWAY=5
%PCC-W-REFUSED, A headway lies between 30 and 3600 seconds.
$ SET LINE /RAMES=12
%PCC-S-FLEET, fleet fixed at 12 trains, cabs included
$ SET LINE /RAMES=AUTO
%PCC-S-FLEET, fleet sized from the headway again
$ SET LINE /SERVICE=MAYBE
%PCC-W-IVVALUE, usage: /SERVICE=ON or /SERVICE=OFF
```

### START LINE, STOP LINE

```
START LINE
STOP LINE
```

Line service on and off: `SET LINE /SERVICE=ON` and `=OFF`.

```
$ STOP LINE

New mail on node PCCVL1 from OPCOM
%PCC-S-SERVICE, line service stopped -- the trains come to a stand where they can
$ SHOW LINE

  Ligne 21 (21, rev 25030a0dde1f0c8b)
  Track:                7617.5 m a track, 11 stations
  From -- to:           Porte du Levant -- Porte du Couchant
  Service:              OFF   Mode: SERVICE STOPPED   Line clock: 08:42:21
  Headway:              120 s   Fleet: FROM THE HEADWAY   Lap: 39 min 10 s
  Trains:               16 -- 15 automatic (19 wanted), cabs: 1
  Stock:                75 m, 70.0 km/h, 560 places

  SHOW LINE /STATIONS lists the stations, /SOURCE says where the data came from; SET LINE gives the orders.
$ START LINE

New mail on node PCCVL1 from OPCOM
%PCC-S-SERVICE, line service started
```

### EMERGENCY, RESUME

```
EMERGENCY
RESUME
```

The general emergency stop and its release: `SET LINE /EMERGENCY=ON` and `=OFF`. The stop raises the
critical alarm `LIGNE AU`, which returns to normal when it is released.

```
$ EMERGENCY

New mail on node PCCVL1 from OPCOM

New mail on node PCCVL1 from SCADA$MGR
%PCC-S-EMERGENCY, general emergency stop -- every train is braked
$ SHOW STATUS

  Status on 11-NOV-2026 21:59:13.42
  Elapsed CPU: 0 00:31:25.95   Buf I/O: 38271    Dir I/O: 19135    Page faults: 76542
  Connect time: 1 18:31:25
  PCC: Ligne 21 -- EMERGENCY STOP -- trains: 17, cabs: 1
$ SHOW ALARMS

Standing SCADA alarms at 11-NOV-2026 21:59:13.43
  Id    Time                         Severity   State    Source      Point          Message
  ----  ---------------------------  ---------  -------  ----------  -------------  ------------------------------
  0003  11-NOV-2026 21:59:13.42      CRITICAL   UNACK    LIGNE       AU             General emergency stop -- every train is braked

  ACKNOWLEDGE ALARM <id|ALL> [/CLEAR] acknowledges, and clears an event; SHELVE/UNSHELVE manage nuisance alarms.
  SHOW ALARMS/ALL lists the full journal including cleared history.
$ RESUME

New mail on node PCCVL1 from OPCOM
%PCC-S-EMERGENCY, general emergency stop released
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
$ SHOW RAMES

  Trains of Ligne 21 at 08:42:20 by the line's clock:
    No  Kind     Trk    Position      Speed  State         Doors      Station
    --  ------  ----  ----------  ---------  ------------  ---------  ----------------------
    02  AUTO       1    1659.6 m    0.0 m/s  DEPARTING     40 %       Place de l'Horloge
    03  AUTO       1    2225.4 m    0.0 m/s  AT PLATFORM   OPEN       Jardin d'Hiver
    04  AUTO       1    3258.7 m    8.3 m/s  RUNNING       CLOSED     Halle aux Blés
    05  AUTO       1    4518.9 m    5.8 m/s  RUNNING       CLOSED     Passage des Lanternes
    06  AUTO       1    5347.2 m    2.0 m/s  RUNNING       CLOSED     Cour des Messageries
    07  AUTO       1    6746.8 m    0.0 m/s  DEPARTING     OPEN       Les Trois Moulins
    08  AUTO       1    7414.9 m    0.0 m/s  DEPARTING     32 %       Porte du Couchant
    09  AUTO       2     282.3 m    2.6 m/s  RUNNING       CLOSED     Les Trois Moulins
    10  AUTO       2     947.7 m    0.0 m/s  DEPARTING     CLOSED     Les Trois Moulins
    11  AUTO       2    2367.2 m    6.7 m/s  RUNNING       CLOSED     Carrefour Saint-Aubin
    12  AUTO       2    3189.3 m    0.0 m/s  DEPARTING     CLOSED     Carrefour Saint-Aubin
    13  AUTO       2    4534.2 m   10.5 m/s  RUNNING       CLOSED     Jardin d'Hiver
    14  AUTO       2    5533.1 m   10.2 m/s  RUNNING       CLOSED     Place de l'Horloge
    15  AUTO       2    6816.8 m    0.7 m/s  RUNNING       CLOSED     Porte du Levant
    16  AUTO       2    7415.0 m    0.0 m/s  AT PLATFORM   OPEN       Porte du Levant
    21  CAB        1     563.7 m   14.0 m/s  RUNNING       CLOSED     Rue des Tanneurs
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
$ SHOW RAME 21

  Train 21 of Ligne 21 at 08:42:20 by the line's clock
  Kind:                 CAB
  Track:                1   Position: 563.7 m
  Speed:                14.0 m/s  (50.4 km/h)   Acceleration: +0.00 m/s²
  State:                RUNNING   Doors: CLOSED
  Station:              TO Rue des Tanneurs
  PCC orders:           none

  Cab:                  Alma  (Alma-0001)
  Connection:           #1  127.0.0.1:49777  Cabine 1.0
  Link:                 LIVE (round trip 10 ms)
  Driving:              PA   Autopilot: ENGAGED
  Passengers:           212/560   Timetable: 4 s EARLY
  Emergency brake:      RELEASED
  Authority:            ends 993 m ahead: train 02 ahead, its rear 1027 m away
  Last report:          none
$ SHOW RAME 3

  Train 03 of Ligne 21 at 08:42:20 by the line's clock
  Kind:                 AUTO
  Track:                1   Position: 2225.4 m
  Speed:                0.0 m/s  (0.0 km/h)   Acceleration: +0.00 m/s²
  State:                AT PLATFORM   Doors: OPEN
  Station:              AT Jardin d'Hiver
  PCC orders:           none
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
$ SET RAME 21 /HOLD /MESSAGE="WAIT FOR THE DEPARTURE SIGNAL"
%PCC-S-HOLD, train 21 is held at its platform, or at the next it reaches
%PCC-S-MESSAGE, message sent to the cab of train 21
$ SHOW CABS

  Cabs in service on Ligne 21: 1
    No  Cab                 Link           RT  Mode  Autopilot   Trk    Position      Speed  Authority
    --  ------------------  --------  -------  ----  ---------  ----  ----------  ---------  ----------------------------------
    21  Alma                LIVE        10 ms  PA    ENGAGED       1     563.7 m   14.0 m/s  ends 993 m ahead: train 02 ahead, its rear 1027 m away   [HELD BY THE PCC]

  SHOW RAME number shows one in full; SET RAME number gives it an order; MONITOR CABS follows them live.
$ SET RAME 21 /RELEASE
%PCC-S-RELEASE, train 21 is released
$ SET RAME 3 /MESSAGE="HELLO"
%PCC-W-REFUSED, Train 03 is not a cab: only a cab takes a message or a call.
$ SET RAME 77 /HOLD
%PCC-W-REFUSED, No train 77 on the line: SHOW RAMES lists them.
$ SET RAME 21
%PCC-W-MISSQUAL, expected /HOLD, /RELEASE, /BRAKE, /UNBRAKE, /MESSAGE= or /CALL -- see HELP SET RAME
$ SET RAME 21 /CALL
%PCC-S-CALL, the driver of train 21 is being called
```

A brake the PCC has ordered is a standing alarm until it is released:

```
$ SET RAME 21 /BRAKE
%PCC-S-BRAKE, emergency brake ordered on train 21
$ SHOW ALARMS

Standing SCADA alarms at 11-NOV-2026 21:59:12.36
  Id    Time                         Severity   State    Source      Point          Message
  ----  ---------------------------  ---------  -------  ----------  -------------  ------------------------------
  0001  11-NOV-2026 21:59:12.36      MAJOR      UNACK    CABINE 21   FU             Emergency brake applied

  ACKNOWLEDGE ALARM <id|ALL> [/CLEAR] acknowledges, and clears an event; SHELVE/UNSHELVE manage nuisance alarms.
  SHOW ALARMS/ALL lists the full journal including cleared history.
$ SET RAME 21 /UNBRAKE
%PCC-S-UNBRAKE, emergency brake released on train 21
```

### START RAME, STOP RAME

```
STOP RAME number
START RAME number
```

The emergency brake of one train, and its release: `SET RAME number /BRAKE` and `/UNBRAKE`.

```
$ STOP RAME 5
%PCC-S-BRAKE, emergency brake ordered on train 05
$ SHOW RAME 5

  Train 05 of Ligne 21 at 08:42:21 by the line's clock
  Kind:                 AUTO
  Track:                1   Position: 4524.4 m
  Speed:                4.3 m/s  (15.3 km/h)   Acceleration: -1.85 m/s²
  State:                EB   Doors: CLOSED
  Station:              TO Passage des Lanternes
  PCC orders:           EB ORDERED BY THE PCC
$ START RAME 5
%PCC-S-UNBRAKE, emergency brake released on train 05
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
$ SHOW CABS

  Cabs in service on Ligne 21: 1
    No  Cab                 Link           RT  Mode  Autopilot   Trk    Position      Speed  Authority
    --  ------------------  --------  -------  ----  ---------  ----  ----------  ---------  ----------------------------------
    21  Alma                LIVE        10 ms  PA    ENGAGED       1     563.7 m   14.0 m/s  ends 993 m ahead: train 02 ahead, its rear 1027 m away

  SHOW RAME number shows one in full; SET RAME number gives it an order; MONITOR CABS follows them live.
```

### SHOW CONNECTIONS

```
SHOW CONNECTIONS
```

Every connection to the PCC, whatever its standing: its number, its standing, its train if it has one,
the cab's name and its program; where it comes from, the line it holds, when it was last heard and the
round trip of its last ping.

```
$ SHOW CONNECTIONS

  Connections: 1 -- LISTENING ON PORT 62000
    #1  IN SERVICE  Train 21  Alma (Cabine 1.0)
        127.0.0.1:49777  its line Ligne 21 (21, rev 25030a0dde1f0c8b)  heard 0.0 s ago, round trip 10 ms
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
$ SHOW JOURNAL

  Journal -- lines shown: 5 of 5
    --:--:--  Library read: 6 lines held
    08:42:00  Line taken up: Ligne 21 (21, rev 25030a0dde1f0c8b), 16 automatic trains
    08:42:00  Cab Alma connected, holding Ligne 21 (21, rev 25030a0dde1f0c8b)
    08:42:00  Cab Alma is on the line
    08:42:00  Cab Alma in service as train 21, track 1 at 279.5 m, in place of 01
$ SHOW JOURNAL /LAST=3

  Journal -- lines shown: 3 of 5
    08:42:00  Cab Alma connected, holding Ligne 21 (21, rev 25030a0dde1f0c8b)
    08:42:00  Cab Alma is on the line
    08:42:00  Cab Alma in service as train 21, track 1 at 279.5 m, in place of 01
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
$ SHOW ALARMS

Standing SCADA alarms at 11-NOV-2026 22:00:07.92
  Id    Time                         Severity   State    Source      Point          Message
  ----  ---------------------------  ---------  -------  ----------  -------------  ------------------------------
  0001  11-NOV-2026 22:00:04.57      MINOR      UNACK    PCC         FICHIER        A line file was refused -- see the journal

  ACKNOWLEDGE ALARM <id|ALL> [/CLEAR] acknowledges, and clears an event; SHELVE/UNSHELVE manage nuisance alarms.
  SHOW ALARMS/ALL lists the full journal including cleared history.
$ EMERGENCY

New mail on node PCCVL1 from OPCOM

New mail on node PCCVL1 from SCADA$MGR
%PCC-S-EMERGENCY, general emergency stop -- every train is braked
$ ACKNOWLEDGE ALARM ALL
%ACK-S-ACKED, 2 alarms acknowledged
$ SHOW ALARMS

Standing SCADA alarms at 11-NOV-2026 22:00:07.93
  Id    Time                         Severity   State    Source      Point          Message
  ----  ---------------------------  ---------  -------  ----------  -------------  ------------------------------
  0002  11-NOV-2026 22:00:07.93      CRITICAL   ACK      LIGNE       AU             General emergency stop -- every train is braked
  0001  11-NOV-2026 22:00:04.57      MINOR      ACK      PCC         FICHIER        A line file was refused -- see the journal

  ACKNOWLEDGE ALARM <id|ALL> [/CLEAR] acknowledges, and clears an event; SHELVE/UNSHELVE manage nuisance alarms.
  SHOW ALARMS/ALL lists the full journal including cleared history.
$ ACKNOWLEDGE ALARM 2 /CLEAR
%ACK-S-ACKED, alarm 0002 acknowledged
%ACK-W-HELD, alarm 0002 is held by its condition: it returns to normal when the condition does
$ ACKNOWLEDGE ALARM 1 /CLEAR
%ACK-S-ACKED, alarm 0001 acknowledged
%ACK-S-CLEARED, alarm 0001 cleared
$ RESUME

New mail on node PCCVL1 from OPCOM
%PCC-S-EMERGENCY, general emergency stop released
$ SHOW ALARMS/ALL

SCADA alarm journal at 11-NOV-2026 22:00:07.93
  Id    Time                         Severity   State    Source      Point          Message
  ----  ---------------------------  ---------  -------  ----------  -------------  ------------------------------
  0002  11-NOV-2026 22:00:07.93      CRITICAL   CLEARED  LIGNE       AU             General emergency stop -- every train is braked
  0001  11-NOV-2026 22:00:04.57      MINOR      CLEARED  PCC         FICHIER        A line file was refused -- see the journal

  ACKNOWLEDGE ALARM <id|ALL> [/CLEAR] acknowledges, and clears an event; SHELVE/UNSHELVE manage nuisance alarms.
```

The states are `UNACK`, `ACK`, `RTN` for an alarm that returned to normal before it was acknowledged,
`SHLVD` and `CLEARED`. A shelved alarm leaves the list of those that stand and stays in the log:

```
$ SET RAME 21 /BRAKE
%PCC-S-BRAKE, emergency brake ordered on train 21
$ SHELVE ALARM 3
%SHELVE-S-SHELVED, alarm 0003 shelved (ISA-18.2 SHLVD)
$ SHOW ALARMS

Standing SCADA alarms at 11-NOV-2026 22:00:07.93
  Id    Time                         Severity   State    Source      Point          Message
  ----  ---------------------------  ---------  -------  ----------  -------------  ------------------------------
  (no standing alarms -- SHOW ALARMS/ALL for history)
$ UNSHELVE ALARM 3
%UNSHELVE-S-RESTORED, alarm 0003 restored to the annunciator
$ SHOW ALARMS

Standing SCADA alarms at 11-NOV-2026 22:00:07.93
  Id    Time                         Severity   State    Source      Point          Message
  ----  ---------------------------  ---------  -------  ----------  -------------  ------------------------------
  0003  11-NOV-2026 22:00:07.93      MAJOR      UNACK    CABINE 21   FU             Emergency brake applied

  ACKNOWLEDGE ALARM <id|ALL> [/CLEAR] acknowledges, and clears an event; SHELVE/UNSHELVE manage nuisance alarms.
  SHOW ALARMS/ALL lists the full journal including cleared history.
$ SET RAME 21 /UNBRAKE
%PCC-S-UNBRAKE, emergency brake released on train 21
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
$ MONITOR LINE
 LPD PCC-CABINE V1.0             LINE MONITOR                      Node PCCVL1
 11-NOV-2026 21:59:43   Ligne 21   Mode: NORMAL   Line clock: 08:42:25
┌─ Ligne 21 -- 7.6 km a track, 11 stations ───────────────────────────────────┐
│      ▼Porte du Levant  ▼Jardin d'Hiver                 Porte du Couchant▼   │
│ 1→╭╌╌╤═21»═╤══════╤═22»╤>══════04>════╤════05>══════06>══╤══════07>════08>╌╮│
│ 2←╰╌<16═══<15═════╧════<14═════<13════╧═════<12═════<11══╧═══════<10═══<09╌╯│
│            ▲Rue des Tanneurs     ▲Pont aux Cygnes   ▲Passage des Lanternes  │
│ 03> automatic   21» cab   H held   ! braked   · turning back   ╌ tail       │
└─────────────────────────────────────────────────────────────────────────────┘
┌─ Alarms  0 active, 0 unacknowledged ────────────────────────────────────────┐
│ No active alarms                                                            │
└─────────────────────────────────────────────────────────────────────────────┘
┌─ Cabs (2) ──────────────────────────────────────────────────────────────────┐
│ No  Cab           Link    Mode km/h   State        Authority                │
│ 21  Alma          LIVE    PA     50.4 RUNNING      1273 m: train 22         │
│ 22  Bastien       LIVE    PA     50.4 RUNNING      119 m: train 03          │
│                                                                             │
│                                                                             │
│                                                                             │
│                                                                             │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘

 Ctrl/Z Exit   Ctrl/W Refresh   Interval 0.5 s              Elapsed 0 00:00:00
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
$ MONITOR LINE
 LPD PCC-CABINE V1.0             LINE MONITOR                      Node PCCVL1
 11-NOV-2026 21:59:48   Ligne 21   Mode: NORMAL   Line clock: 08:42:30
┌─ Ligne 21 -- 7.6 km a track, 11 stations ───────────────────────────────────┐
│      ▼Porte du Levant  ▼Jardin d'Hiver                 Porte du Couchant▼   │
│ 1→╭╌╌╤══21H╤══════╤═22!╤>═══════04>═══╤═════05>═════╤06>═╤══════07>════08>╌╮│
│ 2←╰╌<16═══<15═════╧═══<14══════<13════╧════<12══════<11══╧═══════<10═══<09╌╯│
│            ▲Rue des Tanneurs     ▲Pont aux Cygnes   ▲Passage des Lanternes  │
│ 03> automatic   21» cab   H held   ! braked   · turning back   ╌ tail       │
└─────────────────────────────────────────────────────────────────────────────┘
┌─ Alarms  1 active, 1 unacknowledged ────────────────────────────────────────┐
│ 21:59:46  UNACK %PCC-E-FU, CABINE 22: Emergency brake applied               │
└─────────────────────────────────────────────────────────────────────────────┘
┌─ Cabs (2) ──────────────────────────────────────────────────────────────────┐
│ No  Cab           Link    Mode km/h   State        Authority                │
│ 21  Alma          LIVE    PA     50.4 HELD         1259 m: train 22         │
│ 22  Bastien       LIVE    PA      0.0 EB           106 m: train 03          │
│                                                                             │
│                                                                             │
│                                                                             │
│                                                                             │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘

 Ctrl/Z Exit   Ctrl/W Refresh   Interval 0.5 s              Elapsed 0 00:00:00
```

### MONITOR CABS

Every cab in service, four rows each: its number and name, its link and the round trip of its last ping,
the driving mode and whether the automatic driver has the train; its track, position, speed, state and
station; what the PCC has ordered of it, its doors, its emergency brake, its timetable and its
passengers; and its movement authority with what ends it. A cab that has fallen silent says for how long,
flashing. A row too long for the screen loses its last items whole, and an emergency brake that is
applied comes first, with its cause in the cab's own words.

```
$ MONITOR CABS
 LPD PCC-CABINE V1.0              CAB MONITOR                      Node PCCVL1
 11-NOV-2026 21:59:48   Ligne 21   Mode: NORMAL   Line clock: 08:42:30
┌─ Cabs (2) ──────────────────────────────────────────────────────────────────┐
│ 21  Alma               LIVE 39 ms   PA   autopilot ENGAGED                  │
│     track 1   706.3 m   50.4 km/h   HELD   TO Rue des Tanneurs              │
│     [HELD BY THE PCC]   doors CLOSED   EB RELEASED   4 s EARLY   pax 212/560│
│     authority ends 1252 m ahead: train 22 ahead, its rear 1286 m away       │
│ 22  Bastien            LIVE 25 ms   PA   autopilot ENGAGED                  │
│     track 1   2063.3 m   0.0 km/h   EB   TO Jardin d'Hiver                  │
│     EB APPLIED (ARRET COMMANDE PAR LE PCC)   [EB ORDERED BY THE PCC]        │
│     authority ends 112 m ahead: train 03 ahead, its rear 140 m away         │
│                                                                             │
│                                                                             │
│                                                                             │
│                                                                             │
│                                                                             │
│                                                                             │
│                                                                             │
│                                                                             │
│                                                                             │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘

 Ctrl/Z Exit   Ctrl/W Refresh   Interval 0.5 s              Elapsed 0 00:00:00
```

### MONITOR RAMES

Every train of the line: number, kind, track, position, speed, state, doors, the operator's hold (`H`)
and brake (`!`), and the station it stands at or runs to.

```
$ MONITOR RAMES
 LPD PCC-CABINE V1.0             TRAIN MONITOR                     Node PCCVL1
 11-NOV-2026 21:59:44   Ligne 21   Mode: NORMAL   Line clock: 08:42:26
┌─ Trains (16) ───────────────────────────────────────────────────────────────┐
│ No Kind   Trk  Position  km/h State        Doors    PCC Station             │
│ 03 AUTO   1      2244 m  24.2 RUNNING      CLOSED       Pont aux Cygnes     │
│ 04 AUTO   1      3268 m  30.0 RUNNING      CLOSED       Halle aux Blés      │
│ 05 AUTO   1      4546 m  35.3 RUNNING      CLOSED       Passage des Lantern…│
│ 06 AUTO   1      5488 m  45.5 RUNNING      CLOSED       Cour des Messageries│
│ 07 AUTO   1      6761 m  21.5 RUNNING      CLOSED       Porte du Couchant   │
│ 08 AUTO   1      7463 m  27.9 RUNNING      CLOSED       --                  │
│ 09 AUTO   2       326 m  38.6 RUNNING      CLOSED       Les Trois Moulins   │
│ 10 AUTO   2       952 m  12.1 RUNNING      CLOSED       Cour des Messageries│
│ 11 AUTO   2      2351 m   8.0 RUNNING      CLOSED       Carrefour Saint-Aub…│
│ 12 AUTO   2      3264 m  48.2 RUNNING      CLOSED       Halle aux Blés      │
│ 13 AUTO   2      4596 m  55.5 RUNNING      CLOSED       Jardin d'Hiver      │
│ 14 AUTO   2      5531 m  36.5 RUNNING      CLOSED       Place de l'Horloge  │
│ 15 AUTO   2      6824 m  15.9 RUNNING      CLOSED       Porte du Levant     │
│ 16 AUTO   2      7508 m  28.0 RUNNING      CLOSED       --                  │
│ 21 CAB    1       647 m  50.4 RUNNING      CLOSED       Rue des Tanneurs    │
│ 22 CAB    1      2027 m  50.4 RUNNING      CLOSED       Jardin d'Hiver      │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘

 Ctrl/Z Exit   Ctrl/W Refresh   Interval 0.5 s              Elapsed 0 00:00:00
```

### MONITOR CONNECTIONS

The listener, and every connection whatever its standing: its train, its cab's name, the line it holds
(id, and the first eight figures of the revision), when it was last heard, the round trip of its last
ping and where it comes from.

```
$ MONITOR CONNECTIONS
 LPD PCC-CABINE V1.0          CONNECTION MONITOR                   Node PCCVL1
 11-NOV-2026 21:59:44   Ligne 21   Mode: NORMAL   Line clock: 08:42:26
┌─ PCC LIGNE 21 ──────────────────────────────────────────────────────────────┐
│ LISTENING ON PORT 62005 -- THIS MAC ONLY (LOOPBACK)                         │
│ Address for Cabine: localhost port 62005                                    │
└─────────────────────────────────────────────────────────────────────────────┘
┌─ Connections (2) ───────────────────────────────────────────────────────────┐
│ #   Standing   Train Cab         Line           Heard     RT From           │
│ #1  IN SERVICE 21    Alma        21 25030a0d    0.1 s  38 ms 127.0.0.1      │
│ #2  IN SERVICE 22    Bastien     21 25030a0d    0.1 s  20 ms 127.0.0.1      │
│                                                                             │
│                                                                             │
│                                                                             │
│                                                                             │
│                                                                             │
│                                                                             │
│                                                                             │
│                                                                             │
│                                                                             │
│                                                                             │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘

 Ctrl/Z Exit   Ctrl/W Refresh   Interval 0.5 s              Elapsed 0 00:00:00
```

### The system's classes

OpenVMS's own Monitor Utility is there beside them, in English as it always was: `MONITOR SYSTEM`,
`MODES`, `PROCESSES`, `IO`, `PAGE`, `STATES`, `DISK`, `LOCK`, `FCP` and `ALL_CLASSES`, every three seconds
or every `/INTERVAL`. Its figures are the Mac's own. The PCC shows in it as the processes an OpenVMS node
would run it in: the engine, the listener, the alarm server, and a link for each cab in service.

```
$ MONITOR PROCESSES
                          VSI OpenVMS Monitor Utility
                             TOP CPU TIME PROCESSES
                                 on node PCCVL1
                            11-NOV-2026 21:59:50.91

    0     10    20    30    40    50    60    70    80    90    100
    + - - + - - + - - + - - + - - + - - + - - + - - + - - + - - +
00000403 PCC_ENGINE        40.0  COM
    |********************
0000040A CAB_21_LINK        6.0  COM
    |***
0000040B CAB_22_LINK        6.0  COM
    |***
00000404 PCC_LISTENER       4.0  LEF
    |**
00000405 PCC_SCADA          3.0  HIB
    |*
000004CB DCL_OPERATOR       0.5  CUR
    |
----------------------------------------------------------------------------
  From: 11-NOV-2026 21:59:50.61   To: 11-NOV-2026 21:59:50.91
  Elapsed: 0 00:00:00   Interval: 3s   Ctrl/Y or ESC ESC interrupts
$ SHOW SYSTEM

VSI OpenVMS V9.2-3 on node PCCVL1  11-NOV-2026 21:59:50.92  Uptime  1 18:32:02
  Load average: 2.44  2.63  2.45    Active processes: 1131
  Pid    Process Name      State  Pri      I/O       CPU       Page flts Pages
00000401 SWAPPER          HIB    16        0   0 00:00:01.21          0     0
00000402 NULL             COM     0        0   3 00:00:04.18          0     0
00000403 PCC_ENGINE       COM     8      819   0 00:00:12.66        321   629
00000404 PCC_LISTENER     LEF     6      853   0 00:00:13.31        339   625
00000405 PCC_SCADA        HIB     6      887   0 00:00:14.47        357   605
0000040A CAB_21_LINK      COM     6      950   0 00:00:15.68        375   632
0000040B CAB_22_LINK      COM     6     1006   0 00:00:16.85        393   663
00000414 LOGGER           LEF     4      209   0 00:00:04.81         72   240
00000415 TELNET_SERVER    LEF     6      144   0 00:00:01.95        108   373
000004CB DCL_OPERATOR     CUR     4       23   0 00:00:00.18         24   154
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
$ RUN RAME_DIR
┌────────────────────────────────────────────────────────────────────────────┐
│                  LPD PCC-CABINE V1.0  --  TRAINS AND CABS                  │
│           Ligne 21 -- NORMAL -- 08:42:26 -- trains: 16, cabs: 2            │
├────────────────────────┬───────────────────────────────────────────────────┤
│ No Kind   Cab / state  │                                                   │
│▶03 AUTO   RUNNING      │  Train:         03 AUTO                           │
│ 04 AUTO   RUNNING      │  Track:         1                                 │
│ 05 AUTO   RUNNING      │  Position:      2247.1 m                          │
│ 06 AUTO   RUNNING      │  Speed:         26.4 km/h (7.3 m/s)               │
│ 07 AUTO   RUNNING      │  State:         RUNNING                           │
│ 08 AUTO   RUNNING      │  Doors:         CLOSED                            │
│ 09 AUTO   RUNNING      │  Station:       TO Pont aux Cygnes                │
│ 10 AUTO   RUNNING      │  PCC orders:    none                              │
│ 11 AUTO   RUNNING      │                                                   │
│ 12 AUTO   RUNNING      │                                                   │
│ 13 AUTO   RUNNING      │                                                   │
│ 14 AUTO   RUNNING      │                                                   │
│ 15 AUTO   RUNNING      │                                                   │
├────────────────────────┴───────────────────────────────────────────────────┤
│  Find: ______                                                   16 trains  │
│                                                                            │
│  H Hold  R Release  B Brake  U Release EB  M Message  C Call               │
│  ↑↓ Select  0-9 Find  Tab Page  Ctrl/W Repaint  Ctrl/Z Exit                │
└────────────────────────────────────────────────────────────────────────────┘
```

`21` finds train 21, and Tab turns to its cab's page:

```
$ RUN RAME_DIR
┌────────────────────────────────────────────────────────────────────────────┐
│                  LPD PCC-CABINE V1.0  --  TRAINS AND CABS                  │
│           Ligne 21 -- NORMAL -- 08:42:27 -- trains: 16, cabs: 2            │
├────────────────────────┬───────────────────────────────────────────────────┤
│ No Kind   Cab / state  │                                                   │
│▶21 CAB    Alma         │  Cab:           Alma                              │
│                        │  Link:          LIVE (round trip 35 ms)           │
│                        │  Driving:       PA Autopilot: ENGAGED             │
│                        │  Passengers:    212/560                           │
│                        │  Timetable:     4 s EARLY                         │
│                        │  Emerg. brake:  RELEASED                          │
│                        │  Authority:     ends 1273 m ahead: train 22       │
│                        │                 ahead, its rear 1306 m away       │
│                        │  Last report:   none                              │
│                        │                                                   │
│                        │                                                   │
│                        │                                                   │
│                        │  page 2/2 -- Tab                                  │
├────────────────────────┴───────────────────────────────────────────────────┤
│  Find: 21____                                                     1 train  │
│                                                                            │
│  H Hold  R Release  B Brake  U Release EB  M Message  C Call               │
│  ↑↓ Select  0-9 Find  Tab Page  Ctrl/W Repaint  Ctrl/Z Exit                │
└────────────────────────────────────────────────────────────────────────────┘
```

`H` asks:

```
$ RUN RAME_DIR
┌────────────────────────────────────────────────────────────────────────────┐
│                  LPD PCC-CABINE V1.0  --  TRAINS AND CABS                  │
│           Ligne 21 -- NORMAL -- 08:42:27 -- trains: 16, cabs: 2            │
├────────────────────────┬───────────────────────────────────────────────────┤
│ No Kind   Cab / state  │                                                   │
│▶21 CAB    Alma         │  Train:         21 CAB                            │
│                        │  Track:         1                                 │
│                        │  Position:      668.1 m                           │
│                        │  Speed:         50.4 km/h (14.0 m/s)              │
│                        │  State:         RUNNING                           │
│                        │  Doors:         CLOSED                            │
│                        │  Station:       TO Rue des Tanneurs               │
│                        │  PCC orders:    none                              │
│                        │                                                   │
│                        │                                                   │
│                        │                                                   │
│                        │                                                   │
│                        │  page 1/2 -- Tab                                  │
├────────────────────────┴───────────────────────────────────────────────────┤
│  Hold train 21 at its next platform? (Y/N)                                 │
│                                                                            │
│  H Hold  R Release  B Brake  U Release EB  M Message  C Call               │
│  ↑↓ Select  0-9 Find  Tab Page  Ctrl/W Repaint  Ctrl/Z Exit                │
└────────────────────────────────────────────────────────────────────────────┘
```

and `Y` holds the train:

```
$ RUN RAME_DIR
┌────────────────────────────────────────────────────────────────────────────┐
│                  LPD PCC-CABINE V1.0  --  TRAINS AND CABS                  │
│           Ligne 21 -- NORMAL -- 08:42:28 -- trains: 16, cabs: 2            │
├────────────────────────┬───────────────────────────────────────────────────┤
│ No Kind   Cab / state  │                                                   │
│▶21 CAB    Alma         │  Train:         21 CAB                            │
│                        │  Track:         1                                 │
│                        │  Position:      675.2 m                           │
│                        │  Speed:         50.4 km/h (14.0 m/s)              │
│                        │  State:         HELD                              │
│                        │  Doors:         CLOSED                            │
│                        │  Station:       TO Rue des Tanneurs               │
│                        │  PCC orders:    HELD BY THE PCC                   │
│                        │                                                   │
│                        │                                                   │
│                        │                                                   │
│                        │                                                   │
│                        │  page 1/2 -- Tab                                  │
├────────────────────────┴───────────────────────────────────────────────────┤
│  Find: 21____                                                     1 train  │
│  %PCC-S-HOLD, train 21 is held at its platform, or at the next it reaches  │
│  H Hold  R Release  B Brake  U Release EB  M Message  C Call               │
│  ↑↓ Select  0-9 Find  Tab Page  Ctrl/W Repaint  Ctrl/Z Exit                │
└────────────────────────────────────────────────────────────────────────────┘
```

An order that cannot be carried out is refused on the form as at the prompt. `M` on train 05:

```
$ RUN RAME_DIR
┌────────────────────────────────────────────────────────────────────────────┐
│                  LPD PCC-CABINE V1.0  --  TRAINS AND CABS                  │
│           Ligne 21 -- NORMAL -- 08:42:28 -- trains: 16, cabs: 2            │
├────────────────────────┬───────────────────────────────────────────────────┤
│ No Kind   Cab / state  │                                                   │
│▶05 AUTO   RUNNING      │  Train:         05 AUTO                           │
│ 15 AUTO   RUNNING      │  Track:         1                                 │
│                        │  Position:      4572.1 m                          │
│                        │  Speed:         39.2 km/h (10.9 m/s)              │
│                        │  State:         RUNNING                           │
│                        │  Doors:         CLOSED                            │
│                        │  Station:       TO Passage des Lanternes          │
│                        │  PCC orders:    none                              │
│                        │                                                   │
│                        │                                                   │
│                        │                                                   │
│                        │                                                   │
│                        │                                                   │
├────────────────────────┴───────────────────────────────────────────────────┤
│  %PCC-W-REFUSED, Train 05 is not a cab: only a cab takes a message or a    │
│  call.                                                                     │
│  H Hold  R Release  B Brake  U Release EB  M Message  C Call               │
│  ↑↓ Select  0-9 Find  Tab Page  Ctrl/W Repaint  Ctrl/Z Exit                │
└────────────────────────────────────────────────────────────────────────────┘
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
$ RUN LIGNE_DIR
┌────────────────────────────────────────────────────────────────────────────┐
│                   LPD PCC-CABINE V1.0  --  LINE LIBRARY                    │
│           Ligne 21 -- NORMAL -- 08:42:30 -- trains: 16, cabs: 2            │
├────────────────────────┬───────────────────────────────────────────────────┤
│   Id     Line          │                                                   │
│   1      Ligne 1       │  Line:       Ligne 21                             │
│   4      Ligne 4       │  Id:         21                                   │
│   6      Ligne 6       │  Revision:   25030a0dde1f0c8b                     │
│   11     Ligne 11      │  Length:     7.62 km a track                      │
│   14     Ligne 14      │  Stations:   11                                   │
│▶● 21     Ligne 21      │  From:       Porte du Levant                      │
│                        │  To:         Porte du Couchant                    │
│                        │  Source:     none: built into every Cabine        │
│                        │  The PCC:    is on this line                      │
│                        │                                                   │
│                        │                                                   │
│                        │                                                   │
│                        │  page 1/3 -- Tab                                  │
├────────────────────────┴───────────────────────────────────────────────────┤
│  Find: ______                                                     6 lines  │
│                                                                            │
│  L Load the line  C Close the line  R Reread the library                   │
│  ↑↓ Select  0-9 Find  Tab Page  Ctrl/W Repaint  Ctrl/Z Exit                │
└────────────────────────────────────────────────────────────────────────────┘
```

`4` finds Ligne 4 (and Ligne 14), and Tab turns to where its data came from:

```
$ RUN LIGNE_DIR
┌────────────────────────────────────────────────────────────────────────────┐
│                   LPD PCC-CABINE V1.0  --  LINE LIBRARY                    │
│           Ligne 21 -- NORMAL -- 08:42:31 -- trains: 16, cabs: 2            │
├────────────────────────┬───────────────────────────────────────────────────┤
│   Id     Line          │                                                   │
│▶  4      Ligne 4       │  Sources of the line's data:                      │
│   14     Ligne 14      │  Track:      Île-de-France Mobilités, Tracés du   │
│                        │              réseau ferré (Licence Ouverte 2.0)   │
│                        │  Stations:   OpenStreetMap relation 123767, ©     │
│                        │              OpenStreetMap contributors (ODbL)    │
│                        │  Ground:     IGN RGE ALTI (Licence Ouverte 2.0)   │
│                        │  Extract:    2026-11-10                           │
│                        │                                                   │
│                        │                                                   │
│                        │                                                   │
│                        │                                                   │
│                        │                                                   │
│                        │  page 2/5 -- Tab                                  │
├────────────────────────┴───────────────────────────────────────────────────┤
│  Find: 4_____                                                     2 lines  │
│                                                                            │
│  L Load the line  C Close the line  R Reread the library                   │
│  ↑↓ Select  0-9 Find  Tab Page  Ctrl/W Repaint  Ctrl/Z Exit                │
└────────────────────────────────────────────────────────────────────────────┘
```

Tab again turns to its stations:

```
$ RUN LIGNE_DIR
┌────────────────────────────────────────────────────────────────────────────┐
│                   LPD PCC-CABINE V1.0  --  LINE LIBRARY                    │
│           Ligne 21 -- NORMAL -- 08:42:31 -- trains: 16, cabs: 2            │
├────────────────────────┬───────────────────────────────────────────────────┤
│   Id     Line          │                                                   │
│▶  4      Ligne 4       │   No Station                     Track 1  Track 2 │
│   14     Ligne 14      │    1 Porte de Clignancourt         279.5  13507.5 │
│                        │    2 Simplon                       731.0  13056.0 │
│                        │    3 Marcadet – Poissonniers      1067.6  12719.4 │
│                        │    4 Château Rouge                1543.2  12243.8 │
│                        │    5 Barbès – Rochechouart        1886.0  11901.0 │
│                        │    6 Gare du Nord                 2620.1  11166.9 │
│                        │    7 Gare de l'Est                3143.1  10643.9 │
│                        │    8 Château d'Eau                3511.7  10275.3 │
│                        │    9 Strasbourg – Saint-Denis     3927.8   9859.2 │
│                        │   10 Réaumur – Sébastopol         4244.5   9542.5 │
│                        │   11 Étienne Marcel               4678.5   9108.5 │
│                        │  page 3/5 -- Tab                                  │
├────────────────────────┴───────────────────────────────────────────────────┤
│  Find: 4_____                                                     2 lines  │
│                                                                            │
│  L Load the line  C Close the line  R Reread the library                   │
│  ↑↓ Select  0-9 Find  Tab Page  Ctrl/W Repaint  Ctrl/Z Exit                │
└────────────────────────────────────────────────────────────────────────────┘
```

`L` and `Y` would put the PCC on it. With cabs in service it is refused, and says why:

```
$ RUN LIGNE_DIR
┌────────────────────────────────────────────────────────────────────────────┐
│                   LPD PCC-CABINE V1.0  --  LINE LIBRARY                    │
│           Ligne 21 -- NORMAL -- 08:42:32 -- trains: 16, cabs: 2            │
├────────────────────────┬───────────────────────────────────────────────────┤
│   Id     Line          │                                                   │
│▶  4      Ligne 4       │  Line:       Ligne 4                              │
│   14     Ligne 14      │  Id:         4                                    │
│                        │  Revision:   c4f41e9d8fbc77b4                     │
│                        │  Length:     13.71 km a track                     │
│                        │  Stations:   29                                   │
│                        │  From:       Porte de Clignancourt                │
│                        │  To:         Bagneux – Lucie Aubrac               │
│                        │  Source:     in the package                       │
│                        │  The PCC:    is not on this line                  │
│                        │                                                   │
│                        │                                                   │
│                        │                                                   │
│                        │  page 1/5 -- Tab                                  │
├────────────────────────┴───────────────────────────────────────────────────┤
│  %PCC-W-REFUSED, A cab is in service on the present line: the PCC changes  │
│  line only when none is.                                                   │
│  L Load the line  C Close the line  R Reread the library                   │
│  ↑↓ Select  0-9 Find  Tab Page  Ctrl/W Repaint  Ctrl/Z Exit                │
└────────────────────────────────────────────────────────────────────────────┘
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
$ WRITE SYS$OUTPUT F$PCC("LINE_NAME")
Ligne 21
$ WRITE SYS$OUTPUT F$PCC("CABS")
1
$ WRITE SYS$OUTPUT F$PCC("FIRST_CAB")
21
$ WRITE SYS$OUTPUT F$RAME(21,"STATION")
Rue des Tanneurs
$ WRITE SYS$OUTPUT F$RAME(21,"IS_CAB")
TRUE
$ WRITE SYS$OUTPUT F$RAME(3,"KIND")
AUTO
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
$ SHOW SYMBOL PCC$MODE
  PCC$MODE = "NORMAL"
$ SHOW SYMBOL PCC$LINE
  PCC$LINE = "21"
```

### $STATUS, and what is true

`$STATUS` is the condition value the last command left, and `$SEVERITY` its severity. An expression with
no operator is true as DCL has it: an integer when it is odd, a string when it begins with T or Y. So
`IF $STATUS` is true after a success and false after a refusal, and the `TRUE` and `FALSE` of the two
functions test as themselves. A procedure of the operator's own:

```
$ TYPE ORDERS.COM
$ ! ORDERS.COM -- holds the first cab, and says what became of the order
$ N = F$PCC("FIRST_CAB")
$ IF N .EQ. 0 THEN GOTO NOCAB
$ SET RAME 'N' /HOLD
$ IF .NOT. $STATUS THEN GOTO REFUSED
$ WRITE SYS$OUTPUT "Train ''N' is held: ''F$RAME('N',"CAB")' is told at the next platform."
$ IF F$RAME('N',"AUTOMATIC") THEN WRITE SYS$OUTPUT "Its automatic driver has the train."
$ SET RAME 'N' /RELEASE
$ EXIT
$REFUSED:
$ WRITE SYS$OUTPUT "The PCC refused the order: status ''$STATUS'."
$ EXIT
$NOCAB:
$ WRITE SYS$OUTPUT "No cab is in service."
$ EXIT
$ @ORDERS
%PCC-S-HOLD, train 21 is held at its platform, or at the next it reaches
Train 21 is held: Alma is told at the next platform.
Its automatic driver has the train.
%PCC-S-RELEASE, train 21 is released
```

### The procedures in the store

The command store is seeded with five procedures the first time a node runs: `LOGIN.COM`, which every
session runs as it logs in; `STARTUP.COM`, the node's own, run with `@STARTUP`; `HELLO.COM` and
`DEMO.COM`, which are examples; and `WAITCAB.COM`, which waits for a cab to enter service, holds it at
its next platform and tells its driver why. They are the operator's to change: `EDIT WAITCAB.COM` opens
EDT on it.

```
$ TYPE WAITCAB.COM
$ ! WAITCAB.COM -- waits for a cab to enter service, then holds it at
$ ! its next platform and tells its driver why. P1 is how many seconds
$ ! to wait at most (120 when left out):  @WAITCAB 300
$ ! CTRL/Y gives up.
$ LIMIT = 120
$ IF P1 .NES. "" THEN LIMIT = 'P1'
$ COUNT = 0
$LOOP:
$   IF F$PCC("CABS") .GT. 0 THEN GOTO FOUND
$   IF COUNT .GE. LIMIT THEN GOTO NONE
$   WAIT 00:00:01
$   COUNT = COUNT + 1
$   GOTO LOOP
$FOUND:
$ N = F$PCC("FIRST_CAB")
$ IF PCC$LANGUAGE .EQS. "FR" THEN GOTO FR
$ SET RAME 'N' /HOLD /MESSAGE="Hold at the next platform: the PCC will release you"
$ EXIT
$FR:
$ SET RAME 'N' /RETENIR /MESSAGE="Retenue au prochain quai : le PCC vous liberera"
$ EXIT
$NONE:
$ IF PCC$LANGUAGE .EQS. "FR" THEN GOTO NONEFR
$ WRITE SYS$OUTPUT "No cab entered service in ''LIMIT' seconds."
$ EXIT
$NONEFR:
$ WRITE SYS$OUTPUT "Aucune cabine n'est entree en service en ''LIMIT' secondes."
$ EXIT
$ @WAITCAB 5
%PCC-S-HOLD, train 21 is held at its platform, or at the next it reaches
%PCC-S-MESSAGE, message sent to the cab of train 21
```

The procedure language is a procedure's: at the prompt a line is a command, and neither an assignment nor
an `IF`.

## In French

The same desk with the app in French. The words that are gated answer only in their own language, and
what the product prints is French; OpenVMS's own messages stay as they are.

```
$ SHOW LIGNE

  Ligne 21 (21, rév. 25030a0dde1f0c8b)
  Voie :                7617.5 m par voie, 11 stations
  De -- à :             Porte du Levant -- Porte du Couchant
  Service :             ACTIF   Mode : NORMAL   Heure de la ligne : 08:42:12
  Intervalle :          150 s   Parc : SELON L'INTERVALLE   Tour : 39 min 10 s
  Rames :               16 -- 15 automatiques (15 voulues), cabines : 1
  Matériel :            75 m, 70.0 km/h, 560 places

  SHOW LIGNE /STATIONS liste les stations, /SOURCE indique l'origine des données ; SET LIGNE donne les ordres.
$ SET RAME 21 /RETENIR /MESSAGE="ATTENDEZ LE SIGNAL DE DEPART"
%PCC-S-HOLD, la rame 21 est retenue à quai, ou au prochain quai qu'elle atteint
%PCC-S-MESSAGE, message envoyé à la cabine de la rame 21
$ SET RAME 21 /HOLD
%PCC-W-MISSQUAL, attendu : /RETENIR, /LIBERER, /FREINER, /DEFREINER, /MESSAGE= ou /APPELER -- voir HELP SET RAME
$ SHOW LINE
%DCL-W-IVKEYW, unrecognized keyword - check validity and spelling
   \LINE\
$ SET LIGNE /CHARGER=4
%PCC-W-REFUSED, Une cabine est en service sur la ligne actuelle : le PCC ne change de ligne que lorsqu'aucune ne l'est.
$ MONITOR CABINES
 LPD PCC-CABINE V1.0         MONITEUR DES CABINES                  Nœud PCCVL1
 11-NOV-2026 22:00:03   Ligne 21   Mode : NORMAL   Heure ligne : 08:42:12
┌─ Cabines (1) ───────────────────────────────────────────────────────────────┐
│ 21  Alma               ACTIVE 29 ms   PA   pilote auto ENGAGÉ               │
│     voie 1   458.0 m   50.4 km/h   RETENUE   VERS Rue des Tanneurs          │
│     [RETENUE PAR LE PCC]   portes FERMÉES   FU RELÂCHÉ   4 s D'AVANCE       │
│     autorisation se termine à 1099 m : rame 02 devant, son arrière à 1128 m │
│                                                                             │
│                                                                             │
│                                                                             │
│                                                                             │
│                                                                             │
│                                                                             │
│                                                                             │
│                                                                             │
│                                                                             │
│                                                                             │
│                                                                             │
│                                                                             │
│                                                                             │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘

 Ctrl/Z Quitter   Ctrl/W Rafraîchir   Intervalle 0,5 s        Durée 0 00:00:00
$ URGENCE

New mail on node PCCVL1 from OPCOM

New mail on node PCCVL1 from SCADA$MGR
%PCC-S-EMERGENCY, arrêt d'urgence général -- toutes les rames sont freinées
$ SHOW ALARMS

Alarmes SCADA actives à 11-NOV-2026 22:00:04.51
  Id    Heure                        Gravité    État     Source      Point          Message
  ----  ---------------------------  ---------  -------  ----------  -------------  ------------------------------
  0001  11-NOV-2026 22:00:04.50      CRITIQUE   N.ACQ    LIGNE       AU             Arrêt d'urgence général -- toutes les rames sont freinées

  ACKNOWLEDGE ALARM <id|ALL> [/CLEAR] acquitte, et efface un événement ; SHELVE/UNSHELVE gèrent les alarmes parasites.
  SHOW ALARMS/ALL liste le journal complet, historique effacé inclus.
$ REPRISE

New mail on node PCCVL1 from OPCOM
%PCC-S-EMERGENCY, arrêt d'urgence général levé
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
$ DIRECTORY

Directory PCC$ROOT:[OPERATOR]

PCC_ENGINE.EXE;12
PCC_LISTENER.EXE;4
PCC_SCADA.EXE;3
LIBRARY.DAT;6
DEMO.COM;1
HELLO.COM;1
LOGIN.COM;1
MAILBOX.JSON;1
STARTUP.COM;1
WAITCAB.COM;1

Total of 10 files.
$ SHOW LICENSE

Active licenses on PCCVL1 (VSI OpenVMS V9.2-3):

OPENVMS-X86          Active            (loaded)
DECNET-PLUS          Active            (loaded)
LPD-PCC-CABINE       Active            (loaded)
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
$ SELFTEST

SELFTEST -- driving every documented verb (LOGOUT/EXIT/CLEAR excluded)

  SHOW PROCESS                            ok              (1250 chars)
  SHOW PROCESS/ALL                        ok              (1337 chars)
  …
  HELP SHOW QUEUE                         ok              (455 chars)
  HELP SET SECURITY                       ok              (1179 chars)

  229/229 verbs returned cleanly.
```

The headless tool's `--selftest` runs it in both languages, checks that every verb it drives has its
`HELP` topic, and then does what `SELFTEST` cannot: it gives the orders for real, to an engine with
scripted cabs, and checks what each one did ([architecture.md](architecture.md#the-self-test)).
