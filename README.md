# Boubou 🩺

La mascotte Osa en docteur, toute petite dans un coin de l'écran du Mac de Jeanne : une station de
motivation pour les études de médecine, un soutien quand c'est dur, et un fil avec l'OsaNotch de Yanis.

## Ce que fait Boubou

- **Le matin** : bonjour, ses tâches (celles d'hier pas finies sont reportées), ses révisions du jour
  (**méthode des J** : J1, J3, J7, J14, J30) et un défi bien-être.
- **Dans la journée**, seulement quand elle est devant l'écran et jamais par-dessus le plein écran :
  « Alors, ça se passe bien ? » 😊 / 😐 / 😟 → « Tiens bon », « C'est pas grave, on va trouver une
  solution », respiration guidée, pause, « un tout petit pas ». Ou un petit mot (eau, étirements…).
- **Le soir** : le bilan. **Dès 22 h 30** : « va dormir ».
- **Le 8 octobre** : chapeau de fête, confettis et cœurs pour l'anniversaire de couple.
- **Quand on ne s'occupe pas de lui** : il s'étire, regarde autour, sautille, danse, bâille.
- Si c'est dur plusieurs jours de suite : SPS 0 805 23 23 36, 3040, 3114, 15.

## Ce qu'elle peut faire avec lui

| Geste | Effet |
|---|---|
| Clic | Le panneau : sa liste du jour, ajouter (Entrée = tâche, « Cours » = révisions J), pauses, « ça va ? » |
| **Double-clic** | Boubou va se coucher dans son petit lit en bas à droite et **ne dit plus rien**. Un clic le réveille. |
| Passer la souris dessus en va-et-vient | Il se fait caresser : yeux en cœur, petits cœurs |
| Le prendre et le secouer | Tournis… et l'OsaNotch de Yanis affiche **« Jeanne pense à vous 💕 »** |
| Le glisser | Il file au coin le plus proche (même sur un autre écran) |
| Panneau → Respirer / S'étirer / Bulles / Focus / 💧 | Cohérence cardiaque 1 min, étirements guidés, 30 s de bulles anti-stress à éclater, focus 25 min silencieux, compteur de verres d'eau |

Et quand **Yanis clique 3 fois sur la mascotte de son OsaNotch**, Boubou fait une pirouette, des yeux en
cœur, une fontaine de cœurs : « Yanis pense à toi 💕 » (s'il dort, seulement des cœurs, et elle le saura
au réveil).

## Boubou, on l'élève à deux (0.4)

Onglet **Boubou** du panneau (ou clic droit → « S'occuper de Boubou »). L'état vit sur
`boubou.osalabs.fr` (dépôt privé `boubou-site`, contrat dans `docs/foyer.md`) : Jeanne s'en occupe ici,
Yanis depuis l'onglet 🥕 de son OsaNotch (≥ 1.0.14).

- **4 jauges** : ventre, câlins, toilette, énergie. Elles baissent doucement (presque pas la nuit).
  Boubou ne meurt jamais : laissé à l'abandon, il **s'enrhume** (écharpe, nez qui coule) et il faut
  une soupe, un velouté ou une tisane pour le guérir.
- **Ses besoins se voient sur lui** : petite bulle 🍽️ 🛁 💤 au-dessus de sa tête, mine inquiète, taches
  quand il est sale, et il le dit de temps en temps (« J'ai un petit creux… »).
- **Potager** de 6 cases à deux : planter, arroser (pousse 35 % plus vite), récolter.
- **Carottes sauvages** : toutes les 90 min une carotte pousse à côté de Boubou sur le bureau, un clic
  pour l'arracher (8 % de chances : une carotte dorée ✨).
- **Cuisine** : 2 ou 3 ingrédients dans la marmite → une des 17 recettes (crêpes, soupe de carottes,
  gâteau, velouté de potiron…) ou un plat mystère. Carnet de recettes à découvrir, plats au frigo.
- **Étoiles ⭐** : gagnées en travaillant (tâche +2, révision +3, focus +3, défi +2, bulles et
  respiration +1 ; 40 par jour), dépensées à l'épicerie. Yanis, lui, fait les **courses** 1 fois par jour.
- **Niveaux** : P1 → Externe → Interne → Docteur → Chef de clinique → Professeur, chacun débloque un
  accessoire (toque, écharpe, bonnet, lunettes, nœud papillon, couronne de fleurs) dans la garde-robe.
- **Soins animés** : bain (baignoire + canard), marmite qui mijote, câlins (caresser Boubou compte aussi),
  jouer = les bulles, dodo (double-clic) synchronisé avec le foyer.
- **Scènes en 3D (0.5)** : bain, repas, cuisine, passage de niveau, et tout ce que fait Yanis (courses au
  marché avec le chariot, potager…) se jouent sur une petite île qui flotte à côté de Boubou (`Scenes.swift`,
  recopié dans OsaNotch). Le potager du panneau est dessiné (bacs en bois, plantes qui poussent vraiment), et les
  cartes penchent vers la souris. Aperçu : `.build/release/Boubou apercu-scenes /tmp/scenes [bain,courses…]`.
- **Potager et cuisine interactifs (0.6)** (`Interactif.swift`, recopié dans OsaNotch) : une île en 3D avec
  6 bacs ; on prend l'arrosoir et on le glisse au-dessus d'un bac (il penche, l'eau coule), on glisse un sachet
  de graines dans un bac vide, on clique un légume mûr pour le récolter. La cuisine : une marmite sur le feu où
  l'on glisse les ingrédients de l'étagère (ils flottent dans la soupe, clic = on le ressort), puis « Touiller ».
  Aperçu : `.build/release/Boubou apercu-interactif /tmp`.
- **Journal à deux** : chaque geste s'écrit ; quand Yanis s'est occupé de Boubou, Boubou le raconte
  (« Yanis m'a fait des crêpes ! »).
- **💌 Un mot pour Yanis** : Jeanne écrit, Yanis le reçoit en bannière dans son notch. À sens unique :
  il ne peut pas répondre par là.

## Le fil Boubou ↔ OsaNotch

Par le relais « Amis » du serveur OsaDrop (socket.io, `friend-send`). Boubou écoute sur son propre code à
6 chiffres et écrit au code de l'OsaNotch de Yanis (`lien` dans `messages.json`). Il se présente tout seul
(`mochi_hello`) : OsaNotch (≥ 1.0.13) l'enregistre, et ce n'est qu'alors que les 3 clics sur sa mascotte
envoient un cœur — la fonction n'existe que chez Yanis. Un message qui n'a pas pu partir (Mac éteint)
repart à la reconnexion, pendant 12 h. Depuis 0.4, `mochi_hello` porte aussi le secret du foyer et
`boubou_maj` prévient l'autre app qu'il faut relire l'état (le serveur reste la source de vérité).

## Modifier les phrases (sans publier de version)

Tout ce que dit Boubou est dans [`messages.json`](messages.json) (et `evenements` pour les dates de fête,
format `MM-JJ`). Modifie-le et pousse sur `main` : l'app le relit au lancement puis toutes les 3 h.
⚠️ Le dépôt est public : tout ce fichier est visible de tous.

## Développer

```bash
./build.sh                       # → Boubou.app
./publish.sh 0.2.1 "notes"       # → release GitHub ; les Boubou installés se mettent à jour seuls
.build/release/Boubou apercu /tmp/m.png   # toutes les humeurs ;  `Boubou lit /tmp/lit.png` : le lit
BOUBOU_DOSSIER=/tmp/m BOUBOU_DEMO=matin ./Boubou.app/Contents/MacOS/Boubou
# scènes : matin question bien bof mal respire etire bulles focus dodo reveil caresse secoue yanis anniversaire eau panneau idle
#          bain cuisine carotte niveau foyer mot
# le foyer, jamais contre la prod (le premier secret inscrit devient LE foyer) :
#   cd ../boubou-site && BOUBOU_DEV=1 PORT=3083 BOUBOU_DATA=/tmp/fy node server.js
BOUBOU_API=http://127.0.0.1:3083 .build/release/Boubou essai-foyer            # tous les gestes, de bout en bout
.build/release/Boubou apercu-foyer etat.json jeu.json /tmp/captures           # l'onglet Boubou hors écran
```
Une Boubou lancée avec `BOUBOU_DOSSIER` ou `BOUBOU_DEMO` sans `BOUBOU_API` ne se connecte pas au foyer.

⚠️ Lancer Boubou sur le Mac de Yanis l'appaire à l'OsaNotch de Yanis à la place de celui de Jeanne
(jusqu'au prochain lancement du sien). Pour nettoyer : `defaults delete com.osalabs.boubou`.

## Installer chez Jeanne

1. `Boubou.dmg` depuis la [dernière release](https://github.com/osayanis/boubou/releases/latest) → glisser dans Applications.
2. Premier lancement : clic droit → **Ouvrir** (app non notariée). Sinon Réglages Système → Confidentialité et sécurité → « Ouvrir quand même ».
3. Boubou dit bonjour, s'ajoute au démarrage du Mac et se met à jour tout seul ensuite.

Données : `~/Library/Application Support/Boubou/donnees.json` (rien ne quitte le Mac, sauf les petits
messages « pense à toi »).
