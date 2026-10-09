#!/usr/bin/env bash
# Publie une nouvelle version de l'app Street Medics.
#
#   ./tools/release.sh 1.0.1 "Correction du suivi en arrière-plan"
#   ./tools/release.sh 1.0.1 "Correctif critique" --mandatory
#
# Étapes : incrémente la version, construit l'AAB Play Store signé, puis
# déclare la version sur le serveur (collection app_release) pour que les
# apps installées proposent la mise à jour.
set -euo pipefail

cd "$(dirname "$0")/.."

VERSION="${1:?usage: release.sh <version, ex 1.0.1> [notes] [--mandatory]}"
NOTES="${2:-}"
MANDATORY=false
[[ "${3:-}" == "--mandatory" ]] && MANDATORY=true

# --- 1. version dans pubspec.yaml -------------------------------------------
# versionCode Android = entier qui doit STRICTEMENT augmenter à chaque release.
OLD_VERSION=$(grep -E '^version:' pubspec.yaml | awk '{print $2}')
OLD_NAME="${OLD_VERSION%%+*}"
OLD_CODE="${OLD_VERSION##*+}"
NEW_CODE=$((OLD_CODE + 1))
NEW_VERSION="${VERSION}+${NEW_CODE}"
sed -i "s/^version: .*/version: ${NEW_VERSION}/" pubspec.yaml
echo "==> version ${OLD_VERSION} → ${NEW_VERSION}"

# --- 2. build AAB signé -----------------------------------------------------
export PATH="$PATH:/root/tools/flutter/bin"
export ANDROID_HOME="${ANDROID_HOME:-/usr/lib/android-sdk}"
echo "==> build de l'AAB Play Store"
flutter build appbundle --release

AAB="build/app/outputs/bundle/release/app-release.aab"
echo "==> AAB : ${AAB} ($(du -h "$AAB" | cut -f1))"

# --- 3. déclaration de la version sur le serveur ----------------------------
# Le serveur refuse l'écriture aux non-superusers : on s'authentifie.
PB_URL="${PB_URL:-http://127.0.0.1:8090}"
PB_EMAIL="${PB_EMAIL:-admin@local.dev}"
PB_PASSWORD="${PB_PASSWORD:-}"

if [[ -z "${PB_PASSWORD}" ]]; then
  echo "!! PB_PASSWORD non défini : la version n'est PAS publiée sur le serveur."
  echo "   Relance avec PB_PASSWORD=... $0 $VERSION \"$NOTES\""
  exit 0
fi

TOKEN=$(curl -s -X POST "$PB_URL/api/collections/_superusers/auth-with-password" \
  -H 'Content-Type: application/json' \
  -d "{\"identity\":\"$PB_EMAIL\",\"password\":\"$PB_PASSWORD\"}" \
  | python3 -c 'import sys,json;print(json.load(sys.stdin).get("token",""))')

if [[ -z "$TOKEN" ]]; then
  echo "!! Authentification échouée : version non publiée."
  exit 1
fi

# Un seul record fait foi : on met à jour celui qui existe, sinon on le crée.
EXISTING=$(curl -s "$PB_URL/api/collections/app_release/records?perPage=1" \
  -H "Authorization: $TOKEN" \
  | python3 -c 'import sys,json;i=json.load(sys.stdin).get("items",[]);print(i[0]["id"] if i else "")')

BODY=$(python3 -c "
import json,sys
print(json.dumps({
  'versionCode': $NEW_CODE,
  'versionName': '$VERSION',
  'mandatory': $MANDATORY,
  'notes': '''$NOTES''',
}))
")

if [[ -n "$EXISTING" ]]; then
  curl -s -X PATCH "$PB_URL/api/collections/app_release/records/$EXISTING" \
    -H "Authorization: $TOKEN" -H 'Content-Type: application/json' \
    -d "$BODY" > /dev/null
else
  curl -s -X POST "$PB_URL/api/collections/app_release/records" \
    -H "Authorization: $TOKEN" -H 'Content-Type: application/json' \
    -d "$BODY" > /dev/null
fi

echo "==> version $VERSION (code $NEW_CODE) publiée sur $PB_URL"
echo
echo "Prochaine étape : téléverser $AAB dans la Play Console."
