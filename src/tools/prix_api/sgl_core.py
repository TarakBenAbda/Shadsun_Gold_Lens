# -*- coding: utf-8 -*-
"""
===============================================================================
 Shadsun Gold Lens — application : cœur sans interface (sgl_core.py)
 Auteur : Tarak Ben Abda – novembre 2026
-------------------------------------------------------------------------------
 FR : Tout ce que l'application fait, sans fenêtre (testable hors Windows) :
      - dossier de données dans %APPDATA%\\ShadsunGoldLens (configuration,
        journal, cache) : l'application peut être lancée de n'importe où ;
      - clé Blizzard rangée dans le Gestionnaire d'identification de Windows
        (jamais en clair dans un fichier) ;
      - détection de WoW Forever, de la région et du type de serveur ;
      - installation / mise à jour de l'add-on livré avec l'application ;
      - démarrage avec Windows (clé « Exécuter » de l'utilisateur, sans
        Planificateur de tâches) et retrait de l'ancienne tâche planifiée ;
      - reprise de la configuration de l'ancien outil (C:\\ShadsunGoldLens-Prix) ;
      - boucle horaire dans un fil, chaque mise à jour dans un processus séparé ;
      - instance unique (un deuxième lancement fait réapparaître la fenêtre).
 EN : Headless core of the desktop app.
===============================================================================
"""
import configparser
import glob
import hashlib
import io
import json
import ntpath
import os
import re
import shutil
import subprocess
import sys
import threading
import time
import urllib.request
import zipfile

import sgl_prix_api as E

APP_NAME = "Shadsun Gold Lens"
APP_VERSION = "1.6.1"
APP_ID = "ShadsunGoldLens"
FLAVOR = "_forever_"
PORTAL_URL = "https://develop.battle.net/access/clients"
FAH_URL = "https://forever-ah.com"
OLD_TOOL_DIRS = [r"C:\ShadsunGoldLens-Prix"]
CRED_TARGET = "ShadsunGoldLens/battlenet"
RUN_KEY = r"Software\Microsoft\Windows\CurrentVersion\Run"
# Mises à jour en ligne (GitHub Releases) / online updates
GITHUB_REPO = "TarakBenAbda/Shadsun_Gold_Lens"
RELEASE_API = "https://api.github.com/repos/%s/releases/latest" % GITHUB_REPO
RELEASE_PAGE = "https://github.com/%s/releases/latest" % GITHUB_REPO
MANIFEST_NAME = "sgl-version.json"
ONLINE_EVERY = 24 * 3600          # une vérification par jour au plus / at most daily
ONLINE_MAX_BYTES = 60 * 1024 * 1024

IS_WIN = os.name == "nt"
FROZEN = bool(getattr(sys, "frozen", False))
HERE = os.path.dirname(os.path.abspath(__file__))


# -----------------------------------------------------------------------------
# Dossiers / folders
# -----------------------------------------------------------------------------
def data_dir():
    """%APPDATA%\\ShadsunGoldLens (SGL_DATA_DIR pour les tests)."""
    d = os.environ.get("SGL_DATA_DIR")
    if not d:
        base = os.environ.get("APPDATA") if IS_WIN else os.path.expanduser("~/.config")
        d = os.path.join(base or os.path.expanduser("~"), APP_ID)
    os.makedirs(d, exist_ok=True)
    return d


def config_path():
    return os.path.join(data_dir(), "config.ini")


def setup_engine():
    """Le moteur écrit journal, cache et signaux dans le dossier de données."""
    d = data_dir()
    E.CACHE_ROOT = d
    E.JOURNAL = os.path.join(d, "journal_maj.txt")
    E.ETAT_BOUCLE = os.path.join(d, "boucle_etat.json")
    E.VERROU_BOUCLE = os.path.join(d, "boucle.verrou")
    E.DEMANDE_MAJ = os.path.join(d, "maj_demandee")
    return d


def bundled_addon_dir():
    """Dossier « ShadsunGoldLens » livré avec l'application (ou None)."""
    cands = []
    if FROZEN:
        cands.append(os.path.join(getattr(sys, "_MEIPASS", HERE), "addon", "ShadsunGoldLens"))
    cands += [os.path.join(HERE, "addon", "ShadsunGoldLens"),
              os.path.normpath(os.path.join(HERE, "..", "..", "..", "ShadsunGoldLens"))]
    for c in cands:
        if os.path.isfile(os.path.join(c, "ShadsunGoldLens.toc")):
            return c
    return None


def toc_version(addon_dir):
    try:
        with open(os.path.join(addon_dir, "ShadsunGoldLens.toc"), encoding="utf-8-sig") as f:
            m = re.search(r"^##\s*Version:\s*(\S+)", f.read(), re.M)
            return m.group(1) if m else None
    except OSError:
        return None


# -----------------------------------------------------------------------------
# Configuration
# -----------------------------------------------------------------------------
APP_DEFAULTS = {
    "app": {"assistant_fait": "0", "version": APP_VERSION, "avis_zone_vu": "0"},
    "source": {"type": "foreverah"},
    "marche": {"region": "eu", "type_marche": "", "hdv_alliance": "", "hdv_horde": "", "hdv_neutre": "",
               "prix_annonce": "total", "namespace": "dynamic-forever-{region}", "ruleset_api": "1"},
    "wow": {"dossier": "", "addons": "", "savedvariables": "", "serveur": ""},
    "outil": {"cache_minutes": "50", "dossier_cache": "cache", "intervalle_minutes": "60",
              "auto_horaire": "1", "demarrage_windows": "1", "zone_notification": "1"},
    "battlenet": {"client_id": ""},
}


def load():
    cfg = configparser.ConfigParser(interpolation=None)
    for sec, vals in APP_DEFAULTS.items():
        cfg[sec] = dict(vals)
    p = config_path()
    if os.path.exists(p):
        with open(p, encoding="utf-8-sig") as f:
            cfg.read_file(f)
    return cfg


