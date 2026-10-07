#!/bin/bash
# Compila Moon e, se va tutto bene, la apre.
# Tutto quello che succede finisce in build-log.txt, accanto a questo file, così Claude può leggerlo.

cd "$(dirname "$0")" || exit 1
LOG="$PWD/build-log.txt"
# Fuori da Documenti: i file di compilazione sono pesanti e non devono finire su iCloud.
BUILD="$HOME/Library/Caches/Moon-build"

if [ -d "/Applications/Xcode.app/Contents/Developer" ]; then
  export DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer"
fi

{
  echo "=== Compilazione avviata: $(date '+%Y-%m-%d %H:%M:%S') ==="
  sw_vers
  echo "Architettura: $(uname -m)"
  xcodebuild -version
  echo
} > "$LOG" 2>&1

echo "Compilo Moon… la prima volta può volerci un minuto o due."
xcodebuild -project Moon.xcodeproj -scheme Moon -configuration Debug \
  -destination 'platform=macOS,arch=arm64' -derivedDataPath "$BUILD" build >> "$LOG" 2>&1
STATUS=$?
echo "=== ESITO: $STATUS ===" >> "$LOG"

if [ $STATUS -eq 0 ]; then
  echo "Fatto. Apro l'app."
  pkill -x Moon 2>/dev/null && sleep 1
  open "$BUILD/Build/Products/Debug/Moon.app"
else
  echo "La compilazione non è riuscita. Dillo a Claude: gli errori sono in build-log.txt."
fi
