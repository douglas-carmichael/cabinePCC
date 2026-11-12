import Foundation

// The PCC node's HELP library source, in OpenVMS `.HLP`
// format (see DCLHelpLibrary.swift for the reader). Written in the
// DEC/VSI documentation voice: a one-line gloss, a Format: section, then
// parameter / qualifier / example subtopics where a command has them.
//
// Substitution tokens resolved at parse time:
//   $OSTITLE$    e.g. "VSI OpenVMS"
//   $OSVERSION$  e.g. "V9.2-3"
//   $NODE$       this node's DECnet-style name
//   $USER$       the logged-in user name
//   $STOREROOT$  host path backing PCC$ROOT: (the command store)
//   $LINESROOT$  host path of the operator's own lines

extension HelpLibrary {
    static let source = """
1 @
  Executes a command procedure. The at sign (@) is the execute-procedure
  command; DCL reads command lines from the named file as though you had
  typed them at the terminal.

  Format:

    @file-spec[.COM] [parameter[ ...]]

  Up to eight parameters may follow the file specification. Inside the
  procedure they are available as the local symbols P1 through P8. The
  default file type is COM.

  Procedures are read from this node's command-procedure store; use EDIT
  to author one and DIRECTORY to list those already present. See also
  HELP SCRIPTING and HELP TUTORIAL.

  Example:

    $ @STARTUP
    $ @GREET MARK

2 Examples
  The procedure is located in the PCC$ROOT: command store. The .COM
  file type need not be typed:

    $ @HELLO
    $ @WAITCAB 300

1 ACCOUNTING
  Displays a per-user summary of the resources consumed on this node
  since the system was booted. The PCC node keeps a lightweight
  accounting log in place of the SYS$MANAGER:ACCOUNTNG.DAT file used on a
  full VMS system.

  Format:

    ACCOUNTING

1 ACKNOWLEDGE
  Marks one active SCADA alarm, or every active alarm, as seen by the
  operator. Acknowledging an alarm records the operator response in the
  alarm history without clearing the underlying condition. A
  process-driven alarm (a silent cab, an emergency brake, the general
  emergency stop) returns to normal only when its cause is removed; an
  event (a driver's report or call, a line file that was refused) stands
  until it is cleared, with /CLEAR here or at the PCC Dispatcher's panel.

  Format:

    ACKNOWLEDGE ALARM {alarm-id | ALL} [/CLEAR]

  The complete alarm history, with acknowledgement state, is shown by
  SHOW ALARMS/ALL.

2 Parameters
  alarm-id

    The sequence number of a single active alarm, as listed by
    SHOW ALARMS.

  ALL

    Acknowledges every alarm currently active.

2 /CLEAR
  Clears the alarm as well as acknowledging it. With ALL, every
  acknowledged event is cleared. A process-driven alarm is not the
  operator's to clear: the command says so, and leaves it standing.

    $ ACKNOWLEDGE ALARM 12 /CLEAR
    $ ACKNOWLEDGE ALARM ALL /CLEAR

1 ALLOCATE
  Reserves a device for the exclusive use of your process. A user-class
  device (a scratch disk, a tape drive, or a terminal line) may be
  allocated; system volumes are refused.

  Format:

    ALLOCATE device-name[:]

  The allocation is held until you DEALLOCATE the device or log out.

1 ANALYZE
  Examines the internal structure of a file, an error log, the security
  audit journal, or a system dump. The operator account may inspect the
  error log and audit characteristics; image and crash-dump analysis are
  privileged.

  Format:

    ANALYZE/qualifier [file-spec]

  Additional information available:

  Choose a qualifier subtopic below for details.

2 /ERROR_LOG
  Reports the most recent entries from the system error log, in the
  format produced by ANALYZE/ERROR_LOG on a full VMS system: device
  errors, machine checks, and volume state changes.

  Format:

    ANALYZE/ERROR_LOG

2 /AUDIT
  Displays the security auditing characteristics currently in effect --
  the classes of event (login, breakin, file access, privilege use)
  being written to the audit journal.

  Format:

    ANALYZE/AUDIT

2 /IMAGE
  Analyzes the structure of an executable image. This function is
  privileged and returns %SYSTEM-F-NOPRIV for the operator account.

  Format:

    ANALYZE/IMAGE image-name

2 /CRASH_DUMP
  Reads and formats SYS$SYSTEM:SYSDUMP.DMP. This function is privileged
  and returns %SYSTEM-F-NOPRIV for the operator account.

  Format:

    ANALYZE/CRASH_DUMP dump-file

1 APPEND
  Adds the contents of one or more files to the end of an existing file.
  APPEND is COPY with the records concatenated onto the output file
  rather than replacing it.

  Format:

    APPEND input-file-spec[,...] output-file-spec

1 ASSIGN
  Creates a logical name and equates it to an equivalence string in the
  process logical name table. ASSIGN takes the equivalence name first;
  DEFINE takes the logical name first.

  Format:

    ASSIGN equivalence-name logical-name

  Use SHOW LOGICAL to display the resulting table entry and DEASSIGN to
  remove it.

1 ATTACH
  Transfers control of your terminal from the current process to another
  process in your job. This shell has no parent process, so
  ATTACH returns -DCL-W-ATTNOPAR.

  Format:

    ATTACH process-name

1 BACKUP
  Saves, restores, or copies files as a BACKUP save set. The command
  prints the standard BACKUP identification banner and the
  CREATED/COPIED messages.

  Format:

    BACKUP input-specifier output-specifier

  Example:

    $ BACKUP PCC$LINES: MUA0:LINES.BCK

1 START
  Starts line service, or releases the emergency brake the PCC has
  ordered on one train.

  Format:

    START LINE
    START RAME number

  Additional information available:

  Choose a form below for details.

2 LINE
  Line service on: the automatic trains run again and every cab has its
  movement authority. The same as SET LINE /SERVICE=ON. In French mode
  the object is LIGNE.

    START LINE

2 RAME
  Releases the emergency brake ordered on a train with STOP RAME or
  SET RAME /BRAKE. The same as SET RAME number /UNBRAKE. A cab stays
  braked while the general emergency stop is on.

    START RAME number

  Example:

    $ START RAME 21

1 CLEAR
  Clears the terminal screen and the scrollback buffer, then redisplays
  the DCL prompt.

  Format:

    CLEAR

1 CONTINUE
  Resumes execution of a command or image that was interrupted by
  CTRL/Y. With nothing interrupted, CONTINUE has no effect.

  Format:

    CONTINUE

1 COPY
  Creates a new file from one or more existing files. In this shell the
  file namespace outside the command-procedure store is read-only, so a
  COPY whose input lies there returns %COPY-E-OPENIN and -RMS-E-FNF.

  Format:

    COPY input-file-spec[,...] output-file-spec

1 CREATE
  Creates a new sequential file. A file created with a .COM type is
  written to the command-procedure store, where EDIT and @ can find it
  later.

  Format:

    CREATE file-spec

1 DEALLOCATE
  Releases a device you previously reserved with ALLOCATE, returning it
  to the pool of free devices.

  Format:

    DEALLOCATE {device-name[:] | /ALL}

  DEALLOCATE/ALL releases every device your process holds.

1 DEASSIGN
  Cancels a logical name assignment made with ASSIGN or DEFINE. An
  undefined name returns %SYSTEM-F-NOLOGNAM.

  Format:

    DEASSIGN logical-name

1 DEFINE
  Creates a logical name and equates it to an equivalence string. DEFINE
  takes the logical name first; ASSIGN takes the equivalence name first.
  The two commands are otherwise identical.

  Format:

    DEFINE logical-name equivalence-name

1 DELETE
  Deletes one or more files. A user-authored .COM file is removed from
  the command-procedure store; a file elsewhere in the read-only
  namespace returns -RMS-E-FNF.

  Format:

    DELETE file-spec[;version]

1 DEPOSIT
  Replaces the contents of memory locations. This command is privileged
  and returns %SYSTEM-F-NOPRIV for the operator account. See EXAMINE for
  the read-only counterpart.

  Format:

    DEPOSIT location=data[,...]

1 DIFFERENCES
  Compares two files record by record and reports the lines that differ.

  Format:

    DIFFERENCES file-spec-1 file-spec-2

1 DIRECTORY
  Displays a list of files, or information about a file or group of
  files, in the command-procedure store.

  Format:

    DIRECTORY [file-spec] [/SIZE] [/DATE] [/FULL]

  Additional information available:

  Choose a qualifier subtopic below for details.

2 /SIZE
  Adds the used and allocated block counts to each entry.

    DIRECTORY/SIZE

2 /DATE
  Adds the creation date and time to each entry.

    DIRECTORY/DATE

2 /FULL
  Displays the full set of file attributes for each entry.

    DIRECTORY/FULL

1 DISMOUNT
  Detaches a volume that was previously mounted on a device with MOUNT.

  Format:

    DISMOUNT device-name[:]

1 EDIT
  Invokes an interactive text editor on a file in the command-procedure
  store. By default EDIT starts the EDT screen editor; EDIT/LINE starts
  the EDT line editor for scripted or line-at-a-time work.

  Format:

    EDIT [/LINE] file-spec

  Additional information available:

  Choose a subtopic below for editor details.

2 Screen_Mode
  The default EDT screen editor. Arrow keys move the cursor; printable
  characters insert at the cursor; RETURN splits the current line; and
  BACKSPACE or DELETE removes the character to the left, joining lines at
  the left margin. PAGE UP and PAGE DOWN scroll the viewport.

  CTRL/Z (or CTRL/X) writes the buffer and exits; CTRL/Y (or ESC ESC)
  discards changes and exits. The CTRL/X and ESC ESC alternatives exist
  for telnet clients whose terminal driver intercepts CTRL/Z and CTRL/Y.

2 /LINE
  Starts the EDT line editor, which prompts with an asterisk (*) and
  accepts the line-mode commands TYPE, INSERT, DELETE, FIND, SUBSTITUTE
  and EXIT. Preferred for editing a procedure from a script.

  Format:

    EDIT/LINE file-spec

1 EMERGENCY
  Orders the general emergency stop: every automatic train is braked to
  a stand and every cab is ordered to brake. The line's mode becomes
  EMERGENCY STOP, and a critical alarm stands until the stop is released
  with RESUME. EMERGENCY is the English short form of
  SET LINE /EMERGENCY=ON; in French mode the command is URGENCE.

  Format:

    EMERGENCY

1 EXAMINE
  Displays the contents of memory. The value at the given virtual
  address is shown as a longword.

  Format:

    EXAMINE location

  A hexadecimal address may be entered as ^X1000 or as 1000. See DEPOSIT
  for the (privileged) write counterpart.

1 EXIT
  Ends the current command procedure, or, at the interactive prompt,
  ends the DCL session. An optional status value is stored in $STATUS
  for the caller. See also LOGOUT.

  Format:

    EXIT [status-code]

1 FINGER
  Displays the interactive sessions on this node, or detailed information
  about a single user.

  Format:

    FINGER [user-name]

1 GOTO
  Within a command procedure, transfers control to a labelled line. The
  target is a line of the form $label: elsewhere in the procedure.

  Format:

    GOTO label

  See HELP SCRIPTING for labels, GOSUB and RETURN.

1 HELP
  Invokes the HELP facility to display information about a command or
  topic. Typed with no topic, HELP displays introductory text and then
  prompts for a topic; typed with a topic, it displays that topic and
  prompts for a subtopic.

  Format:

    HELP [topic [subtopic[ ...]]]

  At the "Topic?" prompt, type a topic name, a question mark (?) to
  redisplay the current text, an asterisk (*) to list everything, or
  press RETURN to move up one level (and, from the top level, to exit).
  Topic names may be abbreviated. Press CTRL/Z at any time to exit HELP.

2 Instructions
  See the INSTRUCTIONS topic for detailed operating instructions.

1 HINTS
  If you do not know the exact name of the command or topic you want,
  choose one of the categories below; each lists the commands that
  belong to it. Then request help on the command by name.

    Files          APPEND COPY CREATE DELETE DIFFERENCES DIRECTORY
                   PRINT PURGE RENAME SEARCH TYPE

    Devices        ALLOCATE DEALLOCATE MOUNT DISMOUNT

    PCC            SET SHOW START STOP EMERGENCY RESUME ACKNOWLEDGE
                   SHELVE UNSHELVE RUN PCC LEXICALS

    Information     SHOW MONITOR FINGER ACCOUNTING INSTALL PRODUCT

    Procedures     @ CREATE EDIT GOTO IF SUBMIT WAIT SCRIPTING TUTORIAL

    Mail_and_Msgs  MAIL PHONE REPLY REQUEST

    Session        SET RECALL SPAWN ATTACH LOGOUT EXIT

    Utilities      MONITOR LINE, MONITOR CABS, RUN RAME_DIR,
                   RUN LIGNE_DIR, MONITOR, EDIT
                   -- the full-screen displays; see HELP UTILITIES

  Short-form aliases follow the interface language: English mode accepts
  TRAIN, FLEET, LINE, STATIONS, CABS, EMERGENCY, RESUME; French mode
  accepts RAME, FLOTTE, LIGNE, GARES, CABINES, URGENCE, REPRISE, AIDE.

  Any command can be given the /PAGE qualifier to display long output one
  screenful at a time -- for example  SHOW SYSTEM/PAGE  or  HELP PCC/PAGE.
  Press RETURN for the next page, or Q to stop. The page length follows
  SET TERMINAL/PAGE.

1 IF
  Tests a condition and, when it is true, executes the command following
  THEN. An optional ELSE clause supplies a command for the false case.

  Format:

    IF expression THEN command [ELSE command]

  The comparison operators each begin and end with a period:

      .EQ. .NE. .LT. .LE. .GT. .GE.    integer comparison
      .EQS. .NES.                       string comparison
      .AND. .OR. .NOT.                  logical combination

  An expression with no operator is true when it is an odd integer or a
  string that begins with T or Y. So a condition value tests as success
  or failure, and a lexical function's TRUE and FALSE as themselves:

    $ SET RAME 21 /HOLD
    $ IF .NOT. $STATUS THEN GOTO REFUSED
    $ IF F$RAME(21,"IS_CAB") THEN SET RAME 21 /CALL

  See HELP SCRIPTING for the surrounding procedure language.

1 INITIALIZE
  Formats and labels a volume, destroying any data already on it. This
  command is privileged and returns %SYSTEM-F-NOPRIV for the operator
  account.

  Format:

    INITIALIZE device-name[:] volume-label

1 INSTALL
  Lists the known-image table -- the images made permanently resident by
  the system startup procedure, with their attributes (Open,
  Header-resident, Shared, Linkable).

  Format:

    INSTALL [LIST]

1 INSTRUCTIONS
  HELP displays information in levels. The top level lists commands and
  topics. When you select a topic, HELP shows its text and lists the
  subtopics available beneath it, then prompts for one.

  At any prompt you may:

    o  Type a topic or subtopic name (abbreviations are accepted). Type
       several names on one line to descend directly, for example
       SHOW PROCESS.

    o  Type an asterisk (*) to display everything at the current level,
       or a name containing an asterisk to match a group of topics.

    o  Type a question mark (?) to redisplay the text you last saw.

    o  Press RETURN to move up one level. Pressing RETURN at the
       top-level "Topic?" prompt exits HELP, as does CTRL/Z at any
       prompt.

1 LOGOUT
  Ends the interactive session and closes the terminal. /FULL appends an
  accounting summary of the session.

  Format:

    LOGOUT [/FULL]

1 LEXICALS
  The two lexical functions that read the PCC, for command procedures
  (and for WRITE SYS$OUTPUT at the prompt). Their values are
  identifiers, the same in both languages: TRUE and FALSE, numbers, a
  line's id, the words of the link in capitals. The other lexical
  functions are listed under HELP SCRIPTING Lexical_Functions.

  Additional information available:

  Choose a function below.

2 F$PCC
  Returns one thing about the PCC or its line.

    F$PCC(item)

      LISTENING     TRUE while the PCC listens
      PORT          the port it listens on, 0 when it does not
      NAME          its name
      LAN           TRUE on every interface, FALSE on loopback only
      LINE          the id of the line it is on, empty on none
      LINE_NAME     that line's name
      LINES         how many lines the library holds
      MODE          NORMAL, STOPPED or EMERGENCY; empty on no line
      SERVICE       TRUE while line service is on
      EMERGENCY     TRUE while the general emergency stop is on
      CLOCK         the line's time of day, hh:mm:ss
      HEADWAY       seconds between trains each way
      RAMES         how many trains are on the line
      FIRST_RAME    the lowest train number, 0 with none
      CABS          how many cabs are in service
      FIRST_CAB     the lowest number of a cab's train, 0 with none
      CONNECTIONS   how many connections the PCC has
      ALARMS        how many alarms stand
      UNACKED       how many of them are not acknowledged

  Example:

    $ IF F$PCC("CABS") .GT. 0 THEN GOTO FOUND

2 F$RAME
  Returns one thing about a train of the line, named by its number.
  Every item but EXISTS is empty when there is no such train.

    F$RAME(number,item)

      EXISTS        TRUE when the line has a train of that number
      KIND          AUTO or CAB
      IS_CAB        TRUE for a cab's train
      TRACK         1 or 2
      POSITION      metres along its track, to the metre
      SPEED         km/h, to the unit
      PHASE         RUNNING, DWELLING, DEPARTING, HELD, EMERGENCY or TAIL
      STATION       the station it stands at or runs to
      HELD          TRUE while the PCC holds it
      BRAKED        TRUE while the PCC has it braked
      CAB           its cab's name
      LINK          LIVE or SILENT
      MODE          CM, PA or CA
      AUTOMATIC     TRUE while the automatic driver has it
      EB            TRUE while its emergency brake is applied

  The number is a numeral: substitute a symbol with apostrophes.

    $ N = F$PCC("FIRST_CAB")
    $ IF F$RAME('N',"HELD") .EQS. "TRUE" THEN SET RAME 'N' /RELEASE

2 Example
  WAITCAB.COM, seeded in the command store, waits for a cab to enter
  service, then holds it at its next platform and tells its driver why.
  Its parameter is how many seconds to wait at most:

    $ @WAITCAB 300

1 MAIL
  Invokes the $OSTITLE$ Personal Mail Utility. Typed by itself, MAIL
  opens the MAIL> subshell for reading and sending messages; a one-line
  form is also accepted for use in procedures.

  Format:

    MAIL
    MAIL {DIRECTORY | READ [n] | SEND addr "subj" "text" | DELETE n}

  The line writes in-universe status mail (OPCOM and SCADA notices)
  into the same inbox as its state changes.

  Additional information available:

  Choose a MAIL> subcommand below.

2 DIRECTORY
  Lists the messages in the current folder, marking the current message
  and any that are new.

    MAIL> DIRECTORY

2 READ
  Displays a message. With no number, reads the current message, or the
  first new message if none is current. A bare RETURN at the MAIL>
  prompt reads the next message.

    MAIL> READ [n]

2 SEND
  Composes and sends a message. You are prompted for To:, Subj: and the
  message text; end the text with CTRL/Z, or CTRL/C to abandon it.

    MAIL> SEND [addr]

2 REPLY
  Composes a reply to the current message, pre-filling the recipient and
  the subject.

    MAIL> REPLY

2 FORWARD
  Forwards the current message, pre-loading the body with the forwarded
  text so you can add a note before sending.

    MAIL> FORWARD [addr]

2 DELETE
  Deletes a message. With no number, deletes the current message;
  DELETE ALL empties the folder.

    MAIL> DELETE [n | ALL]

2 Navigation
  NEXT and BACK step through the folder; FIRST and LAST jump to its ends;
  CURRENT redisplays the current message.

    MAIL> {NEXT | BACK | FIRST | LAST | CURRENT}

2 EXIT
  Leaves MAIL and returns to the DCL prompt. QUIT is a synonym.

    MAIL> EXIT

1 MONITOR
  Displays a continuously updated, full-screen report. The system
  classes are the $OSTITLE$ Monitor Utility's: they refresh every
  INTERVAL seconds (default 3); press CTRL/Y (or ESC ESC over telnet) to
  interrupt one and return to the DCL prompt. LINE, CABS, RAMES and
  CONNECTIONS are the PCC's own displays: they are drawn on the
  LPD PCC-CABINE screen in the session language, refresh every 0.5 s by
  default (/INTERVAL down to 0.25), CTRL/W repaints them and CTRL/Z
  leaves.

  Format:

    MONITOR class [/INTERVAL=seconds]

  Additional information available:

  Choose a class below.

2 LINE
  The line as a mimic board. Track 1 runs left to right on the upper
  rail and track 2 right to left on the lower, so a station is at one
  place on both and the two ends are the turn-backs; the stations are
  ticked and named. A train is its number and a mark at its nose:

      03>    an automatic train       21»    a cab (reverse video)
      03H    a train that is held     03!    one that is braked (flashing)
      03·    a train turning back in a tail

  Below it are the most severe standing alarm and a row for each cab:
  link, driving mode, speed, state, and where its authority ends. In
  French mode the class is LIGNE.

    MONITOR LINE [/INTERVAL=seconds]

2 CABS
  Every cab in service, four rows each: its link and the round trip of
  its last ping; CM, PA or CA and whether the automatic driver has the
  train; track, position, speed, state and station; the PCC's orders on
  it, doors, emergency brake, timetable and passengers; its movement
  authority and what ends it. In French mode the class is CABINES.

    MONITOR CABS [/INTERVAL=seconds]

2 RAMES
  Every train of the line: number, kind, track, position, speed, state,
  doors, the operator's hold (H) and brake (!), and the station it
  stands at or runs to. A table longer than the screen turns its pages
  by itself.

    MONITOR RAMES [/INTERVAL=seconds]

2 CONNECTIONS
  The listener, and every connection whatever its standing: opened,
  connected, on the line or in service; with its train, its cab's name,
  the line it holds, when it was last heard and the round trip of its
  last ping.

    MONITOR CONNECTIONS [/INTERVAL=seconds]

2 SYSTEM
  A composite display: processor mode breakdown, I/O rates and paging.

2 MODES
  The time the processor spends in each access mode.

2 PROCESSES
  The top processes by CPU time, as a bar chart.

2 IO
  I/O subsystem rates.

2 PAGE
  Page-management rates and the size of the free and modified lists.

2 STATES
  The number of processes in each scheduling state.

2 DISK
  Per-disk operation rates.

2 LOCK
  Lock manager rates.

2 FCP
  Files-11 XQP file-primitive rates.

2 ALL_CLASSES
  The SYSTEM, IO and STATES displays in turn, one at each refresh.

1 MOUNT
  Attaches a volume to a device and makes its files available. The
  volume label defaults to SCRATCH when omitted. System volumes are
  refused.

  Format:

    MOUNT device-name[:] [volume-label]

1 PATCH
  Modifies an image or data file in place. This command is privileged
  and returns %SYSTEM-F-NOPRIV for the operator account.

  Format:

    PATCH file-spec

1 PCC
  This node is the PCC (poste de commande centralisé, the control
  centre) of Cabine cabs. A Cabine in PCC mode dials it (TCP port 5289,
  advertised by Bonjour as _cabinepcc._tcp), and the PCC runs the line
  for every cab connected to it: it keeps a library of lines, runs the
  one its operator puts it on, drives the automatic trains, keeps every
  train apart in moving block, gives each cab its movement authority,
  and takes the operator's orders. LPD PCC-CABINE is the layered product
  that puts all of it at the DCL prompt.

  A first turn at the desk:

    $ SHOW PCC                      ! is it listening, and where
    $ SHOW LINES                    ! the library
    $ SET LINE /LOAD=4              ! put the PCC on ligne 4
    $ SHOW LINE                     ! the line, its service, its trains
    $ MONITOR LINE                  ! the mimic board (CTRL/Z to leave)
    $ SHOW CABS                     ! the cabs in service
    $ SET RAME 21 /HOLD /MESSAGE="WAIT FOR THE CONNECTION"
    $ SET RAME 21 /RELEASE
    $ RUN RAME_DIR                  ! the same orders, on a form
    $ SHOW ALARMS                   ! what the cabs have raised
    $ ACKNOWLEDGE ALARM ALL

  Additional information available:

  Choose a subject below.

2 Vocabulary
  The verbs, and the words that read the same in both languages, are
  fixed: PCC, RAME, RAMES, CONNECTIONS, JOURNAL, ALARMS, /SERVICE,
  /RAMES, /MESSAGE. The railway's other words follow the interface
  language, and only that language's spelling is accepted:

      English mode      French mode
      ---------------   ---------------
      LINE, LINES       LIGNE, LIGNES
      CABS              CABINES
      /LOAD             /CHARGER
      /CLOSE            /FERMER
      /REREAD           /RELIRE
      /EMERGENCY        /URGENCE
      /HEADWAY          /INTERVALLE
      /HOLD             /RETENIR
      /RELEASE          /LIBERER
      /BRAKE            /FREINER
      /UNBRAKE          /DEFREINER
      /CALL             /APPELER

  The short forms follow it too: TRAIN, FLEET, LINE, STATIONS, CABS,
  EMERGENCY and RESUME in English mode; RAME, FLOTTE, LIGNE, GARES,
  CABINES, URGENCE, REPRISE and AIDE in French mode.

2 Lines
  The lines are the PCC's. Each is a package: the description the engine
  runs it on, and the source a Cabine builds it from, which the PCC
  keeps and hands to any cab that does not hold the line. The library is
  read when the PCC starts: the lines the program was built with, then
  every *.line.json file in the Lines folder of the node's store (see
  HELP STORAGE). SHOW LINES lists it, SET LINE /LOAD puts the PCC on a
  line, and RUN LIGNE_DIR does both on a form. The PCC changes line only
  while no cab is in service.

2 Alarms
  The PCC raises its alarms into the SCADA log (SHOW ALARMS):

      Source      Point      Meaning
      ----------  ---------  ----------------------------------------
      LIGNE       AU         The general emergency stop is on
      CABINE nn   LIAISON    The cab of train nn has fallen silent
      CABINE nn   FU         The emergency brake of cab nn is applied
      RAME nn     FU         The PCC has braked automatic train nn
      CABINE #n   REVISION   Connection #n holds another revision of
                             the line, and cannot come on it
      PCC         ECOUTE     The listener failed
      CABINE nn   RADIO      A driver's coded report (an event)
      CABINE nn   APPEL      A driver calls the PCC (an event)
      PCC         FICHIER    A line file was refused (an event)
      PCC         LIGNE      The line last run is not in the library
                             (an event)

  The first six are process-driven: they return to normal when their
  cause does. The events stand until they are acknowledged and cleared
  (ACKNOWLEDGE ALARM id /CLEAR).

1 PHONE
  Establishes a real-time conversation with another user. This utility
  is not available on this installation and returns %PHONE-W-NOTAVAIL.

  Format:

    PHONE

1 PRINT
  Queues one or more files to a print queue for printing. Files are
  queued to SYS$PRINT.

  Format:

    PRINT file-spec[,...]

1 PRODUCT
  Displays or manages software products installed with the POLYCENTER
  Software Installation utility. Listed here are the installed VSI PCSI
  products with their kit, state and release.

  Format:

    PRODUCT SHOW PRODUCT

1 PURGE
  Deletes all but the most recent version, or versions, of the specified
  files.

  Format:

    PURGE [file-spec]

1 RECALL
  Displays or re-executes commands stored in the recall buffer.

  Format:

    RECALL [n | /ALL | /ERASE]

  RECALL n reprints command n; /ALL lists every command in the buffer;
  /ERASE clears the buffer. Up-arrow and down-arrow also step through it.

1 RENAME
  Changes the name, type, or version of one or more files.

  Format:

    RENAME input-file-spec output-file-spec

1 REPLY
  Sends a message to the operator console (OPA0:). The PCC node
  queues the reply line to OPCOM.

  Format:

    REPLY "message-text"

1 REQUEST
  Sends a message to the system operator and logs a request for
  operator assistance through OPCOM.

  Format:

    REQUEST "message-text"

1 RESUME
  Releases the general emergency stop. The cabs the operator has braked
  one by one stay braked. RESUME is the English short form of
  SET LINE /EMERGENCY=OFF; in French mode the command is REPRISE.

  Format:

    RESUME

1 RUN
  Executes an installed image. The operator account may run the PCC's
  two forms; other images return %SYSTEM-F-NOPRIV.

  Format:

    RUN image-name

  Additional information available:

  Choose a form below.

2 RAME_DIR
  Opens the trains and cabs form -- a full-screen DECforms-style
  application. The list on the left has every train of the line; the
  record on the right is the train under the cursor bar, with its cab's
  on a second page.

      Up, Down       move the cursor bar
      0-9            find a train by its number (DEL erases, CTRL/U
                     clears)
      Tab            the next page of the record
      H  R           hold the train at its next platform; release it
      B  U           order its emergency brake; release it
      M              a message for the cab's display
      C              call the cab's driver
      CTRL/W         repaint
      CTRL/Z         leave (ESC ESC over telnet)

  Every order asks before it acts: Y carries it out, any other key takes
  it back. In French mode the order keys are R (retenir), L (liberer),
  F (freiner), D (defreiner), M (message) and A (appeler), and the
  answer is O.

    RUN RAME_DIR

2 LIGNE_DIR
  Opens the line library form. The list on the left has every line the
  PCC holds, the one it is on marked with a dot; the record on the right
  is the line under the cursor bar: its name, revision, length and ends,
  then where its data came from, then its stations with the stop on each
  track.

      Up, Down       move the cursor bar
      0-9            find a line by its id
      Tab            the next page of the record
      L              put the PCC on the line
      C              put the PCC on no line
      R              read the library again
      CTRL/W         repaint
      CTRL/Z         leave (ESC ESC over telnet)

  Every order asks before it acts. A change of line is refused while a
  cab is in service. In French mode the keys are C (charger), F
  (fermer) and R (relire), and the answer is O.

    RUN LIGNE_DIR

1 SCRIPTING
  An overview of the DCL command-procedure language. Every command line
  in a procedure begins with a dollar sign ($); a line beginning with $!
  is a comment; a line with no leading $ is data echoed to SYS$OUTPUT.

  For a step-by-step guide, type HELP TUTORIAL.

  Additional information available:

  Choose an element below.

2 Symbols
  A symbol is created or updated with the equals sign. String values are
  quoted; integer values are numerals or arithmetic expressions:

    $ WHY = "WAIT FOR THE SIGNAL"  ! string symbol
    $ N = 7                        ! integer symbol
    $ N = N + 1                    ! integer arithmetic

  SHOW SYMBOL lists the defined symbols. The read-only symbols $STATUS,
  $SEVERITY, $PID, $PROCESS and $RESTART are always available. $STATUS
  is the condition value the last command left: %X00000001 after a
  success, a warning after an order the PCC refused (%X000080D0), and
  $SEVERITY its severity (1 success, 0 warning, 2 error, 4 fatal).
  SHOW SYMBOL $STATUS shows it, a symbol takes it (S = $STATUS), and IF
  tests it (HELP IF).

  PCC$LANGUAGE is a read-only built-in symbol holding the active
  console language, "EN" or "FR". It resolves live (switching the
  language changes it immediately) and cannot be shadowed by a user
  symbol. Procedures branch on it to keep their output and their
  language-gated qualifiers in the operator's language -- DEMO.COM and
  WAITCAB.COM do exactly this:

    $ IF PCC$LANGUAGE .EQS. "FR" THEN GOTO FR
    $ ! ... English block ...
    $ EXIT
    $FR:
    $ ! ... bloc francais ...

  The lexical function F$LANGUAGE() returns the same value.

  PCC$LINE, PCC$MODE, PCC$RAMES and PCC$CABS are read-only too, and as
  live: the id of the line the PCC is on (empty on none), the line's
  mode (NORMAL, STOPPED or EMERGENCY), and how many trains and cabs it
  has. F$PCC and F$RAME read the rest: see HELP LEXICALS.

2 Substitution
  Enclose a symbol name in apostrophes to substitute its value into a
  command line. Inside a quoted string, use the two-apostrophe opening
  form:

    $ WRITE SYS$OUTPUT "Train ''N' is held"

  A lexical function goes in the same way, with its arguments:

    $ WRITE SYS$OUTPUT "Train ''N' is at ''F$RAME('N',"STATION")'"

2 Labels
  A label is a line of the form $label:. GOTO branches to a label; GOSUB
  calls the code at a label and RETURN comes back to the line after the
  GOSUB:

    $LOOP:
    $   IF COUNT .GT. 5 THEN GOTO DONE
    $   GOSUB STEP
    $   COUNT = COUNT + 1
    $   GOTO LOOP
    $DONE:

2 Conditionals
  IF tests a condition and runs the command after THEN, with an optional
  ELSE branch. See HELP IF for the operator list.

    $ IF F$PCC("CABS") .GT. 0 THEN GOTO FOUND

2 Lexical_Functions
  Lexical functions have names beginning with F$ and return a string
  substituted into the command line before it runs:

      F$LENGTH  F$EXTRACT  F$LOCATE  F$INTEGER  F$STRING
      F$EDIT    F$TIME     F$USER    F$MODE     F$ENVIRONMENT
      F$SEARCH  F$TRNLNM   F$PID     F$LANGUAGE F$PCC   F$RAME

  F$LANGUAGE() returns the active console language, "EN" or "FR"
  (the same value as the read-only symbol PCC$LANGUAGE). F$PCC(item)
  and F$RAME(number,item) read the PCC and its trains: see HELP LEXICALS.

  Example:

    $ NAME = F$EDIT("  joe smith ","TRIM,UPCASE,COMPRESS")

2 Invocation
  Run a procedure with the @ command; up to eight parameters become the
  symbols P1 through P8:

    $ @GREET MARK

1 SEARCH
  Searches one or more files for the specified string and displays the
  lines that contain it.

  Format:

    SEARCH file-spec search-string

1 SELFTEST
  Drives every documented DCL verb once, in dry-run mode, and prints a
  per-verb pass or fail line. If the shell is still responsive
  afterwards, every verb dispatches without error. This is the PCC
  node's built-in command self-test. A verb that would take over the screen
  or change the PCC, its line, a train or the alarm log says what it would
  do, and does not do it.

  Format:

    SELFTEST

1 SET
  Modifies the characteristics of your process, your terminal, or the
  session environment, and gives the PCC, its line and its trains their
  orders (SET PCC, SET LINE, SET RAME).

  Format:

    SET option [value]

  Additional information available:

  Choose an option below.

2 PCC
  Starts and closes the PCC, and says how it listens.

    SET PCC /ENABLE /DISABLE        start / close the PCC
            /LAN={ON|OFF}           every interface and Bonjour, or
                                    this Mac only (loopback)
            /NAME="name"            the name cabs and Bonjour show

  Qualifiers compose. /DISABLE tells the cabs that the PCC is closing and
  closes their connections; the line goes with it, and is taken up again
  by /ENABLE. /LAN and /NAME take effect on a PCC that is running by
  closing it and starting it again, on the line it was on. All three are
  settings: they are kept for the next launch.

  Example:

    $ SET PCC /NAME="PCC LIGNE 4" /LAN=ON

2 LINE
  Chooses the line the PCC is on, and gives the line its orders. In
  French mode the object is LIGNE.

    SET LINE /LOAD=id               put the PCC on a line of its library
             /CLOSE                 put it on none
             /REREAD                read the library again
             /SERVICE={ON|OFF}      line service
             /EMERGENCY={ON|OFF}    the general emergency stop
             /HEADWAY=seconds       size the fleet for a train every so
                                    many seconds each way (30 to 3600)
             /RAMES={n|AUTO}        fix the number of trains, cabs
                                    included (2 to 52), or size it from
                                    the headway again

  Qualifiers compose: which line first, then its orders. /LOAD and
  /CLOSE are refused while a cab is in service on the present line. When
  the line changes, the PCC withdraws its automatic trains, seeds them
  afresh on the new line, starts the line's clock again, clears a
  general emergency stop and puts the line in service; every cab is told
  and follows. /REREAD keeps what is new or changed in the Lines folder
  without closing the PCC.

  French mode: /CHARGER, /FERMER, /RELIRE, /URGENCE, /INTERVALLE.

  Examples:

    $ SET LINE /LOAD=14
    $ SET LINE /HEADWAY=120
    $ SET LINE /EMERGENCY=ON

2 RAME
  Gives one train an order. The train is named by its number, which
  SHOW RAMES lists.

    SET RAME number /HOLD /RELEASE   keep it at the platform it is at,
                                     or the next it reaches; release it
                    /BRAKE /UNBRAKE  order its emergency brake; release
                                     it
                    /MESSAGE="text"  words for a cab's display (120
                                     characters at most)
                    /CALL            ring a cab's driver

  Qualifiers compose, so one line can hold a train and tell its driver
  why. /HOLD and /BRAKE work on any train; /MESSAGE and /CALL need a
  cab. An order that cannot be carried out is refused with its reason,
  and leaves a warning in $STATUS.

  French mode: /RETENIR, /LIBERER, /FREINER, /DEFREINER, /APPELER.

  Example:

    $ SET RAME 21 /HOLD /MESSAGE="WAIT FOR THE DEPARTURE SIGNAL"
    $ SET RAME 21 /RELEASE

2 DEFAULT
  Sets the default device and directory for file operations.

    SET DEFAULT [device:][directory]

2 TERMINAL
  Sets terminal characteristics such as display width and page length.

    SET TERMINAL /WIDTH=n /PAGE=n

2 PROMPT
  Sets the DCL prompt string.

    SET PROMPT="string"

2 PROCESS
  Sets process characteristics such as scheduling priority and name.

    SET PROCESS /PRIORITY=n /NAME=name

2 PASSWORD
  Changes the password of the current account.

    SET PASSWORD

2 ON
  Enables error checking, so that a warning or worse in a procedure
  triggers the established ON action. NOON disables the checking.

    SET {ON | NOON}

2 VERIFY
  Enables command echo, so that each line of a procedure is displayed as
  it executes. NOVERIFY disables the echo.

    SET {VERIFY | NOVERIFY}

1 SHELVE
  Shelves an active SCADA alarm (ISA-18.2 SHLVD): the alarm is removed from
  the primary annunciator -- the beacon, the panel list and the active
  count -- while remaining in the log so the action stays auditable. Use it
  to silence a known nuisance alarm without losing the record. UNSHELVE
  restores it. Distinct from ACKNOWLEDGE, which keeps the alarm annunciated.

  Format:

    SHELVE ALARM alarm-id

  The alarm sequence number is the one listed by SHOW ALARMS.

1 SHOW
  Displays information about the process, the system, devices, and the
  session environment, and about the PCC, its lines, its trains and its
  cabs.

  Format:

    SHOW option

  Additional information available:

  Choose a subject below.

2 PCC
  Displays the PCC: whether it listens and on which port, the network
  (every interface and Bonjour, or this Mac only), its name, the address
  to give a Cabine, how long it has listened, the line it is on, how
  many connections it has, and how many lines its library holds.

    SHOW PCC

2 LINES
  Displays the library: every line the PCC holds, with its id, name,
  revision, number of stations, length, whether its package has the
  line's source, and its two ends. The line the PCC is on is marked. In
  French mode the object is LIGNES.

    SHOW LINES

2 LINE
  Displays the line the PCC is on: its name and revision, length and
  ends, service, mode and clock, headway, fleet and lap, its trains, and
  its stock. In French mode the object is LIGNE.

    SHOW LINE [/STATIONS] [/SOURCE]

  /STATIONS lists every station with the stop on each track, in metres
  from the start of that track. /SOURCE says where the line's data came
  from, with the credits its licences ask for.

2 RAMES
  Displays every train of the line, cabs and automatic trains alike:
  number, kind, track, position, speed, state, doors and station, and
  the operator's hold and brake.

    SHOW RAMES

2 RAME
  Displays one train in full: kind, track, position, speed and
  acceleration, state, doors, station and the PCC's orders on it. For a
  cab's train it adds the cab: its name and connection, its link,
  driving mode and automatic driver, passengers and timetable, emergency
  brake, movement authority and last report. With no number it lists
  every train, as SHOW RAMES does.

    SHOW RAME [number]

2 CABS
  Displays the cabs in service: link and round trip, driving mode,
  automatic driver, track, position, speed, and where each one's
  movement authority ends and why. In French mode the object is CABINES.

    SHOW CABS

2 CONNECTIONS
  Displays every connection to the PCC, whatever its standing: opened,
  connected but not on the PCC's line, on the line, or in service; with
  its train, its cab's name and program, where it comes from, the line
  it holds, and when it was last heard.

    SHOW CONNECTIONS

2 JOURNAL
  Displays the PCC's journal, the newest lines last, by the line's
  clock: lines taken up, cabs connecting, joining, leaving and falling
  silent, drivers' reports and calls, orders refused, line files
  refused.

    SHOW JOURNAL [/LAST=n]

  /LAST gives how many lines to show (20 when left out). The journal
  keeps the last 200.

2 PROCESS
  Displays information about a process. /ALL displays the full set of
  process attributes.

    SHOW PROCESS [/ALL]

2 SYSTEM
  Displays the processes on the system, with their state and resource
  use.

    SHOW SYSTEM

2 USERS
  Displays the interactive users logged in to the node.

    SHOW USERS

2 DEVICES
  Displays the status of the devices on the system.

    SHOW DEVICES

2 MEMORY
  Displays the availability and use of physical memory and paging.

    SHOW MEMORY

2 TIME
  Displays the current date and time.

    SHOW TIME

2 NETWORK
  Displays the state of the network and the reachable nodes.

    SHOW NETWORK

2 ALARMS
  Displays the SCADA alarm log, with each alarm's severity, source,
  point and acknowledgement state. By default only standing (active,
  unshelved) alarms are shown; /ALL lists the full journal, including
  cleared, returned-to-normal (RTN) and shelved (SHLVD) history.

    SHOW ALARMS [/ALL]

2 LOGICAL
  Displays logical name translations. /PROCESS limits the display to the
  process logical name table.

    SHOW LOGICAL [/PROCESS] [name]

2 SYMBOL
  Displays the value of a DCL symbol, or of every symbol when no name is
  given. The read-only built-in symbols answer by name: $STATUS,
  $SEVERITY, PCC$LANGUAGE, PCC$LINE, PCC$MODE, PCC$RAMES and PCC$CABS.

    SHOW SYMBOL [name]

2 ERROR
  Displays a summary of recent device and system errors.

    SHOW ERROR

2 STATUS
  Displays the status and accumulated resource use of the current
  process.

    SHOW STATUS

2 LICENSE
  Displays the software licences registered on the node.

    SHOW LICENSE

2 CPU
  Displays the state of the processors in the system.

    SHOW CPU

2 DEFAULT
  Displays the current default device and directory.

    SHOW DEFAULT

2 QUOTA
  Displays the disk quota in effect for a user.

    SHOW QUOTA

2 PROTECTION
  Displays the default file protection applied to new files.

    SHOW PROTECTION

2 TERMINAL
  Displays the characteristics of your terminal.

    SHOW TERMINAL

2 WORKING_SET
  Displays the working-set limits and quota of the current process.

    SHOW WORKING_SET

2 VERSION
  Displays the operating-system name and version ($OSTITLE$
  $OSVERSION$).

    SHOW VERSION

2 RMS_DEFAULT
  Displays the process and system RMS default multiblock and
  multibuffer counts.

    SHOW RMS_DEFAULT

2 INTRUSION
  Displays the entries in the intrusion database (failed-login and
  break-in records).

    SHOW INTRUSION

2 AUDIT
  Displays the security-auditing characteristics in effect.

    SHOW AUDIT

2 CLUSTER
  Displays the cluster as this node sees it. A PCC node is a cluster of
  one: itself, with its votes and its quorum.

    SHOW CLUSTER

1 SPAWN
  Creates a subprocess to execute a command or an interactive session.
  This shell has no subprocess facility, so SPAWN returns
  -DCL-E-NOSUBPROC.

  Format:

    SPAWN [command]

1 STOP
  Stops line service, or brakes one train to a stand.

  Format:

    STOP LINE
    STOP RAME number

  Additional information available:

  Choose a form below for details.

2 LINE
  Line service off: no train has leave to move. A train at a platform
  stays there, and one on the move comes to a stand where it can. The
  same as SET LINE /SERVICE=OFF. For the general emergency stop, see
  HELP EMERGENCY. In French mode the object is LIGNE.

    STOP LINE

2 RAME
  Orders the emergency brake on one train: an automatic train brakes to
  a stand, a cab is ordered to brake. Release it with START RAME. The
  same as SET RAME number /BRAKE.

    STOP RAME number

1 STORAGE
  Describes the on-disk storage that backs the simulated PCC$ROOT:
  volume. Files kept there round-trip between the host and the shell.

  The host directory of the command store is:

    $STOREROOT$

  File types kept there:

    *.COM         Command procedures (CREATE / EDIT / TYPE / @ /
                  DELETE / COPY / RENAME / APPEND).
    *.LOG         Batch-job logs written by SUBMIT when a procedure
                  finishes.
    MAILBOX.JSON  The persistent MAIL inbox; it re-seeds with the
                  welcome messages if deleted.

  STARTUP.COM, LOGIN.COM, HELLO.COM, DEMO.COM and WAITCAB.COM are seeded
  into the directory on first launch. The INSTALL known-image table
  lives only in memory and re-seeds on every start.

  The operator's own lines are kept beside it, in:

    $LINESROOT$

  Every *.line.json file there is kept in the PCC's library when the PCC
  starts, after the lines the program was built with, and again on
  SET LINE /REREAD. A line file is a package, as
  Cabine --lines --export <folder> writes one for each of Cabine's
  lines.

1 SUBMIT
  Queues one or more command procedures to a batch queue for execution
  as a detached job. The prompt returns immediately; the job runs in the
  background.

  Format:

    SUBMIT file-spec[,...]

  When the job finishes, OPCOM posts a notification to this terminal,
  MAIL delivers the captured output, and a .LOG file is written beside
  the .COM (see HELP STORAGE for the host path).

1 TUTORIAL
  A step-by-step tutorial on writing and running DCL command procedures
  on this node. Every example runs on the live shell.

  Additional information available:

  Choose a lesson below, or read them in order.

2 Overview
  A command procedure is a text file containing the lines you would
  otherwise type at the "$" prompt. Every command line begins with a "$"
  so DCL treats it as a command rather than data:

    $ WRITE SYS$OUTPUT "Hello, world."
    $ EXIT

  Lines beginning with "$!" are comments. Blank lines, and lines with no
  leading "$", are treated as data and echoed to SYS$OUTPUT.

2 Editing
  Use EDIT to open the EDT editor on the file you want to author. Type
  your lines, then write the file and return to DCL. The default file
  type COM need not be typed. See HELP EDIT for the editor commands.

    $ EDIT GREET.COM

2 Running
  Invoke a procedure with "@" followed by its name. Up to eight
  positional parameters follow the name and appear inside the procedure
  as P1 through P8:

    $ @GREET
    $ @GREET MARK

2 Symbols
  A symbol is created with "=". String values are quoted; integers are
  numerals or arithmetic. Substitute a symbol into a line by enclosing
  its name in apostrophes:

    $ N = 7
    $ WRITE SYS$OUTPUT "Train ''N' is held"

  See HELP SCRIPTING Symbols for the read-only $STATUS and $SEVERITY
  symbols.

2 Branching
  IF is a single-line statement with an optional ELSE. Labels are lines
  of the form $label:; GOTO branches to one, GOSUB calls one and RETURN
  comes back. See HELP IF and HELP GOTO.

    $ IF N .GT. 8 THEN GOTO DONE

2 Lexical_Functions
  Lexical functions (names beginning with F$) return strings substituted
  into the command line before it runs -- F$TIME, F$USER, F$EDIT,
  F$EXTRACT, and others. See HELP SCRIPTING Lexical_Functions; F$PCC and
  F$RAME, which read the PCC and its trains, are under HELP LEXICALS.

    $ NAME = F$EDIT("  joe smith ","TRIM,UPCASE")

2 Example
  This procedure holds the first three trains of the line at their next
  platforms for ten seconds, then releases them. Save it as SWEEP.COM
  and run it with @SWEEP. (In French mode the qualifiers are /RETENIR
  and /LIBERER.)

    $ ! SWEEP.COM -- hold trains 1 to 3 for ten seconds
    $ N = 1
    $LOOP:
    $   IF N .GT. 3 THEN GOTO HELD
    $   IF F$RAME('N',"EXISTS") .EQS. "TRUE" THEN SET RAME 'N' /HOLD
    $   N = N + 1
    $   GOTO LOOP
    $HELD:
    $ WAIT 00:00:10
    $ N = 1
    $FREE:
    $   IF N .GT. 3 THEN GOTO DONE
    $   IF F$RAME('N',"EXISTS") .EQS. "TRUE" THEN SET RAME 'N' /RELEASE
    $   N = N + 1
    $   GOTO FREE
    $DONE:
    $ WRITE SYS$OUTPUT "Sweep complete at ''F$TIME()'"
    $ EXIT

1 TYPE
  Displays the contents of one or more sequential ASCII files at the
  terminal. A user-authored .COM file is read from the command-procedure
  store; a binary file (such as LIBRARY.DAT) returns %TYPE-W-NOTASCII.

  Format:

    TYPE file-spec[,...]

1 UNSHELVE
  Restores a shelved SCADA alarm (see HELP SHELVE) to the primary
  annunciator. If the underlying condition is still present the alarm
  re-annunciates immediately.

  Format:

    UNSHELVE ALARM alarm-id

1 UTILITIES
  The full-screen utilities available on this node. Each one takes over
  the terminal (the DCL window or a telnet session on port 2324) until
  you leave it, then returns you to the $ prompt. Type the command shown
  at the $ prompt to start the utility.

    Command                  Display
    -----------------------  -----------------------------------------
    MONITOR LINE             The line as a mimic board, alarms, cabs
    MONITOR CABS             Every cab in service, live
    MONITOR RAMES            Every train of the line, live
    MONITOR CONNECTIONS      The listener and every connection, live
    RUN RAME_DIR             Trains and cabs form, with the orders
    RUN LIGNE_DIR            Line library form
    MONITOR class            $OSTITLE$ Monitor Utility (SYSTEM, IO, ...)
    EDIT file-spec           EDT screen editor

  In French mode the line and cab monitors are MONITOR LIGNE and
  MONITOR CABINES.

  Leaving a utility. The keys are the same on every screen:

    CTRL/Z     Exit (the PCC's monitors and forms, EDT -- EDT saves the
               file)
    CTRL/W     Repaint (the PCC's monitors and forms)
    CTRL/Y     Interrupt and return to the $ prompt (every display)
    ESC ESC    Same as CTRL/Y, for telnet clients whose terminal driver
               swallows CTRL/Y or CTRL/Z

  MAIL and HELP are prompt-driven rather than full-screen: leave MAIL
  with EXIT, and HELP with CTRL/Z or RETURN at the "Topic?" prompt.

  Add /PAGE to any ordinary command to page its output instead, for
  example  SHOW RAMES/PAGE.

2 Monitors
  The PCC's four live displays, the layered product's own SMG
  pasteboard: a banner, the line's status, bordered displays and a key
  legend, drawn once and then updated row by row.

    $ MONITOR LINE                 ! refresh every 0.5 s
    $ MONITOR LINE /INTERVAL=0.25  ! the fastest refresh
    $ MONITOR CABS
    $ MONITOR RAMES
    $ MONITOR CONNECTIONS

  CTRL/W repaints the screen; CTRL/Z exits. See HELP MONITOR for each
  display, and for the system classes.

2 Forms
  The PCC's two DECforms-style forms. The arrows move the cursor bar,
  digits find, Tab turns the pages of the record, and a key gives an
  order, which the form asks about before it acts.

    $ RUN RAME_DIR
    $ RUN LIGNE_DIR

  CTRL/Z or ESC ESC leaves a form. See HELP RUN.

1 WAIT
  Suspends the procedure or the interactive session for the specified
  delta time.

  Format:

    WAIT hh:mm:ss[.cc]

1 WRITE
  Writes a line to an open file or to a logical device. WRITE
  SYS$OUTPUT echoes a literal string to the terminal; other destinations
  return a WRITERR condition in this shell.

  Format:

    WRITE logical-name expression
"""
}
