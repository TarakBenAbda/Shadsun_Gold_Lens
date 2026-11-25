# -*- coding: utf-8 -*-
"""
===============================================================================
 Shadsun Gold Lens — habillage de l'application (sgl_theme.py)
 Auteur : Tarak Ben Abda – novembre 2026
-------------------------------------------------------------------------------
 FR : Dessine avec Pillow le décor de style « WoW » allégé : fond bleu nuit
      (ou assets/fond.jpg s'il existe), halo doré, cadre et ornements dorés,
      personnage, logo, panneaux, cartes des HDV avec symboles originaux
      (bouclier, haches croisées, pièces), boutons dorés ou bleus avec icônes.
      Aucun logo de Blizzard : symboles dessinés ici.
 EN : Pillow-drawn "WoW-like" skin for the desktop app.
===============================================================================
"""
import math
import os
import sys

from PIL import Image, ImageDraw, ImageFilter

HERE = os.path.dirname(os.path.abspath(__file__))
SS = 3          # sur-échantillonnage des formes (bords lisses) / supersampling

GOLD = (232, 194, 90)
GOLD_L = (250, 226, 150)
GOLD_D = (150, 108, 34)
NAVY = (12, 20, 38)
NAVY2 = (22, 38, 72)
FAC = {"A": (60, 120, 230), "H": (205, 50, 50), "N": (214, 168, 60)}


def asset(name):
    for base in (getattr(sys, "_MEIPASS", None), HERE):
        if base:
            p = os.path.join(base, "assets", name)
            if os.path.exists(p):
                return p
    return None


_cache = {}


def load(name):
    if name not in _cache:
        p = asset(name)
        _cache[name] = Image.open(p).convert("RGBA") if p else None
    return _cache[name]


# -----------------------------------------------------------------------------
# Outils / helpers
# -----------------------------------------------------------------------------
def vgradient(w, h, top, bottom, alpha=255):
    g = Image.new("RGBA", (1, max(1, h)))
    for y in range(h):
        t = y / max(1, h - 1)
        g.putpixel((0, y), tuple(int(top[i] + (bottom[i] - top[i]) * t) for i in range(3)) + (alpha,))
    return g.resize((max(1, w), max(1, h)))


def radial(w, h, cx, cy, r, color, alpha):
    """Halo : disque flou de couleur / soft radial glow."""
    lay = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    d = ImageDraw.Draw(lay)
    d.ellipse((cx - r, cy - r, cx + r, cy + r), fill=color + (alpha,))
    return lay.filter(ImageFilter.GaussianBlur(r * 0.45))


