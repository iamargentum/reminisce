#!/usr/bin/env bash
set -euo pipefail

# mirror_encrypt.sh
# Usage: ./mirror_encrypt.sh /path/to/source /path/to/destination
# Requires: openssl or gpg installed. Will prefer openssl aes-256-gcm if available.

if [[ $# -ne 2 ]]; then
  echo "Usage: $0 <SOURCE_DIR> <DEST_DIR>"
  exit 2
fi

SRC="$1"
DST="$2"

# Basic sanity checks
if [[ ! -d "$SRC" ]]; then
  echo "Source directory does not exist or is not a directory: $SRC"
  exit 3
fi

# Read passphrase securely (no echo). Ask twice to confirm.
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

# Check for openssl support for aes-256-gcm
OPENSSL_CMD=""
if command -v openssl >/dev/null 2>&1; then
  # check cipher availability (works on modern openssl)
  if openssl list -cipher-algorithms 2>/dev/null | grep -qi 'aes-256-gcm'; then
    OPENSSL_CMD="openssl"
  else
    # older openssl may still accept enc -aes-256-gcm; try a quick supported test
    if openssl enc -help 2>&1 | grep -qi 'aes-256-gcm'; then
      OPENSSL_CMD="openssl"
    fi
  fi
fi

GPG_CMD=""
if command -v gpg >/dev/null 2>&1; then
  GPG_CMD="gpg"
fi

if [[ -z "$OPENSSL_CMD" && -z "$GPG_CMD" ]]; then
  echo "Error: neither OpenSSL (with AES-256-GCM) nor GPG found on PATH. Install one and retry."
  exit 5
fi

# Create destination directory if needed
mkdir -p "$DST"

# Configure openssl parameters (if used)
# -pbkdf2 and -iter increase resistance to brute-force on passphrase; iterations can be adjusted.
OPENSSL_PBKDF2="-pbkdf2 -iter 200000"

# Walk files using find. Handle spaces/newlines in names.
# We encrypt regular files only (not symlinks, device files). Hidden files included.
find "$SRC" -type f -print0 | while IFS= read -r -d '' srcfile; do
  # Compute relative path and target path
  relpath="${srcfile#$SRC/}"  # remove "$SRC/" prefix (if srcfile == $SRC/foo)
  # If srcfile equals SRC (possible if SRC ends without slash?), fallback:
  if [[ "$relpath" == "$srcfile" ]]; then
    relpath="$(basename "$srcfile")"
  fi

  target_dir="$DST/$(dirname "$relpath")"
  mkdir -p "$target_dir"

  target_file="$target_dir/$(basename "$relpath").enc"

  # Skip if target already exists (avoid double encrypt). You can change behavior if you like.
  if [[ -e "$target_file" ]]; then
    echo "Skipping (exists): $relpath -> $(realpath --relative-to="$(pwd)" "$target_file")"
    continue
  fi

  echo -n "Encrypting: $relpath -> ${target_file} ... "

  if [[ -n "$OPENSSL_CMD" ]]; then
    # Use OpenSSL AES-256-GCM (authenticated). -salt ensures salt header for pbkdf2.
    # Note: We pass the passphrase via stdin to avoid showing it in process list.
    # The output file contains OpenSSL's salt header and GCM tag handled by openssl enc.
    if printf "%s" "$PASSWORD" | openssl enc -aes-256-gcm $OPENSSL_PBKDF2 -salt -in "$srcfile" -out "$target_file" -pass stdin >/dev/null 2>&1; then
      chmod 600 "$target_file"
      echo "done (openssl aes-256-gcm)"
    else
      rm -f "$target_file" || true
      echo "FAILED (openssl)"
    fi
  else
    # Fallback to gpg symmetric AES256
    # --batch and --yes ensure noninteractive; passphrase passed on fd 0 using --passphrase-fd 0
    if printf "%s" "$PASSWORD" | gpg --symmetric --cipher-algo AES256 --batch --yes --passphrase-fd 0 -o "$target_file" "$srcfile" >/dev/null 2>&1; then
      chmod 600 "$target_file"
      echo "done (gpg AES256)"
    else
      rm -f "$target_file" || true
      echo "FAILED (gpg)"
    fi
  fi
done

echo "Encryption complete. Encrypted files stored under: $DST"
echo "Notes:"
echo "- Originals were NOT deleted. Verify and securely delete originals yourself if desired."
echo "- Use a strong passphrase or consider using a keyfile stored securely."
