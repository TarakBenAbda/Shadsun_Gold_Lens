# Shadsun Gold Lens 0.14.0 — WoW Forever

Créé par Shadsun. Add-on d'aide au commerce entre marchands PNJ et hôtels des ventes (HDV), dans trois sens : acheter au PNJ pour revendre à l'HDV, acheter à l'HDV pour revendre au PNJ, et acheter sur un HDV pour revendre sur un autre (Alliance, Horde, neutre), pour **World of Warcraft: Forever** (client 1.60.1, `## Interface: 16001`).

L'add-on est un **outil d'information** : il n'achète rien, ne déplace pas votre personnage et n'automatise aucune action protégée.

---

## 1. Installation

1. Fermez complètement le jeu.
2. Supprimez l'ancien dossier `World of Warcraft\_forever_\Interface\AddOns\ShadsunGoldLens` (vos données sont conservées dans `WTF`, elles seront migrées).
3. Décompressez `Shadsun_Gold_Lens_v0.14.0_WoW_Forever.zip` dans `Interface\AddOns\`. Le fichier `ShadsunGoldLens.toc` doit se trouver directement dans `Interface\AddOns\ShadsunGoldLens\`.
4. Relancez le jeu, activez **Shadsun Gold Lens** (et Auctionator) dans la liste des add-ons.
5. Le chat doit afficher : `Shadsun Gold Lens v0.14.0 · Créé par Shadsun · /sgl`.

Dépendances :

| Add-on | Rôle | Obligatoire |
|---|---|---|
| Auctionator | prix HDV (API publique v1) | non — sans lui, les prix HDV et la rentabilité sont désactivés proprement |
| TomTom | points de navigation | non — sans lui, le repère natif de la carte du jeu est utilisé |
| LibStub, CallbackHandler, LibDataBroker, LibDBIcon | icône de minicarte | incluses dans le ZIP |

Si le client passe à une nouvelle version (TOC différent), l'add-on apparaîtra « périmé » : `/sgl diag` affiche le TOC réel du client.

---

## 2. Utilisation

### Infobulle (survol d'un objet)

Fonctionne dans les sacs, la banque, l'HDV, les fenêtres marchandes, le journal des métiers, les liens du chat, l'échange et les récompenses de quête — partout où le client affiche une infobulle d'objet.

```
Shadsun Gold Lens                         Confirmé
Profession                                 Cuisine
Possédé                     8 : Aurelia 3 · Kael 5
Achat PNJ                                    40 pc
Vente PNJ                                    10 pc
HDV Alliance        1 po 50 pa (12 en vente · il y a 2 h)
HDV neutre           1 po 95 pa (3 en vente · il y a 1 j)
Bénéfice net    +1 po 42 pa 10 pc (+35 525,0 %) Alliance
Catherine Leland · Alliance +9 autre(s)  Hurlevent 55.1, 69.8
Accessible aux deux factions (confiance moyenne)
```

Lignes **HDV** : pour chaque objet, la donnée la plus récente qui le contient, entre votre scan et les prix téléchargés par l'application. L'âge et la source affichés sont ceux de cette donnée. Si un objet n'est en vente qu'en **variantes** (« … de l'aigle », bonus), la ligne indique un prix « dès » : `HDV Alliance  dès 4 po (variantes seulement · 2 en vente · API, il y a 1 h)`.

- **Achat PNJ** : ce que vous payez au marchand (lot indiqué : « 25 pc / lot de 5 »).
- **Vente PNJ** : ce que le marchand vous donne si vous lui vendez l'objet.
- **HDV Alliance / HDV Horde / HDV neutre** : une ligne par hôtel des ventes dont le prix est connu (vos scans ou l'API Blizzard), avec le prix unitaire le plus bas, la quantité en vente, la source et l'âge (en orange au-delà de « Prix HDV ancien après »). L'HDV de l'autre faction peut être masqué (option). Objet absent de tous les scans : ligne **HDV** avec le dernier prix connu par Auctionator. Pour les armes et armures, seules les annonces de la **version simple** comptent (le marchand vend la version simple ; les variantes « … de l'aigle » sont plus chères) ; sans scan, leur prix HDV est indisponible.
- **Bénéfice net** : calculé sur le **marché de revente** (Paramètres ou onglet Marchés), dont le nom est rappelé en fin de ligne quand son scan est utilisé.
- **Possédé** : exemplaires détenus par **tous vos personnages du serveur** (sacs et banque). Personnage connecté : nombre exact donné par le jeu ; autres personnages : dernier relevé (sacs à chaque changement, banque à chaque visite).
- Montants affichés avec les icônes de pièces du jeu (option pour revenir à « po / pa / pc »).
- **Métier** : pour une recette, la profession concernée ; pour un composant d'artisanat, le ou les métiers qui l'utilisent, d'après la catégorie attribuée par le jeu (tissu : Couture, Secourisme ; herbe : Alchimie ; métal et pierre : Forge, Ingénierie ; cuir : Travail du cuir ; viande : Cuisine ; enchantement : Enchantement…). Catégorie générique : rien n'est affiché plutôt qu'une supposition.
- **Maj** enfoncée : source des données, seuil de rentabilité, marge, verdict, commission, sort enseigné par une recette, ID de l'objet. Maintenez Maj pendant le survol (l'add-on ne force pas de reconstruction de l'infobulle).

### Panneau de l'HDV : barre de scan et trois sens

En haut du panneau, la **barre de scan**, commune aux trois sens :

- **Scan pour** : l'HDV auquel le prochain scan sera attribué (HDV de votre faction ou HDV neutre). Le choix est **prérempli d'après la zone** (Baie-du-Butin, Gadgetzan, Long-guet = HDV neutre ; ailleurs = HDV de votre faction) et **mémorisé pour chaque personnage** dès que vous le changez. Si votre choix ne concorde pas avec la zone, un avertissement orange s'affiche (sans bloquer). Si vous changez le choix juste après un scan, l'HDV encore ouvert, ce scan est réattribué au bon HDV.
- **Lire les annonces** : scan complet (une fois toutes les 15 minutes, limite du jeu ; un scan complet lancé par Auctionator est lu de la même façon). **Tout arrêter** : arrêt immédiat de toute analyse.
- Ligne d'état : progression de la lecture, dernier scan de l'HDV choisi, délai avant le prochain scan complet.

Sous la barre, quatre onglets : **HDV » PNJ**, **PNJ » HDV**, **HDV » HDV** et **Listes** (vos listes d'achats avec un sélecteur de liste, une loupe par article et « Rechercher toute la liste »). En mode PNJ » HDV, la liste est **la même que l'onglet Opportunités** (mêmes filtres et colonnes), avec une **loupe** par ligne. Un astérisque signale un prix HDV issu de l'historique Auctionator plutôt que d'un scan.

**Filtres communs à toutes les listes** :

- **Catégorie** : même arbre que l'onglet « Acheter » de l'HDV — catégorie (Armes, Armure, Conteneur, Consommable, Artisanat, Recette…) » sous-catégorie » emplacement pour les armures (Tête, Torse…). Survolez une catégorie pour ouvrir ses sous-catégories ; cliquez pour choisir. Les noms viennent du jeu. Seules les catégories présentes dans vos données sont proposées. Les recettes par profession se trouvent dans **Recette » Couture**, **Recette » Cuisine**…
- **Qualité min.** : Médiocre à Légendaire, en couleur.
- **Nom de l'objet** : recherche pendant la frappe, sans tenir compte des majuscules ni des accents (« epee » trouve « Épée »).

Les sélecteurs s'ouvrent en menu au clic ; la molette (ou un clic droit) passe à la valeur suivante (ou précédente). Les en-têtes de colonnes trient (flèche sur la colonne active). Les icônes de ligne affichent leur rôle au survol : **loupe** = rechercher dans l'HDV, **carte** = point TomTom, **note** = commande `/tway` à copier.

La **loupe** lance une recherche **non exacte** : toutes les variantes d'un objet (« Bâtarde aiguisée de l'aigle », « … de force »…) s'affichent, comme une recherche manuelle.

### Marchés : scans par HDV, par serveur, partagés par vos personnages

Chaque lecture des annonces enregistre une **photo du marché** de l'HDV choisi : prix unitaire le plus bas et quantité totale en vente pour chaque objet, heure du scan et personnage. Les photos sont **communes à tous les personnages du compte** et **rangées par serveur** : un personnage scanne l'HDV de l'Alliance, un autre l'HDV neutre, et chacun voit les deux prix. Trois marchés possibles par serveur : **Alliance**, **Horde**, **neutre** (l'HDV neutre est commun aux deux factions). Un personnage de la Horde voit « HDV Horde » et « HDV neutre » sans rien régler.

Onglet **Marchés** de la fenêtre principale (`/sgl marches`) :

- une fiche par HDV du serveur : nombre d'annonces et d'objets, personnage, date et âge du scan, bouton **Effacer** (deux clics) ;
- **Marché de revente** (calculs PNJ » HDV) et **Scans de ce personnage** (selon la zone, HDV de ma faction, HDV neutre) ;
- options de l'infobulle (prix des HDV scannés, HDV de l'autre faction) ;
- **vos personnages du serveur** : or, nombre d'objets en sac, fraîcheur des relevés des sacs et de la banque, bouton **Oublier** (personnage supprimé).

Une photo n'est valable qu'au moment du scan ; elle est supprimée au bout de 30 jours. Stockage compact : un nombre par objet (environ 550 Ko de données sauvegardées et 640 Ko de mémoire pour un HDV de 25 000 objets, mesuré hors jeu).

### Arbitrage HDV » HDV

Deux sens, au choix par un commutateur (« Faction » désigne l'HDV de l'Alliance ou de la Horde selon le personnage connecté) :

- **Faction » Neutre** : acheter à l'HDV de votre faction, revendre à l'HDV neutre (commission 15 %) ;
- **Neutre » Faction** : acheter à l'HDV neutre, revendre à l'HDV de votre faction (commission 5 %).

**Gain par unité = prix de revente - commission de l'HDV de revente - prix d'achat** (commissions réglables). Colonnes : prix d'achat, prix de revente, **Repère** (prix sur l'HDV de l'autre faction), gain, rentabilité, quantité en vente à l'achat, âge des données, nombre possédé. Filtres : catégorie, qualité, nom, **achat max (po)** (votre budget par unité), gain réaliste minimal, rentabilité minimale. Tri par défaut : gain réaliste décroissant.

**Avis** (colonne et filtre) :

| Sens | Favorable | À vérifier | Défavorable |
|---|---|---|---|
| Faction » Neutre | gain réaliste positif (en revendant, si besoin, au prix repère de l'autre faction) et au moins « Qté min. » objets en vente au neutre | pas de repère, trop peu d'objets en vente au neutre, ou prix de plus de 24 h | même au prix repère, plus aucun gain |
| Neutre » Faction | l'HDV de revente a au moins « Qté min. » objets en vente (vrai prix de marché) | trop peu d'objets en vente, ou prix de plus de 24 h | — |

En Neutre » Faction, seuls les joueurs de votre faction achètent à son HDV : le prix de l'autre faction n'entre pas dans l'avis (il reste affiché pour information). « Qté min. » vaut 3 par défaut. Au survol : la raison de l'avis et l'âge de chaque prix. **Gain réal.** : gain calculé sur le plus bas entre votre prix de revente et le repère (Faction » Neutre).

**Repère** : ce que les joueurs de l'autre faction paient chez eux. C'est le meilleur indice du prix auquel ils achèteront au neutre : en orange quand il est inférieur à votre prix de revente au neutre (ils n'ont aucune raison de payer plus cher au neutre). Explication au survol de la ligne. Disponible grâce aux prix de l'API Blizzard (ci-dessous) ou à un scan par un personnage de l'autre faction.

Prix des annonces les moins chères au moment des relevés : vérifiez dans l'HDV avant d'acheter ; revendre suppose de rester sous l'annonce la moins chère.

### Listes d'achats (`/sgl listes`)

Listes communes à tous vos personnages du compte, dans l'onglet **Listes** :

- à gauche, vos listes : **Nouvelle**, **Renommer** (tapez le nom dans le champ), **Dupliquer**, **Supprimer** (deux clics) ; un clic rend une liste **active** ;
- à droite, les articles : quantité voulue, **Possédé** (« 3 / 5 », vos personnages du serveur, en vert une fois atteint), prix maximum, prix sur l'HDV de votre faction, de l'autre faction et neutre ; en vert, le moins cher sous votre prix maximum ;
- clic sur un article : modifier la quantité voulue et le prix maximum ;
- colonne **PNJ** : prix d'achat chez le meilleur marchand connu, comparé aux HDV (le moins cher sous votre maximum en vert, PNJ compris) ; marchand et emplacement au survol ;
- dans la fenêtre principale : icônes **Aller** (TomTom vers le marchand) et **Copier** (commande `/tway`) ; dans le panneau de l'HDV : **loupe** (recherche de l'article) ; **Rechercher toute la liste** : tous les articles non encore obtenus en une seule recherche (Auctionator) ; icône de retrait ;
- ajout : icône **+** sur chaque ligne des tableaux d'opportunités (onglet et panneau de l'HDV), **Alt+clic** sur un objet (sacs, liens du chat, HDV ; jamais dans la fenêtre du marchand), le bouton **Ajouter à la liste** de l'onglet Objet (Maj+clic : +5), ou le champ **Ajouter** (ID, nom, ou Maj+clic sur un objet pendant que le champ est actif : ajout immédiat).

Sous le tableau : **Coût de la liste** (tout acheter au meilleur prix connu, case verte), **reste à acheter** (ce qui manque encore) et le nombre d'articles sans prix sous votre maximum.

Infobulle : ligne **Liste** (nom et progression). Chez un marchand, les articles de vos listes sont entourés en **bleu** (prioritaire sur la bordure « rentable »). L'achat reste manuel.

### Prix des trois HDV (HDV de la Horde compris) : l'application Shadsun Gold Lens

Un add-on ne peut pas accéder à Internet. L'**application Shadsun Gold Lens** (`ShadsunGoldLens.exe`, ou `Lancer_Shadsun_Gold_Lens.bat`), lancée sur votre PC, télécharge les prix des HDV Alliance, Horde et neutre de votre type de serveur et écrit le module **Shadsun Gold Lens - Prix** dans AddOns. Deux sources :
- **Simple, sans compte** : Forever AH (forever-ah.com), qui lit l'API Battle.net ;
- **Avancé** : votre propre clé Blizzard.

L'add-on lit le module à la connexion ou après `/reload` (bouton **Recharger** de l'onglet Marchés ou icône de la barre de scan). L'application met les prix à jour toutes les heures en arrière-plan (icône près de l'horloge). Pour chaque HDV, la donnée la plus récente (votre scan ou les prix téléchargés) est utilisée, avec sa source (« Forever AH, il y a 1 h » ou « API, il y a 1 h »). Installation et réglages : **`LISEZ-MOI-APPLICATION.md`**, livré avec l'application.

### Fenêtre du marchand : bordure des objets rentables

Quand vous ouvrez un marchand, les objets qu'il vend et qui sont rentables à revendre à l'HDV sont entourés d'une bordure de couleur (aucun texte sur l'icône). Calcul : prix réellement demandé par ce marchand (remise de réputation incluse), taille du lot, prix HDV (scan du marché de revente, sinon Auctionator), commission ; bordure si bénéfice > 0 et rentabilité ≥ « rentabilité minimale » (Paramètres). Objets payés en devise ou sans prix HDV : jamais entourés. Couleur au choix (vert, or, bleu, violet) ; option désactivable.

### Arbitrage HDV » PNJ (panneau dans l'hôtel des ventes)

À l'ouverture de l'HDV, un panneau **Gold Lens** s'ouvre à droite de la fenêtre (bouton **Gold Lens** au-dessus de l'HDV pour l'afficher ou le masquer ; ouverture automatique désactivable). Il liste les objets vendus à l'HDV **moins cher que le prix de rachat d'un marchand**.

- **PNJ / u.** = prix de **rachat** par un marchand, celui que le jeu affiche « Prix de vente » dans l'infobulle. Tant que le jeu n'a pas chargé un objet, il n'apparaît pas (aucune valeur de remplacement) ; il est ajouté dès son chargement.
- Gain = prix de vente au PNJ − prix d'achat HDV. L'acheteur ne paie ni commission ni dépôt.
- **Annonces en cours** (source « Direct ») : après un scan complet, l'add-on lit toutes les annonces chargées et calcule, annonce par annonce, la quantité rentable, le coût et le gain total. Le scan complet peut venir d'Auctionator ou du bouton **Lire les annonces** de la barre de scan : c'est la même requête Blizzard, limitée à une fois toutes les 15 minutes par compte. Si des annonces sont déjà chargées, le bouton les relit sans nouveau scan.
- **Historique Auctionator** (source « Hist. ») : bouton **Analyser l'historique Auctionator**, qui compare le dernier prix connu de chaque objet de la base à son prix de rachat. Quantité et disponibilité inconnues.
- **Volume** : aucune limite sur le nombre d'annonces ou d'objets analysés (HDV neutre ou de faction, quelle que soit sa taille).
- **Tout arrêter** (ou `/sgl stop`) : arrête immédiatement toute activité en arrière-plan — lecture des annonces, analyse de l'historique, demandes d'informations au serveur. Les résultats déjà obtenus restent affichés ; vous pouvez relancer l'analyse plus tard. La lecture n'a lieu qu'une fois par scan : le jeu signale la liste plusieurs fois, l'add-on attend 2 s de calme puis ne relit que si la liste a changé.
- **Figer la liste** : plus aucune mise à jour automatique, les lignes ne bougent plus ; **Actualiser** applique les nouvelles données à la demande. Même non figée, la liste n'est jamais recalculée pendant une lecture et garde sa position de défilement.
- **Source** : trois onglets — **Toutes**, **Direct (annonces)** (annonces présentes au dernier scan, prix et quantités réels), **Historique** (dernier prix Auctionator, quantité inconnue). Filtres de catégorie, de qualité et de nom comme dans les autres listes.
- **Vitesse d'analyse** (Paramètres) : Lente (jeu prioritaire, 40 demandes/s), Normale (80/s), Rapide (200/s). Elle règle seulement le rythme, jamais la quantité analysée.
- **Performance** : les informations d'objets sont demandées au jeu au rythme choisi, uniquement HDV ouvert ou pendant une analyse ; chaque réponse ne recalcule que l'objet concerné. À la fermeture de l'HDV, les annonces brutes et les demandes en attente sont libérées ; seuls les résultats (compacts) sont conservés. `/sgl diag` affiche la mémoire utilisée par l'add-on.
- **Taille** : le panneau se réduit automatiquement pour tenir dans l'espace libre à droite de l'HDV sans le recouvrir. Boutons **-** / **+** (pas de 5 %, mémorisés) et **Auto** (retour à l'ajustement automatique). Si l'écran est trop étroit même réduit à 60 %, le panneau se place contre le bord droit de l'écran.
- **Replacer à côté de l'HDV** : le panneau suit la fenêtre de l'HDV ; si vous le déplacez, il reste à l'endroit choisi et ce bouton apparaît pour le remettre contre l'HDV.
- Gain minimal par unité ; tri par clic sur un en-tête de colonne. Clic sur une ligne : détail de l'objet. **Loupe** : lance la recherche de l'objet (onglet Achats d'Auctionator, sinon barre de recherche de l'HDV). **L'achat reste manuel** : vérifiez le prix affiché par l'HDV avant d'acheter, les données datent du scan.
- La même liste est disponible hors de l'HDV : onglet **Opportunités**, onglet **HDV » PNJ**.
- Dans l'infobulle, la ligne **Revente PNJ (HDV » PNJ)** apparaît seulement si l'objet est rentable dans ce sens.

### Fenêtre principale (`/sgl` ou clic gauche sur l'icône)

Onglets : **Objet**, **Listes**, **Opportunités** (trois sens : PNJ » HDV, HDV » PNJ, HDV » HDV), **Marchés**, **Paramètres**, **Base & diagnostic**. Dans les tableaux, les montants sont compacts (sans cuivre au-delà de 1 po, sans argent au-delà de 100 po) ; le détail complet est au survol. La barre d'état, en bas, rappelle le marché de revente et l'âge de son scan.

Dans l'onglet **Opportunités** (sens PNJ » HDV), deux petites icônes devant chaque objet : la **carte** place un point TomTom vers le marchand ; la **note** ouvre une petite fenêtre avec la commande `/tway #carte x y Marchand` déjà sélectionnée — faites Ctrl+C puis collez-la dans le chat (les add-ons ne peuvent pas écrire eux-mêmes dans le presse-papiers). Toutes les colonnes se trient, y compris « Poss. ». **Maj+clic** sur un objet pendant qu'un champ « Nom de l'objet » est actif y inscrit son nom.

