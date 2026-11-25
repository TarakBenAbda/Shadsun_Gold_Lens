# Audit de Shadsun Gold Lens v0.3.0

Auteur : Tarak Ben Abda — audit réalisé le 16 novembre 2026 sur les fichiers fournis (`ShadsunGoldLens.toc`, `GoldLens.lua`, `Interface.lua`, `Reference.lua`, `Vendors.lua`, bibliothèques et licences).

Légende : **[Confirmé]** = démontré par lecture du code ou exécution hors jeu ; **[Hypothèse]** = probable, à confirmer en jeu.

## A. État du code

| Fichier | Rôle |
|---|---|
| `ShadsunGoldLens.toc` | Interface 16001, SavedVariablesPerCharacter `ShadsunGoldLensDB`, dépendance optionnelle Auctionator |
| `Reference.lua` (958 Ko) | 916 PNJ et 1 765 objets (QuestieDB Forever + tarifs CMaNGOS), 1 765 noms anglais, 14 889 objets connus |
| `Vendors.lua` (233 Ko) | 339 PNJ et 1 159 objets observés sur Forever (EG Link), plus 2 ajouts manuels |
| `GoldLens.lua` | prix Auctionator, relevé marchand, fusion des offres, infobulle |
| `Interface.lua` | fenêtre unique, repère de carte, icône LDB, `/sgl` |
| `Libs/` | LibStub, CallbackHandler, LibDataBroker, LibDBIcon 56 |

## B. Pourquoi l'add-on ne fonctionnait pas

1. **[Confirmé]** Infobulle instable : rendu différé (voir D).
2. **[Confirmé]** Double raccordement : `TooltipDataProcessor` + `hooksecurefunc` sur `SetHyperlink`, `SetItemByID`, `SetMerchantItem`, `SetBagItem` ; chaque survol déclenche plusieurs mises en file.
3. **[Confirmé]** Prix d'achat incohérents : la fusion clé `npc:qty:ext` laisse le prix EG (payé par un joueur, remise incluse) écraser le tarif de référence ; 946 des 3 912 couples PNJ/objet présents dans les deux sources ont un prix différent.
4. **[Confirmé]** Rentabilité calculée seulement si `priority(offer) <= 2` et si le type de liaison est en cache ; sinon « Type de liaison en attente » sans mise à jour.
5. **[Confirmé]** Commission 5 % codée en dur ; aucun choix HDV neutre.
6. **[Confirmé]** Aucune intégration TomTom ; clic droit de l'icône = carte (pas de paramètres) ; seulement 3 options.
7. **[Hypothèse]** Icône de minicarte « bizarre » : icône `INV_Misc_Coin_01` recadrée par LibDBIcon et dimensions « Classic » choisies car `WOW_PROJECT_ID` ≠ `WOW_PROJECT_MAINLINE` sur Forever. La v0.4.0 conserve LibDBIcon (même rendu que Questie) avec une icône plus lisible ; à valider visuellement.

## C. Base PNJ

Comptage réel (script `audit.lua`) : 2 116 objets avec au moins un vendeur, 966 PNJ utilisés, 18 280 lignes brutes (14 368 après dédoublonnage), 17 920 avec prix en or, 343 en devise, 17 à prix nul. Le chiffre annoncé « 2 116 objets / 966 PNJ » est exact en nombre, mais la qualité est inégale :

| Constat | Volume |
|---|---|
| Écarts de prix EG / référence pour un même PNJ | 946 (674 à 90 % : remise de réputation ; ~70 à 10–12 % : vrais changements Forever) |
| Quantité de lot différente entre sources | 108 |
| PNJ EG sans faction | 57 (dont gobelins neutres connus de la référence) |
| PNJ à position différente entre sources | 10 (Foire de Sombrelune, patrouilles, PNJ déplacés) |
| PNJ sans coordonnées | 28 (souvent en instance) |
| Lignes à condition CMaNGOS brute (1535…1538, 156, 161, 500, 1368, 1369) | 301 |
| Objets connus uniquement par la référence Classic | 957 |
| Ajouts manuels non sourcés en jeu | 2 (Catherine Leland via sites web, Kendor Kabonka via ForeverDB) |

Cause de « Aucun achat PNJ documenté » : texte affiché pour tout objet sans ligne d'offre, sans distinction entre « connu sans vendeur » et « inconnu », et sans possibilité de compléter. **[Hypothèse]** Certains cas venaient aussi d'objets nouveaux de Forever absents des deux sources.

## D. Clignotement de l'infobulle

Cause **[Confirmé, reproduite hors jeu]** : `queueTooltip()` diffère l'ajout des lignes (`C_Timer.After(0)`) puis appelle `tooltip:Show()`. Le client moderne reconstruit périodiquement l'infobulle (`RefreshData` : `ClearLines` → lignes Blizzard → post-calls → `Show`). Le hook `ClearLines` remet l'état à zéro, le post-call remet un rendu en file : l'infobulle s'affiche d'abord sans le bloc, puis avec à l'image suivante. Mesure : hauteurs successives `2, 8, 2, 8, …` (12 changements en 6 reconstructions) ; v0.4.0 : `10, 10, 10, …` (0 changement). Script : `tests/repro_v030_flicker.lua`.

## E. Compatibilité Forever

Forever utilise le client moderne (TOC 16001, API Retail 12.x). Aucune incompatibilité bloquante trouvée dans la v0.3.0 : `TooltipDataProcessor`, `C_MerchantFrame.GetItemInfo`, `C_Map`, `C_Item` existent. Points fragiles : `xpcall` avec arguments supplémentaires (non portable Lua 5.1, corrigé), valeurs « secrètes » du client 12.x non gérées (gérées en v0.4.0), `select(14, C_Item.GetItemInfo())` sans gestion de l'objet non chargé.

## F. Plan appliqué

| Partie | Décision |
|---|---|
| Infobulle | réécrite (post-call synchrone unique, gardes, recettes) |
| Données | reconstruites par un outil reproductible (prix de base, positions, factions, conditions, statuts) |
| Prix / calculs | réécrits (cuivre entier, commission configurable, verdict non garanti) |
| Observation marchande | conservée, enrichie, partagée entre personnages |
| Interface | remplacée (onglets, opportunités, paramètres, diagnostic) |
| Minicarte | LibDBIcon conservée, comportement conforme |
| TomTom | ajouté |
| SavedVariables | migration automatique et réversible |
