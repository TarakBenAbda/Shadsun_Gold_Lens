#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
===============================================================================
 Shadsun Gold Lens — tests du cœur de l'application et de la source Forever AH
 Auteur : Tarak Ben Abda – novembre 2026
-------------------------------------------------------------------------------
 FR : Faux serveur local imitant Forever AH (/v1/houses, /v1/houses/{clé}/market,
      mêmes champs que le vrai site). Vérifie : source sans clé, types de serveur
      et numéros d'HDV, écriture du module (chargé en Lua 5.1), configuration
      sans secret, coffre de la clé, détection de WoW et de la région,
      installation de l'add-on, reprise de l'ancien outil, état des prix,
      vérification du type de serveur avec un relevé du jeu, boucle horaire,
      instance unique.
 EN : Offline tests of the app core and the Forever AH source.
===============================================================================
"""
import gzip
import json
import os
import shutil
import subprocess
import sys
import tempfile
import threading
import time
from http.server import BaseHTTPRequestHandler, HTTPServer

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "tools", "prix_api"))
TMP = tempfile.mkdtemp(prefix="sgl_core_")
os.environ["SGL_DATA_DIR"] = os.path.join(TMP, "appdata")

import sgl_prix_api as E   # noqa: E402
import sgl_core as core    # noqa: E402

RESULTS = []


def _raises(fn):
    try:
        fn()
    except Exception:
        return True
    return False


def check(name, ok, detail=""):
    RESULTS.append((name, bool(ok), detail))


# --- Faux Forever AH ---------------------------------------------------------
HOUSE_IDS = [110, 111, 112, 113, 114, 115, 116, 117, 118, 119, 120, 121, 123, 124, 125]


def house_name(hid):
    if hid in (110, 111, 112, 119, 123):
        return "Alliance Auction House"
    if hid in (113, 114, 115, 120, 124):
        return "Horde Auction House"
    return "Blackwater Auction House"


def price(hid, iid):
    # Les HDV PvP (110/113/116) ont les prix du relevé du jeu ; les autres diffèrent.
    base = {2589: 95, 2592: 300, 2318: 40, 4306: 210, 2770: 55, 2771: 120, 2772: 260, 3576: 90, 2840: 45, 2841: 140,
            2842: 180, 3575: 700}[iid]
    return base if hid in (110, 113, 116) else base + (hid % 7) + 3


SEEN = {"ua": True, "count": 0}


class FakeFAH(BaseHTTPRequestHandler):
    def log_message(self, *a):
        pass

    def send_json(self, obj, code=200):
        raw = gzip.compress(json.dumps(obj).encode())
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Encoding", "gzip")
        self.end_headers()
        self.wfile.write(raw)

    def do_GET(self):
        SEEN["count"] += 1
        if "ShadsunGoldLens" not in self.headers.get("User-Agent", ""):
            SEEN["ua"] = False
        if self.path == "/v1/houses":
            rows = [{"house_key": 33, "region": "eu", "ruleset_id": 2, "house_id": 0, "name": "All Auction Houses",
                     "last_snapshot": "2026-11-24T12:22:57Z", "house_type": "unified"}]
            for i, hid in enumerate(HOUSE_IDS):
                rows.append({"house_key": 18 + i, "region": "eu", "ruleset_id": 2, "house_id": hid, "name": house_name(hid),
                             "last_snapshot": "2026-11-24T12:22:56Z", "house_type": "real"})
            rows.append({"house_key": 99, "region": "us", "ruleset_id": 2, "house_id": 110, "name": "Alliance Auction House",
                         "last_snapshot": "2026-11-24T12:22:56Z", "house_type": "real"})
            return self.send_json(rows)
        if self.path.startswith("/v1/houses/") and self.path.endswith("/market"):
            key = int(self.path.split("/")[3])
            hid = HOUSE_IDS[key - 18] if 18 <= key < 18 + len(HOUSE_IDS) else 110
            rows = []
            for iid in (2589, 2592, 2318, 4306, 2770, 2771, 2772, 3576, 2840, 2841, 2842, 3575):
                p = price(hid, iid)
                rows.append({"item": {"item_id": iid, "name": "Objet %d" % iid, "quality": "COMMON"},
                             "current": {"ts": "2026-11-24T17:23:11Z", "min_unit": p, "p10_unit": p, "median_unit": p + 5,
                                         "mean_unit": p + 9, "quantity": 20 + iid % 7, "listings": 3 + iid % 4},
                             "stats": {"market_value": p + 4, "sold_per_day": 12.5}})
            rows.append({"item": {"item_id": 9999}, "current": {"min_unit": None, "quantity": 0}})   # ligne vide ignorée
            return self.send_json({"house": {"house_id": hid}, "as_of": "2026-11-24T17:23:11Z", "change_window_hours": 24,
                                   "total": len(rows), "rows": rows})
        self.send_json({"error": "not found"}, 404)


srv = HTTPServer(("127.0.0.1", 0), FakeFAH)
threading.Thread(target=srv.serve_forever, daemon=True).start()
E.FAH_BASE = "http://127.0.0.1:%d" % srv.server_address[1]
E.FAH_PAUSE = 0
core.setup_engine()

# --- Types de serveur ----------------------------------------------------------
check("Types de serveur : PvP = 110/113/116, Normal = 111/114/117, JdR = 119/120/121, JdR-PvP = 123/124/125",
      E.houses_for("pvp") == {"A": 110, "H": 113, "N": 116} and E.houses_for("normal") == {"A": 111, "H": 114, "N": 117}
      and E.houses_for("rp") == {"A": 119, "H": 120, "N": 121} and E.houses_for("rppvp") == {"A": 123, "H": 124, "N": 125})
check("Type de serveur d'un HDV (120 → JdR) ; inconnu → None", E.ruleset_of(120) == "rp" and E.ruleset_of(5) is None)
check("Suggestion d'après le nom de royaume du jeu (…Realm6PvP → PvP, …RPPvP → JdR-PvP, …Realm2 → rien)",
      E.suggest_ruleset("CAMWOWEU4Realm6PvP") == "pvp" and E.suggest_ruleset("CAMWOWEU4Realm9RPPvP") == "rppvp"
      and E.suggest_ruleset("CAMWOWEU4Realm2") is None and E.suggest_ruleset("XRealmNormal") == "normal")

# --- Source Forever AH -----------------------------------------------------------
ok, msg = core.test_source({"source": "foreverah", "region": "eu"})
check("Source simple : Forever AH joignable sans clé, 15 HDV EU (HDV « tous » et US ignorés)", ok and "15 HDV" in msg, msg)
check("Forever AH : l'application s'identifie (User-Agent)", SEEN["ua"])
cfg = core.load()
cfg["marche"]["type_marche"] = "pvp"
cfg["source"]["type"] = "foreverah"
addons = os.path.join(TMP, "World of Warcraft", "_forever_", "Interface", "AddOns")
os.makedirs(addons)
cfg["wow"]["addons"] = addons
cfg["app"]["assistant_fait"] = "1"
core.save(cfg)
ecfg = core.engine_config()
check("Configuration du moteur : HDV déduits du type de serveur", E.configured_houses(ecfg) == {"A": 110, "H": 113, "N": 116},
      E.configured_houses(ecfg))
mk = E.ForeverAH(ecfg).market(113)
check("Table du marché : prix unitaire minimum et quantité ; ligne sans prix ignorée",
      mk["items"][2589] == (95, 20 + 2589 % 7) and 9999 not in mk["items"] and len(mk["items"]) == 12, mk["items"].get(2589))
check("Table du marché : date des données (as_of) et nombre d'annonces",
      mk["time"] == E.iso_time("2026-11-24T17:23:11Z") and mk["total"] == sum(3 + i % 4 for i in mk["items"]), mk["time"])
n_before = SEEN["count"]
E.ForeverAH(ecfg).market(113)
check("Table du marché : cache local (pas de nouvelle requête dans les 50 min)", SEEN["count"] == n_before)
code = core.run_update_inline("test")
prix = os.path.join(addons, E.MODULE, "Prix.lua")
check("Mise à jour (source Forever AH) : module écrit, journal « OK »", code == 0 and os.path.isfile(prix)
      and E.journal_runs()[-1]["ok"], E.journal_runs()[-1]["lines"][-5:] if E.journal_runs() else None)
txt = open(prix, encoding="utf-8").read()
check("Module : source « Forever AH » et attribution", 'source = "Forever AH"' in txt and "forever-ah.com" in txt
      and 'rulesetName = "PvP"' in txt)
toc = open(os.path.join(addons, E.MODULE, E.MODULE + ".toc"), encoding="utf-8").read()
check("Module : titre « Shadsun Gold Lens - Prix (Forever AH) »", "Prix (Forever AH)" in toc)
lua = shutil.which("lua5.1") or shutil.which("lua")
if lua:
    r = subprocess.run([lua, "-e", 'dofile(%r); local m = ShadsunGoldLensExternal; local v = m.markets.H.d[2589]; '
                        'print(m.source, m.markets.H.house, math.floor(v / 100000), v %% 100000)' % prix],
                       capture_output=True, text=True)
    check("Module chargé en Lua 5.1 : HDV Horde 113, Étoffe 95 pc", r.stdout.split() == ["Forever", "AH", "113", "95", str(20 + 2589 % 7)],
          r.stdout + r.stderr)
st = core.prices_status(addons)
check("État des prix lu dans le module (source, 3 HDV, annonces)", st and st["source"] == "Forever AH"
      and sorted(st["markets"]) == ["A", "H", "N"] and st["markets"]["A"]["house"] == 110, st)

# --- Vérification du type de serveur avec un relevé du jeu ------------------------
forever = os.path.join(TMP, "World of Warcraft", "_forever_")
sv_dir = os.path.join(forever, "WTF", "Account", "TARAK", "SavedVariables")
os.makedirs(sv_dir)
d = ", ".join("[%d] = %d" % (iid, price(110, iid) * 100000 + 5) for iid in (2589, 2592, 2318, 4306, 2770, 2771, 2772, 3576, 2840, 2841, 2842, 3575))
with open(os.path.join(sv_dir, "ShadsunGoldLens.lua"), "w") as f:
    f.write('ShadsunGoldLensGlobal = { ["markets"] = { ["CAMWOWEU4Realm6PvP"] = { ["A"] = { ["time"] = 1795000000, ["d"] = { %s } } } } }\n' % d)
with open(os.path.join(forever, "WTF", "Config.wtf"), "w") as f:
    f.write('SET portal "EU"\nSET locale "frFR"\n')
logs = []
key, msg = core.verify_market_with_scans(forever, {"source": "foreverah", "region": "eu"}, log=logs.append)
check("Vérification avec le relevé du jeu : PvP reconnu (100 % de prix identiques)", key == "pvp" and "100 %" in msg, (key, msg, logs))
check("Suggestion du type de serveur d'après le royaume du relevé", core.suggest_from_game(forever) == ("pvp", "CAMWOWEU4Realm6PvP"))
check("Région détectée dans WTF\\Config.wtf (EU)", core.detect_region(forever) == "eu")

# --- WoW, add-on, configuration -------------------------------------------------
check("Dossier du jeu, _forever_, Interface ou AddOns → dossier _forever_",
      core.forever_from_any(os.path.join(TMP, "World of Warcraft")) == forever and core.forever_from_any(addons) == forever
      and core.forever_from_any(forever) == forever and core.forever_from_any(TMP) is None)
check("Recherche de WoW Forever (dossiers donnés)", core.find_forever_dirs([os.path.join(TMP, "World of Warcraft")]) == [forever])
v = core.install_addon(addons)
src_v = core.toc_version(core.bundled_addon_dir())
check("Installation de l'add-on livré avec l'application", v == src_v and core.addon_status(addons) == (src_v, src_v), v)
with open(os.path.join(addons, "ShadsunGoldLens", "ancien_fichier.lua"), "w") as f:
    f.write("-- obsolète")
core.install_addon(addons)
check("Mise à jour de l'add-on : ancien dossier remplacé (fichiers obsolètes retirés)",
      not os.path.exists(os.path.join(addons, "ShadsunGoldLens", "ancien_fichier.lua"))
      and not os.path.exists(os.path.join(addons, "ShadsunGoldLens.ancien")))
core.set_secret("ID123", "S3CRET")
cfg = core.load()
cfg["battlenet"]["client_id"] = "ID123"
cfg["battlenet"]["client_secret"] = "ne-doit-pas-etre-ecrit"
core.save(cfg)
raw = open(core.config_path(), encoding="utf-8").read()
check("Configuration : la clé secrète n'est jamais écrite dans le fichier", "S3CRET" not in raw and "ne-doit-pas" not in raw)
e2 = core.engine_config()
check("Configuration du moteur : clé secrète reprise du coffre, en mémoire", e2["battlenet"]["client_secret"] == "S3CRET")
check("Coffre : autre Client ID → pas de secret", core.get_secret("AUTRE") is None)
old_dir = os.path.join(TMP, "ShadsunGoldLens-Prix")
os.makedirs(old_dir)
with open(os.path.join(old_dir, "sgl_prix_api.ini"), "w", encoding="utf-8") as f:
    f.write("[battlenet]\nclient_id = OLDID\nclient_secret = OLDSECRET\n[marche]\nregion = eu\nhdv_alliance = 110\n"
            "hdv_horde = 113\nhdv_neutre = 116\n[wow]\naddons = %s\n" % addons)
old = core.find_old_config([old_dir])
check("Reprise de l'ancien outil : clé, AddOns et type de serveur (110 → PvP)",
      old and old["client_id"] == "OLDID" and old["client_secret"] == "OLDSECRET" and old["type_marche"] == "pvp"
      and old["addons"] == addons, old)
cmd = core.launch_command("--arriere-plan")
check("Commande de relance : script de l'application + option", cmd[-2].endswith("sgl_app.py") and cmd[-1] == "--arriere-plan", cmd)
check("Âge lisible (à l'instant, min, h)", core.ago(time.time()) == "à l'instant" and core.ago(time.time() - 600) == "il y a 10 min"
      and core.ago(time.time() - 3 * 3600 - 300).startswith("il y a 3 h"))
check("Application prête (assistant fait, type de serveur, AddOns)", core.is_ready())

# --- Boucle horaire -------------------------------------------------------------------
runs, events = [], []


def runner(origin):
    runs.append(origin)
    return 0


sch = core.Scheduler(60, runner=runner, on_event=lambda t, d: events.append(t), tick=0.05)
sch.last_ok = time.time()
sch.start()
time.sleep(0.3)
check("Boucle : rien avant l'heure", runs == [])
sch.update_now()
time.sleep(0.3)
check("Boucle : « Mettre à jour maintenant » exécuté une fois, événements début / fin", runs == ["mise à jour manuelle"]
      and events[:2] == ["debut", "fin"], (runs, events))
sch.interval = 1
time.sleep(1.4)
check("Boucle : mise à jour automatique quand l'intervalle est écoulé", "mise à jour horaire" in runs, runs)
sch.enabled = False
n = len(runs)
time.sleep(1.4)
check("Boucle : automatique désactivé → plus de mise à jour", len(runs) == n, runs)
check("Boucle : prochaine mise à jour nulle quand désactivée", sch.next_due == 0)
sch.stop()
fails = []
E_RETRY = E.RETRY
E.RETRY = 0.6
sch2 = core.Scheduler(60, runner=lambda o: fails.append(o) or 1, tick=0.05)
sch2.last_ok = 0
sch2.start()
time.sleep(0.35)
check("Boucle : après un échec, pas de nouvel essai immédiat", len(fails) == 1, fails)
time.sleep(0.6)
check("Boucle : nouvel essai après le délai de reprise", len(fails) >= 2, fails)
sch2.stop()
E.RETRY = E_RETRY

# --- Instance unique -------------------------------------------------------------------
l1 = core.acquire_instance_lock()
code = subprocess.run([sys.executable, "-c", "import sys; sys.path.insert(0, %r); import sgl_core as c; "
                       "print('libre' if c.acquire_instance_lock() else 'pris')" % os.path.join(HERE, "..", "tools", "prix_api")],
                      capture_output=True, text=True, env=dict(os.environ)).stdout.strip()
check("Instance unique : un deuxième lancement trouve le verrou pris", l1 is not None and code == "pris", code)
core.signal_show()
check("Deuxième lancement : signal « afficher » reçu par la première instance", core.take_show_signal() and not core.take_show_signal())

# --- Habillage : images et icône ----------------------------------------------------------
import sgl_theme as TH   # noqa: E402
import sgl_icon         # noqa: E402
miss = [n for n in ("logo.png", "gemme.png", "personnage_appuyee.png", "personnage_marteau_leve.png") if not TH.asset(n)]
check("Images de l'application présentes (logo, gemme, personnage)", not miss, miss)
check("Personnage sur fond transparent", TH.load("personnage_appuyee.png").getchannel("A").getextrema()[0] == 0)
ico = os.path.join(TMP, "test.ico")
sgl_icon.build(ico)
from PIL import Image  # noqa: E402
check("Icône : 7 tailles de 16 à 256 px", Image.open(ico).info.get("sizes") == {(16, 16), (24, 24), (32, 32), (48, 48), (64, 64), (128, 128), (256, 256)})
check("Symboles des HDV et boutons dessinés (tailles demandées)", TH.emblem("H", 56).size == (56, 56) and TH.button(200, 50).size == (200, 50)
      and TH.background(640, 400, 0.5).size == (640, 400))
GFX = ("cadre_etat.png", "cadre_bouton.png", "cadre_panneau.png", "cadre_carte.png", "ornement_coin.png",
       "separateur.png", "embleme_alliance.png", "embleme_horde.png", "embleme_neutre.png", "icone_globe.png",
       "icone_plume.png", "icone_boussole.png", "icone_coffre.png", "icone_griffon.png")
miss = [n for n in GFX if not TH.asset(n)]
check("Éléments graphiques fournis présents (cadres, emblèmes, icônes)", not miss, miss)
try:
    tiny = [TH.button(1, 1).size, TH.button(10, 3, 0.01).size, TH.panel(2, 1, 0.001).size, TH.asset_button(3, 2).size,
            TH.hslice(TH.load("cadre_etat.png"), 2, 2).size, TH.nslice(TH.load("cadre_panneau.png"), 3, 3).size,
            TH.background(4, 4, 0.003).size]
    err = None
except Exception as ex:   # l'erreur « y1 must be greater than or equal to y0 »
    tiny, err = None, ex
check("Dessin à très petite taille : aucune erreur (plantage de l'exe 1.1)", err is None, err)
check("Cadres étirés aux tailles demandées", TH.hslice(TH.load("cadre_etat.png"), 620, 72).size == (620, 72)
      and TH.nslice(TH.load("cadre_panneau.png"), 780, 132).size == (780, 132)
      and TH.asset_button(258, 56, "gold").size == (258, 56))

bar = TH.hslice(TH.load("cadre_etat.png"), 780, 66, fr=(.27, .37, .63, .88))
a_ = bar.getchannel("A").load()
cols_ = [x for x in range(780) if any(a_[x, y] > 128 for y in range(61, 66))]
mid_ = (min(cols_) + max(cols_)) / 2 if cols_ else -1
check("Bandeau d'état : ornement du bas centré (symétrie)", abs(mid_ - 390) <= 3, mid_)

def _top_mid(img, rows):
    a = img.getchannel("A").load()
    cols = [x for x in range(img.width) if any(a[x, y] > 128 for y in range(*rows))]
    return (min(cols) + max(cols)) / 2 if cols else -1
_c = TH.nslice(TH.load("cadre_carte.png"), 248, 186, fx=(.06, .45, .56, .94), fy=(.08, .92))
_p = TH.nslice(TH.load("cadre_panneau.png"), 780, 96, smax=0.2)
check("Cadres des cartes et du panneau : ornement du haut centré (symétrie)",
      abs(_top_mid(_c, (0, 2)) - 124) <= 2 and abs(_top_mid(_p, (0, 3)) - 390) <= 3,
      (_top_mid(_c, (0, 2)), _top_mid(_p, (0, 3))))

# --- construire_exe.bat : structure (le fichier ne peut pas être exécuté ici) ------------
import re  # noqa: E402
bat = open(os.path.join(HERE, "..", "tools", "prix_api", "construire_exe.bat"), encoding="ascii", newline="").read()
lines = [ln.strip() for ln in bat.split("\r\n")]
labels = {ln[1:].lower() for ln in lines if ln.startswith(":") and not ln.startswith("::")}
targets = {t.lower() for t in re.findall(r"goto :(\w+)", bat)}
check("construire_exe.bat : toutes les étiquettes existent, fins de ligne Windows", targets <= labels and "\n" not in bat.replace("\r\n", ""),
      targets - labels)
# Un message d'erreur ne doit jamais suivre directement une commande qui a réussi (bug de la 1.2 initiale).
def _prev(i):
    j = i - 1
    while j >= 0 and lines[j] == "echo.":
        j -= 1
    return lines[j]
bad = [i for i, ln in enumerate(lines) if ln.startswith("echo ERREUR")
       and not (_prev(i).startswith(":") or _prev(i).startswith('if not exist "dist\\ShadsunGoldLens.exe" goto'))]
check("construire_exe.bat : messages d'erreur seulement après une étiquette ou un test", not bad, bad)
check("construire_exe.bat : ferme l'application, met de côté l'exe bloqué, puis fabrique",
      bat.index("taskkill /F /T /IM ShadsunGoldLens.exe") < bat.index("ren \"dist") < bat.index("-m PyInstaller"))

# --- Mises à jour en ligne (faux GitHub) -------------------------------------------
import hashlib  # noqa: E402
import io  # noqa: E402
import zipfile  # noqa: E402


def make_addon_zip(version, evil=False):
    buf = io.BytesIO()
    root = core.bundled_addon_dir()
    with zipfile.ZipFile(buf, "w", zipfile.ZIP_DEFLATED) as z:
        for d, _, files in os.walk(root):
            for fn in files:
                full = os.path.join(d, fn)
                arc = "ShadsunGoldLens/" + os.path.relpath(full, root).replace(os.sep, "/")
                data = open(full, "rb").read()
                if fn == "ShadsunGoldLens.toc":
                    data = re.sub(rb"## Version: \S+", ("## Version: " + version).encode(), data)
                z.writestr(arc, data)
        if evil:
            z.writestr("../../evil.txt", "x")
    return buf.getvalue()


GH = {"calls": 0, "zip": make_addon_zip("9.9.9"), "app": "9.0.0", "sha": None}


class FakeGitHub(BaseHTTPRequestHandler):
    def log_message(self, *a):
        pass

    def do_GET(self):
        base = "http://127.0.0.1:%d" % self.server.server_address[1]
        if self.path.startswith("/repos/"):
            GH["calls"] += 1
            body = json.dumps({"tag_name": "v9.9.9", "html_url": base + "/page", "assets": [
                {"name": "sgl-version.json", "browser_download_url": base + "/dl/sgl-version.json"},
                {"name": "addon.zip", "browser_download_url": base + "/dl/addon.zip"},
                {"name": "ShadsunGoldLens.exe", "browser_download_url": base + "/dl/app.exe"}]}).encode()
        elif self.path == "/dl/sgl-version.json":
            body = json.dumps({"addon": {"version": "9.9.9", "file": "addon.zip",
                                         "sha256": GH["sha"] or hashlib.sha256(GH["zip"]).hexdigest()},
                               "app": {"version": GH["app"], "file": "ShadsunGoldLens.exe", "sha256": "0" * 64}}).encode()
        elif self.path == "/dl/addon.zip":
            body = GH["zip"]
        else:
            self.send_response(404); self.end_headers(); return
        self.send_response(200)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)


gh = HTTPServer(("127.0.0.1", 0), FakeGitHub)
threading.Thread(target=gh.serve_forever, daemon=True).start()
API = "http://127.0.0.1:%d/repos/x/y/releases/latest" % gh.server_address[1]
info = core.online_info(api_url=API)
check("En ligne : dernière version lue (add-on 9.9.9, application 9.0.0, page)",
      info and info["addon"]["version"] == "9.9.9" and info["app"]["version"] == "9.0.0" and info["page"].endswith("/page"), info)
core.online_info(api_url=API)
check("En ligne : une seule vérification par jour (cache)", GH["calls"] == 1, GH["calls"])
core.online_info(api_url=API, now=time.time() + 25 * 3600)
check("En ligne : nouvelle vérification après 24 h", GH["calls"] == 2, GH["calls"])
text, action = core.addon_offer(addons, info)
check("Bandeau : add-on 9.9.9 proposé en ligne", action == "online" and "9.9.9 disponible en ligne" in text, text)
# Empreinte fausse : rien n'est installé
GH["sha"] = "f" * 64
bad = core.fetch_online(API)
try:
    core.install_addon_online(addons, bad)
    err = None
except E.Erreur as ex:
    err = str(ex)
check("Empreinte différente : installation annulée, ancien add-on intact",
      err and "empreinte" in err and core.addon_status(addons)[0] == src_v, err)
GH["sha"] = None
# Archive piégée (chemin « ../ ») refusée
GH["zip"] = make_addon_zip("9.9.9", evil=True)
try:
    core.install_addon_online(addons, core.fetch_online(API))
    err = None
except E.Erreur as ex:
    err = str(ex)
check("Archive avec chemin « ../ » refusée, rien d'écrit hors du dossier",
      err and "chemin inattendu" in err and core.addon_status(addons)[0] == src_v
      and not os.path.exists(os.path.join(TMP, "evil.txt")), err)
# Version annoncée ≠ version de l'archive
GH["zip"] = make_addon_zip("9.9.8")
try:
    core.install_addon_online(addons, core.fetch_online(API))
    err = None
except E.Erreur as ex:
    err = str(ex)
check("Version de l'archive différente de l'annonce : refus", err and "différente" in err, err)
# Installation normale
GH["zip"] = make_addon_zip("9.9.9")
v = core.install_addon_online(addons, core.fetch_online(API))
check("Installation depuis GitHub : add-on 9.9.9 installé, empreinte vérifiée",
      v == "9.9.9" and core.addon_status(addons)[0] == "9.9.9"
      and not os.path.exists(os.path.join(core.data_dir(), "telechargement")), v)
text, action = core.addon_offer(addons, info)
check("Bandeau : ensuite, nouvelle application 9.0.0 signalée (lien de téléchargement)",
      action == "app" and "9.0.0" in text, text)
GH["app"] = core.APP_VERSION
text, action = core.addon_offer(addons, core.fetch_online(API))
check("Bandeau : rien à proposer quand tout est à jour (pas de retour à l'add-on livré, plus ancien)",
      action is None and text == "", text)
check("Adresse non HTTPS refusée", _raises(lambda: core._http_get("http://example.com/x")))
core.install_addon(addons)   # remet l'add-on livré pour la suite
gh.shutdown()

srv.shutdown()
ok = sum(1 for r in RESULTS if r[1])
for name, good, detail in RESULTS:
    print(("OK    " if good else "ÉCHEC ") + name + ("" if good else "  -> " + str(detail)[:400]))
print("Résultat application : %d réussis, %d échoués" % (ok, len(RESULTS) - ok))
sys.exit(0 if ok == len(RESULTS) else 1)
