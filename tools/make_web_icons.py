# -*- coding: utf-8 -*-
"""Icones web et favicon, fabriquees depuis la marque du studio.

Le gabarit Flutter livre son propre logo : il annonce l'outil, pas l'auteur, et
dans un onglet de navigateur il se lit comme « projet de demonstration ».

    python tools/make_web_icons.py

Remplace web/favicon.png et les quatre fichiers de web/icons/.

Deux familles d'icones, et elles ne se dessinent pas pareil :
  - les icones ordinaires sont affichees telles quelles : coins arrondis, la
    marque occupe largement la surface ;
  - les icones « maskable » sont recadrees par le systeme, parfois en cercle.
    Tout ce qui sort du cercle central de 80 % peut disparaitre, donc la marque
    y est plus petite et le fond va jusqu'au bord.
"""
import os

from PIL import Image, ImageDraw

RACINE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SOURCE = os.path.join(RACINE, "tools", "logo-pluriface.png")
WEB = os.path.join(RACINE, "web")

FOND = (255, 255, 255)
# Un fond blanc, et non le marine de l'application : dans la barre d'onglets
# sombre d'un navigateur, un carre marine se fond dans le decor, alors qu'un
# carre blanc se detache. Sur une barre claire, c'est la marque elle-meme,
# marine, qui porte le contraste.

TUILE = 4  # on dessine a 4x puis on reduit : les traits fins restent nets


def marque():
    im = Image.open(SOURCE).convert("RGBA")
    # Le fichier est sur fond blanc opaque : on le rend transparent pour pouvoir
    # le poser sur n'importe quel fond sans trainee de bord.
    px = im.load()
    for y in range(im.height):
        for x in range(im.width):
            r, g, b, a = px[x, y]
            if r > 248 and g > 248 and b > 248:
                px[x, y] = (r, g, b, 0)
    return im.crop(im.getbbox())


def icone(taille, part, rayon_relatif):
    """part : fraction du cote occupee par la plus grande dimension de la marque."""
    grand = taille * TUILE
    toile = Image.new("RGBA", (grand, grand), (0, 0, 0, 0))

    masque = Image.new("L", (grand, grand), 0)
    ImageDraw.Draw(masque).rounded_rectangle(
        [0, 0, grand - 1, grand - 1], radius=int(grand * rayon_relatif), fill=255)
    fond = Image.new("RGBA", (grand, grand), FOND + (255,))
    toile.paste(fond, (0, 0), masque)

    m = marque()
    cible = int(grand * part)
    ratio = cible / float(max(m.size))
    m = m.resize((max(1, int(m.width * ratio)), max(1, int(m.height * ratio))),
                 Image.LANCZOS)
    toile.paste(m, ((grand - m.width) // 2, (grand - m.height) // 2), m)

    return toile.resize((taille, taille), Image.LANCZOS)


def ecrire(img, chemin, avec_alpha):
    if not avec_alpha:
        plat = Image.new("RGB", img.size, FOND)
        plat.paste(img, (0, 0), img)
        img = plat
    img.save(chemin)
    print("  %-34s %dx%d" % (os.path.relpath(chemin, RACINE), img.size[0], img.size[1]))


print("Icones fabriquees depuis", os.path.relpath(SOURCE, RACINE))
# Le favicon garde un fond transparent hors du carre arrondi : certains
# navigateurs le posent sur une barre sombre.
# 0,82 : a 16 px dans un onglet, chaque pixel de marge perdue compte.
ecrire(icone(64, 0.82, 0.22), os.path.join(WEB, "favicon.png"), True)
for t in (192, 512):
    ecrire(icone(t, 0.72, 0.20), os.path.join(WEB, "icons", "Icon-%d.png" % t), False)
    # 0,52 : la marque tient dans le cercle de securite, quoi que le systeme decoupe.
    ecrire(icone(t, 0.52, 0.0), os.path.join(WEB, "icons", "Icon-maskable-%d.png" % t), False)
