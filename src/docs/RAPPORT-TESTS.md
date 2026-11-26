# Rapport de tests — Shadsun Gold Lens 0.15.1 et application 1.6.1

Auteur : Tarak Ben Abda — 20 novembre 2026.

**L'add-on n'a pas été exécuté dans World of Warcraft.** Tous les tests ci-dessous ont été exécutés hors jeu, avec Lua 5.1 (même version de langage que le client) et un client simulé strict (`tests/wowmock.lua`) : toute méthode de widget absente de l'API réelle provoque une erreur. Une simulation réussie ne prouve pas le fonctionnement dans le client ; elle prouve la logique, l'absence d'erreurs Lua et l'absence de récursion ou de doublons dans le modèle de cycle de vie reproduit. Sortie brute : `sortie-tests.txt`.

## 1. Tests exécutés et réussis

### Techniques

| # | Test | Résultat |
|---|---|---|
| 1 | Inventaire de tous les fichiers du ZIP v0.3.0 et de la v0.4.0 | réussi |
| 2 | Ordre de chargement du `.toc` (bibliothèques → init → locale → données → modules → interface) : chargement complet, `ADDON_LOADED`, `PLAYER_LOGIN` | réussi |
| 3 | Syntaxe Lua 5.1 de tous les fichiers de l'add-on (`luac5.1 -p`) | 36/36 réussis (dont 4 bibliothèques) |
| 4 | Globales : toutes les fonctions appelées sont des API du client ou des replis protégés ; seules 7 globales voulues sont écrites (`check_globals.sh`) | réussi |
| 5 | Structure de la base : aucune association vers un PNJ inexistant, coordonnées dans ]0;100[, statistiques recalculées en jeu = rapport de construction (objets, associations, PNJ) | réussi |
| 6 | Localisation : clé absente → repli sans erreur ; textes en français | réussi |
| 7 | SavedVariables : persistance après rechargement (réglages, position de l'icône, observations), migration v0.3.0 (relevés, options, minicarte, sauvegarde `legacy030`), idempotence | réussi |
| 8 | Calculs : exemple du cahier des charges (achat 20 pa, HDV 1 po 50 pa, 5 %) → bénéfice **1 po 22 pa 50 pc**, rentabilité **612,5 %**, commission 7 pa 50 pc, seuil 21 pa 6 pc ; lot de 5 ; HDV neutre 15 % ; monnaie négative, zéro, milliers ; objet lié ; achat en devise | réussi |
| 9 | Récursion : post-call réentrant ignoré ; post-call double dans une passe → un seul bloc ; reconstruction sans `OnTooltipCleared` → bloc rétabli une seule fois | réussi |
| 10 | Dépendances : aucune hors du ZIP (Auctionator et TomTom facultatifs) | réussi |
| — | Outil d'import : référence + observations, CSV manuel, SavedVariables (chaînes échappées, nouveaux PNJ) ; base produite rechargeable en Lua | réussi |

### Scénarios (version simulée)

| Scénario | Vérification | Résultat |
|---|---|---|
| 1 — Objet vendu par un PNJ | prix d'achat, marchand, zone, coordonnées | réussi |
| 2 — Recette (sac) | itemID de l'emplacement, profession, prix 40 pc, appel imbriqué de l'objet fabriqué ignoré | réussi |
| 3 — Objet sans vendeur connu | « aucun vendeur connu (non définitif) » ; objet hors base : « information non disponible » | réussi |
| 4 — Stabilité | 150 reconstructions (≈ 30 s) : contenu et hauteur identiques ; aucun minuteur | réussi |
| 5 — Changement rapide | 10 objets en rafale : ni texte résiduel ni doublon | réussi |
| 6 — Auctionator | prix, âge, bénéfice ; invalidation par `RegisterForDBUpdate` | réussi |
| 7 — Prix HDV absent | message exact demandé, « Calcul impossible », aucun faux bénéfice | réussi |
| 8 — Marchand | relevé (prix payé, lot, PNJ, position) ; priorité dans l'infobulle | réussi |
| 9 — TomTom | `AddWaypoint(uiMapID, x/100, y/100, opts)` ; commande `/tway #1453 55.1 69.8 …` ; refus sans coordonnées ou carte inconnue ; repli natif sans TomTom | réussi |
| 10 — Interface et minicarte | 4 onglets, boutons TomTom/Carte réels, clic gauche/droit, persistance au rechargement | réussi |
| 11 — Sans Auctionator | chargement sans erreur, indisponibilité affichée, achat PNJ conservé | réussi |
| 12 — Plusieurs vendeurs | 194 vendeurs de l'eau : zone, faction et coordonnées propres à chaque PNJ | réussi |

### Arbitrage HDV → PNJ (v0.5.0)

| Vérification | Résultat |
|---|---|
| Calcul par annonce : gain = Σ (quantité × rachat PNJ − prix de l'annonce) pour les seules annonces rentables | réussi |
| Scan complet : une requête, limite de 15 min respectée, refus si l'HDV est fermé | réussi |
| Lecture de 4 003 annonces en tranches, sans erreur | réussi |
| Opportunité exacte (3 u. à 5 pc, rachat 16 pc → +33 pc) ; aucune fausse opportunité | réussi |
| Historique Auctionator (prix 10 pc, rachat 25 pc → +15 pc / u.) ; priorité aux annonces en cours sans doublon | réussi |
| Ligne d'infobulle présente seulement si rentable | réussi |
| Panneau ouvert avec l'HDV, liste remplie, bouton Rechercher (Auctionator puis repli Blizzard), fermeture avec l'HDV | réussi |
| `/sgl hdv`, `/sgl arb`, sélecteur de sens de l'onglet Opportunités | réussi |
| Aucun texte affiché ne contient le nom réel ; signature « Créé par Shadsun » | réussi |

### Reproduction du bug de la v0.3.0

`tests/repro_v030_flicker.lua` charge le code d'origine de la v0.3.0 dans le même client simulé : hauteurs `2, 8, 2, 8, …` (12 changements de taille en 6 reconstructions). version actuelle : `10, 10, 10, …` (0 changement).

Coût mesuré d'un rendu (vue en cache) : environ 0,08 ms dans la simulation, hors coût du client.

### Corrections 0.5.1

| Vérification | Résultat |
|---|---|
| Signal de liste répété 5 fois : une seule lecture ; signal suivant, même liste : aucune relecture | réussi |
| « Arrêter la lecture » : lecture interrompue, données précédentes conservées | réussi |
| « Figer la liste » : aucune ligne modifiée pendant les mises à jour ; défiger applique les nouvelles données | réussi |
| Bouton de source « Direct (annonces) » : seules les annonces actuelles | réussi |
| « Replacer à côté de l'HDV » : masqué au départ, visible après déplacement, remet le panneau en place | réussi |
| Aucun caractère absent de la police du jeu dans les textes affichés | réussi |

Premier essai en jeu (captures du 16 novembre, 16 h 15) : panneau affiché à côté de l'HDV, 54 555 annonces lues, opportunités « Direct » et « Historique » listées. Défauts constatés et corrigés en 0.5.1 : relecture sans fin, flèche affichée comme un carré.

### Corrections 0.5.2

| Vérification | Résultat |
|---|---|
| « PNJ / u. » = prix de vente au marchand du jeu ; le prix marchand d'Auctionator (prix d'achat) n'est jamais utilisé (simulé à 999 999 pc pour le détecter) | réussi |
| Objet non chargé : absent, puis ajouté avec son vrai prix de rachat après chargement | réussi |
| Taille automatique : panneau réduit pour tenir à droite de l'HDV ; boutons « + » et « Auto » ; écran trop étroit : bord droit, échelle minimale 60 % | réussi |

Deuxième essai en jeu (16 h 42) : Actualiser et Figer la liste fonctionnent. Défauts constatés et corrigés en 0.5.2 : prix de rachat erroné, panneau recouvrant l'HDV.

### Corrections 0.5.3 (performance)

| Vérification | Résultat |
|---|---|
| Lecture des annonces : aucune demande d'infos envoyée d'un coup | réussi |
| Demandes au serveur : 20 au plus par tranche de 0,25 s | réussi |
| Info reçue pour un objet : un seul calcul, pas de recalcul complet | réussi |
| Fermeture de l'HDV : annonces brutes libérées, file vidée, plus aucune demande ensuite, résultats conservés | réussi |
| Mémoire, 54 555 annonces / 8 000 objets : +5 Mo pendant la lecture, 0 Mo conservé après fermeture | réussi |

Troisième essai en jeu : saccades persistantes après utilisation du panneau, disparaissant à la déconnexion. Causes identifiées dans le code et corrigées en 0.5.3 ; confirmation en jeu à faire.

### 0.5.4 (arrêt global, vitesse)

| Vérification | Résultat |
|---|---|
| « Tout arrêter » : analyse de l'historique stoppée, file vidée, plus aucune demande au serveur, résultats conservés | réussi |
| `/sgl stop` : lecture des annonces interrompue | réussi |
| Vitesse « Rapide » : 50 demandes par tranche ; volume non limité (120 objets tous demandés) | réussi |

### 0.6.0 (bordure dans la fenêtre du marchand)

| Vérification | Résultat |
|---|---|
| Objet rentable entouré ; objet à perte, sans prix HDV ou payé en devise non entouré | réussi |
| Aucun texte sur l'icône ; couleur par défaut et couleur choisie appliquées | réussi |
| Onglet Rachats, option désactivée, page sans objet : aucune bordure, aucune erreur | réussi |

À vérifier en jeu : nom des boutons de la fenêtre du marchand de Forever (`MerchantItem1ItemButton`…) et rafraîchissement au changement de page.

### 0.6.1 (métier des composants)

| Vérification | Résultat |
|---|---|
| Tissu : « Couture, Secourisme » ; herbe : « Alchimie » ; catégorie générique : rien ; recette : profession conservée | réussi |

À vérifier en jeu : sous-catégories d'artisanat attribuées par le client Forever aux objets Classic (si un tissu apparaît sans ligne « Métier », le client le classe en « Artisanat » générique).

### 0.7.0

| Vérification | Résultat |
|---|---|
| Recherche Auctionator non exacte (toutes les variantes) | réussi |
| Équipement : prix HDV = version simple seulement ; variantes utilisées dans le sens HDV » PNJ ; historique Auctionator non utilisé sans scan | réussi |
| Prix des annonces prioritaire sur l'historique | réussi |
| Ligne « Possédé » (sacs, banque), absente si rien | réussi |
| Nom coloré selon la qualité ; montants avec icônes de pièces ; option texte | réussi |
| Panneau HDV : sélecteur de sens, liste PNJ » HDV, colonne Poss., boutons Aller et Rechercher | réussi |
| Fenêtre principale : « + » (mémorisé), plafond 150 %, « 100 % » | réussi |

Essai en jeu du 17 novembre (19 h 30) : 310 447 annonces lues sur l'HDV de l'Alliance, 308 opportunités. Défaut constaté et corrigé : recherche exacte sans résultat pour les objets à variantes.

### 0.7.1

| Vérification | Résultat |
|---|---|
| Panneau HDV PNJ » HDV : filtres de l'onglet Opportunités, bouton Rechercher, pas de bouton Aller | réussi |
| Onglet Opportunités : icône Aller (TomTom), icône Copier (commande `/tway` présélectionnée) | réussi |
| Tri par « Poss. » ; mise à jour après changement des sacs | réussi |
| Arme de jet : prix à l'unité (15 pc), plus de lot de 200 à 0 pc | réussi |

### 0.8.0 (marchés, inventaire du compte, catégories, HDV » HDV, interface)

| Vérification | Résultat |
|---|---|
| Choix de l'HDV : Hurlevent = HDV Alliance, Tanaris = HDV neutre ; choix mémorisé par personnage ; avertissement si la zone ne concorde pas (barre de scan) | réussi |
| Scan enregistré pour l'HDV choisi et le serveur « Forever » : prix le plus bas 50 pc, 5 en vente, 3 annonces, personnage Aurelia | réussi |
| Stockage compact : 50 × 100 000 + 5 = 5 000 005 ; emballage réversible, valeurs sous 10^14 (exactes à 14 chiffres), plafonds de quantité et de prix | réussi |
| Choix corrigé juste après le scan : scan déplacé, ancien contenu de l'HDV rétabli ; visite suivante : aucun déplacement | réussi |
| Deuxième scan (HDV neutre) : celui de l'Alliance conservé | réussi |
| Équipement chargé après le scan : prix de la version simple ajouté à la photo (variante moins chère ignorée) | réussi |
| Infobulle : lignes « HDV Alliance » et « HDV neutre » (prix, quantité, âge) ; ligne Auctionator pour un objet absent des scans ; autre faction seulement avec l'option | réussi |
| Prix de revente : scan du marché de revente (faction ou neutre) ; scan ancien (10 j) : Auctionator préféré | réussi |
| HDV » HDV : 200 − commission 30 − 50 = 120 pc (240 %) ; paire Alliance » Horde « indirecte » ; 6 paires pour 3 HDV | réussi |
| Inventaire : sacs et banque relevés ; possédé = personnage connecté + autres personnages du serveur ; autre serveur exclu ; infobulle « 8 : Aurelia 3 · Kael 5 » | réussi |
| Catégories : noms du jeu, ordre de l'HDV, Armure » Tissu » Tête / Torse, robe rangée avec le torse | réussi |
| Recherche « epee » → « Épée courte usée » ; qualité minimale Rare | réussi |
| Menus : catégorie (3 niveaux au survol), sélection, libellé ; qualité au menu, à la molette, au clic droit ; recherche par nom après 0,3 s, effacement | réussi |
| Panneau de l'HDV : trois onglets de sens ; liste HDV » HDV, transferts indirects masqués, filtre de paire, infobulle de ligne ; loupe en icône | réussi |
| Onglet Marchés : fiches des HDV, personnages du serveur seulement ; Effacer en deux clics | réussi |
| `/sgl marches`, `/sgl diag`, `/sgl hdv` : marchés et personnages dans les rapports | réussi |
| Rechargement : scans et inventaires conservés ; autre serveur : aucun scan utilisé ; scans de plus de 30 jours supprimés ; migration 9 → 11 lignes | réussi |
| Volume : 2 HDV × 25 000 objets : HDV » HDV en 27 ms, 1 281 Ko en mémoire Lua pour les deux, ≈ 554 Ko par HDV dans les SavedVariables | réussi |
| Aucun caractère absent de la police du jeu dans les nouveaux textes ; aucune erreur interne | réussi |

### 0.9.0 (prix de l'API Blizzard, HDV » HDV en deux sens)

Outil `sgl_prix_api.py`, testé contre un faux serveur local imitant l'authentification Battle.net et les routes Forever (`test_sgl_prix_api.py`). **L'API réelle n'a pas été appelée** (pas de clé dans l'environnement de test) : les routes et champs suivent les relevés publics de la communauté.

| Vérification | Résultat |
|---|---|
| Jeton : authentification Basic, `grant_type=client_credentials` ; requêtes avec jeton Bearer, espace `dynamic-forever-eu`, locale `en_US` | réussi |
| Clé invalide, fichier `.ini` absent, mise à jour sans HDV configuré : message clair, code 1 | réussi |
| Identification : HDV Alliance et neutre trouvés d'après les scans des SavedVariables (100 % / 0 % sur les autres), HDV Horde déduit par position, prix des annonces = prix du lot entier ; `.ini` mis à jour sans perdre la clé | réussi |
| Synthèse : prix unitaire le plus bas et quantité totale ; variante à suffixe ignorée ; objet seulement en variante absent ; enchère seule absente ; marchandises (lien séparé) ; heure = en-tête Last-Modified ; cache local | réussi |
| Module écrit (TOC avec l'interface du client et la dépendance, Prix.lua en tranches) et chargé par Lua 5.1 ; valeurs emballées identiques à l'add-on | réussi |
| Add-on : module accepté (région EU) ; infobulle « HDV Horde \| 75 pc (1 en vente · API, il y a 1 h) » | réussi |
| Donnée la plus récente entre votre scan et l'API, dans les deux cas | réussi |
| HDV » HDV depuis l'API : achat 2 pa, revente 2 pa 60 pc, commission 39 pc, gain 21 pc, repère Horde 3 pa | réussi |
| HDV » HDV : sens « Faction » Neutre » par défaut, « Neutre » Faction », en-têtes selon le sens, repère de l'autre faction | réussi |
| Onglet Marchés : ligne « API Blizzard » par HDV, état du module | réussi |
| Région du client différente, format inconnu, module absent : prix ignorés sans erreur, explication | réussi |

Premier essai réel (19 novembre, 22 h 43) : identification sur l'API réelle — HDV Alliance 110 (85,3 % de prix identiques sur 4 597 objets), neutre 116 (68,2 % sur 2 430), Horde 113 par position ; mise à jour : 261 820 / 266 367 / 43 849 annonces ; prix Horde vérifié en jeu sur un objet connu.

### 0.10.0 (listes d'achats, avis HDV » HDV, rechargement, mise à jour horaire)

| Vérification | Résultat |
|---|---|
| Listes : liste de départ, ajout, doublon refusé, création, renommage, duplication, suppression (une liste toujours conservée), quantité et prix maximum | réussi |
| Progression (possédé / voulu), ligne d'infobulle « Liste \| Ma liste 3 / 5 » | réussi |
| Alt+clic : ajout ; aucun ajout dans la fenêtre du marchand ni sans Alt | réussi |
| Icône + d'une ligne d'opportunité : ajout à la liste active | réussi |
| Onglet Listes : prix par HDV, le moins cher en vert, prix maximum respecté, édition par clic, ajout par ID, loupe inactive puis active à l'HDV, recherche d'un article, « Rechercher toute la liste » (articles non obtenus seulement), retrait | réussi |
| Listes conservées au rechargement (communes au compte) | réussi |
| Marchand : article d'une liste entouré en bleu, option désactivable | réussi |
| Avis : Faction » Neutre (Favorable, Défavorable avec gain réaliste au repère, À vérifier sans repère ou avec 1 objet), Neutre » Faction (Favorable / À vérifier) ; colonne, filtre, seuil réglable | réussi |
| Boutons Recharger (onglet Marchés, barre de scan), `/sgl listes` | réussi |
| Outil : noms des types de serveur lus sur `/ruleset/{id}` ; tâche horaire (toutes les heures, sans fenêtre, batterie, rattrapage après veille, une instance, 15 min max) ; refus clair hors Windows | réussi |

### 0.10.1

| Vérification | Résultat |
|---|---|
| Ordre des onglets : Objet, Listes, Opportunités, Marchés, Paramètres, Base & diagnostic | réussi |
| Panneau de l'HDV : 4ᵉ onglet Listes, articles de la liste active, loupe active, recherche, « Rechercher toute la liste », sélecteur de liste | réussi |
| Montants compacts (490 po ; 15 po 90 pa ; 99 pc) et rentabilité compacte (>999 % ; 178 %) | réussi |

### 0.10.2

| Vérification | Résultat |
|---|---|
| Onglet Listes (fenêtre principale) : icônes Aller (point TomTom) et Copier (`/tway` présélectionné), pas de loupe | réussi |
| Colonne PNJ (recette à 40 pc) en vert, moins chère que les HDV ; prix maximum : HDV grisés, PNJ conservé | réussi |
| Panneau de l'HDV : loupe sans icône Aller ; vue des listes rafraîchie à l'affichage | réussi |

### 0.11.0

| Vérification | Résultat |
|---|---|
| Bouton + répété : quantité augmentée (plus de refus « déjà dans la liste ») ; bouton - à gauche ; Maj+clic ±5 ; sous 1, retrait ; - grisé si absent ; badge de quantité | réussi |
| Message et survol : « 1 dans « Ma liste » — sacs 2 · banque 5 » ; « en vente 2 » quand des enchères existent | réussi |
| Enchères : relevé demandé à l'ouverture de l'HDV et après une mise en vente ; enchères vendues ignorées ; ligne « En vente » sous « Possédé » | réussi |
| Hors HDV : « acheteur trouvé » et « a expiré » retirent l'annonce ; marchandise vendue en partie : « ~19 » / « (au plus) » ; autre message sans effet | réussi |
| Enchères de tous les personnages du serveur additionnées, détail par personnage ; option de l'infobulle ; colonne « Vente » ; progression sans les objets en vente ; relevé conservé après rechargement | réussi |
| Migration : infobulle 11 → 12 lignes (schéma 4) | réussi |
| Outil : tâche lancée par `pythonw.exe` (repli `wscript` + `maj_cachee.vbs`), déclencheur à l'ouverture de session avec l'utilisateur, répétition sans fin | réussi |
| Outil : journal `journal_maj.txt` (réussite, erreur avec raison, trace complète d'une erreur inattendue, exécution sans console, taille limitée) ; codes du Planificateur traduits ; `etat` hors Windows | réussi |

### 0.11.1

| Vérification | Résultat |
|---|---|
| Colonnes « Sacs » (sacs du personnage, sans la banque) et « Vente » (« ~25 », « - ») dans les tableaux ; tri par « Sacs » mis à jour quand les sacs changent ; plus de « Poss. » | réussi |
| Outil : téléchargement au compte-gouttes arrêté au délai maximal ; connexion bloquée : 3 tentatives puis erreur claire | réussi |
| Outil : délai global, mise à jour abandonnée et notée ; journal écrit au fil de l'eau ; priorité normale de la tâche | réussi |

### Outil 0.12.0

| Vérification | Résultat |
|---|---|
| Tâche : boucle résidente (`pythonw.exe … boucle`), ouverture de session + 1 min, relance horaire de secours (quotidienne répétée chaque heure), sans limite de durée ; repli `wscript` limité à 15 min | réussi |
| Boucle (horloge simulée) : mise à jour à l'heure écoulée puis une heure d'attente ; nouvelle tentative 15 min après un échec ; rattrapage au réveil après 90 s ; demande immédiate ; verrou (une seule boucle) ; processus séparé avec délai | réussi |

### Add-on 0.12.0 et application de bureau 1.0

| Vérification | Résultat |
|---|---|
| Add-on : nom de la source repris du module (« Forever AH »), infobulle « Forever AH, il y a 1 h », onglet Marchés avec la mention de Forever AH, « API Blizzard » par défaut pour un ancien module | réussi |
| Moteur : faux serveur Forever AH (mêmes champs que le vrai site) : 15 HDV EU retenus (HDV « tous » et autres régions ignorés), table du marché (prix minimum, quantité, date, annonces), ligne sans prix ignorée, cache, identification par User-Agent | réussi |
| Moteur : types de serveur → HDV (PvP 110/113/116, Normal 111/114/117, JdR 119/120/121, JdR-PvP 123/124/125), suggestion d'après le nom de royaume | réussi |
| Mise à jour complète en source Forever AH : module écrit avec source et mention, chargé en Lua 5.1 ; état des prix relu par l'application | réussi |
| Vérification du type de serveur avec un relevé du jeu (SavedVariables) : PvP reconnu ; région lue dans Config.wtf | réussi |
| Cœur : dossier du jeu reconnu à partir de n'importe quel niveau, installation et remplacement de l'add-on, clé jamais écrite dans le fichier, coffre (repli hors Windows), reprise de l'ancien outil, commande de relance | réussi |
| Boucle horaire : rien avant l'heure, mise à jour immédiate unique, automatique à l'intervalle, désactivation, délai de reprise après échec ; instance unique et signal « afficher » | réussi |
| Interface sous écran virtuel (Python 3.12 + Tk 8.6) : les 4 étapes de l'assistant, installation de l'add-on, test de la source, suggestion et vérification du type de serveur, enregistrement, une seule première mise à jour, fenêtre principale (3 HDV, annonces, prochaine mise à jour), journal, réouverture des paramètres ; captures de chaque écran | réussi |

### Add-on 0.13.0 et application 1.1

| Vérification | Résultat |
|---|---|
| Filtre « Meilleur achat » : Tous, PNJ, HDV neutre, HDV Horde, aucune offre, HDV Alliance vide avec message | réussi |
| Case « Seulement là où ce personnage peut acheter » : HDV Horde ignoré pour le filtre et le vert, prix toujours affiché ; décochée, vert rétabli | réussi |
| Tri des listes : prix neutre croissant / décroissant (sans prix en bas), PNJ, nom sans accents, flèche, clic sur l'en-tête | réussi |
| Surbrillance de la ligne au survol du X (listes) et du + (PNJ » HDV), rendue à la sortie | réussi |
| Logo dans l'en-tête ; icône dans le TOC et sur le bouton de la mini-carte ; TGA 32 bits non compressés 256 et 64 px ; icônes de faction du jeu dans l'infobulle | réussi |
| Application : images présentes et transparentes, icône à 7 tailles, symboles et boutons dessinés | réussi |
| Interface (écran virtuel) : décor de l'assistant et de la fenêtre principale, 5 boutons dessinés, redimensionnement avec textes conservés, journal ouvert par le bouton dessiné | réussi |

### Application 1.2

| Vérification | Résultat |
|---|---|
| Dessin à très petite taille (bouton 1×1, panneau 2×1, cadres 2×2, échelle 0,001) : aucune erreur `y1 must be greater than or equal to y0` | réussi |
| Fenêtre réduite à 200×120 : aucun plantage, décor reporté puis redessiné à la bonne taille | réussi |
| Éléments graphiques fournis présents ; cadres étirés aux tailles demandées | réussi |
| Guide de la clé : ouverture à l'étape 1, navigation, étape du formulaire avec 3 boutons Copier (presse-papiers vérifié), pas de deuxième fenêtre, Terminer ferme | réussi |
| `construire_exe.bat` : arrêt de l'exe et suppression de l'ancien fichier avant PyInstaller | relu, non exécuté (Windows) |

### Application 1.2.1

| Vérification | Résultat |
|---|---|
| `construire_exe.bat` : toutes les étiquettes existent, fins de ligne Windows | réussi |
| `construire_exe.bat` : un message d'erreur ne suit jamais une étape réussie. Ce test détecte le défaut de la 1.2 (3 messages fautifs) | réussi |
| `construire_exe.bat` : ordre fermeture → mise de côté de l'exe bloqué → PyInstaller | réussi |
| En-tête : logo en médaillon dans le bandeau (fenêtre principale et assistant), mise en page vérifiée sur capture | réussi |
| Exécution réelle de `construire_exe.bat` sous Windows | non exécutée |

### Application 1.3 (visuel)

| Vérification | Résultat |
|---|---|
| Bandeau d'état : ornement du bas centré à ± 3 px (avant : décalé de 133 px sur 780) | réussi |
| Boutons ornés dans l'assistant, le guide et le journal ; navigation du guide et boutons Copier toujours fonctionnels | réussi |
| Mise en page vérifiée sur captures (fenêtre principale, assistant, guide) | réussi |
| Rendu avec la police Gabriola sous Windows | non vérifié (absente de l'environnement de test) |

| 1.3.4 — Ornements du haut des cartes et du panneau centrés à ± 3 px ; bords gauches alignés (vérifié sur capture, axe central et bord gauche tracés) | réussi |
| 1.3.3 — Losanges du milieu du cadre retirés (vérifié sur capture) | réussi |
| 1.3.2 — Légende fixe du personnage (« PVP · EUROPE ») dans la fenêtre principale et dans l'assistant | réussi |

### Add-on 0.14.0 et application 1.5

| Vérification | Résultat |
|---|---|
| Arme présente dans votre scan (hier) mais absente de l'API (il y a 1 h) : prix du scan conservé, avec son heure. Avant : aucun prix | réussi |
| Objet présent des deux côtés : la donnée la plus récente l'emporte | réussi |
| Infobulle de l'arme : « 2 po 50 pa (1 en vente · scan, il y a 1 j) » | réussi |
| Objet vendu seulement en variantes : « dès 4 po (variantes seulement · 2 en vente · API, il y a 1 h) » | réussi |
| Prix d'équipement ajouté au scan après la lecture : visible dans la photo fusionnée | réussi |
| HDV » HDV : l'arme du scan Alliance est comparée au neutre | réussi |
| Moteur : variante seule gardée à part (2531 → 4 pa), table `v` écrite dans Prix.lua et relue par Lua 5.1 | réussi |
| Fenêtre principale : médaillon de 76 px débordant en haut à gauche, zone de maintien à l'écran élargie, titre décalé | réussi |
| Panneau de l'HDV : gemme seule (28 px) | réussi |
| `Media/medaillon.tga` : 128 × 128, 32 bits, non compressé | réussi |
| Rendu réel du médaillon et des prix d'armes dans le jeu | non vérifié (client simulé) |
| Mises à jour en ligne (faux GitHub local) : lecture de la dernière version et de `sgl-version.json` | réussi |
| Une seule vérification par jour (cache), nouvelle vérification après 24 h | réussi |
| Empreinte différente : installation annulée, add-on installé intact | réussi |
| Archive contenant un chemin `../` : refusée, rien d'écrit hors du dossier | réussi |
| Version de l'archive différente de l'annonce : refus | réussi |
| Installation depuis GitHub : add-on installé, dossier temporaire supprimé | réussi |
| Bandeau : add-on en ligne proposé ; nouvelle application signalée (« Télécharger ») ; rien quand tout est à jour, sans retour à un add-on plus ancien | réussi |
| Adresse non HTTPS refusée | réussi |
| Interface : bandeau « version … disponible en ligne » avec le bouton « Installer l'add-on » | réussi |
| Téléchargement réel depuis github.com et fabrication de l'exe par GitHub Actions | à vérifier à la première publication |

### Add-on 0.15.0 et application 1.6

| Vérification | Résultat |
|---|---|
| Onglet Objet : Maj+clic (fonction du client actuel `ChatFrameUtil.InsertLink`) → objet affiché | réussi |
| Onglet Objet (0.15.1) : « + » → 1 ; Maj+clic « + » → 6 ; « - » → 5 ; Maj+clic « - » → retiré, « - » grisé | réussi |
| Listes (0.15.1) : « + » et « - » sur une ligne, badge à jour | réussi |
| Listes : Maj+clic dans « Ajouter » → ajout immédiat (avant : sans effet sur le client actuel) ; ancien client pris en charge, un seul ajout | réussi |
| Filtre « Nom de l'objet » : Maj+clic → nom inséré ; le lien ne va qu'au champ actif | réussi |
| Avis : prix de plus de 24 h → À vérifier ; raisons lisibles | réussi |
| Avis : repère plus bas mais revente au repère rentable → Favorable « au prix repère » (avant : Défavorable) ; sans gain au repère → Défavorable | réussi |
| HDV » HDV : budget « Achat max (po) » ; tri par défaut sur le gain réaliste ; âge de chaque prix sur la ligne | réussi |
| Listes : coût total, reste à acheter (selon le possédé), articles sans prix ; ligne affichée | réussi |
| Application : exe téléchargé → copié à l'emplacement fixe, version notée, copie installée relancée | réussi |
| Même version installée : simple relance ; vieil exe : ouvre la copie installée sans l'écraser ; Python et modes `--maj` / `--remplacer` : jamais d'installation | réussi |
| Mise à jour en un clic : empreinte fausse refusée ; nouvel exe téléchargé, mode `--remplacer`, remplacement, version notée, relance, nettoyage | réussi |
| Raccourcis (1.6.1) : Bureau réel demandé à Windows (OneDrive compris), menu Démarrer, raccourci égaré de la 1.6.0 retiré, réparation une seule fois | réussi (script vérifié ; création réelle sous Windows non testée) |
| En-tête : versions et état (disponible / à jour / non installé), affichage vérifié sur capture | réussi |
| Installation, raccourcis et remplacement réels sous Windows | à vérifier chez vous (1.6 installe ; la mise à jour en un clic se vérifiera avec la version suivante) |

**Total : 423 tests de l'add-on, 52 tests du moteur de prix, 78 tests du cœur de l'application et 30 tests de l'interface, tous réussis.**

**Non vérifiable ici (0.13.0) :** l'affichage réel en jeu des fichiers TGA (logo, icône de la liste des add-ons) et des icônes de faction `Interface\FriendsFrame\PlusManz-*` dans le client Forever ; le rendu de l'application sous Windows (polices Palatino Linotype / Segoe UI, échelle d'affichage).

**Non vérifiable ici :**
- la fabrication et le lancement de l'exe (PyInstaller sous Windows) ;
- l'avertissement SmartScreen ;
- l'icône pystray près de l'horloge de Windows ;
- le Gestionnaire d'identification de Windows et la clé « Exécuter » ;
- la suppression de l'ancienne tâche planifiée ;
- le vrai site Forever AH (le format a été relevé sur le site réel le 24 novembre 2026, les tests utilisent une copie locale).

**Non vérifiable ici :** la création et l'exécution réelles de la tâche par le Planificateur de tâches de Windows (pas de Windows dans l'environnement de test), la commande PowerShell de `7_Etat…`, et la liste des enchères renvoyée par le client Forever (`C_AuctionHouse.GetOwnedAuctions`, messages système de vente et d'expiration en français).

## 2. Tests exécutés et échoués

Aucun dans la version livrée. Défauts détectés puis corrigés pendant le développement : appel `xpcall` avec arguments (non portable), format de GUID dans un test, isolement des événements entre rechargements simulés.

## 3. Tests non exécutables sans client WoW

À effectuer en jeu (Aurelia, Alliance, client français) ; envoyez-moi `/sgl diag` en cas d'anomalie :

1. Chargement réel avec `## Interface: 16001` (vérifier l'absence de la mention « périmé »).
2. Rendu visuel des infobulles dans chaque contexte : sacs, banque, HDV, marchand, journal des métiers, lien du chat, échange, récompenses de quête.
3. Stabilité réelle (souris immobile 30 s, rafale sur 10 objets) avec Auctionator et d'autres add-ons d'infobulle actifs.
4. Comportement réel des recettes : présence de `GetPrimaryTooltipData` et ordre des appels imbriqués sur Forever.
5. Valeurs réelles de l'API Auctionator installée (prix, âge) et de `C_MerchantFrame.GetItemInfo`.
6. Point TomTom réel et commande `/tway #uiMapID` (syntaxe de TomTom à confirmer).
7. Aspect de l'icône de minicarte avec la minicarte de Forever (LibDBIcon 56).
8. Fenêtres : lisibilité, chevauchements, police, position sauvegardée.
9. Règles HDV de Forever (commission de faction/neutre, dépôt).
10. Panneau HDV : position à côté de la fenêtre de l'HDV, bouton **Gold Lens**, lecture des annonces après un scan complet d'Auctionator, **loupe** (lancer `/sgl hdv` devant l'HDV et me transmettre le résultat).
11. v0.8.0 — Détection de l'HDV neutre : à Baie-du-Butin, « Scan pour » doit proposer « HDV neutre » sans avertissement ; sinon, `/sgl hdv` donne l'identifiant de carte réel à ajouter.
12. v0.8.0 — Rendu des nouveaux éléments : menus déroulants (fermeture au clic extérieur et avec Échap), flèches (texture du jeu pivotée), icônes loupe / carte / note, champ de recherche (icône, texte d'aide, croix d'effacement), onglets.
13. v0.8.0 — Relevé de la banque du personnage avec les onglets de banque du client moderne (la banque de bataillon n'est pas comptée).
14. v0.8.0 — Taille réelle des SavedVariables après des scans de l'HDV de l'Alliance et de l'HDV neutre.
15. v0.9.0 — API réelle : `1_Tester` (liste des 15 HDV), `2_Identifier_mes_HDV` (score de correspondance), sens du champ `buyout` (prix du lot ou de l'unité), présence des marchandises, fréquence de mise à jour (heure affichée par l'outil), chargement du module en jeu et taille de Prix.lua.
16. v0.10.0 — Création réelle de la tâche horaire par `5_Activer_la_mise_a_jour_horaire` (Planificateur de tâches) et absence de fenêtre ; Alt+clic dans les sacs et sur les liens du chat ; rendu de l'onglet Listes.

18. Add-on 0.14.0 — En jeu : survoler une arme lue au scan alors que les prix de l'application sont plus récents (prix affiché avec « scan, il y a … ») ; une arme vendue seulement en variantes (ligne « dès ») ; netteté du médaillon de la fenêtre principale, débordement esthétique, fenêtre déplacée en haut de l'écran.
17. Application 1.2 — Sous Windows : démarrage de l'exe sans erreur (premier affichage, réduction puis restauration de la fenêtre, écran à 125 % ou 150 %), aspect des cadres fournis, guide de la clé (liens et boutons Copier), `construire_exe.bat` lancé pendant que l'application tourne.

## 4. Limitations restantes

- Données : 958 objets en référence Classic seule ; 304 objets dont aucun vendeur n'a de coordonnées (vendeurs de rang JcJ, instances) ; 30 PNJ à faction inconnue ; conditions CMaNGOS interprétées par déduction.
- Prix d'un HDV disponible seulement après un scan de cet HDV par l'un de vos personnages ; HDV de la faction adverse : scan par un personnage de cette faction.
- Détails Maj visibles à la reconstruction suivante de l'infobulle (pas de rafraîchissement forcé, pour éviter toute contamination de l'infobulle sécurisée).
