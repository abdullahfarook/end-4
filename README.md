# end-4 customizations

Personal tweaks on top of the illogical-impulse (end-4) Hyprland + Quickshell dotfiles.
This repo is the source of truth; `install.sh` in each folder applies it to the live config.

| Folder | What it does | Applies to |
|---|---|---|
| `super-tab/` | ALT+Tab goes to next workspace and shows the overview; releasing ALT closes it; SUPER+click on previews works | `~/.config/hypr/custom/` (keybinds.lua + scripts) |
| `dolphin-menu/` | Dolphin right-click: "Open in Claude" (kitty + claude) and "Open in VS Code" on folders | `~/.local/share/kio/servicemenus/` |
| `ai-sidebar/` | Optional left sidebar backend: native Intelligence panel, or kitty running Claude Code / Codex (Settings → Services → AI) | `~/.config/quickshell/ii/` (Config + Settings patch), `~/.config/hypr/custom/` (script + SUPER+A/B/O) |
| `fan-control/` | Bar performance button opens a click popup: power profile + Acer fan Auto/Max/Manual with CPU/GPU sliders; saved and re-applied after login/resume | `~/.config/quickshell/ii/` (patch), `~/.config/hypr/custom/` (scripts), system service (one-time sudo) |
| `cpu-info/` | CPU Speed (avg GHz) and Temp (package °C) rows in the bar's resources popup | `~/.config/quickshell/ii/` (ResourceUsage + ResourcesPopup patch) |
| `widgets/` | "Frequent apps" in the launcher (patch + saved copies) | `~/.config/quickshell/ii/` |

## Workflow: change, back up, apply, push

1. Edit the files **in this repo**, not in `~/.config` (installs overwrite the live copies).
2. Run the folder's `./install.sh`. It backs up what it replaces to `~/backups/<name>/<timestamp>/` (for `super-tab/`, back up first by hand: `mkdir -p ~/backups/super-tab/$(date +%Y%m%d-%H%M%S)` and copy `~/.config/hypr/custom/keybinds.lua` and `super-tab*.sh` into it).
3. Reload: Hyprland reloads Lua config automatically (else `hyprctl reload`). Restart the shell after QML changes: `qs -c ii kill; nohup qs -c ii >/dev/null 2>&1 & disown`.
4. Test, then commit and `git push` (remote `origin`, branch `master`).

Installers are idempotent: keybind snippets live between `-- >>> name >>>` / `-- <<< name <<<` markers and are replaced in place.

## super-tab internals

- Hyprland here uses the **Lua config**. Legacy dispatch syntax fails; use e.g. `hyprctl dispatch 'hl.dsp.focus({ workspace = "e+1" })'`.
- `super-tab.sh`: sets a flag file, enters the `super-tab` submap, goes to the next workspace, opens the overview (`qs -c ii ipc call search open`) if the `quickshell:overview` layer is absent.
- `super-tab-release.sh`: on ALT release (only if the flag exists) resets the submap, waits 0.15s so the shell's own release handler runs first, then closes the overview.
- The submap exists because `SUPER+mouse:272` is bound to window-move, which swallows clicks on overview previews while SUPER is held (SUPER+click on previews). Inside the submap that bind is absent. Side effect: other shortcuts defined outside the submap are inactive until ALT is released.
- The upstream `SUPER + Tab` bind (shell overview toggle) is left at its default; don't edit the upstream file.

## Reset and rollback

- `./reset.sh`: removes all customizations from the live config (stock illogical-impulse); the repo is untouched. Backs up to `~/backups/reset/<timestamp>/`.
- `./rollback.sh`: runs `reset.sh`, reverts the last commit (`git revert`, history kept), then re-runs every folder's `install.sh`. Needs a clean working tree; keeps your AI sidebar backend choice.
