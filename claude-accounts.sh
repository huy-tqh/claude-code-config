#!/bin/sh
# Use several Claude Code accounts side by side. Run it with no arguments for the commands.
#
# Each account is a config dir (~/.claude-NAME) plus a small command in
# ~/.local/bin that sets CLAUDE_CONFIG_DIR. Nothing to source, no shell rc edits.
# Plain sh: run it with sh or directly.
#
# Env: CLAUDE_ACCOUNTS_BIN (default ~/.local/bin), CLAUDE_SHARED_DIR (default ~/.claude-shared)

BIN="${CLAUDE_ACCOUNTS_BIN:-$HOME/.local/bin}"
SHARED="${CLAUDE_SHARED_DIR:-$HOME/.claude-shared}"
MARK="# claude-accounts"
BASH_COMP="${XDG_DATA_HOME:-$HOME/.local/share}/bash-completion/completions/claude-accounts.sh"
ZSH_COMP="${XDG_DATA_HOME:-$HOME/.local/share}/zsh/site-functions/_claude-accounts.sh"
# Settings that "share config" links from ~/.claude. .claude.json (the login) never is.
CONFIG_ITEMS="settings.json CLAUDE.md commands skills agents plugins themes statusline-command.sh"

# Command templates, shown whenever a command is used wrongly.
tmpl() {
  case "$1" in
    add)        echo "$0 add NAME" ;;
    rm)         echo "$0 rm NAME keep|delete" ;;
    share)      echo "$0 share sessions|config on|off all|NAME [NAME ...]" ;;
    list)       echo "$0 list" ;;
    completion) echo "$0 completion install|uninstall|print bash|zsh" ;;
  esac
}

usage() {
  cat <<EOF
Commands:
  $(tmpl add)
      create the command claude-NAME (then run it and /login)
  $(tmpl rm)
      remove claude-NAME; keep or delete its config dir ~/.claude-NAME
  $(tmpl share)
      sessions = conversation history, config = theme/skills/plugins/settings;
      "all" or the accounts to change
  $(tmpl list)
      accounts, login state, what each shares
  $(tmpl completion)
      tab completion
EOF
}

die() { echo "error: $*" >&2; exit 1; }

# fail COMMAND MESSAGE: the message, then the correct template.
fail() {
  echo "error: $2" >&2
  if [ "$1" = all ]; then usage >&2; else echo "usage: $(tmpl "$1")" >&2; fi
  exit 2
}

adir() { echo "$HOME/.claude-$1"; }

check_name() { # check_name COMMAND NAME
  case "$2" in
    ""|[!a-z0-9]*|*[!a-z0-9_-]*) fail "$1" "name must be lowercase letters, digits, - or _ (got '$2')" ;;
    shared|all) fail "$1" "'$2' is reserved" ;;
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

# Whether new accounts share each kind: "on" or "off", saved in $SHARED/<kind>. Empty = not chosen yet.
default_of() { cat "$SHARED/$1" 2>/dev/null; }
set_default() { mkdir -p "$SHARED"; echo "$2" > "$SHARED/$1"; }

# yn QUESTION: 0 for y, 1 for n, 2 when there is no terminal to ask.
yn() {
  [ -t 0 ] || return 2
  while :; do
    printf '%s [y/n] ' "$1"
    read -r ans || return 2
    case "$ans" in y|yes) return 0 ;; n|no) return 1 ;; esac
    echo "Please answer y or n."
  done
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

# Ask once per kind (conversations, settings); the answer applies to every later account.
choose_default() { # choose_default KIND TITLE DETAIL
  [ -n "$(default_of "$1")" ] && return 0
  echo "$2"; echo "$3"
  yn "Share?"
  case $? in
    0) set_default "$1" on ;;
    1) set_default "$1" off ;;
    *) echo "error: not set whether new accounts share $1, and there is no terminal to ask." >&2
       echo "Choose first: $0 share $1 on|off all" >&2
       exit 2 ;;
  esac
}

