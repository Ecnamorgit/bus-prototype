# monRéZO — prototype d'application voyageurs

Prototype Flutter (Android + web) sur les horaires réels du réseau monRéZO, données ouvertes de la CUCM.
Le brief complet et les règles de travail sont dans `CLAUDE.md` ; le dossier d'argumentation dans `docs/`.

## Démarrer

```powershell
# 1. Récupérer le GTFS (bouton Télécharger sur la fiche transport.data.gouv.fr) et le déposer ici :
#    data/gtfs/monrezo.zip
# 2. Générer les données embarquées
python tools/gtfs_to_json.py data/gtfs/monrezo.zip assets/data/network.json
# 3. Lancer
flutter create --platforms android,web .
flutter pub get
flutter test
flutter run -d chrome        # ou -d <appareil Android>
```

## Données embarquées actuellement

`assets/data/network.json` est généré depuis le GTFS réel du réseau :

| | |
|---|---|
| Fiche | https://transport.data.gouv.fr/datasets/arrets-horaires-et-parcours-theoriques-du-reseau-monrezo-cucm-gtfs-1 |
| Ressource | `gtfs-20260928-101048-open-data-cmt.zip` (319 Ko), publiée le 02/10/2026 |
| Lien direct | https://www.data.gouv.fr/api/1/datasets/r/128b06bc-f263-4530-8e03-395402f87256 |
| Téléchargé le | 06/11/2026 |
| Contenu | 8 lignes (C1 C2 C3 M1 M2 M3 M4 TGV), 167 arrêts, 29 motifs, 456 courses, 12 services |
| Validité | 28/09/2026 → 27/09/2027 |

Le zip brut n'est pas committé (`.gitignore`) : seul le JSON généré l'est.

### Un arrêt = un lieu, pas un quai

Le GTFS décrit 311 points d'arrêt : les deux quais d'un même arrêt y sont deux entrées de même nom,
distantes de quelques dizaines de mètres. Affichés tels quels, ils donnent deux lignes identiques dans
la recherche. Le convertisseur les fusionne (`MERGE_RADIUS_M = 300` dans `tools/gtfs_to_json.py`) :
même `parent_station`, ou même nom (accents et casse ignorés) à 300 m ou moins, position = barycentre
des quais. Résultat : 167 lieux. Les arrêts homonymes réellement distincts restent séparés — CENTRE
COMMERCIAL existe à Blanzy et au Creusot, à 15,7 km.

Conséquence à connaître : certaines lignes desservent deux fois le même lieu dans une course (la navette
TGV boucle par CORIOLIS). Le moteur d'horaires liste tous les passages, pas seulement le premier
(cas couvert par le groupe de tests « motif en boucle »).

### Les identifiants d'arrêt doivent rester stables

Les favoris sont enregistrés sur le téléphone sous l'identifiant de l'arrêt. Un identifiant attribué
par un compteur dans l'ordre du fichier ne tient pas : un arrêt ajouté décale toute la suite, et le
favori de l'usager désigne alors un autre arrêt — un écran faux, pas un écran vide.

L'identifiant vient donc du `stop_code` de l'exploitant, sans son numéro de quai : `BLBSA1` et
`BLBSA2` (les deux quais de BOIS DE SAVIGNY à Blanzy) donnent l'arrêt `BLBSA`. Le préfixe de commune
distingue au passage les homonymes : `BRCCO` et `MOCCO` pour les deux CENTRE COMMERCIAL. Quand deux
lieux distincts partagent un code (GARE TGV ARRIVEE et DEPART), le code de quai complet les départage
(`MCTGV1`, `MCTGV2`). Sans `stop_code`, le script retombe sur une empreinte du nom et du `stop_id`.

Un favori enregistré sous un ancien identifiant ne correspond plus à rien : l'application l'ignore
(elle n'affiche jamais un autre arrêt à la place).

### Une ligne a plusieurs parcours par sens

Le GTFS décrit 29 motifs pour 8 lignes : chaque sens a sa variante principale et des variantes
marginales (un détour, un service partiel, parfois une autre destination). La navette TGV en a
trois dans le même sens, de 2 à 30 courses par jour. L'écran Lignes en tient compte :

- le sens est nommé par la variante qui porte le plus de courses (`Network.mainPatternOfDirection`),
  pas par la plus longue — la plus longue, sur la navette TGV, circule deux fois par jour ;
- la liste d'arrêts fusionne les variantes (`Network.directionStops`) : les 22 arrêts du réseau
  desservis par une seule variante (PROMENADE DU MIDI sur C1) sont affichés et marqués
  « Certains bus seulement » ;
- la grille horaire d'un arrêt réunit toutes les variantes du sens (`Schedule.directionTimetable`)
  et porte la destination de chaque course : à CORIOLIS, 32 passages vers trois destinations là où
  une seule variante en montrerait 13.

### Contraste des badges de ligne

Les couleurs de texte déclarées dans le GTFS échouent le contraste AA sur 5 lignes sur 8 (C3 :
blanc sur cyan, 2,37 pour 4,5 exigés). `_readableOn` garde la couleur de l'exploitant et choisit
le noir ou le blanc. Le jalon vertical de l'écran Lignes reprend la couleur de la ligne, assombrie
quand elle disparaît sur fond blanc (le jaune de la navette TGV).

### Tests du convertisseur

```powershell
python tools/test_gtfs_to_json.py
```

Sans dépendance, sur un GTFS fabriqué en mémoire (le vrai zip n'est pas committé). Ils vérifient la
fusion des quais, la séparation des homonymes lointains, et la stabilité des identifiants quand le
GTFS est remanié.

## Quand la CUCM publie un nouveau GTFS

Refaire l'étape 2, vérifier le résumé imprimé (8 lignes, période de validité), lancer `flutter test`,
committer `assets/data/network.json`.
