# -*- coding: utf-8 -*-
"""
===============================================================================
 Shadsun Gold Lens — application de bureau (sgl_app.py)
 Auteur : Tarak Ben Abda – novembre 2026
-------------------------------------------------------------------------------
 FR : Une fenêtre au lieu des fichiers .bat :
      - assistant en 4 étapes au premier lancement (installation de l'add-on,
        source des prix, type de serveur, mise à jour automatique) ;
      - fenêtre principale : état des trois HDV, dernière / prochaine mise à
        jour, boutons Mettre à jour, Journal, Paramètres, Dossier AddOns ;
      - icône près de l'horloge (si pystray est présent) : l'application reste
        active fenêtre fermée et met à jour les prix toutes les heures.
      Lancement : double-clic sur l'exe (ou « python sgl_app.py »).
      Options : --arriere-plan (démarrage avec Windows, fenêtre cachée),
                --maj [--origine texte] (une mise à jour, sans fenêtre).
 EN : Desktop app (tkinter): setup wizard, status window, tray icon.
===============================================================================
"""
import os
import queue
import sys
import threading
import time
import webbrowser

HERE = os.path.dirname(os.path.abspath(__file__))
if HERE not in sys.path:
    sys.path.insert(0, HERE)

import sgl_prix_api as E   # noqa: E402
import sgl_core as core    # noqa: E402

# --- Mode sans fenêtre : une mise à jour (processus enfant de la boucle) -----
if __name__ == "__main__" and "--maj" in sys.argv:
    origin = "mise à jour"
    if "--origine" in sys.argv:
        i = sys.argv.index("--origine")
        if i + 1 < len(sys.argv):
            origin = sys.argv[i + 1]
    if sys.stdout is None or sys.stderr is None:
        sys.stdout = sys.stderr = open(os.devnull, "w", encoding="utf-8")
    sys.exit(core.run_update_inline(origin))

import tkinter as tk                                     # noqa: E402
from tkinter import ttk, filedialog, messagebox          # noqa: E402

from PIL import Image, ImageDraw, ImageTk               # noqa: E402
import sgl_theme as TH                                   # noqa: E402

try:   # icône près de l'horloge : facultative / optional tray icon
    import pystray
    HAS_TRAY = True
except Exception:      # pragma: no cover - dépend de l'installation
    pystray = None
    HAS_TRAY = False

# --- Couleurs : bleu nuit et or (accordées au décor) ---------------------------
BG = "#0f1a33"
PANEL = "#082449"      # intérieur du cadre fourni (cadre_panneau.png)
PANEL2 = "#123766"
LINE = "#2c5596"
GOLD = "#e8c25a"
TEXT = "#eef0f4"
DIM = "#a3abbb"
GREEN = "#7beb96"
RED = "#ff8a8a"
FAC_COLORS = {"A": "#7fb2ff", "H": "#ff7a7a", "N": GOLD}
FAC_NAMES = {"A": "HDV Alliance", "H": "HDV Horde", "N": "HDV neutre"}
FONT = ("Segoe UI", 10)
FONT_B = ("Segoe UI", 10, "bold")
FONT_S = ("Segoe UI", 9)
FONT_T = ("Palatino Linotype", 16, "bold")
FONT_H = ("Palatino Linotype", 13, "bold")
SERIF = "Palatino Linotype"     # titres (remplacée par une police voisine hors Windows)
SANS = "Segoe UI"
# Hommage au personnage de Tarak (l'image est la sienne, en jeu) : texte fixe,
# le même pour tous les utilisateurs de l'application.
CHAR_NAME = "Aurelia Shadsun"
CHAR_REALM = "PvP · Europe"
NAME_FONTS = ("Gabriola", "Monotype Corsiva", "Palatino Linotype")   # nom du personnage, si installée
# Légende du personnage : centre (géométrie de référence), dans un espace libre du décor.
CAPTION_MAIN = (96, 172)        # à gauche de la tête (fenêtre principale)
CAPTION_WIZ = (78, 566)         # sous le marteau levé (assistant)
DESIGN_W, DESIGN_H = 1280, 800  # dimensions de référence de la fenêtre dessinée
TH_GOLD_LINE = "#8a6a2a"


def coin_image(size=64):
    """Icône de la fenêtre et de la zone de notification : la gemme du logo."""
    gem = TH.load("gemme.png")
    if gem is not None:
        return gem.resize((size, size), Image.LANCZOS)
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    ImageDraw.Draw(img).ellipse((2, 2, size - 2, size - 2), fill=(232, 194, 90, 255))
    return img


class CanvasText:
    """Texte dessiné sur le canevas, utilisable comme un libellé (cget / configure)."""

    def __init__(self, canvas, item):
        self.c, self.item = canvas, item

    def cget(self, key):
        return self.c.itemcget(self.item, "fill" if key == "fg" else key)

    def configure(self, text=None, fg=None, **kw):
        opts = {}
        if text is not None:
            opts["text"] = text
        if fg is not None:
            opts["fill"] = fg
        if opts:
            self.c.itemconfigure(self.item, **opts)

    def winfo_exists(self):
        try:
            return bool(self.c.winfo_exists()) and bool(self.c.type(self.item))
        except tk.TclError:
            return False


class CanvasButton:
    """Bouton dessiné (fond doré ou bleu, icône, texte) avec survol et état."""

    def __init__(self, app, x, y, w, h, text, cmd, kind="blue", icon=None, k=1.0, font=None):
        self.app, self.c, self.cmd, self.state = app, app.canvas, cmd, "normal"
        w, h = max(20, int(w)), max(14, int(h))
        self.imgs = {st: ImageTk.PhotoImage(TH.asset_button(w, h, kind, st)) for st in ("normal", "hover", "disabled")}
        self.bg = self.c.create_image(x, y, image=self.imgs["normal"], anchor="nw")
        tags = [self.bg]
        side = int(h * 0.44)                      # bouts ornés du cadre / ornate ends
        left, right = x + side, x + w - side
        if icon:
            isz = int(h * 0.62)
            if icon.endswith(".png"):
                im = TH.fit(TH.load(icon), isz, isz)
            else:
                im = TH.icon(icon, isz, (40, 26, 6) if kind == "gold" else TH.GOLD_L)
            if im is not None:
                self.icon_img = ImageTk.PhotoImage(im)
                tags.append(self.c.create_image(left + 2, y + h / 2, image=self.icon_img, anchor="w"))
                left += im.width + 6
        self.txt = self.c.create_text((left + right) / 2, y + h / 2, text=text,
                                      fill="#2a1a04" if kind == "gold" else TEXT,
                                      font=font or (SANS, -max(11, int(15 * k)), "bold"))
        tags.append(self.txt)
        self._items = tags
        for t in tags:
            self.c.tag_bind(t, "<Enter>", lambda e: self._hover(True))
            self.c.tag_bind(t, "<Leave>", lambda e: self._hover(False))
            self.c.tag_bind(t, "<Button-1>", lambda e: self._click())

    def _hover(self, on):
        if self.state != "disabled":
            self.c.itemconfigure(self.bg, image=self.imgs["hover" if on else "normal"])
            self.c.configure(cursor="hand2" if on else "")

    def _click(self):
        if self.state != "disabled":
            self.cmd()

    def configure(self, state=None, text=None, **kw):
        if state is not None:
            self.state = state
            self.c.itemconfigure(self.bg, image=self.imgs["disabled" if state == "disabled" else "normal"])
        if text is not None:
            self.c.itemconfigure(self.txt, text=text)

    def invoke(self):
        self._click()

    def set_visible(self, on):
        for it in self._items:
            self.c.itemconfigure(it, state="normal" if on else "hidden")


class InfoLines:
    """Plusieurs lignes de texte du canevas vues comme un seul libellé."""

    def __init__(self, canvas, items):
        self.c, self.items = canvas, items

    def cget(self, key):
        return "\n".join(self.c.itemcget(i, "text") for i in self.items if self.c.itemcget(i, "text"))

    def configure(self, text=None, **kw):
        if text is not None:
            parts = text.split("\n")
            for j, it in enumerate(self.items):
                self.c.itemconfigure(it, text=parts[j] if j < len(parts) else "")

    def winfo_exists(self):
        return bool(self.c.winfo_exists())


class Wrap(tk.Label):
    """Libellé qui revient à la ligne selon sa largeur."""

    def __init__(self, master, **kw):
        kw.setdefault("bg", master["bg"])
        kw.setdefault("fg", TEXT)
        kw.setdefault("font", FONT)
        kw.setdefault("justify", "left")
        kw.setdefault("anchor", "w")
        super().__init__(master, **kw)
        self.bind("<Configure>", lambda e: self.configure(wraplength=max(100, e.width - 4)))


