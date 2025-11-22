#!/usr/bin/env bash
set -euo pipefail

# mirror_encrypt.sh
# Recursively encrypt all files in a source directory using AES-256-CBC
# and store encrypted versions in a mirrored folder structure.

if [[ $# -ne 2 ]]; then
  echo "Usage: $0 <SOURCE_DIR> <DEST_DIR>"
  exit 2
fi

SRC="$1"
DST="$2"

# --- Validate source ---
if [[ ! -d "$SRC" ]]; then
  echo "Error: Source directory not found: $SRC"
  exit 3
fi

# --- Prompt for passphrase ---
read -rs -p "Enter encryption passphrase: " PASS1
echo
read -rs -p "Confirm passphrase: " PASS2
echo
if [[ "$PASS1" != "$PASS2" || -z "$PASS1" ]]; then
  echo "Passphrases do not match or are empty. Aborting."
  exit 4
fi
PASSWORD="$PASS1"
unset PASS1 PASS2

# --- Ensure destination directory exists ---
mkdir -p "$DST"

# --- OpenSSL parameters ---
# -pbkdf2: modern key derivation
# -iter 200000: increases brute-force cost
OPENSSL_ARGS=(-aes-256-cbc -pbkdf2 -iter 200000 -salt)

# --- Walk and encrypt files ---
find "$SRC" -type f -print0 | while IFS= read -r -d '' srcfile; do
  relpath="${srcfile#$SRC/}"
  if [[ "$relpath" == "$srcfile" ]]; then
    relpath="$(basename "$srcfile")"
  fi

  target_dir="$DST/$(dirname "$relpath")"
  mkdir -p "$target_dir"
  target_file="$target_dir/$(basename "$relpath").enc"

  if [[ -e "$target_file" ]]; then
    echo "Skipping (already exists): $relpath"
    continue
  fi

  echo -n "Encrypting: $relpath ... "

  # Perform encryption; password passed through stdin to avoid showing in process list
  if printf "%s" "$PASSWORD" | openssl enc "${OPENSSL_ARGS[@]}" -in "$srcfile" -out "$target_file" -pass stdin >/dev/null 2>&1; then
    chmod 600 "$target_file"
    echo "done"
  else
    rm -f "$target_file" || true
    echo "FAILED"
  fi
done

echo
echo "✅ Encryption complete. Encrypted files stored under: $DST"
echo
echo "Notes:"
echo "- Uses AES-256-CBC with PBKDF2 (200k iterations) and random salt per file."
echo "- Originals are untouched — delete or shred them manually if needed."
