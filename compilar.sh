#!/bin/bash
# Compila a Nexa no GitHub Actions (macos-15) e baixa o resultado em build/Nexa.ipa.
# Uso: ./compilar.sh
set -euo pipefail
cd "$(dirname "$0")"

gh workflow run build.yml --ref main
sleep 6
RUN=$(gh run list --workflow build.yml --limit 1 --json databaseId --jq '.[0].databaseId')
echo "build $RUN: https://github.com/breroch10/nexa-ios/actions/runs/$RUN"

if ! gh run watch "$RUN" --exit-status --interval 20 >/dev/null; then
  gh run view "$RUN" --log-failed 2>/dev/null | tail -80 || true
  gh run view "$RUN" | tail -15
  exit 1
fi

mkdir -p build
rm -f build/Nexa.ipa
gh run download "$RUN" -n Nexa -D build
ls -la build/Nexa.ipa
