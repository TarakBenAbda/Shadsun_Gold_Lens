# Journal des modifications — Shadsun Gold Lens

## Application 1.6.2 — 25 novembre 2026

Add-on inchangé (0.15.1).

- **Vérifier les nouvelles versions à la demande** : lien « ↻ Vérifier » dans l'en-tête, à côté des versions, et entrée « Vérifier les nouvelles versions » dans le menu de l'icône près de l'horloge. GitHub est interrogé tout de suite, sans attendre la vérification quotidienne ; un message indique ce qui est disponible, ou que tout est à jour.
- Publication : une version de l'application seule (add-on inchangé) reçoit l'étiquette `vADDON-appAPP`, par exemple `v0.15.1-app1.6.2`.

## 0.15.1 et application 1.6.1 — 25 novembre 2026

- **Onglet Objet** : boutons « - » et « + » (Maj+clic : ±5), avec la quantité dans la liste active (« 3 dans « Ma liste » »), au lieu du seul bouton « Ajouter à la liste ».
- **Listes** : « - » et « + » sur chaque ligne, comme dans les tableaux d'opportunités. Le « X » de retrait reste. Les colonnes sont légèrement resserrées.
- **Raccourci du Bureau** : la 1.6.0 cherchait le Bureau à l'emplacement classique (`Utilisateur\Desktop`). Il est souvent redirigé vers OneDrive (`OneDrive\Bureau`) : le raccourci y était invisible.
  - Le Bureau réel est maintenant demandé à Windows.
  - Les raccourcis sont réparés une fois au démarrage de la copie installée, et le raccourci égaré est retiré.

## 0.15.0 et application 1.6 — 25 novembre 2026

