#!/bin/sh
# Use several Claude Code accounts side by side.
#
#   ./claude-accounts.sh add work              create the command "claude-work"
#   ./claude-accounts.sh add personal          create the command "claude-personal"
#   ./claude-accounts.sh                       list accounts and what they share
#   ./claude-accounts.sh rm work               remove an account
#   ./claude-accounts.sh share sessions on     share conversations between accounts
#   ./claude-accounts.sh share config off work stop sharing settings for "work" only
#
# Each account is a config dir (~/.claude-NAME) plus a small command in
# ~/.local/bin that sets CLAUDE_CONFIG_DIR. Nothing to source, no shell rc edits.
# Run it with sh or directly; it needs no bash.
#
# Env: CLAUDE_ACCOUNTS_BIN (default ~/.local/bin), CLAUDE_SHARED_DIR (default ~/.claude-shared)

BIN="${CLAUDE_ACCOUNTS_BIN:-$HOME/.local/bin}"
SHARED="${CLAUDE_SHARED_DIR:-$HOME/.claude-shared}"
MARK="# claude-accounts"
# Settings that "share config" links from ~/.claude. .claude.json (the login) never is.
CONFIG_ITEMS="settings.json CLAUDE.md commands skills agents plugins themes statusline-command.sh"

die() { echo "error: $*" >&2; exit 1; }
adir() { echo "$HOME/.claude-$1"; }

check_name() {
  case "$1" in
    ""|[!a-z0-9]*|*[!a-z0-9_-]*) die "name must be lowercase letters, digits, - or _ (got '$1')" ;;
  esac
}

# Names of accounts, from the commands we created.
names() {
  for f in "$BIN"/claude-*; do
    [ -f "$f" ] || continue
    [ "$(sed -n 2p "$f")" = "$MARK" ] && basename "$f" | sed 's/^claude-//'
  done
}

has_account() { names | grep -qx "$1"; }

# Default for new accounts: "on" or "off", saved in $SHARED/<kind>.
default_of() { cat "$SHARED/$1" 2>/dev/null; }
set_default() { mkdir -p "$SHARED"; echo "$2" > "$SHARED/$1"; }

ask() {
  [ -t 0 ] || return 1
  printf '%s [y/N] ' "$1"
  read -r ans
  case "$ans" in y|Y|yes|Yes) return 0 ;; esac
  return 1
}

# link TARGET LINK: make LINK a symlink to TARGET, keeping what LINK held.
link() {
  target="$1"; lnk="$2"; bak=""
  [ "$(readlink "$lnk" 2>/dev/null)" = "$target" ] && return 0
  if [ -e "$lnk" ] || [ -L "$lnk" ]; then
    if [ -d "$lnk" ] && [ ! -L "$lnk" ]; then
      mkdir -p "$target"; cp -an "$lnk"/. "$target"/ 2>/dev/null
    fi
    bak="$lnk.bak-$(date +%Y%m%d%H%M%S)"
    mv "$lnk" "$bak"
  fi
  if ! ln -s "$target" "$lnk" 2>/dev/null || [ ! -L "$lnk" ]; then
    rm -rf "$lnk"; [ -n "$bak" ] && mv "$bak" "$lnk"
    die "cannot create symlink $lnk (Windows: use WSL, or enable Developer Mode and set MSYS=winsymlinks:nativestrict)"
  fi
}

# Replace a symlink with a real copy of what it points to.
unlink_copy() {
  [ -L "$1" ] || return 0
  tmp="$1.tmp$$"
  cp -aL "$1" "$tmp" && rm "$1" && mv "$tmp" "$1"
}

sessions_on() {
  mkdir -p "$SHARED/projects"
  [ -d "$HOME/.claude/projects" ] && cp -an "$HOME/.claude/projects"/. "$SHARED/projects"/ 2>/dev/null
  link "$SHARED/projects" "$1/projects"
}
sessions_off() { unlink_copy "$1/projects"; }

config_on() {
  for item in $CONFIG_ITEMS; do
    [ -e "$HOME/.claude/$item" ] || continue
    # Keep an account's own file; only link what it doesn't have.
    if [ -e "$1/$item" ] && [ ! -L "$1/$item" ]; then continue; fi
    link "$HOME/.claude/$item" "$1/$item"
  done
}
config_off() {
  for item in $CONFIG_ITEMS; do
    case "$(readlink "$1/$item" 2>/dev/null)" in "$HOME/.claude/"*) unlink_copy "$1/$item" ;; esac
  done
}

