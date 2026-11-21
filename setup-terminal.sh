#!/bin/bash
# setup-terminal.sh: iTerm2 + Homebrew + Oh My Zsh + Powerlevel10k, non-destructive and re-runnable.
#   - Only installs what is missing. Never reinstalls or overwrites what exists.
#   - ~/.zshrc: backed up, then only (a) ZSH_THEME line and (b) the p10k source line are touched, if needed.
#   - ~/.p10k.zsh: our config is installed ONLY if you have none (so the wizard is skipped, same look).
# Flags: --dry-run (preview, change nothing)  --yes (no confirmation prompt)
set -euo pipefail
DRY=0; YES=0
for a in "$@"; do case "$a" in --dry-run) DRY=1;; --yes) YES=1;; -h|--help) sed -n '2,8p' "$0"; exit 0;; *) echo "Unknown option: $a"; exit 2;; esac; done
here="$(cd "$(dirname "$0")" && pwd)"
say(){ echo "• $*"; }
die(){ echo "✗ $*" >&2; echo "  Nothing further was changed." >&2; exit 1; }
run(){ if (( DRY )); then echo "  [dry-run] $*"; else "$@"; fi; }
stamp(){ date +%Y%m%d-%H%M%S; }
ZRC="$HOME/.zshrc"; ZP="$HOME/.zprofile"; P10="$HOME/.p10k.zsh"
OMZ="${ZSH:-$HOME/.oh-my-zsh}"; THEME_DIR="${ZSH_CUSTOM:-$OMZ/custom}/themes/powerlevel10k"

# ---------- preflight ----------
[[ $(uname) == Darwin || ${FORCE:-0} == 1 ]] || die "macOS only (FORCE=1 to override)."
[[ -n ${HOME:-} && -d $HOME ]] || die "HOME is not set."
[[ -f $here/files/p10k.zsh ]] || die "Missing files/p10k.zsh"
for f in "$ZRC" "$ZP" "$P10"; do [[ ! -e $f || -f $(python3 -c 'import os,sys;print(os.path.realpath(sys.argv[1]))' "$f" 2>/dev/null || echo "$f") ]] || die "$f is not a regular file."; done
case $(uname -m) in arm64) BREW=/opt/homebrew/bin/brew;; *) BREW=/usr/local/bin/brew;; esac
[[ -x $BREW ]] || BREW=$(command -v brew || echo "$BREW")

if (( ! YES && ! DRY )); then
  echo "This will install anything missing from: Homebrew, iTerm2, font MesloLGS NF, Oh My Zsh, Powerlevel10k,"
  echo "and make small, backed-up edits to ~/.zshrc / ~/.zprofile. Existing items are skipped."
  read -r -p "Continue? [y/N] " ans; [[ $ans == [yY]* ]] || { echo "Cancelled. Nothing changed."; exit 0; }
fi
[[ ${SKIP_NETWORK:-0} == 1 ]] && say "SKIP_NETWORK=1: network installs skipped (test mode)"
net(){ if [[ ${SKIP_NETWORK:-0} == 1 ]]; then echo "  [skipped] $*"; else run "$@"; fi; }

# ---------- 1. Homebrew ----------
if [[ -x $BREW ]]; then say "Homebrew present"; else
  say "Installing Homebrew (may ask for your password)"
  net /bin/bash -c '/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"'
fi
SHELLENV='eval "$('"$BREW"' shellenv)"'
if [[ -f $ZP ]] && grep -qF "brew shellenv" "$ZP"; then say "Homebrew already on PATH in .zprofile"
else
  if (( DRY )); then echo "  [dry-run] append brew shellenv to $ZP"; else
    [[ -s $ZP && $(tail -c1 "$ZP" | wc -l) -eq 0 ]] && printf '\n' >> "$ZP"
    printf '%s\n' "$SHELLENV" >> "$ZP"; fi
  say "Added Homebrew to PATH in .zprofile"
fi
[[ -x $BREW ]] && eval "$("$BREW" shellenv)" || true

# ---------- 2. iTerm2, git, font ----------
if [[ -d /Applications/iTerm.app || -d $HOME/Applications/iTerm.app ]]; then say "iTerm2 present"; else say "Installing iTerm2"; net brew install --cask iterm2; fi
if command -v git >/dev/null; then say "git present"; else say "Installing git"; net brew install git; fi
if ls "$HOME/Library/Fonts" /Library/Fonts 2>/dev/null | grep -qi 'MesloLGS NF'; then say "Font MesloLGS NF present"
else say "Installing font"; net brew install --cask font-meslo-lg-nerd-font || echo "  (font install failed: install MesloLGS NF manually)"; fi

