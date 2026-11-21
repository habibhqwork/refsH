#!/bin/zsh
# refsH: Claude Code Status Enhancer: powerline-style two-row status line
setopt null_glob
# Optional user config (never overwritten by the installer): ~/.claude/status-enhancer/config.sh
[[ -f ${SL_CONFIG:-$HOME/.claude/status-enhancer/config.sh} ]] && source "${SL_CONFIG:-$HOME/.claude/status-enhancer/config.sh}"
# Preset: SL_PRESET=minimal turns the optional segments off by default; any SL_SHOW_* you set wins.
[[ ${SL_PRESET:-full} == minimal ]] && d=0 || d=1
: ${SL_SHOW_AGE:=$d} ${SL_SHOW_VERSION:=$d} ${SL_SHOW_NET:=$d} ${SL_SHOW_DISK:=$d} ${SL_SHOW_LIMITS:=$d} ${SL_SHOW_CACHE:=$d}
: ${SL_SHOW_COST:=0}          # opt in: estimated session cost (list-price estimate; mainly useful for API users)
: ${SL_PROJECT_SEGMENTS:=0}   # local-site status (wp-env/docker) + node/php versions: off unless you opt in
# Powerline/Nerd glyphs only if a Nerd/Powerline font is installed (override: SL_GLYPHS=1|0); else plain text
if [[ ${SL_GLYPHS:-auto} == auto ]]; then
  ls ~/Library/Fonts /Library/Fonts /System/Library/Fonts 2>/dev/null | grep -qiE 'nerd|powerline|meslolgs| NF' && SL_GLYPHS=1 || SL_GLYPHS=0
