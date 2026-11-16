# Mochi 🩺

La mascotte Osa en docteur, toute petite dans un coin de l'écran du Mac de Jeanne : une station de
motivation pour les études de médecine, un soutien quand c'est dur, et un fil avec l'OsaNotch de Yanis.

## Ce que fait Mochi

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
| **Double-clic** | Mochi va se coucher dans son petit lit en bas à droite et **ne dit plus rien**. Un clic le réveille. |
| Passer la souris dessus en va-et-vient | Il se fait caresser : yeux en cœur, petits cœurs |
| Le prendre et le secouer | Tournis… et l'OsaNotch de Yanis affiche **« Jeanne pense à vous 💕 »** |
| Le glisser | Il file au coin le plus proche (même sur un autre écran) |
| Panneau → Respirer / S'étirer / Bulles / Focus / 💧 | Cohérence cardiaque 1 min, étirements guidés, 30 s de bulles anti-stress à éclater, focus 25 min silencieux, compteur de verres d'eau |

Et quand **Yanis clique 3 fois sur la mascotte de son OsaNotch**, Mochi fait une pirouette, des yeux en
cœur, une fontaine de cœurs : « Yanis pense à toi 💕 » (s'il dort, seulement des cœurs, et elle le saura
au réveil).

## Le fil Mochi ↔ OsaNotch

Par le relais « Amis » du serveur OsaDrop (socket.io, `friend-send`). Mochi écoute sur son propre code à
6 chiffres et écrit au code de l'OsaNotch de Yanis (`lien` dans `messages.json`). Il se présente tout seul
(`mochi_hello`) : OsaNotch (≥ 1.0.13) l'enregistre, et ce n'est qu'alors que les 3 clics sur sa mascotte
envoient un cœur — la fonction n'existe que chez Yanis. Un message qui n'a pas pu partir (Mac éteint)
repart à la reconnexion, pendant 12 h.

## Modifier les phrases (sans publier de version)

Tout ce que dit Mochi est dans [`messages.json`](messages.json) (et `evenements` pour les dates de fête,
format `MM-JJ`). Modifie-le et pousse sur `main` : l'app le relit au lancement puis toutes les 3 h.
⚠️ Le dépôt est public : tout ce fichier est visible de tous.

## Développer

```bash
./build.sh                       # → Mochi.app
./publish.sh 0.2.1 "notes"       # → release GitHub ; les Mochi installés se mettent à jour seuls
.build/release/Mochi apercu /tmp/m.png   # toutes les humeurs ;  `Mochi lit /tmp/lit.png` : le lit
MOCHI_DOSSIER=/tmp/m MOCHI_DEMO=matin ./Mochi.app/Contents/MacOS/Mochi
# scènes : matin question bien bof mal respire etire bulles focus dodo reveil caresse secoue yanis anniversaire eau panneau idle
```

⚠️ Lancer Mochi sur le Mac de Yanis l'appaire à l'OsaNotch de Yanis à la place de celui de Jeanne
(jusqu'au prochain lancement du sien). Pour nettoyer : `defaults delete com.osalabs.mochi`.

## Installer chez Jeanne

1. `Mochi.dmg` depuis la [dernière release](https://github.com/osayanis/mochi/releases/latest) → glisser dans Applications.
2. Premier lancement : clic droit → **Ouvrir** (app non notariée). Sinon Réglages Système → Confidentialité et sécurité → « Ouvrir quand même ».
3. Mochi dit bonjour, s'ajoute au démarrage du Mac et se met à jour tout seul ensuite.

Données : `~/Library/Application Support/Mochi/donnees.json` (rien ne quitte le Mac, sauf les petits
messages « pense à toi »).
