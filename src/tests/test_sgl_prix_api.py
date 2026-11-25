#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
===============================================================================
 Shadsun Gold Lens — tests de l'outil sgl_prix_api.py (hors ligne)
 Auteur : Tarak Ben Abda – novembre 2026
-------------------------------------------------------------------------------
 FR : Un faux serveur local (127.0.0.1) imite l'authentification Battle.net et
      les routes Forever de l'API (index des HDV, annonces, marchandises).
      Vérifie : jeton, en-têtes, identification des HDV d'après les scans en
      jeu, sens du prix des annonces, versions à suffixe ignorées,
      marchandises, écriture du module et chargement en Lua 5.1.
      Écrit fixtures/ShadsunGoldLens_Prix/ pour les tests de l'add-on.
 EN : Offline tests of the API tool against a local fake server.
===============================================================================
"""
import base64
import gzip
import json
import os
import time
import shutil
import subprocess
import sys
import tempfile
import threading
import email.utils
from http.server import BaseHTTPRequestHandler, HTTPServer
from urllib.parse import urlsplit, parse_qs

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "tools", "prix_api"))
import sgl_prix_api as T  # noqa: E402

RESULTS = []


def check(name, ok, detail=""):
    RESULTS.append((name, bool(ok), detail))


# --- Données factices / fake data -------------------------------------------
A_IDS = [110, 113, 116, 119, 123]
H_IDS = [111, 114, 117, 120, 124]
N_IDS = [112, 115, 118, 121, 125]
LAST_MOD = 1763600000  # horodatage fixe des réponses


def house_auctions(hid):
    """Annonces : HDV 113 (Alliance de « notre » marché) = prix des scans."""
    rank = (A_IDS + H_IDS + N_IDS).index(hid) % 5
    fac = "A" if hid in A_IDS else ("H" if hid in H_IDS else "N")
    base = {"A": 100, "H": 150, "N": 130}[fac] + (0 if rank == 1 else 37 * rank + 11)
    out = []
    aid = hid * 100000
    for i in range(1, 31):
        unit = base * i
        # buyout = prix du lot entier (stack de 4) / buyout is for the whole stack
        out.append({"id": aid + i, "item": {"id": 50000 + i}, "buyout": unit * 4, "quantity": 4, "time_left": "LONG"})
        out.append({"id": aid + 100 + i, "item": {"id": 50000 + i}, "buyout": unit * 5 * 2, "quantity": 2, "time_left": "SHORT"})
    # Arme : version simple 9 pa, variante à suffixe moins chère (ignorée)
    out.append({"id": aid + 900, "item": {"id": 2530}, "buyout": 900, "quantity": 1})
    out.append({"id": aid + 901, "item": {"id": 2530, "bonus_lists": [1234]}, "buyout": 500, "quantity": 1})
    out.append({"id": aid + 902, "item": {"id": 2531, "rand": 77}, "buyout": 400, "quantity": 1})   # variante seule
    out.append({"id": aid + 903, "item": {"id": 2532}, "bid": 100, "quantity": 1})                  # enchère seule
    if fac == "H" and rank == 1:
        out.append({"id": aid + 904, "item": {"id": 7005}, "buyout": 75, "quantity": 1})
    return out


def house_commodities(hid):
    if hid != 113:
        return []
    return [{"id": 1, "item": {"id": 2589}, "quantity": 20, "unit_price": 95},
            {"id": 2, "item": {"id": 2589}, "quantity": 10, "unit_price": 120}]


class Handler(BaseHTTPRequestHandler):
    seen = {"bearer": True, "namespace": True, "locale": True}

    def log_message(self, *a):
        pass

    def send_json(self, obj, code=200):
        raw = gzip.compress(json.dumps(obj).encode())
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Encoding", "gzip")
        self.send_header("Last-Modified", email.utils.formatdate(LAST_MOD, usegmt=True))
        self.end_headers()
        self.wfile.write(raw)

    def do_POST(self):
        auth = self.headers.get("Authorization", "")
        ok = auth == "Basic " + base64.b64encode(b"ID:SECRET").decode()
        length = int(self.headers.get("Content-Length") or 0)
        body = self.rfile.read(length).decode()
        if self.path != "/token" or not ok or "grant_type=client_credentials" not in body:
            self.send_json({"error": "unauthorized"}, 401)
            return
        self.send_json({"access_token": "TOKEN", "token_type": "bearer", "expires_in": 86399})

    def do_GET(self):
        parts = urlsplit(self.path)
        q = parse_qs(parts.query)
        if self.headers.get("Authorization") != "Bearer TOKEN":
            Handler.seen["bearer"] = False
        if q.get("namespace") != ["dynamic-forever-eu"]:
            Handler.seen["namespace"] = False
        if q.get("locale") != ["en_US"]:
            Handler.seen["locale"] = False
        p = parts.path
        if p == "/data/wow/ruleset/index":
            # Comme l'API réelle : l'index ne donne que les identifiants.
            return self.send_json({"rulesets": [{"key": {"href": "x"}, "id": 1}, {"key": {"href": "x"}, "id": 2}]})
        if p in ("/data/wow/ruleset/1", "/data/wow/ruleset/2"):
            rid = int(p.rsplit("/", 1)[1])
            return self.send_json({"id": rid, "name": {1: "PvP", 2: "Normal"}[rid], "status": {"type": "UP"}})
        if p == "/data/wow/ruleset/1/auctions/":
            hs = []
            for hid in sorted(A_IDS + H_IDS + N_IDS):
                nm = "Alliance Auction House" if hid in A_IDS else ("Horde Auction House" if hid in H_IDS else "Blackwater Auction House")
                hs.append({"key": {"href": "http://x/data/wow/ruleset/1/auctions/%d" % hid}, "id": hid, "name": nm})
            return self.send_json({"auctions": hs})
        if p.startswith("/data/wow/ruleset/1/auctions/"):
            rest = p[len("/data/wow/ruleset/1/auctions/"):]
            if rest.endswith("/commodities"):
                hid = int(rest.split("/")[0])
                return self.send_json({"commodities": house_commodities(hid)})
            hid = int(rest)
            host = "http://127.0.0.1:%d" % self.server.server_port
            return self.send_json({"id": hid, "auctions": house_auctions(hid),
                                   "commodities": {"href": host + "/data/wow/ruleset/1/auctions/%d/commodities?namespace=dynamic-forever-eu" % hid}})
        self.send_json({"code": 404}, 404)


def sv_text():
    """SavedVariables simulées : scans Alliance (HDV 113) et neutre (HDV 115)."""
    def d(base):
        return ",".join("[%d] = %d" % (50000 + i, (base * i) * 100000 + 6) for i in range(1, 31))
    return ("ShadsunGoldLensGlobal = {\n [\"schema\"] = 3,\n [\"markets\"] = {\n  [\"Forever\"] = {\n"
            "   [\"A\"] = { [\"time\"] = 1763590000, [\"total\"] = 60, [\"char\"] = \"Aurelia\", [\"d\"] = { %s } },\n"
            "   [\"N\"] = { [\"time\"] = 1763591000, [\"total\"] = 60, [\"char\"] = \"Kael\", [\"d\"] = { %s } },\n"
            "  },\n },\n}\nShadsunGoldLensDB = nil\n") % (d(100), d(130))


def main():
    srv = HTTPServer(("127.0.0.1", 0), Handler)
    port = srv.server_port
    threading.Thread(target=srv.serve_forever, daemon=True).start()
    tmp = tempfile.mkdtemp(prefix="sgl_api_")
    try:
        addons = os.path.join(tmp, "AddOns")
        os.makedirs(os.path.join(addons, "ShadsunGoldLens"))
        with open(os.path.join(addons, "ShadsunGoldLens", "ShadsunGoldLens.toc"), "w", encoding="utf-8") as f:
            f.write("## Interface: 16001\n## Title: x\n")
        sv = os.path.join(tmp, "ShadsunGoldLens.lua")
        with open(sv, "w", encoding="utf-8") as f:
            f.write(sv_text())
        ini = os.path.join(tmp, "sgl_prix_api.ini")
        shutil.copy(os.path.join(HERE, "..", "tools", "prix_api", "sgl_prix_api.exemple.ini"), ini)
        import configparser
        cp = configparser.ConfigParser(interpolation=None)
        cp.read(ini, encoding="utf-8")
        cp["battlenet"]["client_id"] = "ID"
        cp["battlenet"]["client_secret"] = "SECRET"
        cp["battlenet"]["oauth_url"] = "http://127.0.0.1:%d/token" % port
        cp["battlenet"]["api_base"] = "http://127.0.0.1:%d" % port
        cp["wow"]["addons"] = addons
        cp["wow"]["savedvariables"] = sv
        cp["outil"]["dossier_cache"] = os.path.join(tmp, "cache")
        with open(ini, "w", encoding="utf-8") as f:
            cp.write(f)

        T.JOURNAL = os.path.join(tmp, "journal_maj.txt")   # jamais dans le dossier de l'outil

        # 1. test
        rc = T.main(["test", "--config", ini])
        check("Commande « test » : jeton obtenu, 15 HDV listés", rc == 0)
        check("Requêtes : jeton Bearer, espace dynamic-forever-eu, locale en_US",
              Handler.seen["bearer"] and Handler.seen["namespace"] and Handler.seen["locale"], Handler.seen)
        # Clé invalide
        bad = os.path.join(tmp, "bad.ini")
        cp2 = configparser.ConfigParser(interpolation=None)
        cp2.read(ini, encoding="utf-8")
        cp2["battlenet"]["client_secret"] = "FAUX"
        with open(bad, "w", encoding="utf-8") as f:
            cp2.write(f)
        check("Clé invalide : erreur claire (code 1)", T.main(["test", "--config", bad]) == 1)
        # Configuration absente
        check("Fichier .ini absent : erreur claire", T.main(["test", "--config", os.path.join(tmp, "absent.ini")]) == 1)
        # maj avant identification
        check("« maj » sans HDV configuré : erreur claire", T.main(["maj", "--config", ini]) == 1)
        runs = T.journal_runs()
        check("Journal : échec noté avec la raison (mise à jour manuelle)", len(runs) == 1 and runs[0]["ok"] is False
              and runs[0]["origin"] == "mise à jour manuelle" and "Aucun HDV" in (runs[0]["result"] or ""), runs and runs[-1])

        # 2. identifier
        rc = T.main(["identifier", "--config", ini])
        cp3 = configparser.ConfigParser(interpolation=None)
        cp3.read(ini, encoding="utf-8")
        m = cp3["marche"]
        check("Identification : HDV Alliance 113 et neutre 115 d'après vos scans", rc == 0 and m["hdv_alliance"] == "113" and m["hdv_neutre"] == "115",
              dict(m))
        check("Identification : HDV Horde déduit par position (114)", m["hdv_horde"] == "114", m["hdv_horde"])
        check("Identification : prix des annonces = prix du lot entier", m["prix_annonce"] == "total", m["prix_annonce"])
        check("Fichier .ini : clé conservée après l'enregistrement", cp3["battlenet"]["client_id"] == "ID")

        # 3. synthèse
        api = T.Api(T.load_config(ini))
        data113 = api.house_data(113)
        s = T.summarize(data113, "total")
        check("Synthèse : prix unitaire le plus bas (100 pc) et quantité totale (6)", s[50001] == (100, 6), s.get(50001))
        check("Synthèse : variante à suffixe ignorée (version simple 9 pa)", s[2530] == (900, 1), s.get(2530))
        check("Synthèse : objet vendu seulement en variante : absent", 2531 not in s)
        check("Synthèse : enchère sans achat immédiat : absente", 2532 not in s)
        s2, var = T.summarize_full(data113, "total")
        check("Synthèse : variante seule gardée à part, prix « dès » 4 pa (0.14)", var.get(2531) == (400, 1) and 2530 not in var
              and s2 == s, var)
        check("Synthèse : marchandises (prix unitaire 95 pc, 30 en vente)", s[2589] == (95, 30), s.get(2589))
        check("Horodatage : en-tête Last-Modified de l'API", data113["time"] == LAST_MOD, data113["time"])
        check("Cache local réutilisé (fichier présent)", any(n.startswith("hdv_eu_1_113") for n in os.listdir(os.path.join(tmp, "cache"))))

        check("Types de serveur : noms lus sur /ruleset/{id} (PvP, Normal)", api.rulesets() == [(1, "PvP"), (2, "Normal")], api.rulesets())

        # Tâche horaire : définition XML (le Planificateur n'existe que sous Windows)
        import xml.etree.ElementTree as ET
        xml_text = T.build_task_xml(r"C:\ShadsunGoldLens-Prix", "2026-11-21T00:00:00", r"C:\anaconda3\pythonw.exe",
                                    '"C:\\ShadsunGoldLens-Prix\\sgl_prix_api.py" boucle', "PC\\Tarak")
        root = ET.fromstring(xml_text.split("?>", 1)[1])
        ns = {"t": "http://schemas.microsoft.com/windows/2004/02/mit/task"}
        g = lambda path: root.find(path, ns).text
        check("Tâche : boucle horaire résidente lancée par pythonw.exe (sans fenêtre, sans VBScript ni .bat)",
              g("t:Actions/t:Exec/t:Command") == "C:\\anaconda3\\pythonw.exe"
              and g("t:Actions/t:Exec/t:Arguments") == '"C:\\ShadsunGoldLens-Prix\\sgl_prix_api.py" boucle'
              and g("t:Actions/t:Exec/t:WorkingDirectory") == "C:\\ShadsunGoldLens-Prix")
        check("Tâche : 1 min après l'ouverture de VOTRE session (UserId, sans droits admin)",
              g("t:Triggers/t:LogonTrigger/t:UserId") == "PC\\Tarak" and g("t:Triggers/t:LogonTrigger/t:Delay") == "PT1M"
              and g("t:Principals/t:Principal/t:UserId") == "PC\\Tarak")
        check("Tâche : relance horaire de secours (quotidienne, répétée chaque heure pendant 1 jour), plus de déclencheur unique",
              g("t:Triggers/t:CalendarTrigger/t:Repetition/t:Interval") == "PT1H" and g("t:Triggers/t:CalendarTrigger/t:Repetition/t:Duration") == "P1D"
              and g("t:Triggers/t:CalendarTrigger/t:ScheduleByDay/t:DaysInterval") == "1" and root.find("t:Triggers/t:TimeTrigger", ns) is None)
        check("Tâche : boucle sans limite de durée (chaque mise à jour a son propre délai), une seule instance",
              g("t:Settings/t:ExecutionTimeLimit") == "PT0S" and g("t:Settings/t:MultipleInstancesPolicy") == "IgnoreNew")
        x2 = T.build_task_xml(r"C:\T", "2026-11-21T00:00:00", "wscript.exe", '"C:\\T\\maj_cachee.vbs"', "PC\\Tarak")
        check("Repli wscript (une mise à jour par lancement) : limité à 15 min", "<ExecutionTimeLimit>PT15M</ExecutionTimeLimit>" in x2)
        # Choix du programme : pythonw.exe à côté de python.exe, sinon wscript + maj_cachee.vbs
        fake = os.path.join(tmp, "py")
        os.makedirs(fake)
        saved_exe = sys.executable
        try:
            sys.executable = os.path.join(fake, "python.exe")
            c1 = T.task_command(r"C:\Outil")
            open(os.path.join(fake, "pythonw.exe"), "w").close()
            c2 = T.task_command(r"C:\Outil")
        finally:
            sys.executable = saved_exe
        check("Programme de la tâche : wscript + maj_cachee.vbs sans pythonw.exe ; pythonw.exe sinon",
              c1 == ("wscript.exe", '"C:\\Outil\\maj_cachee.vbs"') and c2 == (os.path.join(fake, "pythonw.exe"), '"C:\\Outil\\sgl_prix_api.py" boucle'), (c1, c2))
        check("Codes du Planificateur traduits (0x41303 jamais exécutée, 0x80070002 introuvable)",
              "jamais exécutée" in T.task_result_text(0x41303) and "introuvable" in T.task_result_text(2147942402) and "réussie" in T.task_result_text(0), T.task_result_text(0x41303))
        check("Tâche : aussi sur batterie, rattrapée après veille, priorité normale",
              g("t:Settings/t:DisallowStartIfOnBatteries") == "false" and g("t:Settings/t:StopIfGoingOnBatteries") == "false"
              and g("t:Settings/t:StartWhenAvailable") == "true" and g("t:Settings/t:Priority") == "6")
        check("« planifier » hors Windows : message clair", T.main(["planifier", "--config", ini]) == 1)

        # 4. verifier
        check("Commande « verifier 7005 »", T.main(["verifier", "7005", "--config", ini]) == 0)

        # 5. maj (tranches réduites pour tester le découpage)
        T.CHUNK = 7
        rc = T.main(["maj", "--config", ini])
        out = os.path.join(addons, T.MODULE)
        runs = T.journal_runs()
        check("Journal : mise à jour réussie notée « RÉSULTAT : OK »", runs and runs[-1]["ok"] is True and any("Module écrit" in l for l in runs[-1]["lines"]), runs and runs[-1])
        check("« maj » : module écrit dans AddOns/ShadsunGoldLens_Prix", rc == 0 and os.path.exists(os.path.join(out, "Prix.lua"))
              and os.path.exists(os.path.join(out, "ShadsunGoldLens_Prix.toc")))
        with open(os.path.join(out, "ShadsunGoldLens_Prix.toc"), encoding="utf-8") as f:
            toc = f.read()
        check("TOC : interface du client reprise (16001) et dépendance à l'add-on", "## Interface: 16001" in toc and "## Dependencies: ShadsunGoldLens" in toc)
        lua = shutil.which("lua5.1") or shutil.which("lua")
        if lua:
            prog = (
                "dofile([[%s]]) local x = ShadsunGoldLensExternal "
                "local A, H, N = x.markets.A, x.markets.H, x.markets.N "
                "local n = 0 for _ in pairs(A.d) do n = n + 1 end "
                "print(x.version, x.region, A.house, H.house, N.house, A.d[50001], A.d[2589], H.d[7005], n, A.time, A.v and A.v[2531])"
            ) % os.path.join(out, "Prix.lua")
            res = subprocess.run([lua, "-e", prog], capture_output=True, text=True)
            vals = res.stdout.split()
            check("Prix.lua chargé par Lua 5.1 (tranches multiples)", res.returncode == 0 and len(vals) == 11, res.stderr or res.stdout)
            if len(vals) == 11:
                check("Prix.lua : table v des variantes seules (2531 → 4 pa, 1 en vente)", vals[10] == "40000001", vals[10])
                check("Prix.lua : HDV 113/114/115, valeurs emballées (100 x 100 000 + 6)",
                      vals[2:5] == ["113", "114", "115"] and vals[5] == "10000006" and vals[6] == "9500030" and vals[7] == "7500001", vals)
                check("Prix.lua : 32 objets pour l'Alliance (variante seule et enchère seule exclues), heure de l'API", vals[8] == "32" and vals[9] == str(LAST_MOD), vals)
        else:
            check("Lua 5.1 disponible pour vérifier Prix.lua", False)
        # Tâche planifiée : pythonw.exe n'a pas de console (sys.stdout = None)
        so, se = sys.stdout, sys.stderr
        try:
            sys.stdout = sys.stderr = None
            rc2 = T.main(["maj", "--journal", "--config", ini])
        finally:
            sys.stdout, sys.stderr = so, se
        runs = T.journal_runs()
        check("Sans console (pythonw.exe) : mise à jour faite et notée « tâche planifiée »",
              rc2 == 0 and runs[-1]["origin"] == "tâche planifiée" and runs[-1]["ok"] is True, runs and runs[-1])
        # Erreur inattendue : trace complète dans le journal
        saved_upd = T.cmd_update
        T.cmd_update = lambda cfg, args: 1 / 0
        try:
            rc3 = T.main(["maj", "--journal", "--config", ini])
        finally:
            T.cmd_update = saved_upd
        runs = T.journal_runs()
        check("Erreur inattendue : trace et « RÉSULTAT : ERREUR — ZeroDivisionError » dans le journal",
              rc3 == 1 and runs[-1]["ok"] is False and "ZeroDivisionError" in runs[-1]["result"] and any("Traceback" in l for l in runs[-1]["lines"]), runs and runs[-1])
        T.JOURNAL_MAX = 10
        T.journal_trim()
        with open(T.JOURNAL, encoding="utf-8") as f:
            check("Journal limité (anciennes lignes supprimées)", len(f.readlines()) == 10)
        check("« etat » hors Windows : message clair", T.main(["etat", "--config", ini]) == 1)

        # Téléchargement bloqué ou trop lent : délai, nouvelles tentatives, erreur claire
        class Slow:
            def __init__(self): self.n = 0
            def read(self, size):
                self.n += 1
                return b"x" if self.n < 5 else b""
        saved = (T.REQ_DEADLINE, T.time.sleep, T.urllib.request.urlopen)
        try:
            T.REQ_DEADLINE = -1
            try:
                T.Api(T.load_config(ini))._read(Slow())
                slow_ok = False
            except TimeoutError:
                slow_ok = True
            check("Téléchargement au compte-gouttes : arrêté au délai maximal", slow_ok)
            T.time.sleep = lambda s: None
            calls = []
            def stuck(req, timeout=None):
                calls.append(timeout)
                raise TimeoutError("timed out")
            T.urllib.request.urlopen = stuck
            try:
                T.Api(T.load_config(ini))._open(T.urllib.request.Request("http://127.0.0.1:1/x"), "/x")
                msg = ""
            except T.Erreur as e:
                msg = str(e)
            check("Connexion bloquée : 3 tentatives (45 s sans données chacune), puis erreur claire",
                  len(calls) == 3 and calls[0] == T.NET_TIMEOUT and "Échec après 3 tentatives" in msg and "interrompue" in msg, (calls, msg))
        finally:
            T.REQ_DEADLINE, T.time.sleep, T.urllib.request.urlopen = saved
        # Délai global : une mise à jour bloquée est abandonnée et notée
        import threading as _th
        ev, rec = _th.Event(), []
        saved_exit, saved_wd = T.os._exit, T.WATCHDOG
        try:
            T.WATCHDOG = 0.2
            T.os._exit = lambda c: (rec.append(c), ev.set())
            T.run_logged(lambda: (ev.wait(3), 0)[1], "tâche planifiée")
        finally:
            T.os._exit, T.WATCHDOG = saved_exit, saved_wd
        runs = T.journal_runs()
        check("Délai global (10 min) : mise à jour bloquée abandonnée, « délai global dépassé » au journal",
              rec == [2] and any("RÉSULTAT : ERREUR — délai global dépassé" in l for l in runs[-1]["lines"]), (rec, runs[-1]["lines"][-3:] if runs else None))
        with open(T.JOURNAL, encoding="utf-8") as f:
            check("Journal écrit au fil de l'eau (lisible pendant la mise à jour)", "Python :" in f.read())

        # --- Boucle horaire résidente ---------------------------------------------------
        T.ETAT_BOUCLE = os.path.join(tmp, "boucle_etat.json")
        T.VERROU_BOUCLE = os.path.join(tmp, "boucle.verrou")
        T.DEMANDE_MAJ = os.path.join(tmp, "maj_demandee")
        T.JOURNAL = os.path.join(tmp, "journal_boucle.txt")
        now0 = time.time()
        with open(T.JOURNAL, "w", encoding="utf-8") as f:
            f.write("===== %s · tâche planifiée =====\nRÉSULTAT : OK\n" % time.strftime("%Y-%m-%d %H:%M:%S", time.localtime(now0 - 1800)))

        def simulate(times, results=None):
            """times : horloge de chaque tour ; results : codes des mises à jour."""
            calls, it, res = [], iter(times), list(results or [])
            clock_val = [times[0]]
            def clock():
                return clock_val[0]
            def sleep(_):
                try:
                    clock_val[0] = next(it)
                except StopIteration:
                    pass
            next(it)
            def runner(cfg):
                calls.append(clock_val[0])
                return res.pop(0) if res else 0
            T.cmd_loop(ini, 60, ticks=len(times), sleep=sleep, runner=runner, clock=clock)
            return calls

        # Dernière réussite il y a 30 min : rien avant 60 min, puis une mise à jour, puis attente d'une heure
        c = simulate([now0, now0 + 600, now0 + 1700, now0 + 1830, now0 + 1900, now0 + 5300, now0 + 5450])
        check("Boucle : mise à jour quand l'heure est écoulée (y compris en pleine partie), puis une heure d'attente",
              len(c) == 2 and abs(c[0] - (now0 + 1830)) < 1 and abs(c[1] - (now0 + 5450)) < 1, [round(x - now0) for x in c])
        st = T.loop_state()
        check("Boucle : battement de cœur écrit (prochaine mise à jour, intervalle)", st and st["interval"] == 60 and st["next"] > st["last_ok"], st)
        # Échec : nouvelle tentative 15 min après, pas avant
        with open(T.JOURNAL, "w", encoding="utf-8") as f:
            f.write("")
        c = simulate([now0, now0 + 300, now0 + 600, now0 + 890, now0 + 905, now0 + 935], results=[1, 0])
        check("Boucle : après un échec, nouvelle tentative 15 min plus tard (pas avant)", len(c) == 2 and abs(c[1] - (now0 + 905)) < 1, [round(x - now0) for x in c])
        # Réveil du PC (trou de plus de 5 min) : 90 s d'attente pour le réseau
        with open(T.JOURNAL, "w", encoding="utf-8") as f:
            f.write("===== %s · tâche planifiée =====\nRÉSULTAT : OK\n" % time.strftime("%Y-%m-%d %H:%M:%S", time.localtime(now0)))
        c = simulate([now0, now0 + 30, now0 + 9000, now0 + 9060, now0 + 9100])
        check("Boucle : heure dépassée pendant une veille rattrapée au réveil, après 90 s", len(c) == 1 and abs(c[0] - (now0 + 9100)) < 1, [round(x - now0) for x in c])
        # Demande immédiate (5_Activer…)
        open(T.DEMANDE_MAJ, "w").close()
        c = simulate([now0 + 10, now0 + 40])
        check("Boucle : demande immédiate exécutée tout de suite, signal effacé", len(c) == 1 and not os.path.exists(T.DEMANDE_MAJ))
        # Une seule boucle
        held = T._lock()
        open(T.DEMANDE_MAJ, "w").close()
        c = simulate([now0 + 10, now0 + 40])
        held.close()
        os.remove(T.DEMANDE_MAJ)
        check("Boucle : une deuxième boucle s'arrête aussitôt (verrou)", held is not None and c == [])
        # La boucle lance maj --journal --origine dans un processus séparé
        saved_run = T.subprocess.run
        seen = []
        T.subprocess.run = lambda cmd, **kw: (seen.append((cmd, kw)), type("R", (), {"returncode": 0})())[1]
        try:
            rc4 = T.run_update_process(ini)
        finally:
            T.subprocess.run = saved_run
        check("Boucle : chaque mise à jour dans un processus séparé, avec délai et libellé « mise à jour horaire »",
              rc4 == 0 and seen and seen[0][0][2:6] == ["maj", "--journal", "--origine", "mise à jour horaire"] and seen[0][1]["timeout"] == T.WATCHDOG + 120, seen and seen[0][0])
        # Libellé au journal
        rc5 = T.main(["maj", "--journal", "--origine", "mise à jour horaire", "--config", ini])
        check("Journal : libellé « mise à jour horaire »", rc5 == 0 and T.journal_runs()[-1]["origin"] == "mise à jour horaire")
        fx = os.path.join(HERE, "fixtures", T.MODULE)
        if os.path.exists(fx):
            shutil.rmtree(fx)
        shutil.copytree(out, fx)
    finally:
        srv.shutdown()
        shutil.rmtree(tmp, ignore_errors=True)

    print()
    ok = 0
    for name, passed, detail in RESULTS:
        print(("  OK    " if passed else "  ÉCHEC ") + name + ("" if passed or not detail else "  -> " + str(detail)))
        ok += passed
    print("\nRésultat outil API : %d réussis, %d échoués" % (ok, len(RESULTS) - ok))
    return 0 if ok == len(RESULTS) else 1


if __name__ == "__main__":
    sys.exit(main())
