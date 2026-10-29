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
COMP_DIR="${XDG_DATA_HOME:-$HOME/.local/share}"
# Settings that "share settings" links from ~/.claude. .claude.json (the login) never is.
CONFIG_ITEMS="settings.json CLAUDE.md commands skills agents plugins themes statusline-command.sh"

# Command templates, shown whenever a command is used wrongly.
tmpl() {
  case "$1" in
    add)        echo "$0 add NAME" ;;
    edit)       echo "$0 edit NAME" ;;
    rm)         echo "$0 rm NAME" ;;
    list)       echo "$0 list" ;;
    completion) echo "$0 completion bash|zsh" ;;
  esac
}

usage() {
  cat <<EOF
Commands:
  $(tmpl add)
      create the command claude-NAME
  $(tmpl edit)
      change what NAME shares with other accounts
  $(tmpl rm)
      remove claude-NAME
  $(tmpl list)
      accounts, login state, what each shares
  $(tmpl completion)
      install tab completion
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
    shared) fail "$1" "'shared' is reserved" ;;
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

# yn QUESTION: 0 for y, 1 for n. There is no default: only y or n is accepted.
yn() {
  printf '%s [y/n] ' "$1"
  while read -r ans; do
    case "$ans" in y|yes) return 0 ;; n|no) return 1 ;; esac
    printf 'Please answer y or n: '
  done
  echo; die "no answer given"
}

need_terminal() { [ -t 0 ] || fail "$1" "this command asks questions and needs a terminal"; }

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

# Ask both sharing questions for the account in $1 and apply the answers.
ask_sharing() {
  if yn "Share conversations with other accounts? (continue a chat on another account; the chat is then sent to it)"
  then sessions_on "$1"; else sessions_off "$1"; fi
  if yn "Share settings from ~/.claude? (theme, skills, plugins, CLAUDE.md; n = this account keeps its own)"
  then config_on "$1"; else config_off "$1"; fi
}

cmd_add() {
  [ $# -eq 1 ] || fail add "expected exactly one NAME, got $#"
  name="$1"; check_name add "$name"; need_terminal add
  cmd="$BIN/claude-$name"; dir="$(adir "$name")"
  if [ -e "$cmd" ] && [ "$(sed -n 2p "$cmd")" != "$MARK" ]; then
    die "$cmd already exists and was not created by this script"
  fi
  [ -e "$cmd" ] && die "claude-$name already exists (change it with: $(tmpl edit | sed "s/NAME/$name/"))"

  mkdir -p "$BIN" "$dir"
  printf '#!/bin/sh\n%s\nCLAUDE_CONFIG_DIR="%s" exec claude "$@"\n' "$MARK" "$dir" > "$cmd"
  chmod +x "$cmd"
  ask_sharing "$dir"

  echo "Added: claude-$name"
  case ":$PATH:" in *":$BIN:"*) ;; *) echo "Note: $BIN is not in your PATH; add it to use the command." ;; esac
  echo "Next: cd into your project, run claude-$name, then /login."
}

cmd_edit() {
  [ $# -eq 1 ] || fail edit "expected exactly one NAME, got $#"
  check_name edit "$1"; need_terminal edit
  has_account "$1" || fail edit "no account '$1' (see: $(tmpl list))"
  ask_sharing "$(adir "$1")"
  echo "Updated: claude-$1"
}

cmd_rm() {
  [ $# -eq 1 ] || fail rm "expected exactly one NAME, got $#"
  check_name rm "$1"; need_terminal rm
  has_account "$1" || fail rm "no account '$1' (see: $(tmpl list))"
  if yn "Also delete $(adir "$1") (its login and settings)? Shared conversations stay."
  then del=1; else del=0; fi
  rm -f "$BIN/claude-$1"
  echo "Removed: claude-$1"
  if [ $del = 1 ]; then rm -rf "$(adir "$1")"; echo "Deleted: $(adir "$1")"
  else echo "Kept: $(adir "$1")"; fi
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
}

# Completion scripts use shell builtins only (no subprocess), so Tab stays instant.
# Account names come from the ~/.claude-* directory names.
print_bash_comp() {
  cat <<'EOF'
_claude_accounts() {
  local cur=${COMP_WORDS[COMP_CWORD]} w="" a d n
  if [[ $COMP_CWORD == 1 ]]; then
    w="add edit rm list completion"
  elif [[ $COMP_CWORD == 2 ]]; then
    case ${COMP_WORDS[1]} in
      completion) w="bash zsh" ;;
      edit|rm)
        for d in "$HOME"/.claude-*/; do
          n=${d%/}; n=${n##*/.claude-}
          [[ $n != shared && $n != "*" ]] && w="$w $n"
        done ;;
    esac
  fi
  COMPREPLY=()
  for a in $w; do [[ $a == "$cur"* ]] && COMPREPLY+=("$a"); done
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
  case $CURRENT in
    2) compadd add edit rm list completion ;;
    3) case $words[2] in
         completion) compadd bash zsh ;;
         edit|rm)
           for d in ~/.claude-*(N/); do
             n=${d:t}; n=${n#.claude-}
             [[ $n == shared ]] || acc+=($n)
           done
           compadd -a acc ;;
       esac ;;
  esac
}
_claude_accounts "$@"
EOF
}

cmd_completion() {
  [ $# -eq 1 ] || fail completion "expected bash or zsh, got $# argument(s)"
  case "$1" in
    bash) file="$COMP_DIR/bash-completion/completions/claude-accounts.sh" ;;
    zsh) file="$COMP_DIR/zsh/site-functions/_claude-accounts.sh" ;;
    *) fail completion "expected bash or zsh (got '$1')" ;;
  esac
  mkdir -p "$(dirname "$file")"
  "print_${1}_comp" > "$file"
  echo "Installed: $file (delete that file to remove it)"
  if [ "$1" = bash ]; then
    echo "Open a new shell. Needs the bash-completion package; without it, add to ~/.bashrc:  . $file"
  else
    echo "Add to ~/.zshrc before compinit:  fpath=($(dirname "$file") \$fpath)"
  fi
}

[ $# -ge 1 ] || { usage; exit 2; }
cmd="$1"; shift
case "$cmd" in
  add) cmd_add "$@" ;;
  edit) cmd_edit "$@" ;;
  rm) cmd_rm "$@" ;;
  list) cmd_list "$@" ;;
  completion) cmd_completion "$@" ;;
  -h|--help|help) usage ;;
  *) fail all "unknown command '$cmd'" ;;
esac
