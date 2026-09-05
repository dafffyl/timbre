#!/usr/bin/env bash
# Fait échouer le build si KeyboardExtension importe un package local
# autre que TimbreCore/TimbreSecurity (contrainte C2 : budget mémoire du
# clavier trop serré pour tolérer une dépendance non maîtrisée).
set -euo pipefail

ALLOWED=("TimbreCore" "TimbreSecurity")
LOCAL_PACKAGES=("TimbreCore" "TimbreSecurity" "TimbreAudio" "TimbreTranscription" "TimbreDiarization" "TimbreUI")

violations=0

while IFS= read -r file; do
  imports=$(grep -oE '^import [A-Za-z0-9_]+' "$file" | awk '{print $2}' || true)
  for imp in $imports; do
    for pkg in "${LOCAL_PACKAGES[@]}"; do
      if [ "$imp" = "$pkg" ]; then
        is_allowed=false
        for ok in "${ALLOWED[@]}"; do
          [ "$imp" = "$ok" ] && is_allowed=true
        done
        if [ "$is_allowed" = false ]; then
          echo "❌ $file importe '$imp', interdit dans KeyboardExtension"
          violations=$((violations + 1))
        fi
      fi
    done
  done
done < <(find KeyboardExtension -name "*.swift")

if [ "$violations" -gt 0 ]; then
  echo ""
  echo "$violations violation(s) de la règle de dépendance du clavier."
  echo "KeyboardExtension ne doit importer que TimbreCore et TimbreSecurity."
  exit 1
fi

echo "✅ Règle de dépendance respectée."
