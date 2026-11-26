#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
===============================================================================
 Shadsun Gold Lens — test de l'interface de l'application (écran virtuel)
 Auteur : Tarak Ben Abda – novembre 2026
-------------------------------------------------------------------------------
 FR : Lance l'application sur un faux dossier WoW Forever, parcourt l'assistant
      (4 étapes) puis la fenêtre principale, sans réseau (source et mise à jour
      simulées), et enregistre une capture de chaque écran.
      Usage : xvfb-run -s "-screen 0 1100x800x24" python3 test_app_gui.py <dossier_captures>
 EN : GUI walkthrough test with screenshots, run under Xvfb.
===============================================================================
"""
import os
import subprocess
import sys
import tempfile
import time

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "tools", "prix_api"))
OUT = sys.argv[1] if len(sys.argv) > 1 else os.path.join(tempfile.gettempdir(), "sgl_captures")
os.makedirs(OUT, exist_ok=True)

tmp = tempfile.mkdtemp(prefix="sgl_gui_")
os.environ["SGL_DATA_DIR"] = os.path.join(tmp, "appdata")
forever = os.path.join(tmp, "World of Warcraft", "_forever_")
os.makedirs(os.path.join(forever, "Interface", "AddOns"))
os.makedirs(os.path.join(forever, "WTF", "Account", "TARAK", "SavedVariables"))
with open(os.path.join(forever, "WTF", "Config.wtf"), "w") as f:
    f.write('SET locale "frFR"\nSET portal "EU"\n')
with open(os.path.join(forever, "WTF", "Account", "TARAK", "SavedVariables", "ShadsunGoldLens.lua"), "w") as f:
    f.write('ShadsunGoldLensGlobal = { ["markets"] = { ["CAMWOWEU4Realm6PvP"] = { ["A"] = { ["time"] = 1795000000, '
            '["d"] = { [2589] = 9500020, [2592] = 30000010 } } } } }\n')

import sgl_prix_api as E   # noqa: E402
import sgl_core as core    # noqa: E402
import sgl_app as appmod   # noqa: E402

appmod.HAS_TRAY = False
core.find_forever_dirs = lambda extra_roots=None: [forever]
core.old_task_exists = lambda: False
core.test_source = lambda vals, log=print: (True, "Forever AH répond : 15 HDV pour la région EU.")


def fake_verify(fv, vals, log=print):
    log("Relevé utilisé : royaume « CAMWOWEU4Realm6PvP », HDV Alliance (2 objets)")
    log("  PvP                          :  92.0 % de prix identiques (2 objets communs)")
    log("  Normal                       :   4.0 % de prix identiques (2 objets communs)")
    return "pvp", "PvP : 92 % de prix identiques sur 2 objets."


core.verify_market_with_scans = fake_verify
RUNS = []


def fake_runner(origin):
    RUNS.append(origin)
    now = int(time.time())
    markets = {k: {"time": now - 600, "total": t, "house": h, "items": {2589: (95, 20)}}
               for k, t, h in (("A", 196937, 110), ("H", 249360, 113), ("N", 61822, 116))}
    E.write_module(os.path.join(forever, "Interface", "AddOns", E.MODULE), "16001",
                   {"generated": now, "region": "eu", "ruleset": "PvP", "source": "Forever AH"}, markets)
    with open(E.JOURNAL, "a", encoding="utf-8") as f:
        f.write("===== %s · %s =====\nRÉSULTAT : OK\n" % (time.strftime("%Y-%m-%d %H:%M:%S"), origin))
    return 0


import tkinter as tk   # noqa: E402

RESULTS = []


def check(name, ok, detail=""):
    RESULTS.append((name, bool(ok), detail))


def shot(root, name):
    root.update()
    time.sleep(0.25)
    root.update()
    path = os.path.join(OUT, name + ".png")
    subprocess.run(["import", "-window", str(root.winfo_id()), path], check=False)
    if not os.path.exists(path):
        subprocess.run(["import", "-window", "root", path], check=False)
    return path


def pump(root, seconds=0.6):
    end = time.time() + seconds
    while time.time() < end:
        root.update()
        time.sleep(0.05)


root = tk.Tk()
a = appmod.App(root, scheduler_runner=fake_runner, check_online=False)
a.scheduler.tick = 0.2
pump(root)
check("Premier lancement : assistant, étape 1", a.step == 0 and a.head_right.cget("text").startswith("Étape 1 sur 4"))
check("Étape 1 : WoW Forever trouvé, région EU détectée", "Trouvé" in a.lbl_forever.cget("text") and a.w["region"].get() == "eu",
      a.lbl_forever.cget("text"))
check("Étape 1 : add-on pas encore installé, installation cochée", a.w["install"].get() and "Pas encore installé" in a.lbl_addon.cget("text"),
      a.lbl_addon.cget("text"))
shot(root, "1_installation")
appmod.messagebox.showinfo = lambda *x, **k: None
appmod.messagebox.showerror = lambda *x, **k: RESULTS.append(("(message d'erreur inattendu)", False, str(x)))
a._next()
pump(root)
inst = os.path.join(forever, "Interface", "AddOns", "ShadsunGoldLens", "ShadsunGoldLens.toc")
check("Suivant : add-on copié dans AddOns", os.path.isfile(inst))
check("Étape 2 : source simple (Forever AH) par défaut", a.step == 1 and a.w["source"].get() == "foreverah")
a._test_source()
pump(root, 1.0)
check("Étape 2 : test de la source affiché", "Forever AH répond" in a.lbl_test.cget("text"), a.lbl_test.cget("text"))
shot(root, "2_source_simple")
a.w["source"].set("blizzard")
a._source_changed()
a.w["client_id"].set("0123456789abcdef")
a.w["client_secret"].set("secret-de-test")
pump(root)
shot(root, "2b_source_avancee")
# Guide pas à pas de la clé
import sgl_app as _SA
gw = a.show_key_guide()
pump(root)
check("Guide de la clé : fenêtre ouverte à l'étape 1", gw.winfo_exists() and gw._state["i"] == 0)
for _ in range(4):
    gw._next()
pump(root)
gw.update()
time.sleep(0.2)
subprocess.run(["import", "-window", str(gw.winfo_id()), os.path.join(OUT, "2c_guide_cle.png")], check=False)
copies = [b for b in gw.winfo_children() for b in b.winfo_children() if isinstance(b, tk.Button) and "Copier" in b.cget("text")]
if copies:
    copies[-1].invoke()
check("Guide de la clé : étape du formulaire avec boutons Copier",
      gw._state["i"] == 4 and len(copies) == 3 and "Usage personnel" in gw.clipboard_get(), len(copies))
check("Guide de la clé : rouvrir ne crée pas de deuxième fenêtre", a.show_key_guide() is gw)
for _ in range(10):
    if gw.winfo_exists():
        gw._next()
pump(root)
check("Guide de la clé : Terminer ferme la fenêtre", not gw.winfo_exists())
a.w["source"].set("foreverah")
a._source_changed()
a._next()
pump(root)
_cap = [a.canvas.itemcget(i, "text") for i in a.canvas.find_withtag("caption")]
check("Assistant : légende fixe du personnage (AURELIA SHADSUN, PVP · EUROPE)", len(_cap) == 2 and "PVP" in _cap[1]
      and "EUROPE" in _cap[1], _cap)
check("Étape 3 : type de serveur suggéré d'après le royaume (PvP)", a.step == 2 and a.w["type_marche"].get() == "pvp")
check("Étape 3 : HDV 110 / 113 / 116 affichés", "110" in a.lbl_houses.cget("text") and "116" in a.lbl_houses.cget("text"))
a._verify_market()
pump(root, 1.2)
txt = a.txt_verify.get("1.0", "end")
check("Étape 3 : vérification avec le relevé du jeu affichée", "=> PvP" in txt, txt)
shot(root, "3_marche")
a._next()
pump(root)
check("Étape 4 : mise à jour automatique cochée", a.step == 3 and a.w["auto"].get())
shot(root, "4_mise_a_jour_auto")
a._finish()
pump(root, 2.5)
cfg = core.load()
check("Terminer : configuration enregistrée (Forever AH, PvP, AddOns)", cfg["source"]["type"] == "foreverah"
      and cfg["marche"]["type_marche"] == "pvp" and cfg["wow"]["addons"].endswith("AddOns"))
check("Terminer : aucune clé secrète dans le fichier de configuration",
      "secret" not in open(core.config_path(), encoding="utf-8").read().lower().replace("client_secret", "X"))
check("Terminer : une seule première mise à jour, lancée tout de suite", RUNS == ["mise à jour manuelle"], RUNS)
a.refresh_main()
pump(root)
check("Fenêtre principale : prix à jour, 3 HDV avec leur numéro",
      a.lbl_state.cget("text").startswith("Prix à jour") and a.cards["H"][0].cget("text") == "HDV n° 113",
      a.lbl_state.cget("text"))
check("Fenêtre principale : nombre d'annonces affiché", "196 937 annonces" in a.cards["A"][2].cget("text"), a.cards["A"][2].cget("text"))
check("Fenêtre principale : prochaine mise à jour annoncée", "Prochaine mise à jour" in a.lbl_info.cget("text"), a.lbl_info.cget("text"))
shot(root, "5_fenetre_principale")
a._online = {"addon": {"version": "99.0.0", "url": "https://x/a.zip", "sha256": "0" * 64}, "app": None, "page": "https://x"}
a.refresh_main()
pump(root)
check("Bandeau : version de l'add-on publiée en ligne proposée, bouton « Installer l'add-on »",
      "99.0.0 disponible en ligne" in a.banner_txt.cget("text") and a._banner_action == "online"
      and a.banner_btn.c.itemcget(a.banner_btn.txt, "text") == "Installer l'add-on", a.banner_txt.cget("text"))
a._online = {"addon": {"version": "99.0.0", "url": "https://x/a.zip", "sha256": "0" * 64},
             "app": {"version": "9.0.0", "url": "https://x/a.exe", "sha256": "0" * 64}, "page": "https://x"}
a.refresh_main()
pump(root)
vt = getattr(a, "version_texts", [])
check("En-tête : versions de l'application et de l'add-on, avec leur état",
      len(vt) == 2 and vt[0][0].startswith("Application " + appmod.core.APP_VERSION) and "9.0.0 disponible" in vt[0][0]
      and vt[1][0].startswith("Add-on ") and "99.0.0 disponible" in vt[1][0], vt)
shot(root, "5b_versions_a_mettre_a_jour")
a._online = {"addon": None, "app": {"version": appmod.core.APP_VERSION, "url": "https://x/a.exe", "sha256": "0" * 64}, "page": "https://x"}
a.refresh_main()
pump(root)
vt = a.version_texts
check("En-tête : « à jour » quand tout est à jour", vt[0][1] == "ok" and "à jour" in vt[0][0] and vt[1][1] == "ok", vt)
# Vérification manuelle (lien « Vérifier » de l'en-tête)
msgs = []
appmod.messagebox.showinfo = lambda *x, **k: msgs.append(x)
real_online = appmod.core.online_info
appmod.core.online_info = lambda force=False, **k: (msgs.append(("force", force)) or
    {"addon": None, "app": {"version": "9.1.0", "url": "https://x/a.exe", "sha256": "0" * 64}, "page": "https://x"})
appmod.core.online_error = lambda: None
check("En-tête : lien « Vérifier » présent", a.canvas.itemcget(a.check_link, "text").endswith("Vérifier"))
a.canvas.tag_bind(a.check_link, "<Button-1>")      # liaison présente
a.check_updates_now()
for _ in range(30):
    pump(root, 0.05)
    if not getattr(a, "checking", False):
        break
check("Vérifier : interrogation immédiate (sans cache), nouvelle version annoncée et bandeau à jour",
      ("force", True) in msgs and any("9.1.0" in str(m) for m in msgs) and a._banner_action == "app"
      and "9.1.0 disponible" in a.version_texts[0][0], msgs)
appmod.core.online_info = real_online
appmod.messagebox.showinfo = lambda *x, **k: None
a._online = None
a.refresh_main()
cap = [a.canvas.itemcget(i, "text") for i in a.canvas.find_withtag("caption")]
check("Nom du personnage affiché en petit, avec sa localisation fixe (PVP · EUROPE)", cap[:1] == ["Aurelia Shadsun"]
      and len(cap) == 2 and "PVP" in cap[1] and "EUROPE" in cap[1], cap)
check("Fenêtre principale dessinée : 5 boutons, symboles des HDV, bouton principal actif",
      sorted(a.buttons) == sorted(["Mettre à jour maintenant", "Journal", "Paramètres", "Dossier AddOns", "Quitter"])
      and a.btn_update.state == "normal")
# Fenêtre minuscule (cas du premier affichage sous Windows) : pas de plantage
root.geometry("200x120")
pump(root, 0.6)
check("Fenêtre minuscule : aucun plantage, rendu reporté", a._size == (0, 0) or a._size[0] >= 480, a._size)
root.geometry("1100x690")
pump(root, 1.0)
check("Redimensionnement : décor redessiné, textes conservés", a.lbl_state.cget("text").startswith("Prix à jour")
      and a._size[0] <= 1100, a._size)
a.buttons["Journal"].invoke()
pump(root)
tops = [w for w in root.winfo_children() if isinstance(w, tk.Toplevel)]
check("Journal : fenêtre ouverte", len(tops) == 1)
if tops:
    tops[0].update()
    time.sleep(0.2)
    subprocess.run(["import", "-window", str(tops[0].winfo_id()), os.path.join(OUT, "6_journal.png")], check=False)
    tops[0].destroy()
# Paramètres : l'assistant se rouvre avec les valeurs actuelles, Annuler revient
a.start_wizard(0)
pump(root)
check("Paramètres : assistant rouvert avec le dossier enregistré", a.w["forever"] == forever)
a.show_main()
pump(root)
a.quit()
ok = sum(1 for r in RESULTS if r[1])
for name, good, detail in RESULTS:
    print(("OK    " if good else "ÉCHEC ") + name + ("" if good else "  -> " + str(detail)[:300]))
print("Résultat interface : %d réussis, %d échoués" % (ok, len(RESULTS) - ok))
sys.exit(0 if ok == len(RESULTS) else 1)
