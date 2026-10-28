#!/bin/bash
# Claude Code status line (Tokyo Night colors).
# It runs every couple of seconds (refreshInterval), so it is kept cheap:
# one jq call, one stty call, everything else in plain bash.
export LC_ALL=C.UTF-8   # so ${#var} counts characters, not bytes

fields=$(jq -r '
  def pct100: if . == null then "" else (. * 100 + 0.5 | floor) end;
  (.context_window.total_input_tokens // 0) as $u
  | (.context_window.context_window_size // 0) as $m
  | [ .model.display_name // "", .effort.level // "",
      (.workspace.current_dir // .cwd // ""), $u, $m,
      (if $m > 0 then ($u * 100 / $m | pct100) else "" end),
      (.rate_limits.five_hour.used_percentage | pct100),
      (.rate_limits.seven_day.used_percentage | pct100) ]
  | map(tostring) | join("\u001f")')
IFS=$'\x1f' read -r model effort dir used max ctx five week <<< "$fields"

# Tokyo Night palette (truecolor)
R=$'\e[0m'; CY=$'\e[38;2;125;207;255m'; GR=$'\e[38;2;158;206;106m'; YE=$'\e[38;2;224;175;104m'
RD=$'\e[38;2;247;118;142m'; MG=$'\e[38;2;187;154;247m'; BL=$'\e[38;2;122;162;247m'; DIM=$'\e[38;2;86;95;137m'
EMPTY=$'\e[38;2;59;66;97m'; EMPTY_BG=$'\e[48;2;59;66;97m'
PARTIAL=(" " "▏" "▎" "▍" "▌" "▋" "▊" "▉")

# Percentages below are "p100": percent times 100, as integers (12.34% -> 1234).

# color by percentage: green < 50, yellow < 80, red otherwise
pc() { if (( $1 < 5000 )); then col=$GR; elif (( $1 < 8000 )); then col=$YE; else col=$RD; fi; }

# bar <p100> <width>: filled cells in color, empty cells dark gray, 1/8-cell precision
bar() {
  local p=$1 w=$2 e full rem i
  (( p < 0 )) && p=0; (( p > 10000 )) && p=10000
  pc "$p"
  (( e = (p * w * 8 + 5000) / 10000, full = e / 8, rem = e % 8 ))
  b=""
  for (( i = 0; i < w; i++ )); do
    if (( i < full )); then b+="$col█$R"
    elif (( i == full && rem > 0 )); then b+="$col$EMPTY_BG${PARTIAL[rem]}$R"
    else b+="$EMPTY█$R"; fi
  done
}

# 1234 -> 1k, 1234567 -> 1.2M
fmt() {
  local n=$1 t
  if (( n >= 1000000 )); then (( t = (n + 50000) / 100000 )); f="$(( t / 10 )).$(( t % 10 ))M"
  elif (( n >= 1000 )); then f="$(( (n + 500) / 1000 ))k"
  else f="$n"; fi
}

# --- Terminal width (so the line adapts when the phone is rotated) ---
# Order: STATUSLINE_WIDTH override, the terminal Claude Code runs in, $COLUMNS, 80.
cols="${STATUSLINE_WIDTH:-}"
if [ -z "$cols" ]; then
  # We run through a pipe, and under proot (Termux) /dev/tty doesn't work.
  # Walk up the parent processes to the first one attached to a terminal,
  # and read its size through /proc/<pid>/fd/0.
  pid=$PPID
  for _ in 1 2 3 4 5; do
    case "$pid" in ''|0|1) break ;; esac
    if [[ -c /proc/$pid/fd/0 ]]; then
      size=$(stty -F "/proc/$pid/fd/0" size 2>/dev/null); cols=${size#* }
      break
    fi
    read -r -a st < "/proc/$pid/stat" 2>/dev/null || break
    pid=${st[3]}
  done
fi
[ -z "$cols" ] && cols="${COLUMNS:-80}"
case "$cols" in ''|*[!0-9]*) cols=80 ;; esac
# Claude Code pads the status line a little; keep a small margin.
(( width = cols - 4, width < 20 && (width = 20) ))

# Narrow screen (portrait phone): shorter context bar
cbar=10; (( width < 50 )) && cbar=6

# --- Sections ---
# add <text with colors> <visible text>: the visible text is only used to
# measure width (stripping color codes in bash is slow).
parts=(); plens=()
add() { parts+=("$1"); plens+=("${#2}"); }

if [ -n "$model" ]; then
  m="${CY}◆ ${model}${R}"; mp="◆ $model"
  [ -n "$effort" ] && { m+=" ${DIM}(${effort})${R}"; mp+=" ($effort)"; }
  add "$m" "$mp"
fi
if [ -n "$ctx" ]; then
  fmt "$used"; u=$f; fmt "$max"
  bar "$ctx" "$cbar"; printf -v pad '%*s' "$cbar" ''
  add "$b ${DIM}$u/$f${R}" "$pad $u/$f"
fi
# Nerd Font glyphs (U+F07B folder, U+E0A0 git branch); change these two if your font lacks them
ICON_DIR=$''; ICON_BRANCH=$''
if [ -n "$dir" ]; then
  add "${BL}${ICON_DIR} ${dir##*/}${R}" "$ICON_DIR ${dir##*/}"
  # git branch without running git: find .git and read HEAD
  d=$dir; head=""
  while [ -n "$d" ]; do
    if [ -d "$d/.git" ]; then read -r head < "$d/.git/HEAD"; break
    elif [ -f "$d/.git" ]; then  # worktree/submodule: ".git" file points to the git dir
      read -r _ g < "$d/.git"; [[ $g != /* ]] && g="$d/$g"
      read -r head < "$g/HEAD"; break
    fi
    [ "$d" = / ] && break
    d=${d%/*}; d=${d:-/}
  done 2>/dev/null
  if [ -n "$head" ]; then
    case "$head" in ref:*) branch=${head#ref: refs/heads/} ;; *) branch=${head:0:7} ;; esac
    add "${MG}${ICON_BRANCH} ${branch}${R}" "$ICON_BRANCH $branch"
  fi
fi
# 5h and 7d stay together as one section, so they always wrap as a unit
lim=""; limp=""
if [ -n "$five" ]; then
  bar "$five" 5; pct="$(( (five + 50) / 100 ))%"
  lim="${DIM}5h${R} $b ${DIM}$pct${R}"; limp="5h ----- $pct"
fi
if [ -n "$week" ]; then
  bar "$week" 5; pct="$(( (week + 50) / 100 ))%"
  lim="${lim:+$lim  }${DIM}7d${R} $b ${DIM}$pct${R}"; limp="${limp:+$limp  }7d ----- $pct"
fi
[ -n "$lim" ] && add "$lim" "$limp"

# --- Greedy wrap: keep sections on one line while they fit, otherwise start a new line ---
sep=" ${DIM}|${R} "
out=""; line=""; len=0
for i in "${!parts[@]}"; do
  p=${parts[i]}; pl=${plens[i]}
  if [ -z "$line" ]; then
    line=$p; len=$pl
  elif (( len + 3 + pl <= width )); then
    line+="$sep$p"; (( len += 3 + pl ))
  else
    out+="${out:+$'\n'}$line"; line=$p; len=$pl
  fi
done
[ -n "$line" ] && out+="${out:+$'\n'}$line"
printf '%s' "$out"
