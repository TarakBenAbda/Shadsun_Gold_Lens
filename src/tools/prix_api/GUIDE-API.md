# Prix des HDV par l'API Blizzard — guide pas à pas (ligne de commande)

Shadsun Gold Lens 0.12.0 · moteur `sgl_prix_api.py` 0.14.0 · Créé par Shadsun.

> **Depuis l'application 1.0, ce guide est facultatif.** L'application (`ShadsunGoldLens.exe`, voir `LISEZ-MOI-APPLICATION.md`) fait tout dans une fenêtre, avec un mode simple sans compte (Forever AH). Pour le mode Avancé, seule l'**étape 2** ci-dessous (créer la clé) sert encore : collez le Client ID et le Client Secret dans l'application. La suite décrit l'ancien fonctionnement par fichiers `.bat`, conservé pour la ligne de commande.

Un add-on WoW ne peut pas accéder à Internet. Cet outil, lancé sur votre PC, télécharge les annonces de vos trois hôtels des ventes (Alliance, Horde, neutre) grâce à l'**API officielle de Blizzard**, puis écrit le module **Shadsun Gold Lens - Prix** dans votre dossier AddOns. L'add-on le lit à la connexion ou après `/reload`.

Ce que vous obtenez : le prix de l'**HDV de la Horde** (impossible à scanner avec un personnage de l'Alliance), et des prix Alliance et neutre à jour sans passer à l'HDV. Pour chaque HDV, l'add-on utilise la donnée la plus récente : votre scan ou l'API.

Temps nécessaire la première fois : 15 à 20 minutes.

---

## Étape 1 — Python

Rien à faire si Python est installé d'une de ces façons : **Anaconda / Miniconda** (Spyder, Jupyter), **python.org** ou le lanceur `py`. Les fichiers `.bat` le trouvent automatiquement et affichent « Python utilisé : … » au démarrage.

Si un lanceur affiche « Python introuvable » :

1. Ouvrez **Spyder** (ou un notebook Jupyter) et tapez dans la console : `import sys; print(sys.executable)`
2. Copiez le chemin affiché (par exemple `C:\Users\Vous\anaconda3\python.exe`).
3. Dans le dossier de l'outil, créez un fichier texte nommé `python_chemin.txt` contenant ce chemin seul, sur une ligne, sans guillemets.

## Étape 2 — Créer votre clé Battle.net (gratuit)

1. Ouvrez **https://develop.battle.net** et cliquez sur **Log In** (en haut à droite). Connectez-vous avec votre compte Battle.net habituel.
2. À la première connexion, lisez et acceptez les conditions d'utilisation de l'API (**API Terms of Use**).
3. Cliquez sur **API Access** (menu du haut), puis sur **Create Client**.
4. Remplissez le formulaire :
   - **Client Name** : `Shadsun Gold Lens`
   - **Redirect URLs** : laissez vide. Si le formulaire refuse, mettez `https://localhost`
   - **Service URL** : laissez vide (ou `https://localhost` si le champ est obligatoire)
   - **Intended Use** (description) : `Usage personnel : prix des hôtels des ventes de WoW Forever pour un add-on.`
   - Cochez la case d'acceptation si elle est présente.
5. Cliquez sur **Save**. La page affiche **Client ID** et **Client Secret**.
6. Copiez les deux dans un fichier texte temporaire. Le secret peut n'être affiché qu'une fois ; si vous le perdez, revenez sur le client et générez-en un nouveau.

Le **Client Secret** est un mot de passe : ne le partagez jamais, ne l'envoyez à personne (moi compris).

## Étape 3 — Installer l'outil

