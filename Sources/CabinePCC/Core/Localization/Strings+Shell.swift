import Foundation

// The strings of the DCL shell's own (in-universe OpenVMS) output, of the
// alarm verbs and the annunciator, and of the windows' chrome. The PCC's
// are in Strings+PCC.swift.
extension Strings {
    static func addShellStrings(to t: inout [String: [Lang: String]]) {
        func add(_ key: String, _ en: String, _ fr: String) {
            t[key] = [.en: en, .fr: fr]
        }

        add("window.control",       "PCC Dispatcher",                      "Régulation PCC")
        add("window.dcl",           "DCL Terminal",                        "Terminal DCL")
        add("menu.newterminal",     "New DCL Terminal",                    "Nouveau terminal DCL")

        add("theme.label",          "DISPLAY",                             "AFFICHAGE")
        add("theme.retro",          "RETRO",                               "RÉTRO")
        add("theme.iso",            "ISA-101",                             "ISA-101")

        add("banner.title",         "PCC — CABINE",                        "PCC — CABINE")
        add("banner.subtitle",      "VSI OpenVMS V9.2-3   TERMINAL VT320", "VSI OpenVMS V9.2-3   TERMINAL VT320")
        add("banner.copyright",     "LPD PCC-CABINE V1.0 — CONTROL CENTRE OF THE CABINE CABS",
                                    "LPD PCC-CABINE V1.0 — POSTE DE COMMANDE DES CABINES CABINE")

        // The second launch of the app on one Mac.
        add("launch.duplicate.title", "Another Cabine PCC is already running",
                                    "Un autre Cabine PCC est déjà lancé")
        add("launch.duplicate.text", "Only one PCC may run on this Mac at a time. The one that is running (pid %d) keeps running; this launch will quit.",
                                    "Un seul PCC peut tourner sur ce Mac à la fois. Celui qui tourne (pid %d) continue ; ce lancement va quitter.")
        add("launch.duplicate.quit", "Quit",                               "Quitter")
        add("launch.duplicate.activate", "Show the One Running",           "Afficher celui qui tourne")

        // OpenVMS login banner: system output, English in both modes.
        add("dcl.banner.welcome",       "Welcome to %@ (TM) Operating System, Version %@",
                                        "Welcome to %@ (TM) Operating System, Version %@")
        add("dcl.banner.onnode",        "on node %@",                          "on node %@")
        add("dcl.banner.lastinter",     "Last interactive login on %@",        "Last interactive login on %@")
        add("dcl.banner.lastnon",       "Last non-interactive login on %@",    "Last non-interactive login on %@")
        add("dcl.banner.shelltag",      "%@ -- PCC OPERATOR SHELL",            "%@ -- PCC OPERATOR SHELL")

        // The layered product's splash, after the banner.
        add("login.lpd.line1",  "LPD PCC-CABINE for OpenVMS x86-64 V1.0",
                                "LPD PCC-CABINE pour OpenVMS x86-64 V1.0")
        add("login.lpd.ctrl",   "Control centre of the Cabine cabs -- line library, moving block, orders",
                                "Poste de commande des cabines Cabine -- bibliothèque de lignes, canton mobile, ordres")
        add("login.lpd.line2",  "Live displays and forms (MONITOR <class> or RUN <image>):",
                                "Affichages et formulaires (MONITOR <classe> ou RUN <image>) :")
        add("login.lpd.monline", "  MONITOR LINE         Mimic board of the line, with the alarms and the cabs",
                                "  MONITOR LIGNE        Tableau synoptique de la ligne, avec alarmes et cabines")
        add("login.lpd.moncabs", "  MONITOR CABS         Every cab: link, driving mode, authority",
                                "  MONITOR CABINES      Chaque cabine : liaison, conduite, autorisation")
        add("login.lpd.ramedir", "  RUN RAME_DIR         Trains and cabs form, with the orders (DECforms)",
                                "  RUN RAME_DIR         Formulaire des rames et cabines, avec les ordres (DECforms)")
        add("login.lpd.lignedir", "  RUN LIGNE_DIR        Line library form (DECforms)",
                                "  RUN LIGNE_DIR        Formulaire de la bibliothèque de lignes (DECforms)")
        add("login.lpd.help",   "Type HELP PCC for a worked example, HELP HINTS for the commands.",
                                "Tapez HELP PCC pour un exemple commenté, HELP HINTS pour les commandes.")

        // The status strip.
        add("status.node",          "NODE",                                "NŒUD")
        add("status.pcc.failed",    "FAILED",                              "EN DÉFAUT")
        add("status.line",          "LINE",                                "LIGNE")
        add("status.rames",         "TRAINS",                              "RAMES")
        add("status.cabs",          "CABS",                                "CABINES")
        add("status.telnet",        "TELNET",                              "TELNET")
        add("status.telnet.none",   "NO SESSION",                          "AUCUNE SESSION")
        add("status.telnet.one",    "1 SESSION",                           "1 SESSION")
        add("status.telnet.many",   "%d SESSIONS",                         "%d SESSIONS")
        add("status.mode",          "MODE",                                "MODE")
        add("status.ready",         "READY",                               "PRÊT")
        add("status.alarms",        "ALARMS",                              "ALARMES")
        add("status.alarms.normal", "NORMAL",                              "NORMAL")
        add("status.alarms.summary","%d ACT / %d UNACK",                   "%d ACT / %d N.ACQ")

        // The SCADA annunciator.
        add("alarm.panel.title",    "SCADA ALARMS",                        "ALARMES SCADA")
        add("alarm.active",         "ACTIVE",                              "ACTIVES")
        add("alarm.unack",          "UNACK",                               "N.ACQ")
        add("alarm.ack",            "ACK",                                 "ACQ")
        add("alarm.ack.all",        "ACK ALL",                             "ACQ TOUT")
        add("alarm.clear.all",      "CLEAR ALL",                           "EFFACER TOUT")
        add("alarm.clear.ack",      "CLEAR ACK",                           "EFFACER ACQ")
        add("alarm.none.active",    "-- no active alarms --",              "-- aucune alarme active --")
        add("alarm.col.id",         "ID",                                  "ID")
        add("alarm.col.sev",        "SEVERITY",                            "GRAVITÉ")
        add("alarm.col.state",      "STATE",                               "ÉTAT")
        add("alarm.col.source",     "SOURCE",                              "SOURCE")
        add("alarm.col.point",      "POINT",                               "POINT")
        add("alarm.col.message",    "MESSAGE",                             "MESSAGE")
        add("alarm.sev.advisory",   "ADVISORY",                            "AVIS")
        add("alarm.sev.minor",      "MINOR",                               "MINEURE")
        add("alarm.sev.major",      "MAJOR",                               "MAJEURE")
        add("alarm.sev.critical",   "CRITICAL",                            "CRITIQUE")
        add("alarm.status.ack",     "ACK",                                 "ACQ")
        add("alarm.status.unack",   "UNACK",                               "N.ACQ")
        add("alarm.status.cleared", "CLEARED",                             "EFFACÉE")
        add("alarm.status.rtn",     "RTN",                                 "RAN")
        add("alarm.status.shlvd",   "SHLVD",                               "SUSP")

        // The foot of the dispatcher, and its overlays.
        add("hint.line",            "E emergency stop · D DCL terminal · L language · T display · ?/F1 help",
                                    "E arrêt d'urgence · D terminal DCL · L langue · T affichage · ?/F1 aide")
        add("hint.lang",            "LANG",                                "LANGUE")
        add("help.title",           "KEYBOARD HELP",                       "AIDE CLAVIER")
        add("help.dismiss",         "Press ESC, ? or click to dismiss",    "Appuyez ESC, ? ou cliquez pour fermer")
        add("help.k.help",          "Show / hide this help",               "Afficher / masquer cette aide")
        add("help.k.lang",          "Switch language (EN / FR)",           "Changer de langue (EN / FR)")
        add("help.k.theme",         "Switch display (retro / ISA-101)",    "Changer d'affichage (rétro / ISA-101)")
        add("help.k.emergency",     "Toggle the general emergency stop",   "Basculer l'arrêt d'urgence général")
        add("help.k.dcl",           "Open a DCL terminal",                 "Ouvrir un terminal DCL")
        add("help.k.quit",          "Quit",                                "Quitter")
        add("help.k.esc",           "Dismiss overlays",                    "Fermer les fenêtres superposées")
        add("credits.title",        "CREDITS",                             "CRÉDITS")
        add("credits.dismiss",      "Click or press ESC to close",         "Cliquez ou appuyez ESC pour fermer")
        add("credits.role.pcc",     "CONTROL CENTRE OF THE CABINE CABS",   "POSTE DE COMMANDE DES CABINES CABINE")
        add("credits.role.retro",   "RETRO UI & OpenVMS DCL SHELL",        "UI RÉTRO & SHELL DCL OpenVMS")
        add("credits.role.data",    "DATA OF THE REAL LINES",              "DONNÉES DES LIGNES RÉELLES")
        add("credits.data.osm",     "Stations, stopping points, distances and speed limits; the track's curves on lignes 1 and 6: OpenStreetMap, © OpenStreetMap contributors, ODbL 1.0.",
                                    "Stations, points d'arrêt, distances et limites de vitesse ; tracé des lignes 1 et 6 : OpenStreetMap, © les contributeurs d'OpenStreetMap, ODbL 1.0.")
        add("credits.data.idfm",    "The track's curves on lignes 4, 11 and 14: Île-de-France Mobilités, Tracés du réseau de transport ferré d'Île-de-France, Licence Ouverte 2.0.",
                                    "Tracé des lignes 4, 11 et 14 : Île-de-France Mobilités, Tracés du réseau de transport ferré d'Île-de-France, Licence Ouverte 2.0.")
        add("credits.data.ign",     "Ground level: IGN, RGE ALTI, Licence Ouverte 2.0.",
                                    "Altimétrie : IGN, RGE ALTI, Licence Ouverte 2.0.")
        add("credits.data.where",   "Each line's own sources and the date of its extract are in the LINE LIBRARY panel, as its package gives them.",
                                    "Les sources propres à chaque ligne et la date de son extraction figurent dans le panneau BIBLIOTHÈQUE DE LIGNES, telles que son paquet les donne.")
        add("credits.role.font",    "TYPEFACE",                            "POLICE")
        add("credits.font.licence", "VT323 by Peter Hull, SIL Open Font License 1.1.",
                                    "VT323 de Peter Hull, SIL Open Font License 1.1.")

        // The alarm verbs of the shell.
        add("dcl.page.more",        "  -- more (%d/%d) -- RETURN for next page, Q to quit --\n",
                                    "  -- suite (%d/%d) -- ENTRÉE page suivante, Q pour quitter --\n")
        add("dcl.ack.nosystem",     "%ACK-W-NOSYSTEM, alarm system not attached",
                                    "%ACK-W-NOSYSTEM, système d'alarmes non attaché")
        add("dcl.ack.missalarm",    "%ACK-W-MISSPARM, usage: ACKNOWLEDGE ALARM {id | ALL} [/CLEAR]",
                                    "%ACK-W-MISSPARM, usage : ACKNOWLEDGE ALARM {id | ALL} [/CLEAR]")
        add("dcl.ack.missid",       "%ACK-W-MISSID, supply an alarm id or ALL",
                                    "%ACK-W-MISSID, précisez un id d'alarme ou ALL")
        add("dcl.ack.invalid",      "%%ACK-W-IVID, invalid alarm id \\%@\\",
                                    "%%ACK-W-IVID, id d'alarme invalide \\%@\\")
        add("dcl.ack.alarm",        "%%ACK-S-ACKED, alarm %@ acknowledged",
                                    "%%ACK-S-ACKED, alarme %@ acquittée")
        add("dcl.ack.alarms.one",   "%ACK-S-ACKED, 1 alarm acknowledged",
                                    "%ACK-S-ACKED, 1 alarme acquittée")
        add("dcl.ack.alarms.many",  "%%ACK-S-ACKED, %d alarms acknowledged",
                                    "%%ACK-S-ACKED, %d alarmes acquittées")
        add("dcl.ack.notfound",     "%%ACK-W-NOTFOUND, no active alarm %@",
                                    "%%ACK-W-NOTFOUND, aucune alarme active %@")
        add("dcl.ack.cleared",      "%%ACK-S-CLEARED, alarm %@ cleared",
                                    "%%ACK-S-CLEARED, alarme %@ effacée")
        add("dcl.ack.cleared.many", "%%ACK-S-CLEARED, events cleared: %d",
                                    "%%ACK-S-CLEARED, événements effacés : %d")
        add("dcl.ack.held",         "%%ACK-W-HELD, alarm %@ is held by its condition: it returns to normal when the condition does",
                                    "%%ACK-W-HELD, l'alarme %@ est maintenue par sa cause : elle revient à la normale avec elle")
        add("dcl.ack.dryrun",       "%%ACK-I-DRYRUN, would carry out %@ (no change made)",
                                    "%%ACK-I-DRYRUN, exécuterait %@ (aucun changement)")
        add("dcl.shelve.missalarm", "%SHELVE-W-MISSPARM, usage: SHELVE ALARM <id>",
                                    "%SHELVE-W-MISSPARM, usage : SHELVE ALARM <id>")
        add("dcl.shelve.missid",    "%SHELVE-W-MISSID, supply an alarm id",
                                    "%SHELVE-W-MISSID, précisez un id d'alarme")
        add("dcl.shelve.ok",        "%%SHELVE-S-SHELVED, alarm %@ shelved (ISA-18.2 SHLVD)",
                                    "%%SHELVE-S-SHELVED, alarme %@ suspendue (ISA-18.2 SHLVD)")
        add("dcl.unshelve.missalarm","%UNSHELVE-W-MISSPARM, usage: UNSHELVE ALARM <id>",
                                    "%UNSHELVE-W-MISSPARM, usage : UNSHELVE ALARM <id>")
        add("dcl.unshelve.missid",  "%UNSHELVE-W-MISSID, supply an alarm id",
                                    "%UNSHELVE-W-MISSID, précisez un id d'alarme")
        add("dcl.unshelve.ok",      "%%UNSHELVE-S-RESTORED, alarm %@ restored to the annunciator",
                                    "%%UNSHELVE-S-RESTORED, alarme %@ rétablie à l'annonciateur")
        add("dcl.alarm.title",      "SCADA alarm journal at %@",           "Journal des alarmes SCADA à %@")
        add("dcl.alarm.title.active","Standing SCADA alarms at %@",        "Alarmes SCADA actives à %@")
        add("dcl.alarm.header",     "  Id    Time                         Severity   State    Source      Point          Message",
                                    "  Id    Heure                        Gravité    État     Source      Point          Message")
        add("dcl.alarm.none",       "  (journal is empty)",                "  (journal vide)")
        add("dcl.alarm.none.active","  (no standing alarms -- SHOW ALARMS/ALL for history)",
                                    "  (aucune alarme active -- SHOW ALARMS/ALL pour l'historique)")
        add("dcl.alarm.ackhint",    "  ACKNOWLEDGE ALARM <id|ALL> [/CLEAR] acknowledges, and clears an event; SHELVE/UNSHELVE manage nuisance alarms.",
                                    "  ACKNOWLEDGE ALARM <id|ALL> [/CLEAR] acquitte, et efface un événement ; SHELVE/UNSHELVE gèrent les alarmes parasites.")
        add("dcl.alarm.allhint",    "  SHOW ALARMS/ALL lists the full journal including cleared history.",
                                    "  SHOW ALARMS/ALL liste le journal complet, historique effacé inclus.")
    }
}
