#!/usr/bin/env bash
# Rebrand Mac OS X / macOS codenames & version strings to:
#   "Samsoft OS X Beta 2.0 MARIO OS"
# - Renames files/directories (deep-first) in the target tree
# - Optional: rewrites text-file contents in place (with .bak backups)
# - Dry-run by default; use --apply to execute
#
# Requires: POSIX sh + Perl (available by default on macOS & most *nix)

set -euo pipefail
IFS=$'\n\t'

TARGET_DEFAULT='Samsoft OS X Beta 2.0 MARIO OS'
ROOT="."
APPLY=false
REWRITE=false
VERBOSE=false
TARGET="$TARGET_DEFAULT"

usage() {
  cat <<'USAGE'
Usage:
  samsoft_rebrand.sh [--root DIR] [--apply] [--rewrite-contents] [--target STRING] [--verbose]

Options:
  --root DIR            Directory to process (default: .)
  --apply               Perform changes (default: dry-run preview)
  --rewrite-contents    Also replace tokens inside text files (creates .bak)
  --target STRING       Replacement text (default: Samsoft OS X Beta 2.0 MARIO OS)
  -v, --verbose         Print skipped items and extra info
  -h, --help            Show this help

What it catches (case-insensitive):
  - macOS/OS X tokens + optional codename + optional version
  - Standalone codenames: Cheetah, Puma, Jaguar, Panther, Tiger, Leopard, Snow Leopard,
    Lion, Mountain Lion, Mavericks, Yosemite, El Capitan, Sierra, High Sierra,
    Mojave, Catalina, Big Sur, Monterey, Ventura, Sonoma, Sequoia
  - Versions when tied to OS tokens: 10.0–10.15, 11, 12, 13, 14, 15
USAGE
}

# Parse args
while [[ $# -gt 0 ]]; do
  case "$1" in
    --root) ROOT="${2:?missing DIR}"; shift 2;;
    --apply) APPLY=true; shift;;
    --rewrite-contents) REWRITE=true; shift;;
    --target) TARGET="${2:?missing STRING}"; shift 2;;
    -v|--verbose) VERBOSE=true; shift;;
    -h|--help) usage; exit 0;;
    *) echo "Unknown argument: $1"; usage; exit 64;;
  esac
done

# Preconditions
command -v perl >/dev/null 2>&1 || { echo "ERROR: perl is required on PATH"; exit 2; }
[[ -d "$ROOT" ]] || { echo "ERROR: --root '$ROOT' is not a directory"; exit 3; }

# Regex for codenames (no captures; case-insensitive in Perl)
CODENAMES='Cheetah|Puma|Jaguar|Panther|Tiger|Leopard|Snow[ -]?Leopard|Lion|Mountain[ -]?Lion|Mavericks|Yosemite|El[ -]?Capitan|Sierra|High[ -]?Sierra|Mojave|Catalina|Big[ -]?Sur|Monterey|Ventura|Sonoma|Sequoia'
export REPL="$TARGET"
export CODES="$CODENAMES"

transform_name() {
  # Reads 1 arg: a basename; writes the transformed name to stdout
  perl -CS -Mopen=locale -pe '
    BEGIN { $r=$ENV{REPL}; $codes=$ENV{CODES}; }
    # Replace phrases like: macOS Ventura 13, OS X 10.11, Mac OS X Snow Leopard 10.6, etc.
    s/\b(?:Mac\s*OS\s*X|Mac\s*OSX|MacOS\s*X|OS\s*X|mac\s*OS)\b(?:\s+(?:$codes))?(?:\s+(?:10\.\d{1,2}|11|12|13|14|15))?/$r/ig;

    # Replace any remaining standalone codenames
    s/\b(?:$codes)\b/$r/ig;

    # Collapse duplicate replacements and tidy whitespace
    s/(?:\Q$r\E[ _-]*){2,}/$r/ig;
    s/\s{2,}/ /g;
  ' <<< "$1"
}

safe_rename() {
  # 1 arg: full path
  local path="$1" dir base newbase dest n=0
  dir=$(dirname "$path")
  base=$(basename "$path")
  newbase=$(transform_name "$base")
  if [[ "$base" == "$newbase" ]]; then
    $VERBOSE && printf 'skip    %s\n' "$path"
    return 0
  fi
  dest="$dir/$newbase"
  # Avoid collisions by suffixing _N if needed
  while [[ -e "$dest" ]]; do
    n=$((n+1))
    dest="$dir/${newbase}_$n"
  done
  if $APPLY; then
    mv "$path" "$dest"
    printf 'rename  %s -> %s\n' "$path" "$dest"
  else
    printf 'plan    %s -> %s\n' "$path" "$dest"
  fi
}

is_text_file() {
  # Return 0 if likely text; 1 otherwise
  if command -v file >/dev/null 2>&1; then
    file -b --mime "$1" 2>/dev/null | grep -qiE 'text|json|xml|yaml|javascript|x-empty'
  else
    # Fallback: heuristic (skip obvious binaries)
    grep -Iq . "$1"
  fi
}

rewrite_file_contents() {
  # 1 arg: path to file
  local f="$1"
  [[ -f "$f" ]] || return 0
  if ! is_text_file "$f"; then
    $VERBOSE && printf 'skip(bin) %s\n' "$f"
    return 0
  fi
  if $APPLY; then
    perl -CS -Mopen=locale -0777 -i'.bak' -pe '
      BEGIN { $r=$ENV{REPL}; $codes=$ENV{CODES}; }
      s/\b(?:Mac\s*OS\s*X|Mac\s*OSX|MacOS\s*X|OS\s*X|mac\s*OS)\b(?:\s+(?:$codes))?(?:\s+(?:10\.\d{1,2}|11|12|13|14|15))?/$r/ig;
      s/\b(?:$codes)\b/$r/ig;
      s/(?:\Q$r\E[ _-]*){2,}/$r/ig;
    ' -- "$f"
    printf 'rewrite %s (backup: %s.bak)\n' "$f" "$f"
  else
    printf 'plan    rewrite %s\n' "$f"
  fi
}

echo "== Samsoft rebrand =="
echo "root:   $ROOT"
echo "mode:   $([ "$APPLY" = true ] && echo APPLY || echo DRY-RUN)"
echo "target: $TARGET"
$REWRITE && echo "contents: ENABLED (with .bak backups)" || echo "contents: disabled"

# Rename dirs/files (deep-first so children move before parents)
find "$ROOT" -depth -mindepth 1 -print0 |
  while IFS= read -r -d '' p; do
    safe_rename "$p"
  done

# Optional: rewrite inside text files
if $REWRITE; then
  find "$ROOT" -type f -print0 |
    while IFS= read -r -d '' f; do
      rewrite_file_contents "$f"
    done
fi

echo "== DONE =="
