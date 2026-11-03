# dotfiles

My desktop setup, managed with [chezmoi](https://www.chezmoi.io/): stock
**Ubuntu** (GNOME), themed with Catppuccin.

`run_onchange_after_60-gnome-settings.sh.tmpl` sets GNOME's keyboard
layouts, tap to click, night light and shortcuts (Super+Return
Alacritty, Super+Shift+Return Brave, Super+Shift+T theme-toggle,
Super+Shift+B monitor brightness).

The previous setup, Fedora Sway Atomic (sway, waybar, rofi, dunst,
swaylock, Thunar's helpers), is kept as the tag `fedora-sway-atomic`:
`git checkout fedora-sway-atomic` to look at it.

This repo is the user half of the setup. The system half (apt packages,
third-party repos, and installing Bitwarden and chezmoi) is in
[workstation-bootstrap](https://github.com/michellhuaman/workstation-bootstrap),
whose `setup.sh` clones and applies this repo on a new machine.

The dividing line is **sudo**: everything here installs into the home folder,
so `chezmoi apply` never asks for a password.

## Layout

```
.chezmoiignore          repo files that are not copied to ~ (this README)
.chezmoidata/
  packages.yaml         flatpaks, Nerd Font version, systemd user units
.chezmoiscripts/        run by `chezmoi apply`, in number order
  run_onchange_after_20-install-flatpaks.sh.tmpl    reruns when the flatpak list changes
  run_onchange_after_25-install-cli-tools.sh.tmpl   mise install + prune; reruns when the mise config changes
  run_onchange_after_30-install-fonts.sh.tmpl       Nerd Font, bat cache
  run_onchange_after_40-enable-services.sh.tmpl     enables the user units in packages.yaml
  run_once_after_50-default-theme.sh.tmpl           dark theme on the first apply only
  run_onchange_after_55-theme-links.sh.tmpl         points the theme links at the current flavor
  run_onchange_after_60-gnome-settings.sh.tmpl      Ubuntu only: GNOME keyboard, touchpad, night light, shortcuts
  run_onchange_after_65-virt-manager-connection.sh  virt-manager Flatpak: connects to the host's libvirt (qemu:///system)
.chezmoitemplates/      starship.toml, the one config whose theme line is edited in place (see "Themes")
dot_bash_profile, dot_bashrc
dot_gitconfig           Git name, email, editor
private_dot_ssh/        ~/.ssh/config: Bitwarden's agent for every host
dot_config/             ~/.config (Alacritty, bat, btop, mise, Neovim, starship, tmux, systemd, ...)
  autostart/            apps started at login: Bitwarden (the SSH agent) and Brave (apt package)
dot_local/bin/          theme-toggle.sh, ddc-brightness.sh, powermenu.sh
dot_local/private_share/applications/nvim.desktop   Neovim in the app grid and "Open With" (mise installs no app entry)
```

chezmoi turns source names into real ones: `dot_` becomes `.`, `private_`
means only you can read it, `executable_` makes it executable, `.tmpl` means
it's a template, and `modify_` means a template that edits the existing file
(see "Themes").

## Editing dotfiles

The source of truth is this repo, at `~/.local/share/chezmoi`. Files in `~`
(`~/.bashrc`, `~/.config/...`) are output: chezmoi writes them from here and
overwrites them on apply. So changes are made here, never directly in `~`.

### The workflow

**1. Edit and apply**, using the file's real path in your home folder:

```bash
edot ~/.config/alacritty/alacritty.toml
```

`edot` (a function in `.bashrc`) opens the right source file in `$EDITOR` and
applies the change when you quit:

- for most files it runs `chezmoi edit --apply`;
- for `~/.config/starship.toml` it opens its template in `.chezmoitemplates/`
  instead, which is where that config lives (see "Themes"). Plain
  `chezmoi edit` would open the wrong file for it.

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

then continue from step 2. `re-add` skips templates and `starship.toml`; for
those, copy the change into the template with `edot` instead.
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
| a CLI tool, or a newer version of one | `edot ~/.config/mise/config.toml` (exact versions; `mise outdated --bump` lists newer ones) | applied on save: installed, and anything no longer listed is pruned |
| a new Nerd Font release | `fonts.nerd_fonts` in `.chezmoidata/packages.yaml` | `chezmoi apply` downloads it |
| a systemd user unit | the unit in `dot_config/systemd/user/`, its name in `services.user` | `chezmoi apply` enables it |
| a script, template or anything else in the repo | `chezmoi cd`, then edit the file (e.g. `vim .chezmoidata/packages.yaml`) | `chezmoi apply`, `exit` |
| a system (apt) package | not here: workstation-bootstrap's lists | re-run its `setup.sh` |

Each of these then goes through step 2 like any other change.

**All the pinned versions at once** (the Nerd Font, the CLI tools, the
Neovim plugins, and chezmoi in workstation-bootstrap): workstation-bootstrap's `update-pins.sh` bumps them
to the latest stable releases on a branch, to test in a VM before merging.
Its README, "Updating the pinned versions", has the steps.

## Themes

`theme-toggle.sh` (`Super+Shift+T`) switches between light and dark: it sets
the desktop's color scheme (which GTK4/libadwaita apps and Brave follow) and
GTK theme, and switches every themed app between the Catppuccin flavors
(Latte for light, Mocha for dark). A new machine starts on Mocha, matching
the dark theme `run_once_after_50-default-theme.sh.tmpl` sets.

GTK and icon themes are set by `theme-toggle.sh` and the default-theme script:
Yaru on Ubuntu, Adwaita everywhere else.

### Theme links

Most apps use Catppuccin's own theme files (copied from the catppuccin/alacritty,
btop and bat repos), one per
flavor, under each app's `themes/` folder. Each config reads a "current" link
instead of naming a flavor:

| Config | Reads |
| --- | --- |
| `~/.config/alacritty/alacritty.toml` | `~/.config/alacritty/themes/catppuccin-current.toml` |
| `~/.config/btop/btop.conf` | `~/.config/btop/themes/catppuccin_current.theme`. That's its only line, and the file is read-only, so settings changed in btop's menu last only until it quits |
| `~/.config/bat/config` | is the link itself (`config-mocha` / `config-latte`, the same apart from the theme: change both) |

`theme-toggle.sh` points the links at the other flavor and touches
`alacritty.toml`, which makes open Alacritty windows reload; btop reads its
theme when it starts, and bat its config on every run. chezmoi tracks the theme files but not the links, so the configs are
plain files you can edit directly, and a toggle never shows up as a
difference. On a new machine, `run_onchange_after_55-theme-links.sh.tmpl`
creates the links (`theme-toggle.sh links`) for the current mode.

(bat could pick a light or dark theme by itself from the terminal's
background, but inside a tmux that was started before a toggle it keeps
seeing the old color, so it uses a link too.)

### starship

starship can't include another file, so its flavor is the line
`palette = "catppuccin_mocha"` inside `~/.config/starship.toml`, which
`theme-toggle.sh` edits in place. So that a toggle doesn't show up as a
difference, the config is split in two:

- **`.chezmoitemplates/starship.toml`**: the full config, with the flavor left
  as a blank (`{{ .flavor }}`). **This is the file to edit**: `edot
  ~/.config/starship.toml` opens it and applies when you quit.
- **`dot_config/modify_starship.toml`**: a few lines that build the file.
  chezmoi passes it the current file from `~/.config`; it finds which flavor
  is active there, defaulting to `mocha` if the file doesn't exist yet, and
  fills it into the template.

(`chezmoi edit ~/.config/starship.toml` would open the `modify_` file
instead, which is not where the config is.)

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

Command-line tools (Neovim, lazygit, ripgrep, fd, bat, starship,
tree-sitter) come from [mise](https://mise.jdx.dev), not the distro, so every
machine gets the same versions. mise itself is an apt package from its own
repo (workstation-bootstrap), updated with the system. They're pinned in
`~/.config/mise/config.toml`, and that file is the whole set: on each change
chezmoi installs what's listed and prunes what isn't. mise puts them on `PATH`
through its shims (`~/.local/share/mise/shims`, set in `.bash_profile`), ahead
of any distro copy. `update` lists newer releases; to take one, bump the
version with `edot` and commit (or bump everything with workstation-bootstrap's
`update-pins.sh`).

## Terminal

Alacritty is the terminal (an apt package from workstation-bootstrap).
Each launcher finds it its own way:

| From | How |
| --- | --- |
| `Super+Return` | a custom shortcut in `run_onchange_after_60-gnome-settings.sh.tmpl` |
| terminal apps such as Neovim, from the app grid or "Open With" | `xdg-terminal-exec` (apt) reads `dot_config/xdg-terminals.list`. GLib's own fallback list has no Alacritty, so without it these fail |

Neovim comes from mise, which installs no app entry, so
`~/.local/share/applications/nvim.desktop` adds one (app grid, "Open With").
