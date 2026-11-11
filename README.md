# monRéZO — prototype d'application voyageurs

Prototype Flutter (Android + web) sur les horaires réels du réseau monRéZO, données ouvertes de la CUCM.
Tout est embarqué : l'application fonctionne sans réseau, et ne demande même pas la permission Internet
— Android lui interdit donc d'envoyer quoi que ce soit.

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

## Format des informations trafic

`assets/data/alerts.json` contient aujourd'hui des **exemples**, écrits pour la maquette. Le format
est prévu pour qu'un back-office de l'exploitant le produise tel quel :

```json
{
  "_note": "...",
  "alerts": [
    {
      "id": "a-schneider-2026-11",
      "severity": "severe",          // info | warning | severe
      "lines": ["C1", "C2"],         // noms publics des lignes ; [] = tout le réseau
      "title": "Place Schneider non desservie",
      "body": "Texte complet affiché au détail.",
      "from": "2026-11-02",          // null = depuis toujours
      "to": "2026-11-14",            // null = sans fin annoncée ; jour inclus
      "updated": "2026-11-05T17:40",
      "example": true                // true = donnée simulée, étiquetée à l'écran
    }
  ]
}
```

Trois décisions qui tiendront quand les données deviendront réelles :

- **Les lignes sont désignées par leur nom public** (`M2`), jamais par l'identifiant interne du GTFS
  (`R5`) : cet identifiant est un compteur attribué à la conversion, il se décale dès qu'une ligne
  est ajoutée. Un flux écrit par un exploitant doit survivre à une régénération des données.
- **`example` est l'interrupteur.** Tant qu'il vaut `true`, l'écran affiche un bandeau de
  démonstration et une étiquette « exemple » sur chaque carte — le bandeau seul ne suffit pas, c'est
  une carte isolée qui circulera en capture d'écran. Le jour où un back-office publie de vraies
  alertes, l'étiquette disparaît sans toucher au code. Une alerte sans le champ est traitée comme un
  exemple : on préfère étiqueter à tort que présenter un exemple comme vrai.
- **Un flux abîmé ne vide pas l'écran** : une entrée illisible est ignorée, une gravité inconnue
  devient une simple information, une date illisible est oubliée. Seul un fichier sans champ
  `alerts` est une erreur — et elle s'affiche, avec un bouton « Réessayer ».

Les perturbations terminées disparaissent d'elles-mêmes : le filtrage se fait à l'affichage, sur la
date du téléphone.

## Titres de transport : prix réels, achat simulé

`assets/data/fares.json` contient les **tarifs publics du réseau**, relevés le 06/11/2026 sur
<https://www.monrezo.org/tarifs> : ticket unitaire 1,20 €, titre 10 voyages 9 €, ticket journée
3,60 €. Le fichier porte sa source et la date du relevé, et l'écran les affiche sous la grille :
un prix sans provenance ne vaut rien dans un dossier.

L'achat, lui, est une **démonstration** :

- aucun paiement n'est effectué et **aucun champ de saisie n'existe dans tout le parcours** — pas de
  formulaire de carte bancaire, même factice. Une maquette ne doit pas entraîner les gens à taper un
  numéro de carte dans une application d'essai. Un test le vérifie écran par écran ;
- le QR est **dessiné**, déterministe à partir de l'identifiant du titre, avec « DÉMONSTRATION » en
  travers. Un vrai encodeur demanderait une dépendance que le brief n'autorise pas, et un faux QR
  crédible serait pire qu'un faux QR assumé ;
- `Ticket.bought` est le seul constructeur d'achat, et il marque le titre (`demo: true`). Rien dans
  le code ne sait produire un titre non étiqueté ;
- les titres sont rangés sur le téléphone (`shared_preferences`), jamais envoyés nulle part, et un
  bouton les efface.

Le catalogue affiche aussi, en clair, **comment le titre se vend réellement aujourd'hui** (« vendu
auprès du conducteur », « à charger sur une carte sans contact ») : c'est précisément ce que la
vente en ligne changerait.

