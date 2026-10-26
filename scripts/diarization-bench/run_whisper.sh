#!/bin/zsh
# Sortie standard par segments avec horodatage des jetons (-ojf) : pas de -ml/-sow,
# qui dupliquait du texte sur ces enregistrements.
for m in IS1009a ES2004a TS3003a EN2002a; do
  start=$(date +%s)
  whisper-cli -m models/ggml-large-v3.bin -f ami/$m.Array1-01.wav -l en -t 8 -fa -mc 0 -ojf -of whisper_$m > whisper_$m.log 2>&1
  echo "$m fini en $(( $(date +%s) - start )) s" >> whisper_progress.txt
done
echo TOUT_FINI >> whisper_progress.txt