1. Clic droit sur `Shadsun_Gold_Lens_v0.10.0_outil_prix_API.zip`, **Extraire tout…**, destination `C:\` : le dossier `C:\ShadsunGoldLens-Prix` est créé. **Pas** dans le dossier de WoW ni dans AddOns, et de préférence pas sur le Bureau ou dans Documents (souvent synchronisés par OneDrive).
2. Dans ce dossier, copiez `sgl_prix_api.exemple.ini` et renommez la copie en `sgl_prix_api.ini`.
   - Si Windows masque les extensions, activez-les : Explorateur, menu **Affichage**, **Afficher**, **Extensions de noms de fichiers**.

## Étape 4 — Remplir la configuration

Clic droit sur `sgl_prix_api.ini`, **Ouvrir avec**, **Bloc-notes**.

1. Section `[battlenet]` : collez vos valeurs après le signe égal :
   ```
   client_id = votre Client ID
   client_secret = votre Client Secret
   ```
2. Section `[marche]` : `region = eu` et `type_serveur = PvP` (votre marché). Laissez les lignes `hdv_…` vides : l'outil les remplit.
3. Section `[wow]`, ligne `addons` : le chemin de votre dossier `Interface\AddOns` de WoW Forever. Pour le trouver :
   - application Battle.net, **World of Warcraft** (version Forever sélectionnée), roue dentée à côté du bouton **Jouer**, **Afficher dans l'Explorateur** ;
   - ouvrez `_forever_`, puis `Interface`, puis `AddOns` ;
   - cliquez dans la barre d'adresse de l'Explorateur, copiez le chemin et collez-le après `addons =`.
4. Ligne `savedvariables` : même dossier `_forever_`, puis `WTF\Account\<VOTRE_COMPTE>\SavedVariables\ShadsunGoldLens.lua`. `<VOTRE_COMPTE>` est le nom du dossier présent dans `WTF\Account` (souvent un numéro comme `12345678#1`).
5. Enregistrez (**Ctrl+S**) et fermez.

## Étape 5 — Tester la clé

Double-cliquez sur **`1_Tester.bat`**. Vous devez voir :

```
Clé acceptée : jeton d'accès obtenu.
Hôtels des ventes (EU, dynamic-forever-eu) :
   110  Alliance Auction House        HDV Alliance
   111  Horde Auction House           HDV Horde
   ...
```

Quinze HDV sont listés : cinq par faction, un par marché (région et type de serveur). L'étape suivante trouve ceux de **votre** marché.

## Étape 6 — Identifier vos HDV (une seule fois)

L'API ne dit pas quel HDV correspond à « EU PvP ». L'outil le trouve en comparant vos propres scans aux quinze HDV.