def save(cfg):
    p = config_path()
    tmp = p + ".tmp"
    # Jamais de secret dans le fichier / never a secret in the file
    if cfg.has_option("battlenet", "client_secret"):
        cfg.remove_option("battlenet", "client_secret")
    with open(tmp, "w", encoding="utf-8") as f:
        f.write("; Shadsun Gold Lens — configuration de l'application (modifiable par l'application)\n")
        cfg.write(f)
    os.replace(tmp, p)


def engine_config(cfg=None):
    """Configuration au format du moteur, clé secrète comprise (en mémoire seulement)."""
    cfg = cfg or load()
    e = configparser.ConfigParser(interpolation=None)
    for sec, vals in E.DEFAULTS.items():
        e[sec] = dict(vals)
    for sec in ("source", "marche", "wow", "outil"):
        for k, v in cfg[sec].items():
            e[sec][k] = v
    cid = cfg["battlenet"].get("client_id", "").strip()
    e["battlenet"]["client_id"] = cid
    e["battlenet"]["client_secret"] = (get_secret(cid) or "") if cid else ""
    # HDV d'après le type de serveur / houses from the ruleset
    auto = E.houses_for(cfg["marche"].get("type_marche", "").strip())
    if auto:
        for fac, hid in auto.items():
            e["marche"][E.CFG_KEYS[fac]] = str(hid)
    return e


def is_ready(cfg=None):
    """L'application peut-elle mettre à jour (assistant terminé, marché, AddOns) ?"""
    cfg = cfg or load()
    return (cfg["app"].get("assistant_fait") == "1" and bool(E.houses_for(cfg["marche"].get("type_marche", "")))
            and os.path.isdir(cfg["wow"].get("addons", "")))


# -----------------------------------------------------------------------------
# Clé Blizzard : Gestionnaire d'identification de Windows
# -----------------------------------------------------------------------------
def _cred_api():
    import ctypes
    from ctypes import wintypes

    class CREDENTIAL(ctypes.Structure):
        _fields_ = [("Flags", wintypes.DWORD), ("Type", wintypes.DWORD), ("TargetName", wintypes.LPWSTR),
                    ("Comment", wintypes.LPWSTR), ("LastWritten", wintypes.FILETIME),
                    ("CredentialBlobSize", wintypes.DWORD), ("CredentialBlob", ctypes.POINTER(ctypes.c_char)),
                    ("Persist", wintypes.DWORD), ("AttributeCount", wintypes.DWORD), ("Attributes", ctypes.c_void_p),
                    ("TargetAlias", wintypes.LPWSTR), ("UserName", wintypes.LPWSTR)]
    adv = ctypes.WinDLL("advapi32", use_last_error=True)
    return ctypes, CREDENTIAL, adv


def _fallback_secret_file():
    return os.path.join(data_dir(), ".secret_dev")   # hors Windows : tests et développement


def set_secret(client_id, secret):
    if not IS_WIN:
        with open(_fallback_secret_file(), "w", encoding="utf-8") as f:
            f.write("%s\n%s\n" % (client_id, secret))
        try:
            os.chmod(_fallback_secret_file(), 0o600)
        except OSError:
            pass
        return True
    ctypes, CREDENTIAL, adv = _cred_api()
    blob = secret.encode("utf-16-le")
    cred = CREDENTIAL()
    cred.Type = 1                      # CRED_TYPE_GENERIC
    cred.TargetName = CRED_TARGET
    cred.UserName = client_id
    cred.CredentialBlobSize = len(blob)
    cred.CredentialBlob = ctypes.cast(ctypes.create_string_buffer(blob, len(blob)), ctypes.POINTER(ctypes.c_char))
    cred.Persist = 2                   # CRED_PERSIST_LOCAL_MACHINE (cet utilisateur, ce PC)
    return bool(adv.CredWriteW(ctypes.byref(cred), 0))


def get_secret(client_id=None):
    if not IS_WIN:
        try:
            with open(_fallback_secret_file(), encoding="utf-8") as f:
                cid, sec = (f.read().splitlines() + ["", ""])[:2]
            return sec if (client_id is None or cid == client_id) else None
        except OSError:
            return None
    ctypes, CREDENTIAL, adv = _cred_api()
    p = ctypes.POINTER(CREDENTIAL)()
    if not adv.CredReadW(CRED_TARGET, 1, 0, ctypes.byref(p)):
        return None
    try:
        c = p.contents
        if client_id is not None and c.UserName != client_id:
            return None
        return ctypes.string_at(c.CredentialBlob, c.CredentialBlobSize).decode("utf-16-le")
    finally:
        adv.CredFree(p)


def delete_secret():
    if not IS_WIN:
        try:
            os.remove(_fallback_secret_file())
        except OSError:
            pass
        return
    ctypes, _, adv = _cred_api()
    adv.CredDeleteW(CRED_TARGET, 1, 0)


# -----------------------------------------------------------------------------
# WoW Forever : dossier, région, relevés du jeu
# -----------------------------------------------------------------------------
def _registry_wow_paths():
    out = []
    if not IS_WIN:
        return out
    try:
        import winreg
    except ImportError:
        return out
    keys = [(winreg.HKEY_LOCAL_MACHINE, r"SOFTWARE\WOW6432Node\Blizzard Entertainment\World of Warcraft"),
            (winreg.HKEY_LOCAL_MACHINE, r"SOFTWARE\Blizzard Entertainment\World of Warcraft"),
            (winreg.HKEY_CURRENT_USER, r"Software\Blizzard Entertainment\World of Warcraft")]
    for hive, sub in keys:
        try:
            with winreg.OpenKey(hive, sub) as k:
                val, _ = winreg.QueryValueEx(k, "InstallPath")
                out.append(val)
        except OSError:
            pass
    return out


