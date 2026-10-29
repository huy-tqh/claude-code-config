# claude-code-config

My Claude Code setup: a TokyoNight Storm theme and a status line.

## Files

| Path | What it is |
|------|------------|
| `themes/tokyonight.json` | Custom Claude Code theme based on the dark theme, using Tokyo Night Storm colors. Diff colors come from a reference screenshot. |
| `statusline-command.sh` | Status line script: model and effort, context tokens, folder, git branch, and 5h/7d rate-limit bars. |
| `settings.json` | Claude Code settings that select the custom theme and the status line script. |
| `claude-accounts.sh` | Adds one command per Claude Code account (`claude-work`, `claude-personal`, ...), optionally sharing conversations between them. |

## Install

1. Copy the files into `~/.claude/`:

   ```bash
   mkdir -p ~/.claude/themes
   cp themes/tokyonight.json ~/.claude/themes/
   cp statusline-command.sh ~/.claude/
   cp settings.json ~/.claude/settings.json   # or merge the keys you need
   ```

2. Make sure your terminal supports truecolor. Add this to your shell rc file, then open a new shell:

   ```bash
   export COLORTERM=truecolor
   ```

3. Restart Claude Code, or run `/theme` and choose `tokyonight`.

## Requirements

- `jq`, used by the status line script.
- A Nerd Font in your terminal. The folder and branch icons (`U+F07B`, `U+E0A0`) won't render otherwise.

## Phone / narrow terminals (Termux)

The status line measures the terminal width each time it redraws. When everything doesn't fit on one line (for example a phone in portrait mode), it wraps onto extra lines instead of getting cut off, and below 50 columns the context bar gets shorter. Rotate back to landscape and it goes back to one line. `settings.json` sets `refreshInterval: 2`, so the status line redraws within a couple of seconds after you rotate, even when nothing else is happening. Claude Code has no resize event for the status line, so it polls. To keep that cheap, the script starts only two programs per run (`jq` and `stty`) and does everything else in bash. It reads the git branch from `.git/HEAD` directly instead of running `git`.

Under proot (Termux), the script reads the width from the terminal Claude Code itself runs in (`/proc/<pid>/fd`), because `/dev/tty` isn't available there.

If the width is detected wrong, set it yourself in `settings.json`:

```json
"statusLine": { "type": "command", "command": "STATUSLINE_WIDTH=45 bash ~/.claude/statusline-command.sh" }
```

## Multiple accounts

Use several Claude Code accounts (for example work and personal) on one machine, each with its own login. `claude-accounts.sh` is plain `sh`: run it with `sh claude-accounts.sh ...` or `./claude-accounts.sh ...`.

Five commands, all take at most one name:

| Command | What it does |
|---------|--------------|
| `add NAME` | Create the command `claude-NAME`. |
| `edit NAME` | Change what `NAME` shares with other accounts. |
| `rm NAME` | Remove `claude-NAME`. |
| `list` | Accounts, login state, and what each one shares. |
| `completion bash\|zsh` | Install tab completion. |

Run it with no arguments to see them. A wrong or missing argument stops with an error and the correct template; the script never guesses a value. For example:

```
$ ./claude-accounts.sh add
error: expected exactly one NAME, got 0
usage: ./claude-accounts.sh add NAME
```

### 1. Add accounts

```bash
./claude-accounts.sh add work
./claude-accounts.sh add personal
```

Each `add` creates a command `claude-<name>` in `~/.local/bin` and a config dir `~/.claude-<name>`. Add as many as you like. If `~/.local/bin` isn't in your `PATH`, the script says so. The name can't be `shared`.

`add` asks two questions about that account. Each needs an explicit `y` or `n`; Enter alone isn't accepted. These commands need a terminal because of the questions.

| Question | `y` means | Why you might want it |
|----------|-----------|-----------------------|
| Share conversations? | The account's `projects/` points to `~/.claude-shared/projects`, so it sees the same conversation history as every other account that answered `y`. | Continue a conversation on another account with `-c`. |
| Share settings? | `settings.json`, `CLAUDE.md`, `commands`, `skills`, `agents`, `plugins`, `themes` and `statusline-command.sh` are linked from `~/.claude`. | Same theme, skills and plugins everywhere. Answer `n` for an account that needs different ones. |

`.claude.json` holds the login and is never shared. To change an answer later, run `edit NAME`; it asks the same two questions. `n` gives the account a real copy of what it shared, so nothing is lost. `y` on settings keeps any file the account already has of its own and only links what is missing. Old directories that get replaced are kept as `<name>.bak-<timestamp>`.

### 2. Log in, once per account

```bash
claude-work        # then type /login and sign in with the work account
claude-personal    # then type /login and sign in with the personal account
```

### 3. Use them

Use `claude-work` or `claude-personal` anywhere you would use `claude`. Same flags, same behavior; the only difference is which account it uses.

```bash
cd ~/my-project
claude-work              # work on this project with the work account
```

When the work account runs out of quota and both accounts share conversations, continue the same conversation on the other account. Run it in the same folder:

```bash
claude-personal -c            # continue the latest conversation in this folder
claude-personal --resume      # or pick one from a list
```

### Tab completion

```bash
./claude-accounts.sh completion bash    # or: zsh
```

Open a new shell, then press Tab after `./claude-accounts.sh` for commands and account names. The completion uses only shell built-ins, with no subprocess and no call to the script, so it is instant, and bash loads it only the first time you press Tab. To remove it, delete the file the command prints.

- bash needs the `bash-completion` package, which is already installed on most Linux distributions (`brew install bash-completion@2` on macOS). Without it, add `. <file>` to `~/.bashrc`; the command prints the line.
- zsh needs the install directory in `fpath` before `compinit` in `~/.zshrc`; the command prints the line to add.

### Things to know

- `rm NAME` asks whether to also delete `~/.claude-NAME` (login and settings). Shared conversations are never deleted.
- Continuing a conversation on another account sends the whole conversation to that account. Don't share conversations between a work account and a personal one if the code or data is restricted.
- Conversations are stored per folder, so continue from the same folder.
- Don't run the same conversation in two terminals at once.
- The first message after switching accounts may use more quota, because the prompt cache has to be rebuilt.
- Sharing uses symlinks, so it needs Linux, macOS, WSL or Termux. On Windows Git Bash, enable Developer Mode and set `MSYS=winsymlinks:nativestrict`; otherwise the script stops and leaves the folders as they were.
- Paths can be moved with `CLAUDE_ACCOUNTS_BIN` (commands, default `~/.local/bin`) and `CLAUDE_SHARED_DIR` (shared conversations, default `~/.claude-shared`). Set them the same way every time you run the script.

## Notes

- Claude Code's built-in syntax highlighting for code blocks isn't controlled by the theme file, so code blocks keep their default colors.
- The unchanged lines in a diff use the terminal background. The theme file can't set that color.
