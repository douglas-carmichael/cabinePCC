# The lines cabinePCC is built with

Six line packages, one to a file: `ligne-<id>.line.json`. Every `.line.json` in this folder goes into the
app, and beside the headless tool, when they are built, and is kept in the PCC's library when it starts.
[docs/lines.md](../docs/lines.md) says what a package is, how the library is read, and how a line gets
into it; [docs/cabine-link.md](../docs/cabine-link.md#lines-the-pccs-library) has the package field by
field.

| File | Line | Revision | Track | Stations | From | To |
|---|---|---|---:|---:|---|---|
| `ligne-1.line.json` | Ligne 1 | `54031a242d1d2b6a` | 16.87 km | 25 | La Défense (Grande Arche) | Château de Vincennes |
| `ligne-4.line.json` | Ligne 4 | `c4f41e9d8fbc77b4` | 13.71 km | 29 | Porte de Clignancourt | Bagneux – Lucie Aubrac |
| `ligne-6.line.json` | Ligne 6 | `8aed083cbb6a5806` | 14.11 km | 28 | Charles de Gaulle – Étoile | Nation |
| `ligne-11.line.json` | Ligne 11 | `524d18bb8a29d7b5` | 12.66 km | 19 | Châtelet | Rosny-Bois-Perrier |
| `ligne-14.line.json` | Ligne 14 | `76f90530f0c30026` | 28.25 km | 21 | Saint-Denis – Pleyel | Aéroport d'Orly |
| `ligne-21.line.json` | Ligne 21 | `25030a0dde1f0c8b` | 7.62 km | 11 | Porte du Levant | Porte du Couchant |

Cabine wrote them, with `Cabine --lines --export <directory>`: each is the description Cabine works out
of one of its own lines and, for the real lines, that line's data file as its source. They are not
edited by hand: a package whose description does not match its source is another line to a Cabine, and
is refused there.

## Where the data comes from

Ligne 21 is invented. It has no source in its package and no outside data to credit.

Lignes 1, 4, 6, 11 and 14 are real lines of the Paris Métro. Their packages hold their stations, their
geometry and their distances, which come from open data, under these licences:

| What | Source | Licence |
| --- | --- | --- |
| Stations in order, the point where trains stop at each, distances, tunnel and bridge tags, speed limits | [OpenStreetMap](https://www.openstreetmap.org/copyright): one direction's route relation for each line | © OpenStreetMap contributors, ODbL 1.0 |
| The track's curves on lignes 1 and 6 | OpenStreetMap, the same relation | ODbL 1.0 |
| The track's curves on lignes 4, 11 and 14 | Île-de-France Mobilités, [Tracés du réseau de transport ferré d'Île-de-France](https://data.iledefrance-mobilites.fr/explore/dataset/traces-du-reseau-ferre-idf/) | Licence Ouverte 2.0 (Etalab) |
| Ground level | IGN, RGE ALTI, through the Géoplateforme's altimetry service | Licence Ouverte 2.0 |

Each file names its own sources and the date of the OpenStreetMap extract, in `source.source`:

| File | Track | Stations | Ground | Extract |
|---|---|---|---|---|
| `ligne-1.line.json` | OpenStreetMap relation 3328692, © OpenStreetMap contributors (ODbL) | OpenStreetMap relation 3328692, © OpenStreetMap contributors (ODbL) | IGN RGE ALTI (Licence Ouverte 2.0) | 2026-11-10 |
| `ligne-4.line.json` | Île-de-France Mobilités, Tracés du réseau ferré (Licence Ouverte 2.0) | OpenStreetMap relation 123767, © OpenStreetMap contributors (ODbL) | IGN RGE ALTI (Licence Ouverte 2.0) | 2026-11-10 |
| `ligne-6.line.json` | OpenStreetMap relation 123912, © OpenStreetMap contributors (ODbL) | OpenStreetMap relation 123912, © OpenStreetMap contributors (ODbL) | IGN RGE ALTI (Licence Ouverte 2.0) | 2026-11-10 |
| `ligne-11.line.json` | Île-de-France Mobilités, Tracés du réseau ferré (Licence Ouverte 2.0) | OpenStreetMap relation 123792, © OpenStreetMap contributors (ODbL) | IGN RGE ALTI (Licence Ouverte 2.0) | 2026-11-10 |
| `ligne-14.line.json` | Île-de-France Mobilités, Tracés du réseau ferré (Licence Ouverte 2.0) | OpenStreetMap relation 123737, © OpenStreetMap contributors (ODbL) | IGN RGE ALTI (Licence Ouverte 2.0) | 2026-11-10 |

The files derived from OpenStreetMap's data stay under the ODbL, and whatever shows that data says
"© OpenStreetMap contributors". The Licence Ouverte 2.0 asks for the source and the date. cabinePCC shows
both to its operator, for each line: in the PCC Dispatcher, with `SHOW LINE /SOURCE`, and in
`RUN LIGNE_DIR`.

Nothing comes from another simulator, and nothing of the RATP's is used but the names and numbers of its
lines and stations: no logo, no typeface, no recorded announcement. The RATP has not approved cabinePCC,
and nothing here says or suggests that it has.

## A line of your own

A line that is not one of these goes in the operator's folder, not here:
`~/Library/Application Support/CabinePCC/Lines/`. Put a line in this folder only to build it into the
program, and then say in this page where its data came from and under what licence.
