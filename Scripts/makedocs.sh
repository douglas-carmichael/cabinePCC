#!/bin/sh
# Makes docs/dcl.md.
#
#     Scripts/makedocs.sh [path to cabinepcc-headless]
#
# docs/dcl.md is not written by hand. Its words are in Scripts/dcl.template.md, and every sample in it
# is what the program printed: this script runs the headless tool once for each of the page's
# scenarios, a fresh node each time, and Scripts/filldocs.py puts what the tool printed where the
# template asks for it. To change the page, change the template, or a scenario here, and run this
# again. A command the template quotes and no scenario runs stops the build.
#
# The tool is the cabinepcc-headless the project builds. Without an argument it is looked for where
# the README's build commands put it when they are given -derivedDataPath build. The scenarios take
# about two minutes, most of it the line being left to run before the first command.
#
# Nothing is written but the page. The nodes keep their settings in memory and their files in a
# scratch folder that is removed at the end, and listen on loopback ports the system chooses. Each is
# named PCCVL1 and its operator OPERATOR, so that the page shows neither this Mac's name nor its
# user's. The cabs are the tool's scripted ones. The times, the ports and the cabs' figures are those
# of the run, so they change from one run to the next.

set -eu

here=$(cd "$(dirname "$0")" && pwd)
repo=$(dirname "$here")
tool=${1:-"$repo/build/Build/Products/Debug/cabinepcc-headless"}
if [ ! -x "$tool" ]; then
    echo "makedocs: no cabinepcc-headless at $tool" >&2
    echo "makedocs: build that scheme, or give the tool's path" >&2
    exit 1
fi

work=$(mktemp -d "${TMPDIR:-/tmp}/cabinepcc-docs.XXXXXX")
trap 'rm -rf "$work"' EXIT
trap 'exit 1' INT TERM
samples="$work/samples"
store="$work/store"
mkdir -p "$samples" "$work/home"

# run <name> <the tool's options>: one scenario, on a node of its own. What the tool prints is kept as
# <name>.txt, which is the name the template's {{name|command}} asks for.
run() {
    name=$1
    shift
    echo "makedocs: $name" >&2
    if ! CFFIXED_USER_HOME="$work/home" "$tool" --store "$store" --node PCCVL1 --user OPERATOR \
        --name "PCC LIGNE 21" "$@" > "$samples/$name.txt" 2>&1; then
        echo "makedocs: the tool failed on $name; it last printed:" >&2
        tail -5 "$samples/$name.txt" >&2
        exit 1
    fi
    rm -rf "$store"
}

# A cab in service on Ligne 21: the PCC, the line, the trains, the cab and its orders, the line's
# orders, the journal, the lexical functions and a command procedure. ORDERS.COM is the procedure the
# page shows: it is put in the node's command store before the node starts.
mkdir -p "$store/COM"
cat > "$store/COM/ORDERS.COM" <<'COM'
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
COM
run en-cab --cabs 1 --settle 20 \
    --dcl "SHOW PCC" --dcl "SHOW LINES" --dcl "SHOW LINE" --dcl "SHOW LINE /STATIONS" --dcl "SHOW RAMES" \
    --dcl "SHOW RAME 21" --dcl "SHOW RAME 3" --dcl "SHOW CABS" --dcl "SHOW CONNECTIONS" \
    --dcl 'SET RAME 21 /HOLD /MESSAGE="WAIT FOR THE DEPARTURE SIGNAL"' --dcl "SHOW CABS" \
    --dcl "SET RAME 21 /RELEASE" --dcl 'SET RAME 3 /MESSAGE="HELLO"' --dcl "SET RAME 77 /HOLD" \
    --dcl "SET RAME 21" --dcl "SET RAME 21 /CALL" --dcl "SET RAME 21 /BRAKE" --dcl "SHOW ALARMS" \
    --dcl "SET RAME 21 /UNBRAKE" --dcl "STOP RAME 5" --dcl "WAIT 00:00:01" --dcl "SHOW RAME 5" \
    --dcl "START RAME 5" --dcl "SET LINE /LOAD=4" --dcl "SET LINE /HEADWAY=120" \
    --dcl "SET LINE /HEADWAY=5" --dcl "SET LINE /RAMES=12" --dcl "SET LINE /RAMES=AUTO" \
    --dcl "SET LINE /SERVICE=MAYBE" --dcl "STOP LINE" --dcl "SHOW LINE" --dcl "START LINE" \
    --dcl "EMERGENCY" --dcl "SHOW STATUS" --dcl "SHOW ALARMS" --dcl "RESUME" --dcl "SHOW JOURNAL" \
    --dcl "SHOW JOURNAL /LAST=3" --dcl "SHOW ALARMS/ALL" --dcl "ACKNOWLEDGE ALARM ALL /CLEAR" \
    --dcl 'WRITE SYS$OUTPUT F$PCC("LINE_NAME")' --dcl 'WRITE SYS$OUTPUT F$PCC("CABS")' \
    --dcl 'WRITE SYS$OUTPUT F$PCC("FIRST_CAB")' --dcl 'WRITE SYS$OUTPUT F$RAME(21,"STATION")' \
    --dcl 'WRITE SYS$OUTPUT F$RAME(21,"IS_CAB")' --dcl 'WRITE SYS$OUTPUT F$RAME(3,"KIND")' \
    --dcl 'SHOW SYMBOL PCC$MODE' --dcl 'SHOW SYMBOL PCC$LINE' --dcl "SET RAME 77 /HOLD" \
    --dcl 'SHOW SYMBOL $STATUS' --dcl "SHOW LINES" --dcl 'SHOW SYMBOL $STATUS' --dcl "@WAITCAB 5" \
    --dcl "SHOW RAME 21" --dcl "SET RAME 21 /RELEASE" --dcl "@ORDERS" --dcl "TYPE ORDERS.COM"