class ImgButton(tk.Button):
    """Bouton tkinter habillé du cadre orné fourni (doré ou bleu), avec survol,
    état désactivé et largeur adaptée au texte."""

    H = 36

    def __init__(self, master, text, cmd, primary=False, **kw):
        self._kind = "gold" if primary else "blue"
        self._font = FONT_B
        bg = master["bg"]
        super().__init__(master, text=text, command=cmd, relief="flat", bd=0, cursor="hand2", compound="center",
                         highlightthickness=0, padx=0, pady=0, bg=bg, activebackground=bg,
                         fg="#2a1a04" if primary else TEXT, activeforeground="#2a1a04" if primary else "#ffffff",
                         disabledforeground="#8b93a6", font=self._font, **kw)
        self._state = "normal"
        self._make(text)
        self.bind("<Enter>", lambda e: self._swap("hover"))
        self.bind("<Leave>", lambda e: self._swap("normal"))

    def _make(self, text):
        from tkinter import font as tkfont
        try:
            tw = tkfont.Font(root=self, font=self._font).measure(text)
        except tk.TclError:
            tw = 8 * len(text)
        w = int(tw + 2 * self.H * 0.95 + 12)     # bouts ornés de chaque côté du texte
        self._imgs = {st: ImageTk.PhotoImage(TH.asset_button(w, self.H, self._kind, st), master=self)
                      for st in ("normal", "hover", "disabled")}
        tk.Button.configure(self, image=self._imgs["disabled" if self._state == "disabled" else "normal"],
                            width=w, height=self.H)

    def _swap(self, st):
        if self._state != "disabled":
            tk.Button.configure(self, image=self._imgs[st])

    def configure(self, cnf=None, **kw):
        if "state" in kw:
            self._state = kw["state"]
            kw["image"] = self._imgs["disabled" if self._state == "disabled" else "normal"]
            kw["cursor"] = "" if self._state == "disabled" else "hand2"
        res = tk.Button.configure(self, cnf, **kw)
        if "text" in kw:
            self._make(kw["text"])
        return res

    config = configure


def button(master, text, cmd, primary=False, **kw):
    return ImgButton(master, text, cmd, primary, **kw)

# -----------------------------------------------------------------------------
# Guide pas à pas : créer sa clé API Blizzard / step-by-step API key guide
# Chaque étape : (titre, texte, url à ouvrir ou None, [(libellé, texte à copier)])
# -----------------------------------------------------------------------------
KEY_GUIDE = [
    ("Avant de commencer",
     "Il vous faut seulement votre compte Battle.net habituel (celui du jeu). C'est gratuit et ça prend "
     "environ 5 minutes.\n\nGardez cette fenêtre ouverte à côté du navigateur : à chaque étape, faites ce qui "
     "est écrit, puis cliquez « Suivant ».\n\nSi Battle.net vous demande un code de sécurité (authentificateur "
     "ou SMS), c'est normal : entrez-le.", None, []),
    ("1. Ouvrir le portail développeur",
     "Cliquez « Ouvrir la page ». Le site develop.battle.net s'ouvre dans votre navigateur.\n\n"
     "En haut à droite, cliquez « Log In » et connectez-vous avec votre compte Battle.net.",
     core.PORTAL_URL, []),
    ("2. Accepter les conditions",
     "La première fois, Blizzard affiche ses conditions d'utilisation de l'API (« API Terms of Use »).\n\n"
     "Lisez-les, cochez la case d'acceptation puis validez. Si rien ne s'affiche, passez à l'étape suivante.",
     None, []),
    ("3. Créer un client",
     "Allez dans « API Access » (si vous n'y êtes pas déjà), puis cliquez le bouton « Create Client ».\n\n"
     "Un formulaire s'ouvre. Les étapes suivantes vous disent quoi mettre dans chaque case.",
     core.PORTAL_URL, []),
    ("4. Remplir le formulaire",
     "Client Name : un nom au choix (copiez celui-ci si vous voulez).\n\n"
     "Redirect URLs : laissez vide. Si le formulaire refuse, mettez https://localhost\n\n"
     "Service URL : laissez vide ou cochez « I do not have a service URL ».\n\n"
     "Intended Use : copiez la phrase ci-dessous.",
     None, [("Copier le nom", "Shadsun Gold Lens"),
            ("Copier https://localhost", "https://localhost"),
            ("Copier la phrase « Intended Use »",
             "Usage personnel : prix des hôtels des ventes de WoW Forever pour un add-on.")]),
    ("5. Enregistrer",
     "Cliquez « Save » en bas du formulaire.\n\n"
     "La page de votre client s'affiche, avec deux valeurs : « Client ID » et « Client Secret ».",
     None, []),
    ("6. Copier les deux valeurs",
     "Copiez le « Client ID » et collez-le dans la case Client ID de l'application.\n\n"
     "Copiez ensuite le « Client Secret » et collez-le dans la case Client Secret.\n\n"
     "Le secret n'est parfois montré qu'une seule fois. Si vous ne le voyez plus, cliquez « Generate new "
     "secret » (ou équivalent) sur la page du client et utilisez le nouveau.",
     None, []),
    ("7. Tester",
     "Fermez ce guide et cliquez « Tester la source » dans l'application. Un message vert confirme que la clé "
     "fonctionne ; cliquez alors « Suivant ».\n\n"
     "Important : le Client Secret est comme un mot de passe. Ne le donnez à personne, ne l'envoyez par aucun "
     "message, ne le collez nulle part ailleurs. L'application le range dans le Gestionnaire d'identification "
     "de Windows.",
     None, []),
]