1. En jeu, avec Shadsun Gold Lens 0.9.0 : **Lire les annonces** à l'HDV de l'Alliance, et si possible à un HDV neutre (barre de scan du panneau de l'HDV).
2. Tapez `/reload` (ou déconnectez-vous) : le jeu écrit alors vos scans sur le disque.
3. Double-cliquez sur **`2_Identifier_mes_HDV.bat`**. L'outil télécharge les HDV (quelques minutes, environ 9 Mo chacun) et affiche, pour chacun, la part des prix identiques à vos scans :
   ```
   => HDV Alliance = HDV 113 (64 % de prix identiques)
   => HDV neutre = HDV 115 (58 % de prix identiques)
   HDV Horde déduit par position : HDV 114 (à confirmer avec « verifier »)
   ```
4. Les numéros sont enregistrés automatiquement dans `sgl_prix_api.ini`.

**Vérifier l'HDV Horde** (recommandé) : choisissez un objet dont vous connaissez le prix Horde (site, ami, guilde), puis, dans une fenêtre `cmd` ouverte dans le dossier de l'outil :

```
py -3 sgl_prix_api.py verifier 12345
```

(12345 = ID de l'objet, visible avec Maj au survol en jeu). Le prix de chaque HDV s'affiche : celui de votre marché doit correspondre.

## Étape 7 — Mettre à jour les prix

1. Double-cliquez sur **`3_Mettre_a_jour_les_prix.bat`**. L'outil télécharge vos trois HDV et écrit `AddOns\ShadsunGoldLens_Prix`.
2. En jeu : `/reload`, ou le bouton **Recharger** (onglet **Marchés**, ou icône à droite de la barre de scan du panneau de l'HDV).
3. La première fois, vérifiez dans la liste des add-ons (écran des personnages, bouton **AddOns**) que **Shadsun Gold Lens - Prix** est coché.
4. Contrôle : survolez un objet. Vous devez voir par exemple `HDV Horde   15 po 98 pa (18 en vente · API, il y a 1 h)`. L'onglet **Marchés** (`/sgl marches`) affiche une ligne « API Blizzard » par HDV.

Le module est séparé de l'add-on : une mise à jour de Shadsun Gold Lens ne l'efface pas.

## Étape 8 (facultatif) — Mise à jour automatique toutes les heures

1. Double-cliquez sur **`5_Activer_la_mise_a_jour_horaire.bat`**. Windows crée la tâche « Shadsun Gold Lens - prix HDV » et la lance tout de suite ; l'outil attend la première mise à jour (3 minutes au plus).
2. Message attendu : **« OK : la mise à jour horaire fonctionne »**. Sinon, la fenêtre affiche l'erreur exacte : faites une capture et envoyez-la. Vous pouvez ensuite fermer la fenêtre.
3. Fonctionnement : la tâche lance, sans fenêtre, une petite boucle qui reste en arrière-plan tant que votre session est ouverte. C'est elle qui compte les heures (pendant que vous jouez ou non) et lance une mise à jour par heure. Une heure dépassée pendant une veille est rattrapée au réveil. La boucle redémarre seule 1 minute après chaque ouverture de session (et la tâche la relance dans l'heure si elle s'est arrêtée). Rien à réactiver après un redémarrage.
4. En jeu : bouton **Recharger** (onglet Marchés ou barre de scan) ou `/reload` quand vous voulez les derniers prix. Le jeu ne relit le fichier des prix qu'à ce moment-là.
5. Contrôle à tout moment : **`7_Etat_de_la_mise_a_jour_horaire.bat`** (« Mise à jour horaire : ACTIVE », dernière réussie, prochaine, date du fichier des prix, journal). Dans le Planificateur, la tâche apparaît « en cours » : c'est normal.
6. Pour arrêter : double-clic sur **`6_Desactiver_la_mise_a_jour_horaire.bat`**.
7. Intervalle : `intervalle_minutes` dans la section `[outil]` du fichier `.ini` (60 par défaut, 30 au minimum), puis relancez `5_Activer…`.

Consommation : environ 30 secondes par heure, quelques Mo téléchargés, puis plus rien. Une mise à jour bloquée (réseau, serveur de Blizzard) est abandonnée au bout de 10 minutes au plus et notée au journal ; l'heure suivante repart normalement. Chaque mise à jour est notée dans **`journal_maj.txt`** (dossier de l'outil). Ne déplacez pas le dossier de l'outil, ni Python, après l'activation (sinon, relancez `5_Activer…`). Après une mise à jour de l'outil, relancez aussi `5_Activer…`.

---

## Dépannage

| Message | Cause et solution |
|---|---|
| « Python est introuvable ; exécutez sans arguments à installer à partir du Microsoft Store » | Ancien lanceur (outil 0.9.0) : utilisez l'outil 0.9.1, qui trouve Python d'Anaconda. Sinon, voir l'étape 1 (`python_chemin.txt`). |
| `Clé refusée (401)` | Client ID ou Secret incorrect (espace en trop, secret régénéré). Recopiez-les. |
| `Fichier de configuration introuvable` | `sgl_prix_api.ini` absent ou mal nommé (`.ini.txt` si les extensions sont masquées). |
| `Introuvable (404)` | Route de l'API modifiée par Blizzard (API de Forever non documentée). Envoyez-moi le message. |
| `aucun HDV ne correspond nettement` | Scan trop ancien ou trop petit : relisez les annonces en jeu, `/reload`, relancez l'identification. |
| `Dossier AddOns introuvable` | Ligne `addons` incorrecte : vérifiez le chemin (étape 4). |
| Rien en jeu après `/reload` | Module décoché dans la liste des add-ons, ou onglet Marchés : « Prix API ignorés » (région du client différente de celle de l'outil). |

## Pour un autre joueur, un autre marché

- Chacun crée **sa propre clé** (étape 2) : ne partagez jamais la vôtre.
- `region = us` pour l'Amérique, `type_serveur` = libellé affiché en jeu (PvP, Normal, JdR, JdR JcJ).
- L'identification fonctionne avec les scans de n'importe quelle faction. Sans aucun scan, utilisez `verifier` sur un objet dont vous connaissez le prix, puis renseignez à la main `hdv_alliance`, `hdv_horde` et `hdv_neutre`.

## Données et limites

- Pour chaque objet : prix unitaire le plus bas et quantité totale en vente. Objets à variantes (« … de l'aigle ») : version simple seulement. Enchères sans achat immédiat ignorées.
- L'API de Forever n'est pas documentée par Blizzard et peut changer. Fréquence de mise à jour des annonces côté Blizzard : non publiée (environ une heure sur les autres versions du jeu).
- Les prix sont ceux du moment du relevé : vérifiez toujours dans l'HDV avant d'acheter.
- Données conservées 30 jours au plus ; aucune donnée n'est envoyée ailleurs que vers l'API de Blizzard.