def find_forever_dirs(extra_roots=None):
    """Dossiers « …\\World of Warcraft\\_forever_ » trouvés sur le PC."""
    roots = list(extra_roots or [])
    for p in _registry_wow_paths():
        p = p.rstrip("\\/")
        roots += [p, os.path.dirname(p)]           # InstallPath pointe souvent sur _retail_
    if IS_WIN:
        for drive in "CDEFGH":
            for sub in (r"Program Files (x86)\World of Warcraft", r"Program Files\World of Warcraft",
                        r"World of Warcraft", r"Games\World of Warcraft", r"Jeux\World of Warcraft",
                        r"Battle.net\World of Warcraft", r"Blizzard\World of Warcraft"):
                roots.append("%s:\\%s" % (drive, sub))
    found = []
    for r in roots:
        r = r.rstrip("\\/")
        cand = r if os.path.basename(r).lower() == FLAVOR else os.path.join(r, FLAVOR)
        if os.path.isdir(cand) and os.path.normcase(cand) not in [os.path.normcase(x) for x in found]:
            found.append(cand)
    return found


def forever_from_any(path):
    """Accepte le dossier du jeu, _forever_, Interface ou AddOns → dossier _forever_."""
    p = os.path.normpath(path or "")
    for _ in range(4):
        if os.path.basename(p).lower() == FLAVOR:
            return p if os.path.isdir(p) else None
        if os.path.isdir(os.path.join(p, FLAVOR)):
            return os.path.join(p, FLAVOR)
        p = os.path.dirname(p)
    return None


def addons_dir(forever):
    return os.path.join(forever, "Interface", "AddOns")


def detect_region(forever):
    """Région d'après WTF\\Config.wtf (SET portal "EU"), sinon None."""
    try:
        with open(os.path.join(forever, "WTF", "Config.wtf"), encoding="utf-8", errors="replace") as f:
            m = re.search(r'^SET\s+portal\s+"?(\w+)"?', f.read(), re.M | re.I)
    except OSError:
        return None
    if not m:
        return None
    reg = m.group(1).lower()
    return reg if reg in [r for r, _ in E.REGIONS] else None


def saved_variables_files(forever):
    """SavedVariables de l'add-on (un fichier par compte), plus récent d'abord."""
    pats = os.path.join(forever, "WTF", "Account", "*", "SavedVariables", "ShadsunGoldLens.lua")
    return sorted(glob.glob(pats), key=os.path.getmtime, reverse=True)


def game_scans(forever):
    """Relevés de l'HDV faits en jeu : {royaume: {A|H|N: {time, items}}}."""
    out = {}
    for f in saved_variables_files(forever):
        try:
            for realm, mk in E.read_scans(f).items():
                cur = out.setdefault(realm, {})
                for fac, data in mk.items():
                    if fac not in cur or (data.get("time") or 0) > (cur[fac].get("time") or 0):
                        cur[fac] = data
        except Exception:
            continue
    return out


def suggest_from_game(forever):
    """(type de serveur suggéré, nom du royaume) d'après les relevés du jeu."""
    scans = game_scans(forever)
    for realm in sorted(scans, key=lambda r: -sum(len(v.get("items", {})) for v in scans[r].values())):
        rs = E.suggest_ruleset(realm)
        if rs:
            return rs, realm
    return None, (next(iter(scans)) if scans else None)


# -----------------------------------------------------------------------------
# Add-on
# -----------------------------------------------------------------------------
def addon_status(addons):
    """(version installée ou None, version livrée ou None)."""
    inst = toc_version(os.path.join(addons, "ShadsunGoldLens")) if addons else None
    src = bundled_addon_dir()
    return inst, (toc_version(src) if src else None)


def install_addon(addons, src=None):
    """Copie l'add-on (livré, ou `src`) dans AddOns en remplaçant l'ancien dossier.
    Retourne la version installée. / Installs the add-on, returns its version."""
    src = src or bundled_addon_dir()
    if not src:
        raise E.Erreur("Add-on introuvable dans l'application (dossier « addon » manquant).")
    os.makedirs(addons, exist_ok=True)
    dst = os.path.join(addons, "ShadsunGoldLens")
    tmp = dst + ".nouveau"
    old = dst + ".ancien"
    for p in (tmp, old):
        shutil.rmtree(p, ignore_errors=True)
    shutil.copytree(src, tmp)
    if os.path.isdir(dst):
        os.rename(dst, old)
    os.rename(tmp, dst)
    shutil.rmtree(old, ignore_errors=True)
    return toc_version(dst)


# -----------------------------------------------------------------------------
# Mises à jour en ligne : dernière version publiée sur GitHub
# Online updates: latest GitHub release.
#   La page de version contient sgl-version.json :
#   {"addon": {"version", "file", "sha256"}, "app": {"version", "file", "sha256"}}
#   L'add-on téléchargé n'est installé que si son empreinte SHA-256 correspond,
#   que l'archive ne contient que le dossier ShadsunGoldLens et que la version
#   du .toc est celle annoncée. Rien n'est jamais exécuté.
# -----------------------------------------------------------------------------
_VER_RE = re.compile(r"^\d+(\.\d+){1,3}$")
_SHA_RE = re.compile(r"^[0-9a-f]{64}$")


def vtuple(v):
    try:
        return tuple(int(x) for x in str(v).split("."))
    except (TypeError, ValueError):
        return ()


def is_newer(a, b):
    """a strictement plus récente que b (b peut être None)."""
    return bool(a) and (not b or vtuple(a) > vtuple(b))


def _http_get(url, timeout=15, accept=None, limit=ONLINE_MAX_BYTES):
    if not url.startswith("https://") and not url.startswith("http://127.0.0.1"):
        raise E.Erreur("Adresse refusée (HTTPS obligatoire) : %s" % url)
    headers = {"User-Agent": "ShadsunGoldLens/%s" % APP_VERSION}
    if accept:
        headers["Accept"] = accept
    req = urllib.request.Request(url, headers=headers)
    with urllib.request.urlopen(req, timeout=timeout) as r:
        data = r.read(limit + 1)
    if len(data) > limit:
        raise E.Erreur("Fichier trop gros : %s" % url)
    return data


