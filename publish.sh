#!/bin/bash
# Publie une version de Mochi sur GitHub (osayanis/mochi) :
#   ./publish.sh 0.1.1 "Ce qui change"
# Construit l'app, fait Mochi.zip (mises à jour auto) et Mochi.dmg (installation),
# commit + tag + push, puis crée la release. Les Mochi installées se mettent à jour
# toutes seules dans les 6 h (au prochain moment calme à l'écran).
# Pour changer seulement les phrases : modifier messages.json et le pousser sur main, sans version.
set -euo pipefail
cd "$(dirname "$0")"

V="${1:-}"
NOTES="${2:-Mochi $V}"
[[ "$V" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "Usage : ./publish.sh X.Y.Z [\"notes\"]"; exit 1; }
gh release view "v$V" -R osayanis/mochi >/dev/null 2>&1 && { echo "La version $V est déjà publiée."; exit 1; }

echo "$V" > VERSION
./build.sh

rm -f Mochi.zip Mochi.dmg
ditto -c -k --keepParent "Mochi.app" Mochi.zip
STAGE="$(mktemp -d)"
cp -R "Mochi.app" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
hdiutil create -srcfolder "$STAGE" -volname "Mochi" -fs HFS+ -format UDZO -ov Mochi.dmg >/dev/null
rm -rf "$STAGE"

git add -A
git commit -q -m "Version $V" || true
git tag "v$V"
git push -q origin HEAD && git push -q --tags
gh release create "v$V" Mochi.zip Mochi.dmg -R osayanis/mochi --title "Mochi $V" --notes "$NOTES"
echo "✅ Mochi $V publiée."
