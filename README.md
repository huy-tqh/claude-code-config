# claude-code-config

My Claude Code setup: a TokyoNight Storm theme and a status line.

## Files

| Path | What it is |
|------|------------|
| `themes/tokyonight.json` | Custom Claude Code theme based on the dark theme, using Tokyo Night Storm colors. Diff colors come from a reference screenshot. |
| `statusline-command.sh` | Status line script: model and effort, context tokens, folder, git branch, and 5h/7d rate-limit bars. |
| `settings.json` | Claude Code settings that select the custom theme and the status line script. |

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

## Notes

- Claude Code's built-in syntax highlighting for code blocks isn't controlled by the theme file, so code blocks keep their default colors.
- The unchanged lines in a diff use the terminal background. The theme file can't set that color.
