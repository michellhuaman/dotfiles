# dotfiles

My Fedora atomic desktop setup, themed with Catppuccin and managed with
[chezmoi](https://www.chezmoi.io/). One branch serves:

- **Fedora Sway Atomic** (Fedora's preconfigured sway): my main setup;
- **Fedora Silverblue**: GNOME, optionally with niri and DankMaterialShell
  next to it.

Everything is applied everywhere; a config for a program that isn't
installed (sway's on Silverblue, niri's without niri) just sits unused. Only
things that would *do* something are limited to where they belong: the
GNOME custom shortcuts and GNOME-only Flatpaks need `gnome-shell`, and the
theme script and helper scripts check what's running.

This repo is the user half of the setup. The system half (layered packages,
COPRs, third-party repos, and installing Bitwarden and chezmoi) is in
[workstation-bootstrap](https://github.com/michellhuaman/workstation-bootstrap),
whose `setup.sh` clones and applies this repo on a new machine.

The dividing line is **sudo**: everything here installs into the home folder,
so `chezmoi apply` never asks for a password.

## Layout

```
.chezmoi.toml.tmpl      per-machine settings, asked once by `chezmoi init` (Git name/email)
.chezmoiignore          what chezmoi leaves alone: this README, and DMS's generated niri files (~/.config/niri/dms)
.chezmoidata/
  packages.yaml         flatpaks (+ GNOME-only ones), Nerd Font version, mise version and checksums, systemd user units
.chezmoiexternal.toml.tmpl  downloads mise itself (pinned, checksum-verified)
.chezmoiscripts/        run by `chezmoi apply`, in number order
  run_onchange_after_20-install-flatpaks.sh.tmpl    reruns when the flatpak list changes
  run_onchange_after_25-install-cli-tools.sh.tmpl   mise install + prune; reruns when the mise config changes
  run_onchange_after_30-install-fonts.sh.tmpl       Nerd Font, bat cache
  run_onchange_after_40-enable-services.sh.tmpl     enables the user units in packages.yaml
  run_once_after_50-default-theme.sh.tmpl           dark theme on the first apply only
  run_onchange_after_55-theme-links.sh.tmpl         points the sway desktop's theme links at the current flavor
  run_onchange_after_60-gnome-shortcuts.sh.tmpl     GNOME custom shortcuts (the whole set); only where GNOME is installed
.chezmoitemplates/      the four themed configs (see "Themes" below)
dot_bash_profile, dot_bashrc
dot_gitconfig.tmpl      uses the name/email from .chezmoi.toml.tmpl
private_dot_ssh/        ~/.ssh/config: Bitwarden's agent for every host
dot_config/             ~/.config (Alacritty, bat, btop, mise, Neovim, niri, starship, tmux, systemd, ...)
  sway/config.d/        drop-ins on top of Fedora's sway config: keyboard layouts, workspaces per
                        monitor, thin borders, wallpaper, floating blueman and Bitwarden, keybindings, Catppuccin colors
  autostart/            apps started at login: Bitwarden (the SSH agent) and Brave
  waybar/config.jsonc  Fedora's waybar config plus a few module settings
  waybar, dunst, rofi, swaylock   Catppuccin for the rest of the sway desktop
dot_local/bin/          theme-toggle.sh, ddc-brightness.sh, powermenu.sh
dot_local/private_share/themes/   Adwaita-dark for GTK3 apps (Thunar), missing on Sway Atomic
dot_local/private_share/applications/nvim.desktop   Neovim in rofi and "Open With" (mise installs no app entry)
dot_local/private_share/xfce4/helpers/, dot_config/xfce4/helpers.rc   Alacritty for Thunar's "Open Terminal Here"
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
- for the four themed configs (Alacritty, starship, btop, bat) it opens their
  template in `.chezmoitemplates/` instead, which is where those configs live
  (see "Themes"). Plain `chezmoi edit` would open the wrong file for these.

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

then continue from step 2. `re-add` skips templates and the four themed
configs; for those, copy the change into the template with `edot` instead.
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
| a sway keybinding | `dot_config/sway/config.d/70-bindings.conf` (replaces Fedora's binding for the same keys) | `chezmoi apply`, then `$mod+Shift+c` (reload) |
| a GNOME custom shortcut | `.chezmoiscripts/run_onchange_after_60-gnome-shortcuts.sh.tmpl` (shortcuts made in Settings are replaced by this list) | `chezmoi apply` sets them |
| a niri keybinding | `dot_config/niri/config.kdl` | `chezmoi apply`; niri reloads it on its own |
| a CLI tool, or a newer version of one | `edot ~/.config/mise/config.toml` (exact versions; `mise outdated --bump` lists newer ones) | applied on save: installed, and anything no longer listed is pruned |
| a new mise release | `mise.version` and both `mise.sha256` lines in `.chezmoidata/packages.yaml` | `chezmoi apply` downloads and verifies it |
| a new Nerd Font release | `fonts.nerd_fonts` in `.chezmoidata/packages.yaml` | `chezmoi apply` downloads it |
| a systemd user unit | the unit in `dot_config/systemd/user/`, its name in `services.user` | `chezmoi apply` enables it |
| a script, template or anything else in the repo | `chezmoi cd`, then edit the file (e.g. `vim .chezmoidata/packages.yaml`) | `chezmoi apply`, `exit` |
| a layered RPM or COPR | not here: workstation-bootstrap's lists | re-run its `setup.sh`, then reboot |

Each of these then goes through step 2 like any other change.

## Themes

`theme-toggle.sh` (`Super+Shift+T` in sway, niri and GNOME) switches between
light and dark: it sets the desktop's color scheme (which GTK4/libadwaita apps
and Brave follow) and GTK theme, the sway desktop's theme links (see "The sway
desktop"), DankMaterialShell's mode (see "niri and DankMaterialShell"), and
the Catppuccin flavor (Latte for light, Mocha for dark) inside four configs:

| Config | Line it changes |
| --- | --- |
| `~/.config/alacritty/alacritty.toml` | `import = [".../catppuccin-mocha.toml"]` |
| `~/.config/starship.toml` | `palette = "catppuccin_mocha"` |
| `~/.config/btop/btop.conf` | `color_theme = ".../catppuccin_mocha.theme"` |
| `~/.config/bat/config` | `--theme="Catppuccin Mocha"` |

If these were plain files, every toggle would be a difference: `chezmoi diff`
would show it, `apply` would undo it, and `re-add` would commit whichever
flavor was active. So the configs are split in two:

- **`.chezmoitemplates/<name>`**: the full config, with the flavor left as a
  blank (`{{ .flavor }}`). **This is the file to edit.**
- **`dot_config/.../modify_<name>`**: a few lines that build the file. chezmoi
  passes it the current file from `~/.config`; it finds which flavor is active
  there, defaulting to `mocha` if the file doesn't exist yet, and fills it into
  the template.

The result is always your config with whatever flavor is already on disk. A
toggle never shows up in `chezmoi diff`, `apply` never undoes it, and a real
edit (say, a new font size) still goes through. A new machine starts on Mocha,
matching the dark theme `run_once_after_50-default-theme.sh.tmpl` sets.

To change one of these configs, use `edot` with its real path. It opens the
template and applies when you quit:

```bash
edot ~/.config/alacritty/alacritty.toml     # opens .chezmoitemplates/alacritty.toml
```

(`chezmoi edit` on these paths would open the `modify_` file instead, which is
not where the config is.)

Only the theme line is protected. Anything else changed in `~/.config` (btop,
for example, rewrites `btop.conf` with all its settings when it quits) shows up
in `chezmoi diff`. To keep it, copy the line into the template with `edot`.

GTK and icon themes are set by `theme-toggle.sh` and the default-theme script:
Yaru on Ubuntu, Adwaita everywhere else (Fedora included). GTK3 apps (Thunar)
need the theme named `Adwaita-dark`, which Sway Atomic doesn't ship, so
`~/.local/share/themes/Adwaita-dark` provides it.

### The sway desktop

Sway, waybar, dunst, rofi and swaylock use Catppuccin's own theme files
(copied from the catppuccin/i3, waybar, dunst, rofi and swaylock repos), one
per flavor, under each app's `themes/` folder. Each config reads a "current"
link instead of naming a flavor:

| Config | Reads |
| --- | --- |
| `~/.config/sway/config.d/80-catppuccin.conf` | `~/.config/sway/themes/catppuccin-current` |
| `~/.config/waybar/style.css` | `~/.config/waybar/themes/catppuccin-current.css` |
| `~/.config/rofi/themes/catppuccin-default.rasi` | `~/.config/rofi/themes/catppuccin-current.rasi` |
| `~/.config/dunst/dunstrc.d/80-catppuccin.conf` | is the link itself (`../themes/<flavor>.conf`); `~/.config/dunst/dunstrc` exists only so dunst reads `dunstrc.d/` |
| `~/.config/swaylock/config` | is the link itself (`themes/<flavor>.conf`) |

`theme-toggle.sh` points the links at the other flavor, reloads sway (which
restarts waybar) and stops dunst (D-Bus starts it again for the next
notification); rofi and swaylock read theirs when they start. chezmoi
tracks the theme files but not the links, so this needs no `modify_` files
and a toggle never shows up as a difference. On a new machine,
`run_onchange_after_55-theme-links.sh.tmpl` creates the links (`theme-toggle.sh
links`) for the current mode.

### niri and DankMaterialShell

On Silverblue with niri, DankMaterialShell (DMS) is the bar, launcher,
notifications and wallpaper. niri starts it (`spawn-sh-at-startup "dms run"`
in `config.kdl`), and DMS writes its own files into `~/.config/niri/dms/`
(colors, monitor settings), which `config.kdl` includes and chezmoi ignores.
DMS's settings (`~/.config/DankMaterialShell`) aren't tracked: set them in its
Settings app. `theme-toggle.sh` switches DMS to light or dark
(`dms ipc call theme light|dark`), which also regenerates niri's border colors.

## SSH and Git

Bitwarden (Flatpak) holds the SSH keys and is the SSH agent.
`~/.ssh/config` points every host at its socket, and `.bash_profile` sets
`SSH_AUTH_SOCK` to the same place, so Bitwarden must be unlocked for
`git push` and `ssh`.

- It starts at login from `~/.config/autostart/com.bitwarden.desktop.desktop`
  (Brave from the file next to it). That file is exactly what the desktop
  portal writes when Bitwarden asks to start at login: on GNOME it does, and
  replaces ours; Fedora's sway portal can't. Keep it identical, with no
  comments, or chezmoi reports a conflict after every GNOME login.
- `~/.local/share/flatpak/overrides/com.bitwarden.desktop` lets it show its
  tray icon: the Flatpak may talk to the tray but not claim the D-Bus name the
  icon needs (always `org.freedesktop.StatusNotifierItem-2-1` inside the
  sandbox).
- To run in the tray, turn on "Keep Bitwarden running in the background" in
  its settings (stored with the vault data, so not tracked here).

Git's name and email are asked once per machine by `chezmoi init`; to change
them, run `chezmoi init` again.

## CLI tools

Command-line tools (Neovim, lazygit, ripgrep, fd, bat, starship,
tree-sitter) come from [mise](https://mise.jdx.dev), not the distro, so every
machine gets the same versions whatever the distro. They're pinned in
`~/.config/mise/config.toml`, and that file is the whole set: on each change
chezmoi installs what's listed and prunes what isn't. mise puts them on `PATH`
through its shims (`~/.local/share/mise/shims`, set in `.bash_profile`), ahead
of any distro copy. `update` lists newer releases; to take one, bump the
version with `edot` and commit.

## Terminal

Alacritty is the terminal everywhere (layered by workstation-bootstrap). Each
launcher finds it its own way:

| From | How |
| --- | --- |
| `Super+Return` | sway: `$term` in `70-bindings.conf`; niri: `config.kdl`; GNOME: the custom shortcuts script |
| rofi (sway), for terminal apps such as Neovim | rofi's `-terminal alacritty` (`$menu` in `70-bindings.conf`) |
| GTK apps: GNOME's app grid, "Open With" in Files or Thunar | `xdg-terminal-exec` (layered) reads `dot_config/xdg-terminals.list`. GLib's own fallback list has no Alacritty, so without it these fail |
| Thunar's "Open Terminal Here" | Xfce's preferred terminal: `~/.config/xfce4/helpers.rc` and the helper in `~/.local/share/xfce4/helpers/` (Sway Atomic ships none) |
| Nautilus's "Open in Terminal" | ignores all of these and always opens Ptyxis |

Neovim comes from mise, which installs no app entry, so
`~/.local/share/applications/nvim.desktop` adds one (rofi, app grid, "Open
With").
