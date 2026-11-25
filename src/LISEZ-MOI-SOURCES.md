# Shadsun Gold Lens 0.14.0 — sources, outils et documentation

Auteur : Tarak Ben Abda.

| Dossier | Contenu |
|---|---|
| `ShadsunGoldLens/` | l'add-on complet (identique au ZIP installable) |
| `src/tools/sgl_build_db.py` | outil de construction de la base (voir `src/tools/README-OUTILS.md`) |
| `src/tools/prix_api/` | application de bureau (`sgl_app.py` interface, `sgl_theme.py` habillage, `assets/` images, `sgl_core.py` cœur, `sgl_prix_api.py` moteur et ligne de commande), fabrication de l'exe (`construire_exe.bat`, `sgl_icon.py`), `LISEZ-MOI-APPLICATION.md`, `GUIDE-API.md`, anciens lanceurs `.bat` |
| `.github/workflows/` | `publier.yml` : « Run workflow » (ou étiquette `vX.Y.Z`), tests puis publication (zip de l'add-on, exe, `sgl-version.json`) ; `construire-application.yml` : exe d'essai à la demande |
| `src/tools/input/` | fichiers d'entrée (base v0.3.0) et modèle CSV d'ajouts manuels |
| `src/tools/audit_v030/` | scripts d'audit de la base v0.3.0 |
| `src/tests/` | client simulé strict, 388 tests de l'add-on, 50 tests du moteur de prix, 41 tests du cœur de l'application et 20 tests de l'interface (écran virtuel, captures), reproduction du clignotement v0.3.0, vérification des globales |
| `src/docs/AUDIT-v0.3.0.md` | audit de la version précédente |
| `src/docs/RAPPORT-BASE.md` | statistiques et empreintes de la base générée |
| `src/docs/RAPPORT-TESTS.md` | rapport de tests |
| `src/docs/sortie-tests.txt` | sortie brute des tests |

Documentation utilisateur : `ShadsunGoldLens/LISEZ-MOI.md` ; journal des modifications : `ShadsunGoldLens/CHANGELOG.md`.

Reconstruire la base puis relancer les tests :

```
cd src/tools
python sgl_build_db.py --reference input/Reference_v030.lua --observed input/Vendors_v030.lua --out ../../ShadsunGoldLens/Data/Catalog.lua --report ../docs/RAPPORT-BASE.md
cd ../tests
python3 test_sgl_prix_api.py
python3 test_app_core.py
xvfb-run -a python3 test_app_gui.py captures   # Python avec tkinter
lua5.1 run_tests.lua ../../ShadsunGoldLens
```