### Add-on
- **Onglet Objet : « Ajouter à la liste »**. Le bouton ajoute l'objet affiché à la liste active (Maj+clic : +5) et indique la quantité déjà présente, par exemple « Ajouter (3 en liste) ».
- **Maj+clic dans toutes les zones de recherche d'objet** : champ « Ajouter » des listes (ajout immédiat), champs « Nom de l'objet » des filtres (Opportunités, panneau de l'HDV), onglet Objet.
  - Cause : seul l'onglet Objet suivait la fonction du client actuel (`ChatFrameUtil.InsertLink`) ; le champ des listes ne suivait que l'ancienne.
  - Désormais, un mécanisme commun suit les deux fonctions et ne traite chaque lien qu'une fois.
- **Avis HDV » HDV revus** :
  - « Défavorable » ne sert plus que lorsque, même en revendant au prix de l'autre faction (repère), il n'y a plus de gain. Avant, un repère plus bas suffisait, même si la revente au repère restait rentable : ces lignes sont maintenant « Favorable », avec l'explication « au prix repère ».
  - « À vérifier » si un des deux prix a plus de 24 h ; l'âge des prix était ignoré.
  - Au survol : la raison de l'avis et l'âge de chaque prix.
  - Le gain minimal filtre sur le gain réaliste ; le tri par défaut se fait sur le gain réaliste.
- **HDV » HDV : « Achat max (po) »**, budget par unité comme en PNJ » HDV.
- **Listes : coût de la liste** sous le tableau : tout acheter au meilleur prix connu, reste à acheter, nombre d'articles sans prix sous le maximum.

### Application 1.6
- **Emplacement fixe** : au premier lancement, d'où qu'il vienne, l'exe s'installe dans `%LOCALAPPDATA%\Programs\ShadsunGoldLens`, crée les raccourcis « Shadsun Gold Lens » (Bureau et menu Démarrer), ferme une ancienne version encore ouverte et met le démarrage avec Windows à jour. Le fichier téléchargé peut ensuite être supprimé. Relancer un vieil exe ouvre simplement la version installée.
- **Mise à jour de l'application en un clic** (bouton « Mettre à jour » du bandeau) : téléchargement du nouvel exe, contrôle de l'empreinte, fermeture, remplacement, redémarrage.
- **En-tête : versions de l'application et de l'add-on**, avec leur état : « à jour » en vert, « x.y.z disponible » en doré, « non installé » en rouge.

## 0.14.0 et application 1.5 — 25 novembre 2026

Première version publiée sur GitHub : https://github.com/TarakBenAbda/Shadsun_Gold_Lens

### Mises à jour en ligne (application 1.5)
- L'application vérifie une fois par jour la dernière version publiée sur GitHub. Si un add-on plus récent existe, le bandeau propose « Installer l'add-on ». Le téléchargement se fait en arrière-plan, puis il reste à faire `/reload` en jeu.
- **Sécurité** :
  - le fichier est refusé si son empreinte SHA-256 ne correspond pas à la fiche de version ;
  - l'archive est refusée si elle contient autre chose que le dossier `ShadsunGoldLens` ;
  - l'installation est annulée si la version du `.toc` diffère de celle annoncée ;
  - rien de téléchargé n'est jamais exécuté ;
  - en cas d'échec, l'add-on déjà installé reste en place.
- Une nouvelle version de l'application est signalée avec un bouton « Télécharger », qui ouvre la page de la version.
- Sans Internet, l'application garde la copie de l'add-on qu'elle contient.
- Publication automatique (onglet « Actions » > « Publier une version ») : GitHub lance tous les tests. S'ils passent, il fabrique le zip de l'add-on et l'exe, puis crée la page de version avec les empreintes.

### Correction : armes et armures sans prix HDV
- **Cause.** Pour chaque HDV, l'add-on gardait une seule photo : la plus récente entre votre scan et les prix téléchargés. Or l'API Blizzard écarte volontairement les objets vendus seulement en version à suffixe ou à bonus, ce qui concerne surtout des armes et des armures. Quand la photo de l'API était plus récente, elle masquait donc tout votre scan, y compris les prix d'équipement qu'il contenait. Résultat : « Prix HDV indisponible » sur les trois HDV.
- **Correction.** Votre scan et l'API sont maintenant fusionnés objet par objet : chaque objet prend la donnée la plus récente qui le contient, avec son âge et sa source réels (« scan, il y a 1 j »). La fusion vaut partout : infobulle, listes, opportunités, HDV » HDV.
- **Variantes seules.** Le moteur de l'application (0.14.0) garde désormais à part le prix le plus bas des objets vendus uniquement en variantes. L'infobulle l'affiche en « dès 4 po (variantes seulement · …) ». Ce prix n'est jamais utilisé pour calculer un bénéfice, car une variante n'est pas l'objet vendu par le PNJ.
- **Limite.** Un objet qui n'est ni dans votre scan, ni dans l'API (ni en variante) reste sans prix : il faut alors un scan complet à l'HDV.

### Logo
- **Fenêtre principale** (bouton de la mini-carte) : grand médaillon de 76 px, préparé pour cette taille (`Media/medaillon.tga`, 128 × 128, ombre portée). Il est posé sur le coin supérieur gauche et déborde du cadre ; la fenêtre reste entièrement visible à l'écran, médaillon compris.
- **Panneau de l'HDV** : la gemme seule (`Media/icon.tga`), lisible en petit.

Auteur : Tarak Ben Abda.

## Application 1.3.4 — 25 novembre 2026

- **Alignement vertical** : dans la fenêtre principale, le bandeau d'en-tête, le bandeau d'état, les trois cartes, le panneau d'informations et la rangée de boutons commencent tous à la même ligne à gauche et finissent à la même ligne à droite. Le panneau de l'assistant suit la même colonne.
- **Ornements centraux sur une seule ligne** : ceux des bandeaux, de la carte du milieu et du panneau d'informations tombent tous sur l'axe central de la colonne. L'étirement des cadres aligne désormais le centre de l'image source sur le centre du bloc, et non plus le centre du morceau découpé (il y avait 2 à 3 px d'écart).
- La rangée de boutons occupe toute la largeur de la colonne.

## Application 1.3.3 — 25 novembre 2026

- Retrait des losanges dorés au milieu du cadre de la fenêtre, en haut et en bas.

## Application 1.3.2 — 25 novembre 2026

- La légende sous le personnage est un hommage au personnage de Tarak, dont c'est l'image en jeu : « Aurelia Shadsun · PvP · Europe » est désormais un texte fixe, identique pour tous les utilisateurs et dans toutes les vues. Elle ne dépend plus des réglages (cela remplace la 1.3.1).

## Application 1.3 — 25 novembre 2026 (visuel)

Add-on inchangé (0.13.0).

- **Symétrie du bandeau d'état** : le losange du haut et l'œil du bas sont maintenant exactement au milieu. Avant, ils étaient décalés vers la gauche parce que les deux bouts du cadre n'ont pas la même largeur (le cercle à gauche). L'étirement place désormais l'ornement central au centre.
- **Nom du personnage** « Aurelia Shadsun », en petit et en écriture élégante (Gabriola sous Windows), avec un fin séparateur doré et sa localisation « PVP · EUROPE » en petites capitales. Il est placé dans un espace libre du décor, sans recouvrir le personnage : à gauche de sa tête dans la fenêtre principale, sous le marteau dans l'assistant.
- **Boutons de l'assistant, du guide de la clé et du journal** habillés du même cadre orné que la fenêtre principale (doré pour l'action principale, bleu pour les autres), avec survol et état grisé.
- **Fenêtre principale réordonnée** :
  - espacements réguliers entre les blocs ;
  - cartes des HDV et panneau d'informations un peu plus hauts ;
  - l'avis « nouvelle version de l'add-on » devient la 4e ligne du panneau d'informations ;
  - rangée de boutons centrée sous le contenu.

## Application 1.2.1 — 25 novembre 2026

- **`construire_exe.bat` réécrit.** Dans la 1.2, une erreur de ma part faisait afficher « dist\ShadsunGoldLens.exe est encore utilisé » juste après l'installation des outils, même quand rien n'était ouvert : le message était atteint dès que l'étape précédente réussissait. Le fichier, désormais, avant de fabriquer :
  1. ferme l'exe et ses processus enfants (mise à jour en cours) ;
  2. ferme une version lancée avec Python (`sgl_app.py`) ;
  3. supprime l'ancien exe ;
  4. s'il est encore bloqué (antivirus, Explorateur), le renomme `ShadsunGoldLens_ancien_….exe` : Windows autorise à renommer un exe utilisé. Cette copie est supprimée à la fabrication suivante.
- **Logo dans un bandeau d'en-tête** en haut à droite, en médaillon à gauche du titre, au lieu d'être seul au milieu de l'écran. Même bandeau dans l'assistant. Le reste de la fenêtre remonte, et les cartes des HDV sont plus hautes.

## Application 1.2 — 25 novembre 2026

Add-on inchangé (0.13.0).

- **Correction du plantage au démarrage de l'exe** (`ValueError: y1 must be greater than or equal to y0`). Sous Windows, la fenêtre n'a pas encore sa taille au premier dessin : les boutons étaient calculés à quelques pixels et le dessin du contour échouait. Désormais :
  - le décor attend que la fenêtre ait sa taille réelle ;
  - les fonctions de dessin acceptent toutes les tailles.
- **`construire_exe.bat`** ferme d'abord l'application si elle tourne encore et supprime l'ancien exe (corrige `PermissionError: [WinError 5] Accès refusé`). Si le fichier reste verrouillé, un message explique quoi fermer.
- **Guide pas à pas pour créer sa clé Blizzard** : bouton « Comment obtenir ma clé ? (pas à pas) » en mode Avancé (étape 2). Il ouvre une fenêtre en 8 écrans, avec « Ouvrir la page » et des boutons « Copier » pour les textes à saisir dans le formulaire.
- **Nouveaux éléments graphiques** (fournis par Tarak), étirés sans déformer les ornements :
  - cadre du bandeau d'état, avec la pastille dans le cercle ;
  - cadres des cartes HDV ;
  - cadre du panneau d'informations et de l'assistant ;
  - boutons ornés (version dorée pour « Mettre à jour maintenant ») ;
  - ornements d'angle et séparateur sous le logo ;
  - emblèmes des HDV : lion, dragon, marteau d'enchères ;
  - icônes des boutons : globe, plume, boussole, coffre, griffon.
- Si une image manque, l'ancien dessin est utilisé.

## 0.13.0 et application 1.1 — 24 novembre 2026

### Add-on 0.13.0
- **Listes : filtre « Meilleur achat »** (deux vues Listes : fenêtre principale et panneau de l'HDV). Valeurs : Tous, PNJ, HDV Alliance, HDV Horde, HDV neutre, Aucune offre sous le prix max. La règle est celle de la case verte ; le nombre d'articles affichés apparaît dans la ligne de résumé.
- Case **« Seulement là où ce personnage peut acheter »** (décochée par défaut) : ignore l'HDV de l'autre faction pour la case verte et pour le filtre.
- **Tri sur toutes les colonnes des listes** : clic sur l'en-tête, flèche de sens ; les objets sans prix restent en bas.
- **Surbrillance de la ligne conservée** au survol de la loupe, du X, du + et du −, dans tous les tableaux.
- **Logo** dans l'en-tête de la fenêtre principale et du panneau de l'HDV. **Icône** (gemme du logo) sur le bouton de la mini-carte et dans la liste des add-ons du jeu.
- **Icônes de faction fournies par le jeu** devant « HDV Alliance / Horde / neutre » dans l'infobulle et l'onglet Marchés (aucun fichier copié).

### Application 1.1
- Nouveau visuel :
  - fond bleu nuit, cadre et ornements dorés ;
  - personnage (Aurelia Shadsun) et logo ;
  - bandeau d'état avec pastille ;
  - cartes des HDV avec symboles originaux (bouclier, haches croisées, pièces) ;
  - boutons dorés ou bleus avec icônes.
- L'assistant prend le même style. Fenêtre redimensionnable, adaptée aux écrans à haute résolution. Aucun logo de Blizzard.
- Icône de l'exe : logo complet en grand, gemme seule en 16 à 48 px.
- Un décor (`assets/fond.jpg`) sera utilisé automatiquement comme fond s'il est ajouté.

## 0.12.0 et application de bureau 1.0 — 24 novembre 2026

### Application de bureau (remplace les fichiers .bat)
- Un seul fichier `ShadsunGoldLens.exe` (Python intégré), ou `Lancer_Shadsun_Gold_Lens.bat` avec le Python du PC.
- **Assistant en 4 étapes** au premier lancement :
  1. dossier de WoW Forever et région trouvés seuls, installation ou mise à jour de l'add-on livré ;
  2. source des prix ;
  3. type de serveur (suggéré d'après le royaume du personnage, vérifiable avec un relevé de l'HDV fait en jeu) ;
  4. mise à jour automatique.
- **Mode simple sans compte** : prix de Forever AH (forever-ah.com, API publique alimentée par l'API Battle.net), une requête par HDV et par heure, mention de la source affichée. **Mode avancé** : clé Blizzard personnelle, rangée dans le Gestionnaire d'identification de Windows (jamais dans un fichier).
- **HDV choisis par type de serveur** : PvP 110 / 113 / 116, Normal 111 / 114 / 117, JdR 119 / 120 / 121, JdR-PvP 123 / 124 / 125. L'étape d'identification n'est plus nécessaire.
- **Fenêtre principale** :
  - état des trois HDV (heure des données, ancienneté, annonces) ;
  - dernière et prochaine mise à jour ;
  - boutons Mettre à jour maintenant, Journal, Paramètres, Dossier AddOns ;
  - bandeau quand une version plus récente de l'add-on est livrée.
- **Icône près de l'horloge** : l'application reste active fenêtre fermée et met à jour toutes les heures. Démarrage avec Windows par la clé « Exécuter » de l'utilisateur, sans le Planificateur de tâches. L'ancienne tâche planifiée est retirée automatiquement.
- Reprise des réglages de l'ancien outil (`C:\ShadsunGoldLens-Prix`). Données dans `%APPDATA%\ShadsunGoldLens`. Instance unique : relancer l'exe fait réapparaître la fenêtre.
- Fabrication de l'exe : `construire_exe.bat` (PyInstaller) ou workflow GitHub Actions fourni.

### Add-on 0.12.0
- Source des prix externes affichée (« Forever AH » ou « API Blizzard ») dans l'infobulle (« Forever AH, il y a 1 h »), l'onglet Marchés et le diagnostic, avec la mention « Prix : Forever AH (forever-ah.com), données de l'API Battle.net de Blizzard ».
- Textes d'aide : « l'application Shadsun Gold Lens » au lieu de l'outil en ligne de commande.

## Outil de prix 0.12.0 — 21 novembre 2026

- **Mise à jour horaire refaite** : sur certains PC, la répétition horaire du Planificateur de tâches ne se déclenche jamais (constaté dans le journal : seuls les lancements à l'ouverture de session et au réveil avaient lieu). La tâche lance désormais une petite boucle résidente, sans fenêtre, 1 minute après l'ouverture de session ; la boucle compte elle-même les heures et lance chaque mise à jour dans un processus séparé (délai de 10 minutes chacun).
- Heure dépassée pendant une veille : rattrapée au réveil (après 90 s, le temps que le réseau revienne). Échec : nouvelle tentative 15 minutes plus tard. Une seule boucle à la fois.
- Relance horaire de secours par la tâche si la boucle s'est arrêtée.
- `7_Etat…` : « Mise à jour horaire : ACTIVE / ARRÊTÉE », dernière réussie, prochaine. `intervalle_minutes` réglable dans le `.ini`.
- Add-on inchangé (0.11.1).

## 0.11.1 — 20 novembre 2026

- **Colonnes « Sacs » et « Vente »** dans tous les tableaux (PNJ » HDV, HDV » PNJ, HDV » HDV), dans la fenêtre principale comme dans le panneau de l'HDV : nombre dans les sacs du personnage connecté et nombre mis en vente à l'HDV (tous vos personnages du serveur ; « ~ » = au plus). Elles remplacent « Poss. » ; banque et autres personnages restent dans l'infobulle (« Possédé »). Tri possible sur les deux colonnes.
- **Outil de prix 0.11.1** : une mise à jour ne peut plus rester bloquée (cause du problème observé : téléchargement figé, tâche « en cours » et heure suivante refusée).
  - Téléchargement : 45 s au plus sans données reçues, 4 minutes au plus par HDV, 3 tentatives, puis erreur claire au journal.
  - Délai global de 10 minutes : au-delà, la mise à jour est abandonnée et notée ; l'heure suivante part normalement.
  - Journal écrit ligne par ligne (on voit où une mise à jour s'arrête) ; durée de chaque HDV notée.
  - Priorité normale (au lieu de basse) pour la tâche ; `5_Activer…` arrête d'abord une exécution bloquée.
  - `7_Etat…` signale une tâche que Windows n'a pas lancée à l'heure prévue.

## 0.11.0 — 20 novembre 2026

### Listes d'achats : boutons + et -
- Un nouveau clic sur **+** ajoute un exemplaire de plus (fini le message « déjà dans la liste »). Bouton **-** juste à côté : retire un exemplaire ; sous 1, l'objet quitte la liste. **Maj+clic** : 5 d'un coup. Alt+clic sur un objet ajoute aussi 1.
- Badge sur le **+** : quantité déjà dans la liste active ; le **-** est grisé si l'objet n'y est pas.
- Message dans le chat et survol des boutons : quantité dans la liste et ce que vous avez déjà (« sacs 2 · banque 5 · autres persos 3 · en vente 6 »).

### Objets en vente à l'HDV
- Vos enchères en cours (mises en vente, pas encore vendues) sont relevées à chaque visite de l'HDV, après chaque mise en vente et chaque annulation, pour chaque personnage du serveur.
- Hors HDV, les messages « un acheteur a été trouvé » et « a expiré » retirent l'annonce. Marchandise vendue en partie : quantité restante inconnue, nombre affiché comme un maximum (« ~19 », « (au plus) »).
- Infobulle : ligne **En vente** sous « Possédé » (détail par personnage, âge du relevé hors HDV ; option dans Paramètres). Onglet Listes : colonne **Vente**. La progression d'une liste compte seulement ce que vous possédez (sacs et banque).
- Infobulle : 12 lignes par défaut (au lieu de 11).

### Outil de prix 0.11.0 : mise à jour horaire fiabilisée
- La tâche lance directement `pythonw.exe` (Python sans fenêtre) : plus de VBScript ni de fichier `.bat` entre Windows et l'outil. Aussi 2 minutes après l'ouverture de votre session.
- `5_Activer_la_mise_a_jour_horaire` lance la tâche par le Planificateur et attend son résultat : « OK : la tâche planifiée fonctionne », ou l'erreur exacte.
- Nouveau **`7_Etat_de_la_mise_a_jour_horaire`** : dernière exécution et son résultat (en clair), prochaine exécution, date du fichier des prix, dernières mises à jour du journal.
- **`journal_maj.txt`** : chaque mise à jour (manuelle ou planifiée) y est notée avec son résultat et, en cas d'erreur, le détail complet.
- Python d'Anaconda lancé sans environnement activé : les bibliothèques de chiffrement sont trouvées automatiquement.

## 0.10.2 — 20 novembre 2026

- **Onglet Listes de la fenêtre principale** : la loupe (utile seulement à l'HDV) est remplacée par les icônes **Aller** (point TomTom vers le meilleur marchand connu) et **Copier** (commande `/tway`), grisées si aucun marchand n'a de coordonnées. La loupe reste dans l'onglet Listes du panneau de l'HDV.
- Nouvelle colonne **PNJ** dans les listes : prix d'achat unitaire chez le meilleur marchand connu (« devise » si payé autrement qu'en or), comparé aux trois HDV ; le moins cher sous votre prix maximum passe en vert, PNJ compris (marchand accessible à votre faction). Marchand et emplacement au survol de la ligne.
- Onglet Listes du panneau de l'HDV toujours à jour à l'ouverture du panneau.

## 0.10.1 — 19 novembre 2026

- **Panneau de l'HDV : onglet Listes** (4ᵉ onglet) : sélecteur de liste, articles avec loupe, « Rechercher toute la liste », ajout, quantité et prix maximum, retrait. Même vue que l'onglet Listes de la fenêtre principale.
- **Ordre des onglets** de la fenêtre principale : Objet, Listes, Opportunités, Marchés, Paramètres, Base & diagnostic.
- **Montants compacts** dans les tableaux (HDV » HDV, PNJ » HDV, HDV » PNJ, listes) : sans cuivre au-delà de 1 po, sans argent au-delà de 100 po ; rentabilité sans décimale au-delà de 100 % et « >999 % » au-delà. Fini les montants coupés (« 490 po 99 |… ») ; détail complet au survol.
- Colonnes d'HDV » HDV réajustées dans le panneau de l'HDV (en-têtes « Rentab. », « Dispo », « Poss. » lisibles) ; texte d'aide de l'onglet Listes plus coupé.

## 0.10.0 — 19 novembre 2026

### Listes d'achats
- **Onglet Listes** (`/sgl listes`) : plusieurs listes communes à tous vos personnages ; nouvelle, renommer, dupliquer, supprimer ; la liste choisie est active.
- Articles : quantité voulue, prix maximum facultatif, progression (« 3 / 5 », possédé par vos personnages du serveur), prix sur l'HDV de votre faction, de l'autre faction et neutre (scan ou API), le moins cher sous votre maximum en vert.
- **Loupe** par article (HDV ouvert) et **Rechercher toute la liste** (articles non obtenus, une seule recherche groupée avec Auctionator) ; icône de retrait ; ajout par ID, nom ou Maj+clic.
- Ajout depuis les tableaux : icône **+** sur chaque ligne (PNJ » HDV, HDV » PNJ, HDV » HDV, onglet et panneau de l'HDV) ; **Alt+clic** sur un objet (sacs, liens du chat, HDV), jamais dans la fenêtre du marchand.
- Infobulle : ligne « Liste » (nom et progression) ; fenêtre du marchand : articles de vos listes entourés en **bleu**. Options dans l'onglet Listes.

### HDV » HDV : avis et gain réaliste
- Colonne et filtre **Avis** : Faction » Neutre = Favorable si l'autre faction paie au moins votre prix de revente chez elle et que le neutre a assez d'objets en vente ; Défavorable si elle paie moins ; À vérifier sans repère ou avec trop peu d'objets en vente. Neutre » Faction = Favorable si l'HDV de revente a assez d'objets en vente, sinon À vérifier. Seuil réglable (« Qté min. (avis) », 3 par défaut). Explication au survol de la ligne.
- Colonne **Gain réal.** : gain calculé sur le plus bas entre votre prix de revente et le repère de l'autre faction (Faction » Neutre).

### Divers
- Bouton **Recharger l'interface** (onglet Marchés et icône de la barre de scan) pour charger les prix de l'API.
- Outil de prix 0.10.0 : `5_Activer_la_mise_a_jour_horaire` / `6_Desactiver_la_mise_a_jour_horaire` (tâche Windows toutes les heures, sans fenêtre, aussi sur batterie) ; noms des types de serveur affichés par `1_Tester`.

## Outil de prix 0.9.1 — 19 novembre 2026

- Les lanceurs `.bat` trouvent Python d'Anaconda / Miniconda (Spyder, Jupyter), de python.org ou le lanceur `py`, sans passer par le raccourci du Microsoft Store ; repli manuel par `python_chemin.txt`.

## 0.9.0 — 19 novembre 2026

### Prix de l'API officielle de Blizzard (HDV de la Horde compris)
- Nouvel outil **`sgl_prix_api.py`** (Python, bibliothèque standard, lancé sur votre PC) : télécharge les annonces des HDV Alliance, Horde et neutre de votre marché par l'API Game Data de Blizzard (`dynamic-forever-<région>`), et écrit le module séparé **Shadsun Gold Lens - Prix** dans AddOns (non effacé par une mise à jour de l'add-on).
- Identification automatique des HDV de votre marché en comparant l'API à vos scans en jeu ; vérification d'un objet dans chaque HDV (`verifier`) ; sens du prix des annonces détecté ; versions à suffixe et enchères sans achat immédiat ignorées ; marchandises incluses.
- Lanceurs Windows (`1_Tester`, `2_Identifier_mes_HDV`, `3_Mettre_a_jour_les_prix`, `4_Mise_a_jour_automatique` pour le Planificateur de tâches) et guide pas à pas `GUIDE-API.md` (création de la clé Battle.net).
- Dans l'add-on : pour chaque HDV, la donnée **la plus récente** entre votre scan et l'API ; source indiquée partout (« API, il y a 1 h » / « scan, il y a 3 h ») : infobulle, Objet, Marchés, barre d'état, icône de minicarte. Prix ignorés si la région du client diffère ; `/sgl diag` donne l'état du module.
- Infobulle : HDV de l'autre faction affiché par défaut (seulement s'il a un prix).

### HDV » HDV : deux sens clairs
- Commutateur **Faction » Neutre** / **Neutre » Faction** (Faction = Alliance ou Horde selon le personnage), à la place du filtre de paire et de la case « transferts directs ».
- En-têtes selon le sens (« Achat alliance », « Revente neutre ») et colonne **Repère** : prix sur l'HDV de l'autre faction, ce que ses joueurs paient chez eux. En orange quand il est inférieur à votre prix de revente au neutre (revente peu probable) ; explication au survol.

## 0.8.0 — 19 novembre 2026

### Marchés par serveur et par HDV, partagés par vos personnages
- Chaque lecture des annonces enregistre une **photo du marché** (prix unitaire le plus bas, quantité en vente, heure, personnage) pour l'HDV choisi : **Alliance**, **Horde** ou **neutre**, rangée **par serveur** et **commune à tout le compte**.
- **Choix de l'HDV** avant le scan (« Scan pour ») : prérempli d'après la zone (Baie-du-Butin, Gadgetzan, Long-guet = neutre), mémorisé pour chaque personnage, avertissement si la zone ne concorde pas ; un changement juste après le scan, HDV encore ouvert, réattribue ce scan.
- **Infobulle** : une ligne par HDV scanné (« HDV Alliance », « HDV neutre », option « autre faction ») avec prix, quantité en vente et âge du scan. Ligne Auctionator conservée pour les objets absents des scans.
- **Prix de revente** (PNJ » HDV, bordure du marchand) : scan du **marché de revente** choisi, sinon Auctionator ; la commission suit ce même marché.
- **Onglet Marchés** : fiche de chaque HDV du serveur (annonces, objets, personnage, âge, Effacer), marché de revente, HDV des scans de ce personnage, options d'infobulle, liste des personnages du serveur (Oublier). Commande `/sgl marches`.
- Stockage compact (un nombre par objet) ; photos supprimées après 30 jours.

### Arbitrage HDV » HDV
- Nouvelle liste (onglet Opportunités et panneau de l'HDV) : acheter sur un HDV, revendre sur un autre du serveur, commission de l'HDV de revente déduite. Filtre de paire ; transferts Alliance <-> Horde marqués « indirects » et masqués par défaut.

### Nombre possédé sur tous vos personnages
- Inventaire de chaque personnage (sacs, banque) enregistré par serveur ; infobulle « Possédé | 8 : Aurelia 3 · Kael 5 » ; colonne « Poss. » de toutes les listes.

### Filtres et interface
- **Catégories de l'hôtel des ventes** dans toutes les listes : catégorie » sous-catégorie » emplacement (armures), noms donnés par le jeu, seules les catégories présentes dans vos données. Remplacent les filtres « Type » et « Profession » (les recettes par profession sont dans Recette » Couture, Recette » Cuisine…).
- Filtre de **qualité minimale** et **recherche par nom** sans accents ni majuscules, dans toutes les listes.
- **Menus déroulants** à la place des boutons cycliques (molette ou clic droit pour passer à la valeur suivante ou précédente) ; **onglets** plats avec repère doré (fenêtre principale, sens d'arbitrage, sources) ; **icônes** avec infobulle à la place des boutons texte (loupe, carte, note) ; icône de l'objet devant chaque nom ; flèche de tri sur la colonne active ; message explicatif quand une liste est vide.
- **Panneau de l'HDV** réorganisé : barre de scan commune en haut (Scan pour, Lire les annonces, Tout arrêter, état), puis trois onglets HDV » PNJ, PNJ » HDV, HDV » HDV.
- Filtres appliqués dès qu'ils changent ; barre d'état de la fenêtre principale avec le marché de revente et l'âge de son scan ; état des scans dans l'infobulle de l'icône de minicarte ; `/sgl diag` et `/sgl hdv` décrivent les marchés et la carte actuelle.
- Infobulle : 11 lignes par défaut (au lieu de 9) pour les lignes d'HDV.

## 0.7.1 — 17 novembre 2026

- **Panneau de l'HDV, sens PNJ » HDV** : même liste que l'onglet Opportunités (tous les filtres et colonnes), avec le bouton Rechercher ; bouton Aller retiré (inutile à l'HDV).
- **Onglet Opportunités** : icônes **Aller** (point TomTom) et **Copier** (commande `/tway`, champ présélectionné pour Ctrl+C) devant chaque objet.
- **Tri par « Poss. »** corrigé dans tous les tableaux (le nombre possédé n'était pas enregistré dans les lignes) ; mis à jour quand les sacs changent.
- **Armes et armures vendues à l'unité** : la référence Classic indiquait des lots de 200 pour les armes de jet (« Petit couteau de lancer » : 15 pc les 200), d'où un achat affiché à 0 pc et de faux bénéfices (+57 po). Le prix est désormais compté pour une unité, comme observé sur Forever.

## 0.7.0 — 17 novembre 2026

- **Recherche corrigée** : le bouton « Rechercher » faisait une recherche exacte et ne trouvait pas les objets à variantes (« Bâtarde aiguisée de l'aigle »…). Recherche non exacte désormais.
- **Prix HDV de l'équipement** : comparaison du prix marchand avec les seules annonces de la version simple (les variantes à suffixe faussaient les opportunités PNJ » HDV : « Tabard », « Gants en étoffe épaisse »…). Sans scan complet, l'historique Auctionator n'est plus utilisé pour les armes et armures.
- **Prix HDV des annonces** prioritaire sur l'historique Auctionator partout (infobulle, opportunités, bordure du marchand), avec l'heure du scan et la quantité en vente.
- **Panneau de l'HDV dans les deux sens** : sélecteur « Sens », nouvelle liste PNJ » HDV avec Rechercher et Aller (TomTom).
- **Nombre possédé** (sacs, banque) : ligne d'infobulle et colonne « Poss. » dans les trois tableaux.
- **Couleur de qualité** des noms d'objets dans les tableaux et la recherche.
- **Icônes de pièces** du jeu pour tous les montants (option).
- **Taille de la fenêtre principale** : « - », « + », « 100 % ».

## 0.6.1 — 16 novembre 2026

- Infobulle : ligne **Métier** pour les composants d'artisanat (métiers déduits de la catégorie d'objet fournie par le jeu ; aucune supposition pour les catégories génériques). Option « Métier (recettes et composants) ».

## 0.6.0 — 16 novembre 2026

- **Fenêtre du marchand** : bordure de couleur autour des objets rentables à revendre à l'HDV (prix réel du marchand, lot, prix Auctionator, commission, rentabilité minimale). Aucun texte sur l'icône. Mise à jour au changement de page, d'onglet (rien sur l'onglet Rachats) et à chaque mise à jour des prix Auctionator.
- Paramètres : activation de la bordure et choix de la couleur (vert, or, bleu, violet).

## 0.5.4 — 16 novembre 2026

- Bouton **Tout arrêter** (remplace « Arrêter la lecture ») et commande `/sgl stop` : arrêt immédiat de la lecture des annonces, de l'analyse de l'historique et des demandes d'informations au serveur ; résultats conservés.
- L'analyse de l'historique devient interruptible.
- Paramètre **Vitesse d'analyse HDV** : Lente (40 demandes/s), Normale (80/s), Rapide (200/s). Il règle le rythme uniquement : aucune limite sur le nombre d'annonces ou d'objets analysés.
- Statut du panneau : nombre de demandes d'informations en file.

## 0.5.3 — 16 novembre 2026

Correction des saccades du jeu après l'utilisation du panneau HDV (y compris hors de l'HDV, jusqu'à la déconnexion).

- **Cause 1 — demandes en masse** : après la lecture des annonces, l'add-on demandait d'un coup au jeu les informations de plusieurs milliers d'objets non chargés. Désormais : file d'attente, 20 demandes toutes les 0,25 s au plus, uniquement HDV ouvert ou pendant une analyse ; file vidée à la fermeture de l'HDV.
- **Cause 2 — recalcul complet périodique** : chaque réponse déclenchait, toutes les 5 s, un recalcul de toutes les opportunités (milliers d'objets). Désormais : seul l'objet reçu est recalculé ; l'affichage est regroupé toutes les 2 s.
- **Cause 3 — mémoire conservée** : les 54 555 annonces lues restaient en mémoire après la fermeture de l'HDV (≈ 5 Mo de petites tables, qui alourdissent le nettoyage automatique de la mémoire du jeu). Elles sont libérées à la fermeture ; seuls les résultats compacts sont gardés. Mesure simulée : 0 Mo conservé.
- Analyse de l'historique sans mise en cache de milliers de prix ; cache des prix plafonné à 2 000 entrées.
- `/sgl diag` : mémoire de l'add-on et nombre de demandes d'infos en attente.

## 0.5.2 — 16 novembre 2026

- **Erreur corrigée — colonne « PNJ / u. »** : pour un objet pas encore chargé par le jeu, l'add-on utilisait le « prix marchand » d'Auctionator (`GetVendorPriceByItemID`), qui est le prix d'**achat** chez un marchand et non le prix de rachat. Toutes les opportunités concernées étaient fausses (ex. Sac lourd marron : 1 po 80 pa affichés au lieu de 50 pa). Seul le prix de vente fourni par le jeu (`C_Item.GetItemInfo`) est désormais utilisé ; un objet non chargé n'est pas listé, puis est ajouté automatiquement quand le jeu fournit son prix.
- **Taille du panneau HDV** : ajustement automatique à l'espace libre à droite de l'HDV (plus de recouvrement), boutons « - », « + », « Auto ».

## 0.5.1 — 16 novembre 2026

Corrections après le premier essai en jeu du panneau HDV.

- **Lecture des annonces qui ne s'arrêtait pas** : le jeu émet plusieurs fois le signal de mise à jour de la liste pendant et après un scan ; chaque signal relançait une lecture complète (54 555 annonces). Désormais : attente de 2 s de calme, une seule lecture, aucune relecture si la liste n'a pas changé.
- La liste n'était plus stable (retri à chaque seconde pendant le chargement des prix de rachat) : recalcul limité à une fois toutes les 5 s, jamais pendant une lecture, position de défilement conservée.
- Nouveau bouton **Arrêter la lecture**, case **Figer la liste**, bouton **Actualiser**, progression affichée (« lecture en cours : 12 000 / 54 555 »).
- Filtre de source en trois boutons visibles : Toutes, Direct (annonces), Historique.
- Bouton « Raccrocher à l'HDV » remplacé par **Replacer à côté de l'HDV**, affiché seulement après un déplacement du panneau.
- Caractères absents de la police du jeu remplacés (la flèche « → » s'affichait comme un carré) : « HDV » PNJ », tiret simple pour les montants négatifs.
- Colonnes de prix et de gain élargies (montants en po tronqués).

## 0.5.0 — 16 novembre 2026

### Nouveautés

- **Arbitrage HDV » PNJ** : repérage des objets vendus à l'HDV moins cher que leur prix de rachat par un marchand.
  - Lecture des annonces en cours après un scan complet (Auctionator ou bouton du panneau, même requête Blizzard, limite de 15 min respectée), en tranches pour ne pas figer le jeu ; calcul par annonce : quantité rentable, coût, gain total.
  - Analyse de l'historique Auctionator sur les ≈ 15 000 objets connus.
  - Panneau **Gold Lens** accolé à la fenêtre de l'hôtel des ventes, bouton de bascule, bouton **Rechercher** (Auctionator, sinon recherche Blizzard). Aucun achat automatique.
  - Onglet Opportunités : sélecteur **Sens : PNJ » HDV / HDV » PNJ**.
  - Ligne d'infobulle « Revente PNJ (HDV » PNJ) » lorsque c'est rentable.
- `/sgl arb` (panneau) et `/sgl hdv` (diagnostic de l'API de l'hôtel des ventes).
- Options : ligne d'arbitrage dans l'infobulle, ouverture automatique du panneau avec l'HDV.

### Modifications

- Signature de l'interface : « Créé par Shadsun » (fenêtres, minicarte, Options > AddOns, message de démarrage, champ Auteur du `.toc`). Le nom de l'auteur reste dans les en-têtes du code.

## 0.4.0 — 16 novembre 2026

Réécriture complète de la v0.3.0 (architecture modulaire `Core/`, `UI/`, `Data/`, `Locale/`).

### Corrections majeures

- **Clignotement des infobulles (cause racine corrigée).** La v0.3.0 ajoutait ses lignes une image plus tard (`C_Timer.After(0)`) puis appelait `Show()`. À chaque reconstruction périodique de l'infobulle par le client, celle-ci s'affichait sans les lignes puis avec : alternance 2 ↔ 8 lignes reproduite hors jeu (12 changements de taille en 6 reconstructions). La v0.4.0 ajoute les lignes **dans le post-call, de façon synchrone** : taille constante (0 changement sur 150 reconstructions simulées).
- Suppression des hooks redondants (`SetHyperlink`, `SetBagItem`, `SetItemByID`, `SetMerchantItem`) qui doublaient le post-call `TooltipDataProcessor`.
- Garde « un bloc par passe » remise à zéro sur `OnTooltipCleared`/`OnHide`, garde de réentrance : plus de lignes dupliquées ni de traitement récursif.
- **Recettes** : l'appel imbriqué de l'objet fabriqué est ignoré ; seul l'objet primaire (la recette, identifiée par son itemID et, dans les sacs, par l'emplacement) est décrit. Le sort enseigné est affiché séparément (Maj).
- **Prix d'achat PNJ** : la v0.3.0 mélangeait tarifs Classic et prix observés remisés (946 écarts pour un même PNJ). La base attribue désormais un prix de base par objet et par lot ; les remises observées sont signalées, les prix modifiés sur Forever sont détectés.
- **« Aucun achat PNJ documenté »** remplacé par quatre statuts honnêtes (confirmé, à vérifier, aucun vendeur confirmé — non définitif, information non disponible).
- Exclusivité de faction calculée sur tous les vendeurs connus, avec niveau de confiance ; plus de conclusion tirée d'un seul vendeur.
- Vendeurs itinérants (9) et vendeurs sans coordonnées (27) identifiés ; les 57 PNJ observés sans faction sont complétés depuis la référence lorsque c'est possible (30 PNJ restent à faction inconnue, signalés comme tels).
- Conditions d'achat CMaNGOS interprétées (réputation, événement saisonnier) au lieu d'un identifiant brut.
- Commission configurable (HDV de faction / neutre) au lieu de 5 % codés en dur ; dépôt non soustrait d'une vente réussie.

### Nouveautés

- Fenêtre à onglets : détail d'objet (tous les marchands, TomTom, carte, commande `/tway`), tableau des opportunités filtrable et triable, paramètres, base & diagnostic.
- Intégration TomTom (`TomTom:AddWaypoint`) avec repli sur le repère natif de la carte.
- Observation automatique des marchands enrichie (faction du PNJ, stock, devise, build), partagée entre personnages.
- Abonnement aux mises à jour Auctionator (`RegisterForDBUpdate`) et âge du prix.
- Icône de minicarte standard (clic gauche : fenêtre, clic droit : paramètres), compartiment d'add-ons, raccourci dans Options > AddOns.
- `/sgl debug`, `/sgl diag` (rapport copiable), `/sgl stats`, `/sgl info`.
- Outil `tools/sgl_build_db.py` : reconstruction documentée et reproductible de la base, fusion de CSV vérifiés et de vos SavedVariables.

### Migration

- Nouvelles SavedVariables de compte `ShadsunGoldLensGlobal`. Les relevés, options et la position de l'icône de la v0.3.0 (`ShadsunGoldLensDB`, par personnage) sont migrés automatiquement une fois ; l'ancien contenu est conservé dans `ShadsunGoldLensDB.legacy030`.

## 0.3.0

Version précédente (développée avec un autre assistant). Voir `AUDIT-v0.3.0.md` dans les sources.