def rounded_mask(w, h, r):
    w, h = max(2, w), max(2, h)
    r = max(1, min(r, w // 2, h // 2))
    m = Image.new("L", (w * SS, h * SS), 0)
    ImageDraw.Draw(m).rounded_rectangle((0, 0, w * SS - 1, h * SS - 1), radius=r * SS, fill=255)
    return m.resize((w, h), Image.LANCZOS)


def border(img, r, width, color, inset=0):
    w, h = img.size
    inset = max(0, min(inset, (min(w, h) - 2) // 2))       # jamais de rectangle inversé
    x0, y0 = inset * SS, inset * SS
    x1, y1 = max(x0 + 1, (w - inset) * SS - 1), max(y0 + 1, (h - inset) * SS - 1)
    rad = max(1, min(r - inset, (x1 - x0) // (2 * SS), (y1 - y0) // (2 * SS))) * SS
    lay = Image.new("RGBA", (w * SS, h * SS), (0, 0, 0, 0))
    ImageDraw.Draw(lay).rounded_rectangle((x0, y0, x1, y1), radius=rad, outline=color, width=max(1, int(width * SS)))
    img.alpha_composite(lay.resize((w, h), Image.LANCZOS))


def diamond(d, cx, cy, s, fill, outline=None):
    d.polygon([(cx, cy - s), (cx + s * 0.62, cy), (cx, cy + s), (cx - s * 0.62, cy)], fill=fill, outline=outline)


def shape_layer(w, h, draw_fn):
    """Dessine en sur-échantillonné puis réduit (bords lisses)."""
    lay = Image.new("RGBA", (w * SS, h * SS), (0, 0, 0, 0))
    draw_fn(ImageDraw.Draw(lay), SS)
    return lay.resize((w, h), Image.LANCZOS)


# -----------------------------------------------------------------------------
# Panneaux, cartes, boutons
# -----------------------------------------------------------------------------
def panel(w, h, k=1.0, fill=(14, 24, 46), alpha=232, radius=10, accent=None, edge=True):
    w, h = max(8, int(w)), max(8, int(h))
    r = max(4, int(radius * k))
    body = vgradient(w, h, tuple(min(255, c + 8) for c in fill), fill, alpha)
    out = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    out.paste(body, (0, 0), rounded_mask(w, h, r))
    if accent:
        glow = vgradient(w, max(2, int(h * 0.45)), accent, fill, 120)
        m = rounded_mask(w, h, r).crop((0, 0, w, glow.size[1]))
        out.alpha_composite(Image.composite(glow, Image.new("RGBA", glow.size, (0, 0, 0, 0)), m))
    if edge:
        border(out, r, max(1.5, 2 * k), GOLD_D + (255,))
        border(out, r, max(1.0, 1.0 * k), GOLD + (220,), inset=max(2, int(3 * k)))
    if accent:
        lay = shape_layer(w, h, lambda d, s: d.line((w * 0.12 * s, 2 * k * s, w * 0.88 * s, 2 * k * s),
                                                     fill=accent + (255,), width=int(3 * k * s)))
        out.alpha_composite(lay.filter(ImageFilter.GaussianBlur(1.2)))
    return out


def button(w, h, k=1.0, kind="blue", state="normal"):
    """Fond de bouton (le texte et l'icône sont ajoutés par l'interface)."""
    w, h = max(8, int(w)), max(8, int(h))
    r = max(4, int(7 * k))
    if kind == "gold":
        top, bot, edge = (252, 222, 130), (196, 140, 40), (120, 80, 20)
    else:
        top, bot, edge = (34, 58, 104), (16, 30, 60), GOLD_D
    if state == "hover":
        top, bot = tuple(min(255, c + 22) for c in top), tuple(min(255, c + 22) for c in bot)
    out = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    out.paste(vgradient(w, h, top, bot), (0, 0), rounded_mask(w, h, r))
    border(out, r, max(1.5, 2 * k), edge + (255,))
    border(out, r, max(1.0, 1 * k), (GOLD_L if kind == "gold" else GOLD) + (200 if state == "hover" else 150,), inset=max(2, int(3 * k)))
    if state == "disabled":
        grey = out.convert("LA").convert("RGBA")
        grey.putalpha(out.getchannel("A").point(lambda a: int(a * 0.55)))
        out = grey
    return out


# --- Icônes des boutons (dessinées) / button icons ----------------------------
def icon(name, size, color=GOLD_L):
    s = size

    def draw(d, f):
        S = s * f
        c = color + (255,)
        lw = max(2, int(S * 0.09))
        if name == "refresh":
            d.arc((S * .14, S * .14, S * .86, S * .86), 30, 300, fill=c, width=lw)
            d.polygon([(S * .70, S * .02), (S * .98, S * .26), (S * .64, S * .34)], fill=c)
        elif name == "scroll":
            d.rounded_rectangle((S * .22, S * .12, S * .80, S * .88), radius=S * .08, outline=c, width=lw)
            for y in (.34, .50, .66):
                d.line((S * .34, S * y, S * .68, S * y), fill=c, width=max(1, lw // 2))
        elif name == "gear":
            cx = cy = S / 2
            for i in range(8):
                a = i * math.pi / 4
                d.line((cx + math.cos(a) * S * .22, cy + math.sin(a) * S * .22, cx + math.cos(a) * S * .44,
                        cy + math.sin(a) * S * .44), fill=c, width=int(S * .16))
            d.ellipse((S * .2, S * .2, S * .8, S * .8), fill=c)
            d.ellipse((S * .37, S * .37, S * .63, S * .63), fill=(0, 0, 0, 0))
        elif name == "folder":
            d.polygon([(S * .08, S * .26), (S * .38, S * .26), (S * .46, S * .36), (S * .92, S * .36),
                       (S * .92, S * .82), (S * .08, S * .82)], fill=c)
        elif name == "exit":
            d.rectangle((S * .12, S * .14, S * .52, S * .86), outline=c, width=lw)
            d.line((S * .40, S * .50, S * .90, S * .50), fill=c, width=lw)
            d.polygon([(S * .96, S * .50), (S * .74, S * .32), (S * .74, S * .68)], fill=c)
        elif name == "gear_small" or name == "info":
            d.ellipse((S * .08, S * .08, S * .92, S * .92), outline=c, width=lw)
            d.line((S * .5, S * .44, S * .5, S * .74), fill=c, width=lw)
            d.ellipse((S * .44, S * .22, S * .56, S * .34), fill=c)
        elif name == "calendar":
            d.rounded_rectangle((S * .12, S * .2, S * .88, S * .88), radius=S * .06, outline=c, width=lw)
            d.line((S * .12, S * .38, S * .88, S * .38), fill=c, width=lw)
            for x in (.32, .68):
                d.line((S * x, S * .1, S * x, S * .28), fill=c, width=lw)
        elif name == "source":
            for i, y in enumerate((.25, .5, .75)):
                d.ellipse((S * .18, S * (y - .1), S * .82, S * (y + .1)), outline=c, width=max(1, lw - 1))
        elif name == "check":
            d.ellipse((0, 0, S - 1, S - 1), fill=(40, 150, 70, 255), outline=(120, 230, 140, 255), width=lw)
            d.line((S * .26, S * .52, S * .44, S * .70, S * .76, S * .32), fill=(255, 255, 255, 255), width=int(lw * 1.4))
        elif name == "warn":
            d.ellipse((0, 0, S - 1, S - 1), fill=(170, 110, 20, 255), outline=GOLD_L + (255,), width=lw)
            d.line((S * .5, S * .22, S * .5, S * .6), fill=(255, 255, 255, 255), width=int(lw * 1.3))
            d.ellipse((S * .44, S * .7, S * .56, S * .82), fill=(255, 255, 255, 255))
        elif name == "error":
            d.ellipse((0, 0, S - 1, S - 1), fill=(170, 40, 40, 255), outline=(255, 140, 140, 255), width=lw)
            d.line((S * .32, S * .32, S * .68, S * .68), fill=(255, 255, 255, 255), width=int(lw * 1.3))
            d.line((S * .68, S * .32, S * .32, S * .68), fill=(255, 255, 255, 255), width=int(lw * 1.3))
    return shape_layer(s, s, draw)


# --- Symboles des HDV (originaux, pas de blason Blizzard) ---------------------
def emblem(key, size):
    s = size
    col = FAC[key]

    def draw(d, f):
        S = s * f
        g = GOLD + (255,)
        if key == "A":
            # Bouclier bleu à bord doré, étoile à quatre branches
            pts = [(S * .5, S * .04), (S * .9, S * .16), (S * .86, S * .56), (S * .5, S * .96), (S * .14, S * .56), (S * .1, S * .16)]
            d.polygon(pts, fill=g)
            inner = [(S * .5, S * .12), (S * .82, S * .22), (S * .78, S * .54), (S * .5, S * .86), (S * .22, S * .54), (S * .18, S * .22)]
            d.polygon(inner, fill=col + (255,))
            cx, cy, r = S * .5, S * .46, S * .2
            d.polygon([(cx, cy - r * 1.4), (cx + r * .35, cy - r * .35), (cx + r * 1.4, cy), (cx + r * .35, cy + r * .35),
                       (cx, cy + r * 1.4), (cx - r * .35, cy + r * .35), (cx - r * 1.4, cy), (cx - r * .35, cy - r * .35)], fill=g)
        elif key == "H":
            # Écu rouge à pointes, deux haches croisées (manches bruns, fers dorés en croissant)
            pts = [(S * .5, S * .02), (S * .66, S * .14), (S * .92, S * .1), (S * .86, S * .5), (S * .5, S * .98),
                   (S * .14, S * .5), (S * .08, S * .1), (S * .34, S * .14)]
            d.polygon(pts, fill=g)
            inner = [(S * .5, S * .1), (S * .64, S * .2), (S * .84, S * .18), (S * .79, S * .5), (S * .5, S * .88),
                     (S * .21, S * .5), (S * .16, S * .18), (S * .36, S * .2)]
            d.polygon(inner, fill=col + (255,))
            for sign in (1, -1):
                bx, by = S * (.5 - sign * .18), S * .76         # bas du manche
                tx, ty = S * (.5 + sign * .1), S * .3           # haut du manche
                d.line((bx, by, tx, ty), fill=(70, 44, 22, 255), width=int(S * .06))
                # fer de hache en croissant, tourné vers l'extérieur
                cx, cy, r = tx + sign * S * .01, ty + S * .02, S * .15
                box = (cx - r, cy - r, cx + r, cy + r)
                if sign == 1:
                    d.pieslice(box, -70, 70, fill=g)
                    d.pieslice((cx - r * .55, cy - r * .55, cx + r * .55, cy + r * .55), -70, 70, fill=col + (255,))
                else:
                    d.pieslice(box, 110, 250, fill=g)
                    d.pieslice((cx - r * .55, cy - r * .55, cx + r * .55, cy + r * .55), 110, 250, fill=col + (255,))
        else:
            # Pile de pièces d'or
            for i in range(4):
                y = S * (.66 - i * .14)
                d.ellipse((S * .16, y, S * .84, y + S * .2), fill=GOLD_D + (255,))
                d.ellipse((S * .16, y - S * .04, S * .84, y + S * .16), fill=g, outline=GOLD_D + (255,), width=max(1, int(S * .02)))
            d.ellipse((S * .5, S * .16, S * .96, S * .46), fill=(250, 220, 120, 255), outline=GOLD_D + (255,), width=max(1, int(S * .02)))
    lay = shape_layer(s, s, draw)
    shadow = Image.new("RGBA", (s, s), (0, 0, 0, 0))
    shadow.paste((0, 0, 0, 140), (0, 0), lay.getchannel("A"))
    out = Image.new("RGBA", (s, s), (0, 0, 0, 0))
    out.alpha_composite(shadow.filter(ImageFilter.GaussianBlur(max(1, s // 24))), (max(1, s // 30), max(1, s // 30)))
    out.alpha_composite(lay)
    return out


# -----------------------------------------------------------------------------
# Éléments graphiques fournis (assets) étirés sans déformer les ornements
# -----------------------------------------------------------------------------
def _cuts(total, fr):
    return [0] + [int(total * f) for f in fr] + [total]


def hslice(src, W, H, fr=(.12, .44, .56, .88), center=True):
    """Étire horizontalement une image (hauteur imposée) : bouts et centre
    gardés, parties 2 et 4 étirées. fr = coupes en fractions de la largeur.
    center=True : l'ornement central (partie 3) est placé exactement au milieu,
    même si les deux bouts n'ont pas la même largeur (cadre d'état)."""
    W, H = max(4, int(W)), max(4, int(H))
    s = H / src.height
    xs = _cuts(src.width, fr)
    parts = [(xs[i], xs[i + 1]) for i in range(5)]
    fixed = sum(int((b - a) * s) for i, (a, b) in enumerate(parts) if i in (0, 2, 4))
    if fixed >= W:
        return src.resize((W, H), Image.LANCZOS)
    stretch_src = sum(b - a for i, (a, b) in enumerate(parts) if i in (1, 3)) or 1
    rest = W - fixed
    fw = [int((b - a) * s) for (a, b) in parts]
    sw = [0, int(rest * (parts[1][1] - parts[1][0]) / stretch_src), 0, 0, 0]
    if center:
        sw[1] = int(round(W / 2 - fw[0] - (src.width / 2 - parts[2][0]) * s))
        if sw[1] < 0 or W - fw[0] - sw[1] - fw[2] - fw[4] < 0:
            sw[1] = int(rest * (parts[1][1] - parts[1][0]) / stretch_src)
    out = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    x = 0
    for i, (a, b) in enumerate(parts):
        w = fw[i] if i in (0, 2, 4) else (sw[1] if i == 1 else W - x - fw[4])
        if i == 4:
            w = W - x
        if w > 0 and b > a:
            out.alpha_composite(src.crop((a, 0, b, src.height)).resize((w, H), Image.LANCZOS), (x, 0))
        x += max(0, w)
    return out


def nslice(src, W, H, fx=(.1, .3, .7, .9), fy=(.16, .88), smax=0.45):
    """Étire dans les deux sens (cadre) : coins, ornement central du haut et
    du bas gardés ; bords et intérieur étirés."""
    W, H = max(8, int(W)), max(8, int(H))
    s = min(W / src.width, H / src.height, smax)
    xs, ys = _cuts(src.width, fx), [0] + [int(src.height * f) for f in fy] + [src.height]
    cols = [(xs[i], xs[i + 1]) for i in range(5)]
    rows = [(ys[i], ys[i + 1]) for i in range(3)]
    fixw = sum(int((b - a) * s) for i, (a, b) in enumerate(cols) if i in (0, 2, 4))
    fixh = int((rows[0][1] - rows[0][0]) * s) + int((rows[2][1] - rows[2][0]) * s)
    if fixw >= W or fixh >= H:
        return src.resize((W, H), Image.LANCZOS)
    sw = sum(b - a for i, (a, b) in enumerate(cols) if i in (1, 3)) or 1
    widths = []
    for i, (a, b) in enumerate(cols):
        widths.append(int((b - a) * s) if i in (0, 2, 4) else int((W - fixw) * (b - a) / sw))
    # Ornement central exactement au milieu (symétrie), quelles que soient les coupes.
    # (les ornements fournis sont au milieu de l'image source : on aligne ce point-là)
    c1 = int(round(W / 2 - widths[0] - (src.width / 2 - cols[2][0]) * s))
    if c1 > 0 and W - widths[0] - c1 - widths[2] - widths[4] > 0:
        widths[1] = c1
        widths[3] = W - widths[0] - c1 - widths[2] - widths[4]
    widths[4] = W - sum(widths[:4])
    heights = [int((rows[0][1] - rows[0][0]) * s), 0, int((rows[2][1] - rows[2][0]) * s)]
    heights[1] = H - heights[0] - heights[2]
    out = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    y = 0
    for j, (ya, yb) in enumerate(rows):
        x = 0
        for i, (xa, xb) in enumerate(cols):
            if widths[i] > 0 and heights[j] > 0:
                out.alpha_composite(src.crop((xa, ya, xb, yb)).resize((widths[i], heights[j]), Image.LANCZOS), (x, y))
            x += widths[i]
        y += heights[j]
    return out


def gold_version(src):
    """Version dorée d'un cadre bleu (bouton principal) : les zones bleues
    deviennent or, les ornements dorés restent."""
    r, g, b, a = src.split()
    import PIL.ImageChops as C
    blue = C.subtract(b, r).point(lambda v: 255 if v > 25 else 0).filter(ImageFilter.GaussianBlur(1))
    v = Image.merge("RGB", (r, g, b)).convert("L").point(lambda x: min(255, int(x * 3.0 + 105)))
    gold = Image.merge("RGB", (v.point(lambda x: min(255, int(x * 1.04))), v.point(lambda x: int(x * .76)),
                               v.point(lambda x: int(x * .24))))
    out = Image.composite(gold, src.convert("RGB"), blue)
    out.putalpha(a)
    return out


def asset_button(w, h, kind="blue", state="normal"):
    """Bouton à partir du cadre fourni (repli : bouton dessiné)."""
    src = load("cadre_bouton.png")
    if src is None:
        return button(w, h, h / 56.0, kind, state)
    key = "_gold_btn"
    if kind == "gold":
        if key not in _cache:
            _cache[key] = gold_version(src)
        src = _cache[key]
    img = hslice(src, w, h)
    if state == "hover":
        from PIL import ImageEnhance
        a = img.getchannel("A")
        img = ImageEnhance.Brightness(img.convert("RGB")).enhance(1.18).convert("RGBA")
        img.putalpha(a)
    elif state == "disabled":
        grey = img.convert("LA").convert("RGBA")
        grey.putalpha(img.getchannel("A").point(lambda v: int(v * 0.5)))
        img = grey
    return img


def corners(img, k, width=250):
    """Ornements d'angle fournis, aux quatre coins (miroirs)."""
    src = load("ornement_coin.png")
    if src is None:
        return False
    w = int(width * k)
    h = int(src.height * w / src.width)
    tl = src.resize((w, h), Image.LANCZOS)
    W, H = img.size
    m = int(4 * k)
    img.alpha_composite(tl, (m, m))
    img.alpha_composite(tl.transpose(Image.FLIP_LEFT_RIGHT), (W - w - m, m))
    img.alpha_composite(tl.transpose(Image.FLIP_TOP_BOTTOM), (m, H - h - m))
    img.alpha_composite(tl.transpose(Image.ROTATE_180), (W - w - m, H - h - m))
    return True


def fit(src, box_w, box_h):
    """Redimensionne en gardant les proportions pour tenir dans la boîte."""
    if src is None:
        return None
    s = min(box_w / src.width, box_h / src.height)
    return src.resize((max(1, int(src.width * s)), max(1, int(src.height * s))), Image.LANCZOS)


# -----------------------------------------------------------------------------
# Fond complet / full background
# -----------------------------------------------------------------------------
def background(w, h, k, glow_center=None):
    fond = load("fond.jpg") or load("fond.png")
    if fond:
        # Image de décor fournie : remplit la fenêtre, assombrie pour la lisibilité
        scale = max(w / fond.width, h / fond.height)
        img = fond.resize((int(fond.width * scale) + 1, int(fond.height * scale) + 1), Image.LANCZOS)
        img = img.crop(((img.width - w) // 2, (img.height - h) // 2, (img.width - w) // 2 + w, (img.height - h) // 2 + h))
        img.alpha_composite(Image.new("RGBA", (w, h), NAVY + (120,)))
    else:
        img = vgradient(w, h, (10, 17, 33), (20, 36, 68))
        img.alpha_composite(radial(w, h, int(w * .78), int(h * .22), int(min(w, h) * .45), (60, 100, 170), 70))
    if glow_center:
        cx, cy = glow_center
        img.alpha_composite(radial(w, h, cx, cy, int(170 * k), GOLD, 70))
        rays = Image.new("RGBA", (w, h), (0, 0, 0, 0))
        d = ImageDraw.Draw(rays)
        for i in range(18):
            a = i * math.pi * 2 / 18 + 0.1
            d.line((cx, cy, cx + math.cos(a) * 420 * k, cy + math.sin(a) * 420 * k), fill=GOLD + (16,), width=max(1, int(6 * k)))
        img.alpha_composite(rays.filter(ImageFilter.GaussianBlur(3 * k)))
    # Vignette
    vig = Image.new("L", (w, h), 0)
    ImageDraw.Draw(vig).rectangle((0, 0, w, h), outline=255, width=int(min(w, h) * .08))
    vig = vig.filter(ImageFilter.GaussianBlur(min(w, h) * .06))
    img.alpha_composite(Image.merge("RGBA", (vig.point(lambda v: 0),) * 3 + (vig.point(lambda v: int(v * .55)),)))
    return img


def frame(img, k, ornate=True):
    """Cadre doré double ; ornements d'angle fournis s'ils existent, sinon dessinés."""
    w, h = img.size
    m = int(10 * k)

    def draw(d, f):
        g, gd = GOLD + (255,), GOLD_D + (255,)
        d.rectangle((m * f, m * f, (w - m) * f, (h - m) * f), outline=gd, width=int(3 * k * f))
        d.rectangle(((m + 6 * k) * f, (m + 6 * k) * f, (w - m - 6 * k) * f, (h - m - 6 * k) * f), outline=g, width=max(1, int(1.2 * k * f)))
        if not have_corners:
            for (cx, cy) in ((m, m), (w - m, m), (m, h - m), (w - m, h - m)):
                diamond(d, cx * f, cy * f, 16 * k * f, g, gd)
                diamond(d, cx * f, cy * f, 7 * k * f, gd)
    have_corners = ornate and load("ornement_coin.png") is not None
    img.alpha_composite(shape_layer(w, h, draw))
    if have_corners:
        corners(img, k)


def place(img, src, x, y, height=None, width=None, shadow=False):
    """Colle une image redimensionnée (hauteur ou largeur imposée) en (x, y)."""
    if src is None:
        return None
    if height:
        width = int(src.width * height / src.height)
    elif width:
        height = int(src.height * width / src.width)
    im = src.resize((max(1, int(width)), max(1, int(height))), Image.LANCZOS)
    if shadow:
        sh = Image.new("RGBA", im.size, (0, 0, 0, 0))
        sh.paste((0, 0, 0, 150), (0, 0), im.getchannel("A"))
        img.alpha_composite(sh.filter(ImageFilter.GaussianBlur(8)), (int(x) + 6, int(y) + 6))
    img.alpha_composite(im, (int(x), int(y)))
    return im.size