cmd_add() {
  [ $# -eq 1 ] || fail add "expected exactly one NAME, got $#"
  name="$1"; check_name add "$name"
  cmd="$BIN/claude-$name"; dir="$(adir "$name")"
  if [ -e "$cmd" ] && [ "$(sed -n 2p "$cmd")" != "$MARK" ]; then
    die "$cmd already exists and was not created by this script"
  fi

  # Decide sharing before creating anything, so a refusal leaves nothing behind.
  choose_default sessions "Share conversations between accounts?" \
"  Lets you continue a conversation on another account (claude-$name -c).
  The whole conversation is then sent to that account."
  choose_default config "Share settings from ~/.claude with accounts?" \
"  Theme, skills, plugins, commands, CLAUDE.md, settings.json.
  Answer n if accounts should have different ones."

  mkdir -p "$BIN" "$dir"
  printf '#!/bin/sh\n%s\nCLAUDE_CONFIG_DIR="%s" exec claude "$@"\n' "$MARK" "$dir" > "$cmd"
  chmod +x "$cmd"
  [ "$(default_of sessions)" = on ] && sessions_on "$dir"
  [ "$(default_of config)" = on ] && config_on "$dir"

  echo "Added: claude-$name"
  case ":$PATH:" in *":$BIN:"*) ;; *) echo "Note: $BIN is not in your PATH; add it to use the command." ;; esac
  echo "Next: cd into your project, run claude-$name, then /login."
}

cmd_rm() {
  [ $# -eq 2 ] || fail rm "expected NAME and keep|delete, got $# argument(s)"
  name="$1"; mode="$2"; check_name rm "$name"
  case "$mode" in keep|delete) ;; *) fail rm "second argument must be keep or delete (got '$mode')" ;; esac
  has_account "$name" || fail rm "no account '$name' (see: $0 list)"
  rm -f "$BIN/claude-$name"
  echo "Removed: claude-$name"
  if [ "$mode" = delete ]; then
    rm -rf "$(adir "$name")"
    echo "Deleted: $(adir "$name") (shared conversations stay in $SHARED)"
  else
    echo "Kept: $(adir "$name")"
  fi
}

cmd_share() {
  [ $# -ge 3 ] || fail share "expected a kind, on|off and all|NAME, got $# argument(s)"
  kind="$1"; mode="$2"; shift 2
  case "$kind" in sessions|config) ;; *) fail share "first argument must be sessions or config (got '$kind')" ;; esac
  case "$mode" in on|off) ;; *) fail share "second argument must be on or off (got '$mode')" ;; esac
  if [ "$1" = all ]; then
    [ $# -eq 1 ] || fail share "'all' cannot be combined with account names"
    targets="$(names)"
    set_default "$kind" "$mode"
    msg="all accounts, and new ones"
  else
    for n in "$@"; do has_account "$n" || fail share "no account '$n' (see: $0 list)"; done
    targets="$*"
    msg="$*"
  fi
  for n in $targets; do "${kind}_$mode" "$(adir "$n")"; done
  echo "Sharing $kind: $mode for $msg"
}