Boutons **Taille** « - » / « + » (de 70 % à 150 %, par pas de 10 %) et « 100 % » en haut à droite ; la taille est mémorisée. Les noms d'objets des tableaux sont colorés selon leur qualité ; une colonne « Poss. » indique le nombre possédé.

- **Objet** : recherche par ID, lien (Maj+clic sur un objet quand le champ est actif) ou nom ; bouton **Ajouter à la liste** (liste active, Maj+clic : +5, quantité déjà présente affichée) ; prix, rentabilité, prix sur chaque HDV scanné, nombre possédé par personnage, **tous les marchands** (faction, zone, coordonnées, prix, stock, conditions, source), boutons **TomTom** et **Carte**, commande `/tway` à copier.
- **Opportunités** : tableaux triables (clic sur un en-tête) et filtrables — catégorie, qualité, nom, faction du vendeur, exclusivité, données HDV, zone, statut, prix d'achat maximal, bénéfice minimal, rentabilité minimale. Les filtres s'appliquent dès qu'ils changent ; **Actualiser** recalcule avec les derniers prix. Jamais de calcul pendant le survol.
- **Marchés** : voir ci-dessus.
- **Paramètres** : voir § 3.
- **Base & diagnostic** : statistiques recalculées sur la base chargée, sources, vos observations, rapport de diagnostic copiable.

