# Shadsun Gold Lens — application de bureau 1.6.1

Auteur : Tarak Ben Abda — novembre 2026

L'application remplace les fichiers `.bat` de l'ancien outil de prix. Une fenêtre suffit pour :
- installer et mettre à jour l'add-on ;
- choisir la source des prix et le type de serveur ;
- mettre à jour les prix des trois HDV (Alliance, Horde, neutre) toutes les heures, en arrière-plan.

## Pour un ami : ce qu'il lui faut

1. **WoW Forever**, installé normalement.
2. **Le fichier `ShadsunGoldLens.exe`**, téléchargé sur la page des versions : https://github.com/TarakBenAbda/Shadsun_Gold_Lens/releases/latest. Il contient l'add-on et Python, il n'y a rien d'autre à installer.

C'est tout : pas de compte développeur, pas de Python, pas de dossier à copier.

**Où que vous ayez enregistré l'exe**, au premier lancement il s'installe lui-même dans `%LOCALAPPDATA%\Programs\ShadsunGoldLens` et crée le raccourci « Shadsun Gold Lens » sur le Bureau et dans le menu Démarrer. Utilisez ensuite ce raccourci ; le fichier téléchargé peut être supprimé. Relancer un ancien exe téléchargé ouvre simplement la version installée.

### Premier lancement

1. Double-cliquez sur `ShadsunGoldLens.exe`.
2. Si Windows affiche **« Windows a protégé votre ordinateur »**, c'est normal : le fichier n'est pas signé (un certificat de signature coûte 100 à 300 $ par an). Cliquez **« Informations complémentaires »**, puis **« Exécuter quand même »**. Cela n'arrive qu'une fois.
3. L'assistant s'ouvre, en 4 étapes :
   1. **Installation.** Le dossier de WoW Forever et la région sont trouvés seuls ; sinon, « Parcourir… » et choisissez le dossier « World of Warcraft ». L'add-on est copié dans `_forever_\Interface\AddOns`.
   2. **Source des prix.** Laissez **« Simple, sans compte »**, qui prend les prix de Forever AH (forever-ah.com). Le mode « Avancé » utilise votre propre clé Blizzard. Pour la créer, cliquez **« Comment obtenir ma clé ? (pas à pas) »** : un guide de 8 écrans vous accompagne, avec des boutons pour ouvrir la bonne page et copier les textes à saisir.
   3. **Mon marché.** Choisissez votre type de serveur (Normal, PvP, JdR, JdR-PvP). Il est souvent suggéré d'après votre personnage. Le bouton « Vérifier avec mon relevé de l'HDV » confirme le choix si vous avez déjà lu les annonces en jeu une fois (puis `/reload`).
   4. **Mise à jour automatique.** Toutes les heures, démarrage avec Windows et icône près de l'horloge sont cochés par défaut.
