#!/bin/bash
# refsH Claude Code Status Enhancer: non-destructive installer.
#   - Our files live in their own folder: ~/.claude/status-enhancer/
#   - ~/.claude/settings.json : only the "statusLine" key is added, and only if none exists
#   - ~/.claude/CLAUDE.md : touched ONLY with --with-refs (one guarded import line, never rewritten)
# Flags: --dry-run    show what would happen, change nothing
#        --with-refs  also enable the optional "refs" message (re-runs the status line)
#        --no-brew    do not install jq / font with Homebrew
#        --uninstall  remove only what this installer added
set -euo pipefail

DRY=0; NOBREW=0; UNINSTALL=0; REFS=0
for a in "$@"; do case "$a" in
  --dry-run) DRY=1;; --no-brew) NOBREW=1;; --uninstall) UNINSTALL=1;; --with-refs) REFS=1;;
  -h|--help) sed -n '2,10p' "$0"; exit 0;;
  *) echo "Unknown option: $a"; exit 2;; esac; done

here="$(cd "$(dirname "$0")" && pwd)"
C="$HOME/.claude"; OURS="$C/status-enhancer"
CMD='~/.claude/status-enhancer/statusline.sh'
IMPORT='@~/.claude/status-enhancer/refs.md'
MARK='# status-enhancer (managed line, remove with install.sh --uninstall)'
say(){ echo "• $*"; }
run(){ if (( DRY )); then echo "  [dry-run] $*"; else "$@"; fi; }
die(){ echo "✗ $*" >&2; echo "  Nothing was changed." >&2; exit 1; }
real(){ python3 -c 'import os,sys;print(os.path.realpath(sys.argv[1]))' "$1" 2>/dev/null || echo "$1"; }

# ---------- preflight: nothing is touched until every check passes ----------
[[ $(uname) == Darwin || ${FORCE:-0} == 1 ]] || die "This setup is for macOS (status line uses macOS commands). Re-run with FORCE=1 to override."
[[ -n ${HOME:-} && -d $HOME ]] || die "HOME is not set."
for f in statusline.sh refs-snippet.md statusLine.json config.example.sh; do [[ -f $here/files/$f ]] || die "Missing $here/files/$f"; done
if ! command -v jq >/dev/null; then
  if (( NOBREW == 0 && DRY == 0 )) && command -v brew >/dev/null; then say "Installing jq"; brew install jq >/dev/null || die "Could not install jq."
  else die "jq is required. Install it (brew install jq) and re-run."; fi
fi
SET="$C/settings.json"; CLM="$C/CLAUDE.md"
if [[ -e $SET ]]; then
  [[ -f $(real "$SET") ]] || die "$SET is not a regular file."
  if [[ -s $SET ]]; then jq -e 'type=="object"' "$SET" >/dev/null 2>&1 || die "$SET is not valid JSON. Fix it first; I will not touch it."; fi
fi
if [[ -e $CLM && ! -f $(real "$CLM") ]]; then die "$CLM is not a regular file."; fi

# ---------- uninstall ----------
if (( UNINSTALL )); then
  if [[ -s $SET ]] && [[ $(jq -r '.statusLine.command // ""' "$SET") == "$CMD" ]]; then
    b="$SET.bak-$(date +%Y%m%d-%H%M%S)"; run cp -p "$SET" "$b"
    t=$(mktemp); jq 'del(.statusLine)' "$SET" > "$t" && jq -e . "$t" >/dev/null && { run cp "$t" "$(real "$SET")"; say "Removed statusLine from settings.json (backup: $b)"; }; rm -f "$t"
  else say "settings.json statusLine is not ours: left alone"; fi
  if [[ -f $CLM ]] && grep -qxF "$IMPORT" "$CLM"; then
    b="$CLM.bak-$(date +%Y%m%d-%H%M%S)"; run cp -p "$CLM" "$b"
    t=$(mktemp); grep -vxF -e "$IMPORT" -e "$MARK" "$CLM" > "$t" || true; run cp "$t" "$(real "$CLM")"; rm -f "$t"; say "Removed import line from CLAUDE.md (backup: $b)"
  fi
  if [[ -d $OURS ]]; then
    if [[ -f $OURS/config.sh ]] && ! cmp -s "$OURS/config.sh" "$here/files/config.example.sh"; then
      cb="$C/status-enhancer-config.bak-$(date +%Y%m%d-%H%M%S)"; run cp -p "$OURS/config.sh" "$cb"; say "Kept your edited config at $cb"
    fi
    run rm -rf "$OURS"; say "Removed $OURS"
  fi
  echo "Done (uninstall)."; exit 0
