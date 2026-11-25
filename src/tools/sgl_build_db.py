#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
===============================================================================
 Shadsun Gold Lens — Outil de construction de la base PNJ / NPC catalog builder
 Auteur : Tarak Ben Abda – novembre 2026
 Version : 0.4.0
-------------------------------------------------------------------------------
 FR : Construit Data/Catalog.lua (base intégrée de l'add-on) à partir de :
      1. la base de référence v0.3.0 (QuestieDB Forever + tarifs CMaNGOS),
      2. les observations Forever (Efficient Games / EG Link, CC BY 4.0),
      3. un CSV facultatif d'ajouts manuels vérifiés,
      4. facultativement, le fichier SavedVariables de l'add-on
         (observations faites en jeu par vos personnages).
      Aucune requête Internet n'est effectuée : les fichiers sources doivent
      être téléchargés au préalable, conformément aux licences des sources.
 EN : Builds Data/Catalog.lua from local source files only (no network).
-------------------------------------------------------------------------------
 Utilisation / Usage :
   python sgl_build_db.py --reference input/Reference_v030.lua \
                          --observed  input/Vendors_v030.lua \
                          [--manual input/manual.csv] \
                          [--savedvariables "WTF/.../SavedVariables/ShadsunGoldLens.lua"] \
                          --out ../../ShadsunGoldLens/Data/Catalog.lua \
                          --report ../docs/RAPPORT-BASE.md
 Dépendances / Dependencies : Python 3.8+ (bibliothèque standard uniquement).
===============================================================================
"""
import argparse
import csv
import datetime as _dt
import hashlib
import json
import os
import re
import sys

AUTHOR = "Tarak Ben Abda"
TOOL_VERSION = "0.4.0"

# ---------------------------------------------------------------------------
# Drapeaux / flags — doivent rester identiques à Core/Catalog.lua
# ---------------------------------------------------------------------------
R_REF, R_EG, R_LIMITED, R_EXTCOST = 1, 2, 4, 8
R_PRICE_FOREVER, R_PRICE_REF_ONLY, R_PRICE_EG_ONLY = 16, 32, 64
R_QTY_CHANGED, R_PRICE_UNCERTAIN, R_MANUAL, R_OBS_LOWER, R_WEB = 128, 256, 512, 1024, 2048

N_REF, N_EG, N_MOVES, N_NOPOS, N_SIDE_CONFLICT, N_SIDE_UNKNOWN, N_MANUAL = 1, 2, 4, 8, 16, 32, 64


def banner():
    line = "=" * 70
    print(line)
    print(" Shadsun Gold Lens — constructeur de base / catalog builder v" + TOOL_VERSION)
    print(" Auteur : " + AUTHOR)
    print(line)


# ---------------------------------------------------------------------------
# Analyseur de littéraux Lua (sous-ensemble) / minimal Lua literal parser
# Gère : tables { }, [clé] = valeur, clé = valeur, nombres, chaînes "..." '...'
#        et [[...]], true/false/nil, commentaires -- et --[[ ]].
# ---------------------------------------------------------------------------
class LuaParser:
    _num = re.compile(r"-?(?:0[xX][0-9a-fA-F]+|\d+\.?\d*(?:[eE][-+]?\d+)?|\.\d+(?:[eE][-+]?\d+)?)")
    _ident = re.compile(r"[A-Za-z_][A-Za-z0-9_]*")

    def __init__(self, text):
        self.s = text
        self.i = 0
        self.n = len(text)

    def error(self, msg):
        line = self.s.count("\n", 0, self.i) + 1
        raise ValueError("Lua parse error line %d: %s" % (line, msg))

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
        esc = {"n": "\n", "t": "\t", "r": "\r", "\\": "\\", '"': '"', "'": "'", "\n": "\n", "a": "\a", "b": "\b", "f": "\f", "v": "\v"}
        while self.i < self.n:
            c = self.s[self.i]
            if c == "\\":
                nx = self.s[self.i + 1]
                if nx.isdigit():
                    m = re.match(r"\d{1,3}", self.s[self.i + 1:])
                    out.append(chr(int(m.group(0))))
                    self.i += 1 + len(m.group(0))
                    continue
                out.append(esc.get(nx, nx))
                self.i += 2
                continue
            if c == q:
                self.i += 1
                raw = "".join(out)
                # Les fichiers WoW sont en UTF-8 : on ré-interprète les octets.
                try:
                    return raw.encode("latin-1").decode("utf-8")
                except (UnicodeEncodeError, UnicodeDecodeError):
                    return raw
            out.append(c)
            self.i += 1
        self.error("unterminated string")

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
            return int(v) if v.is_integer() and "." not in t and "e" not in t.lower() else v
        m = self._ident.match(self.s, self.i)
        if m:
            self.i = m.end()
            w = m.group(0)
            if w == "true":
                return True
            if w == "false":
                return False
            if w == "nil":
                return None
            self.error("unexpected identifier %r" % w)
        self.error("unexpected character %r" % c)

    def table(self):
        self.i += 1  # {
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
                    self.error("expected ]")
                self.i += 1
                if self.peek() != "=":
                    self.error("expected =")
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


def parse_assignments(text):
    """Retourne {nom_complet: valeur} pour les affectations de premier niveau.
    Gère `addon.x = {...}`, `addon.x[12] = {...}` et `Name = {...}`."""
    res = {}
    pat = re.compile(r"^([A-Za-z_][\w\.]*)(\[(\d+)\])?\s*=\s*", re.M)
    pos = 0
    while True:
        m = pat.search(text, pos)
        if not m:
            break
        p = LuaParser(text)
        p.i = m.end()
        try:
            val = p.value()
        except ValueError:
            pos = m.end()
            continue
        name, idx = m.group(1), m.group(3)
        if idx is not None:
            res.setdefault(name, {})
            if isinstance(res[name], list):
                res[name] = {i + 1: v for i, v in enumerate(res[name])}
            res[name][int(idx)] = val
        else:
            if name in res and isinstance(res[name], dict) and isinstance(val, dict):
                val.update(res[name])
            res[name] = val
        pos = p.i
    return res


def as_list(t):
    if t is None:
        return []
    if isinstance(t, list):
        return t
    return [t[k] for k in sorted(t) if isinstance(k, int)]


def sha256(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 16), b""):
            h.update(chunk)
    return h.hexdigest()


# ---------------------------------------------------------------------------
# Chargement des sources / source loading
# ---------------------------------------------------------------------------
def load_reference(path):
    with open(path, encoding="utf-8") as f:
        a = parse_assignments(f.read())
    return {
        "vendors": a.get("addon.referenceVendors", {}),
        "offers": a.get("addon.referenceOffers", {}),
        "names": a.get("addon.referenceNames", {}),
        "known": a.get("addon.knownItems", {}),
    }


def load_observed(path):
    with open(path, encoding="utf-8") as f:
        a = parse_assignments(f.read())
    return {"vendors": a.get("addon.vendors", {}), "offers": a.get("addon.offers", {})}


def load_manual(path):
    """CSV séparé par des points-virgules (Excel FR) ou des virgules.
    Colonnes : itemID;npcID;npcName;side;mapID;x;y;price;quantity;limited;source;note"""
    rows = []
    with open(path, encoding="utf-8-sig", newline="") as f:
        sample = f.read(2048)
        f.seek(0)
        dialect = csv.Sniffer().sniff(sample, delimiters=";,")
        for r in csv.DictReader(f, dialect=dialect):
            if not r.get("itemID") or not r.get("npcID"):
                continue
            def num(k, cast=float):
                v = (r.get(k) or "").strip().replace(",", ".")
                return cast(v) if v else None
            rows.append({
                "item": int(num("itemID", float)), "npc": int(num("npcID", float)),
                "name": (r.get("npcName") or "").strip(), "side": (r.get("side") or "?").strip().upper() or "?",
                "map": num("mapID", lambda v: int(float(v))), "x": num("x"), "y": num("y"),
                "price": num("price", lambda v: int(float(v))), "qty": num("quantity", lambda v: int(float(v))) or 1,
                "limited": (r.get("limited") or "").strip().lower() in ("1", "true", "oui", "yes"),
                "source": (r.get("source") or "manuel").strip(), "note": (r.get("note") or "").strip(),
            })
    return rows


def load_savedvariables(path):
    with open(path, encoding="utf-8", errors="replace") as f:
        a = parse_assignments(f.read())
    g = a.get("ShadsunGoldLensGlobal") or {}
    return {"observations": g.get("observations") or {}, "npcs": g.get("observedNPCs") or {}}


# ---------------------------------------------------------------------------
# Fusion / merge
# ---------------------------------------------------------------------------
def norm_side(s):
    if s in ("A", "H"):
        return s
    if s in ("AH", "N"):
        return "N"
    return "?"


def build(args):
    ref = load_reference(args.reference)
    obs = load_observed(args.observed)
    manual = load_manual(args.manual) if args.manual else []
    sv = load_savedvariables(args.savedvariables) if args.savedvariables else None

    npcs = {}

    def npc_entry(nid):
        return npcs.setdefault(nid, {"en": None, "fr": None, "side": None, "pos": None, "alt": None, "flags": 0})

    # --- PNJ de référence (QuestieDB Forever + noms pfQuest) ---
    for nid, v in ref["vendors"].items():
        v = as_list(v) if not isinstance(v, list) else v
        v = v + [None] * (6 - len(v))
        e = npc_entry(int(nid))
        e["en"] = v[0]
        if v[5] and v[5] != v[0]:
            e["fr"] = v[5]
        e["side"] = norm_side(v[1])
        if v[2] and v[3] is not None and v[4] is not None:
            e["pos"] = (int(v[2]), float(v[3]), float(v[4]))
        e["flags"] |= N_REF

    # --- PNJ observés sur Forever (EG Link) ---
    for nid, v in obs["vendors"].items():
        v = as_list(v) if not isinstance(v, list) else v
        v = v + [None] * (5 - len(v))
        e = npc_entry(int(nid))
        if not e["en"]:
            e["en"] = v[0]
        egside = v[1]
        if egside in ("A", "H"):
            if e["side"] and e["side"] != "?" and e["side"] != egside:
                e["flags"] |= N_SIDE_CONFLICT
            e["side"] = egside
        elif not e["side"]:
            e["side"] = "?"
        if v[2] and v[3] is not None and v[4] is not None:
            egpos = (int(v[2]), float(v[3]), float(v[4]))
            if e["pos"]:
                rp = e["pos"]
                if rp[0] != egpos[0] or abs(rp[1] - egpos[1]) > 3 or abs(rp[2] - egpos[2]) > 3:
                    e["flags"] |= N_MOVES
                    e["alt"] = rp
            e["pos"] = egpos  # la position observée en jeu Forever prime
        e["flags"] |= N_EG

    # --- lignes d'offres / offer rows : clé (item, npc, qty, ext) ---
    rows = {}
    ref_qty = {}
    for iid, lst in ref["offers"].items():
        for r in as_list(lst):
            r = list(r) + [None] * (7 - len(r))
            npc, price, qty, limited, ext, build_tag, cond = r[:7]
            k = (int(iid), int(npc), int(qty or 1), bool(ext))
            ref_qty[(int(iid), int(npc))] = int(qty or 1)
            row = rows.setdefault(k, {"ref": None, "eg": None, "limited": False, "cond": 0, "web": False, "manual": None, "build": None})
            row["ref"] = int(price or 0)
            row["limited"] = row["limited"] or bool(limited)
            row["cond"] = int(cond or 0)

    for iid, lst in obs["offers"].items():
        for r in as_list(lst):
            r = list(r) + [None] * (6 - len(r))
            npc, price, qty, limited, ext, build_tag = r[:6]
            iid_i, npc_i, qty_i = int(iid), int(npc), int(qty or 1)
            k = (iid_i, npc_i, qty_i, bool(ext))
            row = rows.setdefault(k, {"ref": None, "eg": None, "limited": False, "cond": 0, "web": False, "manual": None, "build": None})
            tag = str(build_tag or "")
            if tag.startswith("1.60"):
                row["eg"] = int(price or 0)
                row["build"] = tag
            elif "Zephras" in tag or "Codex" in tag:
                row["web"] = True
                row["eg_web"] = int(price or 0)
            elif tag == "Classic":
                if row["ref"] is None:
                    row["ref"] = int(price or 0)
            row["limited"] = row["limited"] or bool(limited)
            # Quantité modifiée sur Forever : la ligne de référence est remplacée.
            rq = ref_qty.get((iid_i, npc_i))
            if tag.startswith("1.60") and rq is not None and rq != qty_i:
                old = (iid_i, npc_i, rq, bool(ext))
                if old in rows and rows[old]["eg"] is None:
                    del rows[old]
                row["qty_changed"] = True

    for m in manual:
        k = (m["item"], m["npc"], m["qty"], False)
        row = rows.setdefault(k, {"ref": None, "eg": None, "limited": False, "cond": 0, "web": False, "manual": None, "build": None})
        row["manual"] = m["price"]
        row["limited"] = row["limited"] or m["limited"]
        e = npc_entry(m["npc"])
        e["flags"] |= N_MANUAL
        if not e["en"]:
            e["en"] = m["name"] or ("PNJ #%d" % m["npc"])
        if not e["side"] or e["side"] == "?":
            e["side"] = norm_side(m["side"])
        if m["map"] and m["x"] is not None and m["y"] is not None and not e["pos"]:
            e["pos"] = (m["map"], m["x"], m["y"])

    sv_rows = 0
    if sv:
        for iid, entries in (sv["observations"] or {}).items():
            for _, o in (entries or {}).items():
                if not isinstance(o, dict) or not o.get("npc"):
                    continue
                k = (int(iid), int(o["npc"]), int(o.get("qty") or 1), bool(o.get("ext")))
                row = rows.setdefault(k, {"ref": None, "eg": None, "limited": False, "cond": 0, "web": False, "manual": None, "build": None})
                if row["eg"] is None or (o.get("price") or 0) > row["eg"]:
                    row["eg"] = int(o.get("price") or 0)
                    row["build"] = str(o.get("build") or "SavedVariables")
                if o.get("stock") is not None and o.get("stock") >= 0:
                    row["limited"] = True
                e = npc_entry(int(o["npc"]))
                e["flags"] |= N_EG
                if not e["en"]:
                    e["en"] = o.get("name") or ("PNJ #%d" % int(o["npc"]))
                if o.get("side") in ("A", "H", "N") and (not e["side"] or e["side"] == "?"):
                    e["side"] = o["side"]
                if o.get("map") and o.get("x") is not None and not e["pos"]:
                    e["pos"] = (int(o["map"]), float(o["x"]), float(o["y"]))
                sv_rows += 1

    # --- prix de base par (objet, quantité) / base price per (item, qty) ---
    groups = {}
    for (iid, npc, qty, ext), row in rows.items():
        if not ext:
            groups.setdefault((iid, qty), []).append(row)
    base = {}
    for key, lst in groups.items():
        refs = [r["ref"] for r in lst if r["ref"]]
        egs = [r["eg"] for r in lst if r["eg"]]
        mans = [r["manual"] for r in lst if r["manual"]]
        webs = [r.get("eg_web") for r in lst if r.get("eg_web")]
        flags = 0
        if mans:
            b = max(mans)
            flags |= R_MANUAL
        elif refs and egs:
            rp, em = max(refs), max(egs)
            ratio = em / rp if rp else 1
            if 0.85 <= ratio <= 1.0001:
                b = rp  # écart = remise de réputation des observateurs
            else:
                b = em
                flags |= R_PRICE_FOREVER
                if len(set(egs)) == 1:
                    flags |= R_PRICE_UNCERTAIN
        elif refs:
            b = max(refs)
            flags |= R_PRICE_REF_ONLY
        elif egs:
            b = max(egs)
            flags |= R_PRICE_EG_ONLY
            if len(set(egs)) == 1 and len(egs) < 3:
                flags |= R_PRICE_UNCERTAIN
        elif webs:
            b = max(webs)
            flags |= R_PRICE_EG_ONLY | R_PRICE_UNCERTAIN
        else:
            b = 0
        base[key] = (b, flags)

    # --- émission par objet / per-item emission ---
    items = {}
    for (iid, npc, qty, ext), row in rows.items():
        if npc not in npcs:
            continue
        f = 0
        if row["ref"] is not None:
            f |= R_REF
        if row["eg"] is not None:
            f |= R_EG
        if row.get("web"):
            f |= R_WEB
        if row["manual"] is not None:
            f |= R_MANUAL
        if row["limited"]:
            f |= R_LIMITED
        if row.get("qty_changed"):
            f |= R_QTY_CHANGED
        obs_price = 0
        if ext:
            f |= R_EXTCOST
            price = row["eg"] if row["eg"] is not None else (row["ref"] or 0)
        else:
            price, bflags = base[(iid, qty)]
            f |= bflags
            if row["eg"] and row["eg"] < price:
                obs_price = row["eg"]
                f |= R_OBS_LOWER
        items.setdefault(iid, []).append((npc, price, qty, f, row["cond"] or 0, obs_price))

    for iid in items:
        items[iid].sort(key=lambda t: (t[0], t[2]))

    used = set(n for lst in items.values() for t in lst for n in [t[0]])
    for nid, e in npcs.items():
        if not e["pos"]:
            e["flags"] |= N_NOPOS
        if e["side"] in (None, "?"):
            e["side"] = "?"
            e["flags"] |= N_SIDE_UNKNOWN

    names = {}
    for iid, nm in ref["names"].items():
        if int(iid) in items:
            names[int(iid)] = nm

    known = sorted(set(int(k) for k, v in ref["known"].items() if v) | set(items.keys()))
    return npcs, items, names, known, used, sv_rows, manual


# ---------------------------------------------------------------------------
# Statistiques / statistics (calculées sur le résultat réel)
# ---------------------------------------------------------------------------
def stats(npcs, items, used, known):
    s = {"items": len(items), "known_items": len(known)}
    s["npcs_used"] = len(used)
    s["pairs"] = sum(len(v) for v in items.values())
    s["items_with_gold_price"] = sum(1 for v in items.values() if any(t[1] > 0 and not t[3] & R_EXTCOST for t in v))
    s["items_extcost_only"] = sum(1 for v in items.values() if all(t[3] & R_EXTCOST for t in v))
    s["items_confirmed_forever"] = sum(1 for v in items.values() if any(t[3] & (R_EG | R_MANUAL) for t in v))
    s["items_reference_only"] = sum(1 for v in items.values() if all(t[3] & R_REF and not t[3] & (R_EG | R_MANUAL | R_WEB) for t in v))
    s["items_price_forever_changed"] = sum(1 for v in items.values() if any(t[3] & R_PRICE_FOREVER for t in v))
    s["items_with_location"] = sum(1 for v in items.values() if any(npcs[t[0]]["pos"] for t in v))
    s["items_with_reliable_coords"] = sum(1 for v in items.values() if any(npcs[t[0]]["pos"] and npcs[t[0]]["flags"] & N_EG and not npcs[t[0]]["flags"] & N_MOVES for t in v))
    sides = {"A": 0, "H": 0, "N": 0, "?": 0}
    for v in items.values():
        ss = set(npcs[t[0]]["side"] for t in v)
        if "N" in ss or ("A" in ss and "H" in ss):
            sides["N"] += 1
        elif ss == {"A"}:
            sides["A"] += 1
        elif ss == {"H"}:
            sides["H"] += 1
        elif "?" in ss and len(ss - {"?"}) == 0:
            sides["?"] += 1
        else:
            # mélange d'une faction connue et de vendeurs à faction inconnue
            sides["?"] += 1
    s["items_alliance_only"] = sides["A"]
    s["items_horde_only"] = sides["H"]
    s["items_both_factions"] = sides["N"]
    s["items_faction_uncertain"] = sides["?"]
    u = [npcs[n] for n in used]
    s["npcs_with_coords"] = sum(1 for e in u if e["pos"])
    s["npcs_without_coords"] = sum(1 for e in u if not e["pos"])
    s["npcs_moving"] = sum(1 for e in u if e["flags"] & N_MOVES)
    s["npcs_side_unknown"] = sum(1 for e in u if e["side"] == "?")
    s["npcs_side_conflict"] = sum(1 for e in u if e["flags"] & N_SIDE_CONFLICT)
    s["npcs_alliance"] = sum(1 for e in u if e["side"] == "A")
    s["npcs_horde"] = sum(1 for e in u if e["side"] == "H")
    s["npcs_neutral"] = sum(1 for e in u if e["side"] == "N")
    s["rows_incomplete"] = sum(1 for v in items.values() for t in v if not npcs[t[0]]["pos"] or (t[1] <= 0 and not t[3] & R_EXTCOST) or npcs[t[0]]["side"] == "?")
    s["rows_conditional"] = sum(1 for v in items.values() for t in v if t[4])
    s["rows_limited"] = sum(1 for v in items.values() for t in v if t[3] & R_LIMITED)
    s["rows_observed_discount"] = sum(1 for v in items.values() for t in v if t[3] & R_OBS_LOWER)
    return s


# ---------------------------------------------------------------------------
# Écriture Lua / Lua writer
# ---------------------------------------------------------------------------
def lua_str(s):
    if s is None:
        return "false"
    return '"' + str(s).replace("\\", "\\\\").replace('"', '\\"').replace("\n", "\\n") + '"'


def lua_num(v):
    if v is None:
        return "false"
    if isinstance(v, float):
        r = round(v, 2)
        return ("%g" % r) if r != int(r) else str(int(r))
    return str(v)


def ranges(sorted_ids):
    out, start, prev = [], None, None
    for i in sorted_ids:
        if start is None:
            start = prev = i
        elif i == prev + 1:
            prev = i
        else:
            out += [start, prev - start + 1]
            start = prev = i
    if start is not None:
        out += [start, prev - start + 1]
    return out


def write_lua(path, npcs, items, names, known, used, st, meta):
    L = []
    w = L.append
    w("-- =============================================================================")
    w("-- Shadsun Gold Lens — Data/Catalog.lua (FICHIER GÉNÉRÉ / GENERATED FILE)")
    w("-- Auteur : Tarak Ben Abda – novembre 2026")
    w("-- Généré par tools/sgl_build_db.py v%s le %s. Ne pas modifier à la main." % (TOOL_VERSION, meta["date"]))
    w("-- Sources : QuestieDB Forever (GPLv3), CMaNGOS Classic DB (GPLv3),")
    w("--           Efficient Games / EG Link (CC BY 4.0), pfQuest (MIT) — voir LISEZ-MOI.md.")
    w("-- =============================================================================")
    w("local _, ns = ...")
    w("local D = {}")
    w("ns.Data = D")
    w("D.meta = {")
    w("  version = %s," % lua_str(meta["date"]))
    w("  builder = %s," % lua_str("sgl_build_db.py " + TOOL_VERSION))
    w("  observedBuilds = %s," % lua_str(meta["builds"]))
    for k in sorted(st):
        w("  %s = %d," % (k, st[k]))
    w("}")
    w("-- PNJ : {nomEN, nomFR|false, faction A/H/N/?, uiMapID|false, x|false, y|false, drapeaux, altMap, altX, altY}")
    w("D.npcs = {")
    for nid in sorted(used):
        e = npcs[nid]
        pos = e["pos"] or (None, None, None)
        parts = [lua_str(e["en"] or ("PNJ #%d" % nid)), lua_str(e["fr"]), lua_str(e["side"]),
                 lua_num(pos[0]), lua_num(pos[1]), lua_num(pos[2]), str(e["flags"])]
        if e["alt"]:
            parts += [lua_num(e["alt"][0]), lua_num(e["alt"][1]), lua_num(e["alt"][2])]
        w("  [%d]={%s}," % (nid, ",".join(parts)))
    w("}")
    w("-- Offres : liste plate par objet, 6 champs par vendeur :")
    w("-- npcID, prixBase(cuivre, par lot), quantitéLot, drapeaux, conditionCMaNGOS, prixObservéInférieur")
    w("D.items = {")
    for iid in sorted(items):
        flat = []
        for t in items[iid]:
            flat += [str(t[0]), str(t[1]), str(t[2]), str(t[3]), str(t[4]), str(t[5])]
        w("  [%d]={%s}," % (iid, ",".join(flat)))
    w("}")
    w("-- Noms anglais de référence (recherche) / English reference names")
    w("D.names = {")
    for iid in sorted(names):
        w("  [%d]=%s," % (iid, lua_str(names[iid])))
    w("}")
    w("-- Objets connus de QuestieDB (couples début,longueur) / known item ranges")
    rg = ranges(known)
    chunks = [",".join(str(x) for x in rg[i:i + 40]) for i in range(0, len(rg), 40)]
    w("D.knownRanges = {")
    for c in chunks:
        w("  " + c + ",")
    w("}")
    with open(path, "w", encoding="utf-8", newline="\n") as f:
        f.write("\n".join(L) + "\n")


def write_report(path, st, meta, hashes, manual_n, sv_rows):
    labels = [
        ("items", "Objets vendus par au moins un PNJ"),
        ("known_items", "Objets connus des bases (avec ou sans vendeur)"),
        ("pairs", "Associations objet–vendeur"),
        ("npcs_used", "PNJ marchands distincts"),
        ("items_with_gold_price", "Objets avec prix d'achat en or valide"),
        ("items_extcost_only", "Objets payables uniquement en devise/objet"),
        ("items_confirmed_forever", "Objets confirmés sur Forever (observés)"),
        ("items_reference_only", "Objets en référence Classic seulement (à vérifier)"),
        ("items_price_forever_changed", "Objets dont le prix Forever diffère de Classic"),
        ("items_with_location", "Objets avec au moins un vendeur localisé"),
        ("items_with_reliable_coords", "Objets avec coordonnées observées sur Forever (vendeur fixe)"),
        ("items_alliance_only", "Objets vendus uniquement par des PNJ Alliance"),
        ("items_horde_only", "Objets vendus uniquement par des PNJ Horde"),
        ("items_both_factions", "Objets accessibles aux deux factions"),
        ("items_faction_uncertain", "Objets à faction incertaine"),
        ("npcs_with_coords", "PNJ avec coordonnées"),
        ("npcs_without_coords", "PNJ sans coordonnées (instances, inconnus)"),
        ("npcs_moving", "PNJ itinérants / position variable"),
        ("npcs_alliance", "PNJ Alliance"), ("npcs_horde", "PNJ Horde"), ("npcs_neutral", "PNJ neutres"),
        ("npcs_side_unknown", "PNJ à faction inconnue"),
        ("npcs_side_conflict", "PNJ dont la faction diffère entre sources"),
        ("rows_incomplete", "Associations incomplètes (prix, position ou faction manquants)"),
        ("rows_conditional", "Associations soumises à condition (réputation, événement)"),
        ("rows_limited", "Associations à stock limité"),
        ("rows_observed_discount", "Associations dont le prix observé inclut une remise"),
    ]
    out = ["# Rapport de construction de la base — Shadsun Gold Lens %s" % TOOL_VERSION, "",
           "Auteur : Tarak Ben Abda. Généré le %s par `tools/sgl_build_db.py`." % meta["date"], "",
           "Les chiffres ci-dessous sont recalculés à partir des fichiers réellement fusionnés.", "",
           "| Indicateur | Valeur |", "|---|---:|"]
    for k, lab in labels:
        out.append("| %s | %d |" % (lab, st.get(k, 0)))
    out += ["", "Ajouts manuels (CSV) : %d. Observations SavedVariables fusionnées : %d." % (manual_n, sv_rows), "",
            "## Empreintes des fichiers sources", "", "| Fichier | SHA-256 |", "|---|---|"]
    for k, v in hashes.items():
        out.append("| %s | `%s` |" % (k, v))
    with open(path, "w", encoding="utf-8", newline="\n") as f:
        f.write("\n".join(out) + "\n")


def main():
    banner()
    ap = argparse.ArgumentParser(description="Construit Data/Catalog.lua — Tarak Ben Abda")
    ap.add_argument("--reference", required=True)
    ap.add_argument("--observed", required=True)
    ap.add_argument("--manual")
    ap.add_argument("--savedvariables")
    ap.add_argument("--out", required=True)
    ap.add_argument("--report")
    ap.add_argument("--json")
    ap.add_argument("--date", default=_dt.date.today().isoformat())
    a = ap.parse_args()

    npcs, items, names, known, used, sv_rows, manual = build(a)
    st = stats(npcs, items, used, known)
    builds = set()
    with open(a.observed, encoding="utf-8") as f:
        builds.update(re.findall(r'"(1\.60\.\d+\.\d+)"', f.read()))
    meta = {"date": a.date, "builds": (min(builds) + " à " + max(builds)) if builds else "aucun"}
    write_lua(a.out, npcs, items, names, known, used, st, meta)
    hashes = {os.path.basename(p): sha256(p) for p in [a.reference, a.observed, a.manual, a.savedvariables] if p}
    if a.report:
        write_report(a.report, st, meta, hashes, len(manual), sv_rows)
    if a.json:
        with open(a.json, "w", encoding="utf-8") as f:
            json.dump(st, f, indent=2, ensure_ascii=False)
    for k in sorted(st):
        print("  %-32s %d" % (k, st[k]))
    print("Écrit / written: " + a.out)


if __name__ == "__main__":
    sys.exit(main())
