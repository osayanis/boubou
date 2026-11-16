# Petite Boule 🩺

La mascotte Osa en docteur, toute petite dans un coin de l'écran du Mac. Une station de motivation
pour les études de médecine, et un soutien quand c'est dur.

- **Le matin** : bonjour, les tâches du jour (celles d'hier pas finies sont reportées), les révisions
  du jour selon la **méthode des J** (J1, J3, J7, J14, J30, réglable) et un petit défi bien-être.
- **Dans la journée** (toutes les 1 à 3 h, seulement quand elle est devant l'écran, jamais par-dessus
  un film en plein écran) : « Alors, ça se passe bien ? » → *Oui / Bof / Pas top*, et selon la réponse
  « Tiens bon », « C'est pas grave, on va trouver une solution », respiration guidée (cohérence
  cardiaque, la mascotte gonfle et dégonfle), pause de 5 min, « un tout petit pas ».
  Ou un petit mot : boire, s'étirer, écrire à une amie, un mot doux.
- **Le soir** : le bilan. **Après 23 h** : « va dormir ».
- **Si c'est dur plusieurs jours** : elle propose d'en parler (SPS 0 805 23 23 36, 3040, 3114, 15).
- **Le cabinet** (clic sur la mascotte) : Aujourd'hui · Révisions · Ça va ? (humeur de la semaine,
  boîte à outils, numéros d'aide) · Réglages.
- Glisser la mascotte vers un autre coin (ou un autre écran). Clic droit : menu. Le stéthoscope
  dans la barre des menus la fait revenir si elle est cachée.

Les données restent sur le Mac : `~/Library/Application Support/PetiteBoule/donnees.json`.

## Modifier les phrases (sans publier de version)

Tout ce que dit Petite Boule est dans [`messages.json`](messages.json). Modifie-le et pousse sur `main` :
l'app le relit au lancement puis toutes les 3 h. `{prenom}` = son prénom, `{de}` = le champ `de`.
⚠️ Le dépôt est public : les mots doux (`motsDoux`) sont visibles par tout le monde.

## Développer

```bash
./build.sh                      # → « Petite Boule.app »
./publish.sh 0.1.1 "notes"      # → release GitHub ; les apps installées se mettent à jour seules
.build/release/PetiteBoule apercu /tmp/boule.png   # toutes les humeurs de la mascotte
```

Essayer une scène tout de suite, avec des données à part :

```bash
PETITEBOULE_DOSSIER=/tmp/pb PETITEBOULE_DEMO=matin "./Petite Boule.app/Contents/MacOS/PetiteBoule"
# scènes : accueil matin question bien bof mal respire mot doux pas cabinet revisions cava reglages
```

## Installer sur son Mac

1. Télécharger `PetiteBoule.dmg` de la [dernière release](https://github.com/osayanis/petiteboule/releases/latest),
   glisser Petite Boule dans Applications.
2. Premier lancement : clic droit sur l'app → **Ouvrir** → Ouvrir (l'app n'est pas notariée par Apple).
   Si macOS refuse : Réglages Système → Confidentialité et sécurité → « Ouvrir quand même ».
3. Elle demande le prénom, s'ajoute au démarrage du Mac, et se met à jour toute seule ensuite.
