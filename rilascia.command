#!/bin/bash
# Prepara Moon per chi la vuole scaricare: la compila in versione definitiva (Release)
# e la comprime in dist/Moon-<versione>.zip, da allegare a una release su GitHub.
# L'esito finisce in build-log.txt, accanto a questo file, così Claude può leggerlo.

cd "$(dirname "$0")" || exit 1
LOG="$PWD/build-log.txt"
# Fuori da Documenti: i file di compilazione sono pesanti e non devono finire su iCloud.
BUILD="$HOME/Library/Caches/Moon-build"

if [ -d "/Applications/Xcode.app/Contents/Developer" ]; then
  export DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer"
fi

{
  echo "=== Rilascio avviato: $(date '+%Y-%m-%d %H:%M:%S') ==="
  sw_vers
  xcodebuild -version
  echo
} > "$LOG" 2>&1

echo "Compilo la versione da distribuire…"
xcodebuild -project Moon.xcodeproj -scheme Moon -configuration Release \
  -destination 'platform=macOS,arch=arm64' -derivedDataPath "$BUILD" build >> "$LOG" 2>&1
STATUS=$?

if [ $STATUS -eq 0 ]; then
  APP="$BUILD/Build/Products/Release/Moon.app"
  VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$APP/Contents/Info.plist")
  mkdir -p dist
  ZIP="dist/Moon-$VERSION.zip"
  ditto -c -k --sequesterRsrc --keepParent "$APP" "$ZIP" >> "$LOG" 2>&1
  STATUS=$?
  {
    echo "Pacchetto: $ZIP"
    ls -l "$ZIP"
    lipo -archs "$APP/Contents/MacOS/Moon"
    codesign -dv "$APP" 2>&1 | head -6
  } >> "$LOG" 2>&1
fi
echo "=== ESITO: $STATUS ===" >> "$LOG"

if [ $STATUS -eq 0 ]; then
  echo "Fatto: $ZIP"
  open dist
else
  echo "Non è riuscito. Dillo a Claude: gli errori sono in build-log.txt."
fi