4. Cliquez **« Terminer »** : la première mise à jour part tout de suite.
5. En jeu, faites `/reload` (ou utilisez le bouton « Recharger » de l'onglet Marchés) pour charger les prix.

### Ensuite

- L'application tourne en arrière-plan : c'est l'**icône de pièce d'or** près de l'horloge.
  - Clic : ouvrir la fenêtre.
  - Clic droit : « Mettre à jour maintenant » ou « Quitter ».
- Fermer la fenêtre ne quitte pas l'application. Pour l'arrêter, utilisez « Quitter ».
- Elle redémarre seule avec Windows. Il n'y a rien à réactiver.
- Pour tout changer plus tard (type de serveur, source, intervalle), utilisez **« Paramètres »**.

## Fenêtre principale

Le décor reprend le personnage et le logo de Shadsun Gold Lens : fond bleu nuit, cadres et boutons ornés, cartes des trois HDV avec leurs emblèmes (lion, dragon, marteau d'enchères). Les images sont dans `assets` ; aucun logo de Blizzard n'y figure. La fenêtre se redimensionne librement.

**Personnaliser le fond :** placez une image de décor sans texte, nommée `fond.jpg` (environ 1536 × 1024), dans le dossier `assets`, puis refabriquez l'exe. Elle remplace le fond dégradé.

| Élément | Rôle |
|---|---|
| Trois cartes (Alliance, Horde, neutre) | Numéro de l'HDV, heure des données, ancienneté, nombre d'annonces |
| Dernière et prochaine mise à jour | Rythme réel de la mise à jour automatique |
| Mettre à jour maintenant | Mise à jour immédiate (environ 10 à 60 secondes) |
| Journal | Détail de chaque mise à jour et de chaque erreur |
| Paramètres | Rouvre l'assistant avec les réglages actuels |
| Dossier AddOns | Ouvre le dossier des add-ons du jeu |
| Bandeau « Add-on : version … disponible » | Installe la version de l'add-on livrée avec l'application |

## Où sont les données

- **Réglages, journal, cache :** `%APPDATA%\ShadsunGoldLens`. L'exe peut donc être rangé n'importe où (Bureau, Téléchargements…).
- **Clé Blizzard (mode avancé) :** dans le Gestionnaire d'identification de Windows (entrée « ShadsunGoldLens/battlenet »), jamais dans un fichier.
- **Prix pour le jeu :** `AddOns\ShadsunGoldLens_Prix\Prix.lua`, réécrit à chaque mise à jour.

## Sources des prix

| Mode | Source | Il faut | Remarques |
|---|---|---|---|
| Simple (par défaut) | Forever AH (forever-ah.com) | Rien | Site gratuit qui lit l'API Battle.net. Environ une requête par seconde au plus, comme le site le demande. La mention « Prix : Forever AH (forever-ah.com) » est affichée dans l'application et dans l'add-on. |
| Avancé | API Blizzard | Un compte développeur (gratuit) | Ne dépend d'aucun site tiers. Chaque joueur crée sa propre clé : une clé secrète ne se partage pas. |

Si Forever AH change ou ferme, le journal l'indique. Il suffit alors de passer en mode Avancé dans « Paramètres ».

## Types de serveur et HDV

| Type de serveur | Alliance | Horde | Neutre |
|---|---|---|---|
| PvP | 110 | 113 | 116 |
| Normal | 111 | 114 | 117 |
| JdR (RP) | 119 | 120 | 121 |
| JdR-PvP (RP-PvP) | 123 | 124 | 125 |
| Autre | 112 | 115 | 118 |

L'API liste les 15 HDV pour tous les types de serveur : l'application les choisit donc par leur numéro. La correspondance EU PvP 110 / 113 / 116 a été vérifiée en jeu.

## Mises à jour

- **Add-on** : l'application vérifie une fois par jour la dernière version publiée sur GitHub. Si elle est plus récente que l'add-on installé, le bandeau du panneau d'informations propose « Installer l'add-on ». L'archive téléchargée est vérifiée avant installation : empreinte SHA-256, contenu limité au dossier `ShadsunGoldLens`, version annoncée. En jeu, faites ensuite `/reload`.
- **Application** : une nouvelle version est signalée dans le même bandeau. Le bouton **Mettre à jour** télécharge le nouvel exe, vérifie son empreinte, ferme l'application, la remplace et la relance : rien à chercher ni à copier. Lancée avec Python (`Lancer_Shadsun_Gold_Lens.bat`), l'application propose seulement « Télécharger ».
- **En-tête** : versions de l'application et de l'add-on, avec leur état : « à jour » (vert), « x.y.z disponible » (doré), « non installé » (rouge).
- Sans Internet, rien ne change : l'application garde la copie de l'add-on qu'elle contient.

## Pour Tarak : passer de l'ancien outil à l'application

1. Lancez l'application : soit `ShadsunGoldLens.exe`, soit `Lancer_Shadsun_Gold_Lens.bat` avec votre Python.
2. À l'étape 1, laissez cochée **« Reprendre les réglages de l'ancien outil »** : la clé et le type de serveur viennent de `C:\ShadsunGoldLens-Prix`.
3. À l'étape 4, l'ancienne tâche planifiée est arrêtée et supprimée automatiquement.
4. Le dossier `C:\ShadsunGoldLens-Prix` peut ensuite être supprimé (gardez-le si vous voulez encore les commandes en ligne de commande).

### Fabriquer l'exe à partager (une seule fois)

- **Sur votre PC :** double-clic sur `construire_exe.bat`. Au premier lancement, l'exe produit s'installe à l'emplacement fixe, comme celui de GitHub. Il ferme d'abord tout ce qui peut bloquer l'ancien exe (application, mise à jour en cours) ; si l'exe reste bloqué, il est mis de côté sous le nom `ShadsunGoldLens_ancien_….exe` et supprimé à la fabrication suivante. Il installe PyInstaller, pystray et Pillow dans votre Python, puis produit `dist\ShadsunGoldLens.exe` en 1 à 3 minutes.
- **Ou sur GitHub :** chaque version publiée (onglet « Actions » > « Publier une version », voir `.github/workflows/publier.yml`) fabrique l'exe et le met sur la page de version, après avoir lancé tous les tests. Le fichier `construire-application.yml` fabrique un exe d'essai à la demande (onglet « Actions »).

Taille : 20 à 30 Mo (Python intégré). Certains antivirus se méfient des exe fabriqués avec PyInstaller. En cas de blocage, ajoutez une exception ou envoyez le fichier par un lien de téléchargement plutôt qu'en pièce jointe.

## Dépannage

| Problème | Solution |
|---|---|
| « Dossier _forever_ introuvable » | « Parcourir… » et choisissez le dossier « World of Warcraft » qui contient `_forever_`. |
| « Installation impossible » | Fermez le jeu (il peut verrouiller des fichiers), puis réessayez. |
| La mise à jour échoue | Ouvrez « Journal ». Un nouvel essai a lieu 15 minutes plus tard. Si Forever AH est indisponible, passez en mode Avancé. |
| `construire_exe.bat` : « Accès refusé » sur `dist\ShadsunGoldLens.exe` | L'exe tourne encore : clic droit sur l'icône près de l'horloge, « Quitter » ; fermez aussi l'Explorateur ouvert sur `dist`. Relancez. |
| Pas de nouveaux prix en jeu | `/reload` : le jeu ne relit les prix qu'au chargement de l'interface. |
| Pas d'icône près de l'horloge | Elle est peut-être cachée sous la flèche « ^ » de la barre des tâches : faites-la glisser à côté de l'horloge. |
