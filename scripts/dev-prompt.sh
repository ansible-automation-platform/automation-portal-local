#!/bin/bash
# Interactive DEV loop after `make dev`.
#   R — make reload      (re-export changed plugins + reinstall + restart rhdh)
#   F — make reload-fe   (FE export only; browser refresh)
#   S — make stop        (tear down stack and exit)
#   Q — quit this menu   (leave stack running)
#
# Skipped when stdin is not a TTY, or DEV_PROMPT=0.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"

if [ ! -t 0 ] || [ "${DEV_PROMPT:-1}" = "0" ]; then
  exit 0
fi

# Avoid make(1) printing "Entering directory…" noise in the loop.
export MAKEFLAGS="${MAKEFLAGS:-} --no-print-directory"

# Single keypress (no Enter). Restore terminal on exit.
_restore_tty() { stty sane 2>/dev/null || true; }
trap _restore_tty EXIT INT TERM
stty -icanon -echo min 1 time 0 2>/dev/null || true

while true; do
  printf '\n\033[1mDEV loop\033[0m  '
  printf '\033[36m[R]\033[0m reload  '
  printf '\033[36m[F]\033[0m frontend  '
  printf '\033[36m[S]\033[0m stop  '
  printf '\033[36m[Q]\033[0m quit menu\n'
  printf '> '
  # One character, no Enter (-n 1). -s: don't echo the key (we print the action).
  if ! IFS= read -r -s -n 1 key; then
    echo
    echo "Leaving stack running."
    exit 0
  fi
  # Normalize: ignore lone newline/CR from an accidental Enter.
  case "$key" in
    ""|$'\n'|$'\r') printf '(press R/F/S/Q — no Enter needed)\n'; continue ;;
  esac
  printf '%s\n' "$key"

  case "$key" in
    [Rr])
      _restore_tty
      echo "→ make reload"
      if make -C "$ROOT_DIR" reload; then
        echo "Done. Hard-refresh http://localhost:7007"
      else
        echo "reload failed (exit $?) — fix and try again." >&2
      fi
      stty -icanon -echo min 1 time 0 2>/dev/null || true
      ;;
    [Ff])
      _restore_tty
      echo "→ make reload-fe"
      if make -C "$ROOT_DIR" reload-fe; then
        echo "Done. Hard-refresh http://localhost:7007"
      else
        echo "reload-fe failed (exit $?) — fix and try again." >&2
      fi
      stty -icanon -echo min 1 time 0 2>/dev/null || true
      ;;
    [Ss])
      _restore_tty
      echo "→ make stop"
      make -C "$ROOT_DIR" stop
      exit 0
      ;;
    [Qq])
      echo "Leaving stack running. Re-enter with: make dev-prompt"
      exit 0
      ;;
    *)
      echo "Unknown key — use R, F, S, or Q (no Enter)"
      ;;
  esac
done
