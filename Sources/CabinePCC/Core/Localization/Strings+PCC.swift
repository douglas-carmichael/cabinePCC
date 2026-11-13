import Foundation

// The PCC's own strings: what the PCC Dispatcher shows, and what the DCL
// verbs, the monitors and the forms of LPD PCC-CABINE print. They are
// layered-product content, and localized.
//
// A string that goes through String(format:) writes a percent sign twice;
// one that is printed as it stands writes it once. The `%PCC-x-IDENT`
// codes and the qualifiers are the same in both columns where the word is
// fixed, and each language's own where it is gated.
extension Strings {
    static func addPCCStrings(to t: inout [String: [Lang: String]]) {
        func add(_ key: String, _ en: String, _ fr: String) {
            t[key] = [.en: en, .fr: fr]
        }

        // -- alarm messages. Stored in English in the log, localized on
        //    display through `alarmMessageKeys`.
        add("alarm.msg.emergency",  "General emergency stop -- every train is braked",
                                    "Arrêt d'urgence général -- toutes les rames sont freinées")
        add("alarm.msg.fu",         "Emergency brake applied",             "Freinage d'urgence serré")
        add("alarm.msg.cab.silent", "Cab silent -- train held where it was last seen, as an obstacle",
                                    "Cabine muette -- rame maintenue où elle a été vue en dernier, en obstacle")
        add("alarm.msg.cab.revision", "Cab holds another revision of the line -- it cannot come on it",
                                    "Cabine sur une autre révision de la ligne -- elle ne peut pas s'y présenter")
        add("alarm.msg.cab.call",   "Driver calls the PCC",                "Le conducteur appelle le PCC")
        add("alarm.msg.cab.report.radiocheck", "Driver report: radio check",
                                    "Signalement conducteur : essai radio")
        add("alarm.msg.cab.report.readytodepart", "Driver report: ready to depart",
                                    "Signalement conducteur : prêt au départ")
        add("alarm.msg.cab.report.stoppedatsignal", "Driver report: stopped at a signal",
                                    "Signalement conducteur : arrêté devant un signal")
        add("alarm.msg.cab.report.passengerill", "Driver report: passenger taken ill",
                                    "Signalement conducteur : malaise voyageur")
        add("alarm.msg.cab.report.technicalfault", "Driver report: technical fault",
                                    "Signalement conducteur : avarie technique")
        add("alarm.msg.cab.report.incidentover", "Driver report: incident over",
                                    "Signalement conducteur : fin d'incident")
        add("alarm.msg.cab.report.requestcall", "Driver report: asks the PCC to call",
                                    "Signalement conducteur : demande d'appel du PCC")
        add("alarm.msg.cab.report.other", "Driver report received, with a code this PCC does not know",
                                    "Signalement conducteur reçu, avec un code inconnu de ce PCC")
        add("alarm.msg.pcc.listener", "The PCC's listener failed -- no cab can connect",
                                    "L'écoute du PCC est en défaut -- aucune cabine ne peut se connecter")
        add("alarm.msg.pcc.linefile", "A line file was refused -- see the journal",
                                    "Un fichier de ligne a été refusé -- voir le journal")
        add("alarm.msg.pcc.linenotheld", "The line last run is not in the library -- the PCC is on no line",
                                    "La dernière ligne exploitée n'est plus dans la bibliothèque -- le PCC est sans ligne")

        // -- the PCC and its listener.
        add("pcc.title",            "PCC — THE CABS' CONTROL CENTRE",      "PCC — POSTE DE COMMANDE DES CABINES")
        add("pcc.dcl.title",        "%@ on node %@ -- PCC of the Cabine cabs",
                                    "%@ sur le nœud %@ -- PCC des cabines Cabine")
        add("pcc.cab",              "CAB",                                 "CABINE")
        add("pcc.rame",             "Train",                               "Rame")
        add("pcc.listener.disabled", "DISABLED",                           "DÉSACTIVÉ")
        add("pcc.listener.starting", "STARTING",                           "DÉMARRAGE")
        add("pcc.listener.listening", "LISTENING ON PORT %d",              "À L'ÉCOUTE SUR LE PORT %d")
        add("pcc.listener.failed",  "FAILED (%@)",                         "EN DÉFAUT (%@)")
        add("pcc.lan.on",           "EVERY INTERFACE, BONJOUR",            "TOUTES LES INTERFACES, BONJOUR")
        add("pcc.lan.off",          "THIS MAC ONLY (LOOPBACK)",            "CE MAC SEULEMENT (BOUCLE LOCALE)")
        add("pcc.address.fmt",      "%@ port %d",                          "%@ port %d")
        add("pcc.hint.disabled",    "The PCC is disabled: SET PCC /ENABLE in a DCL terminal starts it.",
                                    "Le PCC est désactivé : SET PCC /ENABLE dans un terminal DCL le démarre.")
        add("pcc.hint.failed",      "The listener could not start: SET PCC /DISABLE, then /ENABLE, tries again.",
                                    "L'écoute n'a pas pu démarrer : SET PCC /DISABLE, puis /ENABLE, relance l'essai.")
        add("pcc.hint.slow.lan",    "The PCC has yet to listen. If macOS has not given this program the local network, allow it in System Settings ▸ Privacy & Security ▸ Local Network; SET PCC /LAN=OFF listens on this Mac only.",
                                    "Le PCC n'écoute pas encore. Si macOS n'a pas accordé le réseau local à ce programme, autorisez-le dans Réglages Système ▸ Confidentialité et sécurité ▸ Réseau local ; SET PCC /LAN=OFF n'écoute que sur ce Mac.")
        add("pcc.hint.slow",        "The PCC has yet to listen: SET PCC /DISABLE, then /ENABLE, tries again.",
                                    "Le PCC n'écoute pas encore : SET PCC /DISABLE, puis /ENABLE, relance l'essai.")
        add("pcc.noline",           "The PCC is on no line: SET LINE /LOAD=id puts it on one of its library (SHOW LINES).",
                                    "Le PCC n'est sur aucune ligne : SET LIGNE /CHARGER=id le place sur une ligne de sa bibliothèque (SHOW LIGNES).")
        add("pcc.noline.window",    "The PCC is on no line: its cabs wait for one. Choose a line of the library below.",
                                    "Le PCC n'est sur aucune ligne : ses cabines en attendent une. Choisissez une ligne de la bibliothèque ci-dessous.")

        // -- labels of the reports and the panels.
        add("pcc.label.listener",   "Listener",                            "Écoute")
        add("pcc.label.network",    "Network",                             "Réseau")
        add("pcc.label.name",       "Name",                                "Nom")
        add("pcc.label.address",    "Address for Cabine",                  "Adresse pour Cabine")
        add("pcc.label.uptime",     "Listening for",                       "À l'écoute depuis")
        add("pcc.label.connections", "Connections",                        "Connexions")
        add("pcc.label.connection", "Connection",                          "Connexion")
        add("pcc.label.library",    "Library",                             "Bibliothèque")
        add("pcc.label.line",       "Line",                                "Ligne")
        add("pcc.label.ends",       "From -- to",                          "De -- à")
        add("pcc.label.service",    "Service",                             "Service")
        add("pcc.label.mode",       "Mode",                                "Mode")
        add("pcc.label.clock",      "Line clock",                          "Heure de la ligne")
        add("pcc.label.trains",     "Trains",                              "Rames")
        add("pcc.label.stock",      "Stock",                               "Matériel")
        add("pcc.label.headway",    "Headway",                             "Intervalle")
        add("pcc.label.fleet",      "Fleet",                               "Parc")
        add("pcc.label.lap",        "Lap",                                 "Tour")
        add("pcc.label.kind",       "Kind",                                "Type")
        add("pcc.label.track",      "Track",                               "Voie")
        add("pcc.label.position",   "Position",                            "Position")
        add("pcc.label.speed",      "Speed",                               "Vitesse")
        add("pcc.label.acceleration", "Acceleration",                      "Accélération")
        add("pcc.label.state",      "State",                               "État")
        add("pcc.label.doors",      "Doors",                               "Portes")
        add("pcc.label.station",    "Station",                             "Station")
        add("pcc.label.orders",     "PCC orders",                          "Ordres du PCC")
        add("pcc.label.cab",        "Cab",                                 "Cabine")
        add("pcc.label.link",       "Link",                                "Liaison")
        add("pcc.label.driving",    "Driving",                             "Conduite")
        add("pcc.label.autopilot",  "Autopilot",                           "Pilote auto")
        add("pcc.label.pax",        "Passengers",                          "Voyageurs")
        add("pcc.label.timetable",  "Timetable",                           "Horaire")
        add("pcc.label.eb",         "Emergency brake",                     "Freinage d'urgence")
        add("pcc.label.authority",  "Authority",                           "Autorisation")
        add("pcc.label.report",     "Last report",                         "Dernier signalement")

        // -- the line.
        add("pcc.line.fmt",         "%@ -- %.1f km a track, %d stations",  "%@ -- %.1f km par voie, %d stations")
        add("pcc.line.none",        "none",                                "aucune")
        add("pcc.trains.fmt",       "%d (cabs: %d)",                       "%d (cabines : %d)")
        add("pcc.fleet.auto",       "FROM THE HEADWAY",                    "SELON L'INTERVALLE")
        add("pcc.fleet.fixed",      "FIXED AT %d",                         "FIXÉ À %d")
        add("pcc.word.on",          "ON",                                  "ACTIF")
        add("pcc.word.off",         "OFF",                                 "ARRÊTÉ")
        add("pcc.word.yes",         "yes",                                 "oui")
        add("pcc.word.no",          "no",                                  "non")
        add("pcc.mode.normal",      "NORMAL",                              "NORMAL")
        add("pcc.mode.stopped",     "SERVICE STOPPED",                     "SERVICE ARRÊTÉ")
        add("pcc.mode.emergency",   "EMERGENCY STOP",                      "ARRÊT D'URGENCE")
        add("pcc.controls.title",   "LINE CONTROL",                        "COMMANDE DE LA LIGNE")
        add("pcc.btn.service.start", "START SERVICE",                      "DÉMARRER LE SERVICE")
        add("pcc.btn.service.stop", "STOP SERVICE",                        "ARRÊTER LE SERVICE")
        add("pcc.btn.emergency",    "EMERGENCY STOP",                      "ARRÊT D'URGENCE")
        add("pcc.btn.closeline",    "CLOSE THE LINE",                      "FERMER LA LIGNE")
        add("pcc.btn.reread",       "REREAD",                              "RELIRE")
        add("pcc.diagram.title",    "THE LINE",                            "LA LIGNE")
        add("pcc.diagram.tail",     "TAIL",                                "TIROIR")
        add("pcc.diagram.tracks",   "TRACK 1 ABOVE, LEFT TO RIGHT · TRACK 2 BELOW, RIGHT TO LEFT",
                                    "VOIE 1 EN HAUT, DE GAUCHE À DROITE · VOIE 2 EN BAS, DE DROITE À GAUCHE")
        add("pcc.library.title",    "LINE LIBRARY (%d)",                   "BIBLIOTHÈQUE DE LIGNES (%d)")
        add("pcc.library.line",     "id %@, rev %@ -- %.2f km a track, %d stations: %@ -- %@",
                                    "id %@, rév. %@ -- %.2f km par voie, %d stations : %@ -- %@")

        // -- where a line's data came from. The values are the package's own.
        add("pcc.credits.title",    "Sources of the line's data:",         "Origine des données de la ligne :")
        add("pcc.credits.track",    "Track:     %@",                       "Tracé :      %@")
        add("pcc.credits.stations", "Stations:  %@",                       "Stations :   %@")
        add("pcc.credits.ground",   "Ground:    %@",                       "Altimétrie : %@")
        add("pcc.credits.date",     "Extract of %@",                       "Extraction du %@")
        add("pcc.credits.none",     "An invented line, built into every Cabine: it has no outside data to credit.",
                                    "Ligne inventée, intégrée à chaque Cabine : aucune donnée extérieure à créditer.")

        // -- the words of the wire.
        add("pcc.kind.auto",        "AUTO",                                "AUTO")
        add("pcc.kind.cab",         "CAB",                                 "CABINE")
        add("pcc.phase.running",    "RUNNING",                             "EN MARCHE")
        add("pcc.phase.dwelling",   "AT PLATFORM",                         "À QUAI")
        add("pcc.phase.departing",  "DEPARTING",                           "DÉPART")
        add("pcc.phase.held",       "HELD",                                "RETENUE")
        add("pcc.phase.emergency",  "EB",                                  "FU")
        add("pcc.phase.tail",       "TURNING BACK",                        "RETOURNEMENT")
        add("pcc.link.live",        "LIVE",                                "ACTIVE")
        add("pcc.link.silent",      "SILENT",                              "MUETTE")
        add("pcc.heard",            "heard %.1f s ago",                    "entendue il y a %.1f s")
        add("pcc.roundtrip",        "round trip %.0f ms",                  "aller-retour %.0f ms")
        add("pcc.autopilot.on",     "ENGAGED",                             "ENGAGÉ")
        add("pcc.autopilot.off",    "OFF",                                 "COUPÉ")
        add("pcc.doorphase.closed", "CLOSED",                              "FERMÉES")
        add("pcc.doorphase.opening", "OPENING",                            "OUVERTURE")
        add("pcc.doorphase.open",   "OPEN",                                "OUVERTES")
        add("pcc.doorphase.warning", "CLOSING WARNING",                    "SIGNAL DE FERMETURE")
        add("pcc.doorphase.closing", "CLOSING",                            "FERMETURE")
        add("pcc.side.right",       "ON THE RIGHT",                        "À DROITE")
        add("pcc.side.left",        "ON THE LEFT",                         "À GAUCHE")
        add("pcc.fu.applied",       "APPLIED",                             "SERRÉ")
        add("pcc.fu.released",      "RELEASED",                            "RELÂCHÉ")
        add("pcc.position.fmt",     "track %d, %.0f m",                    "voie %d, %.0f m")
        add("pcc.station.at",       "AT %@",                               "À %@")
        add("pcc.station.to",       "TO %@",                               "VERS %@")
        add("pcc.deviation.ontime", "ON TIME",                             "À L'HEURE")
        add("pcc.deviation.late",   "%d s LATE",                           "%d s DE RETARD")
        add("pcc.deviation.early",  "%d s EARLY",                          "%d s D'AVANCE")
        add("pcc.flag.held",        "HELD BY THE PCC",                     "RETENUE PAR LE PCC")
        add("pcc.flag.braked",      "EB ORDERED BY THE PCC",               "FU COMMANDÉ PAR LE PCC")
        add("pcc.flag.paused",      "GAME PAUSED",                         "JEU EN PAUSE")
        add("pcc.authority.fmt",    "ends %.0f m ahead: %@",               "se termine à %.0f m : %@")
        add("pcc.authority.none",   "none sent yet",                       "aucune envoyée")
        add("pcc.reason.train.gap", "train %@ ahead, its rear %.0f m away",
                                    "rame %@ devant, son arrière à %.0f m")
        add("pcc.reason.train",     "the train ahead",                     "la rame qui précède")
        add("pcc.reason.horizon",   "nothing within reach (horizon)",      "rien à portée (horizon)")
        add("pcc.reason.end",       "the end of the track",                "la fin de la voie")
        add("pcc.reason.hold",      "held by the PCC",                     "retenue par le PCC")
        add("pcc.reason.service",   "the line is out of service",          "la ligne est hors service")
        add("pcc.reason.emergency", "general emergency stop",              "arrêt d'urgence général")
        add("pcc.reason.short.train", "train %@",                          "rame %@")
        add("pcc.reason.short.horizon", "clear ahead",                     "voie libre")
        add("pcc.reason.short.end", "end of track",                        "fin de voie")
        add("pcc.reason.short.hold", "held",                               "retenue")
        add("pcc.reason.short.service", "no service",                      "hors service")
        add("pcc.reason.short.emergency", "emergency stop",                "arrêt d'urgence")
        add("pcc.report.radiocheck", "RADIO CHECK",                        "ESSAI RADIO")
        add("pcc.report.readytodepart", "READY TO DEPART",                 "PRÊT AU DÉPART")
        add("pcc.report.stoppedatsignal", "STOPPED AT A SIGNAL",           "ARRÊTÉ DEVANT UN SIGNAL")
        add("pcc.report.passengerill", "PASSENGER ILL",                    "MALAISE VOYAGEUR")
        add("pcc.report.technicalfault", "TECHNICAL FAULT",                "AVARIE TECHNIQUE")
        add("pcc.report.incidentover", "INCIDENT OVER",                    "FIN D'INCIDENT")
        add("pcc.report.requestcall", "ASKS TO BE CALLED",                 "DEMANDE D'APPEL")
        add("pcc.report.none",      "NO CODE",                             "SANS CODE")
        add("pcc.report.at",        "%@ at %@",                            "%@ à %@")
        add("pcc.report.never",     "none",                                "aucun")
        add("pcc.command.emergencybrake", "EMERGENCY BRAKE",               "FREINAGE D'URGENCE")
        add("pcc.command.hold",     "HOLD",                                "RETENUE")
        add("pcc.command.message",  "MESSAGE",                             "MESSAGE")
        add("pcc.command.call",     "CALL",                                "APPEL")
        add("pcc.standing.opened",  "CONNECTED, NOT YET ANNOUNCED",        "CONNECTÉE, PAS ENCORE ANNONCÉE")
        add("pcc.standing.connected", "CONNECTED, NOT ON THE PCC'S LINE",  "CONNECTÉE, HORS DE LA LIGNE DU PCC")
        add("pcc.standing.online",  "ON THE LINE",                         "SUR LA LIGNE")
        add("pcc.standing.inservice", "IN SERVICE",                        "EN SERVICE")
        add("pcc.standing.short.opened", "OPENED",                         "OUVERTE")
        add("pcc.standing.short.connected", "CONNECTED",                   "CONNECTÉE")
        add("pcc.standing.short.online", "ON LINE",                        "SUR LIGNE")
        add("pcc.standing.short.inservice", "IN SERVICE",                  "EN SERVICE")
        add("pcc.connection.line",  "its line %@ (%@, rev %@)",            "sa ligne %@ (%@, rév. %@)")
        add("pcc.connection.noline", "holds no line",                      "sans ligne")
        add("pcc.connection.gone",  "gone: the train is held where it was last seen",
                                    "perdue : la rame est maintenue où elle a été vue en dernier")
        add("pcc.leave.finished",   "terminus reached",                    "terminus atteint")
        add("pcc.leave.ended",      "service ended by the driver",         "service terminé par le conducteur")
        add("pcc.leave.quit",       "Cabine closed",                       "fermeture de Cabine")
        add("pcc.leave.left",       "service over",                        "fin de service")

        // -- columns of the tables.
        add("pcc.col.no",           "No",                                  "N°")
        add("pcc.col.kind",         "Kind",                                "Type")
        add("pcc.col.track",        "Trk",                                 "Voie")
        add("pcc.col.position",     "Position",                            "Position")
        add("pcc.col.speed",        "Speed",                               "Vitesse")
        add("pcc.col.kmh",          "km/h",                                "km/h")
        add("pcc.col.state",        "State",                               "État")
        add("pcc.col.doors",        "Doors",                               "Portes")
        add("pcc.col.orders",       "PCC",                                 "PCC")
        add("pcc.col.station",      "Station",                             "Station")
        add("pcc.col.cab",          "Cab",                                 "Cabine")
        add("pcc.col.link",         "Link",                                "Liaison")
        add("pcc.col.roundtrip",    "RT",                                  "A-R")
        add("pcc.col.mode",         "Mode",                                "Mode")
        add("pcc.col.autopilot",    "Autopilot",                           "Pilote")
        add("pcc.col.authority",    "Authority",                           "Autorisation")
        add("pcc.col.session",      "#",                                   "#")
        add("pcc.col.standing",     "Standing",                            "Statut")
        add("pcc.col.rame",         "Train",                               "Rame")
        add("pcc.col.line",         "Line",                                "Ligne")
        add("pcc.col.heard",        "Heard",                               "Entendue")
        add("pcc.col.from",         "From",                                "Origine")
        add("pcc.col.id",           "Id",                                  "Id")
        add("pcc.col.name",         "Name",                                "Nom")
        add("pcc.col.rev",          "Revision",                            "Révision")
        add("pcc.col.stations",     "Stations",                            "Stations")
        add("pcc.col.length",       "Length",                              "Longueur")
        add("pcc.col.source",       "Source",                              "Source")
        add("pcc.col.ends",         "From -- to",                          "De -- à")
        add("pcc.col.stop1",        "Track 1",                             "Voie 1")
        add("pcc.col.stop2",        "Track 2",                             "Voie 2")

        // -- the panels of the dispatcher.
        add("pcc.rames.title",      "TRAINS (%d)",                         "RAMES (%d)")
        add("pcc.rames.none",       "(no train on the line)",              "(aucune rame sur la ligne)")
        add("pcc.cabs.title",       "CABS",                                "CABINES")
        add("pcc.cabs.none",        "(no cab in service: the automatic trains run the line)",
                                    "(aucune cabine en service : les rames automatiques assurent la ligne)")
        add("pcc.connections.title", "Connections",                        "Connexions")
        add("pcc.connections.none", "(none)",                              "(aucune)")
        add("pcc.journal.title",    "JOURNAL",                             "JOURNAL")
        add("pcc.journal.none",     "(nothing has happened yet)",          "(rien ne s'est encore passé)")
        add("pcc.btn.hold",         "HOLD",                                "RETENIR")
        add("pcc.btn.release",      "RELEASE",                             "LIBÉRER")
        add("pcc.btn.eb",           "EB",                                  "FU")
        add("pcc.btn.unbrake",      "RELEASE EB",                          "RELÂCHER FU")
        add("pcc.btn.message",      "MESSAGE",                             "MESSAGE")
        add("pcc.btn.call",         "CALL",                                "APPEL")
        add("pcc.message.prompt",   "message for the driver's display",    "message pour l'afficheur du conducteur")

        // -- the journal.
        add("pcc.journal.oframe",   " (train %@)",                         " (rame %@)")
        add("pcc.journal.saying",   " -- %@",                              " -- %@")
        add("pcc.journal.linetakenup", "Line taken up: %@ (%@, rev %@), %d automatic trains",
                                    "Ligne prise en charge : %@ (%@, rév. %@), %d rames automatiques")
        add("pcc.journal.lineclosed", "The PCC is on no line",             "Le PCC n'est sur aucune ligne")
        add("pcc.journal.library",  "Library read: %d lines held",         "Bibliothèque lue : %d lignes")
        add("pcc.journal.library.one", "Library read: 1 line held",        "Bibliothèque lue : 1 ligne")
        add("pcc.journal.linefile", "Line file %@ refused: %@",            "Fichier de ligne %@ refusé : %@")
        add("pcc.journal.linenotheld", "The line last run (%@) is not in the library: the PCC is on no line",
                                    "La dernière ligne exploitée (%@) n'est plus dans la bibliothèque : le PCC est sans ligne")
        add("pcc.fault.unreadable", "it could not be read",                "il n'a pas pu être lu")
        add("pcc.fault.notapackage", "it is not a line package",           "ce n'est pas un paquet de ligne")
        add("pcc.fault.field",      "%@: %@",                              "%@ : %@")
        add("pcc.fault.refused",    "its description fails the engine's checks (%@)",
                                    "sa description est refusée par le moteur (%@)")
        add("pcc.journal.connected", "Cab %@ connected, holding %@ (%@, rev %@)",
                                    "Cabine %@ connectée, avec %@ (%@, rév. %@)")
        add("pcc.journal.connected.noline", "Cab %@ connected, holding no line",
                                    "Cabine %@ connectée, sans ligne")
        add("pcc.journal.online",   "Cab %@ is on the line",               "Cabine %@ sur la ligne")
        add("pcc.journal.linerefused", "Cab %@ asked for a line and was refused (%@): %@",
                                    "Cabine %@ : ligne demandée refusée (%@) : %@")
        add("pcc.journal.linehanded", "%@ (%@, rev %@) handed to cab %@",
                                    "%@ (%@, rév. %@) remise à la cabine %@")
        add("pcc.journal.refused.nosuchline", "the library holds no such line",
                                    "la bibliothèque n'a pas cette ligne")
        add("pcc.journal.joined",   "Cab %@ in service as train %@, track %d at %.1f m",
                                    "Cabine %@ en service, rame %@, voie %d à %.1f m")
        add("pcc.journal.joined.inplace", ", in place of %@",              ", à la place de %@")
        add("pcc.journal.left",     "Cab %@ left service, train %@: %@",   "Cabine %@ sortie du service, rame %@ : %@")
        add("pcc.journal.silent",   "Cab %@ is silent: train %@ held as an obstacle",
                                    "Cabine %@ muette : rame %@ maintenue en obstacle")
        add("pcc.journal.heardagain", "Cab %@ is heard again, train %@",   "Cabine %@ de nouveau entendue, rame %@")
        add("pcc.journal.handedback", "Train %@ of cab %@ handed back to automation as train %@",
                                    "Rame %@ de la cabine %@ rendue à l'automatisme, rame %@")
        add("pcc.journal.disconnected", "Cab %@ disconnected",             "Cabine %@ déconnectée")
        add("pcc.journal.fu.applied", "Cab %@%@: emergency brake applied", "Cabine %@%@ : FU serré")
        add("pcc.journal.fu.released", "Cab %@%@: emergency brake released", "Cabine %@%@ : FU relâché")
        add("pcc.journal.report",   "Cab %@%@ reports %@",                 "Cabine %@%@ signale %@")
        add("pcc.journal.call",     "Cab %@%@ calls the PCC",              "Cabine %@%@ appelle le PCC")
        add("pcc.journal.acknowledge", "Cab %@%@ acknowledges",            "Cabine %@%@ acquitte")
        add("pcc.journal.commandrefused", "Cab %@%@ refused the order %@", "Cabine %@%@ a refusé l'ordre %@")

        // -- why an order was not carried out.
        add("pcc.refusal.notrunning", "The PCC is not running: SET PCC /ENABLE starts it.",
                                    "Le PCC est à l'arrêt : SET PCC /ENABLE le démarre.")
        add("pcc.refusal.noline",   "The PCC is on no line: put it on one of its library first.",
                                    "Le PCC n'est sur aucune ligne : placez-le d'abord sur une ligne de sa bibliothèque.")
        add("pcc.refusal.nosuchrame", "No train %@ on the line: SHOW RAMES lists them.",
                                    "Aucune rame %@ sur la ligne : SHOW RAMES les liste.")
        add("pcc.refusal.notacab",  "Train %@ is not a cab: only a cab takes a message or a call.",
                                    "La rame %@ n'est pas une cabine : seule une cabine reçoit un message ou un appel.")
        add("pcc.refusal.notconnected", "The cab of train %@ is not connected.",
                                    "La cabine de la rame %@ n'est pas connectée.")
        add("pcc.refusal.headway",  "A headway lies between %d and %d seconds.",
                                    "Un intervalle est compris entre %d et %d secondes.")
        add("pcc.refusal.fleet",    "A fleet is %d to %d trains, cabs included, or AUTO.",
                                    "Un parc compte de %d à %d rames, cabines comprises, ou AUTO.")
        add("pcc.refusal.emptymessage", "A message needs words.",          "Un message doit contenir du texte.")
        add("pcc.refusal.longmessage", "A message is %d characters at most: this one is %d.",
                                    "Un message compte %d caractères au plus : celui-ci en compte %d.")
        add("pcc.refusal.emptyname", "A PCC needs a name.",                "Un PCC doit porter un nom.")
        add("pcc.refusal.lineinuse", "A cab is in service on the present line: the PCC changes line only when none is.",
                                    "Une cabine est en service sur la ligne actuelle : le PCC ne change de ligne que lorsqu'aucune ne l'est.")
        add("pcc.refusal.nosuchline", "The library holds no such line.",   "La bibliothèque n'a pas cette ligne.")
        add("pcc.refusal.nosuchline.id", "The library holds no line %@.",  "La bibliothèque n'a pas de ligne %@.")
        add("pcc.refusal.other",    "Refused: %@",                         "Refusé : %@")

        // -- the DCL verbs: what they print.
        add("pcc.err.nolink",       "%PCC-F-NOLINK, the PCC is not attached to this session",
                                    "%PCC-F-NOLINK, le PCC n'est pas rattaché à cette session")
        add("pcc.err.nosuchrame",   "%%PCC-W-NOSUCHRAME, no train %@ on the line: SHOW RAMES lists them",
                                    "%%PCC-W-NOSUCHRAME, aucune rame %@ sur la ligne : SHOW RAMES les liste")
        add("pcc.dryrun",           "%%PCC-I-DRYRUN, would carry out %@ (no change made)",
                                    "%%PCC-I-DRYRUN, exécuterait %@ (aucun changement)")
        add("pcc.dcl.line.id",      "%@ (%@, rev %@)",                     "%@ (%@, rév. %@)")
        add("pcc.dcl.connections",  "%d -- in service: %d, on the line: %d, others: %d",
                                    "%d -- en service : %d, sur la ligne : %d, autres : %d")
        add("pcc.dcl.library",      "%d lines (SHOW LINES)",               "%d lignes (SHOW LIGNES)")
        add("pcc.dcl.library.one",  "1 line (SHOW LINES)",                 "1 ligne (SHOW LIGNES)")
        add("pcc.dcl.lines.title",  "Library of lines: %d held.",          "Bibliothèque de lignes : %d.")
        add("pcc.dcl.lines.on",     "The PCC is on %@ (marked *).",        "Le PCC est sur %@ (marquée *).")
        add("pcc.dcl.lines.onnone", "The PCC is on no line.",              "Le PCC n'est sur aucune ligne.")
        add("pcc.dcl.lines.none",   "(the library is empty)",              "(la bibliothèque est vide)")
        add("pcc.dcl.lines.hint",   "SET LINE /LOAD=id puts the PCC on a line; RUN LIGNE_DIR browses the library.",
                                    "SET LIGNE /CHARGER=id place le PCC sur une ligne ; RUN LIGNE_DIR parcourt la bibliothèque.")
        add("pcc.dcl.track",        "%.1f m a track, %d stations",         "%.1f m par voie, %d stations")
        add("pcc.dcl.trains",       "%d -- %d automatic (%d wanted), cabs: %d",
                                    "%d -- %d automatiques (%d voulues), cabines : %d")
        add("pcc.dcl.stock",        "%.0f m, %.1f km/h, %d places",        "%.0f m, %.1f km/h, %d places")
        add("pcc.dcl.line.hint",    "SHOW LINE /STATIONS lists the stations, /SOURCE says where the data came from; SET LINE gives the orders.",
                                    "SHOW LIGNE /STATIONS liste les stations, /SOURCE indique l'origine des données ; SET LIGNE donne les ordres.")
        add("pcc.dcl.stations.title", "Stations, with the stop on each track (metres from the start of the track):",
                                    "Stations, avec le point d'arrêt sur chaque voie (mètres depuis l'origine de la voie) :")
        add("pcc.dcl.source.yes",   "The package carries the line's source: a Cabine that has not built this line in is sent it.",
                                    "Le paquet contient la source de la ligne : elle est envoyée à toute Cabine qui ne l'a pas intégrée.")
        add("pcc.dcl.source.no",    "The package carries no source: every Cabine has this line built in.",
                                    "Le paquet ne contient pas de source : chaque Cabine a cette ligne intégrée.")
        add("pcc.dcl.rames.title",  "Trains of %@ at %@ by the line's clock:",
                                    "Rames de %@ à %@, heure de la ligne :")
        add("pcc.dcl.rame.title",   "Train %@ of %@ at %@ by the line's clock",
                                    "Rame %@ de %@ à %@, heure de la ligne")
        add("pcc.dcl.cabs.title",   "Cabs in service on %@: %d",           "Cabines en service sur %@ : %d")
        add("pcc.dcl.cabs.hint",    "SHOW RAME number shows one in full; SET RAME number gives it an order; MONITOR CABS follows them live.",
                                    "SHOW RAME numéro en montre une en détail ; SET RAME numéro lui donne un ordre ; MONITOR CABINES les suit en direct.")
        add("pcc.dcl.connections.title", "Connections: %d -- %@",          "Connexions : %d -- %@")
        add("pcc.dcl.journal.title", "Journal -- lines shown: %d of %d",   "Journal -- lignes affichées : %d sur %d")
        add("pcc.dcl.journal.last", "%PCC-W-IVVALUE, /LAST takes a number of lines, 1 or more",
                                    "%PCC-W-IVVALUE, /LAST attend un nombre de lignes, 1 ou plus")
        add("pcc.dcl.status",       "PCC: %@ -- %@ -- trains: %d, cabs: %d", "PCC : %@ -- %@ -- rames : %d, cabines : %d")

        add("pcc.set.onoff",        "%%PCC-W-IVVALUE, usage: /%@=ON or /%@=OFF",
                                    "%%PCC-W-IVVALUE, usage : /%@=ON ou /%@=OFF")
        add("pcc.set.pcc.missqual", "%PCC-W-MISSQUAL, expected /ENABLE, /DISABLE, /LAN= or /NAME= -- see HELP SET PCC",
                                    "%PCC-W-MISSQUAL, attendu : /ENABLE, /DISABLE, /LAN= ou /NAME= -- voir HELP SET PCC")
        add("pcc.set.line.missqual", "%PCC-W-MISSQUAL, expected /LOAD=, /CLOSE, /REREAD, /SERVICE=, /EMERGENCY=, /HEADWAY= or /RAMES= -- see HELP SET LINE",
                                    "%PCC-W-MISSQUAL, attendu : /CHARGER=, /FERMER, /RELIRE, /SERVICE=, /URGENCE=, /INTERVALLE= ou /RAMES= -- voir HELP SET LINE")
        add("pcc.set.rame.missqual", "%PCC-W-MISSQUAL, expected /HOLD, /RELEASE, /BRAKE, /UNBRAKE, /MESSAGE= or /CALL -- see HELP SET RAME",
                                    "%PCC-W-MISSQUAL, attendu : /RETENIR, /LIBERER, /FREINER, /DEFREINER, /MESSAGE= ou /APPELER -- voir HELP SET RAME")
        add("pcc.set.rame.needrame", "%PCC-W-NORAME, name the train by its number: SET RAME number /HOLD ...",
                                    "%PCC-W-NORAME, indiquez la rame par son numéro : SET RAME numéro /RETENIR ...")
        add("pcc.start.usage",      "%PCC-W-MISSPARM, usage: START LINE  or  START RAME number",
                                    "%PCC-W-MISSPARM, usage : START LIGNE  ou  START RAME numéro")
        add("pcc.stop.usage",       "%PCC-W-MISSPARM, usage: STOP LINE  or  STOP RAME number",
                                    "%PCC-W-MISSPARM, usage : STOP LIGNE  ou  STOP RAME numéro")
        add("pcc.set.enabled",      "%PCC-S-ENABLED, PCC enabled: SHOW PCC says where it listens",
                                    "%PCC-S-ENABLED, PCC activé : SHOW PCC indique où il écoute")
        add("pcc.set.disabled",     "%PCC-S-DISABLED, PCC disabled: the cabs were told, and their connections are closed",
                                    "%PCC-S-DISABLED, PCC désactivé : les cabines ont été prévenues, et leurs connexions sont fermées")
        add("pcc.set.lan.on",       "%PCC-S-LAN, the PCC listens on every interface and is advertised by Bonjour",
                                    "%PCC-S-LAN, le PCC écoute sur toutes les interfaces et est annoncé par Bonjour")
        add("pcc.set.lan.off",      "%PCC-S-LAN, the PCC listens on this Mac only (loopback) and is not advertised",
                                    "%PCC-S-LAN, le PCC n'écoute que sur ce Mac (boucle locale) et n'est pas annoncé")
        add("pcc.set.name",         "%%PCC-S-NAME, the PCC is named %@",   "%%PCC-S-NAME, le PCC se nomme %@")
        add("pcc.set.load",         "%%PCC-S-LOAD, the PCC is on %@: its trains are seeded afresh, and every cab follows",
                                    "%%PCC-S-LOAD, le PCC est sur %@ : ses rames sont replacées, et chaque cabine suit")
        add("pcc.set.close",        "%PCC-S-CLOSE, the PCC is on no line: its cabs wait for one",
                                    "%PCC-S-CLOSE, le PCC n'est sur aucune ligne : ses cabines en attendent une")
        add("pcc.set.reread",       "%%PCC-S-REREAD, library read again: %d lines held",
                                    "%%PCC-S-REREAD, bibliothèque relue : %d lignes")
        add("pcc.set.reread.one",   "%PCC-S-REREAD, library read again: 1 line held",
                                    "%PCC-S-REREAD, bibliothèque relue : 1 ligne")
        add("pcc.set.service.on",   "%PCC-S-SERVICE, line service started",
                                    "%PCC-S-SERVICE, service de la ligne démarré")
        add("pcc.set.service.off",  "%PCC-S-SERVICE, line service stopped -- the trains come to a stand where they can",
                                    "%PCC-S-SERVICE, service de la ligne arrêté -- les rames s'immobilisent où elles le peuvent")
        add("pcc.set.emergency.on", "%PCC-S-EMERGENCY, general emergency stop -- every train is braked",
                                    "%PCC-S-EMERGENCY, arrêt d'urgence général -- toutes les rames sont freinées")
        add("pcc.set.emergency.off", "%PCC-S-EMERGENCY, general emergency stop released",
                                    "%PCC-S-EMERGENCY, arrêt d'urgence général levé")
        add("pcc.set.headway",      "%%PCC-S-HEADWAY, headway set to %d s -- the fleet comes to it as trains reach the tails",
                                    "%%PCC-S-HEADWAY, intervalle réglé à %d s -- le parc s'y ajuste quand les rames atteignent les tiroirs")
        add("pcc.set.fleet",        "%%PCC-S-FLEET, fleet fixed at %d trains, cabs included",
                                    "%%PCC-S-FLEET, parc fixé à %d rames, cabines comprises")
        add("pcc.set.fleet.auto",   "%PCC-S-FLEET, fleet sized from the headway again",
                                    "%PCC-S-FLEET, parc de nouveau dimensionné par l'intervalle")
        add("pcc.set.hold",         "%%PCC-S-HOLD, train %@ is held at its platform, or at the next it reaches",
                                    "%%PCC-S-HOLD, la rame %@ est retenue à quai, ou au prochain quai qu'elle atteint")
        add("pcc.set.release",      "%%PCC-S-RELEASE, train %@ is released",
                                    "%%PCC-S-RELEASE, la rame %@ est libérée")
        add("pcc.set.brake",        "%%PCC-S-BRAKE, emergency brake ordered on train %@",
                                    "%%PCC-S-BRAKE, FU commandé sur la rame %@")
        add("pcc.set.unbrake",      "%%PCC-S-UNBRAKE, emergency brake released on train %@",
                                    "%%PCC-S-UNBRAKE, FU relâché sur la rame %@")
        add("pcc.set.message",      "%%PCC-S-MESSAGE, message sent to the cab of train %@",
                                    "%%PCC-S-MESSAGE, message envoyé à la cabine de la rame %@")
        add("pcc.set.call",         "%%PCC-S-CALL, the driver of train %@ is being called",
                                    "%%PCC-S-CALL, appel du conducteur de la rame %@")

        // -- the monitors.
        add("pcc.mon.title.line",   "LINE MONITOR",                        "MONITEUR DE LIGNE")
        add("pcc.mon.title.cabs",   "CAB MONITOR",                         "MONITEUR DES CABINES")
        add("pcc.mon.title.rames",  "TRAIN MONITOR",                       "MONITEUR DES RAMES")
        add("pcc.mon.title.connections", "CONNECTION MONITOR",             "MONITEUR DES CONNEXIONS")
        add("pcc.mon.node",         "Node %@",                             "Nœud %@")
        add("pcc.mon.status",       "%@   Mode: %@   Line clock: %@",      "%@   Mode : %@   Heure ligne : %@")
        add("pcc.mon.noline",       "The PCC is on no line",               "Le PCC n'est sur aucune ligne")
        add("pcc.mon.keys",         "Ctrl/Z Exit   Ctrl/W Refresh",        "Ctrl/Z Quitter   Ctrl/W Rafraîchir")
        add("pcc.mon.interval",     "Interval %@ s",                       "Intervalle %@ s")
        add("pcc.mon.elapsed",      "Elapsed %@",                          "Durée %@")
        add("pcc.mon.noalarm",      "No active alarms",                    "Aucune alarme active")
        add("pcc.mon.lbl.alarms",   "Alarms  %d active, %d unacknowledged", "Alarmes  actives : %d, non acquittées : %d")
        add("pcc.mon.lbl.line.none", "Line",                               "Ligne")
        add("pcc.mon.lbl.cabs",     "Cabs (%d)",                           "Cabines (%d)")
        add("pcc.mon.lbl.cabs.part", "Cabs %d-%d of %d (page %d/%d)",      "Cabines %d-%d sur %d (page %d/%d)")
        add("pcc.mon.lbl.rames",    "Trains (%d)",                         "Rames (%d)")
        add("pcc.mon.lbl.rames.part", "Trains %d-%d of %d (page %d/%d)",   "Rames %d-%d sur %d (page %d/%d)")
        add("pcc.mon.lbl.connections", "Connections (%d)",                 "Connexions (%d)")
        add("pcc.mon.lbl.connections.part", "Connections %d-%d of %d (page %d/%d)",
                                    "Connexions %d-%d sur %d (page %d/%d)")
        add("pcc.mon.legend",       "03> automatic   21» cab   H held   ! braked   · turning back   ╌ tail",
                                    "03> auto   21» cabine   H retenue   ! freinée   · retourn.   ╌ tiroir")
        add("pcc.mon.sum.authority", "%.0f m: %@",                         "%.0f m : %@")
        add("pcc.mon.cab.r1",       "%@   %@   autopilot %@",              "%@   %@   pilote auto %@")
        add("pcc.mon.cab.r2",       "track %d   %.1f m   %.1f km/h   %@   %@",
                                    "voie %d   %.1f m   %.1f km/h   %@   %@")
        add("pcc.mon.cab.r3",       "doors %@",                            "portes %@")
        add("pcc.mon.cab.eb",       "EB %@",                               "FU %@")
        add("pcc.mon.cab.pax",      "pax %@",                              "voy. %@")
        add("pcc.mon.cab.r4",       "authority %@",                        "autorisation %@")
        add("pcc.mon.dryrun",       "%%PCC-S-MONSTART, would start %@ /INTERVAL=%@ (dry-run)",
                                    "%%PCC-S-MONSTART, lancerait %@ /INTERVAL=%@ (essai à blanc)")
        add("pcc.mon.err.interval", "%%PCC-W-IVINTERVAL, invalid interval \\%@\\ (0.25 second minimum)",
                                    "%%PCC-W-IVINTERVAL, intervalle invalide \\%@\\ (0,25 seconde au minimum)")
        add("pcc.mon.exit",         "%%PCC-I-MONEXIT, %@ exited\n",        "%%PCC-I-MONEXIT, %@ : sortie\n")
        add("pcc.mon.interrupt",    "%%PCC-W-INTERRUPT, %@ interrupted by CTRL/Y\n",
                                    "%%PCC-W-INTERRUPT, %@ interrompu par CTRL/Y\n")

        // -- the forms. The labels of a record are padded to one width, so
        //    that its values stand in a column.
        add("pcc.form.rames.title", "TRAINS AND CABS",                     "RAMES ET CABINES")
        add("pcc.form.lines.title", "LINE LIBRARY",                        "BIBLIOTHÈQUE DE LIGNES")
        add("pcc.form.status",      "%@ -- %@ -- %@ -- trains: %d, cabs: %d", "%@ -- %@ -- %@ -- rames : %d, cabines : %d")
        add("pcc.form.rames.who",   "Cab / state",                         "Cabine / état")
        add("pcc.form.rames.count", "%d trains",                           "%d rames")
        add("pcc.form.rames.count.one", "1 train",                         "1 rame")
        add("pcc.form.lines.count", "%d lines",                            "%d lignes")
        add("pcc.form.lines.count.one", "1 line",                          "1 ligne")
        add("pcc.form.find",        "Find:",                               "Chercher :")
        add("pcc.form.nomatch",     "No match.",                           "Aucun résultat.")
        add("pcc.form.none",        "none",                                "aucun")
        add("pcc.form.page",        "page %d/%d -- Tab",                   "page %d/%d -- Tab")
        add("pcc.form.yesno",       "(Y/N)",                               "(O/N)")
        add("pcc.form.cancelled",   "Nothing done.",                       "Rien n'a été fait.")
        add("pcc.form.message",     "Message for train %@:",               "Message pour la rame %@ :")
        add("pcc.form.rames.keys",  "H Hold  R Release  B Brake  U Release EB  M Message  C Call",
                                    "R Retenir  L Libérer  F Freiner  D Défreiner  M Message  A Appeler")
        add("pcc.form.lines.keys",  "L Load the line  C Close the line  R Reread the library",
                                    "C Charger la ligne  F Fermer la ligne  R Relire la bibliothèque")
        add("pcc.form.keys",        "↑↓ Select  0-9 Find  Tab Page  Ctrl/W Repaint  Ctrl/Z Exit",
                                    "↑↓ Choisir  0-9 Chercher  Tab Page  Ctrl/W Repeindre  Ctrl/Z Quitter")
        add("pcc.form.ask.hold",    "Hold train %@ at its next platform?", "Retenir la rame %@ à son prochain quai ?")
        add("pcc.form.ask.release", "Release train %@?",                   "Libérer la rame %@ ?")
        add("pcc.form.ask.brake",   "Order the emergency brake on train %@?", "Commander le FU sur la rame %@ ?")
        add("pcc.form.ask.unbrake", "Release the emergency brake of train %@?", "Relâcher le FU de la rame %@ ?")
        add("pcc.form.ask.message", "Send it to the cab of train %@?",     "L'envoyer à la cabine de la rame %@ ?")
        add("pcc.form.ask.call",    "Call the driver of train %@?",        "Appeler le conducteur de la rame %@ ?")
        add("pcc.form.ask.load",    "Put the PCC on %@?",                  "Placer le PCC sur %@ ?")
        add("pcc.form.ask.close",   "Put the PCC on no line?",             "Laisser le PCC sans ligne ?")
        add("pcc.form.ask.reread",  "Read the library again?",             "Relire la bibliothèque ?")
        add("pcc.form.f.train",     "Train:        ",                      "Rame :         ")
        add("pcc.form.f.track",     "Track:        ",                      "Voie :         ")
        add("pcc.form.f.position",  "Position:     ",                      "Position :     ")
        add("pcc.form.f.speed",     "Speed:        ",                      "Vitesse :      ")
        add("pcc.form.f.state",     "State:        ",                      "État :         ")
        add("pcc.form.f.doors",     "Doors:        ",                      "Portes :       ")
        add("pcc.form.f.station",   "Station:      ",                      "Station :      ")
        add("pcc.form.f.orders",    "PCC orders:   ",                      "Ordres du PCC :")
        add("pcc.form.f.cab",       "Cab:          ",                      "Cabine :       ")
        add("pcc.form.f.link",      "Link:         ",                      "Liaison :      ")
        add("pcc.form.f.driving",   "Driving:      ",                      "Conduite :     ")
        add("pcc.form.f.pax",       "Passengers:   ",                      "Voyageurs :    ")
        add("pcc.form.f.timetable", "Timetable:    ",                      "Horaire :      ")
        add("pcc.form.f.eb",        "Emerg. brake: ",                      "Frein. urg. :  ")
        add("pcc.form.f.authority", "Authority:    ",                      "Autorisation : ")
        add("pcc.form.f.report",    "Last report:  ",                      "Signalement :  ")
        add("pcc.form.f.line",      "Line:      ",                         "Ligne :     ")
        add("pcc.form.f.id",        "Id:        ",                         "Id :        ")
        add("pcc.form.f.rev",       "Revision:  ",                         "Révision :  ")
        add("pcc.form.f.length",    "Length:    ",                         "Longueur :  ")
        add("pcc.form.f.stations",  "Stations:  ",                         "Stations :  ")
        add("pcc.form.f.from",      "From:      ",                         "De :        ")
        add("pcc.form.f.to",        "To:        ",                         "À :         ")
        add("pcc.form.f.source",    "Source:    ",                         "Source :    ")
        add("pcc.form.f.running",   "The PCC:   ",                         "Le PCC :    ")
        add("pcc.form.f.c.track",   "Track:     ",                         "Tracé :     ")
        add("pcc.form.f.c.stations", "Stations:  ",                        "Stations :  ")
        add("pcc.form.f.c.ground",  "Ground:    ",                         "Altimétrie :")
        add("pcc.form.f.c.date",    "Extract:   ",                         "Extraction :")
        add("pcc.form.v.length",    "%.2f km a track",                     "%.2f km par voie")
        add("pcc.form.v.source.yes", "in the package",                     "dans le paquet")
        add("pcc.form.v.source.no", "none: built into every Cabine",       "aucune : intégrée à chaque Cabine")
        add("pcc.form.v.running.yes", "is on this line",                   "est sur cette ligne")
        add("pcc.form.v.running.no", "is not on this line",                "n'est pas sur cette ligne")
    }
}
