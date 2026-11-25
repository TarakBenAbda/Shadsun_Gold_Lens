# Outils — Shadsun Gold Lens 0.7.1

Auteur : Tarak Ben Abda.

## `sgl_build_db.py` — construction de la base

Génère `ShadsunGoldLens/Data/Catalog.lua` et un rapport de qualité. Python 3.8+ ; bibliothèque standard uniquement ; **aucun accès réseau**. Un bandeau d'auteur s'affiche au lancement.

```
python sgl_build_db.py --reference input/Reference_v030.lua --observed input/Vendors_v030.lua \
    [--manual input/manual.csv] [--savedvariables chemin/ShadsunGoldLens.lua] \
    --out ../../ShadsunGoldLens/Data/Catalog.lua --report ../docs/RAPPORT-BASE.md [--json stats.json] [--date AAAA-MM-JJ]
```

### Entrées

| Option | Format | Contenu |
|---|---|---|
| `--reference` | Lua (format v0.3.0) | `addon.referenceVendors`, `referenceOffers`, `referenceNames`, `knownItems` (QuestieDB Forever + CMaNGOS) |
| `--observed` | Lua (format v0.3.0) | `addon.vendors`, `addon.offers` (EG Link, builds 1.60.1.x) |
| `--manual` | CSV `;` ou `,`, UTF-8 | ajouts vérifiés : `itemID;npcID;npcName;side;mapID;x;y;price;quantity;limited;source;note` — modèle : `input/manual_template.csv` |
| `--savedvariables` | Lua | fichier `WTF\Account\<COMPTE>\SavedVariables\ShadsunGoldLens.lua` : vos relevés en jeu |

Conventions : `side` = `A`, `H`, `N` (neutre/les deux) ou `?` ; `mapID` = uiMapID du client (ex. 1453 Hurlevent, 1429 Forêt d'Elwynn) ; `x`, `y` en pourcentage (0–100) ; `price` en **cuivre** pour le lot ; `quantity` = taille du lot.

### Règles de fusion

1. Ajouts manuels > observations Forever (EG, vos SavedVariables) > référence Classic.
2. Prix de base par (objet, lot) : tarif de référence conservé si le prix observé maximal est entre 85 % et 100 % de celui-ci (remise de réputation) ; sinon prix Forever, signalé.
3. Quantité de lot différente sur Forever : la ligne de référence du même PNJ est remplacée.
4. Position observée sur Forever prioritaire ; écart > 3 unités ou zone différente → PNJ « position variable », ancienne position conservée.
5. Faction : observation Forever prioritaire ; `AH` (référence) → `N`.

### Sortie (`Data/Catalog.lua`)

- `D.npcs[npcID] = {nomEN, nomFR|false, faction, uiMapID|false, x|false, y|false, drapeaux[, altMap, altX, altY]}`
- `D.items[itemID] = {npcID, prixBase, lot, drapeaux, condition, prixObservéInférieur, …}` (6 champs par vendeur)
- `D.names`, `D.knownRanges` (plages compactes), `D.meta` (statistiques recalculées).
- Drapeaux des lignes : 1 référence, 2 observé Forever, 4 stock limité, 8 devise/objet, 16 prix Forever ≠ Classic, 32 prix référence seul, 64 prix observé seul, 128 lot modifié, 256 prix incertain, 512 manuel, 1024 remise observée, 2048 source web.
- Drapeaux des PNJ : 1 référence, 2 observé, 4 position variable, 8 sans position, 16 conflit de faction, 32 faction inconnue, 64 manuel.

### Sources et conditions d'utilisation

L'outil ne télécharge rien. Pour actualiser les fichiers d'entrée, récupérez manuellement les publications officielles des projets, dans le respect de leurs licences :

- QuestieDB (GPLv3, voir `LICENSE-QuestieDB.md`) ;
- CMaNGOS classic-db (GPLv3) ;
- Efficient Games / EG Link (CC BY 4.0 — mention obligatoire « Data from Efficient Games ») ;
- pfQuest (MIT) pour les noms français.

Wowhead et les sites similaires n'offrent pas d'API publique de données de vendeurs ; leur extraction automatisée n'est pas prévue. Une vérification ponctuelle à la main, saisie dans `manual.csv` avec la source, reste possible.

## Tests (`../tests`)

```
cd tests
lua5.1 run_tests.lua ../../ShadsunGoldLens          # 180 tests hors jeu
lua5.1 repro_v030_flicker.lua ../../ShadsunGoldLens # reproduction du clignotement v0.3.0
lua5.1 show_tooltip.lua ../../ShadsunGoldLens       # rendu texte d'infobulles simulées
sh check_globals.sh ../../ShadsunGoldLens           # globales lues/écrites (luac5.1 requis)
```
