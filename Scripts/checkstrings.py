#!/usr/bin/env python3
"""Checks the string table against the sources:

    python3 Scripts/checkstrings.py

Every key the sources use is in the table; every key in the table is used; both languages of a key take
the same arguments; the families of keys that are built at run time from a word of the wire are whole;
every alarm message is listed in Strings.alarmMessageKeys; and the labels of a form's record are of one
width, so that its values stand in a column. Exit status 0 when there is nothing to say, 1 otherwise.
"""
import glob
import os
import re
import sys

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
SOURCES = os.path.join(ROOT, "Sources")
TABLE = os.path.join(SOURCES, "CabinePCC", "Core", "Localization")

# What a key begins with, and the names of the settings, which look like keys and are not.
PREFIX = r"(?:pcc|dcl|alarm|login|help|banner|theme|credits|window|hint|status|launch|menu)"
SETTINGS = {"pcc.enabled", "pcc.lan", "pcc.headway", "pcc.name", "pcc.line"}

# Keys made at run time: a stem, and the words of the wire or of the engine that complete it.
FAMILIES = {
    "pcc.mode.": ["normal", "stopped", "emergency"],
    "pcc.kind.": ["auto", "cab"],
    "pcc.phase.": ["running", "dwelling", "departing", "held", "emergency", "tail"],
    "pcc.doorphase.": ["closed", "opening", "open", "warning", "closing"],
    "pcc.command.": ["emergencybrake", "hold", "message", "call"],
    "pcc.link.": ["live", "silent"],
    "pcc.standing.": ["opened", "connected", "online", "inservice"],
    "pcc.standing.short.": ["opened", "connected", "online", "inservice"],
    "pcc.report.": ["radiocheck", "readytodepart", "stoppedatsignal", "passengerill", "technicalfault",
                    "incidentover", "requestcall"],
    "pcc.side.": ["right", "left"],
    "pcc.reason.": ["horizon", "end", "hold", "service", "emergency"],
    "pcc.reason.short.": ["train", "horizon", "end", "hold", "service", "emergency"],
    "pcc.leave.": ["finished", "ended", "quit", "left"],
}
OTHERS = {"pcc.mon.lbl.cabs.part", "pcc.mon.lbl.rames.part", "pcc.mon.lbl.connections.part"}

# The labels of each page of a form's record.
RECORDS = [
    ["train", "track", "position", "speed", "state", "doors", "station", "orders", "cab", "link", "driving",
     "pax", "timetable", "eb", "authority", "report"],
    ["line", "id", "rev", "length", "stations", "from", "to", "source", "running"],
    ["c.track", "c.stations", "c.ground", "c.date"],
]


def read(path):
    with open(path, encoding="utf-8") as file:
        return file.read()


def table():
    entry = re.compile(r'add\("([^"]+)",\s*("(?:[^"\\]|\\.)*")\s*,\s*("(?:[^"\\]|\\.)*")\s*\)', re.S)
    found, twice = {}, []
    for path in glob.glob(os.path.join(TABLE, "Strings*.swift")):
        for match in entry.finditer(read(path)):
            if match.group(1) in found:
                twice.append(match.group(1))
            found[match.group(1)] = (match.group(2)[1:-1], match.group(3)[1:-1])
    return found, twice


def used():
    keys = set()
    for path in glob.glob(os.path.join(SOURCES, "**", "*.swift"), recursive=True):
        if os.sep + "Localization" + os.sep + "Strings" in path:
            continue
        for match in re.finditer(r'"(' + PREFIX + r'\.[A-Za-z0-9_.]*?)(\\\(|")', read(path)):
            key = match.group(1)
            if match.group(2) == '"' and key not in SETTINGS and not key.endswith("."):
                keys.add(key)
    return keys


def main():
    strings, twice = table()
    keys = used()
    family = {stem + word for stem, words in FAMILIES.items() for word in words} | OTHERS
    said = []

    for key in twice:
        said.append("defined twice: " + key)
    for key in sorted(keys - set(strings)):
        said.append("used, and not in the table: " + key)
    for key in sorted(family - set(strings)):
        said.append("made at run time, and not in the table: " + key)

    listed = set(re.findall(r'"(alarm\.msg\.[a-z.]+)"', read(os.path.join(TABLE, "Strings.swift"))))
    for key in sorted(strings):
        if key.startswith("alarm.msg."):
            if key not in listed:
                said.append("an alarm message that Strings.alarmMessageKeys does not list: " + key)
        elif key not in keys and key not in family:
            said.append("in the table, and not used: " + key)
    for key in sorted(listed - set(strings)):
        said.append("listed in Strings.alarmMessageKeys, and not in the table: " + key)

    argument = re.compile(r"%(?:%|[-+ 0#]*\d*(?:\.\d+)?(?:ll|l)?[@dfsuxX])")
    for key, (english, french) in sorted(strings.items()):
        one = [found for found in argument.findall(english) if found != "%%"]
        other = [found for found in argument.findall(french) if found != "%%"]
        if one != other:
            said.append("the two languages take different arguments: %s %s %s" % (key, one, other))
        if not english.strip() or not french.strip():
            said.append("empty: " + key)

    for record in RECORDS:
        for language, name in enumerate(("English", "French")):
            widths = {len(strings["pcc.form.f." + label][language]) for label in record
                      if "pcc.form.f." + label in strings}
            if len(widths) > 1:
                said.append("labels of unequal width in %s: pcc.form.f.%s… %s" % (name, record[0], sorted(widths)))

    for line in said:
        print(line)
    print("%d keys in the table, %d named in the sources, %d to see to" % (len(strings), len(keys), len(said)))
    return 1 if said else 0


if __name__ == "__main__":
    sys.exit(main())
