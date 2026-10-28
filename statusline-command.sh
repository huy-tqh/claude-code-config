#!/bin/bash
export LC_NUMERIC=C
input=$(cat)

model=$(echo "$input" | jq -r '.model.display_name // empty')
effort=$(echo "$input" | jq -r '.effort.level // empty')
dir=$(echo "$input" | jq -r '.workspace.current_dir // .cwd // empty')
used=$(echo "$input" | jq -r '.context_window.total_input_tokens // empty')
max=$(echo "$input" | jq -r '.context_window.context_window_size // empty')
five=$(echo "$input" | jq -r '.rate_limits.five_hour.used_percentage // empty')
week=$(echo "$input" | jq -r '.rate_limits.seven_day.used_percentage // empty')

fmt() { awk -v n="$1" 'BEGIN{ if (n>=1000000) printf "%.1fM", n/1000000; else if (n>=1000) printf "%.0fk", n/1000; else printf "%d", n }'; }

# Tokyo Night palette (truecolor)
R=$'\033[0m'; CY=$'\033[38;2;125;207;255m'; GR=$'\033[38;2;158;206;106m'; YE=$'\033[38;2;224;175;104m'
RD=$'\033[38;2;247;118;142m'; MG=$'\033[38;2;187;154;247m'; BL=$'\033[38;2;122;162;247m'; DIM=$'\033[38;2;86;95;137m'

# color by percentage: green < 50, yellow < 80, red otherwise
pc() { awk -v p="$1" -v g="$GR" -v y="$YE" -v r="$RD" 'BEGIN{ if (p<50) printf "%s", g; else if (p<80) printf "%s", y; else printf "%s", r }'; }

# bar <pct> <width>: filled/empty block characters, colored by pct
bar() {
  # empty part uses the same full-block glyph in dark gray (no gap); partial cell uses gray background
  local col; col=$(pc "$1")
  awk -v p="$1" -v w="${2:-10}" -v c="$col" 'BEGIN{
    if (p<0) p=0; if (p>100) p=100;
    split("▏ ▎ ▍ ▌ ▋ ▊ ▉", pb, " ");
    e=int(p*w*8/100+0.5); full=int(e/8); rem=e%8;
    E="\033[38;2;59;66;97m"; B="\033[48;2;59;66;97m"; Z="\033[0m";
    s=""; for(i=0;i<w;i++){
      if (i<full) s = s c "█" Z;
      else if (i==full && rem>0) s = s c B pb[rem] Z;
      else s = s E "█" Z }
    printf "%s", s }'
}

# --- Terminal width (so the line adapts when the phone is rotated) ---
# Order: STATUSLINE_WIDTH override, the real tty, $COLUMNS, then 80.
cols="${STATUSLINE_WIDTH:-}"
[ -z "$cols" ] && cols=$( { stty size </dev/tty; } 2>/dev/null | awk '{print $2}')
[ -z "$cols" ] && cols=$( { tput cols </dev/tty; } 2>/dev/null)
if [ -z "$cols" ]; then
  # no tty of our own: ask the terminal that Claude Code (our parent) runs in
  ptty=$(ps -o tty= -p "$PPID" 2>/dev/null | tr -d ' ')
  case "$ptty" in ''|'?') ;; *) cols=$( { stty -F "/dev/$ptty" size; } 2>/dev/null | awk '{print $2}') ;; esac
fi
[ -z "$cols" ] && cols="${COLUMNS:-80}"
case "$cols" in ''|*[!0-9]*) cols=80 ;; esac
# Claude Code pads the status line a little; keep a small margin.
width=$(( cols - 4 )); [ "$width" -lt 20 ] && width=20

# Narrow screen (portrait phone): shorter context bar
cbar=10; [ "$width" -lt 50 ] && cbar=6

parts=()
if [ -n "$model" ]; then
  m="${CY}◆ ${model}${R}"; [ -n "$effort" ] && m="$m ${DIM}(${effort})${R}"
  parts+=("$m")
fi
if [ -n "$max" ]; then
  cp=$(awk -v u="${used:-0}" -v m="$max" 'BEGIN{ printf "%.4f", (m>0 ? u*100/m : 0) }')
  parts+=("$(pc "$cp")$(bar "$cp" "$cbar")${R} ${DIM}$(fmt "${used:-0}")/$(fmt "$max")${R}")
fi
# Nerd Font glyphs (U+F07B folder, U+E0A0 git branch); change these two if your font lacks them
ICON_DIR=$''; ICON_BRANCH=$''
[ -n "$dir" ] && parts+=("${BL}${ICON_DIR} ${dir##*/}${R}")
if [ -n "$dir" ]; then
  branch=$(git -C "$dir" --no-optional-locks symbolic-ref --short HEAD 2>/dev/null || git -C "$dir" --no-optional-locks rev-parse --short HEAD 2>/dev/null)
  [ -n "$branch" ] && parts+=("${MG}${ICON_BRANCH} ${branch}${R}")
fi
# 5h and 7d stay together as one section, so they always wrap as a unit
lim=""
if [ -n "$five" ]; then f=$(printf '%.0f' "$five"); lim="${DIM}5h${R} $(pc "$five")$(bar "$five" 5)${R} ${DIM}${f}%${R}"; fi
if [ -n "$week" ]; then w=$(printf '%.0f' "$week"); lim="${lim:+$lim  }${DIM}7d${R} $(pc "$week")$(bar "$week" 5)${R} ${DIM}${w}%${R}"; fi
[ -n "$lim" ] && parts+=("$lim")

# visible width: drop color codes, then count UTF-8 characters (not bytes)
vlen() { printf '%s' "$1" | sed $'s/\033\\[[0-9;]*m//g' | LC_ALL=C tr -d '\200-\277' | wc -c | tr -d ' '; }

# Greedy wrap: put parts on one line while they fit, otherwise start a new line.
sep=" ${DIM}|${R} "
out=""; line=""; len=0
for p in "${parts[@]}"; do
  pl=$(vlen "$p")
  if [ -z "$line" ]; then
    line="$p"; len=$pl
  elif [ $(( len + 3 + pl )) -le "$width" ]; then
    line="$line$sep$p"; len=$(( len + 3 + pl ))
  else
    out="${out:+$out$'\n'}$line"; line="$p"; len=$pl
  fi
done
[ -n "$line" ] && out="${out:+$out$'\n'}$line"
printf '%s' "$out"
