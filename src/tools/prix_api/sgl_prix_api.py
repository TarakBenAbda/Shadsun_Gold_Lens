#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
===============================================================================
 Shadsun Gold Lens — Prix des hôtels des ventes via l'API officielle Blizzard
 Auteur : Tarak Ben Abda – novembre 2026
 Version : 0.14.0
-------------------------------------------------------------------------------
 FR : Un add-on WoW ne peut pas accéder à Internet. Cet outil, lancé sur
      votre PC, télécharge les annonces des hôtels des ventes de votre marché
      (API Game Data de Blizzard, espace « dynamic-forever-<région> ») et
      écrit le module « ShadsunGoldLens_Prix » dans votre dossier AddOns.
      L'add-on lit ces prix à la connexion ou après /reload.

      Pour chaque objet : prix unitaire le plus bas et quantité totale en
      vente. Pour les objets à variantes (suffixes « … de l'aigle »), seule
      la version simple est retenue, comme dans l'add-on.

      Commandes :
        python sgl_prix_api.py test          vérifie la clé et liste les HDV
        python sgl_prix_api.py identifier    trouve les HDV de votre marché
                                             (compare avec vos scans en jeu)
        python sgl_prix_api.py verifier ID   prix d'un objet dans chaque HDV
        python sgl_prix_api.py maj           met à jour les prix (par défaut)
        python sgl_prix_api.py planifier     mise à jour toutes les heures, sans fenêtre
        python sgl_prix_api.py deplanifier   arrête la mise à jour horaire
        python sgl_prix_api.py etat          état de la mise à jour horaire
                                             (dernière exécution, journal)
        python sgl_prix_api.py boucle        mise à jour horaire résidente (lancée
                                             par la tâche à l'ouverture de session)

      Chaque mise à jour est notée dans journal_maj.txt (date, résultat,
      erreur éventuelle).

      Configuration : sgl_prix_api.ini (copie de sgl_prix_api.exemple.ini).
      Ne partagez jamais votre client_secret.
 EN : Downloads Forever auction data from the official Blizzard API and
      writes the ShadsunGoldLens_Prix data add-on. Standard library only.
 Dépendances / Dependencies : Python 3.8+ (bibliothèque standard uniquement).
===============================================================================
"""
import argparse
import base64
import configparser
import email.utils
import gzip
import http.client
import json
import os
import subprocess
import tempfile
from xml.sax.saxutils import escape as xml_escape
import re
import sys
import time
import threading
import traceback


# Python d'Anaconda lancé sans « conda activate » (tâche planifiée) : les DLL
# de chiffrement (Library\bin) doivent être trouvables avant d'importer
# urllib / ssl. Anaconda Python started outside an activated prompt.
def _anaconda_dlls():
    if os.name != "nt":
        return
    base = os.path.dirname(sys.executable)
    extra = [os.path.join(base, d) for d in ("", "Library\\mingw-w64\\bin", "Library\\usr\\bin", "Library\\bin", "Scripts")]
    extra = [d.rstrip("\\") for d in extra if os.path.isdir(d)]
    os.environ["PATH"] = os.pathsep.join(extra + [os.environ.get("PATH", "")])
    for d in extra:
        try:
            os.add_dll_directory(d)
        except (AttributeError, OSError):
            pass


_anaconda_dlls()

import urllib.error
import urllib.parse
import urllib.request

TOOL_VERSION = "0.16.0"
AUTHOR = "Tarak Ben Abda"
HERE = os.path.dirname(os.path.abspath(__file__))
JOURNAL = os.path.join(HERE, "journal_maj.txt")   # une ligne par étape de chaque mise à jour
JOURNAL_MAX = 600                                  # lignes conservées
NET_TIMEOUT = 45          # s sans aucune donnée reçue : connexion considérée comme bloquée
REQ_DEADLINE = 240        # s au plus pour un téléchargement complet (sinon nouvelle tentative)
ATTEMPTS = 3              # tentatives par téléchargement
WATCHDOG = 600            # s au plus pour une mise à jour complète (tâche planifiée)
ETAT_BOUCLE = os.path.join(HERE, "boucle_etat.json")   # battement de cœur de la boucle horaire
VERROU_BOUCLE = os.path.join(HERE, "boucle.verrou")     # une seule boucle à la fois
DEMANDE_MAJ = os.path.join(HERE, "maj_demandee")       # fichier-signal : mise à jour tout de suite
RETRY = 15 * 60           # s avant une nouvelle tentative après un échec
TICK = 30                 # s entre deux vérifications de la boucle
QBASE = 100000          # valeur = prix x 100 000 + quantité (même format que l'add-on)
PMAX = 999999999
QMAX = QBASE - 1
CHUNK = 20000           # entrées par fonction Lua (limite de constantes de Lua 5.1)
MODULE = "ShadsunGoldLens_Prix"
FACTIONS = ("A", "H", "N")
LABELS = {"A": "HDV Alliance", "H": "HDV Horde", "N": "HDV neutre"}
CFG_KEYS = {"A": "hdv_alliance", "H": "hdv_horde", "N": "hdv_neutre"}
CACHE_ROOT = HERE         # dossier du cache (l'application le place dans %APPDATA%)

# Sources de prix / price sources
SOURCES = {"foreverah": "Forever AH", "blizzard": "API Blizzard"}
FAH_BASE = "https://forever-ah.com"
FAH_PAUSE = 1.1           # s entre deux requêtes à Forever AH (demande du site : ~1 par seconde)
FAH_CREDIT = "Prix : Forever AH (forever-ah.com), données de l'API Battle.net de Blizzard"

# Types de serveur et leurs HDV (Alliance, Horde, neutre). L'identifiant de
# ruleset dans l'URL de l'API ne filtre rien : les 15 HDV sont listés partout,
# il faut donc choisir les HDV par leur numéro (constaté par la communauté et
# vérifié : EU PvP = 110 / 113 / 116).
RULESETS = [
    ("pvp", "PvP", (110, 113, 116)),
    ("normal", "Normal", (111, 114, 117)),
    ("rp", "JdR (RP)", (119, 120, 121)),
    ("rppvp", "JdR-PvP (RP-PvP)", (123, 124, 125)),
    ("autre", "Autre (HDV 112 / 115 / 118)", (112, 115, 118)),
]
REGIONS = [("eu", "Europe"), ("us", "Amériques"), ("kr", "Corée"), ("tw", "Taïwan")]


def houses_for(ruleset_key):
    """HDV {A, H, N} d'un type de serveur, ou None."""
    for key, _, ids in RULESETS:
        if key == ruleset_key:
            return dict(zip(FACTIONS, ids))
    return None


def ruleset_of(house_id):
    for key, _, ids in RULESETS:
        if house_id in ids:
            return key
    return None


def ruleset_label(key):
    for k, label, _ in RULESETS:
        if k == key:
            return label
    return key or "?"


def suggest_ruleset(realm):
    """Type de serveur deviné d'après le nom de royaume du jeu
    (ex. « CAMWOWEU4Realm6PvP » → pvp). None si rien de sûr."""
    m = re.search(r"(rppvp|rp-pvp|pvp|rp|normal|pve)$", (realm or "").strip().lower())
    if not m:
        return None
    return {"rppvp": "rppvp", "rp-pvp": "rppvp", "pvp": "pvp", "rp": "rp", "normal": "normal", "pve": "normal"}[m.group(1)]


def banner():
    line = "=" * 70
    print(line)
    print(" Shadsun Gold Lens — prix des HDV v" + TOOL_VERSION)
    print(" Auteur : " + AUTHOR)
    print(line)


class Erreur(Exception):
    """Erreur affichée simplement à l'utilisateur / user-facing error."""


# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------
DEFAULTS = {
    "battlenet": {"client_id": "", "client_secret": "",
                  "oauth_url": "https://oauth.battle.net/token",
                  "api_base": "https://{region}.api.blizzard.com"},
    "marche": {"region": "eu", "type_serveur": "PvP", "ruleset_api": "1",
               "hdv_alliance": "", "hdv_horde": "", "hdv_neutre": "",
               "prix_annonce": "auto", "namespace": "dynamic-forever-{region}"},
    "wow": {"addons": "", "savedvariables": "", "serveur": ""},
    "outil": {"cache_minutes": "50", "dossier_cache": "cache"},
    "source": {"type": "blizzard"},
}


def load_config(path):
    cfg = configparser.ConfigParser(interpolation=None)
    for sec, vals in DEFAULTS.items():
        cfg[sec] = dict(vals)
    if not os.path.exists(path):
        raise Erreur("Fichier de configuration introuvable : %s\n"
                     "Copiez sgl_prix_api.exemple.ini en sgl_prix_api.ini et remplissez-le (voir GUIDE-API.md)." % path)
    with open(path, encoding="utf-8-sig") as f:
        cfg.read_file(f)
    return cfg


def save_hdv(path, mapping, mode):
    """Écrit les identifiants d'HDV trouvés dans le fichier .ini en conservant le reste."""
    with open(path, encoding="utf-8-sig") as f:
        text = f.read()
    values = {CFG_KEYS[k]: str(v) for k, v in mapping.items() if v}
    if mode:
        values["prix_annonce"] = mode
    for key, val in values.items():
        pat = re.compile(r"^(\s*%s\s*=).*$" % re.escape(key), re.M)
        if pat.search(text):
            text = pat.sub(lambda m: m.group(1) + " " + val, text, count=1)
        else:
            text = re.sub(r"(\[marche\][^\n]*\n)", lambda m: m.group(1) + "%s = %s\n" % (key, val), text, count=1)
    with open(path, "w", encoding="utf-8") as f:
        f.write(text)


# ---------------------------------------------------------------------------
# Accès à l'API / API access
# ---------------------------------------------------------------------------
class Http:
    """Téléchargements robustes communs aux deux sources (délais, tentatives)."""

    def _read(self, r):
        """Lit la réponse par blocs : délai maximal par téléchargement, même
        si le serveur envoie au compte-gouttes. Chunked read with a deadline."""
        start, parts = time.time(), []
        while True:
            chunk = r.read(262144)
            if not chunk:
                break
            parts.append(chunk)
            if time.time() - start > REQ_DEADLINE:
                raise TimeoutError("téléchargement trop lent (plus de %d s)" % REQ_DEADLINE)
        return b"".join(parts)

    attempts = None   # None : ATTEMPTS (les indicateurs facultatifs n'essaient qu'une fois)

    def _open(self, req, what):
        last = ""
        tries = self.attempts or ATTEMPTS
        for attempt in range(1, tries + 1):
            if attempt > 1:
                print("  nouvelle tentative %d/%d (%s)…" % (attempt, tries, last), flush=True)
                time.sleep(3 * attempt)
            try:
                with urllib.request.urlopen(req, timeout=NET_TIMEOUT) as r:
                    data = self._read(r)
                    if r.headers.get("Content-Encoding", "").lower() == "gzip":
                        data = gzip.decompress(data)
                    return data, r.headers
            except urllib.error.HTTPError as e:
                if e.code == 401:
                    raise Erreur("Clé refusée (401) : vérifiez client_id et client_secret.")
                if e.code == 404:
                    raise Erreur("Introuvable (404) : %s" % what)
                if e.code in (429, 500, 502, 503, 504):
                    last = "erreur HTTP %d" % e.code
                    continue
                raise Erreur("Erreur HTTP %d pour %s" % (e.code, what))
            except urllib.error.URLError as e:
                last = "connexion impossible : %s" % e.reason
            except (TimeoutError, OSError, http.client.HTTPException) as e:
                last = "connexion interrompue : %s" % (e or type(e).__name__)
        raise Erreur("Échec après %d %s (%s) : %s" % (tries, "tentatives" if tries > 1 else "tentative", last, what))



class Api(Http):
    """API officielle Blizzard (clé de développeur)."""
    def __init__(self, cfg):
        b, m = cfg["battlenet"], cfg["marche"]
        self.client_id = b.get("client_id", "").strip()
        self.client_secret = b.get("client_secret", "").strip()
        if not self.client_id or not self.client_secret:
            raise Erreur("client_id et client_secret manquants dans sgl_prix_api.ini (voir GUIDE-API.md, étape 2).")
        self.region = m.get("region", "eu").strip().lower()
        self.base = b.get("api_base").replace("{region}", self.region).rstrip("/")
        self.oauth = b.get("oauth_url")
        self.namespace = m.get("namespace").replace("{region}", self.region)
        self.ruleset = m.get("ruleset_api", "1").strip() or "1"
        self.token = None
        self.cache_dir = os.path.join(CACHE_ROOT, cfg["outil"].get("dossier_cache", "cache"))
        self.cache_minutes = float(cfg["outil"].get("cache_minutes", "50") or 0)

    def get_token(self):
        if self.token:
            return self.token
        auth = base64.b64encode(("%s:%s" % (self.client_id, self.client_secret)).encode()).decode()
        req = urllib.request.Request(self.oauth, data=b"grant_type=client_credentials", method="POST",
                                     headers={"Authorization": "Basic " + auth,
                                              "Content-Type": "application/x-www-form-urlencoded"})
        data, _ = self._open(req, "jeton d'accès")
        tok = json.loads(data.decode("utf-8")).get("access_token")
        if not tok:
            raise Erreur("Réponse inattendue du serveur d'authentification.")
        self.token = tok
        return tok

    def get(self, path, locale="en_US"):
        """GET JSON. Retourne (objet, horodatage Last-Modified ou None)."""
        url = path if path.startswith("http") else self.base + path
        parts = urllib.parse.urlsplit(url)
        q = dict(urllib.parse.parse_qsl(parts.query))
        q.setdefault("namespace", self.namespace)
        q.setdefault("locale", locale)
        url = urllib.parse.urlunsplit((parts.scheme, parts.netloc, parts.path, urllib.parse.urlencode(q), ""))
        req = urllib.request.Request(url, headers={"Authorization": "Bearer " + self.get_token(),
                                                   "Accept-Encoding": "gzip", "User-Agent": "ShadsunGoldLens/" + TOOL_VERSION})
        data, headers = self._open(req, parts.path)
        lm = headers.get("Last-Modified")
        ts = None
        if lm:
            try:
                ts = int(email.utils.parsedate_to_datetime(lm).timestamp())
            except (TypeError, ValueError):
                ts = None
        return json.loads(data), ts

    # --- HDV -----------------------------------------------------------------
    def rulesets(self):
        """Types de serveur : l'index ne donne que les identifiants, le nom
        vient de /data/wow/ruleset/{id}. Ruleset names from the detail route."""
        obj, _ = self.get("/data/wow/ruleset/index")
        out = []
        for key in ("rulesets", "ruleset", "results"):
            for r in obj.get(key) or []:
                if isinstance(r, dict) and "id" in r:
                    nm = name_of(r.get("name")) or name_of((r.get("type") or {}).get("name") if isinstance(r.get("type"), dict) else None)
                    if not nm:
                        try:
                            det, _ = self.get("/data/wow/ruleset/%s" % r["id"])
                            nm = name_of(det.get("name")) or name_of((det.get("type") or {}).get("name")
                                                                      if isinstance(det.get("type"), dict) else det.get("type"))
                        except Erreur:
                            nm = ""
                    out.append((r["id"], nm or "?"))
        return out

    def houses(self):
        obj, _ = self.get("/data/wow/ruleset/%s/auctions/" % self.ruleset)
        found = []
        for val in obj.values():
            if isinstance(val, list):
                for h in val:
                    if isinstance(h, dict) and "id" in h:
                        nm = name_of(h.get("name"))
                        found.append({"id": int(h["id"]), "name": nm, "faction": faction_of(nm)})
        found.sort(key=lambda h: h["id"])
        return found

    def house_data(self, hid):
        """Annonces et marchandises d'un HDV (avec cache local de quelques minutes)."""
        cache = os.path.join(self.cache_dir, "hdv_%s_%s_%d.json.gz" % (self.region, self.ruleset, hid))
        if self.cache_minutes > 0 and os.path.exists(cache) and time.time() - os.path.getmtime(cache) < self.cache_minutes * 60:
            with gzip.open(cache, "rt", encoding="utf-8") as f:
                return json.load(f)
        obj, ts = self.get("/data/wow/ruleset/%s/auctions/%d" % (self.ruleset, hid))
        auctions = obj.get("auctions") if isinstance(obj.get("auctions"), list) else []
        commodities = []
        com = obj.get("commodities")
        if isinstance(com, list):
            commodities = com
        elif isinstance(com, dict):
            href = (com.get("href") or (com.get("key") or {}).get("href"))
            if href:
                try:
                    cobj, cts = self.get(href)
                    commodities = cobj.get("commodities") or cobj.get("auctions") or []
                    ts = max(ts or 0, cts or 0) or ts
                except Erreur:
                    commodities = []
        out = {"id": hid, "time": ts or int(time.time()), "auctions": auctions, "commodities": commodities}
        os.makedirs(self.cache_dir, exist_ok=True)
        with gzip.open(cache, "wt", encoding="utf-8") as f:
            json.dump(out, f)
        return out


class ForeverAH(Http):
    """Prix de Forever AH (forever-ah.com) : API publique, sans clé ni compte.
    Les données viennent de l'API Battle.net ; le site demande d'environ une
    requête par seconde et de citer « Forever AH » et l'API Battle.net.
    Une seule requête par HDV renvoie toute la table du marché."""

    def __init__(self, cfg, base=None):
        self.region = cfg["marche"].get("region", "eu").strip().lower() or "eu"
        self.base = (base or cfg["source"].get("url", "") or FAH_BASE).rstrip("/")
        self.cache_dir = os.path.join(CACHE_ROOT, cfg["outil"].get("dossier_cache", "cache"))
        self.cache_minutes = float(cfg["outil"].get("cache_minutes", "50") or 0)
        self._houses = None
        self._last = 0.0

    def _get(self, path):
        wait = FAH_PAUSE - (time.time() - self._last)
        if wait > 0:
            time.sleep(wait)
        req = urllib.request.Request(self.base + path, headers={
            "Accept": "application/json", "Accept-Encoding": "gzip",
            "User-Agent": "ShadsunGoldLens/%s (+add-on WoW Forever)" % TOOL_VERSION})
        try:
            data, _ = self._open(req, "Forever AH " + path)
        finally:
            self._last = time.time()
        try:
            return json.loads(data)
        except ValueError:
            raise Erreur("Réponse illisible de Forever AH pour %s (site en maintenance ?)." % path)

    def houses(self):
        """HDV réels de la région : [{id, key, name, faction, snapshot}]."""
        if self._houses is None:
            rows = self._get("/v1/houses")
            if isinstance(rows, dict):
                rows = rows.get("houses") or rows.get("rows") or []
            out = []
            for h in rows if isinstance(rows, list) else []:
                if not isinstance(h, dict) or str(h.get("region", "")).lower() != self.region:
                    continue
                if h.get("house_type", "real") != "real" or not h.get("house_id"):
                    continue
                nm = str(h.get("name") or "")
                out.append({"id": int(h["house_id"]), "key": h.get("house_key"), "name": nm,
                            "faction": faction_of(nm), "snapshot": h.get("last_snapshot")})
            out.sort(key=lambda x: x["id"])
            self._houses = out
        return self._houses

    def market(self, hid):
        """Table du marché d'un HDV : {time, total, items {id: (prix unitaire min, quantité)}}."""
        cache = os.path.join(self.cache_dir, "fah_%s_%d.json.gz" % (self.region, hid))
        if self.cache_minutes > 0 and os.path.exists(cache) and time.time() - os.path.getmtime(cache) < self.cache_minutes * 60:
            with gzip.open(cache, "rt", encoding="utf-8") as f:
                out = json.load(f)
            out["items"] = {int(k): tuple(v) for k, v in out["items"].items()}
            out["stats"] = {int(k): tuple(v) for k, v in (out.get("stats") or {}).items()}
            return out
        key = None
        for h in self.houses():
            if h["id"] == hid:
                key = h["key"]
        if key is None:
            raise Erreur("HDV %d absent de Forever AH pour la région %s." % (hid, self.region.upper()))
        obj = self._get("/v1/houses/%s/market" % key)
        rows = obj.get("rows") if isinstance(obj, dict) else None
        if not isinstance(rows, list):
            raise Erreur("Réponse inattendue de Forever AH (pas de table « rows ») pour l'HDV %d." % hid)
        items, total, newest, stats = {}, 0, 0, {}
        for r in rows:
            it, cur = r.get("item") or {}, r.get("current") or {}
            iid, unit = it.get("item_id"), cur.get("min_unit")
            # Indicateurs Forever AH : valeur habituelle (market_value, moyenne
            # pondérée sur 14 jours du 10e centile) et ventes estimées par jour.
            st = r.get("stats") or {}
            mv, spd = st.get("market_value"), st.get("sold_per_day")
            if isinstance(iid, int) and (isinstance(mv, (int, float)) or isinstance(spd, (int, float))):
                mv = int(round(mv)) if isinstance(mv, (int, float)) and mv > 0 else 0
                spd = int(round(spd * 10)) if isinstance(spd, (int, float)) and spd > 0 else 0
                if mv or spd:
                    stats[iid] = (mv, spd)
            if not isinstance(iid, int) or not isinstance(unit, (int, float)) or unit <= 0:
                continue
            qty = int(cur.get("quantity") or 0)
            items[iid] = (int(round(unit)), qty)
            total += int(cur.get("listings") or qty or 0)
            newest = max(newest, iso_time(cur.get("ts")))
        if isinstance(obj.get("total"), int) and obj["total"] > len(rows):
            print("  (Forever AH : %d lignes reçues sur %d annoncées)" % (len(rows), obj["total"]))
        when = iso_time(obj.get("as_of")) or newest or int(time.time())
        out = {"time": when, "total": total, "items": items, "stats": stats}
        os.makedirs(self.cache_dir, exist_ok=True)
        with gzip.open(cache, "wt", encoding="utf-8") as f:
            json.dump({"time": when, "total": total, "items": {str(k): v for k, v in items.items()},
                       "stats": {str(k): v for k, v in stats.items()}}, f)
        return out


def iso_time(v):
    """« 2026-11-24T17:23:11Z » → horodatage Unix (0 si illisible)."""
    if not isinstance(v, str) or not v:
        return 0
    try:
        import datetime
        return int(datetime.datetime.fromisoformat(v.replace("Z", "+00:00")).timestamp())
    except ValueError:
        return 0


def source_of(cfg):
    t = cfg["source"].get("type", "blizzard").strip().lower() if cfg.has_section("source") else "blizzard"
    return t if t in SOURCES else "blizzard"


def configured_houses(cfg):
    """HDV à télécharger : numéros du .ini, sinon ceux du type de serveur."""
    m = cfg["marche"]
    ids = {k: m.get(CFG_KEYS[k], "").strip() for k in FACTIONS}
    if not any(ids.values()):
        auto = houses_for(m.get("type_marche", "").strip().lower())
        if auto:
            ids = {k: str(v) for k, v in auto.items()}
    return {k: int(v) for k, v in ids.items() if v and v.isdigit()}


def fetch_market(cfg, hid, api=None, mode="total"):
    """Table {time, total, items} d'un HDV, quelle que soit la source."""
    if source_of(cfg) == "foreverah":
        api = api or ForeverAH(cfg)
        return api.market(hid)
    api = api or Api(cfg)
    data = api.house_data(hid)
    items, variants = summarize_full(data, mode)
    return {"time": data["time"], "total": len(data.get("auctions") or []) + len(data.get("commodities") or []),
            "items": items, "variants": variants}


def fetch_stats(cfg, ids, fah=None, log=print):
    """Indicateurs de marché (valeur habituelle, ventes par jour) de Forever AH
    pour chaque HDV configuré, quelle que soit la source des prix : 1 requête
    par HDV, gratuite. Facultatif : en cas d'échec, les prix restent publiés
    sans indicateurs. Retourne {clé: {objet: (valeur habituelle, ventes×10)}}."""
    out = {}
    try:
        fah = fah or ForeverAH(dict_cfg_for_fah(cfg))
        fah.attempts = 1
    except Exception as e:
        log("  (indicateurs Forever AH indisponibles : %s)" % e)
        return out
    for key, hid in ids.items():
        try:
            out[key] = fah.market(hid).get("stats") or {}
        except Exception as e:
            log("  (indicateurs Forever AH indisponibles pour l'HDV %d : %s)" % (hid, e))
            if "connexion" in str(e):
                break    # site injoignable : inutile d'essayer les autres HDV
    return out


def dict_cfg_for_fah(cfg):
    """Configuration pour Forever AH quand la source des prix est Blizzard :
    même région et même cache, adresse Forever AH par défaut."""
    c = configparser.ConfigParser()
    c.read_dict({s: dict(cfg[s]) for s in cfg.sections()})
    if not c.has_section("source"):
        c.add_section("source")
    if source_of(cfg) != "foreverah":
        c["source"]["url"] = ""
    return c


# ---------------------------------------------------------------------------
# Historique local des prix (SQLite) / local price history
#   Une ligne par HDV, objet et relevé (heure des données). Relevés horaires
#   gardés HISTORY_HOURLY_DAYS jours, puis résumés par jour (prix min, moyen,
#   quantité max). Sert plus tard aux courbes, à la volatilité, au score.
# ---------------------------------------------------------------------------
HISTORY_FILE = "historique.sqlite"
HISTORY_HOURLY_DAYS = 14


def history_path(cfg=None):
    """Dans le dossier du cache (celui de l'application : %APPDATA%\\ShadsunGoldLens\\cache)."""
    sub = cfg["outil"].get("dossier_cache", "cache") if cfg is not None and cfg.has_section("outil") else "cache"
    return os.path.join(CACHE_ROOT, sub, HISTORY_FILE)


def record_history(markets, path=None, now=None):
    """Ajoute les relevés de la mise à jour ; retourne le nombre de lignes ajoutées."""
    import sqlite3
    path = path or history_path()
    now = int(now or time.time())
    os.makedirs(os.path.dirname(path), exist_ok=True)
    con = sqlite3.connect(path, timeout=30)
    try:
        con.executescript(
            "CREATE TABLE IF NOT EXISTS relevés (hdv INTEGER, objet INTEGER, t INTEGER, prix INTEGER, qte INTEGER,"
            " PRIMARY KEY (hdv, objet, t)) WITHOUT ROWID;"
            "CREATE TABLE IF NOT EXISTS jours (hdv INTEGER, objet INTEGER, jour INTEGER, prix_min INTEGER, prix_moyen INTEGER,"
            " qte_max INTEGER, n INTEGER, PRIMARY KEY (hdv, objet, jour)) WITHOUT ROWID;")
        added = 0
        for key, m in markets.items():
            hid, t = int(m["house"]), int(m["time"])
            rows = [(hid, int(i), t, int(v[0]), int(v[1])) for i, v in m["items"].items()]
            cur = con.executemany("INSERT OR IGNORE INTO relevés VALUES (?,?,?,?,?)", rows)
            added += cur.rowcount if cur.rowcount and cur.rowcount > 0 else 0
        # Relevés anciens → résumé par jour (jour = nombre de jours depuis 1970, UTC)
        limit = now - HISTORY_HOURLY_DAYS * 86400
        con.execute(
            "INSERT OR REPLACE INTO jours SELECT hdv, objet, t / 86400, MIN(prix), CAST(AVG(prix) AS INTEGER), MAX(qte), COUNT(*)"
            " FROM relevés WHERE t < ? GROUP BY hdv, objet, t / 86400", (limit,))
        con.execute("DELETE FROM relevés WHERE t < ?", (limit,))
        con.commit()
        return added
    finally:
        con.close()


def match_rulesets(own, fetch, factions=None, log=print):
    """Compare un scan du jeu ({A|H|N: {items}}) aux HDV de chaque type de
    serveur. fetch(hid) → {id: (prix, qté)}. Retourne [(score, clé, objets communs)]
    trié du meilleur au moins bon."""
    out = []
    for key, label, ids in RULESETS:
        houses = dict(zip(FACTIONS, ids))
        scores, commons = [], 0
        for fac, data in own.items():
            if factions and fac not in factions:
                continue
            if fac not in houses or not data.get("items"):
                continue
            sc, common = match_score(data["items"], fetch(houses[fac]))
            if common >= 10:
                scores.append(sc)
                commons += common
        if scores:
            score = sum(scores) / len(scores)
            log("  %-28s : %5.1f %% de prix identiques (%d objets communs)" % (label, score * 100, commons))
            out.append((score, key, commons))
    out.sort(reverse=True)
    return out


def name_of(v):
    if isinstance(v, dict):
        return v.get("en_US") or v.get("fr_FR") or next(iter(v.values()), "")
    return v or ""


def faction_of(name):
    n = (name or "").lower()
    if "alliance" in n:
        return "A"
    if "horde" in n:
        return "H"
    if "blackwater" in n or "neutral" in n or "neutre" in n:
        return "N"
    return "?"


# ---------------------------------------------------------------------------
# Synthèse des annonces / listing summary
# ---------------------------------------------------------------------------
def is_variant(item):
    """Version à suffixe (« … de l'aigle ») : enchantement aléatoire ou bonus."""
    if not isinstance(item, dict):
        return False
    if item.get("rand") not in (None, 0):
        return True
    return bool(item.get("bonus_lists"))


def summarize(data, mode):
    """Prix des versions simples seulement (voir summarize_full)."""
    return summarize_full(data, mode)[0]


def summarize_full(data, mode):
    """Retourne {itemID: (prix unitaire le plus bas, quantité)}.
    mode « total » : buyout = prix du lot entier ; « unite » : prix par unité.
    Pour un objet vendu en versions simple et à suffixe, seules les annonces
    de la version simple comptent (l'objet est ignoré s'il n'en a aucune)."""
    plain, any_plain, variant_seen, variants = {}, set(), set(), {}
    for a in data.get("auctions") or []:
        item = a.get("item") or {}
        iid = item.get("id")
        qty = int(a.get("quantity") or 1)
        if not iid or qty <= 0:
            continue
        if is_variant(item):
            variant_seen.add(iid)
            # Prix « dès » des variantes, gardé à part (objets sans version simple).
            vp = a.get("buyout")
            if vp is not None:
                vu = float(vp) / qty if mode == "total" else float(vp)
                cur = variants.get(iid)
                variants[iid] = [vu, qty] if cur is None else [min(cur[0], vu), cur[1] + qty]
            continue
        any_plain.add(iid)
        price = a.get("buyout")
        if price is None:
            price = a.get("unit_price")
            unit = float(price) if price is not None else None
        else:
            unit = float(price) / qty if mode == "total" else float(price)
        cur = plain.get(iid)
        if unit is None:
            if cur is None:
                plain[iid] = [None, qty]
            else:
                cur[1] += qty
            continue
        if cur is None:
            plain[iid] = [unit, qty]
        else:
            cur[0] = unit if cur[0] is None else min(cur[0], unit)
            cur[1] += qty
    for c in data.get("commodities") or []:
        item = c.get("item") or {}
        iid = item.get("id")
        qty = int(c.get("quantity") or 0)
        up = c.get("unit_price")
        if not iid or qty <= 0 or up is None:
            continue
        cur = plain.get(iid)
        if cur is None:
            plain[iid] = [float(up), qty]
        else:
            cur[0] = float(up) if cur[0] is None else min(cur[0], float(up))
            cur[1] += qty
    out = {}
    for iid, (unit, qty) in plain.items():
        if unit is None:
            continue   # enchères sans achat immédiat uniquement / bid-only
        out[int(iid)] = (min(PMAX, int(unit + 0.5)), min(QMAX, qty))
    var = {int(i): (min(PMAX, int(u + 0.5)), min(QMAX, q)) for i, (u, q) in variants.items() if int(i) not in out}
    return out, var


def pack(unit, qty):
    return unit * QBASE + qty


# ---------------------------------------------------------------------------
# Lecture des scans en jeu (SavedVariables) / reading in-game scans
# ---------------------------------------------------------------------------
class LuaParser:
    _num = re.compile(r"-?(?:0[xX][0-9a-fA-F]+|\d+\.?\d*(?:[eE][-+]?\d+)?|\.\d+(?:[eE][-+]?\d+)?)")
    _ident = re.compile(r"[A-Za-z_][A-Za-z0-9_]*")

    def __init__(self, text):
        self.s, self.i, self.n = text, 0, len(text)

    def error(self, msg):
        raise ValueError("Lua ligne %d : %s" % (self.s.count("\n", 0, self.i) + 1, msg))

    def ws(self):
        s, n = self.s, self.n
        while self.i < n:
            c = s[self.i]
            if c in " \t\r\n,;":
                self.i += 1
            elif s.startswith("--[[", self.i):
                j = s.find("]]", self.i + 4)
                self.i = n if j < 0 else j + 2
            elif s.startswith("--", self.i):
                j = s.find("\n", self.i)
                self.i = n if j < 0 else j + 1
            else:
                break

    def peek(self):
        self.ws()
        return self.s[self.i] if self.i < self.n else ""

    def string(self):
        q = self.s[self.i]
        if q == "[":
            m = re.match(r"\[(=*)\[", self.s[self.i:])
            close = "]" + m.group(1) + "]"
            start = self.i + len(m.group(0))
            j = self.s.find(close, start)
            self.i = j + len(close)
            return self.s[start:j]
        self.i += 1
        out = []
        while self.i < self.n:
            c = self.s[self.i]
            if c == "\\":
                nx = self.s[self.i + 1]
                if nx.isdigit():
                    m = re.match(r"\d{1,3}", self.s[self.i + 1:])
                    out.append(chr(int(m.group(0))))
                    self.i += 1 + len(m.group(0))
                    continue
                out.append({"n": "\n", "t": "\t"}.get(nx, nx))
                self.i += 2
                continue
            if c == q:
                self.i += 1
                return "".join(out)
            out.append(c)
            self.i += 1
        self.error("chaîne non terminée")

    def value(self):
        c = self.peek()
        if c == "{":
            return self.table()
        if c in "\"'" or (c == "[" and re.match(r"\[=*\[", self.s[self.i:])):
            return self.string()
        m = self._num.match(self.s, self.i)
        if m:
            self.i = m.end()
            t = m.group(0)
            if t.lower().startswith(("0x", "-0x")):
                return int(t, 16)
            v = float(t)
            return int(v) if v.is_integer() else v
        m = self._ident.match(self.s, self.i)
        if m:
            self.i = m.end()
            return {"true": True, "false": False, "nil": None}.get(m.group(0))
        self.error("caractère inattendu %r" % c)

    def table(self):
        self.i += 1
        arr, hsh = [], {}
        while True:
            c = self.peek()
            if c == "}":
                self.i += 1
                break
            if c == "[" and not re.match(r"\[=*\[", self.s[self.i:]):
                self.i += 1
                k = self.value()
                if self.peek() != "]":
                    self.error("] attendu")
                self.i += 1
                if self.peek() != "=":
                    self.error("= attendu")
                self.i += 1
                hsh[k] = self.value()
                continue
            m = self._ident.match(self.s, self.i)
            if m and m.group(0) not in ("true", "false", "nil"):
                save = self.i
                self.i = m.end()
                if self.peek() == "=" and not self.s.startswith("==", self.i):
                    self.i += 1
                    hsh[m.group(0)] = self.value()
                    continue
                self.i = save
            arr.append(self.value())
        if hsh and not arr:
            return hsh
        if not hsh:
            return arr
        for idx, v in enumerate(arr, 1):
            hsh[idx] = v
        return hsh


def read_scans(path, realm=""):
    """Scans de l'add-on : {serveur: {"A"/"H"/"N": {"time", "items": {id: (prix, qté)}}}}."""
    if not path or not os.path.exists(path):
        raise Erreur("Fichier SavedVariables introuvable : %s\n(paramètre « savedvariables » de la section [wow])" % path)
    with open(path, encoding="utf-8", errors="replace") as f:
        text = f.read()
    m = re.search(r"^ShadsunGoldLensGlobal\s*=\s*", text, re.M)
    if not m:
        raise Erreur("ShadsunGoldLensGlobal absent de %s : connectez-vous au moins une fois avec l'add-on." % path)
    p = LuaParser(text)
    p.i = m.end()
    g = p.value() or {}
    out = {}
    for rname, markets in (g.get("markets") or {}).items():
        if realm and rname != realm:
            continue
        for key, snap in (markets or {}).items():
            d = (snap or {}).get("d") or {}
            items = {}
            for iid, v in d.items():
                if isinstance(iid, int) and isinstance(v, (int, float)):
                    v = int(v)
                    items[iid] = ((v - v % QBASE) // QBASE, v % QBASE)
            if items:
                out.setdefault(rname, {})[key] = {"time": snap.get("time"), "items": items}
    return out


def match_score(own, api):
    """Part des objets communs dont le prix le plus bas est identique."""
    common = [i for i in own if i in api]
    if not common:
        return 0.0, 0
    same = sum(1 for i in common if own[i][0] == api[i][0])
    return same / len(common), len(common)


# ---------------------------------------------------------------------------
# Écriture du module d'add-on / writing the data add-on
# ---------------------------------------------------------------------------
def addon_interface(addons):
    toc = os.path.join(addons, "ShadsunGoldLens", "ShadsunGoldLens.toc")
    try:
        with open(toc, encoding="utf-8-sig") as f:
            m = re.search(r"^##\s*Interface:\s*([\d, ]+)", f.read(), re.M)
            if m:
                return m.group(1).strip()
    except OSError:
        pass
    return "16001"


def write_module(outdir, interface, meta, markets):
    os.makedirs(outdir, exist_ok=True)
    src = meta.get("source", "API Blizzard")
    toc = ("## Interface: %s\n## Title: Shadsun Gold Lens - Prix (%s)\n"
           "## Notes: Prix des hôtels des ventes téléchargés hors du jeu par l'application Shadsun Gold Lens.\n"
           "## Author: Shadsun\n## Version: %s\n## Dependencies: ShadsunGoldLens\n\nPrix.lua\n") % (interface, src, TOOL_VERSION)
    with open(os.path.join(outdir, MODULE + ".toc"), "w", encoding="utf-8", newline="\r\n") as f:
        f.write(toc)
    has_stats = any((markets.get(k) or {}).get("stats") for k in FACTIONS)
    lines = [
        "-- Shadsun Gold Lens — prix des HDV (%s)" % src + (" — " + FAH_CREDIT if (src == SOURCES["foreverah"] or has_stats) else ""),
        "-- Généré par sgl_prix_api.py %s le %s. Ne pas modifier : relancez l'outil." % (
            TOOL_VERSION, time.strftime("%Y-%m-%d %H:%M", time.localtime(meta["generated"]))),
        "-- Auteur de l'outil : Tarak Ben Abda – novembre 2026",
        "ShadsunGoldLensExternal = { version = 1, generated = %d, source = %s, region = %s, rulesetName = %s, markets = {}%s }" % (
            meta["generated"], lua_str(src), lua_str(meta["region"]), lua_str(meta["ruleset"]),
            ", statsSource = \"Forever AH\"" if has_stats else ""),
        "local function S(t, s) for k, v in pairs(s) do t[k] = v end end",
    ]
    for key in FACTIONS:
        m = markets.get(key)
        if not m:
            continue
        lines.append("do local d = {}")
        lines.append("ShadsunGoldLensExternal.markets.%s = { time = %d, total = %d, house = %d, d = d }" % (
            key, m["time"], m["total"], m["house"]))
        ids = sorted(m["items"])
        for start in range(0, len(ids), CHUNK):
            part = ids[start:start + CHUNK]
            body = ",".join("[%d]=%d" % (i, pack(*m["items"][i])) for i in part)
            # Une fonction par tranche : chaque fonction a sa propre table de constantes.
            lines.append("S(d, (function() return {%s} end)())" % body)
        st = m.get("stats") or {}
        if st:
            # Indicateurs Forever AH : valeur = valeur habituelle × QBASE + ventes par jour × 10.
            lines.append("local s = {}; ShadsunGoldLensExternal.markets.%s.s = s" % key)
            sids = sorted(st)
            for start in range(0, len(sids), CHUNK):
                body = ",".join("[%d]=%d" % (i, pack(*st[i])) for i in sids[start:start + CHUNK])
                lines.append("S(s, (function() return {%s} end)())" % body)
        var = m.get("variants") or {}
        if var:
            # Objets vendus seulement en variantes (suffixe, bonus) : prix « dès ».
            lines.append("local v = {}; ShadsunGoldLensExternal.markets.%s.v = v" % key)
            vids = sorted(var)
            for start in range(0, len(vids), CHUNK):
                body = ",".join("[%d]=%d" % (i, pack(*var[i])) for i in vids[start:start + CHUNK])
                lines.append("S(v, (function() return {%s} end)())" % body)
        lines.append("end")
    with open(os.path.join(outdir, "Prix.lua"), "w", encoding="utf-8", newline="\n") as f:
        f.write("\n".join(lines) + "\n")


def lua_str(s):
    return '"' + str(s).replace("\\", "\\\\").replace('"', '\\"') + '"'


# ---------------------------------------------------------------------------
# Commandes / commands
# ---------------------------------------------------------------------------
def cmd_test(cfg, args):
    if source_of(cfg) == "foreverah":
        fah = ForeverAH(cfg)
        hs = fah.houses()
        if not hs:
            raise Erreur("Forever AH ne liste aucun HDV pour la région %s." % fah.region.upper())
        print("Forever AH joignable : %d HDV pour la région %s." % (len(hs), fah.region.upper()))
        for h in hs:
            print("  %4d  %-28s  %s  (%s)" % (h["id"], h["name"], ruleset_label(ruleset_of(h["id"])), h["snapshot"] or "?"))
        return 0
    api = Api(cfg)
    api.get_token()
    print("Clé acceptée : jeton d'accès obtenu.")
    try:
        rs = api.rulesets()
        if rs:
            print("Types de serveur : " + ", ".join("%s = %s" % (i, n) for i, n in rs))
    except Erreur as e:
        print("Types de serveur indisponibles (%s)." % e)
    hs = api.houses()
    print("Hôtels des ventes (%s, %s) :" % (api.region.upper(), api.namespace))
    for h in hs:
        print("  %4d  %-28s  %s" % (h["id"], h["name"], LABELS.get(h["faction"], "?")))
    conf = {k: cfg["marche"].get(CFG_KEYS[k], "") for k in FACTIONS}
    if any(conf.values()):
        print("Configurés : " + ", ".join("%s = %s" % (LABELS[k], conf[k] or "-") for k in FACTIONS))
    else:
        print("Étape suivante : python sgl_prix_api.py identifier")
    return 0


def cmd_identify(cfg, args, cfg_path):
    api = Api(cfg)
    scans = read_scans(cfg["wow"].get("savedvariables", "").strip(), cfg["wow"].get("serveur", "").strip())
    if not scans:
        raise Erreur("Aucun scan dans vos SavedVariables : lisez les annonces en jeu (HDV de faction et/ou neutre), "
                     "déconnectez-vous (sauvegarde), puis relancez.")
    realm = max(scans, key=lambda r: sum(len(v["items"]) for v in scans[r].values()))
    own = scans[realm]
    print("Scans utilisés : serveur « %s » — %s" % (realm, ", ".join(
        "%s (%d objets)" % (LABELS.get(k, k), len(v["items"])) for k, v in sorted(own.items()))))
    houses = api.houses()
    by_fac = {k: [h for h in houses if h["faction"] == k] for k in FACTIONS}
    found, modes, best_index = {}, {}, {}
    for key in ("A", "H", "N"):
        if key not in own:
            continue
        print("\nComparaison avec votre scan %s :" % LABELS[key])
        best = None
        for idx, h in enumerate(by_fac[key]):
            data = api.house_data(h["id"])
            for mode in ("total", "unite"):
                score, common = match_score(own[key]["items"], summarize(data, mode))
                print("  HDV %4d  prix %-5s : %5.1f %% identiques sur %d objets communs" % (h["id"], mode, score * 100, common))
                if common >= 20 and (best is None or score > best[0]):
                    best = (score, h["id"], mode, idx, common)
        if best and best[0] >= 0.25:
            found[key], modes[key], best_index[key] = best[1], best[2], best[3]
            print("  => %s = HDV %d (%.0f %% de prix identiques)" % (LABELS[key], best[1], best[0] * 100))
        else:
            print("  => aucun HDV ne correspond nettement (scan trop ancien ou trop petit ?)")
    # Les HDV des autres faction(s) : même rang que l'HDV identifié.
    ranks = set(best_index.values())
    if not found:
        raise Erreur("Identification impossible. Utilisez « verifier <ID d'objet> » et renseignez les HDV à la main.")
    if len(ranks) > 1:
        print("\nAttention : rangs différents selon la faction (%s). Vérifiez avec « verifier »." % best_index)
    rank = sorted(ranks)[0]
    for key in FACTIONS:
        if key not in found and rank < len(by_fac[key]):
            found[key] = by_fac[key][rank]["id"]
            print("%s déduit par position : HDV %d (à confirmer avec « verifier »)." % (LABELS[key], found[key]))
    mode = None
    if modes:
        vals = list(modes.values())
        mode = max(set(vals), key=vals.count)
        print("Prix des annonces : « %s »." % ("prix du lot entier" if mode == "total" else "prix par unité"))
    save_hdv(cfg_path, found, mode)
    print("\nEnregistré dans %s. Étape suivante : python sgl_prix_api.py maj" % os.path.basename(cfg_path))
    return 0


def cmd_verify(cfg, args):
    api = Api(cfg)
    mode = cfg["marche"].get("prix_annonce", "auto")
    mode = "total" if mode not in ("total", "unite") else mode
    iid = int(args.objet)
    print("Objet %d — prix unitaire le plus bas et quantité dans chaque HDV :" % iid)
    for h in api.houses():
        res = summarize(api.house_data(h["id"]), mode).get(iid)
        txt = money(res[0]) + " (%d en vente)" % res[1] if res else "-"
        print("  %4d  %-14s  %s" % (h["id"], LABELS.get(h["faction"], "?"), txt))
    return 0


def money(c):
    g, s, cu = c // 10000, (c // 100) % 100, c % 100
    parts = []
    if g:
        parts.append("%d po" % g)
    if s or g:
        parts.append("%d pa" % s)
    parts.append("%d pc" % cu)
    return " ".join(parts)


def cmd_update(cfg, args):
    src = source_of(cfg)
    m = cfg["marche"]
    ids = configured_houses(cfg)
    if not ids:
        raise Erreur("Aucun HDV configuré : choisissez votre type de serveur dans l'application "
                     "(ou lancez « python sgl_prix_api.py identifier »).")
    mode = m.get("prix_annonce", "auto").strip()
    if mode not in ("total", "unite"):
        mode = "total"
    addons = args.sortie and os.path.dirname(os.path.abspath(args.sortie)) or cfg["wow"].get("addons", "").strip()
    outdir = args.sortie or os.path.join(addons, MODULE)
    if not args.sortie and (not addons or not os.path.isdir(addons)):
        raise Erreur("Dossier AddOns introuvable : « %s » (paramètre « addons » de la section [wow])." % addons)
    api = ForeverAH(cfg) if src == "foreverah" else Api(cfg)
    print("Source : %s" % SOURCES[src] + (" — " + FAH_CREDIT if src == "foreverah" else ""), flush=True)
    markets = {}
    for key in FACTIONS:
        if key not in ids:
            continue
        hid = ids[key]
        print("Téléchargement %s (HDV %d)…" % (LABELS[key], hid), flush=True)
        t0 = time.time()
        mk = fetch_market(cfg, hid, api, mode)
        markets[key] = {"time": mk["time"], "total": mk["total"], "house": hid, "items": mk["items"], "variants": mk.get("variants") or {}}
        print("  %d annonces, %d objets, données du %s (%d s)" % (mk["total"], len(mk["items"]),
                                                                time.strftime("%d/%m %H:%M", time.localtime(mk["time"])), time.time() - t0), flush=True)
        del mk   # libère la mémoire avant l'HDV suivant / free memory
    # Indicateurs (ventes par jour, valeur habituelle) : Forever AH, même si les prix viennent de Blizzard
    if cfg["outil"].get("indicateurs", "1").strip() != "0":
        stats = {}
        if src == "foreverah":
            for key in markets:
                stats[key] = api.market(markets[key]["house"]).get("stats") or {}
        else:
            print("Indicateurs de marché (Forever AH)…", flush=True)
            stats = fetch_stats(cfg, {k: markets[k]["house"] for k in markets})
        for key, st in stats.items():
            if key in markets and st:
                markets[key]["stats"] = st
        n = sum(len(markets[k].get("stats") or {}) for k in markets)
        print("  %d objets avec ventes par jour et valeur habituelle" % n if n else "  aucun indicateur reçu", flush=True)
    rs = ruleset_of(next(iter(ids.values())))
    meta = {"generated": int(time.time()), "region": m.get("region", "eu").strip().lower() or "eu",
            "ruleset": ruleset_label(rs) if rs else m.get("type_serveur", ""), "source": SOURCES[src]}
    write_module(outdir, addon_interface(addons) if addons else "16001", meta, markets)
    print("Module écrit : %s" % outdir)
    # Historique local (pour les courbes et analyses futures) : jamais bloquant.
    if cfg["outil"].get("historique", "1").strip() != "0":
        try:
            n = record_history(markets, history_path(cfg))
            print("Historique local : %d relevés ajoutés (%s)" % (n, history_path(cfg)))
        except Exception as e:
            print("  (historique local non enregistré : %s)" % e)
    print("En jeu : /reload (ou reconnectez-vous). Vérifiez le module « Shadsun Gold Lens - Prix » dans la liste des add-ons.")
    return 0


# ---------------------------------------------------------------------------
# Mise à jour horaire (Planificateur de tâches Windows) / hourly scheduling
# ---------------------------------------------------------------------------
TASK_NAME = "Shadsun Gold Lens - prix HDV"


def task_command(folder):
    """Commande lancée par la tâche : pythonw.exe (Python sans fenêtre) avec le
    script, sinon wscript + maj_cachee.vbs. Returns (command, arguments)."""
    folder = folder.rstrip("\\/")
    script = folder + "\\sgl_prix_api.py"
    exe = sys.executable or ""
    pyw = os.path.join(os.path.dirname(exe), "pythonw.exe") if exe else ""
    if pyw and os.path.exists(pyw):
        return pyw, '"%s" boucle' % script
    return "wscript.exe", '"%s"' % (folder + "\\maj_cachee.vbs")


def build_task_xml(folder, start=None, command=None, arguments=None, user=None):
    """Définition de la tâche.
    - Programme : la boucle horaire résidente (pythonw.exe … boucle), sans
      fenêtre : c'est elle qui compte les heures, y compris pendant une
      session de jeu, et qui rattrape une heure manquée au réveil du PC.
    - Déclencheurs : 1 minute après l'ouverture de votre session, et chaque
      heure (relance la boucle si elle s'est arrêtée ; ignoré sinon).
    - Une seule instance, aussi sur batterie, sans limite de durée pour la
      boucle (chaque mise à jour a son propre délai de 10 minutes)."""
    start = start or time.strftime("%Y-%m-%dT00:00:00")
    folder = folder.rstrip("\\/")
    if command is None:
        command, arguments = task_command(folder)
    resident = " boucle" in (arguments or "")
    if user is None:
        name, dom = os.environ.get("USERNAME", ""), os.environ.get("USERDOMAIN", "")
        user = (dom + "\\" + name) if (name and dom) else name
    logon = user_tag = ""
    if user:
        # Déclencheur à l'ouverture de VOTRE session (sans droits administrateur)
        logon = ("    <LogonTrigger>\n      <Enabled>true</Enabled>\n      <UserId>%s</UserId>\n"
                 "      <Delay>PT1M</Delay>\n    </LogonTrigger>\n" % xml_escape(user))
        user_tag = "      <UserId>%s</UserId>\n" % xml_escape(user)
    limit = "PT0S" if resident else "PT15M"
    return """<?xml version="1.0" encoding="UTF-16"?>
<Task version="1.2" xmlns="http://schemas.microsoft.com/windows/2004/02/mit/task">
  <RegistrationInfo>
    <Author>Shadsun Gold Lens</Author>
    <Description>Shadsun Gold Lens : prix des hôtels des ventes (API Blizzard), mis à jour toutes les heures.</Description>
  </RegistrationInfo>
  <Triggers>
{logon}    <CalendarTrigger>
      <Repetition>
        <Interval>PT1H</Interval>
        <Duration>P1D</Duration>
        <StopAtDurationEnd>false</StopAtDurationEnd>
      </Repetition>
      <StartBoundary>{start}</StartBoundary>
      <Enabled>true</Enabled>
      <ScheduleByDay>
        <DaysInterval>1</DaysInterval>
      </ScheduleByDay>
    </CalendarTrigger>
  </Triggers>
  <Principals>
    <Principal id="Author">
{user}      <LogonType>InteractiveToken</LogonType>
      <RunLevel>LeastPrivilege</RunLevel>
    </Principal>
  </Principals>
  <Settings>
    <MultipleInstancesPolicy>IgnoreNew</MultipleInstancesPolicy>
    <DisallowStartIfOnBatteries>false</DisallowStartIfOnBatteries>
    <StopIfGoingOnBatteries>false</StopIfGoingOnBatteries>
    <AllowHardTerminate>true</AllowHardTerminate>
    <StartWhenAvailable>true</StartWhenAvailable>
    <RunOnlyIfNetworkAvailable>false</RunOnlyIfNetworkAvailable>
    <IdleSettings>
      <StopOnIdleEnd>false</StopOnIdleEnd>
      <RestartOnIdle>false</RestartOnIdle>
    </IdleSettings>
    <AllowStartOnDemand>true</AllowStartOnDemand>
    <Enabled>true</Enabled>
    <Hidden>false</Hidden>
    <RunOnlyIfIdle>false</RunOnlyIfIdle>
    <WakeToRun>false</WakeToRun>
    <ExecutionTimeLimit>{limit}</ExecutionTimeLimit>
    <Priority>6</Priority>
  </Settings>
  <Actions Context="Author">
    <Exec>
      <Command>{command}</Command>
      <Arguments>{arguments}</Arguments>
      <WorkingDirectory>{folder}</WorkingDirectory>
    </Exec>
  </Actions>
</Task>
""".format(start=start, command=xml_escape(command), arguments=xml_escape(arguments or ""), folder=xml_escape(folder),
           logon=logon, user=user_tag, limit=limit)


def run_schtasks(args):
    r = subprocess.run(["schtasks"] + args, capture_output=True, text=True, errors="replace")
    return r.returncode, (r.stdout or "") + (r.stderr or "")


# ---------------------------------------------------------------------------
# Journal des mises à jour / update log (journal_maj.txt)
# ---------------------------------------------------------------------------
class Tee:
    """Écrit à la fois dans la console (si elle existe) et dans le journal."""
    def __init__(self, *streams):
        self.streams = [s for s in streams if s is not None]

    def write(self, text):
        for s in self.streams:
            try:
                s.write(text)
                s.flush()   # journal toujours à jour, même si le processus est arrêté
            except (OSError, ValueError, UnicodeError):
                pass

    def flush(self):
        for s in self.streams:
            try:
                s.flush()
            except (OSError, ValueError):
                pass


def journal_trim(path=None, keep=None):
    path, keep = path or JOURNAL, keep or JOURNAL_MAX
    try:
        with open(path, encoding="utf-8", errors="replace") as f:
            lines = f.readlines()
    except OSError:
        return
    if len(lines) > keep:
        with open(path, "w", encoding="utf-8") as f:
            f.writelines(lines[-keep:])


def journal_runs(path=None):
    """Exécutions notées : [{start, origin, result, ok, lines}], plus récente en dernier."""
    path = path or JOURNAL
    try:
        with open(path, encoding="utf-8", errors="replace") as f:
            lines = f.read().splitlines()
    except OSError:
        return []
    runs, cur = [], None
    for ln in lines:
        m = re.match(r"^===== (\d{4}-\d\d-\d\d \d\d:\d\d:\d\d) · (.+?) =====$", ln)
        if m:
            cur = {"start": m.group(1), "origin": m.group(2), "result": None, "ok": None, "lines": []}
            runs.append(cur)
            continue
        if cur is None:
            continue
        cur["lines"].append(ln)
        if ln.startswith("RÉSULTAT : "):
            cur["result"] = ln[len("RÉSULTAT : "):]
            cur["ok"] = cur["result"].startswith("OK")
    return runs


def run_logged(fn, origin):
    """Lance fn() en notant le déroulement et le résultat dans le journal."""
    journal_trim()
    try:
        log = open(JOURNAL, "a", encoding="utf-8")
    except OSError:
        log = None
    out, err = sys.stdout, sys.stderr
    tee = Tee(out, log)
    sys.stdout = sys.stderr = tee
    print("===== %s · %s =====" % (time.strftime("%Y-%m-%d %H:%M:%S"), origin))
    print("Python : %s" % sys.executable)

    def watchdog():
        # Jamais de tâche bloquée « en cours » : l'heure suivante doit pouvoir partir.
        print("\nRÉSULTAT : ERREUR — délai global dépassé (%d min), mise à jour abandonnée" % (WATCHDOG // 60))
        tee.flush()
        os._exit(2)
    timer = threading.Timer(WATCHDOG, watchdog)
    timer.daemon = True
    timer.start()
    code = 1
    try:
        code = fn()
        print("RÉSULTAT : OK" if code == 0 else "RÉSULTAT : ERREUR (code %s)" % code)
    except Erreur as e:
        print("\nERREUR : %s" % e)
        print("RÉSULTAT : ERREUR — %s" % str(e).splitlines()[0])
    except Exception as e:   # tâche sans fenêtre : tout doit finir dans le journal
        traceback.print_exc(file=tee)
        print("RÉSULTAT : ERREUR — %s: %s" % (type(e).__name__, e))
    finally:
        timer.cancel()
        tee.flush()
        sys.stdout, sys.stderr = out, err
        if log:
            log.close()
    return code


# ---------------------------------------------------------------------------
# Boucle horaire résidente / resident hourly loop
# ---------------------------------------------------------------------------
# La répétition horaire du Planificateur de tâches peut ne jamais se
# déclencher sur certains PC (constaté : seuls les déclencheurs d'ouverture de
# session et de réveil partaient). La tâche lance donc cette boucle à
# l'ouverture de session ; elle compte elle-même les heures (horloge réelle :
# une heure dépassée pendant une veille est rattrapée au réveil) et lance
# chaque mise à jour dans un processus séparé, avec son propre délai.
def last_ok_time(path=None):
    for r in reversed(journal_runs(path)):
        if r["ok"]:
            try:
                return time.mktime(time.strptime(r["start"], "%Y-%m-%d %H:%M:%S"))
            except ValueError:
                return 0
    return 0


def loop_state():
    """Battement de cœur de la boucle ({pid, started, check, last_ok, next, interval}) ou None."""
    try:
        with open(ETAT_BOUCLE, encoding="utf-8") as f:
            return json.load(f)
    except (OSError, ValueError):
        return None


def _write_state(st):
    tmp = ETAT_BOUCLE + ".tmp"
    try:
        with open(tmp, "w", encoding="utf-8") as f:
            json.dump(st, f)
        os.replace(tmp, ETAT_BOUCLE)
    except OSError:
        pass


def _lock():
    """Verrou exclusif : une deuxième boucle s'arrête aussitôt. None = déjà prise."""
    try:
        fh = open(VERROU_BOUCLE, "a+")
    except OSError:
        return None
    if os.name == "nt":
        import msvcrt
        try:
            fh.seek(0)
            msvcrt.locking(fh.fileno(), msvcrt.LK_NBLCK, 1)
        except OSError:
            fh.close()
            return None
    else:
        try:
            import fcntl
            fcntl.flock(fh.fileno(), fcntl.LOCK_EX | fcntl.LOCK_NB)
        except (ImportError, OSError):
            fh.close()
            return None
    return fh


def run_update_process(config):
    """Une mise à jour dans un processus séparé (mémoire rendue ensuite)."""
    exe = sys.executable or "python"
    pyw = os.path.join(os.path.dirname(exe), "pythonw.exe")
    if os.name == "nt" and os.path.exists(pyw):
        exe = pyw
    cmd = [exe, os.path.join(HERE, "sgl_prix_api.py"), "maj", "--journal", "--origine", "mise à jour horaire", "--config", config]
    flags = 0x08000000 if os.name == "nt" else 0   # CREATE_NO_WINDOW
    try:
        return subprocess.run(cmd, cwd=HERE, timeout=WATCHDOG + 120, creationflags=flags,
                              stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL).returncode
    except subprocess.TimeoutExpired:
        return 2
    except OSError:
        return 1


def cmd_loop(config, interval_min=60, ticks=None, sleep=time.sleep, runner=None, clock=time.time):
    """Boucle : vérifie toutes les 30 s s'il faut mettre à jour.
    ticks / sleep / runner / clock : pour les tests."""
    lock = _lock()
    if lock is None:
        return 0                       # une boucle tourne déjà
    runner = runner or run_update_process
    interval = max(30, int(interval_min)) * 60
    started = clock()
    last_ok, last_try, prev, not_before = last_ok_time(), 0.0, started, 0.0
    n = 0
    try:
        while ticks is None or n < ticks:
            n += 1
            now = clock()
            if now - prev > 300:
                not_before = now + 90  # réveil du PC : laisser le réseau revenir
            prev = now
            asked = os.path.exists(DEMANDE_MAJ)
            due = asked or (now - last_ok >= interval and now - last_try >= RETRY)
            if due and (asked or now >= not_before):
                if asked:
                    try:
                        os.remove(DEMANDE_MAJ)
                    except OSError:
                        pass
                last_try = now
                if runner(config) == 0:
                    last_ok = clock()
                now = clock()
                prev = now
            nxt = max(last_ok + interval, last_try + RETRY if last_try > last_ok else 0, not_before)
            _write_state({"pid": os.getpid(), "started": int(started), "check": int(now),
                          "last_ok": int(last_ok), "next": int(nxt), "interval": interval // 60})
            sleep(TICK)
    finally:
        try:
            lock.close()
        except OSError:
            pass
    return 0


# ---------------------------------------------------------------------------
# Mise à jour horaire (Planificateur de tâches Windows) / hourly scheduling
# ---------------------------------------------------------------------------
# Codes de résultat du Planificateur / Task Scheduler result codes
TASK_RESULTS = {
    0: "réussie",
    1: "échec (voir journal_maj.txt)",
    2: "échec : fichier introuvable",
    0x41300: "prête",
    0x41301: "en cours d'exécution (normal pour la mise à jour horaire)",
    0x41303: "jamais exécutée",
    0x41306: "arrêtée (délai de 15 minutes dépassé ou arrêt manuel)",
    0x8004131F: "une exécution était déjà en cours",
    0x80070002: "échec : programme ou fichier introuvable (dossier de l'outil déplacé ?)",
    0x80070005: "échec : accès refusé",
    0x800710E0: "refusée (conditions de la tâche ou session fermée)",
    0xC000013A: "interrompue (fermeture de session ou arrêt du PC)",
}


def task_result_text(code):
    try:
        code = int(code) & 0xFFFFFFFF
    except (TypeError, ValueError):
        return "inconnu"
    return "%s (code 0x%X)" % (TASK_RESULTS.get(code, "code non répertorié"), code)


def task_info():
    """État de la tâche via PowerShell (indépendant de la langue de Windows).
    Returns dict or None when the task does not exist."""
    ps = ("$ErrorActionPreference='Stop';"
          "$t=Get-ScheduledTask -TaskName '%s';$i=$t|Get-ScheduledTaskInfo;"
          "$n='';if($i.NextRunTime){$n=$i.NextRunTime.ToString('s')};"
          "$l='';if($i.LastRunTime -and $i.LastRunTime.Year -gt 2000){$l=$i.LastRunTime.ToString('s')};"
          "[pscustomobject]@{State=[string]$t.State;Last=$l;Result=[int64]$i.LastTaskResult;Next=$n;"
          "Missed=$i.NumberOfMissedRuns;Exec=[string]$t.Actions[0].Execute;Args=[string]$t.Actions[0].Arguments}|ConvertTo-Json -Compress"
          % TASK_NAME.replace("'", "''"))
    try:
        r = subprocess.run(["powershell", "-NoProfile", "-NonInteractive", "-Command", ps],
                           capture_output=True, text=True, errors="replace", timeout=40)
    except (OSError, subprocess.TimeoutExpired):
        return {"error": "PowerShell indisponible"}
    if r.returncode != 0:
        return None
    try:
        return json.loads((r.stdout or "").strip().splitlines()[-1])
    except (ValueError, IndexError):
        return {"error": (r.stdout or r.stderr or "").strip()[:300]}


STATES = {"Ready": "prête", "Running": "en cours (normal : la mise à jour horaire tourne en arrière-plan)", "Disabled": "DÉSACTIVÉE", "Queued": "en attente", "Unknown": "inconnu"}


def print_task_info(info):
    if info is None:
        print("Tâche « %s » : absente (mise à jour horaire désactivée)." % TASK_NAME)
        return
    if "error" in info:
        print("Tâche : état illisible (%s)." % info["error"])
        return
    print("Tâche « %s » : %s" % (TASK_NAME, STATES.get(info.get("State"), info.get("State"))))
    print("  Dernière exécution : %s" % ((info.get("Last") or "jamais").replace("T", " ")))
    print("  Dernier résultat   : %s" % task_result_text(info.get("Result")))
    print("  Prochaine          : %s" % ((info.get("Next") or "aucune").replace("T", " ")))
    if info.get("Missed"):
        print("  Exécutions manquées (PC éteint ou en veille) : %s" % info["Missed"])
    print("  Programme lancé    : %s %s" % (info.get("Exec", ""), info.get("Args", "")))


def module_age(cfg):
    addons = cfg["wow"].get("addons", "").strip()
    path = os.path.join(addons, MODULE, "Prix.lua") if addons else ""
    if not path or not os.path.exists(path):
        return None, path
    return os.path.getmtime(path), path


def cmd_schedule(cfg, args):
    if os.name != "nt":
        raise Erreur("La mise à jour horaire utilise le Planificateur de tâches de Windows.")
    Api(cfg)   # vérifie que la clé est renseignée / key present
    if not any(cfg["marche"].get(CFG_KEYS[k], "").strip() for k in FACTIONS):
        raise Erreur("Aucun HDV configuré : lancez d'abord 2_Identifier_mes_HDV.")
    command, arguments = task_command(HERE)
    if command.lower() == "wscript.exe" and not os.path.exists(os.path.join(HERE, "maj_cachee.vbs")):
        raise Erreur("pythonw.exe introuvable à côté de %s et maj_cachee.vbs absent : réinstallez l'outil." % sys.executable)
    fd, path = tempfile.mkstemp(suffix=".xml")
    os.close(fd)
    try:
        with open(path, "w", encoding="utf-16") as f:
            f.write(build_task_xml(HERE, command=command, arguments=arguments))
        code, out = run_schtasks(["/Create", "/F", "/TN", TASK_NAME, "/XML", path])
    finally:
        os.remove(path)
    if code != 0:
        raise Erreur("Le Planificateur de tâches a refusé la tâche :\n" + out.strip())
    print("Tâche « %s » créée : mise à jour horaire lancée 1 minute après l'ouverture de session." % TASK_NAME)
    print("Programme : %s %s" % (command, arguments))
    # Vérification immédiate : on (re)lance la tâche et on attend une mise à jour.
    run_schtasks(["/End", "/TN", TASK_NAME])   # arrête l'ancienne boucle ou une exécution bloquée
    time.sleep(2)
    before = len(journal_runs())
    try:
        open(DEMANDE_MAJ, "w").close()         # la boucle met à jour dès son démarrage
    except OSError:
        pass
    run_schtasks(["/Run", "/TN", TASK_NAME])
    print("\nPremière mise à jour lancée par le Planificateur, vérification (3 minutes au plus) ", end="", flush=True)
    run = None
    for _ in range(90):
        time.sleep(2)
        print(".", end="", flush=True)
        runs = journal_runs()
        if len(runs) > before and runs[-1]["result"] is not None:
            run = runs[-1]
            break
    print()
    if run and run["ok"]:
        print("\nOK : la mise à jour horaire fonctionne (mise à jour du %s)." % run["start"])
        print("Elle tourne en arrière-plan, sans fenêtre : une mise à jour par heure tant que votre session est ouverte,")
        print("pendant que vous jouez ou non. Elle redémarre seule à chaque ouverture de session.")
        print("En jeu : /reload (ou le bouton Recharger de l'onglet Marchés) pour charger les nouveaux prix.")
        return 0
    if run:
        print("\nLa tâche s'est lancée mais la mise à jour a échoué (elle sera retentée dans une heure) :")
        for ln in run["lines"][-12:]:
            print("  " + ln)
        print("\nCorrigez l'erreur ci-dessus (souvent : clé, connexion), puis relancez ce fichier.")
        return 1
    print("\nAucun résultat de la tâche après 3 minutes. État vu par Windows :")
    print_task_info(task_info())
    print("\nEnvoyez cet écran : il indique pourquoi Windows n'a pas lancé la mise à jour.")
    return 1


def cmd_status(cfg, args):
    if os.name != "nt":
        raise Erreur("La mise à jour horaire utilise le Planificateur de tâches de Windows.")
    info = task_info()
    print_task_info(info)
    st = loop_state()
    print()
    if st and time.time() - st.get("check", 0) < 3 * TICK + 30:
        fmt = lambda t: time.strftime("%d/%m %H:%M", time.localtime(t)) if t else "jamais"
        print("Mise à jour horaire : ACTIVE (en arrière-plan depuis le %s)" % fmt(st.get("started")))
        print("  Dernière réussie : %s · prochaine vers %s · toutes les %s min"
              % (fmt(st.get("last_ok")), time.strftime("%H:%M", time.localtime(st.get("next", 0))), st.get("interval", 60)))
    elif info and "error" not in info:
        print("Mise à jour horaire : ARRÊTÉE (dernier signe de vie : %s)."
              % (time.strftime("%d/%m %H:%M", time.localtime(st["check"])) if st else "jamais"))
        print("  Elle redémarre à la prochaine ouverture de session ou dans l'heure ; sinon relancez 5_Activer…")
    print()
    mt, path = module_age(cfg)
    if mt:
        print("Fichier des prix : %s" % path)
        print("  modifié le %s (il y a %d min)" % (time.strftime("%d/%m %H:%M", time.localtime(mt)), (time.time() - mt) // 60))
    else:
        print("Fichier des prix introuvable : %s" % (path or "dossier AddOns non configuré"))
    runs = journal_runs()
    print()
    if not runs:
        print("Journal : aucune mise à jour notée (%s)." % JOURNAL)
    else:
        print("Journal (%s) — dernières mises à jour :" % os.path.basename(JOURNAL))
        for r in runs[-8:]:
            print("  %s · %-26s · %s" % (r["start"], r["origin"], r["result"] or "interrompue (pas de résultat)"))
        last = runs[-1]
        if not last["ok"]:
            print("\nDétail de la dernière :")
            for ln in last["lines"][-15:]:
                print("  " + ln)
    old = os.path.join(HERE, "derniere_maj.log")
    if os.path.exists(old):
        print("\n(Ancien journal de la v0.10 : derniere_maj.log, modifié le %s.)"
              % time.strftime("%d/%m %H:%M", time.localtime(os.path.getmtime(old))))
    return 0


def cmd_unschedule(cfg, args):
    if os.name != "nt":
        raise Erreur("La mise à jour horaire utilise le Planificateur de tâches de Windows.")
    run_schtasks(["/End", "/TN", TASK_NAME])   # arrête la boucle en cours
    code, out = run_schtasks(["/Delete", "/F", "/TN", TASK_NAME])
    for f in (ETAT_BOUCLE, DEMANDE_MAJ):
        try:
            os.remove(f)
        except OSError:
            pass
    if code != 0:
        print("Aucune tâche « %s » à supprimer (déjà désactivée)." % TASK_NAME)
        return 0
    print("Mise à jour horaire désactivée. Les prix déjà importés restent dans l'add-on.")
    return 0


def main(argv=None):
    # Console Windows : jamais d'arrêt sur un caractère non affichable.
    for stream in (sys.stdout, sys.stderr):
        try:
            stream.reconfigure(errors="replace")
        except (AttributeError, ValueError):
            pass
    ap = argparse.ArgumentParser(description="Prix des HDV de WoW Forever via l'API Blizzard, pour Shadsun Gold Lens.")
    ap.add_argument("commande", nargs="?", default="maj", choices=["maj", "test", "identifier", "verifier", "planifier", "deplanifier", "etat", "boucle"])
    ap.add_argument("objet", nargs="?", help="ID d'objet (commande verifier)")
    ap.add_argument("--config", default=os.path.join(HERE, "sgl_prix_api.ini"))
    ap.add_argument("--sortie", help="dossier du module à écrire (par défaut : <addons>/ShadsunGoldLens_Prix)")
    ap.add_argument("--journal", action="store_true", help="mise à jour lancée par la tâche planifiée (sans console)")
    ap.add_argument("--origine", help="libellé de l'exécution dans le journal")
    args = ap.parse_args(argv)
    # pythonw.exe (tâche sans fenêtre) : pas de console du tout.
    if sys.stdout is None or sys.stderr is None:
        sys.stdout = sys.stderr = open(os.devnull, "w", encoding="utf-8")
    if args.commande == "maj":
        origin = args.origine or ("tâche planifiée" if args.journal else "mise à jour manuelle")
        def job():
            banner()
            return cmd_update(load_config(args.config), args)
        return run_logged(job, origin)
    if args.commande == "boucle":
        try:
            minutes = float(load_config(args.config)["outil"].get("intervalle_minutes", "60") or 60)
        except Exception:
            minutes = 60
        try:
            return cmd_loop(args.config, minutes)
        except Exception as e:      # noté au journal : jamais d'arrêt silencieux
            run_logged(lambda: (_ for _ in ()).throw(e), "boucle horaire")
            return 1
    banner()
    try:
        cfg = load_config(args.config)
        if args.commande == "test":
            return cmd_test(cfg, args)
        if args.commande == "identifier":
            return cmd_identify(cfg, args, args.config)
        if args.commande == "verifier":
            if not args.objet or not args.objet.isdigit():
                raise Erreur("Indiquez l'ID de l'objet : python sgl_prix_api.py verifier 2589")
            return cmd_verify(cfg, args)
        if args.commande == "planifier":
            return cmd_schedule(cfg, args)
        if args.commande == "deplanifier":
            return cmd_unschedule(cfg, args)
        if args.commande == "etat":
            return cmd_status(cfg, args)
        return cmd_update(cfg, args)
    except Erreur as e:
        print("\nERREUR : %s" % e)
        return 1


if __name__ == "__main__":
    sys.exit(main())