Cycle de vie d'un titre (`lib/data/tickets.dart`, testé dans `test/tickets_test.dart`) : acheté →
validé → correspondance de 60 minutes → voyage suivant, jusqu'à épuisement ; un titre journée vaut
jusqu'à minuit et ne se valide qu'une fois. Revalider pendant une correspondance ne consomme pas de
voyage.

## Plan du réseau : tracé depuis les données, pas copié

Le plan publié par l'exploitant est son travail et son identité visuelle : il n'est pas repris.
Le plan de l'application est **dessiné depuis le GTFS** (`NetworkMap` dans `lib/main.dart`) :
coordonnées des 167 arrêts, ordre de passage des 29 parcours, couleurs des lignes. Projection
équirectangulaire corrigée par la latitude, suffisante pour 30 km de côté.

C'est un **schéma d'arrêt à arrêt** : les segments sont droits là où le bus suit les rues, et
l'écran le dit. Le GTFS contient la géométrie réelle (`shapes.txt`) ; la reprendre alourdirait le
fichier embarqué d'environ 300 Ko, ce qui n'est pas justifié tant que le plan sert à se repérer.

Toucher un badge isole une ligne (les autres passent en gris), `InteractiveViewer` donne le zoom et
le déplacement sans aucune dépendance.

## Informations pratiques

`assets/data/places.json` : boutiques, transport à la demande, liens officiels. Ce sont de **vraies
adresses et de vrais numéros**, relevés le 06/11/2026 sur <https://www.monrezo.org/nous-contacter/>
et <https://www.monrezo.org/monrezo-tad/>. Le fichier porte sa source et sa date, l'écran les
affiche : ce sont les seules informations de l'application avec lesquelles quelqu'un va **agir**
— composer un numéro, se déplacer jusqu'à un guichet — et elles doivent être revérifiées avant
toute diffusion.

Un lien dont l'URL n'est pas en `http(s)` est refusé à la lecture : un libellé rassurant ne doit pas
pouvoir faire ouvrir autre chose qu'une page web.

### La dépendance `url_launcher`

C'est la première dépendance ajoutée au-delà de `geolocator` et `shared_preferences`, et le brief
impose de la justifier. L'écran porte le numéro du transport à la demande et ceux des deux
boutiques : recopier un numéro à la main, debout à un arrêt, n'est pas une option — encore moins
pour le public visé. `url_launcher` est le seul moyen de composer un numéro et d'ouvrir un lien
depuis Flutter. Repli prévu : si rien ne s'ouvre, le numéro part dans le presse-papiers et reste
lisible en grand à l'écran. Les tests injectent l'ouverture et vérifient **ce qui serait composé**
(`tel:+33385730110`) sans rien ouvrir.

## Écran d'accueil : position et horaires prévus

La position sert **uniquement** à trier les arrêts embarqués par distance. Elle n'est enregistrée
nulle part, n'est envoyée nulle part, et n'est **jamais demandée toute seule** : l'usager appuie sur
« Arrêts près de moi », et la raison est écrite à côté du bouton. Une demande de localisation qui
surgit au lancement se fait refuser, et un refus définitif ne se rattrape que dans les réglages du
téléphone.

La géolocalisation a six états, pas deux — inactive, en recherche, accordée, refusée, refusée
définitivement, service coupé — et chacun doit dire à l'usager **ce qu'il peut faire ensuite**.
Ils sont isolés dans `lib/data/location.dart` derrière une fonction injectable
(`LocationProbe`), ce qui permet de tous les passer en test, y compris ceux qu'on ne peut pas
provoquer à la main. Les permissions Android sont déclarées dans `android/app/src/main/AndroidManifest.xml`.

Un arrêt déjà en favori n'est pas reproposé dans « Autour de vous » : il est affiché juste au-dessus.

Chaque carte d'arrêt porte le badge **« horaires prévus »**, et non une seule mention en bas de
page : un horaire théorique présenté sans réserve se lit comme un temps réel, et il n'y a aucun
temps réel sur ce réseau.

### Les jours où le réseau ne circule pas

