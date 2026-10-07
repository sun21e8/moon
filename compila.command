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
  BUILT="$BUILD/Build/Products/Debug/Moon.app"
  pkill -x Moon 2>/dev/null && sleep 1

  # Mette l'app in Applicazioni, così si apre da Launchpad, Spotlight o dal Dock come tutte le altre.
  DEST="/Applications"
  [ -w "$DEST" ] || DEST="$HOME/Applications"
  mkdir -p "$DEST"
  INSTALLED="$DEST/Moon.app"

  # Sostituisce solo una copia precedente di questa stessa app, mai un'altra app che si chiami Moon.
  OWNER=""
  if [ -d "$INSTALLED" ]; then
    OWNER=$(/usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" "$INSTALLED/Contents/Info.plist" 2>/dev/null)
  fi

  if [ -d "$INSTALLED" ] && [ "$OWNER" != "local.moon.Moon" ]; then
    echo "In $DEST c'è già un'altra app chiamata Moon: non la tocco e apro quella appena compilata." | tee -a "$LOG"
    open "$BUILT"
  elif rm -rf "$INSTALLED" && ditto "$BUILT" "$INSTALLED"; then
    echo "Fatto. Moon è installata in $DEST." | tee -a "$LOG"
    open "$INSTALLED"
  else
    echo "Non sono riuscita a copiarla in $DEST: apro quella appena compilata." | tee -a "$LOG"
    open "$BUILT"
  fi
else
  echo "La compilazione non è riuscita. Dillo a Claude: gli errori sono in build-log.txt."
fi