cmd_list() {
  [ $# -eq 0 ] || fail list "takes no arguments, got $#"
  found=0
  for n in $(names); do
    found=1
    dir="$(adir "$n")"
    login="not logged in"; [ -f "$dir/.claude.json" ] && login="logged in"
    s="own conversations"; sessions_linked "$dir" && s="shared conversations"
    c="own settings"; config_linked "$dir" && c="shared settings"
    printf 'claude-%-12s %-14s %-22s %s\n' "$n" "$login" "$s" "$c"
  done
  [ $found = 1 ] || echo "No accounts yet. Add one: $(tmpl add)"
  printf 'New accounts share: conversations=%s settings=%s\n' \
    "$(default_of sessions | sed 's/^$/not chosen/')" "$(default_of config | sed 's/^$/not chosen/')"
}

# Completion scripts use shell builtins only (no subprocess), so Tab stays instant.
# Account names come from the ~/.claude-* directory names.
print_bash_comp() {
  cat <<'EOF'
_claude_accounts() {
  local cur=${COMP_WORDS[COMP_CWORD]} w="" a
  _ca_names=""
  case $COMP_CWORD in
    1) w="add rm share list completion" ;;
    2) case ${COMP_WORDS[1]} in
         share) w="sessions config" ;;
         completion) w="install uninstall print" ;;
         rm) _claude_accounts_names; w=$_ca_names ;;
       esac ;;
    3) case ${COMP_WORDS[1]} in
         share) w="on off" ;;
         rm) w="keep delete" ;;
         completion) w="bash zsh" ;;
       esac ;;
    4) if [[ ${COMP_WORDS[1]} == share ]]; then _claude_accounts_names; w="all$_ca_names"; fi ;;
    *) if [[ ${COMP_WORDS[1]} == share && ${COMP_WORDS[4]} != all ]]; then _claude_accounts_names; w=$_ca_names; fi ;;
  esac
  COMPREPLY=()
  for a in $w; do [[ $a == "$cur"* ]] && COMPREPLY+=("$a"); done
}
_claude_accounts_names() {
  local d n
  _ca_names=""
  for d in "$HOME"/.claude-*/; do
    n=${d%/}; n=${n##*/.claude-}
    [[ $n != shared && $n != "*" ]] && _ca_names="$_ca_names $n"
  done
}
complete -F _claude_accounts claude-accounts.sh
EOF
}

print_zsh_comp() {
  cat <<'EOF'
#compdef claude-accounts.sh
_claude_accounts() {
  local -a acc
  local d n
  for d in ~/.claude-*(N/); do
    n=${d:t}; n=${n#.claude-}
    [[ $n == shared ]] || acc+=($n)
  done
  case $CURRENT in
    2) compadd add rm share list completion ;;
    3) case $words[2] in
         share) compadd sessions config ;;
         completion) compadd install uninstall print ;;
         rm) compadd -a acc ;;
       esac ;;
    4) case $words[2] in
         share) compadd on off ;;
         rm) compadd keep delete ;;
         completion) compadd bash zsh ;;
       esac ;;
    5) [[ $words[2] == share ]] && compadd all $acc ;;
    *) [[ $words[2] == share && $words[5] != all ]] && compadd -a acc ;;
  esac
}
_claude_accounts "$@"
EOF
}

cmd_completion() {
  [ $# -eq 2 ] || fail completion "expected an action and a shell, got $# argument(s)"
  action="$1"; shell="$2"
  case "$shell" in
    bash) file="$BASH_COMP" ;;
    zsh) file="$ZSH_COMP" ;;
    *) fail completion "second argument must be bash or zsh (got '$shell')" ;;
  esac
  case "$action" in
    print) "print_${shell}_comp" ;;
    install)
      mkdir -p "$(dirname "$file")"
      "print_${shell}_comp" > "$file"
      echo "Installed: $file"
      if [ "$shell" = bash ]; then
        echo "Loads on demand if the bash-completion package is installed. Open a new shell, then try: $0 <Tab>"
      else
        echo "zsh needs this before compinit in ~/.zshrc:  fpath=($(dirname "$file") \$fpath)"
      fi ;;
    uninstall) rm -f "$file"; echo "Removed: $file" ;;
    *) fail completion "first argument must be install, uninstall or print (got '$action')" ;;
  esac
}

[ $# -ge 1 ] || { usage; exit 2; }
cmd="$1"; shift
case "$cmd" in
  add) cmd_add "$@" ;;
  rm) cmd_rm "$@" ;;
  share) cmd_share "$@" ;;
  list) cmd_list "$@" ;;
  completion) cmd_completion "$@" ;;
  -h|--help|help) usage ;;
  *) fail all "unknown command '$cmd'" ;;
esac