Le réseau ne roule **ni le dimanche ni les jours fériés** : sur les données du 06/11/2026, le
11 novembre et tous les dimanches n'ont aucun service. L'écran affichait alors, sur chaque arrêt,
« Pas de passage prévu dans les 3 prochaines heures » — exact à la lettre, et illisible : on
comprend que l'application n'a pas de données, pas qu'il n'y a pas de bus.

L'accueil dit maintenant « Le réseau ne circule pas aujourd'hui, mercredi 11 novembre. Reprise
jeudi 12 novembre » et montre les **premiers départs de ce jour-là** à chaque arrêt. Le calcul est
dans `lib/data/schedule.dart` (`runsOn`, `nextServiceDay`, `firstDeparturesOfDay`), pas dans l'écran.

Si aucun service n'est trouvé dans les quinze jours, le message change : ce ne sont plus des
congés, ce sont les données qui ont expiré, et c'est ce que le bandeau annonce. Les deux cas ne se
disent pas de la même façon, et aucun des deux ne se dit en laissant l'écran vide.

Le titre de l'écran est « Prochains passages » et non le nom du réseau : le GTFS donne « CUCM »,
l'acronyme de la collectivité, qui ne dit rien à un usager. Le nom venu des données reste affiché
dans *Plan et infos*, avec la provenance des horaires.

## Installer et déployer

### Web

```powershell
flutter build web --release --base-href /monrezo-mvp/
```

`--base-href` doit valoir le chemin sous lequel le site est servi : GitHub Pages publie dans un
sous-dossier qui porte le nom du dépôt. Le résultat est dans `build/web`, entièrement statique.

Pour vérifier avant publication, servir le dossier **sous ce chemin** et non à la racine :

```powershell
mkdir pages\monrezo-mvp; Copy-Item -Recurse build\web\* pages\monrezo-mvp; python -m http.server 8090 --directory pages
```

Publication automatique : `.github/workflows/web.yml` construit et publie sur GitHub Pages à
chaque poussée sur la branche principale, après `flutter analyze` et `flutter test` — rien ne se
publie si les tests échouent. Une seule chose à faire dans le dépôt : **Settings → Pages →
Source = GitHub Actions**. Aucun secret n'est nécessaire.

> **Publier rend le prototype public.** Les alertes trafic sont des exemples et l'achat est une
> démonstration, mais une page publique peut être trouvée, citée et archivée. À décider avant,
> pas après.

Deux choses à savoir sur la version web :

- le premier chargement transfère environ **3,7 Mo** : le moteur de rendu de Flutter
  (`canvaskit.wasm`, 2,9 Mo compressé) et le code de l'application (`main.dart.js`, 0,8 Mo). Les
  chargements suivants sont servis par le cache. Sur un téléphone en 4G, le premier affichage
  prend quelques secondes. À ne pas confondre avec les ~31 Mo du dossier `build/web` sur le
  disque : c'est la taille non compressée, pas ce qui passe sur le réseau ;
- le fonctionnement hors ligne y dépend du *service worker*, donc d'un premier chargement réussi.
  Sur Android, l'APK est hors ligne dès l'installation : tout est embarqué.

### Android (APK)

```powershell
$env:JAVA_HOME = "<un JDK 21 complet>"
$env:GRADLE_OPTS = "-Djavax.net.ssl.trustStoreType=Windows-ROOT"
flutter build apk --release
# => build\app\outputs\flutter-apk\app-release.apk (46,2 Mo)
```

**Produit et vérifié.** L'APK s'installe par simple lien : le téléphone demandera d'autoriser
l'installation depuis une source inconnue, c'est normal pour une application hors magasin.
Identifiant `fr.pluriface.bus_prototype`, nom affiché « Bus — prototype », Android 7 et plus
(`minSdk` 24), trois architectures dans le même fichier (`arm64-v8a`, `armeabi-v7a`, `x86_64`) :
un seul lien marche sur n'importe quel téléphone. C'est ce qui explique les 46,2 Mo.

Si le poids gêne (envoi par messagerie, téléphone en 4G), `--split-per-abi` découpe par
architecture :

