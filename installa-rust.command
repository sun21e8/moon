#!/bin/bash
# Installa Rust (il compilatore del motore PDF) nella tua cartella utente, usando l'installer ufficiale rustup.
# Non chiede la password e non tocca la configurazione del Terminale: finisce tutto in ~/.cargo e ~/.rustup.
# L'esito viene scritto in rust-log.txt, accanto a questo file, così Claude può leggerlo.

cd "$(dirname "$0")" || exit 1
LOG="$PWD/rust-log.txt"

{
  echo "=== Installazione Rust avviata: $(date '+%Y-%m-%d %H:%M:%S') ==="
  if [ -x "$HOME/.cargo/bin/cargo" ]; then
    echo "Rust è già installato."
  else
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --profile minimal --no-modify-path
  fi
  "$HOME/.cargo/bin/rustc" --version && "$HOME/.cargo/bin/cargo" --version
  echo "=== ESITO: $? ==="
} 2>&1 | tee "$LOG"

echo
echo "Finito. Puoi chiudere questa finestra e dirlo a Claude."