def _online_state_path():
    return os.path.join(data_dir(), "maj_en_ligne.json")


def _read_online_state():
    try:
        with open(_online_state_path(), encoding="utf-8") as f:
            return json.load(f)
    except (OSError, ValueError):
        return {}


def _write_online_state(st):
    try:
        with open(_online_state_path(), "w", encoding="utf-8") as f:
            json.dump(st, f, ensure_ascii=False, indent=1)
    except OSError:
        pass


def fetch_online(api_url=None, timeout=15):
    """Lit la dernière version publiée. Retourne
    {"addon": {version, url, sha256}, "app": {version, url, sha256} ou None, "page", "tag"}."""
    rel = json.loads(_http_get(api_url or RELEASE_API, timeout, "application/vnd.github+json").decode("utf-8"))
    assets = {a.get("name"): a.get("browser_download_url") for a in rel.get("assets") or []}
    if MANIFEST_NAME not in assets:
        raise E.Erreur("Version publiée sans fiche %s." % MANIFEST_NAME)
    man = json.loads(_http_get(assets[MANIFEST_NAME], timeout).decode("utf-8"))
    out = {"page": rel.get("html_url") or RELEASE_PAGE, "tag": rel.get("tag_name", "")}
    for key in ("addon", "app"):
        m = man.get(key) or {}
        v, f, h = str(m.get("version", "")), m.get("file", ""), str(m.get("sha256", "")).lower()
        if _VER_RE.match(v) and f in assets and _SHA_RE.match(h):
            out[key] = {"version": v, "url": assets[f], "sha256": h, "file": f}
        else:
            out[key] = None
    if not out["addon"]:
        raise E.Erreur("Fiche de version invalide (add-on).")
    return out


def online_info(force=False, api_url=None, now=None):
    """Dernière version en ligne, vérifiée au plus une fois par jour (sauf force).
    En cas d'échec, garde la dernière information connue. / Cached daily check."""
    now = now or time.time()
    st = _read_online_state()
    if not force and st.get("checked") and now - st["checked"] < ONLINE_EVERY:
        return st.get("info")
    st["checked"] = now
    try:
        st["info"], st["error"] = fetch_online(api_url), None
    except Exception as ex:   # réseau, GitHub indisponible, fiche invalide
        st["error"] = str(ex)
    _write_online_state(st)
    return st.get("info")


def online_error():
    return _read_online_state().get("error")


def _safe_extract_addon(blob, dest):
    """Extrait l'archive de l'add-on dans dest en refusant tout chemin suspect."""
    with zipfile.ZipFile(io.BytesIO(blob)) as z:
        total = 0
        for info in z.infolist():
            name = info.filename.replace("\\", "/")
            parts = [p for p in name.split("/") if p]
            if not parts or parts[0] != "ShadsunGoldLens" or ".." in parts or name.startswith("/") or ":" in name:
                raise E.Erreur("Archive refusée : chemin inattendu « %s »." % info.filename)
            total += info.file_size
            if total > ONLINE_MAX_BYTES:
                raise E.Erreur("Archive refusée : contenu trop gros.")
        z.extractall(dest)
    return os.path.join(dest, "ShadsunGoldLens")


def install_addon_online(addons, info, timeout=60):
    """Télécharge l'add-on publié, vérifie l'empreinte et la version, puis l'installe.
    En cas de problème, l'add-on déjà installé n'est pas touché."""
    a = (info or {}).get("addon")
    if not a:
        raise E.Erreur("Aucune version en ligne connue.")
    blob = _http_get(a["url"], timeout)
    if hashlib.sha256(blob).hexdigest() != a["sha256"]:
        raise E.Erreur("Fichier téléchargé altéré (empreinte différente) : installation annulée.")
    tmp = os.path.join(data_dir(), "telechargement")
    shutil.rmtree(tmp, ignore_errors=True)
    os.makedirs(tmp, exist_ok=True)
    try:
        src = _safe_extract_addon(blob, tmp)
        v = toc_version(src)
        if v != a["version"]:
            raise E.Erreur("Version de l'archive (%s) différente de celle annoncée (%s)." % (v, a["version"]))
        return install_addon(addons, src)
    finally:
        shutil.rmtree(tmp, ignore_errors=True)


# -----------------------------------------------------------------------------
# Installation à un emplacement fixe et mise à jour de l'application elle-même
# Fixed per-user install location and self-update.
#   L'exe s'installe dans %LOCALAPPDATA%\Programs\ShadsunGoldLens, avec des
#   raccourcis sur le Bureau et dans le menu Démarrer. Où que soit l'exe
#   téléchargé, c'est cette copie qui tourne ; l'utilisateur n'a jamais à
#   retrouver l'ancien fichier. Mise à jour : le nouvel exe est téléchargé à
#   côté (empreinte vérifiée), lancé avec --remplacer ; il attend la fermeture
#   de l'ancien, prend sa place, puis relance l'application.
# -----------------------------------------------------------------------------
EXE_NAME = "ShadsunGoldLens.exe"


def install_dir():
    d = os.environ.get("SGL_INSTALL_DIR")
    if not d:
        base = os.environ.get("LOCALAPPDATA") if IS_WIN else os.path.expanduser("~/.local/share")
        d = os.path.join(base or os.path.expanduser("~"), "Programs", APP_ID)
    return d


def installed_exe():
    return os.path.join(install_dir(), EXE_NAME)


def _install_state_path():
    return os.path.join(install_dir(), "installation.json")


def installed_version():
    """Version de la copie installée (None si aucune)."""
    if not os.path.isfile(installed_exe()):
        return None
    try:
        with open(_install_state_path(), encoding="utf-8") as f:
            return json.load(f).get("version")
    except (OSError, ValueError):
        return None