fi
if [[ $SL_GLYPHS == 1 ]]; then SEP=$'\ue0b0'; OSI=$'\uf179'; BRI=$'\ue0a0'; TSEP=$'\ue0b1'; else SEP=""; OSI="mac"; BRI="⎇"; TSEP="│"; fi
TSEPC=16
in=$(cat)
j() { print -r -- "$in" | jq -r "$1 // empty"; }
dir=$(j '.workspace.current_dir // .cwd'); model=$(j '.model.display_name')
ctx=$(j '.context_window.used_percentage'); r5=$(j '.rate_limits.five_hour.used_percentage')
r5at=$(j '.rate_limits.five_hour.resets_at'); r7=$(j '.rate_limits.seven_day.used_percentage')
effort=$(j '.effort.level'); think=$(j '.thinking.enabled'); fast=$(j '.fast_mode')
cost=$(j '.cost.total_cost_usd'); warm=$(j '.prompt_cache.warm'); sname=$(j '.session_name')
d=${dir/#$HOME/\~}
col() { local p=${1%.*}; (( p < 50 )) && print 70 || { (( p < 80 )) && print 178 || print 160; } }
COLS=$({ stty size </dev/tty 2>/dev/null; } 2>/dev/null | awk '{print $2}')
if [[ -z $COLS ]]; then tt=$(ps -o tty= -p $PPID 2>/dev/null | tr -d ' '); [[ -n $tt && $tt != "??" ]] && COLS=$(stty -f /dev/$tt size 2>/dev/null | awk '{print $2}'); fi
[[ -z $COLS || $COLS -lt 20 ]] && COLS=${COLUMNS:-100}
render() {
  local out="" prev="" s fg rest bg txt w=0 sw
  for s in "$@"; do
    fg=${s%% *}; rest=${s#* }; bg=${rest%% *}; txt=${rest#* }
    sw=$(( ${#txt} + 3 ))
    if [[ -n $prev ]] && (( w + sw > COLS - 4 )); then
      out+=$(printf '\e[0m\e[38;5;%sm%s\e[0m' "$prev" "$SEP"); print -r -- "$out"; out=""; prev=""; w=0
    fi
    if [[ $prev == $bg ]]; then case $bg in 70) bg=114;; 178) bg=221;; 160) bg=203;; 238) bg=241;; 240) bg=243;; *) bg=$((bg+1));; esac; fi
    [[ -n $prev ]] && out+=$(printf '\e[38;5;%sm\e[48;5;%sm%s' "$prev" "$bg" "$SEP")
    out+=$(printf '\e[38;5;%sm\e[48;5;%sm %s ' "$fg" "$bg" "$txt"); prev=$bg; w=$(( w + sw ))
  done
  out+=$(printf '\e[0m\e[38;5;%sm%s\e[0m' "$prev" "$SEP"); print -r -- "$out"
}
trunc() { (( ${#1} > $2 )) && print -r -- "${1:0:$(( $2 - 1 ))}…" || print -r -- "$1"; }

# ---------- line 1: os, dir, git, last commit, unpushed
l1=("255 240 $OSI " "255 31 $d")
gi=(); pj=(); tl=(); nt=(); dk=()
root=""
if git -C "$dir" rev-parse --git-dir >/dev/null 2>&1; then
  root=$(git -C "$dir" rev-parse --show-toplevel)
  br=$(git -C "$dir" symbolic-ref --short HEAD 2>/dev/null || git -C "$dir" rev-parse --short HEAD)
  st=$(git -C "$dir" status --porcelain 2>/dev/null)
  staged=$(print -r -- "$st" | grep -c '^[MADRC]'); unst=$(print -r -- "$st" | grep -c '^.[MD]'); untr=$(print -r -- "$st" | grep -c '^??')
  g="$BRI $br"; a=0; b=0
  ab=$(git -C "$dir" rev-list --left-right --count '@{u}...HEAD' 2>/dev/null)
  if [[ -n $ab ]]; then b=${ab%%$'\t'*}; a=${ab##*$'\t'}; (( a )) && g+=" ⇡$a"; (( b )) && g+=" ⇣$b"; fi
  (( staged )) && g+=" +$staged"; (( unst )) && g+=" !$unst"; (( untr )) && g+=" ?$untr"
  bg=70; [[ -n $st ]] && bg=178
  gi+=("16 $bg $g")
  lc=$(git -C "$dir" log -1 --format='%cr' 2>/dev/null)
  lc=$(print -r -- "$lc" | sed -E 's/ seconds? ago/s/; s/ minutes? ago/m/; s/ hours? ago/h/; s/ days? ago/d/; s/ weeks? ago/w/; s/ months? ago/mo/; s/ years? ago/y/')
  (( SL_SHOW_AGE )) && [[ -n $lc ]] && gi+=("252 238 $lc")
  if [[ -z $ab ]] && git -C "$dir" rev-parse HEAD >/dev/null 2>&1; then gi+=("255 160 no upstream")
  elif (( a )); then gi+=("255 160 ⚠ $a unpushed"); fi
fi

# ---------- line 2: claude (model, mode, ctx, cache, limits, session)
m="$model"; [[ -n $effort ]] && m+=" · ${${${${${effort:l}/#low/L}/#medium/M}/#xhigh/xH}/#high/H}"; [[ $effort == max ]] && m="${m% max} MX"
[[ $think == true ]] && m+=" ◆think"; [[ $fast == true ]] && m+=" ⚡fast"
l2=("16 208 $m")
if [[ -n $ctx ]]; then n=$(( ${ctx%.*} / 10 )); bar=${(l:n::█:)}${(l:$((10-n))::░:)}; l2+=("255 25 ctx ${ctx%.*}%"); fi
if (( SL_SHOW_LIMITS )) && [[ -n $r5 ]]; then t=""; [[ -n $r5at ]] && t=" ↻$(date -r $r5at +%-I:%M%p)"; l2+=("255 91 5h ${r5%.*}%$t"); fi
(( SL_SHOW_COST )) && [[ -n $cost ]] && l2+=("16 220 $(printf '$%.2f' "$cost")")
(( SL_SHOW_LIMITS )) && [[ -n $r7 ]] && l2+=("255 30 7d ${r7%.*}%")
(( SL_SHOW_CACHE )) && [[ -n $warm ]] && { [[ $warm == true ]] && l2+=("16 70 cache warm") || l2+=("255 166 cache cold"); }

# ---------- line 3: mac + project
l3=()
if (( SL_SHOW_NET )); then
if route -n get default >/dev/null 2>&1; then
  net="online"; nc=94
  scutil --nc list 2>/dev/null | grep -q '(Connected)' && { net="online + VPN"; nc=62; }
  nt+=("255 $nc $net")
else nt+=("255 160 offline"); fi
fi
free=""; (( SL_SHOW_DISK )) && free=$(df -h / 2>/dev/null | awk 'NR==2{print $4}' | sed 's/i$//')
(( SL_SHOW_DISK )) && [[ -n $free ]] && dk+=("255 60 disk $free free")
base=${root:-$dir}
vs=""; sp=()
if (( SL_PROJECT_SEGMENTS )); then
[[ -f $base/package.json || -f $dir/package.json ]] && vs+=" node $(node -v 2>/dev/null | sed 's/^v//')"
if [[ -f $base/composer.json || -f $dir/composer.json || ${#${(@f)$(print -l $base/*.php(N))}} -gt 0 && -n $(print -l $base/*.php(N)) ]]; then
  vs+=" php $(php -r 'echo PHP_VERSION;' 2>/dev/null)"; fi
[[ -n $vs ]] && tl+=("16 109 ${vs# }")
if [[ -f $base/.wp-env.json || -f $base/docker-compose.yml ]]; then
  if [[ -S /var/run/docker.sock || -S $HOME/.docker/run/docker.sock ]] && [[ -n $(docker ps -q 2>/dev/null | head -1) ]]; then
    sp=("16 70 ● local site up")
  else sp=("255 166 ○ local site down"); fi
fi
fi
ver=$(grep -m1 -h -E '^[[:space:]]*(\*[[:space:]]*)?Version:' $base/style.css $base/*.php $base/*/style.css $base/themes/*/style.css 2>/dev/null | head -1 | sed -E 's/.*Version:[[:space:]]*//; s/[[:space:]]*$//')
[[ -z $ver && -f $base/package.json ]] && ver=$(jq -r '.version // empty' $base/package.json 2>/dev/null)
(( SL_SHOW_VERSION )) && [[ -n $ver ]] && pj+=("16 141 v$ver")
pj+=("${sp[@]}")

render "${l1[@]}" "${pj[@]}" "${gi[@]}" "${tl[@]}" "${dk[@]}" "${nt[@]}"; render "${l2[@]}"