fi

# ---------- 1. our own folder (safe to overwrite: we own it) ----------
run mkdir -p "$C"; run mkdir -p "$OURS"
run cp "$here/files/statusline.sh" "$OURS/statusline.sh"; run chmod +x "$OURS/statusline.sh"
run cp "$here/files/refs-snippet.md" "$OURS/refs.md"
[[ -e $OURS/config.sh ]] || run cp "$here/files/config.example.sh" "$OURS/config.sh"   # your config is never overwritten
say "Files placed in $OURS"

# ---------- 2. optional "refs": append one import line to CLAUDE.md ----------
if (( REFS )); then
  run mkdir -p "$C"
  if [[ -f $CLM ]] && grep -qxF "$IMPORT" "$CLM"; then
    say "CLAUDE.md already imports refs: nothing to do"
  else
    if [[ -f $CLM ]]; then b="$CLM.bak-$(date +%Y%m%d-%H%M%S)"; run cp -p "$CLM" "$b"; say "Backed up CLAUDE.md to $b"; fi
    if (( DRY )); then echo "  [dry-run] append import line to $CLM"; else
      if [[ -s $CLM && $(tail -c1 "$CLM" | wc -l) -eq 0 ]]; then printf '\n' >> "$CLM"; fi
      printf '\n%s\n%s\n' "$MARK" "$IMPORT" >> "$CLM"
    fi
    say "Added refs import line to CLAUDE.md (existing content untouched)"
  fi
else
  say "refs shortcut not enabled (add --with-refs to enable)"
fi

# ---------- 3. settings.json: add statusLine only if absent ----------
if [[ ! -s $SET ]]; then
  run cp "$here/files/statusLine.json" "$SET"; say "Created settings.json with statusLine"
else
  cur=$(jq -r '.statusLine.command // ""' "$SET")
  if [[ $cur == "$CMD" ]]; then say "settings.json statusLine already ours: nothing to do"
  elif [[ -n $(jq -r '.statusLine // empty' "$SET") ]]; then
    say "settings.json already has a different statusLine: LEFT ALONE."
    echo "  To use ours, set: \"statusLine\": {\"type\":\"command\",\"command\":\"$CMD\"}"
  else
    b="$SET.bak-$(date +%Y%m%d-%H%M%S)"; run cp -p "$SET" "$b"
    t=$(mktemp); jq -s '.[0] + .[1]' "$SET" "$here/files/statusLine.json" > "$t"
    jq -e '.statusLine.command' "$t" >/dev/null || { rm -f "$t"; die "Merge check failed; settings.json untouched."; }
    run cp "$t" "$(real "$SET")"; rm -f "$t"; say "Added statusLine to settings.json (backup: $b)"
  fi
fi

# ---------- 4. font (optional, never fatal) ----------
if (( NOBREW == 0 && DRY == 0 )) && command -v brew >/dev/null; then
  brew list --cask font-meslo-lg-nerd-font >/dev/null 2>&1 || brew install --cask font-meslo-lg-nerd-font >/dev/null 2>&1 \
    || echo "  (font install skipped; status line falls back to plain text)"
fi
echo "Done. Set the iTerm2 font to MesloLGS NF, then restart Claude Code."