class App:
    STEPS = ["Installation", "Source des prix", "Mon marché", "Mise à jour automatique"]

    def __init__(self, root, background=False, scheduler_runner=None, start_scheduler=True, check_online=True,
                 installed_from=None, updated=False):
        self.root = root
        self.q = queue.Queue()
        # Dernière version publiée sur GitHub (information gardée en cache, 1 vérification / jour)
        self._online = core._read_online_state().get("info")
        self._banner_action = None
        self.busy_online = False
        self.cfg = core.load()
        core.setup_engine()
        self.tray = None
        self.quitting = False
        self.busy_update = False
        self.last_code = None
        self._build_window()
        self.scheduler = core.Scheduler(int(self.cfg["outil"].get("intervalle_minutes", "60") or 60),
                                        runner=scheduler_runner, on_event=lambda t, d: self.q.put(("sched", t, d)))
        self.scheduler.enabled = self.cfg["outil"].get("auto_horaire", "1") == "1" and core.is_ready(self.cfg)
        if start_scheduler:
            self.scheduler.start()
        if HAS_TRAY and self.cfg["outil"].get("zone_notification", "1") == "1":
            self._start_tray()
        if core.is_ready(self.cfg):
            self.show_main()
        else:
            self.start_wizard()
            background = False           # premier lancement : toujours visible
        if background:
            self.root.withdraw() if self.tray else self.root.iconify()
        self.root.after(400, self._poll)
        if check_online:
            self.root.after(5000, self._check_online)
        if installed_from:
            self.root.after(900, lambda: messagebox.showinfo(core.APP_NAME,
                "Shadsun Gold Lens est installé dans :\n%s\n\nUtilisez le raccourci « %s » du Bureau ou du menu Démarrer. "
                "Les prochaines mises à jour se feront depuis l'application.\n\nLe fichier téléchargé peut être supprimé :\n%s"
                % (core.install_dir(), core.APP_NAME, installed_from)))
        elif updated:
            self.root.after(900, lambda: messagebox.showinfo(core.APP_NAME, "Application mise à jour : version %s." % core.APP_VERSION))

    # ------------------------------------------------------------------ mises à jour en ligne
    def _check_online(self, force=False):
        """Vérifie (en arrière-plan) la dernière version publiée, puis toutes les 6 h ;
        le cache limite les appels réels à un par jour."""
        def work():
            self.q.put(("online", core.online_info(force=force)))
        threading.Thread(target=work, daemon=True).start()
        if not self.quitting:
            self.root.after(6 * 3600 * 1000, self._check_online)

    def check_updates_now(self):
        """Vérification manuelle (lien « Vérifier » de l'en-tête, menu de l'icône) :
        interroge GitHub tout de suite, sans attendre la vérification quotidienne."""
        if getattr(self, "checking", False):
            return
        self.checking = True
        self._draw_versions()

        def work():
            info = core.online_info(force=True)
            self.q.put(("online_manual", info, core.online_error()))
        threading.Thread(target=work, daemon=True).start()

    # ------------------------------------------------------------------ fenêtre
    def _build_window(self):
        r = self.root
        r.title(core.APP_NAME)
        r.configure(bg=BG)
        try:
            dpi = max(1.0, float(r.winfo_fpixels("1i")) / 96.0)
        except tk.TclError:
            dpi = 1.0
        sw, sh = r.winfo_screenwidth(), r.winfo_screenheight()
        w = int(min(DESIGN_W * dpi, sw * 0.92))
        h = int(min(DESIGN_H * dpi, sh * 0.88))
        w, h = min(w, int(h * DESIGN_W / DESIGN_H)), min(h, int(w * DESIGN_H / DESIGN_W))
        r.geometry("%dx%d" % (max(960, w), max(600, h)))
        r.minsize(960, 600)
        for cls in ("Button", "Checkbutton", "Radiobutton", "Entry", "Text"):
            r.option_add("*%s.highlightThickness" % cls, 0)
        r.protocol("WM_DELETE_WINDOW", self.on_close)
        try:
            self._icon = ImageTk.PhotoImage(coin_image(64))
            r.iconphoto(True, self._icon)
        except Exception:
            pass
        style = ttk.Style(r)
        try:
            style.theme_use("clam")
        except tk.TclError:
            pass
        style.configure("TCombobox", fieldbackground=PANEL2, background=PANEL2, foreground=TEXT,
                        arrowcolor=GOLD, bordercolor=LINE, lightcolor=PANEL2, darkcolor=PANEL2)
        style.map("TCombobox", fieldbackground=[("readonly", PANEL2)], foreground=[("readonly", TEXT)],
                  selectbackground=[("readonly", PANEL2)], selectforeground=[("readonly", TEXT)])
        r.option_add("*TCombobox*Listbox.background", PANEL2)
        r.option_add("*TCombobox*Listbox.foreground", TEXT)
        r.option_add("*TCombobox*Listbox.selectBackground", GOLD)
        r.option_add("*TCombobox*Listbox.selectForeground", "#1a1a1a")
        style.configure("TSpinbox", fieldbackground=PANEL2, foreground=TEXT, background=PANEL2, arrowcolor=GOLD)
        self.canvas = tk.Canvas(r, bg=BG, highlightthickness=0, bd=0)
        self.canvas.pack(fill="both", expand=True)
        self.canvas.bind("<Configure>", self._on_resize)
        self.mode = None
        self.host = None
        self._imgs = []
        self._size = (0, 0)
        self._resize_job = None

    def _on_resize(self, event):
        if (event.width, event.height) == self._size:
            return
        if self._resize_job:
            self.root.after_cancel(self._resize_job)
        self._resize_job = self.root.after(120, self._render)

    def _geom(self):
        self.root.update_idletasks()
        W = max(200, self.canvas.winfo_width())
        H = max(150, self.canvas.winfo_height())
        k = min(W / DESIGN_W, H / DESIGN_H)
        ox, oy = (W - DESIGN_W * k) / 2, (H - DESIGN_H * k) / 2
        return W, H, k, ox, oy

    def _photo(self, img):
        ph = ImageTk.PhotoImage(img)
        self._imgs.append(ph)
        return ph

    def _render(self):
        """Redessine le décor de la vue courante (et ses textes)."""
        self._resize_job = None
        if self.quitting:
            return
        W, H, k, ox, oy = self._geom()
        if W < 480 or H < 300:
            # Fenêtre pas encore affichée (Windows) : on redessinera à sa taille réelle.
            self._size = (0, 0)
            self._resize_job = self.root.after(250, self._render)
            return
        self._size = (W, H)
        X = lambda x: ox + x * k   # noqa: E731
        Y = lambda y: oy + y * k   # noqa: E731
        self.canvas.delete("all")
        self._imgs = []
        if self.mode == "wizard":
            self._render_wizard(W, H, k, X, Y)
        else:
            self._render_main(W, H, k, X, Y)

    # --- décor de l'assistant -----------------------------------------------------
    # --- bandeau d'en-tête commun : logo en médaillon à gauche, titre à côté ------
    # Colonne de contenu commune : tous les blocs commencent en x = 470 et finissent
    # en x = 1250 ; leurs ornements centraux tombent tous sur x = 860.
    HB = (470, 26, 780, 96)        # x, y, largeur, hauteur (géométrie de référence)

    def _header_band(self, bg, k, X, Y):
        x, y, w, h = self.HB
        cadre = TH.load("cadre_panneau.png")
        if cadre is not None:
            bg.alpha_composite(TH.nslice(cadre, int(w * k), int(h * k), smax=0.2), (int(X(x)), int(Y(y))))
        else:
            bg.alpha_composite(TH.panel(int(w * k), int(h * k), k, alpha=235), (int(X(x)), int(Y(y))))
        TH.place(bg, TH.load("logo.png"), X(x + 6), max(0, Y(y - 18)), height=132 * k)

    # --- légende discrète du personnage -------------------------------------------
    def _caption_bg(self, bg, k, X, Y, pos):
        sep = TH.fit(TH.load("separateur.png"), int(118 * k), int(18 * k))
        if sep is not None:
            bg.alpha_composite(sep, (int(X(pos[0]) - sep.width / 2), int(Y(pos[1] + 13) - sep.height / 2)))

    def _name_font(self, px):
        if not hasattr(self, "_name_family"):
            from tkinter import font as tkfont
            fams = {f.lower(): f for f in tkfont.families(self.root)}
            self._name_family = next((fams[f.lower()] for f in NAME_FONTS if f.lower() in fams), SERIF)
        fam = self._name_family
        if fam.lower() == "gabriola":            # petite hauteur d'x : un peu plus grand
            return (fam, -max(12, int(px * 1.3)))
        return (fam, -max(10, int(px)), "italic")

    def _caption_text(self, k, X, Y, pos):
        c = self.canvas
        cx = X(pos[0])
        c.create_text(cx, Y(pos[1]), text=CHAR_NAME, fill="#e8c56a", font=self._name_font(16 * k), tags="caption")
        self._caption_place_id = c.create_text(cx, Y(pos[1] + 27), text=CHAR_REALM.upper(), fill=DIM,
                                               font=(SERIF, -max(8, int(10 * k))), tags="caption")

    def _header_texts(self, k, X, Y, title, sub):
        x, y, w, h = self.HB
        c = self.canvas
        c.create_text(X(x + 152), Y(y + 38), text=title, anchor="w", fill=GOLD, font=(SERIF, -int(30 * k), "bold"))
        c.create_text(X(x + 154), Y(y + 70), text=sub, anchor="w", fill=DIM, font=(SANS, -int(13 * k)))

    def _render_wizard(self, W, H, k, X, Y):
        bg = TH.background(W, H, k)
        TH.place(bg, TH.load("personnage_marteau_leve.png"), max(0, X(-10)), max(0, Y(40)), height=750 * k, shadow=True)
        self._header_band(bg, k, X, Y)
        px, py, pw, ph = X(470), Y(140), int(780 * k), int(636 * k)
        cadre = TH.load("cadre_panneau.png")
        if cadre is not None:
            bg.alpha_composite(TH.nslice(cadre, pw, ph, smax=0.42), (int(px), int(py)))
            ins_x, ins_top, ins_bot = int(26 * k), int(58 * k), int(26 * k)
        else:
            bg.alpha_composite(TH.panel(pw, ph, k, fill=(8, 36, 73), alpha=255), (int(px), int(py)))
            ins_x = ins_top = ins_bot = int(14 * k)
        self._caption_bg(bg, k, X, Y, CAPTION_WIZ)
        TH.frame(bg, k)
        self.canvas.create_image(0, 0, image=self._photo(bg), anchor="nw")
        self._caption_text(k, X, Y, CAPTION_WIZ)
        self._header_texts(k, X, Y, "Configuration", "v" + core.APP_VERSION + " · assistant en 4 étapes")
        if self.host is None or not self.host.winfo_exists():
            return
        self.host_win = self.canvas.create_window(int(px) + ins_x, int(py) + ins_top, anchor="nw", window=self.host,
                                                  width=pw - 2 * ins_x, height=ph - ins_top - ins_bot)

    # --- décor de la fenêtre principale ------------------------------------------
    def _render_main(self, W, H, k, X, Y):
        bg = TH.background(W, H, k, glow_center=(int(X(510)), int(Y(70))))
        TH.place(bg, TH.load("personnage_appuyee.png"), max(0, X(0)), max(0, Y(34)), height=760 * k, shadow=True)
        self._header_band(bg, k, X, Y)
        # Bandeau d'état (cadre fourni, pastille dans le cercle)
        etat = TH.load("cadre_etat.png")
        sx, sy, sw, shh = 470, 142, 780, 66
        if etat is not None:
            bar = TH.hslice(etat, int(sw * k), int(shh * k), fr=(.27, .37, .63, .88))
            bg.alpha_composite(bar, (int(X(sx)), int(Y(sy))))
            s_ = shh * k / etat.height
            circ_x, text_x = X(sx) + .175 * etat.width * s_, X(sx) + .31 * etat.width * s_
        else:
            bg.alpha_composite(TH.panel(int(sw * k), int(50 * k), k, alpha=235, radius=12), (int(X(sx)), int(Y(sy))))
            circ_x, text_x = X(sx + 24), X(sx + 58)
        state_y = Y(sy + shh * .52)
        # Cartes des HDV : fond teinté + cadre fourni + emblème fourni
        self._card_x = []
        cw, gap, cy0, ch = 248, 18, 228, 186
        carte = TH.load("cadre_carte.png")
        emb = {"A": "embleme_alliance.png", "H": "embleme_horde.png", "N": "embleme_neutre.png"}
        for i, fac in enumerate(E.FACTIONS):
            cx = 470 + i * (cw + gap)
            self._card_x.append(cx)
            base = TH.panel(int(cw * k), int(ch * k), k, fill=(10, 22, 48), alpha=240, accent=TH.FAC[fac], edge=carte is None)
            bg.alpha_composite(base, (int(X(cx)), int(Y(cy0))))
            if carte is not None:
                bg.alpha_composite(TH.nslice(carte, int(cw * k), int(ch * k), fx=(.06, .45, .56, .94), fy=(.08, .92)),
                                   (int(X(cx)), int(Y(cy0))))
            e = TH.fit(TH.load(emb[fac]), int(88 * k), int(52 * k))
            if e is None:
                e = TH.emblem(fac, int(52 * k))
            bg.alpha_composite(e, (int(X(cx + 12) + (88 * k - e.width) / 2), int(Y(cy0 + 12) + (52 * k - e.height) / 2)))
        # Panneau d'informations (cadre fourni)
        cadre = TH.load("cadre_panneau.png")
        if cadre is not None:
            bg.alpha_composite(TH.nslice(cadre, int(780 * k), int(156 * k)), (int(X(470)), int(Y(434))))
        else:
            bg.alpha_composite(TH.panel(int(780 * k), int(144 * k), k, alpha=235), (int(X(470)), int(Y(440))))
        for j, ic in enumerate(("source", "calendar", "refresh")):
            bg.alpha_composite(TH.icon(ic, int(18 * k)), (int(X(498)), int(Y(471 + j * 27))))
        self._caption_bg(bg, k, X, Y, CAPTION_MAIN)
        TH.frame(bg, k)
        c = self.canvas
        c.create_image(0, 0, image=self._photo(bg), anchor="nw")
        self._header_texts(k, X, Y, "Prix des hôtels des ventes", "")
        # Versions de l'application et de l'add-on, avec leur état (mis à jour par refresh_main)
        hx, hy = self.HB[0], self.HB[1]
        self._ver_anchor = (X(hx + 154), Y(hy + 70), k)
        self._ver_items = []
        self._caption_text(k, X, Y, CAPTION_MAIN)
        # État
        self._state_imgs = {n: self._photo(TH.icon(n, int(28 * k))) for n in ("check", "warn", "error")}
        self.state_icon = c.create_image(circ_x, state_y, anchor="center", image=self._state_imgs["check"])
        self.lbl_state = CanvasText(c, c.create_text(text_x, state_y, text="", anchor="w", fill=GREEN,
                                                     font=(SANS, -int(19 * k), "bold")))
        # Cartes : textes
        self.cards = {}
        for i, fac in enumerate(E.FACTIONS):
            cx = self._card_x[i]
            c.create_text(X(cx + 106), Y(cy0 + 32), text=FAC_NAMES[fac], anchor="w", fill=FAC_COLORS[fac],
                          font=(SERIF, -int(20 * k), "bold"))
            l1 = CanvasText(c, c.create_text(X(cx + 107), Y(cy0 + 58), text="", anchor="w", fill=DIM, font=(SANS, -int(13 * k))))
            l2 = CanvasText(c, c.create_text(X(cx + 18), Y(cy0 + 116), text="", anchor="w", fill=TEXT, font=(SANS, -int(21 * k), "bold")))
            l3 = CanvasText(c, c.create_text(X(cx + 18), Y(cy0 + 152), text="", anchor="w", fill=DIM, font=(SANS, -int(13 * k))))
            self.cards[fac] = (l1, l2, l3)
        lines = [c.create_text(X(526), Y(480 + j * 27), text="", anchor="w", fill=TEXT, font=(SANS, -int(15 * k)))
                 for j in range(3)]
        self.lbl_info = InfoLines(c, lines)
        # Bandeau « nouvelle version de l'add-on »
        self.banner_txt = CanvasText(c, c.create_text(X(526), Y(561), text="", anchor="w", fill=GOLD,
                                                      font=(SANS, -int(14 * k), "bold")))
        self.banner_btn = CanvasButton(self, X(1036), Y(545), int(196 * k), int(32 * k), "Installer l'add-on",
                                       self.install_addon_now, "blue", None, k, font=(SANS, -int(13 * k), "bold"))
        self.banner_btn.set_visible(False)
        # Boutons (icônes fournies)
        x, y, h = 470, 616, 56
        bgap = (780 - (258 + 138 + 166 + 192)) / 3          # rangée de 470 à 1250
        spec = [("Mettre à jour maintenant", self.update_now, "gold", "icone_globe.png", 258),
                ("Journal", self.show_journal, "blue", "icone_plume.png", 138),
                ("Paramètres", lambda: self.start_wizard(0), "blue", "icone_boussole.png", 166),
                ("Dossier AddOns", self.open_addons, "blue", "icone_coffre.png", 192)]
        self.buttons = {}
        for text, cmd, kind, ic, w in spec:
            self.buttons[text] = CanvasButton(self, X(x), Y(y), int(w * k), int(h * k), text, cmd, kind, ic, k,
                                              font=(SANS, -int(13 * k), "bold"))
            x += w + bgap
        self.buttons["Quitter"] = CanvasButton(self, X(1104), Y(53), int(128 * k), int(42 * k), "Quitter", self.quit,
                                               "blue", "icone_griffon.png", k, font=(SANS, -int(13 * k), "bold"))
        self.btn_update = self.buttons["Mettre à jour maintenant"]
        # Pied de page
        self._info_icon = self._photo(TH.icon("info", int(16 * k)))
        foot = "En jeu : /reload (ou le bouton Recharger de l'onglet Marchés) charge les nouveaux prix."
        c.create_image(X(470), Y(712), image=self._info_icon, anchor="w")
        c.create_text(X(494), Y(712), text=foot, anchor="w", fill=DIM, font=(SANS, -int(14 * k)))
        if self.cfg["source"].get("type") == "foreverah":
            c.create_text(X(494), Y(733), text=E.FAH_CREDIT + ".", anchor="w", fill=DIM, font=(SANS, -int(12 * k)))
        self._k = k
        self.refresh_main()

    def _clear(self):
        if self.host is not None and self.host.winfo_exists():
            for w in self.host.winfo_children():
                w.destroy()

    # ------------------------------------------------------------------ assistant
    def start_wizard(self, step=0):
        c = self.cfg
        old = core.find_old_config() if c["app"].get("assistant_fait") != "1" else None
        forevers = core.find_forever_dirs()
        cur = core.forever_from_any(c["wow"].get("dossier", "")) if c["wow"].get("dossier") else None
        if not cur and old and old.get("addons"):
            cur = core.forever_from_any(old["addons"])
        if not cur and forevers:
            cur = forevers[0]
        cid = c["battlenet"].get("client_id", "")
        self.w = {
            "forevers": forevers, "forever": cur or "", "old": old,
            "import_old": tk.BooleanVar(value=bool(old)),
            "region": tk.StringVar(value=c["marche"].get("region", "eu")),
            "install": tk.BooleanVar(value=True),
            "source": tk.StringVar(value=c["source"].get("type", "foreverah")),
            "client_id": tk.StringVar(value=cid or (old or {}).get("client_id", "")),
            "client_secret": tk.StringVar(value=(core.get_secret(cid) if cid else None) or (old or {}).get("client_secret", "")),
            "type_marche": tk.StringVar(value=c["marche"].get("type_marche", "") or (old or {}).get("type_marche") or ""),
            "auto": tk.BooleanVar(value=c["outil"].get("auto_horaire", "1") == "1"),
            "interval": tk.StringVar(value=c["outil"].get("intervalle_minutes", "60")),
            "startup": tk.BooleanVar(value=c["outil"].get("demarrage_windows", "1") == "1"),
            "tray": tk.BooleanVar(value=c["outil"].get("zone_notification", "1") == "1" and HAS_TRAY),
        }
        if old and old.get("client_id") and not cid and c["app"].get("assistant_fait") != "1":
            self.w["source"].set("blizzard")
        self.step = step
        self._show_step()

    def _show_step(self):
        first = self.mode != "wizard" or self.host is None or not self.host.winfo_exists()
        self.mode = "wizard"
        if first:
            self.host = tk.Frame(self.canvas, bg=PANEL)
        self._clear()
        head = tk.Frame(self.host, bg=PANEL)
        head.pack(fill="x", padx=10, pady=(4, 0))
        dots = tk.Frame(head, bg=PANEL)
        dots.pack(side="left")
        for i, name in enumerate(self.STEPS):
            col = GOLD if i == self.step else (GREEN if i < self.step else "#5d6f96")
            tk.Label(dots, text="%d  %s" % (i + 1, name), bg=PANEL, fg=col,
                     font=FONT_B if i == self.step else FONT_S).pack(side="left", padx=(0, 16))
        self.head_right = tk.Label(head, text="Étape %d sur 4 — %s" % (self.step + 1, self.STEPS[self.step]),
                                   bg=PANEL, fg=DIM, font=FONT_S)
        self.head_right.pack(side="right")
        tk.Frame(self.host, bg=TH_GOLD_LINE, height=1).pack(fill="x", padx=10, pady=(6, 0))
        self.foot = tk.Frame(self.host, bg=PANEL)
        self.foot.pack(side="bottom", fill="x", padx=10, pady=(6, 6))
        inner = tk.Frame(self.host, bg=PANEL)
        inner.pack(fill="both", expand=True, padx=12, pady=(10, 4))
        self.body = inner
        [self._page_install, self._page_source, self._page_market, self._page_auto][self.step](inner)
        nav = self.foot
        if self.step > 0:
            button(nav, "Précédent", self._prev).pack(side="left")
        if core.is_ready(self.cfg):
            button(nav, "Annuler", self.show_main).pack(side="left", padx=8)
        if self.step < 3:
            button(nav, "Suivant", self._next, primary=True).pack(side="right")
        else:
            button(nav, "Terminer", self._finish, primary=True).pack(side="right")
        if first:
            self._render()

    def _prev(self):
        self.step -= 1
        self._show_step()

    def _next(self):
        ok = [self._check_install, self._check_source, self._check_market][self.step]()
        if ok:
            self.step += 1
            self._show_step()

    # --- étape 1 : installation ------------------------------------------------
    def _page_install(self, p):
        w = self.w
        tk.Label(p, text="Installation", bg=PANEL, fg=GOLD, font=FONT_H).pack(anchor="w")
        Wrap(p, text="L'application trouve WoW Forever et installe ou met à jour l'add-on Shadsun Gold Lens.",
             bg=PANEL, fg=DIM).pack(fill="x", pady=(2, 12))
        tk.Label(p, text="Dossier de WoW Forever", bg=PANEL, fg=TEXT, font=FONT_B).pack(anchor="w")
        row = tk.Frame(p, bg=PANEL)
        row.pack(fill="x", pady=(4, 2))
        self.cb_forever = ttk.Combobox(row, values=w["forevers"], font=FONT)
        self.cb_forever.set(w["forever"])
        self.cb_forever.pack(side="left", fill="x", expand=True)
        self.cb_forever.bind("<<ComboboxSelected>>", lambda e: self._forever_changed(self.cb_forever.get()))
        self.cb_forever.bind("<FocusOut>", lambda e: self._forever_changed(self.cb_forever.get()))
        button(row, "Parcourir…", self._browse).pack(side="left", padx=(8, 0))
        self.lbl_forever = Wrap(p, text="", bg=PANEL, font=FONT_S)
        self.lbl_forever.pack(fill="x", pady=(2, 12))
        tk.Label(p, text="Région", bg=PANEL, fg=TEXT, font=FONT_B).pack(anchor="w")
        self.cb_region = ttk.Combobox(p, state="readonly", width=28, font=FONT,
                                      values=["%s (%s)" % (lab, k.upper()) for k, lab in E.REGIONS])
        self.cb_region.pack(anchor="w", pady=(4, 2))
        self.cb_region.bind("<<ComboboxSelected>>", lambda e: w["region"].set(E.REGIONS[self.cb_region.current()][0]))
        self.lbl_region = tk.Label(p, text="", bg=PANEL, fg=DIM, font=FONT_S)
        self.lbl_region.pack(anchor="w", pady=(0, 12))
        tk.Label(p, text="Add-on", bg=PANEL, fg=TEXT, font=FONT_B).pack(anchor="w")
        self.lbl_addon = Wrap(p, text="", bg=PANEL, font=FONT_S)
        self.lbl_addon.pack(fill="x", pady=(2, 2))
        tk.Checkbutton(p, text="Installer ou mettre à jour l'add-on en passant à l'étape suivante", variable=w["install"],
                       bg=PANEL, fg=TEXT, selectcolor=PANEL2, activebackground=PANEL, activeforeground=TEXT,
                       font=FONT).pack(anchor="w")
        if w["old"]:
            box = tk.Frame(p, bg=PANEL2)
            box.pack(fill="x", pady=(14, 0))
            tk.Checkbutton(box, text="Reprendre les réglages de l'ancien outil (%s) : clé Blizzard, type de serveur"
                           % os.path.dirname(w["old"]["path"]), variable=w["import_old"], bg=PANEL2, fg=TEXT,
                           selectcolor=PANEL, activebackground=PANEL2, activeforeground=TEXT, font=FONT_S,
                           wraplength=640, justify="left").pack(anchor="w", padx=8, pady=6)
        self._forever_changed(w["forever"])

    def _browse(self):
        d = filedialog.askdirectory(title="Dossier de World of Warcraft (ou _forever_)")
        if d:
            f = core.forever_from_any(d) or d
            self.cb_forever.set(f)
            self._forever_changed(f)

    def _forever_changed(self, path):
        w = self.w
        f = core.forever_from_any(path) if path else None
        w["forever"] = f or path
        if f:
            self.lbl_forever.configure(text="Trouvé : %s" % f, fg=GREEN)
            reg = core.detect_region(f)
            if reg:
                w["region"].set(reg)
            self.lbl_region.configure(text="Détectée dans la configuration du jeu." if reg else
                                      "Non détectée : choisissez votre région.")
            inst, src = core.addon_status(core.addons_dir(f))
            if inst and src and inst == src:
                txt, col = "Installé, version %s (à jour)." % inst, GREEN
                w["install"].set(False)
            elif inst:
                txt, col = "Installé, version %s — version livrée avec l'application : %s." % (inst, src or "?"), GOLD
                w["install"].set(bool(src))
            else:
                txt, col = "Pas encore installé (version livrée : %s)." % (src or "introuvable"), GOLD
                w["install"].set(bool(src))
            self.lbl_addon.configure(text=txt, fg=col)
        else:
            self.lbl_forever.configure(text="Dossier « _forever_ » introuvable ici. Indiquez le dossier "
                                       "« World of Warcraft » (celui qui contient « _forever_ »).", fg=RED)
            self.lbl_addon.configure(text="-", fg=DIM)
        keys = [k for k, _ in E.REGIONS]
        self.cb_region.current(keys.index(w["region"].get()) if w["region"].get() in keys else 0)

    def _check_install(self):
        w = self.w
        self._forever_changed(self.cb_forever.get())
        f = core.forever_from_any(w["forever"])
        if not f:
            messagebox.showerror(core.APP_NAME, "Indiquez le dossier de WoW Forever (celui qui contient « _forever_ »).")
            return False
        w["forever"] = f
        if w["install"].get():
            try:
                v = core.install_addon(core.addons_dir(f))
                messagebox.showinfo(core.APP_NAME, "Add-on installé (version %s).\nS'il était ouvert, relancez le jeu "
                                    "ou tapez /reload." % v)
            except Exception as ex:
                messagebox.showerror(core.APP_NAME, "Installation impossible :\n%s\n\nFermez le jeu et réessayez." % ex)
                return False
        if w["old"] and w["import_old"].get():
            o = w["old"]
            if o.get("client_id"):
                w["client_id"].set(o["client_id"])
                w["client_secret"].set(o.get("client_secret", ""))
            if o.get("type_marche") and not w["type_marche"].get():
                w["type_marche"].set(o["type_marche"])
        return True

    # --- étape 2 : source --------------------------------------------------------
    def _page_source(self, p):
        w = self.w
        tk.Label(p, text="Source des prix", bg=PANEL, fg=GOLD, font=FONT_H).pack(anchor="w")
        Wrap(p, text="D'où viennent les prix des trois HDV (Alliance, Horde, neutre), mis à jour toutes les heures.",
             bg=PANEL, fg=DIM).pack(fill="x", pady=(2, 10))
        for val, title, desc in (
                ("foreverah", "Simple, sans compte (recommandé)",
                 "Prix de Forever AH (forever-ah.com), un site gratuit qui lit l'API officielle de Blizzard. "
                 "Rien à créer. Les prix sont crédités « Forever AH » dans l'add-on."),
                ("blizzard", "Avancé : ma clé Blizzard",
                 "Directement depuis l'API Blizzard, avec votre propre compte développeur (gratuit, 5 minutes). "
                 "Ne dépend d'aucun site tiers.")):
            f = tk.Frame(p, bg=PANEL)
            f.pack(fill="x", pady=3)
            tk.Radiobutton(f, text=title, value=val, variable=w["source"], command=self._source_changed, bg=PANEL,
                           fg=TEXT, selectcolor=PANEL2, activebackground=PANEL, activeforeground=TEXT,
                           font=FONT_B).pack(anchor="w")
            Wrap(f, text=desc, bg=PANEL, fg=DIM, font=FONT_S).pack(fill="x", padx=(24, 0))
        self.adv = tk.Frame(p, bg=PANEL2)
        a = self.adv
        Wrap(a, text="Pas encore de clé ? Le guide vous accompagne écran par écran (environ 5 minutes, gratuit).",
             bg=PANEL2, font=FONT_S).pack(fill="x", padx=10, pady=(8, 4))
        gb = tk.Frame(a, bg=PANEL2)
        gb.pack(anchor="w", padx=10)
        button(gb, "Comment obtenir ma clé ? (pas à pas)", self.show_key_guide, primary=True).pack(side="left")
        button(gb, "Ouvrir le portail développeur", lambda: webbrowser.open(core.PORTAL_URL)).pack(side="left", padx=8)
        g = tk.Frame(a, bg=PANEL2)
        g.pack(fill="x", padx=10, pady=8)
        tk.Label(g, text="Client ID", bg=PANEL2, fg=TEXT, font=FONT).grid(row=0, column=0, sticky="w", pady=2)
        tk.Entry(g, textvariable=w["client_id"], bg=PANEL, fg=TEXT, insertbackground=TEXT, relief="flat",
                 font=FONT, width=48).grid(row=0, column=1, sticky="we", padx=8)
        tk.Label(g, text="Client Secret", bg=PANEL2, fg=TEXT, font=FONT).grid(row=1, column=0, sticky="w", pady=2)
        self.ent_secret = tk.Entry(g, textvariable=w["client_secret"], show="•", bg=PANEL, fg=TEXT,
                                   insertbackground=TEXT, relief="flat", font=FONT, width=48)
        self.ent_secret.grid(row=1, column=1, sticky="we", padx=8)
        self.show_sec = tk.BooleanVar(value=False)
        tk.Checkbutton(g, text="afficher", variable=self.show_sec, bg=PANEL2, fg=DIM, selectcolor=PANEL,
                       activebackground=PANEL2, font=FONT_S,
                       command=lambda: self.ent_secret.configure(show="" if self.show_sec.get() else "•")
                       ).grid(row=1, column=2)
        Wrap(a, text="La clé secrète est rangée dans le Gestionnaire d'identification de Windows, jamais dans un "
                     "fichier. Ne la donnez à personne.", bg=PANEL2, fg=DIM, font=FONT_S).pack(fill="x", padx=10, pady=(0, 8))
        bar = tk.Frame(p, bg=PANEL)
        bar.pack(side="bottom", fill="x", pady=(10, 0))
        button(bar, "Tester la source", self._test_source).pack(side="left")
        self.lbl_test = Wrap(bar, text="", bg=PANEL, font=FONT_S)
        self.lbl_test.pack(side="left", fill="x", expand=True, padx=10)
        self._source_changed()

    def _source_changed(self):
        if hasattr(self, "lbl_test") and self.lbl_test.winfo_exists():
            self.lbl_test.configure(text="")
        if self.w["source"].get() == "blizzard":
            self.adv.pack(fill="x", pady=(10, 0))
        else:
            self.adv.pack_forget()

    def _source_values(self):
        w = self.w
        return {"source": w["source"].get(), "region": w["region"].get(),
                "client_id": w["client_id"].get().strip(), "client_secret": w["client_secret"].get().strip()}

    def _test_source(self):
        self.lbl_test.configure(text="Test en cours…", fg=DIM)
        vals = self._source_values()
        threading.Thread(target=lambda: self.q.put(("test", core.test_source(vals))), daemon=True).start()

    def _check_source(self):
        v = self._source_values()
        if v["source"] == "blizzard" and (not v["client_id"] or not v["client_secret"]):
            messagebox.showerror(core.APP_NAME, "Renseignez le Client ID et le Client Secret, ou choisissez le mode simple.")
            return False
        return True

    # --- étape 3 : marché ---------------------------------------------------------
    def _page_market(self, p):
        w = self.w
        tk.Label(p, text="Mon marché", bg=PANEL, fg=GOLD, font=FONT_H).pack(anchor="w")
        Wrap(p, text="Choisissez le type de serveur de votre personnage (affiché à l'écran de choix du royaume). "
                     "Les trois HDV de ce type (Alliance, Horde, neutre) seront suivis, quelle que soit votre faction.",
             bg=PANEL, fg=DIM).pack(fill="x", pady=(2, 12))
        tk.Label(p, text="Type de serveur", bg=PANEL, fg=TEXT, font=FONT_B).pack(anchor="w")
        self.cb_rs = ttk.Combobox(p, state="readonly", width=36, font=FONT, values=[lab for _, lab, _ in E.RULESETS])
        self.cb_rs.pack(anchor="w", pady=(4, 2))
        self.cb_rs.bind("<<ComboboxSelected>>", lambda e: self._rs_changed(E.RULESETS[self.cb_rs.current()][0]))
        self.lbl_houses = tk.Label(p, text="", bg=PANEL, fg=DIM, font=FONT_S)
        self.lbl_houses.pack(anchor="w", pady=(0, 10))
        sug, realm = core.suggest_from_game(w["forever"]) if w["forever"] else (None, None)
        if sug:
            txt, col = "Suggestion d'après votre personnage (royaume « %s ») : %s." % (realm, E.ruleset_label(sug)), GREEN
            if not w["type_marche"].get():
                w["type_marche"].set(sug)
        elif realm:
            txt, col = "Relevé du jeu trouvé (royaume « %s »), type non déductible du nom : vérifiez ci-dessous." % realm, GOLD
        else:
            txt, col = ("Aucun relevé de l'HDV trouvé dans le jeu : choisissez votre type de serveur "
                        "(vous pourrez vérifier plus tard)."), DIM
        Wrap(p, text=txt, bg=PANEL, fg=col, font=FONT_S).pack(fill="x")
        bar = tk.Frame(p, bg=PANEL)
        bar.pack(fill="x", pady=(14, 4))
        button(bar, "Vérifier avec mon relevé de l'HDV", self._verify_market).pack(side="left")
        Wrap(p, text="Compare votre dernier relevé fait en jeu (bouton « Lire les annonces » à l'HDV, puis /reload) "
                     "aux HDV de chaque type de serveur. Environ 10 secondes.", bg=PANEL, fg=DIM,
             font=FONT_S).pack(fill="x")
        self.txt_verify = tk.Text(p, height=7, bg=PANEL2, fg=TEXT, relief="flat", font=("Consolas", 9),
                                  state="disabled", wrap="word")
        self.txt_verify.pack(fill="both", expand=True, pady=(8, 0))
        keys = [k for k, _, _ in E.RULESETS]
        if w["type_marche"].get() in keys:
            self.cb_rs.current(keys.index(w["type_marche"].get()))
            self._rs_changed(w["type_marche"].get())

    def _rs_changed(self, key):
        self.w["type_marche"].set(key)
        h = E.houses_for(key)
        self.lbl_houses.configure(text="HDV suivis : Alliance %d · Horde %d · neutre %d" % (h["A"], h["H"], h["N"]))

    def _verify_log(self, text):
        self.txt_verify.configure(state="normal")
        self.txt_verify.insert("end", text + "\n")
        self.txt_verify.see("end")
        self.txt_verify.configure(state="disabled")

    def _verify_market(self):
        self.txt_verify.configure(state="normal")
        self.txt_verify.delete("1.0", "end")
        self.txt_verify.configure(state="disabled")
        self._verify_log("Vérification en cours…")
        vals = self._source_values()
        forever = self.w["forever"]

        def job():
            try:
                res = core.verify_market_with_scans(forever, vals, log=lambda s: self.q.put(("vlog", s)))
            except Exception as ex:
                res = (None, "%s : %s" % (type(ex).__name__, ex))
            self.q.put(("verify", res))
        threading.Thread(target=job, daemon=True).start()

    def _check_market(self):
        if not E.houses_for(self.w["type_marche"].get()):
            messagebox.showerror(core.APP_NAME, "Choisissez votre type de serveur.")
            return False
        return True

    # --- étape 4 : mise à jour automatique -----------------------------------------
    def _page_auto(self, p):
        w = self.w
        tk.Label(p, text="Mise à jour automatique", bg=PANEL, fg=GOLD, font=FONT_H).pack(anchor="w")
        Wrap(p, text="L'application met les prix à jour en arrière-plan, sans fenêtre, pendant que vous jouez ou non. "
                     "En jeu, /reload charge les nouveaux prix.", bg=PANEL, fg=DIM).pack(fill="x", pady=(2, 12))

        def chk(text, var, state="normal"):
            tk.Checkbutton(p, text=text, variable=var, bg=PANEL, fg=TEXT, selectcolor=PANEL2, activebackground=PANEL,
                           activeforeground=TEXT, font=FONT, state=state, disabledforeground=DIM).pack(anchor="w", pady=2)
        row = tk.Frame(p, bg=PANEL)
        row.pack(anchor="w", pady=2)
        tk.Checkbutton(row, text="Mettre à jour les prix toutes les", variable=w["auto"], bg=PANEL, fg=TEXT,
                       selectcolor=PANEL2, activebackground=PANEL, activeforeground=TEXT, font=FONT).pack(side="left")
        ttk.Spinbox(row, from_=30, to=240, increment=15, width=5, textvariable=w["interval"],
                    font=FONT).pack(side="left", padx=6)
        tk.Label(row, text="minutes", bg=PANEL, fg=TEXT, font=FONT).pack(side="left")
        chk("Démarrer avec Windows (en arrière-plan)", w["startup"], "normal" if core.IS_WIN else "disabled")
        chk("Icône près de l'horloge : fermer la fenêtre ne quitte pas l'application", w["tray"],
            "normal" if HAS_TRAY else "disabled")
        if not HAS_TRAY:
            Wrap(p, text="(Icône indisponible : module pystray absent. Fermer la fenêtre la réduit dans la barre des tâches.)",
                 bg=PANEL, fg=DIM, font=FONT_S).pack(fill="x", padx=(24, 0))
        if core.old_task_exists():
            box = tk.Frame(p, bg=PANEL2)
            box.pack(fill="x", pady=(14, 0))
            Wrap(box, text="L'ancienne mise à jour horaire (tâche planifiée « %s ») sera arrêtée et supprimée : "
                           "l'application la remplace." % E.TASK_NAME, bg=PANEL2, fg=GOLD,
                 font=FONT_S).pack(fill="x", padx=10, pady=8)
        sm = tk.Frame(p, bg=PANEL)
        sm.pack(fill="x", pady=(16, 0))
        tk.Label(sm, text="Récapitulatif", bg=PANEL, fg=TEXT, font=FONT_B).pack(anchor="w")
        src = "Forever AH (sans compte)" if w["source"].get() == "foreverah" else "API Blizzard (votre clé)"
        h = E.houses_for(w["type_marche"].get()) or {}
        lines = ["WoW Forever : %s" % w["forever"],
                 "Source : %s · région %s" % (src, w["region"].get().upper()),
                 "Type de serveur : %s (HDV %s / %s / %s)" % (E.ruleset_label(w["type_marche"].get()),
                                                             h.get("A", "?"), h.get("H", "?"), h.get("N", "?"))]
        Wrap(sm, text="\n".join(lines), bg=PANEL, fg=DIM, font=FONT_S).pack(fill="x")

    def _finish(self):
        w = self.w
        c = self.cfg
        try:
            interval = max(30, min(240, int(float(w["interval"].get() or 60))))
        except ValueError:
            interval = 60
        f = w["forever"]
        c["wow"]["dossier"] = f
        c["wow"]["addons"] = core.addons_dir(f)
        c["source"]["type"] = w["source"].get()
        c["marche"]["region"] = w["region"].get()
        c["marche"]["type_marche"] = w["type_marche"].get()
        for fac in E.FACTIONS:
            c["marche"][E.CFG_KEYS[fac]] = ""       # HDV déduits du type de serveur
        c["outil"]["intervalle_minutes"] = str(interval)
        c["outil"]["auto_horaire"] = "1" if w["auto"].get() else "0"
        c["outil"]["demarrage_windows"] = "1" if w["startup"].get() else "0"
        c["outil"]["zone_notification"] = "1" if w["tray"].get() else "0"
        if w["source"].get() == "blizzard":
            cid = w["client_id"].get().strip()
            c["battlenet"]["client_id"] = cid
            if not core.set_secret(cid, w["client_secret"].get().strip()):
                messagebox.showerror(core.APP_NAME, "Impossible d'enregistrer la clé dans le Gestionnaire d'identification.")
                return
        c["app"]["assistant_fait"] = "1"
        c["app"]["version"] = core.APP_VERSION
        core.save(c)
        notes = []
        try:
            if core.IS_WIN:
                core.set_startup(w["startup"].get())
        except OSError as ex:
            notes.append("Démarrage avec Windows non réglé : %s" % ex)
        try:
            if core.remove_old_task():
                notes.append("Ancienne tâche planifiée supprimée.")
        except OSError:
            pass
        if w["tray"].get() and HAS_TRAY and not self.tray:
            self._start_tray()
        elif not w["tray"].get() and self.tray:
            self._stop_tray()
        self.update_now()                  # d'abord la mise à jour demandée (une seule exécution)
        self.scheduler.set_interval(interval)
        self.scheduler.enabled = w["auto"].get()
        self.show_main()
        if notes:
            messagebox.showinfo(core.APP_NAME, "\n".join(notes))

    # ------------------------------------------------------------------ fenêtre principale
    def show_main(self):
        if self.host is not None and self.host.winfo_exists():
            self.host.destroy()
        self.host = None
        self.mode = "main"
        self._render()

    def refresh_main(self):
        if self.mode != "main" or not hasattr(self, "lbl_state") or not self.lbl_state.winfo_exists():
            return
        c = self.cfg
        addons = c["wow"].get("addons", "")
        st = core.prices_status(addons)
        now = time.time()
        houses = E.houses_for(c["marche"].get("type_marche", "")) or {}
        for fac, (l1, l2, l3) in self.cards.items():
            m = (st or {}).get("markets", {}).get(fac)
            l1.configure(text="HDV n° %s" % houses.get(fac, "?"))
            if m:
                fresh = now - m["time"] < 3 * 3600
                l2.configure(text="Données de %s" % time.strftime("%H:%M", time.localtime(m["time"])),
                             fg=TEXT if fresh else GOLD)
                l3.configure(text="%s · %s annonces" % (core.ago(m["time"], now), "{:,}".format(m["total"]).replace(",", " ")))
            else:
                l2.configure(text="Pas encore de prix", fg=DIM)
                l3.configure(text="")
        sch = self.scheduler
        if self.busy_update or sch.running:
            state, col, ic = "Mise à jour en cours…", GOLD, "warn"
        elif self.last_code not in (None, 0):
            state, col, ic = "Dernière mise à jour en échec : voir le journal.", RED, "error"
        elif st:
            state, col, ic = "Prix à jour (%s)." % core.ago(st["generated"], now), GREEN, "check"
        else:
            state, col, ic = "Aucun prix : « Mettre à jour maintenant ».", GOLD, "warn"
        self.lbl_state.configure(text=state, fg=col)
        self.canvas.itemconfigure(self.state_icon, image=self._state_imgs[ic])
        src = "Forever AH" if c["source"].get("type") == "foreverah" else "API Blizzard"
        lines = ["Source : %s  ·  Type de serveur : %s (%s)" % (src, E.ruleset_label(c["marche"].get("type_marche", "")),
                                                              c["marche"].get("region", "eu").upper()),
                 "Dernière mise à jour réussie : %s" % (time.strftime("%d/%m %H:%M", time.localtime(sch.last_ok))
                                                        if sch.last_ok else "aucune")]
        if sch.enabled and sch.next_due:
            lines.append("Prochaine mise à jour : vers %s (toutes les %d min)" % (
                time.strftime("%H:%M", time.localtime(max(sch.next_due, now))), sch.interval // 60))
        elif not sch.enabled:
            lines.append("Mise à jour automatique désactivée (Paramètres, étape 4).")
        self.lbl_info.configure(text="\n".join(lines))
        text, action = core.addon_offer(addons, self._online)
        if self.busy_online:
            text, action = "Téléchargement en cours…", None
        self._banner_action = action
        self.banner_txt.configure(text=text)
        self.banner_btn.configure(text=("Mettre à jour" if core.can_self_update() else "Télécharger")
                                  if action == "app" else "Installer l'add-on")
        self._draw_versions()
        self.banner_btn.set_visible(action is not None)
        self.btn_update.configure(state="disabled" if (self.busy_update or sch.running) else "normal")

    def _draw_versions(self):
        """« Application 1.6.0 · à jour   Add-on 0.15.0 · 0.16.0 disponible » en couleurs."""
        anchor = getattr(self, "_ver_anchor", None)
        if not anchor:
            return
        c = self.canvas
        for i in getattr(self, "_ver_items", []):
            c.delete(i)
        self._ver_items = []
        x, y, k = anchor
        colors = {"ok": GREEN, "maj": GOLD, "dim": DIM, "bad": RED}
        self.version_texts = []
        for txt, st in core.version_status(self.cfg["wow"].get("addons", ""), self._online):
            mark = {"ok": "\u2713 ", "maj": "\u2191 ", "bad": "\u2717 "}.get(st, "")
            item = c.create_text(x, y, text=mark + txt, anchor="w", fill=colors.get(st, DIM),
                                 font=(SANS, -int(13 * k), "bold" if st in ("maj", "bad") else "normal"), tags="versions")
            self._ver_items.append(item)
            self.version_texts.append((txt, st))
            bb = c.bbox(item)
            x = (bb[2] if bb else x + 200 * k) + 22 * k
        # Lien « Vérifier » : vérification immédiate des mises à jour
        busy = getattr(self, "checking", False)
        link = c.create_text(x - 6 * k, y, text="Vérification…" if busy else "\u21bb Vérifier", anchor="w",
                             fill=DIM if busy else GOLD, font=(SANS, -int(13 * k), "underline"), tags="versions")
        self._ver_items.append(link)
        self.check_link = link
        if not busy:
            c.tag_bind(link, "<Button-1>", lambda e: self.check_updates_now())
            c.tag_bind(link, "<Enter>", lambda e: c.configure(cursor="hand2"))
            c.tag_bind(link, "<Leave>", lambda e: c.configure(cursor=""))

    def install_addon_now(self):
        action = self._banner_action
        if action == "app":
            if core.can_self_update():
                # Mise à jour en un clic : téléchargement, contrôle, remplacement, redémarrage.
                self.busy_online = True
                info = self._online

                def work():
                    try:
                        self.q.put(("app_ready", (True, core.download_app(info))))
                    except Exception as ex:
                        self.q.put(("app_ready", (False, str(ex))))
                threading.Thread(target=work, daemon=True).start()
                self.refresh_main()
            else:
                webbrowser.open((self._online or {}).get("page") or core.RELEASE_PAGE)
            return
        if action == "online":
            # Téléchargement en arrière-plan : la fenêtre reste utilisable.
            self.busy_online = True
            addons, info = self.cfg["wow"]["addons"], self._online

            def work():
                try:
                    self.q.put(("online_done", (True, core.install_addon_online(addons, info))))
                except Exception as ex:
                    self.q.put(("online_done", (False, str(ex))))
            threading.Thread(target=work, daemon=True).start()
            self.refresh_main()
            return
        try:
            v = core.install_addon(self.cfg["wow"]["addons"])
            messagebox.showinfo(core.APP_NAME, "Add-on %s installé. En jeu : /reload." % v)
        except Exception as ex:
            messagebox.showerror(core.APP_NAME, "Installation impossible : %s\nFermez le jeu et réessayez." % ex)
        self.refresh_main()

    def update_now(self):
        if not core.is_ready(self.cfg):
            return
        self.busy_update = True
        self.scheduler.update_now()
        self.refresh_main()

    def open_addons(self):
        p = self.cfg["wow"].get("addons", "")
        if os.path.isdir(p):
            if core.IS_WIN:
                os.startfile(p)       # noqa: S606 - ouverture de l'Explorateur
            else:
                webbrowser.open("file://" + p)

    # ------------------------------------------------------------------ guide de la clé
    def show_key_guide(self):
        """Fenêtre guide : une étape à la fois, avec Ouvrir la page / Copier."""
        old = getattr(self, "guide_win", None)
        if old is not None and old.winfo_exists():
            old.lift()
            old.focus_force()
            return old
        win = tk.Toplevel(self.root, bg=PANEL)
        self.guide_win = win
        win.title("Obtenir ma clé Blizzard — pas à pas")
        win.geometry("620x470")
        win.minsize(520, 420)
        try:
            win.transient(self.root)
        except tk.TclError:
            pass
        top = tk.Frame(win, bg=PANEL)
        top.pack(fill="x", padx=18, pady=(14, 4))
        lbl_n = tk.Label(top, text="", bg=PANEL, fg=DIM, font=FONT_S)
        lbl_n.pack(side="right")
        lbl_t = tk.Label(top, text="", bg=PANEL, fg=GOLD, font=FONT_H, anchor="w")
        lbl_t.pack(side="left", fill="x")
        dots = tk.Frame(win, bg=PANEL)
        dots.pack(fill="x", padx=18)
        dot_lbls = [tk.Label(dots, text="●", bg=PANEL, font=FONT_S) for _ in KEY_GUIDE]
        for d in dot_lbls:
            d.pack(side="left", padx=1)
        tk.Frame(win, bg=LINE, height=1).pack(fill="x", padx=18, pady=(6, 10))
        body = Wrap(win, text="", bg=PANEL, fg=TEXT, font=FONT)
        body.pack(fill="x", padx=18)
        acts = tk.Frame(win, bg=PANEL)
        acts.pack(fill="x", padx=18, pady=(12, 0))
        lbl_copy = tk.Label(win, text="", bg=PANEL, fg=GREEN, font=FONT_S, anchor="w")
        lbl_copy.pack(fill="x", padx=18, pady=(6, 0))
        nav = tk.Frame(win, bg=PANEL)
        nav.pack(side="bottom", fill="x", padx=18, pady=14)
        st = {"i": 0}

        def copy(txt):
            win.clipboard_clear()
            win.clipboard_append(txt)
            lbl_copy.configure(text="Copié : « %s » — collez-le (Ctrl+V) dans le formulaire." % txt)

        def show(i):
            st["i"] = i = max(0, min(len(KEY_GUIDE) - 1, i))
            title, text, url, copies = KEY_GUIDE[i]
            lbl_t.configure(text=title)
            lbl_n.configure(text="Étape %d sur %d" % (i + 1, len(KEY_GUIDE)))
            for j, d in enumerate(dot_lbls):
                d.configure(fg=GOLD if j == i else (GREEN if j < i else LINE))
            body.configure(text=text)
            lbl_copy.configure(text="")
            for c in acts.winfo_children():
                c.destroy()
            if url:
                button(acts, "Ouvrir la page", lambda u=url: webbrowser.open(u), primary=True).pack(anchor="w", pady=2)
            for lab, val in copies:
                button(acts, lab, lambda v=val: copy(v)).pack(anchor="w", pady=2)
            b_prev.configure(state="normal" if i > 0 else "disabled")
            b_next.configure(text="Terminer" if i == len(KEY_GUIDE) - 1 else "Suivant")

        def nxt():
            if st["i"] >= len(KEY_GUIDE) - 1:
                win.destroy()
            else:
                show(st["i"] + 1)
        b_prev = button(nav, "Précédent", lambda: show(st["i"] - 1))
        b_prev.pack(side="left")
        b_next = button(nav, "Suivant", nxt, primary=True)
        b_next.pack(side="right")
        win._show, win._next, win._state = show, nxt, st      # pour les tests
        show(0)
        return win

    # ------------------------------------------------------------------ journal
    def show_journal(self):
        win = tk.Toplevel(self.root, bg=BG)
        win.title("Journal des mises à jour")
        win.geometry("760x480")
        txt = tk.Text(win, bg=PANEL, fg=TEXT, relief="flat", font=("Consolas", 9), wrap="none")
        txt.pack(fill="both", expand=True, padx=10, pady=(10, 6))

        def load():
            try:
                with open(E.JOURNAL, encoding="utf-8", errors="replace") as f:
                    lines = f.readlines()[-400:]
            except OSError:
                lines = ["Journal vide pour l'instant.\n"]
            txt.configure(state="normal")
            txt.delete("1.0", "end")
            for ln in lines:
                tag = "ok" if ln.startswith("RÉSULTAT : OK") else ("err" if ln.startswith("RÉSULTAT : ERREUR") else
                                                                  ("head" if ln.startswith("=====") else None))
                txt.insert("end", ln, tag)
            txt.tag_configure("ok", foreground=GREEN)
            txt.tag_configure("err", foreground=RED)
            txt.tag_configure("head", foreground=GOLD)
            txt.see("end")
            txt.configure(state="disabled")
        bar = tk.Frame(win, bg=BG)
        bar.pack(fill="x", padx=10, pady=(0, 10))
        button(bar, "Actualiser", load).pack(side="left")
        button(bar, "Fermer", win.destroy).pack(side="right")
        load()

    # ------------------------------------------------------------------ zone de notification
    def _start_tray(self):
        if not HAS_TRAY or self.tray:
            return
        try:
            menu = pystray.Menu(
                pystray.MenuItem("Ouvrir", lambda: self.q.put(("show",)), default=True),
                pystray.MenuItem("Mettre à jour maintenant", lambda: self.q.put(("update",))),
                pystray.MenuItem("Vérifier les nouvelles versions", lambda: self.q.put(("check_versions",))),
                pystray.MenuItem("Quitter", lambda: self.q.put(("quit",))))
            self.tray = pystray.Icon(core.APP_ID, coin_image(64), core.APP_NAME, menu)
            self.tray.run_detached()
        except Exception:
            self.tray = None

    def _stop_tray(self):
        if self.tray:
            try:
                self.tray.stop()
            except Exception:
                pass
            self.tray = None

    def show(self):
        self.root.deiconify()
        self.root.lift()
        try:
            self.root.focus_force()
        except tk.TclError:
            pass
        self.refresh_main()

    def on_close(self):
        if not core.is_ready(self.cfg):
            self.quit()
            return
        first = self.cfg["app"].get("avis_zone_vu", "0") != "1"
        if self.tray:
            self.root.withdraw()
            msg = ("Shadsun Gold Lens continue en arrière-plan : icône de pièce d'or près de l'horloge "
                   "(clic droit pour ouvrir ou quitter).")
        elif self.scheduler.enabled:
            self.root.iconify()
            msg = "Shadsun Gold Lens reste ouverte dans la barre des tâches pour mettre les prix à jour."
        else:
            self.quit()
            return
        if first:
            self.cfg["app"]["avis_zone_vu"] = "1"
            core.save(self.cfg)
            messagebox.showinfo(core.APP_NAME, msg)

    def quit(self):
        self.quitting = True
        self.scheduler.stop()
        self._stop_tray()
        self.root.destroy()

    # ------------------------------------------------------------------ événements
    def _poll(self):
        if self.quitting:
            return
        try:
            while True:
                ev = self.q.get_nowait()
                self._handle(ev)
        except queue.Empty:
            pass
        if core.take_show_signal():
            self.show()
        now = time.time()
        if now - getattr(self, "_last_refresh", 0) > 20:
            self._last_refresh = now
            self.refresh_main()
        self.root.after(400, self._poll)

    def _handle(self, ev):
        kind = ev[0]
        if kind == "test":
            ok, msg = ev[1]
            if hasattr(self, "lbl_test") and self.lbl_test.winfo_exists():
                self.lbl_test.configure(text=msg, fg=GREEN if ok else RED)
        elif kind == "vlog":
            if hasattr(self, "txt_verify") and self.txt_verify.winfo_exists():
                self._verify_log(ev[1])
        elif kind == "verify":
            key, msg = ev[1]
            if hasattr(self, "txt_verify") and self.txt_verify.winfo_exists():
                self._verify_log(("=> " + msg) if key else msg)
                if key:
                    keys = [k for k, _, _ in E.RULESETS]
                    self.cb_rs.current(keys.index(key))
                    self._rs_changed(key)
        elif kind == "sched":
            t, d = ev[1], ev[2]
            if t == "debut":
                self.busy_update = True
            elif t == "fin":
                self.busy_update = False
                self.last_code = d.get("code")
                if self.tray and self.last_code not in (0, None):
                    try:
                        self.tray.notify("Mise à jour des prix en échec : voir le journal.", core.APP_NAME)
                    except Exception:
                        pass
            self.refresh_main()
        elif kind == "show":
            self.show()
        elif kind == "check_versions":
            self.show()
            self.check_updates_now()
        elif kind == "online":
            if ev[1]:
                self._online = ev[1]
            self.refresh_main()
        elif kind == "online_manual":
            self.checking = False
            info, err = ev[1], ev[2]
            if info and not err:
                self._online = info
            self.refresh_main()
            text, action = core.addon_offer(self.cfg["wow"].get("addons", ""), self._online)
            if err:
                messagebox.showwarning(core.APP_NAME, "Vérification impossible : %s\nRéessayez plus tard." % err)
            elif action:
                messagebox.showinfo(core.APP_NAME, text + "\n\nUtilisez le bouton du bandeau, sous les informations.")
            else:
                messagebox.showinfo(core.APP_NAME, "Tout est à jour.\n" + "\n".join(t for t, _ in core.version_status(
                    self.cfg["wow"].get("addons", ""), self._online)))
        elif kind == "app_ready":
            ok, msg = ev[1]
            if ok:
                core.start_self_update(msg)
                self.quit()
                return
            self.busy_online = False
            messagebox.showerror(core.APP_NAME, "Mise à jour impossible : %s" % msg)
            self.refresh_main()
        elif kind == "online_done":
            self.busy_online = False
            ok, msg = ev[1]
            if ok:
                messagebox.showinfo(core.APP_NAME, "Add-on %s installé depuis GitHub. En jeu : /reload." % msg)
            else:
                messagebox.showerror(core.APP_NAME, "Installation impossible : %s\nFermez le jeu et réessayez." % msg)
            self.refresh_main()
        elif kind == "update":
            self.update_now()
        elif kind == "quit":
            self.quit()


def main(argv=None):
    argv = list(sys.argv[1:] if argv is None else argv)
    if core.IS_WIN:
        try:   # texte net sur les écrans à haute résolution
            import ctypes
            ctypes.windll.shcore.SetProcessDpiAwareness(1)
        except Exception:
            pass
    def arg(name):
        if name in argv:
            i = argv.index(name)
            return argv[i + 1] if i + 1 < len(argv) else ""
        return None
    # Mode remplacement (lancé par l'ancienne version pour se mettre à jour)
    if "--remplacer" in argv:
        core.replace_and_relaunch(sys.executable, arg("--remplacer"), int(arg("--pid") or 0))
        return 0
    # Exe lancé ailleurs qu'à son emplacement fixe : installation puis relance
    if core.bootstrap_install(argv):
        return 0
    lock = core.acquire_instance_lock()
    if lock is None:
        core.signal_show()          # l'application est déjà ouverte : on la fait réapparaître
        return 0
    core.take_show_signal()
    if core.FROZEN and core.running_from_install():
        core.cleanup_update_leftovers()
        core.ensure_shortcuts()     # répare le raccourci du Bureau (1.6.0 : Bureau OneDrive non trouvé)
        if core.startup_enabled():
            core.set_startup(True)  # le démarrage avec Windows pointe vers la copie installée
    root = tk.Tk()
    App(root, background="--arriere-plan" in argv, installed_from=arg("--installe-depuis"),
        updated="--mis-a-jour" in argv)
    root.mainloop()
    return 0


if __name__ == "__main__":
    sys.exit(main())
