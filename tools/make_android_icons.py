# -*- coding: utf-8 -*-
"""Icone de lancement Android, fabriquee depuis la marque du studio.

    python tools/make_android_icons.py

Android a deux systemes d'icones, et le gabarit Flutter n'en fournit qu'un.

  - Jusqu'a Android 7 (notre minSdk est 24), le lanceur affiche le PNG tel quel :
    c'est a l'icone de porter sa propre forme, d'ou le carre arrondi.
  - Depuis Android 8, le lanceur compose lui-meme : il superpose un fond et un
    avant-plan, puis decoupe l'ensemble dans la forme choisie par le
    constructeur — cercle, carre arrondi, goutte. Chaque couche mesure 108 dp
    mais seuls les 72 dp centraux sont surs ; le reste sert au decoupage et aux
    effets de parallaxe. Une marque dessinee jusqu'au bord y perd ses extremites.

Le fond est blanc, comme les icones web : le marine de la marque se fondrait
dans un fond d'ecran sombre, et la marque elle-meme n'y serait plus lisible.
"""
import os

from PIL import Image, ImageDraw

RACINE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SOURCE = os.path.join(RACINE, "tools", "logo-pluriface.png")
RES = os.path.join(RACINE, "android", "app", "src", "main", "res")

FOND = (255, 255, 255)
TUILE = 4  # on dessine a 4x puis on reduit : les traits fins restent nets

# Densites Android : le facteur par rapport a mdpi (1 dp = 1 px en mdpi).
DENSITES = [("mdpi", 1.0), ("hdpi", 1.5), ("xhdpi", 2.0),
            ("xxhdpi", 3.0), ("xxxhdpi", 4.0)]

LEGACY_DP = 48   # taille historique d'une icone de lanceur
ADAPTIVE_DP = 108  # taille d'une couche d'icone adaptative


def marque():
    im = Image.open(SOURCE).convert("RGBA")
    px = im.load()
    for y in range(im.height):
        for x in range(im.width):
            r, g, b, a = px[x, y]
            if r > 248 and g > 248 and b > 248:
                px[x, y] = (r, g, b, 0)
    return im.crop(im.getbbox())


def pose(taille, part, rayon_relatif, fond_plein):
    grand = taille * TUILE
    toile = Image.new("RGBA", (grand, grand), (0, 0, 0, 0))

    if fond_plein:
        masque = Image.new("L", (grand, grand), 0)
        ImageDraw.Draw(masque).rounded_rectangle(
            [0, 0, grand - 1, grand - 1], radius=int(grand * rayon_relatif), fill=255)
        toile.paste(Image.new("RGBA", (grand, grand), FOND + (255,)), (0, 0), masque)

    m = marque()
    cible = int(grand * part)
    ratio = cible / float(max(m.size))
    m = m.resize((max(1, int(m.width * ratio)), max(1, int(m.height * ratio))), Image.LANCZOS)
    toile.paste(m, ((grand - m.width) // 2, (grand - m.height) // 2), m)
    return toile.resize((taille, taille), Image.LANCZOS)


def ecrire(img, dossier, nom):
    d = os.path.join(RES, dossier)
    if not os.path.isdir(d):
        os.makedirs(d)
    chemin = os.path.join(d, nom)
    img.save(chemin)
    print("  %-46s %dx%d" % (os.path.relpath(chemin, RACINE), img.size[0], img.size[1]))


print("Icones Android depuis", os.path.relpath(SOURCE, RACINE))

for nom, k in DENSITES:
    # Heritee : elle porte sa propre forme, donc fond et coins arrondis.
    ecrire(pose(int(LEGACY_DP * k), 0.70, 0.22, True), "mipmap-" + nom, "ic_launcher.png")
    # Avant-plan adaptatif : fond transparent (le fond est une couche a part) et
    # marque a 44 % du cote, soit 48 dp sur les 72 dp surs. Elle survit au
    # decoupage en cercle comme au decoupage en goutte.
    ecrire(pose(int(ADAPTIVE_DP * k), 0.44, 0.0, False),
           "mipmap-" + nom, "ic_launcher_foreground.png")

XML_ICONE = """<?xml version="1.0" encoding="utf-8"?>
<!-- Android 8 et plus compose l'icone : un fond, un avant-plan, et le lanceur
     decoupe l'ensemble dans la forme du constructeur. -->
<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">
    <background android:drawable="@color/ic_launcher_background" />
    <foreground android:drawable="@mipmap/ic_launcher_foreground" />
</adaptive-icon>
"""

XML_COULEUR = """<?xml version="1.0" encoding="utf-8"?>
<resources>
    <!-- Blanc, comme les icones web : le marine de la marque disparaîtrait sur un
         fond d'écran sombre, et la marque elle-même n'y serait plus lisible. -->
    <color name="ic_launcher_background">#FFFFFF</color>
</resources>
"""

for dossier, nom, contenu in [
    ("mipmap-anydpi-v26", "ic_launcher.xml", XML_ICONE),
    ("values", "ic_launcher_background.xml", XML_COULEUR),
]:
    d = os.path.join(RES, dossier)
    if not os.path.isdir(d):
        os.makedirs(d)
    chemin = os.path.join(d, nom)
    with open(chemin, "w", encoding="utf-8", newline="\n") as f:
        f.write(contenu)
    print("  %-46s" % os.path.relpath(chemin, RACINE))