# ---------- 3. Oh My Zsh (never replaces an existing .zshrc) ----------
if [[ -d $OMZ ]]; then say "Oh My Zsh present"; else
  say "Installing Oh My Zsh"
  net env RUNZSH=no CHSH=no KEEP_ZSHRC=yes /bin/bash -c 'sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"'
fi

# ---------- 4. Powerlevel10k theme ----------
if [[ -d $THEME_DIR ]]; then say "Powerlevel10k present"; else
  say "Installing Powerlevel10k"; net git clone --depth=1 https://github.com/romkatv/powerlevel10k.git "$THEME_DIR"
fi

# ---------- 5. ~/.zshrc: theme line + source line only ----------
if [[ -f $ZRC ]]; then
  need_theme=1; grep -qE '^[[:space:]]*ZSH_THEME="powerlevel10k/powerlevel10k"' "$ZRC" && need_theme=0
  need_src=1;   grep -qF 'source ~/.p10k.zsh' "$ZRC" && need_src=0
  if (( need_theme || need_src )); then
    b="$ZRC.bak-$(stamp)"; run cp -p "$ZRC" "$b"; say "Backed up .zshrc to $b"
    if (( need_theme )); then
      if grep -qE '^[[:space:]]*ZSH_THEME=' "$ZRC"; then
        if (( DRY )); then echo "  [dry-run] set ZSH_THEME to powerlevel10k"; else
          t=$(mktemp); awk 'BEGIN{d=0} /^[[:space:]]*ZSH_THEME=/ && !d {print "ZSH_THEME=\"powerlevel10k/powerlevel10k\""; d=1; next} {print}' "$ZRC" > "$t" && cat "$t" > "$ZRC"; rm -f "$t"; fi
        say "Set ZSH_THEME to powerlevel10k (only that line changed)"
      else say ".zshrc has no ZSH_THEME line: add ZSH_THEME=\"powerlevel10k/powerlevel10k\" above 'source \$ZSH/oh-my-zsh.sh' yourself"; fi
    fi
    if (( need_src )); then
      if (( DRY )); then echo "  [dry-run] append p10k source line"; else
        [[ -s $ZRC && $(tail -c1 "$ZRC" | wc -l) -eq 0 ]] && printf '\n' >> "$ZRC"
        printf '\n# To customize prompt, run `p10k configure` or edit ~/.p10k.zsh.\n[[ ! -f ~/.p10k.zsh ]] || source ~/.p10k.zsh\n' >> "$ZRC"; fi
      say "Added p10k source line to .zshrc"
    fi
  else say ".zshrc already set up: nothing to do"; fi
else
  say "No ~/.zshrc yet: open a new iTerm2 tab after Oh My Zsh installs, then re-run this script"
fi

# ---------- 5b. keep the `claude` command reachable (~/.local/bin on PATH) ----------
if [[ -f $ZRC ]]; then
  if grep -qE '^[[:space:]]*export[[:space:]]+PATH=.*\.local/bin' "$ZRC"; then say "PATH already includes ~/.local/bin: claude command safe"
  else
    ls "$ZRC".bak-* >/dev/null 2>&1 || run cp -p "$ZRC" "$ZRC.bak-$(stamp)"
    if (( DRY )); then echo "  [dry-run] append ~/.local/bin PATH line to $ZRC"; else
      [[ -s $ZRC && $(tail -c1 "$ZRC" | wc -l) -eq 0 ]] && printf '\n' >> "$ZRC"
      printf '\n# Claude Code command (~/.local/bin)\nexport PATH="$HOME/.local/bin:$PATH"\n' >> "$ZRC"; fi
    say "Added ~/.local/bin to PATH in .zshrc (so 'claude' keeps working)"
  fi
fi

# ---------- 6. ~/.p10k.zsh only if you have none ----------
if [[ -e $P10 ]]; then say "~/.p10k.zsh exists: kept (run 'p10k configure' to change it)"
else run cp "$here/files/p10k.zsh" "$P10"; say "Installed our Powerlevel10k look (wizard skipped)"; fi

echo "Done. In iTerm2: Settings > Profiles > Text > Font = MesloLGS NF, then open a new tab."
