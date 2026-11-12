# Lines

The lines are the PCC's. cabinePCC keeps a **library** of them, is on one of them or on none, and hands
the one it is on to every Cabine that does not hold it. This page is the library: what a line in it is,
the six the program is built with, where the library is read from, how a line gets into it, and where the
data of the real lines comes from, with the licences it is under.

## A line is a package

A line of the library is a file, `ligne-<id>.line.json`, and a **package** of two things
([cabine-link.md](cabine-link.md#lines-the-pccs-library) sets it out field by field):

- the **description**: the line as the PCC runs it. Its two tracks, where trains stop on each, the speed
  limits, the beacons, and the figures of its stock and of its moving block. The engine works on nothing
  else.
- the **source**: the line as a Cabine builds it. The geometry and the station data of Cabine's own line
  file: the stations and where each is, the heading of the track every few metres, the ground and rail
  levels, the stretches in the open air, the recorded speed limits, and where the data came from.

The PCC does not read the source. It keeps it and hands it on, value for value, to a cab that asks for
the line; that cab builds the line from it with the code that builds its own. The one thing cabinePCC
reads of it is `source.source`, where the data came from, because the licences ask for that to be shown.

A line is known by its `id` and its `rev` together. The `rev` is the revision of the description: sixteen
hexadecimal figures drawn from everything in it, so that two descriptions that differ anywhere differ
there. Two ends that have the same `id` and `rev` mean the same line to the metre.

## The engine runs the line on Cabine's own figures

The description carries the figures Cabine's own traffic is driven by: the stock's length, speed,
acceleration and brakes, the deceleration its automatic driver comes down to a limit or a stop with, the
margin of the moving block, how far an authority reaches, the dwell at a station. The engine in
[Engine/](../Engine/README.md) drives its trains with a port of Cabine's automatic driver and train
motion, and keeps them apart by Cabine's moving-block rules, on those figures. So the PCC's trains stop
where Cabine's would and drive as they do. It is a port, written for this engine: it is not Cabine's
source files compiled in.

## The library the program is built with

Six packages are in the repository's [`Lines/`](../Lines) folder, and go into the app (and beside the
headless tool) when it is built. Cabine wrote them: they are the six lines Cabine itself runs on.

| Id | Line | Revision | Track | Stations | From | To | Source |
|---|---|---|---:|---:|---|---|---|
| 1 | Ligne 1 | `54031a242d1d2b6a` | 16.87 km | 25 | La Défense (Grande Arche) | Château de Vincennes | Yes |
| 4 | Ligne 4 | `c4f41e9d8fbc77b4` | 13.71 km | 29 | Porte de Clignancourt | Bagneux – Lucie Aubrac | Yes |
| 6 | Ligne 6 | `8aed083cbb6a5806` | 14.11 km | 28 | Charles de Gaulle – Étoile | Nation | Yes |
| 11 | Ligne 11 | `524d18bb8a29d7b5` | 12.66 km | 19 | Châtelet | Rosny-Bois-Perrier | Yes |
| 14 | Ligne 14 | `76f90530f0c30026` | 28.25 km | 21 | Saint-Denis – Pleyel | Aéroport d'Orly | Yes |
| 21 | Ligne 21 | `25030a0dde1f0c8b` | 7.62 km | 11 | Porte du Levant | Porte du Couchant | No |

The track is the length of each of the two tracks, from buffer stop to buffer stop, tail tracks included.

**Ligne 21 is invented**: its stations and its route are made up, and it is the line Cabine began with.
Every Cabine has it built in, so its package has no source, and it has no outside data to credit. It is
the line a PCC takes up the first time it runs.

**Lignes 1, 4, 6, 11 and 14 are real lines of the Paris Métro**, the five that run on rubber tyres.
What is real of them is their stations in order, the distances between the stopping points, their
curves, the speed limits OpenStreetMap records, and their colours and numbers. Their gradients and rail
levels are an estimate, their stations are all drawn straight and level, and their signalling is
Cabine's own.

## Where the library is read from

When the PCC starts, and again whenever it is enabled or told to read the library again, it keeps every
`*.line.json` file of two folders, in this order:

1. the lines **the program was built with**: `Lines/` in the app's resources, or beside the headless
   tool;
2. **the operator's own**: `~/Library/Application Support/CabinePCC/Lines/`, or `Lines/` in the folder
   `--store` names.

Within a folder they are taken in the order a person would list them. A package kept under an `id` and
`rev` already there takes that line's place. Two revisions of one `id` are two lines, and both are kept;
an order that names the line by its id, `SET LINE /LOAD=4`, means the one kept last, which is the
operator's own when the program came with another.

**A file that is not a good package is skipped**, and the operator is told twice: the journal has a line
for it with the reason, and the alarm `PCC FICHIER` stands until it is acknowledged and cleared.

```
$ SHOW JOURNAL /LAST=8

  Journal -- lines shown: 7 of 7
    --:--:--  Line file ligne-9.line.json refused: description.stations is missing
    --:--:--  Line file notes.line.json refused: it is not a line package
    --:--:--  Library read: 6 lines held
    08:42:00  Line taken up: Ligne 21 (21, rev 25030a0dde1f0c8b), 16 automatic trains
    08:42:00  Cab Alma connected, holding Ligne 21 (21, rev 25030a0dde1f0c8b)
    08:42:00  Cab Alma is on the line
    08:42:00  Cab Alma in service as train 21, track 1 at 279.5 m, in place of 01
```

The PCC checks a description before it keeps it: the counts and the order of its stations and stops,
that each track has room at both ends to turn a train, that its limits and its figures are possible. A
package must also fit one line of the wire, 1 MiB. The reason for a refusal is the engine's, and is in
English in both languages.

`SET LINE /REREAD`, the `R` key of `RUN LIGNE_DIR` and the REREAD button of the Dispatcher read the two
folders again without closing the PCC, so a file put in the folder is in the library at once.

## Which line the PCC is on

The PCC is on one line of its library at a time, or on none. Its operator chooses: `SET LINE /LOAD=id`,
the `L` key of `RUN LIGNE_DIR`, or the line's button in the Dispatcher. The id of the line is a setting,
so the next launch takes the same line up. The first launch takes up Ligne 21.

- **The PCC changes line only while no cab is in service** on the one it is on, and says so when it
  refuses. A train still held for a cab that has fallen silent counts as in service until it is handed
  back to automation.
- When it changes, it withdraws its automatic trains and seeds them afresh on the new line, starts the
  line's clock again at 08:42:00, clears a general emergency stop, puts the line in service, and tells
  every cab. A cab that holds the new line is on it at once; each of the others asks for it and is sent
  the package.
- `SET LINE /CLOSE` puts the PCC on no line: its trains are withdrawn and its cabs wait.
- **If the line last run is no longer in the library** when the PCC starts, it is on no line, the journal
  says so, and the alarm `PCC LIGNE` stands until the operator has seen it.

`SHOW LINES` lists the library, `SHOW LINE` shows the line the PCC is on, and `RUN LIGNE_DIR` browses
the library on a form ([dcl.md](dcl.md#the-library-and-the-line)).

## How a line gets into the library

Cabine makes the packages, with its command-line tool:

```sh
Cabine --lines --export <directory>
```

writes the package of each of Cabine's lines to `<directory>/ligne-<id>.line.json`: the description
Cabine works out of the line, and the line's data file as its source. The six packages of `Lines/` were
written so. With `--source <file>` it writes the package of a line that is not one of Cabine's own, from
any data file in the form of Cabine's.

To give a PCC a line:

1. Put the `.line.json` file in `~/Library/Application Support/CabinePCC/Lines/` (the folder is made the
   first time the PCC starts).
2. `SET LINE /REREAD`, or start the PCC again. `SHOW LINES` then lists it.
3. `SET LINE /LOAD=id` puts the PCC on it, once no cab is in service.

To build a line into the program, put the file in the repository's `Lines/` folder and build: every
`.line.json` in that folder goes into the app. Say where its data came from in
[`Lines/README.md`](../Lines/README.md) if it is not Cabine's own.

**The description and the source go together.** A Cabine that is sent a package builds the line from the
source and works the description out for itself; only if what it works out has the package's `rev` is it
on the PCC's line. So a package is made by the version of Cabine that will run on it. A cab whose own
working out gives another `rev` stays connected and cannot come on the line: the PCC shows it as
`CONNECTED, NOT ON THE PCC'S LINE` and raises the alarm `CABINE #n REVISION` while it is there.

## Sources and licences

The packages of lignes 1, 4, 6, 11 and 14 hold the stations of those lines, their geometry and their
distances, which come from open data. The data is kept here and handed on from here, so what its
licences ask goes with it. This table is Cabine's own:

| What | Source | Licence |
| --- | --- | --- |
| Stations in order, the point where trains stop at each, distances, tunnel and bridge tags, speed limits | [OpenStreetMap](https://www.openstreetmap.org/copyright): one direction's route relation for each line | © OpenStreetMap contributors, ODbL 1.0 |
| The track's curves on lignes 1 and 6 | OpenStreetMap, the same relation | ODbL 1.0 |
| The track's curves on lignes 4, 11 and 14 | Île-de-France Mobilités, [Tracés du réseau de transport ferré d'Île-de-France](https://data.iledefrance-mobilites.fr/explore/dataset/traces-du-reseau-ferre-idf/) | Licence Ouverte 2.0 (Etalab) |
| Ground level | IGN, RGE ALTI, through the Géoplateforme's altimetry service | Licence Ouverte 2.0 |

Each package names its sources and the date of the OpenStreetMap extract in `source.source`:

| Line | Track | Stations | Ground | Extract |
|---|---|---|---|---|
| 1 | OpenStreetMap relation 3328692, © OpenStreetMap contributors (ODbL) | OpenStreetMap relation 3328692, © OpenStreetMap contributors (ODbL) | IGN RGE ALTI (Licence Ouverte 2.0) | 2026-11-10 |
| 4 | Île-de-France Mobilités, Tracés du réseau ferré (Licence Ouverte 2.0) | OpenStreetMap relation 123767, © OpenStreetMap contributors (ODbL) | IGN RGE ALTI (Licence Ouverte 2.0) | 2026-11-10 |
| 6 | OpenStreetMap relation 123912, © OpenStreetMap contributors (ODbL) | OpenStreetMap relation 123912, © OpenStreetMap contributors (ODbL) | IGN RGE ALTI (Licence Ouverte 2.0) | 2026-11-10 |
| 11 | Île-de-France Mobilités, Tracés du réseau ferré (Licence Ouverte 2.0) | OpenStreetMap relation 123792, © OpenStreetMap contributors (ODbL) | IGN RGE ALTI (Licence Ouverte 2.0) | 2026-11-10 |
| 14 | Île-de-France Mobilités, Tracés du réseau ferré (Licence Ouverte 2.0) | OpenStreetMap relation 123737, © OpenStreetMap contributors (ODbL) | IGN RGE ALTI (Licence Ouverte 2.0) | 2026-11-10 |
| 21 | An invented line: no outside data | | | |

OpenStreetMap's data is under the ODbL: whatever shows it must say "© OpenStreetMap contributors", and
the files derived from it stay under that licence. Île-de-France Mobilités and the IGN publish under the
Licence Ouverte 2.0, which asks for the source and the date.

**Where the credits are shown.** cabinePCC shows each line's credits as its package gives them, where an
operator can read them: in the PCC Dispatcher, under each line of the library and in the credits it
opens from its foot; at the prompt, with `SHOW LINE /SOURCE`; and on the second page of a line's record
in `RUN LIGNE_DIR`. They are beside the files too, in [`Lines/README.md`](../Lines/README.md).

Nothing comes from another simulator, and nothing of the RATP's is used but the names and numbers of its
lines and stations: no logo, no typeface, no recorded announcement. (A package also carries the colour
of its line's roundel, as Cabine's data does. cabinePCC keeps it and hands it on, and does not draw it.)

The RATP has not approved cabinePCC, and nothing in the program or in these pages says or suggests that
it has.