```powershell
flutter build apk --release --split-per-abi
# app-arm64-v8a-release.apk    16,5 Mo  <- tous les téléphones depuis ~2015
# app-armeabi-v7a-release.apk  14,1 Mo  <- vieux téléphones 32 bits
# app-x86_64-release.apk       17,8 Mo  <- émulateurs, quelques tablettes
```

C'est l'arm64 qu'il faut envoyer dans la quasi-totalité des cas. Attention si l'on publie un jour :
Flutter décale le `versionCode` de ces variantes (2001 pour arm64 contre 1 pour l'APK universel),
pour que le magasin serve la bonne à chaque appareil.

Il est signé avec la clé de débogage par défaut de Flutter (`CN=Android Debug`, schéma v2) —
suffisant pour faire essayer un prototype, **à remplacer par une vraie clé** avant toute diffusion
large (`android/app/build.gradle.kts`, bloc `signingConfigs`). Une clé différente oblige à
désinstaller avant de réinstaller.

#### Ce que l'application demande au téléphone

Le manifeste compilé ne contient que deux permissions, et **pas `android.permission.INTERNET`** :

```powershell
aapt2 dump permissions build\app\outputs\flutter-apk\app-release.apk
# uses-permission: android.permission.ACCESS_COARSE_LOCATION
# uses-permission: android.permission.ACCESS_FINE_LOCATION
```

Sans cette permission, Android **empêche** l'application d'ouvrir une connexion réseau. « Aucune
donnée envoyée nulle part » n'est donc pas une promesse à croire : c'est le système qui
l'applique, et n'importe qui peut le vérifier sur l'APK en une commande. Les liens vers
monrezo.org et les numéros de téléphone passent par une autre application (navigateur,
téléphone), ce qui ne requiert rien. À garder en tête : le jour où l'on branche un vrai temps
réel, cette ligne devra être ajoutée, et cet argument tombera.

La position, elle, est déclarée dans `android/app/src/main/AndroidManifest.xml`
(`ACCESS_COARSE_LOCATION`, `ACCESS_FINE_LOCATION`) et n'est demandée qu'au moment où l'usager
touche « Arrêts près de moi ».

#### Les deux réglages de la ligne de commande ci-dessus

Ils ne sont pas décoratifs : sans eux, le build échoue sur ce poste, et probablement sur un autre
poste d'entreprise.

1. **Il faut un JDK 21 *complet*.** Le Java fourni avec IntelliJ ne suffit pas : il a `javac` mais
   **pas `jlink`**, dont le greffon Gradle d'Android a besoin pour construire l'image de modules
   système (`jlink executable ... does not exist`). Installer Temurin 21 :
   `winget install EclipseAdoptium.Temurin.21.JDK`. Sans droits administrateur, le même paquet
   s'extrait à côté, sans rien écrire dans le registre :
   `msiexec /a <le .msi> TARGETDIR=C:\chemin\jdk21 /qn` — `JAVA_HOME` pointe alors sur
   `<…>\PFiles64\Eclipse Adoptium\jdk-21…-hotspot`. C'est ce qui a été fait ici.
2. **Gradle n'arrive pas à télécharger ses dépendances** : `PKIX path building failed` sur
   `dl.google.com`. Le trafic HTTPS est inspecté par un antivirus ou un proxy dont l'autorité de
   certification n'est pas connue de Java. `-Djavax.net.ssl.trustStoreType=Windows-ROOT` fait
   confiance au magasin de certificats de Windows, celui que le navigateur utilise déjà — rien
   n'est installé ni modifié.

Installer Android Studio règle les deux d'un coup, en plus lourd, et fait taire le
`cmdline-tools component is missing` que signale `flutter doctor` (sans conséquence pour la
compilation : c'est l'outil qui sert à installer des composants du SDK).

## Quand la CUCM publie un nouveau GTFS

Refaire l'étape 2, vérifier le résumé imprimé (8 lignes, période de validité), lancer `flutter test`,
committer `assets/data/network.json`.
