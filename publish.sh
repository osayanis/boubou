#!/bin/bash
# Publie une version de Boubou sur GitHub (osayanis/boubou) :
#   ./publish.sh 0.1.1 "Ce qui change"
# Construit l'app, fait Boubou.zip (mises à jour auto) et Boubou.dmg (installation),
# commit + tag + push, puis crée la release. Les Boubou installées se mettent à jour
# toutes seules dans les 6 h (au prochain moment calme à l'écran).
# Pour changer seulement les phrases : modifier messages.json et le pousser sur main, sans version.
set -euo pipefail
cd "$(dirname "$0")"

V="${1:-}"
NOTES="${2:-Boubou $V}"
[[ "$V" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "Usage : ./publish.sh X.Y.Z [\"notes\"]"; exit 1; }
gh release view "v$V" -R osayanis/boubou >/dev/null 2>&1 && { echo "La version $V est déjà publiée."; exit 1; }

echo "$V" > VERSION
./build.sh

rm -f Boubou.zip Boubou.dmg
ditto -c -k --keepParent "Boubou.app" Boubou.zip
STAGE="$(mktemp -d)"
cp -R "Boubou.app" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
hdiutil create -srcfolder "$STAGE" -volname "Boubou" -fs HFS+ -format UDZO -ov Boubou.dmg >/dev/null
rm -rf "$STAGE"

git add -A
git commit -q -m "Version $V" || true
git tag "v$V"
git push -q origin HEAD && git push -q --tags
gh release create "v$V" Boubou.zip Boubou.dmg -R osayanis/boubou --title "Boubou $V" --notes "$NOTES"
echo "✅ Boubou $V publiée."