def _same_path(a, b):
    return bool(a and b) and os.path.normcase(os.path.abspath(a)) == os.path.normcase(os.path.abspath(b))


def running_from_install(exe=None):
    return _same_path(exe or sys.executable, installed_exe())


def install_copy(src_exe, version=APP_VERSION, retries=20, pause=0.5):
    """Copie l'exe à l'emplacement fixe (remplace l'ancien) et note sa version.
    Réessaie quelques secondes si l'ancien est encore en train de se fermer."""
    os.makedirs(install_dir(), exist_ok=True)
    dst = installed_exe()
    tmp = dst + ".copie"
    shutil.copyfile(src_exe, tmp)
    for i in range(retries):
        try:
            os.replace(tmp, dst)
            break
        except OSError:
            if i == retries - 1:
                raise
            time.sleep(pause)
    try:
        with open(_install_state_path(), encoding="utf-8") as f:
            st = json.load(f)
    except (OSError, ValueError):
        st = {}
    st.update({"version": version, "installe": time.strftime("%Y-%m-%d %H:%M")})
    with open(_install_state_path(), "w", encoding="utf-8") as f:
        json.dump(st, f)
    return dst


SHORTCUT_VERSION = 2   # 2 : Bureau réel (OneDrive compris), réparation au démarrage


def _shortcut_script(target):
    """Script PowerShell : raccourcis sur le Bureau réel de l'utilisateur et dans le
    menu Démarrer. Le Bureau est demandé à Windows (GetFolderPath) : il peut être
    redirigé vers OneDrive (…\\OneDrive\\Bureau), ce qui faisait échouer la 1.6.0.
    Un raccourci laissé par la 1.6.0 dans un faux dossier « Desktop » est retiré."""
    q = lambda x: x.replace("'", "''")   # noqa: E731 - guillemets PowerShell
    name = q(APP_NAME + ".lnk")
    return (
        "$t='%s';$w='%s';$sh=New-Object -ComObject WScript.Shell;"
        "$d=[Environment]::GetFolderPath('Desktop');$p=[Environment]::GetFolderPath('Programs');"
        "foreach($f in @($d,$p)){if($f){$s=$sh.CreateShortcut((Join-Path $f '%s'));$s.TargetPath=$t;"
        "$s.WorkingDirectory=$w;$s.IconLocation=$t+',0';$s.Description='%s';$s.Save();Write-Output (Join-Path $f '%s')}};"
        "$old=Join-Path $env:USERPROFILE 'Desktop\\%s';if(($old -ne (Join-Path $d '%s')) -and (Test-Path $old)){Remove-Item $old}"
        % (q(target), q(ntpath.dirname(target)), name, q(APP_NAME + " : prix des HDV de WoW Forever"), name, name, name))


def create_shortcuts(target=None):
    """Crée ou met à jour les raccourcis (Windows uniquement). Retourne leurs chemins."""
    target = target or installed_exe()
    if not IS_WIN:
        return []
    try:
        r = subprocess.run(["powershell", "-NoProfile", "-NonInteractive", "-Command", _shortcut_script(target)],
                           creationflags=getattr(subprocess, "CREATE_NO_WINDOW", 0), timeout=60,
                           capture_output=True, text=True)
        return [l.strip() for l in (r.stdout or "").splitlines() if l.strip().lower().endswith(".lnk")]
    except Exception:
        return []


def ensure_shortcuts():
    """Copie installée : (re)crée les raccourcis une fois par génération de
    raccourcis (corrige le Bureau manquant de la 1.6.0)."""
    try:
        with open(_install_state_path(), encoding="utf-8") as f:
            st = json.load(f)
    except (OSError, ValueError):
        st = {}
    if st.get("raccourcis") == SHORTCUT_VERSION:
        return False
    made = create_shortcuts()
    if made or not IS_WIN:
        st["raccourcis"] = SHORTCUT_VERSION
        try:
            with open(_install_state_path(), "w", encoding="utf-8") as f:
                json.dump(st, f)
        except OSError:
            pass
    return bool(made)


