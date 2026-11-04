# dotfiles

My desktop setup, managed with [chezmoi](https://www.chezmoi.io/): stock
**Ubuntu** (GNOME), themed with Catppuccin.

`run_onchange_after_60-gnome-settings.sh.tmpl` sets GNOME's keyboard
layouts, tap to click and traditional scrolling, night light, 10 fixed
workspaces and shortcuts (Super+Return Alacritty, Super+Shift+Return
Brave, Super+Shift+T theme-toggle, Super+Shift+B monitor brightness,
Super+1-9/0 workspace 1-10, Super+Shift+1-9/0 move the window there; the
script's header lists them all).

The previous setup, Fedora Sway Atomic (sway, waybar, rofi, dunst,
swaylock, Thunar's helpers), is kept as the tag `fedora-sway-atomic`:
`git checkout fedora-sway-atomic` to look at it.

This repo is the user half of the setup. The system half (apt packages,
third-party repos and Bitwarden's polkit action) is in
[workstation-bootstrap](https://github.com/michellhuaman/workstation-bootstrap),
whose `setup.sh` clones and applies this repo on a new machine.

The dividing line is **sudo**: everything here installs into the home folder,
so `chezmoi apply` never asks for a password.

## Layout

```
.chezmoiignore          repo files that are not copied to ~ (this README)
.chezmoiremove          files earlier versions put in ~, deleted on apply
.chezmoidata/
  packages.yaml         flatpaks, Nerd Font version and checksum, systemd user units
.chezmoiscripts/        run by `chezmoi apply`, in number order
  run_onchange_after_20-install-flatpaks.sh.tmpl    reruns when the flatpak list changes
  run_onchange_after_25-install-cli-tools.sh.tmpl   mise install + prune; reruns when the mise config changes
  run_onchange_after_30-install-fonts.sh.tmpl       Nerd Font (checked against its checksum)
  run_onchange_after_40-enable-services.sh.tmpl     enables the user units in packages.yaml
  run_once_after_50-default-theme.sh.tmpl           dark theme on the first apply only
  run_onchange_after_55-theme-links.sh.tmpl         points Alacritty's theme link at the current flavor
  run_onchange_after_60-gnome-settings.sh.tmpl      Ubuntu only: GNOME keyboard, touchpad, night light, shortcuts
dot_bash_profile, dot_bashrc
dot_gitconfig           Git name, email, editor
private_dot_ssh/        ~/.ssh/config: Bitwarden's agent for every host
dot_config/             ~/.config (Alacritty, bat, btop, mise, starship, tmux, systemd, ...)
  autostart/            apps started at login: Bitwarden (the SSH agent), Brave and Claude Desktop (apt packages)
dot_local/bin/          theme-toggle.sh, ddc-brightness.sh, powermenu.sh,
                        sor-vms.sh (start the SOR VirtualBox VMs + tmux SSH panes; `keys`, `stop`),
                        random-wallpaper.sh (random light and dark GNOME wallpapers from ~/Pictures/wallpapers; daily via random-wallpaper.timer),
                        wallpaper-reject.sh (Super+Shift+W: trash the wallpaper on screen, or move it to light/ or dark/)
```

chezmoi turns source names into real ones: `dot_` becomes `.`, `private_`
means only you can read it, `executable_` makes it executable, `readonly_`
makes it read-only, and `.tmpl` means it's a template.

## Editing dotfiles

The source of truth is this repo, at `~/.local/share/chezmoi`. Files in `~`
(`~/.bashrc`, `~/.config/...`) are output: chezmoi writes them from here and
overwrites them on apply. So changes are made here, never directly in `~`.

### The workflow

**1. Edit and apply**, using the file's real path in your home folder:

```bash
edot ~/.config/alacritty/alacritty.toml
```

`edot` (an alias in `.bashrc` for `chezmoi edit --apply`) opens the source
file in `$EDITOR` and applies the change when you quit.

**2. Commit and push:**

```bash
chezmoi git -- diff                     # optional: review what you're committing
chezmoi git -- add -A && chezmoi git -- commit -m "What changed" && chezmoi git -- push
```

**3. Pull on the other machines:**

```bash
chezmoi update                          # git pull + apply
```

You can commit at any time: theme toggles never count as changes (see
"Themes"), so there's no need to switch to dark first.

### Other situations

**A change that started in `~`**, for example a tweak tested directly in
`~/.config` or a setting saved from inside an app:

```bash
chezmoi diff          # see what differs from the repo
chezmoi re-add        # copy the changed files into the repo
```

then continue from step 2. `re-add` skips templates; for those, copy the
change into the template with `edot` instead.
To throw a change away, run `chezmoi apply`, which puts the repo's version
back.

**A new file to track:**

```bash
chezmoi add ~/.config/newapp/config
```

then step 2.

**Something that isn't a single config file:**

| Change | Where | Then |
| --- | --- | --- |
| a Flatpak app | `packages.flatpak` in `.chezmoidata/packages.yaml` (the whole set: per-user apps not listed are uninstalled, their data kept) | `chezmoi apply` installs or uninstalls it |
| a keyboard shortcut | `.chezmoiscripts/run_onchange_after_60-gnome-settings.sh.tmpl` | `chezmoi apply` |
| a CLI tool | `edot ~/.config/mise/config.toml` (as `"latest"`) | applied on save: installed, and anything no longer listed is pruned |
| a new Nerd Font release | `fonts.nerd_fonts` in `.chezmoidata/packages.yaml`, and `fonts.nerd_fonts_sha256` next to it (that release's `SHA-256.txt` line for `JetBrainsMono.tar.xz`) | `chezmoi apply` downloads it and checks it |
| a systemd user unit | the unit in `dot_config/systemd/user/`, its name in `services.user` | `chezmoi apply` enables it |
| a script, template or anything else in the repo | `chezmoi cd`, then edit the file (e.g. `vim .chezmoidata/packages.yaml`) | `chezmoi apply`, `exit` |
| a system (apt) package | not here: workstation-bootstrap's lists | re-run its `setup.sh` |

Each of these then goes through step 2 like any other change.

**A new Nerd Font release, tested first**: workstation-bootstrap's `update-pins.sh`
bumps it to the latest stable release on a branch, to test in a VM before
merging. Its README, "Updating the pinned versions", has the steps.

## Themes

`theme-toggle.sh` (`Super+Shift+T`) switches between light and dark: it sets
the desktop's color scheme (which GTK4/libadwaita apps and Brave follow), the
GTK and icon themes (Ubuntu's Yaru), and Alacritty's Catppuccin flavor (Latte
for light, Mocha for dark). A new machine starts on Mocha, matching the dark
theme `run_once_after_50-default-theme.sh.tmpl` sets.

Alacritty reads `~/.config/alacritty/themes/catppuccin-current.toml`, a link
that `theme-toggle.sh` points at `catppuccin-latte.toml` or
`catppuccin-mocha.toml` (copies of catppuccin/alacritty's files), then
touches `alacritty.toml` so open windows reload. chezmoi tracks the theme
files but not the link, so a toggle never shows up as a difference. On a new
machine, `run_onchange_after_55-theme-links.sh.tmpl` creates the link
(`theme-toggle.sh links`) for the current mode.

Everything that runs inside the terminal uses its 16 ANSI colors instead of
a theme of its own, so it follows Alacritty: starship's colors are ANSI names,
bat has `--theme=ansi` and btop `color_theme = "TTY"`. btop's config is
read-only, so settings changed in its menu last only until it quits.

The wallpaper follows the theme without `theme-toggle.sh`: GNOME keeps one
wallpaper per mode (`picture-uri` for light, `picture-uri-dark` for dark) and
shows the matching one. `random-wallpaper.sh` (daily, via
`random-wallpaper.timer`) picks the light one from `~/Pictures/wallpapers/light`
and the dark one from `~/Pictures/wallpapers/dark`; a mode whose folder is
missing or empty picks from the whole folder. `Super+Shift+W`
(`wallpaper-reject.sh`) asks what to do with the wallpaper on screen: move it
to the Trash (Restore it from the Trash in Files to undo), or to `light/` or
`dark/`. When it leaves the current mode's folder, the mode gets a new one.

## SSH and Git

Bitwarden (Flatpak) holds the SSH keys and is the SSH agent.
`~/.ssh/config` points every host at its socket, and `.bash_profile` sets
`SSH_AUTH_SOCK` to the same place, so Bitwarden must be unlocked for
`git push` and `ssh`. This repo is public, so it's pulled over HTTPS
(`chezmoi update` needs no key) and pushed over SSH: `setup.sh` sets
origin's push URL to `git@github.com:...`.

- It starts at login from `~/.config/autostart/com.bitwarden.desktop.desktop`
  (Brave from the file next to it). That file is exactly what the desktop
  portal writes when Bitwarden asks to start at login (on desktops whose
  portal can, such as GNOME), so it has no
  comments: if a portal ever rewrites it, nothing changes.
- `~/.local/share/flatpak/overrides/com.bitwarden.desktop` lets it show its
  tray icon: the Flatpak may talk to the tray but not claim the D-Bus name the
  icon needs (always `org.freedesktop.StatusNotifierItem-2-1` inside the
  sandbox).
- To run in the tray, turn on "Keep Bitwarden running in the background" in
  its settings (stored with the vault data, so not tracked here).

Git's name and email are in `dot_gitconfig`, the same on every machine.

## CLI tools

Command-line tools (chezmoi itself, bat, starship) come from
[mise](https://mise.jdx.dev), not the distro, so they're newer than Ubuntu's.
mise itself is an apt package from its own repo (workstation-bootstrap),
updated with the system. They're listed in `~/.config/mise/config.toml` as
`"latest"`, and that file is the whole set: on each change chezmoi installs
what's listed and prunes what isn't. mise puts them on `PATH` through its
shims (`~/.local/share/mise/shims`, set in `.bash_profile`), ahead of any
distro copy. `update` (in `.bashrc`) upgrades them with `mise upgrade`.

## Terminal

Alacritty is the terminal (an apt package from workstation-bootstrap).
Each launcher finds it its own way:

| From | How |
| --- | --- |
| `Super+Return` | a custom shortcut in `run_onchange_after_60-gnome-settings.sh.tmpl` |
| terminal apps such as vim, from the app grid or "Open With" | `xdg-terminal-exec` (apt) reads `dot_config/xdg-terminals.list`. GLib's own fallback list has no Alacritty, so without it these fail |

vim is an apt package from workstation-bootstrap (Ubuntu's own `vim-tiny`
has no `vim` command), with Ubuntu's app entry; it's `EDITOR` (`.bash_profile`)
and Git's editor (`dot_gitconfig`). It has no config here.
