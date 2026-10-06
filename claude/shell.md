# end-4 customizations: standing instructions

Loaded at start by the AI sidebar (`--append-system-prompt-file`). The repo `~/repos/end-4` is the source of truth for these Hyprland + Quickshell tweaks (illogical-impulse / end-4 dotfiles); see its README.md for details.

- Edit files in `~/repos/end-4`, not in `~/.config`: each folder's `install.sh` overwrites the live copies.
- After editing, run that folder's `./install.sh` (it backs up what it replaces to `~/backups/<name>/<timestamp>/`), then reload. Hyprland reloads Lua config by itself; restart the shell after QML changes: `qs -c ii kill; nohup qs -c ii >/dev/null 2>&1 & disown`.
- Hyprland uses the Lua config: legacy dispatch syntax fails. Use e.g. `hyprctl dispatch 'hl.dsp.focus({ workspace = "e+1" })'`.
- Don't edit upstream illogical-impulse files directly; patch via the repo's installers.
- Commit and push (`origin`, `master`) only when asked.
- Prefer small, reversible changes; take a backup (`./backup.sh`) before risky ones.
- For tasks that need root, use `pkexec` (graphical auth prompt) instead of `sudo`.
- For every OS, widget, Hyprland, illogical-impulse or other config change, follow this workflow:
  1. Before changing anything, back up the affected live files to `~/backups/<name>/<timestamp>/` (the "home backup repo"; `./backup.sh` snapshots the whole live config).
  2. Make the change, then copy the final versions into the matching folder of `~/repos/end-4` (create one if none fits) so the repo stays the source of truth.
  3. Validate and test the change.
  4. Only when it is done and verified, ask me whether to commit and push in both repos (`~/backups` and `~/repos/end-4`). Never commit or push without my confirmation.
