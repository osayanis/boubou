#!/bin/bash
# Publie une version de Petite Boule sur GitHub (osayanis/petiteboule) :
#   ./publish.sh 0.1.1 "Ce qui change"
# Construit l'app, fait PetiteBoule.zip (mises à jour auto) et PetiteBoule.dmg (installation),
# commit + tag + push, puis crée la release. Les Petite Boule installées se mettent à jour
# toutes seules dans les 6 h (au prochain moment calme à l'écran).
# Pour changer seulement les phrases : modifier messages.json et le pousser sur main, sans version.
set -euo pipefail
cd "$(dirname "$0")"

V="${1:-}"
NOTES="${2:-Petite Boule $V}"
[[ "$V" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "Usage : ./publish.sh X.Y.Z [\"notes\"]"; exit 1; }
gh release view "v$V" -R osayanis/petiteboule >/dev/null 2>&1 && { echo "La version $V est déjà publiée."; exit 1; }

echo "$V" > VERSION
./build.sh

rm -f PetiteBoule.zip PetiteBoule.dmg
ditto -c -k --keepParent "Petite Boule.app" PetiteBoule.zip
STAGE="$(mktemp -d)"
cp -R "Petite Boule.app" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
hdiutil create -srcfolder "$STAGE" -volname "Petite Boule" -fs HFS+ -format UDZO -ov PetiteBoule.dmg >/dev/null
rm -rf "$STAGE"

git add -A
git commit -q -m "Version $V" || true
git tag "v$V"
git push -q origin HEAD && git push -q --tags
gh release create "v$V" PetiteBoule.zip PetiteBoule.dmg -R osayanis/petiteboule --title "Petite Boule $V" --notes "$NOTES"
echo "✅ Petite Boule $V publiée."
