#!/bin/bash
# Compila a Nexa no GitHub Actions (macos-15) e baixa o resultado em build/Nexa.ipa.
# Uso: ./compilar.sh
set -euo pipefail
cd "$(dirname "$0")"

# pega só o build disparado AGORA por este script (nunca um build de push ou um anterior)
INICIO=$(date -u -v-30S +%Y-%m-%dT%H:%M:%SZ)
gh workflow run build.yml --ref main
RUN=""
for _ in $(seq 1 20); do
  sleep 3
  RUN=$(gh run list --workflow build.yml --event workflow_dispatch --limit 5 --json databaseId,createdAt \
    --jq "[.[] | select(.createdAt >= \"$INICIO\")][0].databaseId // empty")
  [ -n "$RUN" ] && break
done
if [ -z "$RUN" ]; then echo "O build não apareceu no GitHub. Rode de novo daqui a pouco."; exit 1; fi
echo "build $RUN: https://github.com/breroch10/nexa-ios/actions/runs/$RUN"

if ! gh run watch "$RUN" --exit-status --interval 20 >/dev/null; then
  gh run view "$RUN" --log-failed 2>/dev/null | tail -80 || true
  gh run view "$RUN" | tail -15
  exit 1
fi

mkdir -p build
rm -f build/Nexa.ipa
gh run download "$RUN" -n Nexa -D build
if ! unzip -l build/Nexa.ipa | grep -E "Payload/Nexa.app/Nexa$" >/dev/null; then echo "O .ipa veio sem o binário Payload/Nexa.app/Nexa."; exit 1; fi
ls -la build/Nexa.ipa
