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

Tant que `assets/data/network.json` est le jeu fictif livré avec le dépôt, l'appli affiche « Réseau de
démonstration » avec une ligne M1 et trois arrêts : c'est normal, c'est pour que ça compile et tourne avant
d'avoir le vrai fichier.

## Quand la CUCM publie un nouveau GTFS

Refaire l'étape 2, vérifier le résumé imprimé (8 lignes, période de validité), lancer `flutter test`,
committer `assets/data/network.json`.