sessions_linked() { [ -L "$1/projects" ]; }
config_linked() {
  for item in $CONFIG_ITEMS; do
    case "$(readlink "$1/$item" 2>/dev/null)" in "$HOME/.claude/"*) return 0 ;; esac
  done
  return 1
}

cmd_add() {
  [ $# -eq 1 ] || die "usage: $0 add NAME"
  name="$1"; check_name "$name"
  cmd="$BIN/claude-$name"; dir="$(adir "$name")"
  if [ -e "$cmd" ] && [ "$(sed -n 2p "$cmd")" != "$MARK" ]; then
    die "$cmd already exists and was not created by this script"
  fi

  mkdir -p "$BIN" "$dir"
  printf '#!/bin/sh\n%s\nCLAUDE_CONFIG_DIR="%s" exec claude "$@"\n' "$MARK" "$dir" > "$cmd"
  chmod +x "$cmd"

  # Ask once per kind of sharing; the answer then applies to every new account.
  if [ -z "$(default_of sessions)" ]; then
    echo "Share conversations between accounts?"
    echo "  Lets you continue a conversation on another account (claude-$name -c)."
    echo "  The whole conversation is then sent to that account."
    if ask "Share conversations?"; then set_default sessions on; else set_default sessions off; fi
  fi
  if [ -z "$(default_of config)" ]; then
    echo "Share settings from ~/.claude with accounts?"
    echo "  Theme, skills, plugins, commands, CLAUDE.md, settings.json."
    echo "  Say no if accounts should have different ones."
    if ask "Share settings?"; then set_default config on; else set_default config off; fi
  fi
  [ "$(default_of sessions)" = on ] && sessions_on "$dir"
  [ "$(default_of config)" = on ] && config_on "$dir"

  echo "Added: claude-$name"
  case ":$PATH:" in *":$BIN:"*) ;; *) echo "Note: $BIN is not in your PATH; add it to use the command." ;; esac
  echo "Next: cd into your project, run claude-$name, then /login."
}

cmd_rm() {
  [ $# -eq 1 ] || die "usage: $0 rm NAME"
  name="$1"; check_name "$name"; has_account "$name" || die "no account '$name'"
  rm -f "$BIN/claude-$name"
  echo "Removed: claude-$name"
  if [ -d "$(adir "$name")" ] && ask "Also delete $(adir "$name") (login and settings)? Shared conversations stay."; then
    rm -rf "$(adir "$name")"
  fi
}

# share sessions|config on|off [NAME ...]
cmd_share() {
  kind="${1:-}"; mode="${2:-}"
  case "$kind" in sessions|config) ;; *) die "usage: $0 share sessions|config on|off [NAME ...]" ;; esac
  case "$mode" in on|off) ;; *) die "usage: $0 share $kind on|off [NAME ...]" ;; esac
  shift 2
  if [ $# -gt 0 ]; then
    for n in "$@"; do has_account "$n" || die "no account '$n'"; done
    targets="$*"
  else
    targets="$(names)"
    set_default "$kind" "$mode"
  fi
  for n in $targets; do "${kind}_$mode" "$(adir "$n")"; done
  echo "Sharing $kind: $mode${*:+ for $*}"
}

cmd_list() {
  found=0
  for n in $(names); do
    found=1
    dir="$(adir "$n")"
    login="not logged in"; [ -f "$dir/.claude.json" ] && login="logged in"
    s="own conversations"; sessions_linked "$dir" && s="shared conversations"
    c="own settings"; config_linked "$dir" && c="shared settings"
    printf 'claude-%-12s %-14s %-22s %s\n' "$n" "$login" "$s" "$c"
  done
  if [ $found = 0 ]; then
    echo "No accounts yet. Add one: $0 add work"
  else
    echo "Add: $0 add NAME    Remove: $0 rm NAME    Sharing: $0 share sessions|config on|off"
  fi
}

case "${1:-}" in
  add) shift; cmd_add "$@" ;;
  rm|remove) shift; cmd_rm "$@" ;;
  share) shift; cmd_share "$@" ;;
  ""|ls|list) cmd_list ;;
  -h|--help|help) sed -n '2,10p' "$0" | sed 's/^# \{0,1\}//' ;;
  *) die "unknown command '$1' (try: add, rm, share, or no argument)" ;;
esac