# No cab: the library, changing line, closing it, and the PCC's own settings.
run en-library --settle 2 \
    --dcl "SET LINE /LOAD=4" --dcl "SHOW LINE" --dcl "SHOW LINE /SOURCE" --dcl "SHOW LINE /STATIONS" \
    --dcl "SHOW JOURNAL /LAST=4" --dcl "SET LINE /LOAD=99" --dcl "SET LINE /CLOSE" --dcl "SHOW LINE" \
    --dcl "SHOW PCC" --dcl "SHOW RAMES" --dcl "SHOW JOURNAL /LAST=2" --dcl "SET LINE /REREAD" \
    --dcl "SET LINE /LOAD=21" --dcl "SHOW LINE /SOURCE" --dcl "SET LINE" \
    --dcl 'SET PCC /NAME="PCC NORD"' --dcl "SET PCC /DISABLE" --dcl "SHOW PCC" --dcl "SET PCC /ENABLE" \
    --dcl "WAIT 00:00:02" --dcl "SHOW PCC" --dcl "SET PCC /LAN=OFF" --dcl "SET PCC" \
    --dcl 'SHOW LOGICAL PCC$LINES' --dcl "DIRECTORY" --dcl "SHOW LICENSE" --dcl "HELP PCC Alarms"

# Two cabs: a frame of each monitor and of each form, with the keys an operator would press.
run en-screens --cabs 2 --settle 25 \
    --dcl "MONITOR LINE" --dcl "MONITOR CABS" --dcl "MONITOR RAMES" --dcl "MONITOR CONNECTIONS" \
    --dcl "RUN RAME_DIR" --dcl "RUN RAME_DIR" --keys "21<TAB>" --dcl "RUN RAME_DIR" --keys "21H" \
    --dcl "RUN RAME_DIR" --keys "21HY" --dcl "RUN RAME_DIR" --keys "5M" --dcl "SET RAME 22 /BRAKE" \
    --dcl "WAIT 00:00:01" --dcl "MONITOR LINE" --dcl "MONITOR CABS" --dcl "SET RAME 22 /UNBRAKE" \
    --dcl "SET RAME 21 /RELEASE" --dcl "RUN LIGNE_DIR" --dcl "RUN LIGNE_DIR" --keys "4<TAB>" \
    --dcl "RUN LIGNE_DIR" --keys "4<TAB><TAB>" --dcl "RUN LIGNE_DIR" --keys "4LY" --dcl "MONITOR SYSTEM" \
    --dcl "MONITOR PROCESSES" --dcl "SHOW SYSTEM" --dcl "TYPE WAITCAB.COM"

# The same desk in French.
run fr --lang fr --cabs 1 --settle 12 \
    --dcl "SHOW PCC" --dcl "SHOW LIGNES" --dcl "SHOW LIGNE" --dcl "SHOW RAMES" --dcl "SHOW CABINES" \
    --dcl 'SET RAME 21 /RETENIR /MESSAGE="ATTENDEZ LE SIGNAL DE DEPART"' --dcl "SET RAME 21 /HOLD" \
    --dcl "SHOW LINE" --dcl "SET LIGNE /CHARGER=4" --dcl "MONITOR LIGNE" --dcl "MONITOR CABINES" \
    --dcl "RUN RAME_DIR" --keys "21LO" --dcl "URGENCE" --dcl "SHOW ALARMS" --dcl "REPRISE" \
    --dcl "SHOW JOURNAL /LAST=4" --dcl "SHOW CONNECTIONS"

# The alarms. Two files that are not line packages are put in the operator's own Lines folder, so
# that the library refuses them when it is read and the alarm for it is raised.
mkdir -p "$store/Lines"
printf '{"format":1,"description":{"id":"9","name":"Ligne 9","rev":"0000000000000009","lengthM":4000}}\n' \
    > "$store/Lines/ligne-9.line.json"
printf 'a note to self, not a line\n' > "$store/Lines/notes.line.json"
run en-alarms --cabs 1 --settle 3 \
    --dcl "SHOW JOURNAL /LAST=8" --dcl "SHOW ALARMS" --dcl "EMERGENCY" --dcl "ACKNOWLEDGE ALARM ALL" \
    --dcl "SHOW ALARMS" --dcl "ACKNOWLEDGE ALARM 2 /CLEAR" --dcl "ACKNOWLEDGE ALARM 1 /CLEAR" \
    --dcl "RESUME" --dcl "SHOW ALARMS/ALL" --dcl "SET RAME 21 /BRAKE" --dcl "SHELVE ALARM 3" \
    --dcl "SHOW ALARMS" --dcl "UNSHELVE ALARM 3" --dcl "SHOW ALARMS" --dcl "SET RAME 21 /UNBRAKE" \
    --dcl "ACKNOWLEDGE ALARM 9"

# The shell's own check of its verbs.
run selftest-en \
    --dcl "SELFTEST"

python3 "$here/filldocs.py" "$here/dcl.template.md" "$samples" "$repo/docs/dcl.md" "$here/makedocs.sh"