### Icône de minicarte

Clic gauche : fenêtre principale · Clic droit : paramètres · Glisser : déplacer (position mémorisée). Elle peut être masquée (paramètres ou `/sgl minimap`). L'add-on figure aussi dans le compartiment d'add-ons du client.

### Commandes

| Commande | Effet |
|---|---|
| `/sgl` | ouvrir/fermer la fenêtre |
| `/sgl objet <ID, lien ou nom>` | détail d'un objet |
| `/sgl opp` | tableau des opportunités |
| `/sgl marches` | scans des HDV du serveur et personnages |
| `/sgl listes` | listes d'achats |
| `/sgl options` | paramètres |
| `/sgl arb` | panneau de l'hôtel des ventes |
| `/sgl stop` | arrêter toute analyse en arrière-plan |
| `/sgl hdv` | diagnostic de l'API de l'hôtel des ventes (à lancer devant l'HDV, résultat à copier) |
| `/sgl info <ID>` | calcul détaillé dans le chat (sans ID : dernier objet survolé) |
| `/sgl debug [on/off]` | messages de diagnostic dans le chat |
| `/sgl diag` | rapport de diagnostic (fenêtre à copier pour me le transmettre) |
| `/sgl stats` | état de la base |
| `/sgl minimap` | afficher/masquer l'icône |
| `/sgl resetui` | réinitialiser la position des fenêtres et de l'icône |

---

## 3. Paramètres

Sauvegardés pour tout le compte dans `WTF\Account\<compte>\SavedVariables\ShadsunGoldLens.lua`.

| Paramètre | Défaut | Effet |
|---|---|---|
| Informations au survol | oui | active le bloc dans les infobulles |
| Prix d'achat / vente PNJ / HDV / rentabilité / marchand / faction / statut / profession | oui | lignes affichées |
| Infobulle : prix des HDV scannés | oui | une ligne par HDV scanné du serveur |
| Infobulle : inclure l'HDV de l'autre faction | oui | affiché seulement s'il a un prix (API Blizzard ou scan) |
| Ligne pour les objets sans vendeur connu | oui | affiche « Aucun vendeur PNJ connu (non définitif) » |
| Nombre possédé | oui | ligne « Possédé » (tous vos personnages du serveur, sacs et banque) |
| Montants avec icônes de pièces | oui | icônes or/argent/cuivre au lieu de « po/pa/pc » |
| Arbitrage HDV » PNJ | oui | ligne « Revente PNJ » quand l'achat HDV est inférieur au rachat PNJ |
| Ouvrir le panneau Gold Lens avec l'HDV | oui | affiche le panneau d'arbitrage à l'ouverture de l'HDV |
| Bordure des objets rentables chez le marchand | oui | entoure les objets rentables à revendre à l'HDV |
| Couleur de la bordure | Vert | vert, or, bleu ou violet |
| Vitesse d'analyse HDV | Normale | Lente / Normale / Rapide : rythme de lecture et de demandes au serveur (aucune limite de volume) |
| Seulement avec Maj | non | n'affiche le bloc qu'avec Maj |
| Masquer en combat | non | |
| Nombre maximal de lignes | 11 | 3 à 20 (+6 avec Maj) ; porté de 9 à 11 lors de la mise à jour si vous ne l'aviez pas modifié |
| Marché de revente | HDV de faction | ou HDV neutre : son scan fournit le prix HDV, sa commission est déduite |
| Scans de ce personnage | selon la zone | ou HDV de ma faction / HDV neutre (mémorisé par personnage) |
| Commission faction / neutre | 5 % / 15 % | règles Classic de référence, à confirmer sur Forever |
| Remise de réputation | 0 % | appliquée aux prix de référence uniquement |
| Rentabilité « intéressante » | 20 % | en dessous : « Marge faible » |
| Prix HDV ancien après | 7 jours | signalé « ancien » |
| Risque de dépôt (estimation) | désactivé | % paramétrable du prix de vente PNJ, affiché avec Maj |

---

## 4. Données des marchands

Trois couches, de la plus fiable à la moins fiable :

1. **Vos observations** (couche B) : à chaque ouverture d'une fenêtre marchande, l'add-on enregistre en lecture seule les objets, le prix **que vous payez** (remise de réputation incluse), le lot, le stock, la devise éventuelle, le PNJ (ID, nom, faction) et votre position. Elles priment sur tout le reste et sont partagées entre vos personnages.
2. **Observations Forever** (Efficient Games / EG Link, builds 1.60.1.70790 → 70938) : vendeurs réellement vus sur Forever.
3. **Référence** (QuestieDB Forever pour les vendeurs et positions, CMaNGOS Classic pour les tarifs) : non confirmée sur Forever.

Statuts affichés :

| Statut | Signification |
|---|---|
| **Vendu par un PNJ confirmé** | au moins un vendeur vu sur Forever (EG Link ou vous) |
| **À vérifier** | uniquement des données de référence Classic |
| **Aucun vendeur PNJ confirmé** | objet connu des bases, aucun vendeur listé — **ce n'est pas une preuve d'absence** |
| **Information non disponible** | objet absent des bases |

Traitements appliqués à la base (outil `sgl_build_db.py`) :

- **Prix de base par objet** : les prix observés incluent souvent la remise de réputation de l'observateur (674 relevés à 90 % du tarif). Le tarif de référence est conservé quand l'écart est ≤ 15 % ; au-delà, le prix Forever est retenu (ex. Couteau à dépecer : 10 pc sur Forever contre 82 pc en Classic) et signalé « prix Forever différent de Classic ».
- **Position** : la position observée sur Forever prime ; les PNJ dont la position diffère entre sources (Foire de Sombrelune, patrouilles) sont marqués « position variable ».
- **Faction** : déterminée par toutes les sources ; l'exclusivité d'un objet est calculée sur **l'ensemble** de ses vendeurs, avec un niveau de confiance.
- **Conditions** : les identifiants de condition CMaNGOS sont interprétés comme « Réputation requise » ou « Événement saisonnier » d'après les objets concernés (déduction à confirmer en jeu).

Contenu actuel (calculé sur les fichiers) : 2 116 objets vendus, 966 PNJ, 14 368 associations objet-vendeur, 1 158 objets confirmés sur Forever, 958 en référence seule. Détail : onglet **Base & diagnostic** et `RAPPORT-BASE.md` (sources).

---

## 5. Auctionator

- API utilisée : `Auctionator.API.v1.GetAuctionPriceByItemID`, `GetAuctionPriceByItemLink` (repli), `GetAuctionAgeByItemID`, `RegisterForDBUpdate` (le cache est vidé à chaque mise à jour de la base Auctionator), toutes appelées sous `pcall`.
- Aucun scan propre à l'add-on, aucun prix inventé : sans donnée, l'infobulle indique **« Prix HDV indisponible — effectuer un scan Auctionator. »** et la rentabilité affiche « Calcul impossible ».
- Priorité des prix pour revendre : **scan du marché de revente** (s'il n'est pas « ancien ») ; sinon dernier prix Auctionator ; sinon scan ancien. Auctionator ne distingue pas l'HDV où chaque prix a été vu ; les scans de Gold Lens, eux, sont rangés par HDV. Aucun prix n'est simulé : un HDV jamais scanné n'a pas de prix.

### Calculs (en cuivre, entiers)

- Commission = ⌈q × prix HDV × taux⌉ (arrondi défavorable).
- Bénéfice = q × prix HDV − commission − coût du lot PNJ.
- Rentabilité = bénéfice / coût du lot × 100.
- Seuil HDV par unité = ⌈coût / (q × (1 − taux))⌉. Marge = bénéfice / (q × prix HDV).
- Le dépôt n'est pas soustrait : il est restitué quand la vente aboutit. Sa perte en cas d'invendu peut être estimée (option).
- Le prix HDV est un prix observé, pas une vente garantie : le meilleur verdict possible est « Opportunité potentielle (non garantie) ».

---

## 6. Mise à jour de la base

Le jeu n'accède pas à Internet : la base est un fichier généré, `Data\Catalog.lua`. Pour la reconstruire (outil séparé, Python 3.8+, aucune dépendance) :

```
python tools\sgl_build_db.py --reference input\Reference_v030.lua --observed input\Vendors_v030.lua ^
  --manual input\manual.csv ^
  --savedvariables "C:\...\WTF\Account\<COMPTE>\SavedVariables\ShadsunGoldLens.lua" ^
  --out ..\ShadsunGoldLens\Data\Catalog.lua --report docs\RAPPORT-BASE.md
```

- `--savedvariables` intègre vos relevés marchands à la base livrée (utile pour partager une base enrichie).
- `--manual` : CSV (séparateur `;` ou `,`) de vendeurs vérifiés : `itemID;npcID;npcName;side;mapID;x;y;price;quantity;limited;source;note`. Un modèle est fourni.
- L'outil n'interroge aucun site : téléchargez vous-même les sources, en respectant leurs licences (voir `tools\README-OUTILS.md`).

---

## 7. Limitations connues

- **Panneau HDV** : fondé sur l'API moderne `C_AuctionHouse` (scan complet, lecture des annonces) et sur la fenêtre `AuctionHouseFrame`. Si un autre add-on remplace la fenêtre de l'HDV, le panneau s'ouvre seul (`/sgl arb`). `/sgl hdv` permet de vérifier l'API réelle.
- Les opportunités HDV » PNJ sont souvent de faible montant et disparaissent vite (autres acheteurs).
- **Non testé dans le client WoW** : les tests ont été exécutés hors jeu sur un client simulé (voir `RAPPORT-TESTS.md`). Les scénarios en jeu restent à valider.
- Règles HDV de Forever (commission, HDV neutres, dépôt) non confirmées officiellement : valeurs Classic par défaut, modifiables.
- Les prix HDV dépendent de vos scans et, avec l'application, de Forever AH ou de l'API Blizzard (non documentée pour Forever, susceptible de changer). Sans l'application, l'HDV de la faction adverse n'a de prix que s'il est scanné par un personnage de cette faction.
- **Détection de l'HDV neutre** par identifiant de carte (identifiants Classic et modernes). Si l'avertissement orange apparaît alors que vous êtes bien à l'HDV indiqué par votre choix, envoyez-moi `/sgl hdv` (il affiche l'identifiant de carte réel) ; le choix manuel reste prioritaire.
- Personnages : les sacs d'un personnage sont relevés quand il est connecté ; sa banque, quand il l'ouvre. La banque de bataillon (commune au compte) n'est pas comptée.
- 958 objets ne sont connus que par la référence Classic ; 27 PNJ n'ont pas de coordonnées (souvent en instance) ; 30 PNJ ont une faction inconnue (nouveaux PNJ Forever) : visitez-les pour compléter la base.
- La recherche par nom utilise les noms anglais de référence et les noms français déjà en cache du client.
- Commande `/tway #uiMapID x y` : syntaxe à identifiant de carte de TomTom ; le bouton **TomTom** (API directe) reste la méthode recommandée.

---

## 8. Sources et licences

- Code : GPLv3 (`LICENSE.txt`), © Tarak Ben Abda (Shadsun).
- [QuestieDB](https://github.com/Questie/QuestieDB) — vendeurs et positions Forever, GPLv3 (`LICENSE-QuestieDB.md`).
- [CMaNGOS Classic DB](https://github.com/cmangos/classic-db) — tarifs de référence, GPLv3.
- [Efficient Games / EG Link](https://github.com/JIVESCORP/eg-link-output-wowf) — *Data from Efficient Games, licensed under CC BY 4.0* ; données regroupées, filtrées, dédoublonnées et indexées.
- [pfQuest](https://github.com/shagu/pfQuest) — noms français des PNJ, MIT (`LICENSE-pfQuest.txt`).
- LibStub (domaine public), CallbackHandler et LibDBIcon (Ace3, style BSD, `Libs\LICENSE-Ace3.txt`), LibDataBroker.
- Les noms, icônes et éléments du jeu appartiennent à Blizzard Entertainment.
