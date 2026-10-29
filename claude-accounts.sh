#!/usr/bin/env bash
# Use several Claude Code accounts side by side.
#
#   claude-accounts.sh add work      create the command "claude-work"
#   claude-accounts.sh add personal  create the command "claude-personal"
#   claude-accounts.sh rm work       remove it
#   claude-accounts.sh               list accounts
#   claude-accounts.sh share on|off  share sessions and settings between accounts
#
# Each account is a config dir (~/.claude-NAME) plus a small command in
# ~/.local/bin that sets CLAUDE_CONFIG_DIR. Nothing to source, no shell rc edits.
# Sharing is asked once, on the first "add", and is off unless you say yes.
# When it is on, "claude-personal -c" continues the conversation of "claude-work".
#
# Env: CLAUDE_ACCOUNTS_BIN (default ~/.local/bin), CLAUDE_SHARED_DIR (default ~/.claude-shared)

set -u

BIN="${CLAUDE_ACCOUNTS_BIN:-$HOME/.local/bin}"
SHARED="${CLAUDE_SHARED_DIR:-$HOME/.claude-shared}"
FLAG="$SHARED/share"
MARK="# claude-accounts"
# Config shared from ~/.claude when sharing is on. .claude.json (the login) never is.
CONFIG_ITEMS=(settings.json CLAUDE.md commands skills agents plugins themes statusline-command.sh)

die() { echo "error: $*" >&2; exit 1; }
adir() { echo "$HOME/.claude-$1"; }
sharing() { [ "$(cat "$FLAG" 2>/dev/null)" = on ]; }

check_name() {
  [[ "$1" =~ ^[a-z0-9][a-z0-9_-]*$ ]] || die "name must be lowercase letters, digits, - or _ (got '$1')"
}

# Names of accounts, from the commands we created.
names() {
  local f
  for f in "$BIN"/claude-*; do
    [ -f "$f" ] && sed -n 2p "$f" | grep -qx "$MARK" && basename "$f" | sed 's/^claude-//'
  done
}

# link TARGET LINK: make LINK a symlink to TARGET, keeping what LINK held.
link() {
  local target="$1" link="$2" bak=""
  [ "$(readlink "$link" 2>/dev/null)" = "$target" ] && return 0
  if [ -e "$link" ] || [ -L "$link" ]; then
    if [ -d "$link" ] && [ ! -L "$link" ]; then
      mkdir -p "$target"; cp -an "$link"/. "$target"/ 2>/dev/null
    elif [ ! -e "$target" ]; then
      cp -aL "$link" "$target"
    fi
    bak="$link.bak-$(date +%Y%m%d%H%M%S)"
    mv "$link" "$bak"
  fi
  if ! ln -s "$target" "$link" 2>/dev/null || [ ! -L "$link" ]; then
    rm -rf "$link"; [ -n "$bak" ] && mv "$bak" "$link"
    die "cannot create symlink $link (Windows: use WSL, or enable Developer Mode and set MSYS=winsymlinks:nativestrict)"
  fi
}

# unlink LINK: replace a symlink with a real copy of what it points to.
unlink_copy() {
  local link="$1" tmp
  [ -L "$link" ] || return 0
  tmp="$link.tmp$$"
  cp -aL "$link" "$tmp" && rm "$link" && mv "$tmp" "$link"
}

share_account() {
  local dir="$1" item
  mkdir -p "$SHARED/projects"
  [ -d "$HOME/.claude/projects" ] && cp -an "$HOME/.claude/projects"/. "$SHARED/projects"/ 2>/dev/null
  link "$SHARED/projects" "$dir/projects"
  for item in "${CONFIG_ITEMS[@]}"; do
    [ -e "$HOME/.claude/$item" ] || continue
    # Keep an account's own config; only link what it doesn't have.
    { [ -e "$dir/$item" ] && [ ! -L "$dir/$item" ]; } && continue
    link "$HOME/.claude/$item" "$dir/$item"
  done
}

unshare_account() {
  local dir="$1" item
  unlink_copy "$dir/projects"
  for item in "${CONFIG_ITEMS[@]}"; do
    case "$(readlink "$dir/$item" 2>/dev/null)" in "$HOME/.claude/"*) unlink_copy "$dir/$item" ;; esac
  done
}

confirm() {
  local ans=""
  [ -t 0 ] && read -r -p "$1 [y/N] " ans
  [[ "$ans" =~ ^[Yy] ]]
}

cmd_add() {
  [ $# -eq 1 ] || die "usage: $0 add NAME"
  local name="$1" cmd dir
  check_name "$name"
  cmd="$BIN/claude-$name"; dir="$(adir "$name")"
  if [ -e "$cmd" ] && ! sed -n 2p "$cmd" | grep -qx "$MARK"; then
    die "$cmd already exists and was not created by this script"
  fi

  mkdir -p "$BIN" "$dir"
  printf '#!/bin/sh\n%s\nCLAUDE_CONFIG_DIR="%s" exec claude "$@"\n' "$MARK" "$dir" > "$cmd"
  chmod +x "$cmd"

  # Ask about sharing once; after that the saved answer applies to new accounts.
  if [ ! -f "$FLAG" ]; then
    echo "Share conversations and settings between your accounts?"
    echo "  Lets you continue a conversation on another account. The whole"
    echo "  conversation is then sent to that account."
    mkdir -p "$SHARED"
    if confirm "Share?"; then echo on > "$FLAG"; else echo off > "$FLAG"; fi
  fi
  sharing && share_account "$dir"

  echo "Added: claude-$name"
  case ":$PATH:" in *":$BIN:"*) ;; *) echo "Note: $BIN is not in your PATH; add it to use the command." ;; esac
  echo "Next: run claude-$name and /login."
}

cmd_rm() {
  [ $# -eq 1 ] || die "usage: $0 rm NAME"
  local name="$1" dir
  check_name "$name"
  dir="$(adir "$name")"
  names | grep -qx "$name" || die "no account '$name'"
  rm -f "$BIN/claude-$name"
  echo "Removed: claude-$name"
  if [ -d "$dir" ] && confirm "Also delete $dir (login and settings)? Shared sessions stay."; then
    rm -rf "$dir"
  fi
}

cmd_share() {
  local mode="${1:-}" n
  case "$mode" in
    on)
      mkdir -p "$SHARED"; echo on > "$FLAG"
      for n in $(names); do share_account "$(adir "$n")"; done ;;
    off)
      [ -d "$SHARED" ] && echo off > "$FLAG"
      for n in $(names); do unshare_account "$(adir "$n")"; done ;;
    *) die "usage: $0 share on|off" ;;
  esac
  echo "Sharing: $mode"
}

cmd_list() {
  local n found=0 login
  for n in $(names); do
    found=1
    login="not logged in"; [ -f "$(adir "$n")/.claude.json" ] && login="logged in"
    printf 'claude-%-12s %s\n' "$n" "$login"
  done
  if [ $found = 0 ]; then
    echo "No accounts yet. Add one: $0 add work"
  else
    echo "Sharing: $(cat "$FLAG" 2>/dev/null || echo off)    Add: $0 add NAME"
  fi
}

case "${1:-}" in
  add) shift; cmd_add "$@" ;;
  rm|remove) shift; cmd_rm "$@" ;;
  share) shift; cmd_share "$@" ;;
  ""|ls|list) cmd_list ;;
  -h|--help|help) sed -n '2,14p' "$0" | sed 's/^# \{0,1\}//' ;;
  *) die "unknown command '$1' (try: add, rm, share, or no argument)" ;;
esac