def stop_other_instances():
    """Ferme les autres copies de l'application (y compris d'anciennes versions
    qui ne connaissent pas les signaux), sans toucher au processus courant."""
    if not IS_WIN:
        return
    flags = getattr(subprocess, "CREATE_NO_WINDOW", 0)
    # Un exe PyInstaller « onefile » tourne en deux processus du même nom :
    # le lanceur (parent) et Python (courant). Les deux sont épargnés.
    spare = ["/FI", "PID ne %d" % os.getpid(), "/FI", "PID ne %d" % os.getppid()]
    for extra in ([], ["/F"]):
        subprocess.run(["taskkill", "/IM", EXE_NAME] + spare + extra, creationflags=flags,
                       stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        time.sleep(1.5)


def bootstrap_install(argv, launcher=None):
    """Au lancement d'un exe qui n'est pas la copie installée : installe (si plus
    récent ou absent) puis lance la copie installée. Retourne True si ce
    processus doit s'arrêter là. Sans effet hors exe (Python) ou si
    SGL_PORTABLE=1. / Returns True when this process should exit."""
    if not FROZEN or os.environ.get("SGL_PORTABLE") == "1" or running_from_install():
        return False
    if any(a in argv for a in ("--maj", "--remplacer")):
        return False
    launcher = launcher or (lambda cmd: subprocess.Popen(cmd, close_fds=True))
    cur = installed_version()
    extra = []
    if not cur or is_newer(APP_VERSION, cur):
        stop_other_instances()
        install_copy(sys.executable)
        ensure_shortcuts()
        extra = ["--installe-depuis", sys.executable]
    elif not os.path.isfile(installed_exe()):
        return False
    launcher([installed_exe()] + [a for a in argv if a != "--arriere-plan"] + extra)
    return True


def download_app(info, timeout=180):
    """Télécharge le nouvel exe à côté de la copie installée, vérifie son
    empreinte. Retourne son chemin. / Downloads and verifies the new exe."""
    a = (info or {}).get("app")
    if not a:
        raise E.Erreur("Aucune version de l'application en ligne connue.")
    blob = _http_get(a["url"], timeout, limit=200 * 1024 * 1024)
    if hashlib.sha256(blob).hexdigest() != a["sha256"]:
        raise E.Erreur("Fichier téléchargé altéré (empreinte différente) : mise à jour annulée.")
    os.makedirs(install_dir(), exist_ok=True)
    new = os.path.join(install_dir(), "ShadsunGoldLens.nouveau.exe")
    with open(new, "wb") as f:
        f.write(blob)
    with open(new + ".version", "w", encoding="utf-8") as f:
        f.write(a["version"])
    return new


def start_self_update(new_exe, launcher=None):
    """Lance le nouvel exe en mode remplacement ; l'application doit ensuite se fermer."""
    launcher = launcher or (lambda cmd: subprocess.Popen(cmd, close_fds=True))
    launcher([new_exe, "--remplacer", installed_exe(), "--pid", str(os.getpid())])


def _pid_alive(pid):
    if not pid:
        return False
    if IS_WIN:
        import ctypes
        h = ctypes.windll.kernel32.OpenProcess(0x00100000, False, int(pid))   # SYNCHRONIZE
        if not h:
            return False
        r = ctypes.windll.kernel32.WaitForSingleObject(h, 0)
        ctypes.windll.kernel32.CloseHandle(h)
        return r == 0x102   # WAIT_TIMEOUT : toujours en vie
    try:
        os.kill(int(pid), 0)
        return True
    except OSError:
        return False


def replace_and_relaunch(src, target, pid=None, version=APP_VERSION, wait=60, launcher=None):
    """Mode --remplacer (exécuté par le nouvel exe) : attend la fin de l'ancien
    processus, prend sa place, puis relance l'application installée."""
    launcher = launcher or (lambda cmd: subprocess.Popen(cmd, close_fds=True))
    t0 = time.time()
    while pid and _pid_alive(pid) and time.time() - t0 < wait:
        time.sleep(0.3)
    if _same_path(os.path.dirname(target), install_dir()):
        install_copy(src, version)
    else:
        shutil.copyfile(src, target)
    launcher([target, "--mis-a-jour"])
    return target


def cleanup_update_leftovers():
    """Supprime l'exe de mise à jour resté à côté (il ne pouvait pas s'effacer lui-même)."""
    for p in (os.path.join(install_dir(), "ShadsunGoldLens.nouveau.exe"),
              os.path.join(install_dir(), "ShadsunGoldLens.nouveau.exe.version"),
              installed_exe() + ".copie"):
        try:
            os.remove(p)
        except OSError:
            pass


def can_self_update():
    return FROZEN and running_from_install()


def version_status(addons, info):
    """État affiché dans l'en-tête : [(texte, couleur)] pour l'application et l'add-on.
    couleur : « ok » (à jour), « maj » (nouvelle version), « dim » (non vérifié), « bad »."""
    online = info or {}
    app = online.get("app") or {}
    if app.get("version") and is_newer(app["version"], APP_VERSION):
        a = ("Application %s · %s disponible" % (APP_VERSION, app["version"]), "maj")
    elif online:
        a = ("Application %s · à jour" % APP_VERSION, "ok")
    else:
        a = ("Application %s" % APP_VERSION, "dim")
    inst, bundled = addon_status(addons)
    ov = (online.get("addon") or {}).get("version")
    best = ov if (ov and not is_newer(bundled, ov)) else bundled
    if not inst:
        b = ("Add-on non installé", "bad")
    elif best and is_newer(best, inst):
        b = ("Add-on %s · %s disponible" % (inst, best), "maj")
    elif online or bundled:
        b = ("Add-on %s · à jour" % inst, "ok")
    else:
        b = ("Add-on %s" % inst, "dim")
    return [a, b]


def addon_offer(addons, info):
    """Ce que le bandeau propose : (texte, action) avec action « online », « bundle »,
    « app » ou None. / What the banner offers."""
    inst, bundled = addon_status(addons)
    online = (info or {}).get("addon") or {}
    ov = online.get("version")
    if ov and is_newer(ov, inst) and not is_newer(bundled, ov):
        return ("Add-on : version %s disponible en ligne (installée : %s)." % (ov, inst or "aucune"), "online")
    if bundled and inst != bundled and is_newer(bundled, inst):
        return ("Add-on : version %s disponible (installée : %s)." % (bundled, inst or "aucune"), "bundle")
    if bundled and not inst:
        return ("Add-on : version %s disponible (installée : aucune)." % bundled, "bundle")
    app = (info or {}).get("app") or {}
    if app.get("version") and is_newer(app["version"], APP_VERSION):
        return ("Nouvelle version de l'application : %s (vous avez %s)." % (app["version"], APP_VERSION), "app")
    return ("", None)


# -----------------------------------------------------------------------------
# Démarrage avec Windows, ancienne tâche, ancienne configuration
# -----------------------------------------------------------------------------
def launch_command(*args):
    """Commande qui relance l'application (exe, ou Python sans fenêtre + script)."""
    if FROZEN:
        return [sys.executable] + list(args)
    exe = sys.executable or "python"
    pyw = os.path.join(os.path.dirname(exe), "pythonw.exe")
    if IS_WIN and os.path.exists(pyw):
        exe = pyw
    return [exe, os.path.join(HERE, "sgl_app.py")] + list(args)


def _quote(cmd):
    return " ".join('"%s"' % c if " " in c or not c else c for c in cmd)


def set_startup(enabled):
    if not IS_WIN:
        return False
    import winreg
    with winreg.OpenKey(winreg.HKEY_CURRENT_USER, RUN_KEY, 0, winreg.KEY_SET_VALUE) as k:
        if enabled:
            winreg.SetValueEx(k, APP_ID, 0, winreg.REG_SZ, _quote(launch_command("--arriere-plan")))
        else:
            try:
                winreg.DeleteValue(k, APP_ID)
            except OSError:
                pass
    return True


def startup_enabled():
    if not IS_WIN:
        return False
    import winreg
    try:
        with winreg.OpenKey(winreg.HKEY_CURRENT_USER, RUN_KEY) as k:
            winreg.QueryValueEx(k, APP_ID)
            return True
    except OSError:
        return False


def old_task_exists():
    if not IS_WIN:
        return False
    try:
        code, _ = E.run_schtasks(["/Query", "/TN", E.TASK_NAME])
        return code == 0
    except OSError:
        return False


def remove_old_task():
    """Arrête et supprime la tâche planifiée de l'ancien outil (s'il y en a une)."""
    if not old_task_exists():
        return False
    E.run_schtasks(["/End", "/TN", E.TASK_NAME])
    code, _ = E.run_schtasks(["/Delete", "/F", "/TN", E.TASK_NAME])
    return code == 0


def find_old_config(dirs=None):
    """Configuration de l'ancien outil (.ini), pour la reprendre. dict ou None."""
    for d in (dirs if dirs is not None else OLD_TOOL_DIRS + [HERE]):
        p = os.path.join(d, "sgl_prix_api.ini")
        if not os.path.isfile(p):
            continue
        c = configparser.ConfigParser(interpolation=None)
        try:
            with open(p, encoding="utf-8-sig") as f:
                c.read_file(f)
        except (OSError, configparser.Error):
            continue
        get = lambda s, k: c.get(s, k, fallback="").strip()
        hdv = {fac: get("marche", E.CFG_KEYS[fac]) for fac in E.FACTIONS}
        rs = None
        if hdv["A"].isdigit():
            rs = E.ruleset_of(int(hdv["A"]))
        return {"path": p, "client_id": get("battlenet", "client_id"), "client_secret": get("battlenet", "client_secret"),
                "addons": get("wow", "addons"), "region": get("marche", "region") or "eu", "type_marche": rs}
    return None


# -----------------------------------------------------------------------------
# État des prix (fichier Prix.lua écrit dans AddOns)
# -----------------------------------------------------------------------------
def prices_status(addons):
    """{generated, source, markets: {A: {time, total, house}}} lu dans Prix.lua, ou None."""
    p = os.path.join(addons or "", E.MODULE, "Prix.lua")
    try:
        with open(p, encoding="utf-8") as f:
            head = f.read(4096)
    except OSError:
        return None
    gen = re.search(r"generated = (\d+), source = \"([^\"]*)\"", head) or re.search(r"generated = (\d+)", head)
    out = {"generated": int(gen.group(1)) if gen else int(os.path.getmtime(p)),
           "source": gen.group(2) if gen and gen.lastindex and gen.lastindex >= 2 else "API Blizzard",
           "markets": {}}
    try:
        with open(p, encoding="utf-8") as f:
            for line in f:
                m = re.match(r"ShadsunGoldLensExternal\.markets\.(\w) = \{ time = (\d+), total = (\d+), house = (\d+)", line)
                if m:
                    out["markets"][m.group(1)] = {"time": int(m.group(2)), "total": int(m.group(3)), "house": int(m.group(4))}
    except OSError:
        pass
    return out


def ago(ts, now=None):
    if not ts:
        return "jamais"
    s = max(0, int((now or time.time()) - ts))
    if s < 90:
        return "à l'instant"
    if s < 3600:
        return "il y a %d min" % (s // 60)
    if s < 86400 * 2:
        return "il y a %d h %02d" % (s // 3600, (s % 3600) // 60)
    return "il y a %d jours" % (s // 86400)


# -----------------------------------------------------------------------------
# Mise à jour : dans un processus séparé / update in a child process
# -----------------------------------------------------------------------------
class _Args:
    sortie = None


def run_update_inline(origin="mise à jour"):
    """Mise à jour dans ce processus, notée au journal (utilisé par --maj)."""
    setup_engine()
    cfg = engine_config()
    return E.run_logged(lambda: (E.banner(), E.cmd_update(cfg, _Args()))[1], origin)


def run_update_process(origin="mise à jour horaire", timeout=None):
    """Lance « --maj » dans un processus séparé sans fenêtre ; code de retour."""
    cmd = launch_command("--maj", "--origine", origin)
    flags = 0x08000000 if IS_WIN else 0   # CREATE_NO_WINDOW
    try:
        return subprocess.run(cmd, timeout=timeout or E.WATCHDOG + 120, creationflags=flags,
                              stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL).returncode
    except subprocess.TimeoutExpired:
        return 2
    except OSError:
        return 1


class Scheduler(threading.Thread):
    """Boucle horaire de l'application : vérifie toutes les 30 s s'il faut
    mettre à jour (horloge réelle : une heure dépassée pendant une veille est
    rattrapée au réveil, après 90 s). update_now() force une mise à jour.
    on_event(type, données) est appelé depuis ce fil (l'interface relaie)."""

    def __init__(self, interval_min=60, runner=None, on_event=None, clock=time.time, tick=None):
        super().__init__(daemon=True)
        self.interval = max(30, int(interval_min)) * 60
        self.runner = runner or run_update_process
        self.on_event = on_event or (lambda *a: None)
        self.clock = clock
        self.tick = E.TICK if tick is None else tick
        self._stop = threading.Event()
        self._wake = threading.Event()
        self._now = False
        self.enabled = True
        self.running = False
        self.last_ok = E.last_ok_time()
        self.last_try = 0.0
        self.next_due = 0.0

    def update_now(self):
        self._now = True
        self._wake.set()

    def stop(self):
        self._stop.set()
        self._wake.set()

    def set_interval(self, minutes):
        self.interval = max(30, int(minutes)) * 60
        self._wake.set()

    def _due(self, now):
        if self._now:
            return True
        if not self.enabled:
            return False
        failed = self.last_try > self.last_ok          # dernier essai en échec : attendre le délai de reprise
        return now - self.last_ok >= self.interval and (not failed or now - self.last_try >= E.RETRY)

    def run(self):
        prev = self.clock()
        not_before = 0.0
        while not self._stop.is_set():
            now = self.clock()
            if now - prev > 300:
                not_before = now + 90        # réveil du PC : laisser revenir le réseau
            prev = now
            if self._due(now) and (self._now or now >= not_before):
                forced = self._now
                self._now = False
                self.last_try = now
                self.running = True
                self.on_event("debut", {"force": forced})
                code = self.runner("mise à jour manuelle" if forced else "mise à jour horaire")
                self.running = False
                if code == 0:
                    self.last_ok = self.clock()
                self.on_event("fin", {"code": code})
                prev = self.clock()
            if self.enabled:
                self.next_due = max(self.last_ok + self.interval,
                                    self.last_try + E.RETRY if self.last_try > self.last_ok else 0, not_before)
            else:
                self.next_due = 0
            self._wake.wait(self.tick)
            self._wake.clear()


# -----------------------------------------------------------------------------
# Instance unique / single instance
# -----------------------------------------------------------------------------
def acquire_instance_lock():
    """Verrou de l'application ; None si une autre instance tourne déjà."""
    path = os.path.join(data_dir(), "application.verrou")
    try:
        fh = open(path, "a+")
    except OSError:
        return None
    try:
        if IS_WIN:
            import msvcrt
            fh.seek(0)
            msvcrt.locking(fh.fileno(), msvcrt.LK_NBLCK, 1)
        else:
            import fcntl
            fcntl.flock(fh.fileno(), fcntl.LOCK_EX | fcntl.LOCK_NB)
    except OSError:
        fh.close()
        return None
    return fh


def show_signal_path():
    return os.path.join(data_dir(), "afficher")


def signal_show():
    """Demande à l'instance déjà ouverte de se montrer."""
    try:
        open(show_signal_path(), "w").close()
    except OSError:
        pass


def take_show_signal():
    p = show_signal_path()
    if os.path.exists(p):
        try:
            os.remove(p)
        except OSError:
            pass
        return True
    return False


# -----------------------------------------------------------------------------
# Tests de la source (assistant)
# -----------------------------------------------------------------------------
def test_source(cfg_values, log=print):
    """Vérifie la source choisie. cfg_values : dict {source, region, client_id,
    client_secret}. Retourne (ok, message)."""
    e = configparser.ConfigParser(interpolation=None)
    for sec, vals in E.DEFAULTS.items():
        e[sec] = dict(vals)
    e["source"]["type"] = cfg_values.get("source", "foreverah")
    e["marche"]["region"] = cfg_values.get("region", "eu")
    e["battlenet"]["client_id"] = cfg_values.get("client_id", "")
    e["battlenet"]["client_secret"] = cfg_values.get("client_secret", "")
    try:
        if e["source"]["type"] == "foreverah":
            hs = E.ForeverAH(e).houses()
            if not hs:
                return False, "Forever AH ne liste aucun HDV pour cette région."
            return True, "Forever AH répond : %d HDV pour la région %s." % (len(hs), e["marche"]["region"].upper())
        api = E.Api(e)
        api.get_token()
        n = len(api.houses())
        return True, "Clé acceptée : %d HDV visibles." % n
    except E.Erreur as ex:
        return False, str(ex)
    except Exception as ex:   # réseau, etc.
        return False, "%s : %s" % (type(ex).__name__, ex)


def verify_market_with_scans(forever, cfg_values, log=print):
    """Compare les relevés du jeu aux HDV de chaque type de serveur.
    Retourne (meilleure clé ou None, message)."""
    scans = game_scans(forever)
    if not scans:
        return None, ("Aucun relevé de l'HDV trouvé. En jeu : ouvrez l'HDV, « Lire les annonces », "
                      "puis /reload (ou déconnectez-vous) et recommencez.")
    realm = max(scans, key=lambda r: sum(len(v.get("items", {})) for v in scans[r].values()))
    own = scans[realm]
    e = configparser.ConfigParser(interpolation=None)
    for sec, vals in E.DEFAULTS.items():
        e[sec] = dict(vals)
    e["source"]["type"] = cfg_values.get("source", "foreverah")
    e["marche"]["region"] = cfg_values.get("region", "eu")
    e["battlenet"]["client_id"] = cfg_values.get("client_id", "")
    e["battlenet"]["client_secret"] = cfg_values.get("client_secret", "")
    e["outil"]["cache_minutes"] = "50"
    api = E.ForeverAH(e) if e["source"]["type"] == "foreverah" else E.Api(e)
    cache = {}

    def fetch(hid):
        if hid not in cache:
            try:
                cache[hid] = E.fetch_market(e, hid, api)["items"]
            except E.Erreur:
                cache[hid] = {}
        return cache[hid]
    # Une faction suffit (la plus fournie) : 5 téléchargements au lieu de 15.
    fac = max(own, key=lambda k: len(own[k].get("items", {})))
    log("Relevé utilisé : royaume « %s », %s (%d objets)" % (realm, E.LABELS.get(fac, fac), len(own[fac].get("items", {}))))
    res = E.match_rulesets(own, fetch, factions=[fac], log=log)
    if not res or res[0][0] < 0.25:
        return None, "Aucun type de serveur ne correspond nettement (relevé trop ancien ou trop petit ?)."
    best = res[0]
    return best[1], "%s : %.0f %% de prix identiques sur %d objets." % (E.ruleset_label(best[1]), best[0] * 100, best[2])
